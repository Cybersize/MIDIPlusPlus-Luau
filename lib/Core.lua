-- MIDI++ Luau core. GPL-3.0-only; see bundled LICENSE and NOTICE.md.
-- Original piano layouts/velocity curves: Zephkek/MIDIPlusPlus.
local Core = {}

local function check(condition, message)
    if not condition then error("MIDI: " .. message, 0) end
end

function Core.parse(data, limits)
    limits = limits or {}
    check(type(data) == "string", "expected a binary string")
    check(#data <= (limits.maxBytes or 16 * 1024 * 1024), "file exceeds the size limit")
    -- RIFF/RMID wraps a standard MIDI file in a little-endian data chunk.
    if data:sub(1, 4) == "RIFF" and data:sub(9, 12) == "RMID" then
        local function le32(p)
            check(p + 3 <= #data, "truncated RIFF length")
            local a, b, c, d = data:byte(p, p + 3)
            return a + b * 256 + c * 65536 + d * 16777216
        end
        local finish, p, found = le32(5) + 8, 13, nil
        check(finish <= #data, "truncated RIFF container")
        while p + 7 <= finish do
            local tag, size = data:sub(p, p + 3), le32(p + 4)
            check(p + 7 + size <= finish, "truncated RIFF chunk")
            if tag == "data" then found = data:sub(p + 8, p + 7 + size); break end
            p = p + 8 + size + size % 2
        end
        check(found ~= nil, "RMID contains no data chunk")
        data = found
    end
    local p, boundary = 1, #data
    local function take(n)
        check(n >= 0 and p + n - 1 <= boundary, "truncated data at byte " .. p)
        local result = data:sub(p, p + n - 1)
        p = p + n
        return result
    end
    local function byte()
        check(p <= boundary, "truncated event at byte " .. p)
        local result = data:byte(p)
        p = p + 1
        return result
    end
    local function u16() return byte() * 256 + byte() end
    local function u32() return byte() * 16777216 + byte() * 65536 + byte() * 256 + byte() end
    local function vlq()
        local value = 0
        for _ = 1, 4 do
            local b = byte()
            value = value * 128 + b % 128
            if b < 128 then return value end
        end
        error("MIDI: variable-length value exceeds four bytes", 0)
    end
    check(take(4) == "MThd", "missing MThd header; use a .mid/.midi file")
    local headerSize = u32()
    check(headerSize >= 6, "invalid header size")
    local format, trackCount, division = u16(), u16(), u16()
    check(format == 0 or format == 1, "only MIDI formats 0 and 1 are supported (format 2 is asynchronous)")
    check(trackCount > 0 and trackCount <= (limits.maxTracks or 256), "invalid or excessive track count")
    check(format ~= 0 or trackCount == 1, "format 0 must contain one track")
    check(division ~= 0, "zero time division")
    take(headerSize - 6)
    local ticksPerSecond = nil
    if division >= 32768 then
        local fps, subframes = 256 - math.floor(division / 256), division % 256
        check((fps == 24 or fps == 25 or fps == 29 or fps == 30) and subframes > 0, "invalid SMPTE division")
        ticksPerSecond = (fps == 29 and 30000 / 1001 or fps) * subframes
    end
    local raw, tracks, serial, parsedCount, lastTick = {}, {}, 0, 0, 0
    local function push(event)
        serial = serial + 1
        event.order = serial
        raw[#raw + 1] = event
    end
    for trackIndex = 1, trackCount do
        boundary = #data
        local tag, size = take(4), u32()
        while tag ~= "MTrk" do
            take(size)
            tag, size = take(4), u32()
        end
        local trackEnd = p + size - 1
        check(trackEnd <= #data, string.format("track %d declares %d bytes, but only %d remain (incomplete binary read)",
            trackIndex, size, #data - p + 1))
        boundary = trackEnd
        local track = { name = "Track " .. trackIndex, notes = 0, channels = {}, muted = false, solo = false }
        tracks[trackIndex] = track
        local tick, running = 0, nil
        while p <= trackEnd do
            parsedCount = parsedCount + 1
            check(parsedCount <= (limits.maxEvents or 250000), "too many events; split or simplify this MIDI")
            tick = tick + vlq()
            lastTick = math.max(lastTick, tick)
            local status = byte()
            if status < 128 then
                check(running ~= nil, "running status without a preceding channel status")
                p = p - 1
                status = running
            elseif status < 240 then
                running = status
            else
                running = nil
            end
            if status == 255 then
                local kind, length = byte(), vlq()
                local payload = take(length)
                if kind == 81 then
                    check(length == 3, "tempo event must have three bytes")
                    local a, b, c = payload:byte(1, 3)
                    local tempo = a * 65536 + b * 256 + c
                    check(tempo > 0, "tempo cannot be zero")
                    push({ kind = "tempo", tick = tick, tempo = tempo, track = trackIndex })
                elseif kind == 3 then
                    track.name = payload:gsub("[%z\1-\31\127-\255]", "?"):sub(1, 80)
                elseif kind == 47 then
                    check(length == 0, "invalid end-of-track event")
                    break
                end
            elseif status == 240 or status == 247 then
                take(vlq())
            else
                check(status >= 128 and status < 240, "unsupported system status " .. status)
                local kind, channel = math.floor(status / 16), status % 16 + 1
                local a = byte()
                local b = (kind == 12 or kind == 13) and 0 or byte()
                check(a < 128 and b < 128, "channel data byte has its status bit set")
                if kind == 8 or kind == 9 then
                    local isOn = kind == 9 and b > 0
                    if isOn then track.notes = track.notes + 1 end
                    track.channels[channel] = true
                    push({ kind = isOn and "on" or "off", tick = tick, track = trackIndex,
                        channel = channel, note = a, velocity = b })
                elseif kind == 11 and (a == 64 or a == 120 or a == 121 or a == 123) then
                    push({ kind = "cc", tick = tick, track = trackIndex, channel = channel, control = a, value = b })
                end
            end
        end
        p = trackEnd + 1
    end
    table.sort(raw, function(a, b)
        if a.tick == b.tick then return a.order < b.order end
        return a.tick < b.tick
    end)
    local tempo, previousTick, seconds = 500000, 0, 0
    local events, tempos = {}, { { time = 0, bpm = 120 } }
    for _, event in ipairs(raw) do
        local scale = ticksPerSecond and 1 / ticksPerSecond or tempo / 1000000 / division
        seconds = seconds + (event.tick - previousTick) * scale
        previousTick = event.tick
        event.time = seconds
        if event.kind == "tempo" then
            tempo = event.tempo
            tempos[#tempos + 1] = { time = seconds, bpm = 60000000 / tempo }
        else
            events[#events + 1] = event
        end
    end
    local scale = ticksPerSecond and 1 / ticksPerSecond or tempo / 1000000 / division
    return { format = format, division = division, tracks = tracks, events = events, tempos = tempos,
        duration = seconds + (lastTick - previousTick) * scale, eventCount = parsedCount }
end

function Core.decodeBase64(text)
    check(type(text) == "string", "expected base64 text")
    text = text:gsub("^data:[^,]*;base64,", ""):gsub("%s", "")
    check(#text % 4 == 0, "base64 length must be a multiple of four")
    local alphabet, lookup = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/", {}
    for i = 1, #alphabet do lookup[alphabet:sub(i, i)] = i - 1 end
    local result = {}
    for i = 1, #text, 4 do
        local a, b, c, d = text:sub(i, i), text:sub(i + 1, i + 1), text:sub(i + 2, i + 2), text:sub(i + 3, i + 3)
        check(lookup[a] ~= nil and lookup[b] ~= nil, "invalid base64 character")
        check((lookup[c] ~= nil or c == "=") and (lookup[d] ~= nil or d == "="), "invalid base64 character")
        check(not (c == "=" and d ~= "=") and ((c ~= "=" and d ~= "=") or i + 3 == #text), "invalid base64 padding")
        local value = lookup[a] * 262144 + lookup[b] * 4096 + (lookup[c] or 0) * 64 + (lookup[d] or 0)
        result[#result + 1] = string.char(math.floor(value / 65536) % 256)
        if c ~= "=" then result[#result + 1] = string.char(math.floor(value / 256) % 256) end
        if d ~= "=" then result[#result + 1] = string.char(value % 256) end
    end
    return table.concat(result)
end

-- Some executor bridges read files in Windows text mode, which can truncate
-- binary MIDI at 0x1A. A .mid.b64 sidecar carries the original bytes as ASCII.
-- Reader injection keeps this path testable without executor-specific globals.
function Core.loadFile(path, reader, limits)
    check(type(path) == "string" and #path > 0, "enter a MIDI path")
    check(type(reader) == "function", "this executor has no readfile; use URL, Base64, or Demo")
    local function parseText(text)
        check(type(text) == "string", "readfile did not return a string")
        check(#text <= 24 * 1024 * 1024, "base64 file is too large")
        return Core.parse(Core.decodeBase64(text), limits)
    end
    if path:lower():match("%.b64$") then
        return parseText(reader(path)), {path = path, binarySafe = true}
    end
    local sidecar = path .. ".b64"
    local found, encoded = pcall(reader, sidecar)
    if found and type(encoded) == "string" and #encoded > 0 then
        local ok, song = pcall(parseText, encoded)
        check(ok, "invalid .b64 sidecar; run Convert-MIDI again: " .. tostring(song))
        return song, {path = sidecar, binarySafe = true}
    end
    local data = reader(path)
    local ok, song = pcall(Core.parse, data, limits)
    check(ok, "could not load MIDI bytes. Run Convert-MIDI to create " .. path .. ".b64. Details: " .. tostring(song))
    return song, {path = path, binarySafe = false}
end

local limited = { "1", "!", "2", "@", "3", "4", "$", "5", "%", "6", "^", "7",
    "8", "*", "9", "(", "0", "q", "Q", "w", "W", "e", "E", "r",
    "t", "T", "y", "Y", "u", "i", "I", "o", "O", "p", "P", "a",
    "s", "S", "d", "D", "f", "g", "G", "h", "H", "j", "J", "k",
    "l", "L", "z", "Z", "x", "c", "C", "v", "V", "b", "B", "n", "m" }
function Core.keymap(full)
    local result = {}
    for i, key in ipairs(limited) do result[i + 35] = key end
    if full then
        local low, high = "1234567890qwert", "yuiopasdfghj"
        for i = 1, #low do result[i + 20] = "ctrl+" .. low:sub(i, i) end
        for i = 1, #high do result[i + 96] = "ctrl+" .. high:sub(i, i) end
    end
    return result
end
Core.velocityKeys = "1234567890qwertyuiopasdfghjklzxc"
Core.curves = {
    Linear = {4,8,12,16,20,24,28,32,36,40,44,48,52,56,60,64,68,72,76,80,84,88,92,96,100,104,108,112,116,120,124,127},
    Fine = {2,6,10,14,18,22,26,30,34,38,42,46,50,54,58,62,66,70,74,78,82,86,90,94,98,102,106,110,114,118,122,127},
    Soft = {1,3,5,7,10,13,16,20,24,29,34,40,46,53,60,68,76,85,94,104,114,120,123,127,127,127,127,127,127,127,127,127},
    Log = {1,2,3,5,7,10,14,19,25,32,40,49,60,72,85,99,115,127,127,127,127,127,127,127,127,127,127,127,127,127,127,127},
    Exp = {1,2,4,8,16,24,32,40,48,56,64,72,80,88,96,104,110,115,120,124,126,127,127,127,127,127,127,127,127,127,127,127},
}
function Core.velocityKey(velocity, curve)
    curve = curve or Core.curves.Linear
    local i = 1
    while i < 32 and curve[i] < velocity do i = i + 1 end
    return Core.velocityKeys:sub(i, i)
end

local Player = {}
Player.__index = Player
function Core.newPlayer(output)
    return setmetatable({ output = output or {}, song = nil, playing = false, position = 0, index = 1,
        speed = 1, transpose = 0, looped = false, skipDrums = true, fold = false, sustain = true,
        map = Core.keymap(false), minNote = 36, maxNote = 96, voices = {}, queues = {},
        pedals = {}, tails = {}, outputActive = false, nextId = 0, skipped = 0, resyncs = 0 }, Player)
end
function Player:_emit(name, ...)
    local fn = self.output[name]
    if fn then fn(...) end
end
function Player:isTrackEnabled(index)
    local track = self.song.tracks[index]
    if track.muted then return false end
    for _, other in ipairs(self.song.tracks) do
        if other.solo then return track.solo end
    end
    return true
end
function Player:_pedalDown()
    if not self.sustain then return false end
    for _, down in pairs(self.pedals) do if down then return true end end
    return false
end
function Player:_silence()
    if self.outputActive then
        for _, voice in pairs(self.voices) do self:_emit("noteOff", voice) end
        self:_emit("sustain", false)
    end
    self:_emit("panic")
    self.outputActive = false
end
function Player:_syncOutput()
    if self.outputActive then return end
    self.outputActive = true
    self:_emit("sustain", self:_pedalDown())
    local ids = {}
    for id in pairs(self.voices) do ids[#ids + 1] = id end
    for id in pairs(self.tails) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local voice = self.voices[id] or self.tails[id]
        self:_emit("noteOn", voice)
        if self.tails[id] then self:_emit("noteOff", voice) end
    end
end
function Player:_resetState()
    self.voices, self.queues, self.pedals, self.tails = {}, {}, {}, {}
    self.nextId, self.skipped = 0, 0
end
function Player:_release(voice, allowTail)
    if self.outputActive then self:_emit("noteOff", voice) end
    self.voices[voice.id] = nil
    if allowTail and self.sustain and self.pedals[voice.channel] then self.tails[voice.id] = voice end
end
function Player:_event(event)
    local queueKey = event.track .. ":" .. event.channel .. ":" .. (event.note or 0)
    if event.kind == "on" then
        if not self:isTrackEnabled(event.track) or (self.skipDrums and event.channel == 10) then return end
        local note = event.note + self.transpose
        if self.fold then
            while note < self.minNote do note = note + 12 end
            while note > self.maxNote do note = note - 12 end
        end
        local key = self.map[note]
        -- Queue placeholders preserve note-off pairing if a note is unmapped.
        local queue = self.queues[queueKey] or {}
        self.queues[queueKey] = queue
        if not key then self.skipped = self.skipped + 1; queue[#queue + 1] = false; return end
        self.nextId = self.nextId + 1
        local voice = { id = self.nextId, key = key, note = note, original = event.note,
            channel = event.channel, track = event.track, velocity = event.velocity }
        queue[#queue + 1] = voice
        self.voices[voice.id] = voice
        if self.outputActive then self:_emit("noteOn", voice) end
    elseif event.kind == "off" then
        local queue = self.queues[queueKey]
        if queue and #queue > 0 then
            local voice = table.remove(queue, 1)
            if voice then self:_release(voice, true) end
            if #queue == 0 then self.queues[queueKey] = nil end
        end
    elseif event.kind == "cc" and self:isTrackEnabled(event.track) then
        if event.control == 64 or event.control == 121 then
            self.pedals[event.channel] = event.control == 64 and event.value >= 64
            if not self.pedals[event.channel] then
                for id, voice in pairs(self.tails) do if voice.channel == event.channel then self.tails[id] = nil end end
            end
            if self.outputActive then self:_emit("sustain", self:_pedalDown()) end
        elseif event.control == 120 or event.control == 123 then
            local release = {}
            for _, voice in pairs(self.voices) do
                if voice.channel == event.channel then release[#release + 1] = voice end
            end
            for _, voice in ipairs(release) do self:_release(voice, event.control == 123) end
            for key in pairs(self.queues) do
                -- Also remove placeholders, without affecting other channels.
                local channel = tonumber(key:match("^%d+:(%d+):"))
                if channel == event.channel then self.queues[key] = nil end
            end
            if event.control == 120 then
                self.pedals[event.channel] = false
                for id, voice in pairs(self.tails) do if voice.channel == event.channel then self.tails[id] = nil end end
                if self.outputActive then self:_emit("sustain", self:_pedalDown()) end
            end
        end
    end
end
function Player:load(song)
    self:_silence()
    self.song, self.playing, self.position, self.index = song, false, 0, 1
    self.resyncs = 0
    self:_resetState()
end
function Player:seek(seconds)
    if not self.song then return end
    self:_silence()
    self:_resetState()
    self.position = math.clamp(seconds, 0, self.song.duration)
    self.index = 1
    while self.index <= #self.song.events and self.song.events[self.index].time < self.position do
        self:_event(self.song.events[self.index])
        self.index = self.index + 1
    end
    if self.playing then self:_syncOutput() end
end
function Player:play()
    if not self.song then return false, "Load a MIDI first" end
    if self.position >= self.song.duration then self:seek(0) end
    self.playing = true
    self:_syncOutput()
    return true
end
function Player:pause()
    self.playing = false
    self:_silence()
end
function Player:stop()
    self:pause()
    self:seek(0)
end
function Player:refresh() self:seek(self.position) end
function Player:step(delta)
    if not self.song or not self.playing then return end
    local target = math.min(self.song.duration, self.position + math.max(0, delta) * self.speed)
    -- After a client stall, reconstruct current state instead of bursting old notes.
    if delta > 0.5 then
        self.resyncs = self.resyncs + 1
        self:seek(target)
    else
        local processed = 0
        while self.index <= #self.song.events and self.song.events[self.index].time <= target do
            self:_event(self.song.events[self.index])
            self.index = self.index + 1
            processed = processed + 1
            if processed >= 4096 and self.index <= #self.song.events and self.song.events[self.index].time <= target then
                self.resyncs = self.resyncs + 1
                self:seek(target)
                break
            end
        end
        self.position = target
    end
    if target >= self.song.duration then
        if self.looped and self.song.duration > 0 then self:seek(0)
        else self:pause() end
    end
end
Core.Player = Player
return Core
