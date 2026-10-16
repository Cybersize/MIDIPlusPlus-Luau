-- Local integration harness: mocks Roblox Instances/signals and executor APIs.
-- This checks script wiring and cleanup, not Roblox rendering or executor permissions.
local TestCore = require("../lib/Core")
local function signal()
    local result = {listeners = {}}
    function result:Connect(fn)
        local connection = {Connected = true}
        function connection:Disconnect() self.Connected = false end
        self.listeners[#self.listeners + 1] = {fn = fn, connection = connection}
        return connection
    end
    function result:Fire(...)
        local snapshot = table.clone(self.listeners)
        for _, entry in ipairs(snapshot) do if entry.connection.Connected then entry.fn(...) end end
    end
    return result
end
local function enumGroup()
    return setmetatable({}, {__index = function(self, name)
        local entry = {Name = name}
        rawset(self, name, entry)
        return entry
    end})
end
local Enum = setmetatable({}, {__index = function(self, name)
    local group = enumGroup(); rawset(self, name, group); return group
end})
local UDim = {new = function(scale, offset) return {Scale = scale, Offset = offset} end}
local UDim2 = {
    new = function(xs, xo, ys, yo) return {X = UDim.new(xs, xo), Y = UDim.new(ys, yo)} end,
    fromOffset = function(x, y) return {X = UDim.new(0, x), Y = UDim.new(0, y)} end,
    fromScale = function(x, y) return {X = UDim.new(x, 0), Y = UDim.new(y, 0)} end,
}
local Vector2 = {new = function(x, y) return {X = x, Y = y} end}
local Color3 = {fromRGB = function(r, g, b) return {r, g, b} end}
local methods = {}
local virtualInputDispatch
local Instance = {}
function Instance.new(class)
    local instance = {_class = class, _properties = {}, _children = {}, _signals = {}, _changes = {}}
    return setmetatable(instance, {
        __index = function(self, key)
            if methods[key] then return methods[key] end
            if key == "Activated" or key == "InputBegan" or key == "InputChanged" or key == "InputEnded" or key == "FocusLost" or key == "Destroying" then
                if not self._signals[key] then self._signals[key] = signal() end
                return self._signals[key]
            end
            if key == "AbsolutePosition" then return {X = 0, Y = 0} end
            if key == "AbsoluteSize" then return {X = 594, Y = 10} end
            return self._properties[key]
        end,
        __newindex = function(self, key, value)
            if key == "Parent" then
                local previous = self._properties.Parent
                if previous and previous._children then
                    local i = table.find(previous._children, self)
                    if i then table.remove(previous._children, i) end
                end
                if value and value._children then value._children[#value._children + 1] = self end
            end
            self._properties[key] = value
            if self._changes[key] then self._changes[key]:Fire() end
        end,
    })
end
function methods:IsA(class) return self._class == class end
function methods:GetChildren() return table.clone(self._children) end
function methods:GetPropertyChangedSignal(property)
    if not self._changes[property] then self._changes[property] = signal() end
    return self._changes[property]
end
function methods:SendKeyEvent(down, code, repeatKey, target)
    assert(self._class == "VirtualInputManager")
    return virtualInputDispatch(down, code, repeatKey, target, "Instance")
end
function methods:Destroy()
    if self._properties.destroyed then return end
    self._properties.destroyed = true
    self.Destroying:Fire()
    for _, child in ipairs(self:GetChildren()) do child:Destroy() end
    for _, event in pairs(self._signals) do
        for _, entry in ipairs(event.listeners) do entry.connection:Disconnect() end
    end
    self.Parent = nil
end
function methods:WaitForChild(name)
    for _, child in ipairs(self._children) do if child.Name == name then return child end end
    error("Missing mock child: " .. name)
end
local root = Instance.new("DataModel")
local playerGui = Instance.new("PlayerGui"); playerGui.Name = "PlayerGui"; playerGui.Parent = root
local localPlayer = Instance.new("Player"); localPlayer.Name = "LocalPlayer"
localPlayer.Parent = root
playerGui.Parent = localPlayer
local UserInputService = {
    InputBegan = signal(), InputChanged = signal(), InputEnded = signal(),
    TextBoxFocused = signal(), WindowFocusReleased = signal(), WindowFocused = signal(),
}
function UserInputService:GetFocusedTextBox() return nil end
local RunService = {Heartbeat = signal()}
local Workspace = Instance.new("Workspace")
Workspace.Parent = root
local camera = Instance.new("Camera"); camera.ViewportSize = {X = 1920, Y = 1080}; Workspace.CurrentCamera = camera
local inputLog, physicallyDown, deniedVirtual = {}, {}, false
local inputEcho = true
local virtualInput = {}
virtualInputDispatch = function(down, code, _, target, kind)
    if deniedVirtual then error("mock permission denied") end
    assert(target == root, "Virtual input requires the real DataModel, not an executor proxy")
    inputLog[#inputLog + 1] = {down = down, code = code.Name, kind = kind}
    physicallyDown[code.Name] = down or nil
    if down and inputEcho then UserInputService.InputBegan:Fire({KeyCode = code}, false) end
end
function virtualInput:SendKeyEvent(down, code, repeatKey, target)
    return virtualInputDispatch(down, code, repeatKey, target, "Service")
end
local services = {Players = {LocalPlayer = localPlayer}, RunService = RunService, UserInputService = UserInputService,
    Workspace = Workspace, VirtualInputManager = virtualInput}
local game = root
function game:GetService(name) assert(services[name], name); return services[name] end
local fileData, httpData
local holdHttp, waitingHttp = false, {}
function game:HttpGet(url)
    assert(url == "https://example.test/song.mid")
    if holdHttp then waitingHttp[#waitingHttp + 1] = coroutine.running(); coroutine.yield() end
    return httpData
end
local function flushHttp()
    local pending = waitingHttp; waitingHttp = {}
    for _, thread in ipairs(pending) do local ok, err = coroutine.resume(thread); assert(ok, err) end
end
local environment = {MIDIPlusPlusConfig = {BackgroundPlayback = false}}
local function getgenv() return environment end
local executorIdentity = "Mock executor"
local function identifyexecutor() return executorIdentity end
local appActive = true
local function isrbxactive() return appActive end
local gethui, keypress, keyrelease, request, http_request, syn = nil, nil, nil, nil, nil, nil
local fileOverrides = {}
local fileListing = {"MIDIPlusPlus/song.mid", "MIDIPlusPlus/no.txt"}
local function readfile(path)
    if fileOverrides[path] ~= nil then return fileOverrides[path] end
    assert(path == "MIDIPlusPlus/song.mid", path)
    return fileData
end
local function listfiles() return fileListing end
local function makefolder() end
local warningLog = {}
local function warn(message) warningLog[#warningLog + 1] = message end
local timers = {}
local task = {
    spawn = function(fn) local ok, err = coroutine.resume(coroutine.create(fn)); assert(ok, err) end,
    delay = function(_, fn) timers[#timers + 1] = fn end,
    wait = function() end,
}
local function flushTimers()
    local pending = timers; timers = {}
    for _, fn in ipairs(pending) do fn() end
end
local function findText(text, parent)
    for _, child in ipairs((parent or playerGui):GetChildren()) do
        if child.Text == text then return child end
        local found = findText(text, child)
        if found then return found end
    end
end
local function findButton(text, parent)
    for _, child in ipairs((parent or playerGui):GetChildren()) do
        if child:IsA("TextButton") and child.Text == text then return child end
        local found = findButton(text, child)
        if found then return found end
    end
end
local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
local tests = 0
local function test(name, fn)
    local ok, err = pcall(fn)
    assert(ok, "FAIL " .. name .. ": " .. tostring(err))
    tests = tests + 1
    print("PASS " .. name)
end

-- The build helper inserts the exact deliverable below, inside runScript().
local function runScript()
-- MIDI++ Luau 1.0.4
-- SPDX-License-Identifier: GPL-3.0-only
-- Piano layouts and velocity curves adapted from Zephkek/MIDIPlusPlus.
-- https://github.com/Zephkek/MIDIPlusPlus
-- Run this entire file in your Roblox executor. No remote code is loaded.
-- Configuration is optional: set getgenv().MIDIPlusPlusConfig before execution.
-- See README.md for input compatibility, controls, and limitations.

local DEMO_BASE64 = "TVRoZAAAAAYAAAABAeBNVHJrAAAAsQD/AxBNSURJKysgTHVhdSBEZW1vAP9RAwehIACQPFqCaIA8AHj/AQAAkEBagmiAQAB4/wEAAJBDWoJogEMAeP8BAACQSFqCaIBIAHj/AQAAkENagmiAQwB4/wEAAJBAWoJogEAAeP8BAACQPlqCaIA+AHj/AQAAkEFagmiAQQB4/wEAALBAfwCQPGQAkEBkAJBDZACQSGSDYIA8AACAQAAAgEMAAIBIAINgsEAAAP8vAA=="

local Core = (function()
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
        timing = ticksPerSecond and "SMPTE" or "PPQN", hasTempo = #tempos > 1,
        duration = seconds + (lastTick - previousTick) * scale, eventCount = parsedCount }
end

function Core.tempoAt(song, seconds)
    local low, high, selected = 1, #song.tempos, 1
    while low <= high do
        local middle = math.floor((low + high) / 2)
        if song.tempos[middle].time <= seconds then selected = middle; low = middle + 1
        else high = middle - 1 end
    end
    return song.tempos[selected].bpm
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

end)()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local environment = type(getgenv) == "function" and getgenv() or _G
local Config = environment.MIDIPlusPlusConfig or {}
local previous = environment.MIDIPlusPlus
if type(previous) == "table" and type(previous.Destroy) == "function" then pcall(function() previous:Destroy() end) end

local function finite(value) return type(value) == "number" and value == value and math.abs(value) < math.huge end
local function trim(value) return value:match("^%s*(.-)%s*$") end
local function bool(value, default) if type(value) == "boolean" then return value end; return default end
local backgroundPlayback = bool(Config.BackgroundPlayback, not bool(Config.PauseOnFocusLoss, false))
local appHasFocus = true
local function windowFocused()
    if type(isrbxactive) == "function" then
        local ok, active = pcall(isrbxactive)
        if ok and type(active) == "boolean" then return active end
    end
    return appHasFocus
end

-- Executors disagree about input APIs. All availability checks are local; no
-- executor name/version is treated as a guarantee that key injection works.
local virtualInput, virtualInputService, ownedVirtualInput
pcall(function() virtualInputService = game:GetService("VirtualInputManager") end)
-- Xeno wraps `game` in a proxy. Native engine methods need a real Instance.
local inputTarget = Workspace.Parent or Workspace
pcall(function() ownedVirtualInput = Instance.new("VirtualInputManager") end)
virtualInput = ownedVirtualInput or virtualInputService
local nativeAvailable = type(keypress) == "function" and type(keyrelease) == "function"
local backend = { name = "Unavailable", used = false, mode = "Auto", sentDown = 0, sentUp = 0 }
local requestedBackend = Config.Backend or "Auto"
local executorName = ""
if type(identifyexecutor) == "function" then
    local ok, name = pcall(identifyexecutor)
    if ok then executorName = tostring(name):lower() end
end
function backend:select(mode)
    self.mode, self.used, self.name = mode, false, "Unavailable"
    if mode == "Custom" and type(Config.SendKey) == "function" then self.name = "Custom"
    elseif mode == "Executor" and nativeAvailable then self.name = "Executor"
    elseif mode == "VirtualInput" and virtualInput then self.name = "VirtualInput"
    elseif mode == "VirtualInputService" and virtualInputService then self.name = "VirtualInputService"
    elseif mode == "Auto" then
        if (backgroundPlayback or executorName:find("xeno", 1, true)) and virtualInput then self.name = "VirtualInput"
        elseif nativeAvailable then self.name = "Executor"
        elseif virtualInput then self.name = "VirtualInput" end
    end
    return self.name ~= "Unavailable"
end
function backend:canBackground()
    return self.name == "VirtualInput" or self.name == "VirtualInputService"
end
local function maySendInput()
    return windowFocused() or (backgroundPlayback and backend:canBackground())
end
backend:select(type(Config.SendKey) == "function" and "Custom" or requestedBackend)
function backend:sendVirtual(info, down)
    local device = self.name == "VirtualInputService" and virtualInputService or virtualInput
    local ok, err = pcall(function() device:SendKeyEvent(down, info.code, false, inputTarget) end)
    if not ok and self.mode == "Auto" and not self.used and device ~= virtualInputService and virtualInputService then
        self.name = "VirtualInputService"
        virtualInputService:SendKeyEvent(down, info.code, false, inputTarget)
    elseif not ok then error("Virtual input failed: " .. tostring(err), 0) end
end
function backend:send(info, down)
    if down and not maySendInput() then
        error("This input mode needs Roblox focused. Enable Background with virtual input.", 0)
    end
    if self.name == "Custom" then
        Config.SendKey(info.code, down, info.vk)
    elseif self.name == "Executor" then
        local ok, err = pcall(down and keypress or keyrelease, info.vk)
        if not ok and self.mode == "Auto" and not self.used and virtualInput then
            self.name = "VirtualInput"
            self:sendVirtual(info, down)
        elseif not ok then error("Executor input failed: " .. tostring(err), 0) end
    elseif self.name == "VirtualInput" or self.name == "VirtualInputService" then
        self:sendVirtual(info, down)
    else
        error("No input backend. Use an executor with keypress/keyrelease or permitted VirtualInputManager access.", 0)
    end
    self.used = true
    if down then self.sentDown = self.sentDown + 1 else self.sentUp = self.sentUp + 1 end
end

local digits = { ["0"] = "Zero", ["1"] = "One", ["2"] = "Two", ["3"] = "Three", ["4"] = "Four",
    ["5"] = "Five", ["6"] = "Six", ["7"] = "Seven", ["8"] = "Eight", ["9"] = "Nine" }
local named = { space = {"Space", 0x20}, tab = {"Tab", 0x09}, enter = {"Return", 0x0D},
    shift = {"LeftShift", 0xA0}, ctrl = {"LeftControl", 0xA2}, control = {"LeftControl", 0xA2},
    alt = {"LeftAlt", 0xA4}, left = {"Left", 0x25}, right = {"Right", 0x27},
    up = {"Up", 0x26}, down = {"Down", 0x28}, escape = {"Escape", 0x1B},
    backspace = {"Backspace", 0x08}, delete = {"Delete", 0x2E} }
local punctuation = { ["-"] = {"Minus", 0xBD}, ["="] = {"Equals", 0xBB}, ["["] = {"LeftBracket", 0xDB},
    ["]"] = {"RightBracket", 0xDD}, ["\\"] = {"BackSlash", 0xDC}, [";"] = {"Semicolon", 0xBA},
    ["'"] = {"Quote", 0xDE}, [","] = {"Comma", 0xBC}, ["."] = {"Period", 0xBE},
    ["/"] = {"Slash", 0xBF}, ["`"] = {"Backquote", 0xC0} }
local shifted = { ["!"]="1", ["@"]="2", ["#"]="3", ["$"]="4", ["%"]="5", ["^"]="6", ["&"]="7",
    ["*"]="8", ["("]="9", [")"]="0", ["_"]="-", ["+"]="=", ["{"]="[", ["}"]="]", ["|"]="\\",
    [":"]=";", ['"']="'", ["<"]=",", [">"]=".", ["?"]="/", ["~"]="`" }
local function plainKey(token)
    local entry = named[token:lower()] or punctuation[token]
    if entry then return {code = Enum.KeyCode[entry[1]], vk = entry[2]} end
    if digits[token] then return {code = Enum.KeyCode[digits[token]], vk = token:byte()} end
    if token:match("^[a-zA-Z]$") then return {code = Enum.KeyCode[token:upper()], vk = token:upper():byte()} end
    local f = tonumber(token:match("^[fF](%d+)$"))
    if f and f >= 1 and f <= 12 then return {code = Enum.KeyCode["F" .. f], vk = 0x6F + f} end
    error("Unsupported piano key: " .. token, 0)
end
local keyCache = {}
local function describeKey(text)
    if keyCache[text] then return keyCache[text] end
    assert(type(text) == "string" and #text > 0, "A piano mapping must be a nonempty string")
    local mods, token = {}, text
    -- A lone '+' is a shifted equals key; prefixes use ctrl+q, shift+q, alt+q.
    while #token > 1 do
        local prefix, rest = token:match("^(%a+)%+(.+)$")
        if not prefix then break end
        local lower = prefix:lower()
        assert(lower == "ctrl" or lower == "control" or lower == "shift" or lower == "alt", "Unknown modifier: " .. prefix)
        mods[#mods + 1] = plainKey(lower)
        token = rest
    end
    if shifted[token] then mods[#mods + 1] = plainKey("shift"); token = shifted[token]
    elseif token:match("^[A-Z]$") then mods[#mods + 1] = plainKey("shift") end
    local result = plainKey(token)
    local seen, unique = {}, {}
    for _, modifier in ipairs(mods) do
        if not seen[modifier.vk] then seen[modifier.vk] = true; unique[#unique + 1] = modifier end
    end
    result.mods, result.text = unique, text
    keyCache[text] = result
    return result
end

local Keyboard = { active = {}, counts = {}, physical = {}, touched = {}, pedal = false,
    velocity = bool(Config.Velocity, false), curveName = "Linear", lastVelocity = nil }
if Core.curves[Config.Curve] then Keyboard.curveName = Config.Curve end
local pedalKey = describeKey(Config.SustainKey or "Space")
function Keyboard:raw(info, down)
    if down then self.touched[info.vk] = info end
    backend:send(info, down)
    if not down then self.touched[info.vk] = nil end
end
function Keyboard:key(info, down)
    -- Foreground-only adapters still need to release held keys after focus loss.
    -- Avoid fresh modifier presses during that cleanup.
    if not down and not windowFocused() and not backend:canBackground() then
        self:raw(info, false)
        for _, modifier in ipairs(info.mods or {}) do self:raw(modifier, false) end
        return
    end
    for _, modifier in ipairs(info.mods or {}) do self:raw(modifier, true) end
    self:raw(info, down)
    for i = #(info.mods or {}), 1, -1 do self:raw(info.mods[i], false) end
end
function Keyboard:tap(info)
    local held = self.physical[info.vk]
    if held then self:key(held, false) end
    self:key(info, true)
    self:key(info, false)
    if held then self:key(held, true) end
end
function Keyboard:noteOn(voice)
    local info = describeKey(voice.key)
    if self.velocity then
        local velocityKey = Core.velocityKey(voice.velocity, Core.curves[self.curveName])
        if velocityKey ~= self.lastVelocity then
            self:tap(describeKey("alt+" .. velocityKey))
            self.lastVelocity = velocityKey
        end
    end
    if self.counts[info.vk] then self:key(self.physical[info.vk], false) end
    self:key(info, true)
    self.counts[info.vk] = (self.counts[info.vk] or 0) + 1
    self.physical[info.vk], self.active[voice.id] = info, info
end
function Keyboard:noteOff(voice)
    local info = self.active[voice.id]
    if not info then return end
    self.active[voice.id] = nil
    local remaining = (self.counts[info.vk] or 1) - 1
    if remaining <= 0 then
        self:key(self.physical[info.vk] or info, false)
        self.counts[info.vk], self.physical[info.vk] = nil, nil
    else self.counts[info.vk] = remaining end
end
function Keyboard:sustain(down)
    if down == self.pedal then return end
    self:key(pedalKey, down)
    self.pedal = down
end
function Keyboard:panic()
    -- Try every release even if one API call fails. Never leave a modifier down
    -- just because a later note raised an input error.
    local physical = self.physical
    self.active, self.counts, self.physical = {}, {}, {}
    for _, info in pairs(physical) do pcall(function() self:key(info, false) end) end
    if self.pedal then pcall(function() self:key(pedalKey, false) end) end
    local pending = {}
    for _, info in pairs(self.touched) do pending[#pending + 1] = info end
    for _, info in ipairs(pending) do pcall(function() self:raw(info, false) end) end
    self.pedal, self.lastVelocity = false, nil
end

local player = Core.newPlayer({
    noteOn = function(voice) Keyboard:noteOn(voice) end,
    noteOff = function(voice) Keyboard:noteOff(voice) end,
    sustain = function(down) Keyboard:sustain(down) end,
    panic = function() Keyboard:panic() end,
})
player.speed = finite(Config.Speed) and math.clamp(Config.Speed, 0.1, 4) or 1
player.transpose = finite(Config.Transpose) and math.clamp(math.floor(Config.Transpose), -48, 48) or 0
player.skipDrums = bool(Config.SkipDrums, true)
player.fold = bool(Config.FoldOutOfRange, false)
player.sustain = bool(Config.Sustain, true)
player.looped = bool(Config.Loop, false)
local fullMode = bool(Config.Full88Keys, false)
local function applyMap()
    player.map = Core.keymap(fullMode)
    player.minNote, player.maxNote = fullMode and 21 or 36, fullMode and 108 or 96
    for note, key in pairs(Config.Keymap or {}) do
        local number = tonumber(note)
        assert(number and number % 1 == 0 and number >= 0 and number <= 127, "Keymap indices must be MIDI note numbers 0..127")
        if key == false then player.map[number] = nil
        else describeKey(key); player.map[number] = key end
    end
end
applyMap()

local alive, loadVersion, playVersion, pendingPlay = true, 0, 0, false
local inputProbe
local connections, rowConnections, queueConnections = {}, {}, {}
local function connect(signal, callback, bucket)
    local connection = signal:Connect(callback)
    table.insert(bucket or connections, connection)
    return connection
end
local function disconnectAll(bucket)
    for _, connection in ipairs(bucket) do connection:Disconnect() end
    table.clear(bucket)
end

local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.DisplayOrder = "MIDIPlusPlusLuau", false, true, 1000
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local uiParent
if type(gethui) == "function" then
    local ok, result = pcall(gethui)
    if ok and typeof(result) == "Instance" then uiParent = result end
end
gui.Parent = uiParent or Players.LocalPlayer:WaitForChild("PlayerGui")
local colors = { background = Color3.fromRGB(17, 22, 29), panel = Color3.fromRGB(27, 34, 43),
    field = Color3.fromRGB(36, 44, 54), text = Color3.fromRGB(236, 240, 237),
    muted = Color3.fromRGB(151, 167, 178), accent = Color3.fromRGB(106, 224, 181), danger = Color3.fromRGB(255, 145, 136) }
local function make(class, properties, parent)
    local object = Instance.new(class)
    for key, value in pairs(properties) do object[key] = value end
    object.Parent = parent
    return object
end
local function round(object, radius)
    make("UICorner", {CornerRadius = UDim.new(0, radius or 7)}, object)
end
local window = make("Frame", {Name = "Window", Size = UDim2.fromOffset(640, 776),
    Position = UDim2.new(0.5, 0, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundColor3 = colors.background, BorderSizePixel = 0, Active = true}, gui)
round(window, 12)
make("UIStroke", {Color = Color3.fromRGB(61, 76, 88), Thickness = 1}, window)
local scale = make("UIScale", {Scale = 1}, window)
local function scaleWindow()
    local camera = Workspace.CurrentCamera
    if camera then scale.Scale = math.clamp(math.min((camera.ViewportSize.X - 24) / 640, (camera.ViewportSize.Y - 24) / 776), 0.3, 1) end
end
scaleWindow()
connect(Workspace:GetPropertyChangedSignal("CurrentCamera"), scaleWindow)
-- Viewport dimensions can change without replacing CurrentCamera.
local viewportCamera, viewportConnection
local function watchViewport()
    if viewportConnection then viewportConnection:Disconnect() end
    viewportCamera = Workspace.CurrentCamera
    if viewportCamera then viewportConnection = connect(viewportCamera:GetPropertyChangedSignal("ViewportSize"), scaleWindow) end
    scaleWindow()
end
connect(Workspace:GetPropertyChangedSignal("CurrentCamera"), watchViewport)
watchViewport()

local function label(parent, text, x, y, w, h, size, color)
    return make("TextLabel", {Text = text, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
        BackgroundTransparency = 1, TextColor3 = color or colors.text, Font = Enum.Font.Gotham,
        TextSize = size or 14, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd}, parent)
end
local function button(parent, text, x, y, w, h, accent)
    local b = make("TextButton", {Text = text, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
        BackgroundColor3 = accent and colors.accent or colors.field, TextColor3 = accent and colors.background or colors.text,
        BorderSizePixel = 0, Font = Enum.Font.GothamMedium, TextSize = 13, AutoButtonColor = true}, parent)
    round(b)
    return b
end
local function box(parent, text, placeholder, x, y, w, h)
    local b = make("TextBox", {Text = text, PlaceholderText = placeholder, Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(w, h), BackgroundColor3 = colors.field, TextColor3 = colors.text,
        PlaceholderColor3 = colors.muted, BorderSizePixel = 0, Font = Enum.Font.Code, TextSize = 14,
        ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left}, parent)
    round(b)
    make("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10)}, b)
    return b
end

local header = make("Frame", {Size = UDim2.new(1, 0, 0, 62), BackgroundTransparency = 1, Active = true}, window)
label(header, "MIDI++", 22, 10, 140, 25, 23, colors.accent).Font = Enum.Font.GothamBold
label(header, "LUAU  /  VIRTUAL PIANO  /  1.0.4", 23, 37, 360, 16, 10, colors.muted)
local backgroundButton = button(header, "", 365, 16, 174, 30)
local function refreshBackgroundButton()
    backgroundButton.Text = backgroundPlayback and (backend:canBackground() and "Background: ON" or "Background: N/A")
        or "Background: OFF"
    backgroundButton.TextColor3 = backgroundPlayback and backend:canBackground() and colors.accent or colors.muted
end
refreshBackgroundButton()
local minimize = button(header, "_", 548, 16, 30, 30)
local close = button(header, "X", 586, 16, 30, 30)
local body = make("Frame", {Position = UDim2.fromOffset(0, 62), Size = UDim2.fromOffset(640, 714), BackgroundTransparency = 1}, window)
label(body, "MIDI SOURCE", 22, 3, 200, 20, 11, colors.muted)
local modeButton = button(body, "File", 22, 29, 78, 34)
local sourceBox = box(body, Config.DefaultFile or "MIDIPlusPlus/song.mid", "Path inside the executor workspace", 108, 29, 308, 34)
local loadButton = button(body, "Load", 424, 29, 92, 34, true)
local enqueueButton = button(body, "+ Queue", 524, 29, 92, 34)
local filesButton = button(body, "Files", 22, 71, 78, 26)
local refreshButton = button(body, "Refresh", 108, 71, 78, 26)
local demoButton = button(body, "Load demo", 194, 71, 104, 26)
local enqueueAllButton = button(body, "Queue all", 306, 71, 100, 26)
local nextButton = button(body, "Next", 414, 71, 90, 26)
local clearQueueButton = button(body, "Clear queue", 512, 71, 104, 26)
local songLabel = label(body, "No MIDI loaded", 22, 108, 594, 25, 17)
songLabel.Font = Enum.Font.GothamMedium
local metaLabel = label(body, "Load a file or try the built-in demo.", 22, 137, 594, 19, 11, colors.muted)
local playButton = button(body, "Play", 22, 167, 110, 34, true)
local stopButton = button(body, "Stop", 140, 167, 78, 34)
local restartButton = button(body, "Restart", 226, 167, 88, 34)
local backButton = button(body, "-5 sec", 322, 167, 80, 34)
local forwardButton = button(body, "+5 sec", 410, 167, 80, 34)
local panicButton = button(body, "Panic / F4", 498, 167, 118, 34)
local seekBar = button(body, "", 22, 216, 594, 10)
local seekFill = make("Frame", {Size = UDim2.fromScale(0, 1), BackgroundColor3 = colors.accent, BorderSizePixel = 0}, seekBar)
round(seekFill, 5)
local timeLabel = label(body, "0:00 / 0:00", 22, 231, 142, 20, 12, colors.muted)
local tempoLabel = label(body, "Tempo: -- BPM", 170, 231, 158, 20, 11, colors.accent)
local activityLabel = label(body, "", 334, 231, 282, 20, 10, colors.muted)
activityLabel.TextXAlignment = Enum.TextXAlignment.Right

label(body, "SPEED", 22, 264, 64, 28, 11, colors.muted)
local speedDown = button(body, "-", 87, 263, 30, 30)
local speedBox = box(body, string.format("%.2f", player.speed), "1.00", 124, 263, 72, 30)
local speedUp = button(body, "+", 203, 263, 30, 30)
label(body, "TRANSPOSE", 278, 264, 100, 28, 11, colors.muted)
local transposeDown = button(body, "-", 382, 263, 30, 30)
local transposeBox = box(body, tostring(player.transpose), "0", 419, 263, 72, 30)
local transposeUp = button(body, "+", 498, 263, 30, 30)
label(body, "semitones", 537, 266, 79, 26, 11, colors.muted)

local fail, refreshQueue
local function toggle(text, x, y, get, set)
    local b = button(body, "", x, y, 192, 28)
    local function update()
        b.Text = (get() and "[ON]   " or "[OFF]  ") .. text
        b.TextColor3 = get() and colors.accent or colors.muted
    end
    connect(b.Activated, function()
        local ok, err = pcall(function() set(not get()); player:refresh() end)
        if not ok then fail(err) end
        update()
    end)
    update()
    return b
end
toggle("88 keys", 22, 309, function() return fullMode end, function(value) fullMode = value; applyMap() end)
toggle("Skip drums", 222, 309, function() return player.skipDrums end, function(value) player.skipDrums = value end)
toggle("Fold octaves", 422, 309, function() return player.fold end, function(value) player.fold = value end)
toggle("Sustain", 22, 345, function() return player.sustain end, function(value) player.sustain = value end)
toggle("Velocity / Alt", 222, 345, function() return Keyboard.velocity end, function(value) Keyboard.velocity = value end)
toggle("Loop", 422, 345, function() return player.looped end, function(value)
    player.looped = value
    if refreshQueue then refreshQueue() end
end)
local curveButton = button(body, "Curve: " .. Keyboard.curveName, 22, 385, 192, 28)
local inputButton = button(body, "Input: " .. backend.mode, 222, 385, 192, 28)
local testInputButton = button(body, "Test keys", 422, 385, 192, 28)
label(body, "TRACKS", 22, 427, 180, 20, 11, colors.muted)
local resetTracks = button(body, "Reset tracks", 500, 422, 116, 25)
local tracksFrame = make("ScrollingFrame", {Position = UDim2.fromOffset(22, 455), Size = UDim2.fromOffset(594, 70),
    BackgroundColor3 = colors.panel, BorderSizePixel = 0, CanvasSize = UDim2.fromOffset(0, 0),
    ScrollBarThickness = 4, ScrollBarImageColor3 = colors.muted, ScrollingDirection = Enum.ScrollingDirection.Y}, body)
round(tracksFrame)
local queueLabel = label(body, "UP NEXT  (0)", 22, 536, 594, 20, 11, colors.muted)
local queueFrame = make("ScrollingFrame", {Position = UDim2.fromOffset(22, 563), Size = UDim2.fromOffset(594, 92),
    BackgroundColor3 = colors.panel, BorderSizePixel = 0, CanvasSize = UDim2.fromOffset(0, 0),
    ScrollBarThickness = 4, ScrollBarImageColor3 = colors.muted, ScrollingDirection = Enum.ScrollingDirection.Y}, body)
round(queueFrame)
local statusLabel = label(body, "Input: " .. backend.name .. " (checked when playing)", 22, 663, 594, 24, 11, colors.accent)
statusLabel.TextWrapped, statusLabel.TextTruncate = true, Enum.TextTruncate.None
label(body, "F6 play/pause  /  F7 stop  /  F8 show/hide  /  F4 panic", 22, 692, 594, 16, 10, colors.muted)

local function status(message, failed)
    if not alive then return end
    statusLabel.Text = tostring(message):gsub("[\r\n]", " "):sub(1, 240)
    statusLabel.TextColor3 = failed and colors.danger or colors.accent
end
local cancelLoading, advanceQueue, startOrPause
local function cancelStart()
    playVersion = playVersion + 1
    pendingPlay = false
    if inputProbe and inputProbe.running then
        inputProbe.running, inputProbe.cancelled = false, true
        Keyboard:panic()
    end
end
fail = function(err)
    cancelStart()
    if cancelLoading then cancelLoading(true) end
    player.playing, player.outputActive = false, false
    Keyboard:panic()
    -- A backend error can interrupt an event after it modified logical state.
    -- Rebuild silently so resuming cannot enqueue that event a second time.
    pcall(function() player:seek(player.position) end)
    status(tostring(err), true)
    warn("[MIDI++ Luau] " .. tostring(err))
end
local function safely(fn)
    return function(...)
        if not alive then return end
        local args = table.pack(...)
        local ok, err = pcall(function() fn(table.unpack(args, 1, args.n)) end)
        if not ok then fail(err) end
    end
end
local function formatTime(seconds)
    local whole = math.floor(math.max(0, seconds))
    return string.format("%d:%02d", math.floor(whole / 60), whole % 60)
end
local function bpmNow()
    if not player.song or player.song.timing == "SMPTE" then return nil end
    return Core.tempoAt(player.song, player.position)
end
local function refreshTracks()
    disconnectAll(rowConnections)
    for _, child in ipairs(tracksFrame:GetChildren()) do if child:IsA("Frame") then child:Destroy() end end
    if not player.song then return end
    for i, track in ipairs(player.song.tracks) do
        local row = make("Frame", {Position = UDim2.fromOffset(0, (i - 1) * 32), Size = UDim2.new(1, -6, 0, 32),
            BackgroundTransparency = 1}, tracksFrame)
        local trackLabel = label(row, string.format("%02d  %s  (%d notes)", i, track.name, track.notes), 10, 3, 408, 26, 11)
        trackLabel.TextColor3 = player:isTrackEnabled(i) and colors.text or colors.muted
        local mute = button(row, track.muted and "Muted" or "Mute", 432, 3, 66, 25)
        local solo = button(row, track.solo and "Solo ON" or "Solo", 506, 3, 66, 25)
        mute.TextColor3 = track.muted and colors.danger or colors.muted
        solo.TextColor3 = track.solo and colors.accent or colors.muted
        connect(mute.Activated, safely(function()
            track.muted = not track.muted; player:refresh(); refreshTracks()
        end), rowConnections)
        connect(solo.Activated, safely(function()
            track.solo = not track.solo; player:refresh(); refreshTracks()
        end), rowConnections)
    end
    tracksFrame.CanvasSize = UDim2.fromOffset(0, #player.song.tracks * 32)
end
local sourceMode, loading, fileList, loadedSource = "File", false, nil, nil
local queue, queueSerial, queuedLoading, queueJob = {}, 0, nil, false
local function sourceName(value, mode)
    if mode == "Raw" then return "Demo - MIDI++ Luau" end
    if mode == "Base64" then return "Base64 MIDI" end
    local path = mode == "URL" and (value:match("^[^?]+") or value) or value
    return (path:match("([^/\\]+)$") or "MIDI"):sub(1, 120)
end
local function queueCount() return #queue + (queuedLoading and 1 or 0) end
refreshQueue = function()
    disconnectAll(queueConnections)
    for _, child in ipairs(queueFrame:GetChildren()) do if child:IsA("Frame") then child:Destroy() end end
    queueLabel.Text = string.format("UP NEXT  (%d)  /  %s", queueCount(), player.looped and "Loop repeats current song" or "Plays in order")
    local rows = {}
    if queuedLoading then rows[1] = queuedLoading end
    for _, item in ipairs(queue) do rows[#rows + 1] = item end
    if #rows == 0 then
        local row = make("Frame", {Size = UDim2.new(1, -6, 0, 30), BackgroundTransparency = 1}, queueFrame)
        label(row, "Use + Queue beside a file, or Queue all. Press Play to begin.", 10, 0, 570, 30, 11, colors.muted)
    end
    for i, item in ipairs(rows) do
        local row = make("Frame", {Position = UDim2.fromOffset(0, (i - 1) * 30), Size = UDim2.new(1, -6, 0, 30),
            BackgroundTransparency = 1}, queueFrame)
        label(row, string.format("%02d  %s%s", i, item == queuedLoading and "Loading: " or "", item.name), 10, 0, 474, 30, 11)
        local remove = button(row, "Remove", 496, 2, 76, 25)
        connect(remove.Activated, safely(function()
            if item == queuedLoading then
                cancelLoading(false)
                status("Removed loading song. Press Play or Next to continue the queue.")
            else
                for index, pending in ipairs(queue) do
                    if pending.id == item.id then table.remove(queue, index); break end
                end
                refreshQueue()
            end
        end), queueConnections)
    end
    queueFrame.CanvasSize = UDim2.fromOffset(0, math.max(1, #rows) * 30)
end
cancelLoading = function(returnQueued)
    loadVersion = loadVersion + 1
    loading, queueJob, loadButton.Text = false, false, "Load"
    if queuedLoading then
        if returnQueued then table.insert(queue, 1, queuedLoading) end
        queuedLoading = nil
    end
    if not player.song then
        songLabel.Text = "No MIDI loaded"
        metaLabel.Text = "Load a file or add songs to the queue."
    end
    refreshQueue()
end
local function enqueueSource(value, mode, quiet)
    local message
    if type(value) ~= "string" or trim(value) == "" then message = "Choose a MIDI source before adding it to the queue."
    elseif mode == "Base64" and #value > 24 * 1024 * 1024 then message = "Base64 source is too large."
    elseif queueCount() >= 128 then message = "Queue is full (128 songs). Remove a song first." end
    if message then if not quiet then status(message, true) end; return nil, message end
    queueSerial = queueSerial + 1
    local item = {id = queueSerial, value = value, mode = mode, name = sourceName(value, mode)}
    queue[#queue + 1] = item
    if not quiet then refreshQueue(); status("Queued: " .. item.name) end
    return item.id
end
local function clearQueue()
    table.clear(queue)
    if queueJob then cancelLoading(false) end
    refreshQueue()
    status("Queue cleared.")
end
refreshQueue()
local function closeFileList()
    if fileList then fileList:Destroy(); fileList = nil end
end
local function setSourceMode(mode)
    sourceMode, modeButton.Text = mode, mode
    sourceBox.Text = ""
    sourceBox.PlaceholderText = mode == "URL" and "Direct https:// URL to a .mid file" or mode == "Base64" and "Paste base64 MIDI data" or "MIDIPlusPlus/song.mid"
end
connect(modeButton.Activated, function()
    setSourceMode(sourceMode == "File" and "URL" or sourceMode == "URL" and "Base64" or "File")
end)
local requestFunction = request or http_request or (type(syn) == "table" and syn.request)
local function fetchMidi(url)
    assert(url:match("^https?://%S+$"), "Enter a direct http(s) MIDI URL")
    if type(requestFunction) == "function" then
        local response = requestFunction({Url = url, Method = "GET"})
        assert(type(response) == "table", "HTTP API returned no response")
        local code = tonumber(response.StatusCode or response.Status)
        assert(code and code >= 200 and code < 300, "HTTP error: " .. tostring(code or "unknown status"))
        assert(type(response.Body) == "string", "HTTP response has no binary body")
        return response.Body
    end
    return game:HttpGet(url)
end
local function installSong(song, name, sourceInfo)
    cancelStart()
    player:load(song)
    loadedSource = sourceInfo
    songLabel.Text = name
    local notes = 0
    for _, track in ipairs(song.tracks) do notes = notes + track.notes end
    metaLabel.Text = string.format("%s  /  %d tracks  /  %d notes  /  MIDI format %d", formatTime(song.duration), #song.tracks, notes, song.format)
    refreshTracks()
    status((sourceInfo and sourceInfo.binarySafe and "Loaded via binary-safe .b64. " or "Loaded. ")
        .. "Open the game's piano, then press Play. Input: " .. backend.name)
end
local function readSource(value, mode)
    local data
    if mode == "File" then return Core.loadFile(value, readfile)
    elseif mode == "Raw" then data = value
    elseif mode == "URL" then data = fetchMidi(value)
    elseif mode == "Base64" then
        assert(#value <= 24 * 1024 * 1024, "Base64 source is too large")
        data = Core.decodeBase64(value)
    else error("Unknown source mode") end
    return Core.parse(data)
end
local function loadSource(value, mode)
    closeFileList()
    cancelStart()
    cancelLoading(true)
    player:stop()
    local version = loadVersion
    loading, loadButton.Text = true, "Loading..."
    status("Loading MIDI...")
    task.spawn(function()
        if not alive or version ~= loadVersion then return end
        local ok, songOrError, sourceInfo = pcall(readSource, value, mode)
        if not alive or version ~= loadVersion then return end
        loading, loadButton.Text = false, "Load"
        if ok then
            local installed, err = pcall(installSong, songOrError, sourceName(value, mode), sourceInfo)
            if not installed then fail(err) end
        else status(songOrError, true) end
    end)
end
connect(loadButton.Activated, safely(function() loadSource(trim(sourceBox.Text), sourceMode) end))
connect(demoButton.Activated, safely(function() loadSource(Core.decodeBase64(DEMO_BASE64), "Raw") end))
connect(enqueueButton.Activated, function() enqueueSource(trim(sourceBox.Text), sourceMode) end)

local function scanFiles()
    assert(type(listfiles) == "function", "This executor has no listfiles; type the relative file path instead")
    local folder = Config.Folder or "MIDIPlusPlus"
    if type(makefolder) == "function" then pcall(makefolder, folder) end
    local files, filtered, choices = listfiles(folder), {}, {}
    for _, file in ipairs(files) do
        local lower = tostring(file):lower()
        local base = lower:gsub("%.b64$", "")
        if base:match("%.midi?$") or base:match("%.rmi$") then
            local canonical = base:gsub("\\", "/"):gsub("^%./", "")
            if not choices[canonical] or not lower:match("%.b64$") then choices[canonical] = file end
        end
    end
    for _, file in pairs(choices) do filtered[#filtered + 1] = file end
    table.sort(filtered, function(a, b) return a:lower() < b:lower() end)
    return filtered, folder
end
local function refreshFiles()
    local ok, filtered, folder = pcall(scanFiles)
    if not ok then status(filtered, true); return nil, filtered end
    closeFileList()
    fileList = make("ScrollingFrame", {Position = UDim2.fromOffset(22, 99), Size = UDim2.fromOffset(594, 158),
        BackgroundColor3 = colors.panel, BorderSizePixel = 0, ScrollBarThickness = 5, ZIndex = 20,
        CanvasSize = UDim2.fromOffset(0, math.max(1, #filtered) * 30)}, body)
    round(fileList)
    if #filtered == 0 then
        local empty = label(fileList, "No MIDI files in " .. folder .. ". Click Files to close.", 10, 0, 570, 30, 12)
        empty.ZIndex = 21
    end
    for i, path in ipairs(filtered) do
        local b = button(fileList, path, 4, (i - 1) * 30, 490, 28)
        b.ZIndex, b.TextTruncate = 21, Enum.TextTruncate.AtEnd
        local add = button(fileList, "+ Queue", 502, (i - 1) * 30, 76, 28)
        add.ZIndex = 21
        -- Destroying the file menu also disconnects these Instance signals.
        b.Activated:Connect(function()
            setSourceMode("File"); sourceBox.Text = path
            closeFileList()
        end)
        add.Activated:Connect(function() enqueueSource(path, "File") end)
    end
    status(string.format("Found %d songs in %s. Select a file or use + Queue.", #filtered, folder))
    return table.clone(filtered)
end
connect(filesButton.Activated, function()
    if fileList then closeFileList() else refreshFiles() end
end)
connect(refreshButton.Activated, function() refreshFiles() end)
connect(enqueueAllButton.Activated, function()
    local ok, files = pcall(scanFiles)
    if not ok then status(files, true); return end
    local added = 0
    for _, path in ipairs(files) do
        if not enqueueSource(path, "File", true) then break end
        added = added + 1
    end
    refreshQueue()
    status(string.format("Added %d songs to the queue.%s", added, added < #files and " Queue limit: 128." or ""), added < #files)
end)
connect(clearQueueButton.Activated, safely(clearQueue))

advanceQueue = function()
    closeFileList()
    cancelStart()
    cancelLoading(false)
    player:stop()
    if #queue == 0 then status("Queue empty. Add a song with + Queue."); return end
    player:load(nil)
    loadedSource = nil
    songLabel.Text = "Loading next song..."
    metaLabel.Text = "Songs play in the order shown below."
    refreshTracks()
    local version = loadVersion
    loading, queueJob, loadButton.Text = true, true, "Loading..."
    task.spawn(safely(function()
        local skipped = 0
        while alive and version == loadVersion and #queue > 0 do
            local item = table.remove(queue, 1)
            queuedLoading = item
            refreshQueue()
            status("Loading queued song: " .. item.name)
            local ok, songOrError, sourceInfo = pcall(readSource, item.value, item.mode)
            if not alive or version ~= loadVersion then return end
            if ok then
                installSong(songOrError, item.name, sourceInfo)
                queuedLoading = nil
                loading, queueJob, loadButton.Text = false, false, "Load"
                refreshQueue()
                local gap = finite(Config.QueueDelay) and math.clamp(Config.QueueDelay, 0, 10) or 0.5
                startOrPause(gap)
                return
            end
            skipped = skipped + 1
            warn("[MIDI++ Luau] Skipped queued song " .. item.name .. ": " .. tostring(songOrError))
            queuedLoading = nil
            -- Yield between bad entries so Stop/Next can cancel a long queue.
            task.wait()
        end
        if not alive or version ~= loadVersion then return end
        loading, queueJob, loadButton.Text = false, false, "Load"
        refreshQueue()
        status(string.format("Queue finished; skipped %d unreadable songs. Check file paths / Convert-MIDI.", skipped), skipped > 0)
    end))
end
connect(nextButton.Activated, safely(function() advanceQueue() end))

startOrPause = function(delayOverride)
    closeFileList()
    if queueJob or player.playing or pendingPlay then
        cancelStart(); cancelLoading(true); player:pause(); status("Paused. Queue kept."); return
    end
    if loading then status("Wait for the MIDI to finish loading."); return end
    if #queue > 0 and (not player.song or player.position >= player.song.duration) then advanceQueue(); return end
    if not player.song then status("Load a MIDI or add songs to the queue first.", true); return end
    if backend.name == "Unavailable" then status("No input backend is available in this executor.", true); return end
    local focused = UserInputService:GetFocusedTextBox()
    if focused then focused:ReleaseFocus() end
    cancelStart()
    local version = playVersion
    pendingPlay = true
    local delay = finite(delayOverride) and math.clamp(delayOverride, 0, 10)
        or (finite(Config.StartDelay) and math.clamp(Config.StartDelay, 0, 10) or 1.5)
    status(string.format("Starting in %.1fs. %s", delay, backgroundPlayback and backend:canBackground()
        and "Background playback enabled." or "Focus the game's piano."))
    task.delay(delay, safely(function()
        if version ~= playVersion or not pendingPlay then return end
        pendingPlay = false
        if not maySendInput() then status("This Input needs Roblox focused. Choose virtual input for background playback.", true); return end
        if UserInputService:GetFocusedTextBox() then status("Close the text box before playing.", true); return end
        local ok, message = player:play()
        status(ok and ((not windowFocused() and "Playing in background / " or "Playing / ") .. backend.name) or message, not ok)
    end))
end
local function stopPlayback()
    cancelStart(); cancelLoading(true); player:stop(); status("Stopped. Queue kept. All piano keys released.")
end
local function setBackend(mode)
    cancelStart()
    cancelLoading(true)
    local paused, pauseError = pcall(function() player:pause() end)
    if not paused then player.playing, player.outputActive = false, false; Keyboard:panic(); warn(pauseError) end
    local available = backend:select(mode)
    inputButton.Text = "Input: " .. mode
    refreshBackgroundButton()
    status(available and ("Input: " .. backend.name .. (backgroundPlayback and backend:canBackground()
        and ". Background playback enabled; click Test keys." or ". Click Test keys with Roblox focused."))
        or ("Input mode is unavailable: " .. mode), not available)
    return available
end
local function setBackgroundPlayback(enabled)
    assert(type(enabled) == "boolean", "BackgroundPlayback must be true or false")
    cancelStart()
    cancelLoading(true)
    local paused, pauseError = pcall(function() player:pause() end)
    if not paused then player.playing, player.outputActive = false, false; Keyboard:panic(); warn(pauseError) end
    backgroundPlayback = enabled
    if enabled and not backend:canBackground() and virtualInput then
        backend:select("VirtualInput")
        inputButton.Text = "Input: " .. backend.mode
    end
    local available = backend:canBackground()
    refreshBackgroundButton()
    status(enabled and (available and "Background ON. Playback can continue while Roblox is unfocused."
        or "Background needs virtual input; the current Input still requires Roblox focus.")
        or "Background OFF. Playback pauses when Roblox loses focus.", enabled and not available)
    return not enabled or available
end
connect(backgroundButton.Activated, safely(function() setBackgroundPlayback(not backgroundPlayback) end))
local inputModes = {"Auto"}
if virtualInput then inputModes[#inputModes + 1] = "VirtualInput" end
if nativeAvailable then inputModes[#inputModes + 1] = "Executor" end
if virtualInputService then inputModes[#inputModes + 1] = "VirtualInputService" end
if type(Config.SendKey) == "function" then inputModes[#inputModes + 1] = "Custom" end
connect(inputButton.Activated, safely(function()
    local index = table.find(inputModes, backend.mode) or 1
    setBackend(inputModes[index % #inputModes + 1])
end))

local function testInput()
    closeFileList()
    cancelStart()
    cancelLoading(true)
    player:pause()
    if backend.name == "Unavailable" then status("No keyboard input backend is available.", true); return end
    local focused = UserInputService:GetFocusedTextBox()
    if focused then focused:ReleaseFocus() end
    local probe = {running = true, cancelled = false, observed = {}, expected = {}, sent = 0,
        received = 0, processed = 0, backend = backend.name}
    inputProbe = probe
    status(backgroundPlayback and backend:canBackground()
        and "Test starts in 1.5s. T, U, O will be sent to Roblox, including in background."
        or "Test starts in 1.5s: focus Roblox's piano. It will play T, U, O.")
    local keys = {"t", "u", "o"}
    local function current() return alive and inputProbe == probe and probe.running end
    local function playOne(index)
        if not current() then return end
        if not maySendInput() then
            cancelStart(); status("This Input needs Roblox focused; enable Background with virtual input.", true); return
        end
        if UserInputService:GetFocusedTextBox() then
            cancelStart(); status("Test cancelled: close the text box and try again.", true); return
        end
        local info = describeKey(keys[index])
        probe.expected[info.code] = true
        Keyboard:key(info, true)
        probe.sent = probe.sent + 1
        task.delay(0.18, safely(function()
            if not current() then return end
            Keyboard:key(info, false)
            if index < #keys then
                task.delay(0.12, safely(function() playOne(index + 1) end))
            else
                task.delay(0.15, safely(function()
                    if not current() then return end
                    probe.running = false
                    Keyboard:panic()
                    if probe.received > 0 then
                        status(string.format("Test: %d/3 keys reached Roblox (%d consumed by UI). If silent, check piano focus/controls.",
                            probe.received, probe.processed))
                    else
                        status("Test: 3 keys sent; Roblox received none. Change Input and test again.", true)
                    end
                end))
            end
        end))
    end
    task.delay(1.5, safely(function() playOne(1) end))
end
connect(UserInputService.InputBegan, function(input, processed)
    local probe = inputProbe
    if probe and probe.running and probe.expected[input.KeyCode] and not probe.observed[input.KeyCode] then
        probe.observed[input.KeyCode] = true
        probe.received = probe.received + 1
        if processed then probe.processed = probe.processed + 1 end
    end
end)
connect(testInputButton.Activated, safely(testInput))
connect(playButton.Activated, safely(startOrPause))
connect(stopButton.Activated, safely(stopPlayback))
connect(panicButton.Activated, safely(stopPlayback))
connect(restartButton.Activated, safely(function()
    cancelStart(); cancelLoading(true); player:stop(); startOrPause()
end))
connect(backButton.Activated, safely(function() player:seek(player.position - 5) end))
connect(forwardButton.Activated, safely(function() player:seek(player.position + 5) end))
connect(seekBar.InputBegan, safely(function(input)
    if not player.song then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        local fraction = (input.Position.X - seekBar.AbsolutePosition.X) / math.max(1, seekBar.AbsoluteSize.X)
        player:seek(math.clamp(fraction, 0, 1) * player.song.duration)
    end
end))
local function setSpeed(value)
    assert(finite(value), "Speed must be a number between 0.10 and 4.00")
    player.speed = math.clamp(value, 0.1, 4)
    speedBox.Text = string.format("%.2f", player.speed)
end
local function setTranspose(value)
    assert(finite(value), "Transpose must be a number between -48 and 48")
    player.transpose = math.clamp(math.floor(value), -48, 48)
    transposeBox.Text = tostring(player.transpose)
    player:refresh()
end
connect(speedBox.FocusLost, safely(function() setSpeed(tonumber(speedBox.Text)) end))
connect(transposeBox.FocusLost, safely(function() setTranspose(tonumber(transposeBox.Text)) end))
connect(speedDown.Activated, safely(function() setSpeed(player.speed - 0.1) end))
connect(speedUp.Activated, safely(function() setSpeed(player.speed + 0.1) end))
connect(transposeDown.Activated, safely(function() setTranspose(player.transpose - 1) end))
connect(transposeUp.Activated, safely(function() setTranspose(player.transpose + 1) end))
connect(resetTracks.Activated, safely(function()
    if not player.song then return end
    for _, track in ipairs(player.song.tracks) do track.muted, track.solo = false, false end
    player:refresh(); refreshTracks()
end))
local curveNames = {"Linear", "Fine", "Soft", "Log", "Exp"}
connect(curveButton.Activated, safely(function()
    local i = table.find(curveNames, Keyboard.curveName) or 1
    Keyboard.curveName = curveNames[i % #curveNames + 1]
    Keyboard.lastVelocity = nil
    curveButton.Text = "Curve: " .. Keyboard.curveName
end))

local minimized = false
connect(minimize.Activated, function()
    minimized = not minimized
    body.Visible = not minimized
    window.Size = UDim2.fromOffset(640, minimized and 62 or 776)
    minimize.Text = minimized and "+" or "_"
end)
local dragInput, dragOrigin, windowOrigin
connect(header.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragInput, dragOrigin, windowOrigin = input, input.Position, window.Position
    end
end)
connect(UserInputService.InputChanged, function(input)
    if not dragInput then return end
    if input.UserInputType == Enum.UserInputType.MouseMovement or input == dragInput then
        local delta = input.Position - dragOrigin
        window.Position = UDim2.new(windowOrigin.X.Scale, windowOrigin.X.Offset + delta.X, windowOrigin.Y.Scale, windowOrigin.Y.Offset + delta.Y)
    end
end)
connect(UserInputService.InputEnded, function(input) if input == dragInput then dragInput = nil end end)
connect(UserInputService.TextBoxFocused, safely(function()
    if player.playing or pendingPlay or queueJob or (inputProbe and inputProbe.running) then
        cancelStart(); cancelLoading(true); player:pause(); status("Paused while typing in Roblox. Press Play to resume.")
    end
end))
connect(UserInputService.WindowFocused, function() appHasFocus = true end)
connect(UserInputService.WindowFocusReleased, safely(function()
    appHasFocus = false
    if player.playing or pendingPlay or queueJob or (inputProbe and inputProbe.running) then
        if backgroundPlayback and backend:canBackground() then
            status("Background playback enabled / " .. backend.name)
        else
            cancelStart(); cancelLoading(true); player:pause()
            status(backgroundPlayback and "This Input needs focus. Choose virtual input for background playback."
                or "Paused because Roblox lost focus.")
        end
    end
end))
if bool(Config.Hotkeys, true) then
    connect(UserInputService.InputBegan, safely(function(input, processed)
        if input.KeyCode == Enum.KeyCode.F4 then stopPlayback(); return end
        if processed or UserInputService:GetFocusedTextBox() then return end
        if input.KeyCode == Enum.KeyCode.F6 then startOrPause()
        elseif input.KeyCode == Enum.KeyCode.F7 then stopPlayback()
        elseif input.KeyCode == Enum.KeyCode.F8 then window.Visible = not window.Visible end
    end))
end

local api = { Version = "1.0.4", InputBackend = function() return backend.name end }
function api:Destroy()
    if not alive then return end
    cancelStart()
    cancelLoading(false)
    alive, loadVersion = false, loadVersion + 1
    player.playing = false
    Keyboard:panic()
    disconnectAll(connections)
    disconnectAll(rowConnections)
    disconnectAll(queueConnections)
    table.clear(queue)
    if ownedVirtualInput then pcall(function() ownedVirtualInput:Destroy() end) end
    if gui.Parent then gui:Destroy() end
    if environment.MIDIPlusPlus == self then environment.MIDIPlusPlus = nil end
end
function api:Play() if alive and not player.playing and not pendingPlay and not loading then startOrPause() end end
function api:Pause() if alive then cancelStart(); cancelLoading(true); player:pause(); status("Paused. Queue kept.") end end
function api:Stop() if alive then stopPlayback() end end
function api:SetBackend(mode) assert(alive, "Player was destroyed"); return setBackend(mode) end
function api:TestInput() assert(alive, "Player was destroyed"); testInput() end
function api:SetBackgroundPlayback(enabled) assert(alive, "Player was destroyed"); return setBackgroundPlayback(enabled) end
function api:Seek(seconds) assert(alive and finite(seconds), "Seek expects a finite number"); player:seek(seconds) end
function api:SetSpeed(speed) assert(alive, "Player was destroyed"); setSpeed(speed) end
function api:SetTranspose(semitones) assert(alive, "Player was destroyed"); setTranspose(semitones) end
function api:LoadFile(path) assert(alive and type(path) == "string", "LoadFile expects a path"); loadSource(path, "File") end
function api:LoadURL(url) assert(alive and type(url) == "string", "LoadURL expects a URL"); loadSource(url, "URL") end
function api:LoadBase64(data) assert(alive and type(data) == "string", "LoadBase64 expects text"); loadSource(data, "Base64") end
function api:LoadData(data, name)
    assert(alive, "Player was destroyed")
    local song = Core.parse(data)
    closeFileList()
    cancelLoading(true)
    installSong(song, name or "MIDI data")
end
function api:EnqueueFile(path) assert(alive, "Player was destroyed"); return enqueueSource(path, "File") end
function api:EnqueueURL(url) assert(alive, "Player was destroyed"); return enqueueSource(url, "URL") end
function api:EnqueueBase64(data) assert(alive, "Player was destroyed"); return enqueueSource(data, "Base64") end
function api:GetQueue()
    local result = {}
    if queuedLoading then result[1] = {id = queuedLoading.id, name = queuedLoading.name, mode = queuedLoading.mode, loading = true} end
    for _, item in ipairs(queue) do result[#result + 1] = {id = item.id, name = item.name, mode = item.mode, loading = false} end
    return result
end
function api:RemoveQueued(index)
    assert(alive and finite(index) and index % 1 == 0 and index >= 1 and index <= queueCount(), "Unknown queue index")
    if queuedLoading and index == 1 then cancelLoading(false)
    else table.remove(queue, index - (queuedLoading and 1 or 0)); refreshQueue() end
end
function api:Next() assert(alive, "Player was destroyed"); advanceQueue() end
function api:ClearQueue() assert(alive, "Player was destroyed"); clearQueue() end
function api:RefreshFiles() assert(alive, "Player was destroyed"); return refreshFiles() end
function api:SetTrack(index, muted, solo)
    assert(alive and player.song and player.song.tracks[index], "Unknown track index")
    local track = player.song.tracks[index]
    if type(muted) == "boolean" then track.muted = muted end
    if type(solo) == "boolean" then track.solo = solo end
    player:refresh(); refreshTracks()
end
function api:Status()
    local midiBpm = bpmNow()
    return { playing = player.playing, pending = pendingPlay, position = player.position,
        loading = loading, queueLoading = queueJob, queueCount = queueCount(), song = player.song and songLabel.Text or nil,
        duration = player.song and player.song.duration or 0, backend = backend.name,
        speed = player.speed, transpose = player.transpose, skippedNotes = player.skipped, resyncs = player.resyncs,
        source = loadedSource and loadedSource.path or nil, binarySafe = loadedSource and loadedSource.binarySafe or false,
        midiBpm = midiBpm, bpm = midiBpm and midiBpm * player.speed or nil, inputMode = backend.mode,
        backgroundPlayback = backgroundPlayback, backgroundCapable = backend:canBackground(),
        sentDown = backend.sentDown, sentUp = backend.sentUp,
        inputTest = inputProbe and {running = inputProbe.running, cancelled = inputProbe.cancelled,
            sent = inputProbe.sent, received = inputProbe.received, processed = inputProbe.processed, backend = inputProbe.backend} or nil }
end
environment.MIDIPlusPlus = api
connect(close.Activated, function() api:Destroy() end)
connect(gui.Destroying, function() api:Destroy() end)
local uiElapsed = 0
connect(RunService.Heartbeat, safely(function(delta)
    if gui.Parent == nil then api:Destroy(); return end
    local wasPlaying = player.playing
    player:step(delta)
    if wasPlaying and not player.playing then
        if #queue > 0 then advanceQueue() else status("Finished. All piano keys released.") end
    end
    uiElapsed = uiElapsed + delta
    if uiElapsed < 0.1 then return end
    uiElapsed = 0
    playButton.Text = player.playing and "Pause" or pendingPlay and "Cancel" or "Play"
    local duration = player.song and player.song.duration or 0
    seekFill.Size = UDim2.fromScale(duration > 0 and player.position / duration or 0, 1)
    timeLabel.Text = formatTime(player.position) .. " / " .. formatTime(duration)
    local midiBpm = bpmNow()
    tempoLabel.Text = midiBpm and string.format("Tempo: %.1f BPM", midiBpm * player.speed)
        or player.song and "Timing: SMPTE" or "Tempo: -- BPM"
    testInputButton.Text = inputProbe and inputProbe.running and "Testing..." or "Test keys"
    refreshBackgroundButton()
    local active = 0
    for _ in pairs(player.voices) do active = active + 1 end
    activityLabel.Text = string.format("%d held  /  %d out of range  /  %s", active, player.skipped, backend.name)
end))
return api

end

test("entire script initializes and demo loads", function()
    local api = runScript()
    assert(environment.MIDIPlusPlus == api and api.InputBackend() == "VirtualInput")
    findText("Load demo").Activated:Fire()
    assert(api:Status().duration == 5)
    assert(findText("01  MIDI++ Luau Demo  (12 notes)"))
end)
local api = environment.MIDIPlusPlus
test("MIDI BPM defaults to 120 and scales with playback speed", function()
    assert(api:Status().midiBpm == 120 and api:Status().bpm == 120)
    api:SetSpeed(1.5); assert(api:Status().bpm == 180 and api:Status().midiBpm == 120)
    api:SetSpeed(1)
end)
test("input test uses a real Instance and observes all three keys", function()
    api:TestInput()
    for _ = 1, 8 do flushTimers() end
    local result = api:Status().inputTest
    assert(not result.running and not result.cancelled and result.sent == 3 and result.received == 3)
    assert(count(physicallyDown) == 0)
    assert(inputLog[#inputLog].kind == "Instance")
    table.clear(inputLog)
end)
test("input test reports silent APIs without claiming they worked", function()
    inputEcho = false
    api:TestInput()
    for _ = 1, 8 do flushTimers() end
    assert(api:Status().inputTest.received == 0 and api:Status().inputTest.sent == 3)
    assert(not api:Status().inputTest.running)
    inputEcho = true
    table.clear(inputLog)
end)
test("stopping an input test releases keys and cancels timers", function()
    api:TestInput(); flushTimers()
    assert(count(physicallyDown) == 1)
    api:Stop(); assert(count(physicallyDown) == 0)
    for _ = 1, 8 do flushTimers() end
    assert(api:Status().inputTest.cancelled)
    table.clear(inputLog)
end)
test("switching input backends releases the previous input", function()
    api:TestInput(); flushTimers()
    assert(api:SetBackend("VirtualInputService"))
    assert(count(physicallyDown) == 0 and api:Status().inputMode == "VirtualInputService")
    for _ = 1, 8 do flushTimers() end
    api:TestInput(); for _ = 1, 8 do flushTimers() end
    assert(inputLog[#inputLog].kind == "Service")
    api:SetBackend("Auto")
    table.clear(inputLog)
end)
test("playback refuses to start when Roblox is not focused", function()
    appActive = false
    api:Play(); flushTimers()
    assert(not api:Status().playing and not api:Status().pending)
    appActive = true
    table.clear(inputLog)
end)
test("play countdown cancellation prevents delayed notes", function()
    api:Play(); assert(api:Status().pending)
    api:Stop(); flushTimers(); RunService.Heartbeat:Fire(0.1)
    assert(not api:Status().playing and #inputLog == 0)
end)
test("play, pause, resume and stop clear physical keys", function()
    api:Play(); flushTimers(); RunService.Heartbeat:Fire(0.1)
    assert(api:Status().playing and count(physicallyDown) == 1)
    api:Play(); assert(api:Status().playing, "Play should be idempotent")
    api:Pause(); assert(count(physicallyDown) == 0)
    api:Play(); flushTimers(); assert(count(physicallyDown) == 1)
    api:Stop(); assert(count(physicallyDown) == 0 and api:Status().position == 0)
end)
test("typing and focus loss pause and release keys", function()
    api:Play(); flushTimers(); RunService.Heartbeat:Fire(0.1)
    UserInputService.TextBoxFocused:Fire({})
    assert(not api:Status().playing and count(physicallyDown) == 0)
    api:Play(); flushTimers(); UserInputService.WindowFocusReleased:Fire()
    assert(not api:Status().playing and count(physicallyDown) == 0)
end)
test("UI track mute and solo update playback", function()
    api:Stop(); api:Play(); flushTimers(); RunService.Heartbeat:Fire(0.1)
    findText("Mute").Activated:Fire(); assert(count(physicallyDown) == 0)
    findText("Muted").Activated:Fire(); assert(count(physicallyDown) == 1)
    findText("Solo").Activated:Fire(); assert(count(physicallyDown) == 1)
    api:Stop()
end)
test("speed, transpose, seek and panic hotkey", function()
    api:SetSpeed(2); api:SetTranspose(1); api:Seek(0)
    api:Play(); flushTimers(); RunService.Heartbeat:Fire(0.1)
    assert(api:Status().position == 0.2)
    assert(physicallyDown.T and not physicallyDown.LeftShift)
    local sawShift = false
    for _, input in ipairs(inputLog) do if input.code == "LeftShift" and input.down then sawShift = true end end
    assert(sawShift)
    UserInputService.InputBegan:Fire({KeyCode = Enum.KeyCode.F4}, true)
    assert(count(physicallyDown) == 0 and not api:Status().playing)
    api:SetSpeed(1); api:SetTranspose(0)
end)
test("file, URL, base64 and invalid file paths", function()
    local embedded = "TVRoZAAAAAYAAAABAeBNVHJrAAAAsQD/AxBNSURJKysgTHVhdSBEZW1vAP9RAwehIACQPFqCaIA8AHj/AQAAkEBagmiAQAB4/wEAAJBDWoJogEMAeP8BAACQSFqCaIBIAHj/AQAAkENagmiAQwB4/wEAAJBAWoJogEAAeP8BAACQPlqCaIA+AHj/AQAAkEFagmiAQQB4/wEAALBAfwCQPGQAkEBkAJBDZACQSGSDYIA8AACAQAAAgEMAAIBIAINgsEAAAP8vAA=="
    fileData, httpData = TestCore.decodeBase64(embedded), TestCore.decodeBase64(embedded)
    api:LoadFile("MIDIPlusPlus/song.mid"); assert(api:Status().duration == 5)
    api:LoadURL("https://example.test/song.mid"); assert(api:Status().duration == 5)
    api:LoadBase64(embedded); assert(api:Status().duration == 5)
    api:LoadFile("bad path"); assert(not api:Status().playing)
end)
test("file menu filters and selects MIDI files", function()
    findText("Files").Activated:Fire()
    assert(findButton("MIDIPlusPlus/song.mid") and not findButton("MIDIPlusPlus/no.txt"))
    findButton("MIDIPlusPlus/song.mid").Activated:Fire()
    assert(not findButton("MIDIPlusPlus/song.mid"), "file menu must close after selection")
end)
test("truncated binary file loads from its ASCII sidecar", function()
    local original = fileData
    fileData = original:sub(1, 40)
    fileOverrides["MIDIPlusPlus/song.mid.b64"] = "TVRoZAAAAAYAAAABAeBNVHJrAAAAsQD/AxBNSURJKysgTHVhdSBEZW1vAP9RAwehIACQPFqCaIA8AHj/AQAAkEBagmiAQAB4/wEAAJBDWoJogEMAeP8BAACQSFqCaIBIAHj/AQAAkENagmiAQwB4/wEAAJBAWoJogEAAeP8BAACQPlqCaIA+AHj/AQAAkEFagmiAQQB4/wEAALBAfwCQPGQAkEBkAJBDZACQSGSDYIA8AACAQAAAgEMAAIBIAINgsEAAAP8vAA=="
    api:LoadFile("MIDIPlusPlus/song.mid")
    assert(api:Status().duration == 5 and api:Status().binarySafe)
    assert(api:Status().source == "MIDIPlusPlus/song.mid.b64")
    fileData = original
    fileOverrides["MIDIPlusPlus/song.mid.b64"] = nil
end)
test("explicit base64 MIDI file loads", function()
    fileOverrides["MIDIPlusPlus/encoded.mid.b64"] = "TVRoZAAAAAYAAAABAeBNVHJrAAAAsQD/AxBNSURJKysgTHVhdSBEZW1vAP9RAwehIACQPFqCaIA8AHj/AQAAkEBagmiAQAB4/wEAAJBDWoJogEMAeP8BAACQSFqCaIBIAHj/AQAAkENagmiAQwB4/wEAAJBAWoJogEAAeP8BAACQPlqCaIA+AHj/AQAAkEFagmiAQQB4/wEAALBAfwCQPGQAkEBkAJBDZACQSGSDYIA8AACAQAAAgEMAAIBIAINgsEAAAP8vAA=="
    api:LoadFile("MIDIPlusPlus/encoded.mid.b64")
    assert(api:Status().duration == 5 and api:Status().binarySafe)
    fileOverrides["MIDIPlusPlus/encoded.mid.b64"] = nil
end)
test("file menu lists base64-only files and hides duplicate sidecars", function()
    local previousListing = fileListing
    fileListing = {"MIDIPlusPlus/song.mid.b64", "MIDIPlusPlus/song.mid", "MIDIPlusPlus/only.mid.b64"}
    findText("Files").Activated:Fire()
    assert(findButton("MIDIPlusPlus/song.mid") and not findButton("MIDIPlusPlus/song.mid.b64"))
    assert(findButton("MIDIPlusPlus/only.mid.b64"))
    api:LoadFile("MIDIPlusPlus/song.mid")
    assert(not findButton("MIDIPlusPlus/song.mid"), "loading must close the menu")
    fileListing = previousListing
end)
test("reinjection replaces the old UI and connections", function()
    api:Play(); flushTimers(); RunService.Heartbeat:Fire(0.1)
    local previous = api
    api = runScript()
    assert(previous ~= api and count(physicallyDown) == 0)
    local guis = 0
    for _, child in ipairs(playerGui:GetChildren()) do if child:IsA("ScreenGui") then guis = guis + 1 end end
    assert(guis == 1)
    findText("Load demo").Activated:Fire()
end)
test("velocity modifier is released before the piano note", function()
    findText("[OFF]  Velocity / Alt").Activated:Fire()
    api:Play(); flushTimers(); RunService.Heartbeat:Fire(0.1)
    assert(count(physicallyDown) == 1 and not physicallyDown.LeftAlt)
    api:Stop(); assert(count(physicallyDown) == 0)
end)
test("denied input pauses and displays the error", function()
    deniedVirtual = true
    api:Play(); flushTimers(); RunService.Heartbeat:Fire(0.1)
    assert(not api:Status().playing and #warningLog > 0)
    local found = false
    for _, child in ipairs(playerGui:GetChildren()) do
        local function scan(node)
            if type(node.Text) == "string" and node.Text:find("mock permission denied", 1, true) then found = true end
            for _, nested in ipairs(node:GetChildren()) do scan(nested) end
        end
        scan(child)
    end
    assert(found)
    deniedVirtual = false
    api:Stop()
end)
test("executor API failure falls back to VirtualInput", function()
    api:Destroy()
    keypress = function() error("not implemented") end
    keyrelease = function() error("not implemented") end
    api = runScript(); findText("Load demo").Activated:Fire()
    assert(api.InputBackend() == "Executor")
    api:Play(); flushTimers(); RunService.Heartbeat:Fire(0.1)
    assert(api.InputBackend() == "VirtualInput" and count(physicallyDown) == 1)
    api:Stop(); assert(count(physicallyDown) == 0)
end)
test("native input accepts VK codes and releases on Destroy", function()
    api:Destroy()
    keypress = function(vk) assert(type(vk) == "number"); physicallyDown[vk] = true end
    keyrelease = function(vk) physicallyDown[vk] = nil end
    api = runScript(); findText("Load demo").Activated:Fire()
    api:Play(); flushTimers(); RunService.Heartbeat:Fire(0.1)
    assert(physicallyDown[0x54])
    api:Destroy()
    assert(count(physicallyDown) == 0 and environment.MIDIPlusPlus == nil)
end)
test("custom SendKey adapter and configuration", function()
    environment.MIDIPlusPlusConfig = {Full88Keys = true, Speed = 1.5, Transpose = -12, StartDelay = 0,
        SendKey = function(code, down, vk)
            assert(code.Name and type(vk) == "number")
            physicallyDown[code.Name] = down or nil
        end}
    api = runScript(); findText("Load demo").Activated:Fire()
    api:Play(); flushTimers(); RunService.Heartbeat:Fire(0.1)
    assert(api:Status().speed == 1.5 and api:Status().transpose == -12 and count(physicallyDown) == 1)
    api:Destroy(); assert(count(physicallyDown) == 0)
end)
test("Xeno auto mode chooses its virtual input adapter over native stubs", function()
    environment.MIDIPlusPlusConfig = {BackgroundPlayback = false}
    executorIdentity = "Xeno"
    keypress = function() end
    keyrelease = function() end
    api = runScript(); assert(api.InputBackend() == "VirtualInput")
    api:TestInput(); for _ = 1, 8 do flushTimers() end
    assert(api:Status().inputTest.received == 3)
    api:Destroy()
    executorIdentity = "Mock executor"
end)
test("executor game proxies are never passed to virtual input", function()
    local originalGame, originalPress, originalRelease = game, keypress, keyrelease
    keypress, keyrelease = nil, nil
    game = setmetatable({}, {__index = function(_, key)
        local value = originalGame[key]
        if type(value) == "function" then return function(_, ...) return value(originalGame, ...) end end
        return value
    end})
    api = runScript()
    api:TestInput(); for _ = 1, 8 do flushTimers() end
    assert(api:Status().inputTest.received == 3)
    api:Destroy()
    game, keypress, keyrelease = originalGame, originalPress, originalRelease
end)
test("background mode defaults on and countdown survives focus loss", function()
    environment.MIDIPlusPlusConfig = {}
    api = runScript()
    assert(api:Status().backgroundPlayback and api:Status().backgroundCapable)
    assert(api.InputBackend() == "VirtualInput")
    findText("Load demo").Activated:Fire()
    api:Play(); assert(api:Status().pending)
    appActive = false
    UserInputService.WindowFocusReleased:Fire()
    assert(api:Status().pending)
    flushTimers(); RunService.Heartbeat:Fire(0.1)
    assert(api:Status().playing and api:Status().position == 0.1)
    assert(physicallyDown.T)
end)
test("background playback advances after repeated focus loss", function()
    local before = api:Status().position
    UserInputService.WindowFocusReleased:Fire()
    RunService.Heartbeat:Fire(0.1)
    assert(api:Status().playing and api:Status().position > before)
    api:Stop(); assert(count(physicallyDown) == 0)
end)
test("virtual input test sends three keys while Roblox is unfocused", function()
    api:TestInput(); for _ = 1, 8 do flushTimers() end
    local result = api:Status().inputTest
    assert(not result.cancelled and result.sent == 3 and result.received == 3)
    assert(count(physicallyDown) == 0 and not appActive)
end)
test("turning background off restores focus checks", function()
    api:Play(); flushTimers(); RunService.Heartbeat:Fire(0.1)
    assert(api:Status().playing)
    api:SetBackgroundPlayback(false)
    assert(not api:Status().playing and not api:Status().backgroundPlayback)
    assert(count(physicallyDown) == 0)
    local before = api:Status().sentDown
    api:Play(); flushTimers()
    assert(not api:Status().playing and api:Status().sentDown == before)
    appActive = true
    UserInputService.WindowFocused:Fire()
    api:Destroy()
end)
test("native keys pause and release on blur without new modifier presses", function()
    local nativeDowns = 0
    keypress = function(vk) nativeDowns = nativeDowns + 1; physicallyDown[vk] = true end
    keyrelease = function(vk) physicallyDown[vk] = nil end
    environment.MIDIPlusPlusConfig = {Backend = "Executor", BackgroundPlayback = true, Transpose = 1}
    api = runScript(); findText("Load demo").Activated:Fire()
    assert(not api:Status().backgroundCapable)
    api:Play(); flushTimers(); RunService.Heartbeat:Fire(0.1)
    assert(nativeDowns > 0 and count(physicallyDown) == 1)
    local before = nativeDowns
    appActive = false
    UserInputService.WindowFocusReleased:Fire()
    assert(not api:Status().playing and count(physicallyDown) == 0)
    assert(nativeDowns == before)
    api:Play(); flushTimers()
    assert(not api:Status().playing and nativeDowns == before)
    api:Destroy()
    appActive = true
    UserInputService.WindowFocused:Fire()
end)
test("enabling background switches a native adapter to virtual input", function()
    environment.MIDIPlusPlusConfig = {Backend = "Executor", BackgroundPlayback = false}
    api = runScript()
    assert(api.InputBackend() == "Executor")
    assert(api:SetBackgroundPlayback(true))
    assert(api.InputBackend() == "VirtualInput" and api:Status().backgroundCapable)
    appActive = false
    api:TestInput(); for _ = 1, 8 do flushTimers() end
    assert(api:Status().inputTest.received == 3)
    api:Destroy()
    appActive = true
    UserInputService.WindowFocused:Fire()
end)
local function newQueuePlayer(config)
    if api then api:Destroy() end
    environment.MIDIPlusPlusConfig = config or {}
    appActive, holdHttp = true, false
    keypress, keyrelease = nil, nil
    fileData, httpData = TestCore.decodeBase64("TVRoZAAAAAYAAAABAeBNVHJrAAAAsQD/AxBNSURJKysgTHVhdSBEZW1vAP9RAwehIACQPFqCaIA8AHj/AQAAkEBagmiAQAB4/wEAAJBDWoJogEMAeP8BAACQSFqCaIBIAHj/AQAAkENagmiAQwB4/wEAAJBAWoJogEAAeP8BAACQPlqCaIA+AHj/AQAAkEFagmiAQQB4/wEAALBAfwCQPGQAkEBkAJBDZACQSGSDYIA8AACAQAAAgEMAAIBIAINgsEAAAP8vAA=="), TestCore.decodeBase64("TVRoZAAAAAYAAAABAeBNVHJrAAAAsQD/AxBNSURJKysgTHVhdSBEZW1vAP9RAwehIACQPFqCaIA8AHj/AQAAkEBagmiAQAB4/wEAAJBDWoJogEMAeP8BAACQSFqCaIBIAHj/AQAAkENagmiAQwB4/wEAAJBAWoJogEAAeP8BAACQPlqCaIA+AHj/AQAAkEFagmiAQQB4/wEAALBAfwCQPGQAkEBkAJBDZACQSGSDYIA8AACAQAAAgEMAAIBIAINgsEAAAP8vAA==")
    api = runScript()
    return api
end
local function finishSong()
    api:Seek(4.9)
    RunService.Heartbeat:Fire(0.2)
end

test("queue starts without a manually loaded song and advances in order", function()
    newQueuePlayer()
    api:EnqueueFile("MIDIPlusPlus/song.mid")
    api:EnqueueURL("https://example.test/song.mid")
    api:EnqueueBase64("TVRoZAAAAAYAAAABAeBNVHJrAAAAsQD/AxBNSURJKysgTHVhdSBEZW1vAP9RAwehIACQPFqCaIA8AHj/AQAAkEBagmiAQAB4/wEAAJBDWoJogEMAeP8BAACQSFqCaIBIAHj/AQAAkENagmiAQwB4/wEAAJBAWoJogEAAeP8BAACQPlqCaIA+AHj/AQAAkEFagmiAQQB4/wEAALBAfwCQPGQAkEBkAJBDZACQSGSDYIA8AACAQAAAgEMAAIBIAINgsEAAAP8vAA==")
    assert(api:Status().queueCount == 3)
    api:Play(); flushTimers(); RunService.Heartbeat:Fire(0.1)
    assert(api:Status().playing and api:Status().queueCount == 2 and api:Status().song == "song.mid")
    finishSong(); assert(api:Status().pending and api:Status().queueCount == 1)
    flushTimers(); assert(api:Status().playing and api:GetQueue()[1].mode == "Base64")
    finishSong(); flushTimers()
    assert(api:Status().song == "Base64 MIDI" and api:Status().queueCount == 0)
    finishSong()
    assert(not api:Status().playing and not api:Status().pending and count(physicallyDown) == 0)
end)

test("adding to the queue leaves the current song playing", function()
    newQueuePlayer(); findButton("Load demo").Activated:Fire()
    api:Play(); flushTimers(); RunService.Heartbeat:Fire(0.1)
    local before = api:Status().position
    findButton("+ Queue").Activated:Fire()
    assert(api:Status().playing and api:Status().position == before and api:Status().queueCount == 1)
    assert(count(physicallyDown) == 1)
    api:Stop()
end)

test("Refresh discovers a newly copied Queen file with spaces while playing", function()
    newQueuePlayer(); findButton("Load demo").Activated:Fire()
    local oldListing = fileListing
    findButton("Refresh").Activated:Fire()
    local queen = "MIDIPlusPlus/Queen - Bohemian Rhapsody.mid"
    assert(not findButton(queen))
    api:Play(); flushTimers(); RunService.Heartbeat:Fire(0.1)
    local before = api:Status().position
    fileListing = {queen .. ".b64", queen, "MIDIPlusPlus/no.txt"}
    fileOverrides[queen .. ".b64"] = "TVRoZAAAAAYAAAABAeBNVHJrAAAAsQD/AxBNSURJKysgTHVhdSBEZW1vAP9RAwehIACQPFqCaIA8AHj/AQAAkEBagmiAQAB4/wEAAJBDWoJogEMAeP8BAACQSFqCaIBIAHj/AQAAkENagmiAQwB4/wEAAJBAWoJogEAAeP8BAACQPlqCaIA+AHj/AQAAkEFagmiAQQB4/wEAALBAfwCQPGQAkEBkAJBDZACQSGSDYIA8AACAQAAAgEMAAIBIAINgsEAAAP8vAA=="
    findButton("Refresh").Activated:Fire()
    assert(findButton(queen) and not findButton(queen .. ".b64"))
    assert(api:Status().playing and api:Status().position == before and count(physicallyDown) == 1)
    local menu = findButton(queen).Parent
    findButton("+ Queue", menu).Activated:Fire()
    assert(api:GetQueue()[1].name == "Queen - Bohemian Rhapsody.mid" and findButton(queen))
    findButton(queen).Activated:Fire(); findButton("Load").Activated:Fire()
    assert(api:Status().song == "Queen - Bohemian Rhapsody.mid" and api:Status().binarySafe)
    fileListing, fileOverrides[queen .. ".b64"] = oldListing, nil
end)

test("Queue all sorts the refreshed file list and hides duplicate sidecars", function()
    newQueuePlayer()
    local oldListing = fileListing
    fileListing = {"MIDIPlusPlus/z.mid.b64", "MIDIPlusPlus/a.MID.b64", "./MIDIPlusPlus/a.MID", "MIDIPlusPlus/no.txt"}
    findButton("Queue all").Activated:Fire()
    local items = api:GetQueue()
    assert(#items == 2 and items[1].name == "a.MID" and items[2].name == "z.mid.b64")
    findButton("Remove").Activated:Fire()
    assert(api:Status().queueCount == 1 and api:GetQueue()[1].name == "z.mid.b64")
    findButton("Clear queue").Activated:Fire(); assert(api:Status().queueCount == 0)
    fileListing = oldListing
end)

test("queue rejects empty sources and enforces its bound without stopping playback", function()
    newQueuePlayer(); findButton("Load demo").Activated:Fire()
    api:Play(); flushTimers(); RunService.Heartbeat:Fire(0.1)
    assert(not api:EnqueueFile(" "))
    for _ = 1, 128 do assert(api:EnqueueFile("MIDIPlusPlus/song.mid")) end
    local id, err = api:EnqueueFile("MIDIPlusPlus/song.mid")
    assert(not id and err:find("128", 1, true) and api:Status().playing and api:Status().queueCount == 128)
    local snapshot = api:GetQueue(); snapshot[1].name = "changed"; table.clear(snapshot)
    assert(#api:GetQueue() == 128 and api:GetQueue()[1].name == "song.mid")
    api:ClearQueue(); assert(api:Status().playing and count(physicallyDown) == 1)
    api:Stop()
end)

test("queue skips missing or malformed songs and starts the next valid song", function()
    newQueuePlayer()
    api:EnqueueFile("missing.mid")
    api:EnqueueBase64("invalid!")
    api:EnqueueFile("MIDIPlusPlus/song.mid")
    local beforeWarnings = #warningLog
    api:Next(); flushTimers(); RunService.Heartbeat:Fire(0.1)
    assert(api:Status().playing and api:Status().queueCount == 0 and api:Status().song == "song.mid")
    assert(#warningLog == beforeWarnings + 2)
    api:Stop(); api:EnqueueFile("missing.mid"); api:Next(); flushTimers()
    assert(not api:Status().loading and not api:Status().pending and not api:Status().playing)
    assert(api:Status().queueCount == 0 and count(physicallyDown) == 0)
end)

test("Loop holds the current song and Next overrides it", function()
    newQueuePlayer({Loop = true})
    findButton("Load demo").Activated:Fire()
    api:EnqueueFile("MIDIPlusPlus/song.mid")
    api:Play(); flushTimers(); finishSong()
    assert(api:Status().playing and api:Status().queueCount == 1 and api:Status().position == 0)
    findButton("Next").Activated:Fire(); flushTimers()
    assert(api:Status().playing and api:Status().song == "song.mid" and api:Status().queueCount == 0)
    assert(findText("UP NEXT  (0)  /  Loop repeats current song"))
    findButton("[ON]   Loop").Activated:Fire()
    assert(findText("UP NEXT  (0)  /  Plays in order"))
end)

test("Stop cancels the automatic next-song countdown and keeps pending songs", function()
    newQueuePlayer(); findButton("Load demo").Activated:Fire()
    api:EnqueueFile("MIDIPlusPlus/song.mid"); api:EnqueueBase64("TVRoZAAAAAYAAAABAeBNVHJrAAAAsQD/AxBNSURJKysgTHVhdSBEZW1vAP9RAwehIACQPFqCaIA8AHj/AQAAkEBagmiAQAB4/wEAAJBDWoJogEMAeP8BAACQSFqCaIBIAHj/AQAAkENagmiAQwB4/wEAAJBAWoJogEAAeP8BAACQPlqCaIA+AHj/AQAAkEFagmiAQQB4/wEAALBAfwCQPGQAkEBkAJBDZACQSGSDYIA8AACAQAAAgEMAAIBIAINgsEAAAP8vAA==")
    api:Play(); flushTimers(); finishSong()
    assert(api:Status().pending and api:Status().queueCount == 1)
    api:Stop(); flushTimers(); RunService.Heartbeat:Fire(0.1)
    assert(not api:Status().playing and not api:Status().pending and api:Status().queueCount == 1)
    assert(count(physicallyDown) == 0 and api:Status().position == 0)
end)

test("Pause cancels an in-flight queued HTTP load and preserves its order", function()
    newQueuePlayer()
    api:EnqueueURL("https://example.test/song.mid"); api:EnqueueBase64("TVRoZAAAAAYAAAABAeBNVHJrAAAAsQD/AxBNSURJKysgTHVhdSBEZW1vAP9RAwehIACQPFqCaIA8AHj/AQAAkEBagmiAQAB4/wEAAJBDWoJogEMAeP8BAACQSFqCaIBIAHj/AQAAkENagmiAQwB4/wEAAJBAWoJogEAAeP8BAACQPlqCaIA+AHj/AQAAkEFagmiAQQB4/wEAALBAfwCQPGQAkEBkAJBDZACQSGSDYIA8AACAQAAAgEMAAIBIAINgsEAAAP8vAA==")
    holdHttp = true; api:Next()
    assert(api:Status().loading and api:GetQueue()[1].loading and api:Status().queueCount == 2)
    api:Pause(); assert(not api:Status().loading and api:Status().queueCount == 2)
    holdHttp = false; flushHttp(); flushTimers()
    assert(not api:Status().playing and not api:Status().pending and not api:Status().song)
    api:Play(); flushTimers()
    assert(api:Status().playing and api:Status().queueCount == 1 and api:GetQueue()[1].mode == "Base64")
end)

test("Next skips a downloading entry and ignores its late HTTP response", function()
    newQueuePlayer()
    api:EnqueueURL("https://example.test/song.mid"); api:EnqueueBase64("TVRoZAAAAAYAAAABAeBNVHJrAAAAsQD/AxBNSURJKysgTHVhdSBEZW1vAP9RAwehIACQPFqCaIA8AHj/AQAAkEBagmiAQAB4/wEAAJBDWoJogEMAeP8BAACQSFqCaIBIAHj/AQAAkENagmiAQwB4/wEAAJBAWoJogEAAeP8BAACQPlqCaIA+AHj/AQAAkEFagmiAQQB4/wEAALBAfwCQPGQAkEBkAJBDZACQSGSDYIA8AACAQAAAgEMAAIBIAINgsEAAAP8vAA==")
    holdHttp = true; api:Next(); api:Next(); flushTimers()
    assert(api:Status().song == "Base64 MIDI" and api:Status().playing and api:Status().queueCount == 0)
    holdHttp = false; flushHttp()
    assert(api:Status().song == "Base64 MIDI" and api:Status().playing)
end)

test("Clear queue cancels a downloading entry without starting it later", function()
    newQueuePlayer(); api:EnqueueURL("https://example.test/song.mid")
    holdHttp = true; api:Next(); api:ClearQueue()
    holdHttp = false; flushHttp(); flushTimers()
    assert(api:Status().queueCount == 0 and not api:Status().loading and not api:Status().pending)
    assert(not api:Status().playing and count(physicallyDown) == 0)
end)

test("manual load replaces a queued HTTP job and keeps that entry for later", function()
    newQueuePlayer(); api:EnqueueURL("https://example.test/song.mid")
    holdHttp = true; api:Next(); api:LoadData(fileData, "Manual song")
    holdHttp = false; flushHttp(); flushTimers()
    assert(api:Status().song == "Manual song" and api:Status().queueCount == 1 and not api:Status().pending)
    assert(api:GetQueue()[1].mode == "URL" and not api:GetQueue()[1].loading)
end)

test("RemoveQueued cancels a downloading entry and leaves the following songs", function()
    newQueuePlayer(); api:EnqueueURL("https://example.test/song.mid"); api:EnqueueBase64("TVRoZAAAAAYAAAABAeBNVHJrAAAAsQD/AxBNSURJKysgTHVhdSBEZW1vAP9RAwehIACQPFqCaIA8AHj/AQAAkEBagmiAQAB4/wEAAJBDWoJogEMAeP8BAACQSFqCaIBIAHj/AQAAkENagmiAQwB4/wEAAJBAWoJogEAAeP8BAACQPlqCaIA+AHj/AQAAkEFagmiAQQB4/wEAALBAfwCQPGQAkEBkAJBDZACQSGSDYIA8AACAQAAAgEMAAIBIAINgsEAAAP8vAA==")
    holdHttp = true; api:Next(); api:RemoveQueued(1)
    holdHttp = false; flushHttp(); flushTimers()
    assert(api:Status().queueCount == 1 and api:GetQueue()[1].mode == "Base64" and not api:Status().loading)
    assert(not pcall(function() api:RemoveQueued(2) end))
    api:Next(); flushTimers(); assert(api:Status().playing and api:Status().song == "Base64 MIDI")
end)

test("typing pauses a queued download while background focus loss can keep it running", function()
    newQueuePlayer(); api:EnqueueURL("https://example.test/song.mid")
    holdHttp = true; api:Next()
    appActive = false; UserInputService.WindowFocusReleased:Fire()
    assert(api:Status().queueLoading)
    UserInputService.TextBoxFocused:Fire({})
    assert(not api:Status().loading and api:Status().queueCount == 1)
    holdHttp = false; flushHttp(); flushTimers()
    assert(not api:Status().playing)
    appActive = true; UserInputService.WindowFocused:Fire()
end)

test("Destroy invalidates a queued download and clears its connections", function()
    newQueuePlayer(); api:EnqueueURL("https://example.test/song.mid")
    holdHttp = true; api:Next(); api:Destroy()
    holdHttp = false; flushHttp(); flushTimers(); RunService.Heartbeat:Fire(0.1)
    assert(environment.MIDIPlusPlus == nil and count(physicallyDown) == 0)
    assert(api:Status().queueCount == 0 and not api:Status().playing)
end)
print(string.format("%d integration tests passed (mock Roblox / executor)", tests))
