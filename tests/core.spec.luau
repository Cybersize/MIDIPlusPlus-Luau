local Core = require("../lib/Core")
local passed = 0
local function test(name, callback)
    local ok, err = pcall(callback)
    if not ok then error("FAIL " .. name .. ": " .. tostring(err), 0) end
    passed = passed + 1
    print("PASS " .. name)
end
local function near(a, b) assert(math.abs(a - b) < 0.0000001, tostring(a) .. " ~= " .. tostring(b)) end
local function bytes(...) return string.char(...) end
local function u32(n) return bytes(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256) end
local function u16(n) return bytes(math.floor(n / 256) % 256, n % 256) end
local function vlq(n)
    local list = {n % 128}; n = math.floor(n / 128)
    while n > 0 do table.insert(list, 1, n % 128 + 128); n = math.floor(n / 128) end
    return bytes(table.unpack(list))
end
local function event(delta, ...) return vlq(delta) .. bytes(...) end
local eot = event(0, 255, 47, 0)
local function midi(tracks, division, format)
    local result = "MThd" .. u32(6) .. u16(format or (#tracks == 1 and 0 or 1)) .. u16(#tracks) .. u16(division or 480)
    for _, track in ipairs(tracks) do result = result .. "MTrk" .. u32(#track) .. track end
    return result
end
local function simple(note)
    return Core.parse(midi({event(0, 144, note or 60, 100) .. event(480, 128, note or 60, 0) .. eot}))
end
local function setup(song)
    local log = {}
    local player = Core.newPlayer({
        noteOn = function(v) log[#log + 1] = {"on", v.note, v.id} end,
        noteOff = function(v) log[#log + 1] = {"off", v.note, v.id} end,
        sustain = function(down) log[#log + 1] = {"pedal", down} end,
        panic = function() log[#log + 1] = {"panic"} end,
    })
    player:load(song)
    return player, log
end
local function count(tableValue) local n = 0; for _ in pairs(tableValue) do n = n + 1 end; return n end
local function rejects(data)
    local ok = pcall(Core.parse, data)
    assert(not ok, "malformed MIDI was accepted")
end

test("format 0 / default tempo / note off", function()
    local song = simple()
    near(song.duration, 0.5)
    assert(#song.events == 2 and song.tracks[1].notes == 1 and song.format == 0)
    assert(song.events[1].note == 60 and song.events[2].kind == "off")
end)
test("format 1 / shared tempo map / trailing silence", function()
    local conductor = event(0, 255, 81, 3, 7, 161, 32) .. event(480, 255, 81, 3, 15, 66, 64) .. event(960, 255, 47, 0)
    local notes = event(0, 144, 60, 100) .. event(960, 128, 60, 0) .. eot
    local song = Core.parse(midi({conductor, notes}))
    near(song.events[2].time, 1.5)
    near(song.duration, 2.5)
    assert(song.tempos[3].bpm == 60)
end)
test("BPM lookup follows tempo changes at the playhead", function()
    local conductor = event(0, 255, 81, 3, 7, 161, 32) .. event(480, 255, 81, 3, 15, 66, 64) .. event(960, 255, 47, 0)
    local song = Core.parse(midi({conductor}))
    assert(song.hasTempo and song.timing == "PPQN")
    near(Core.tempoAt(song, 0), 120)
    near(Core.tempoAt(song, 0.49), 120)
    near(Core.tempoAt(song, 0.5), 60)
    near(Core.tempoAt(song, 1), 60)
    local noTempo = simple()
    assert(not noTempo.hasTempo)
    near(Core.tempoAt(noTempo, 0.1), 120)
end)
test("running status / velocity-zero note off", function()
    local song = Core.parse(midi({event(0, 144, 60, 90) .. event(120, 64, 90) .. event(120, 60, 0) .. event(0, 64, 0) .. eot}))
    assert(#song.events == 4 and song.events[3].kind == "off")
    near(song.duration, 0.25)
end)
test("program change and channel pressure have one data byte", function()
    local song = Core.parse(midi({event(0, 192, 0) .. event(0, 208, 45) .. event(0, 144, 60, 90) .. event(10, 128, 60, 0) .. eot}))
    assert(#song.events == 2)
end)
test("SysEx and unknown meta payloads are skipped", function()
    local song = Core.parse(midi({event(0, 240, 3, 1, 2, 247) .. event(0, 255, 9, 2, 88, 89) .. event(0, 144, 60, 90) .. eot}))
    assert(#song.events == 1)
end)
test("track names are safe to display", function()
    local song = Core.parse(midi({event(0, 255, 3, 4, 65, 0, 255, 66) .. eot}))
    assert(song.tracks[1].name == "A??B")
end)
test("SMPTE 25fps and drop-frame 29.97fps", function()
    local track = event(1000, 144, 60, 90) .. eot
    near(Core.parse(midi({track}, (256 - 25) * 256 + 40)).events[1].time, 1)
    near(Core.parse(midi({track}, (256 - 29) * 256 + 100)).events[1].time, 1000 / (30000 / 1001 * 100))
end)
test("RIFF/RMID with padded unknown chunk", function()
    local smf = midi({eot})
    local function le(n) return bytes(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, 0) end
    local payload = "RMIDJUNK" .. le(1) .. "x\0data" .. le(#smf) .. smf
    assert(Core.parse("RIFF" .. le(#payload) .. payload).format == 0)
end)
test("truncation at every byte is rejected", function()
    local smf = midi({event(0, 144, 60, 90) .. event(480, 128, 60, 0) .. eot})
    for i = 0, #smf - 1 do rejects(smf:sub(1, i)) end
end)
test("malformed events and unsupported format are rejected", function()
    rejects(midi({event(0, 60, 90) .. eot}))
    rejects(midi({event(0, 255, 81, 3, 0, 0, 0) .. eot}))
    rejects(midi({event(0, 144, 255, 90) .. eot}))
    rejects(midi({bytes(129, 128, 128, 128, 0) .. eot}))
    rejects(midi({eot}, 480, 2))
    rejects(midi({eot}, 0))
    rejects(midi({eot, eot}, 480, 0))
end)
test("parser limits", function()
    local data = midi({eot})
    assert(not pcall(Core.parse, data, {maxBytes = 4}))
    assert(not pcall(Core.parse, midi({event(0, 144, 60, 90) .. eot}), {maxEvents = 1}))
end)
test("base64 roundtrip known vectors and invalid padding", function()
    assert(Core.decodeBase64("TUlESQ==") == "MIDI")
    assert(Core.decodeBase64("data:audio/midi;base64, AAEC\n /w==") == bytes(0, 1, 2, 255))
    for _, invalid in ipairs({"A", "====", "AA=A", "AA==AAAA", "!!!!"}) do assert(not pcall(Core.decodeBase64, invalid)) end
end)
test("sidecar preserves MIDI through a text-mode reader", function()
    local data = midi({event(0, 144, 60, 90) .. event(26, 128, 60, 0) .. eot})
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local function encode(source: string)
        local out: {string} = {}
        for i = 1, #source, 3 do
            local a, b, c = source:byte(i, i + 2)
            local value = a * 65536 + (b or 0) * 256 + (c or 0)
            out[#out + 1] = alphabet:sub(math.floor(value / 262144) % 64 + 1, math.floor(value / 262144) % 64 + 1)
            out[#out + 1] = alphabet:sub(math.floor(value / 4096) % 64 + 1, math.floor(value / 4096) % 64 + 1)
            out[#out + 1] = b and alphabet:sub(math.floor(value / 64) % 64 + 1, math.floor(value / 64) % 64 + 1) or "="
            out[#out + 1] = c and alphabet:sub(value % 64 + 1, value % 64 + 1) or "="
        end
        return table.concat(out)
    end
    local rawRead = false
    local song, source = Core.loadFile("song.mid", function(path)
        if path == "song.mid.b64" then return encode(data) end
        rawRead = true
        return data:sub(1, data:find(string.char(26), 1, true) - 1)
    end)
    assert(not rawRead and source.binarySafe and source.path == "song.mid.b64")
    near(song.duration, 26 * 0.5 / 480)
    assert(#song.events == 2)
end)
test("binary reader works when no sidecar exists", function()
    local data = midi({eot})
    local song, source = Core.loadFile("song.mid", function(path)
        assert(path == "song.mid", "missing sidecar"); return data
    end)
    assert(song.format == 0 and not source.binarySafe)
end)
test("explicit base64 files and damaged sidecars", function()
    local emptyMidi = "TVRoZAAAAAYAAAABAeBNVHJrAAAABAD/LwA="
    local song, source = Core.loadFile("empty.mid.b64", function() return emptyMidi end)
    assert(song.format == 0 and source.binarySafe)
    local ok, err = pcall(Core.loadFile, "song.mid", function(path)
        if path == "song.mid.b64" then return "broken" end
        error("must not use raw bytes")
    end)
    assert(not ok and tostring(err):find("invalid .b64 sidecar", 1, true))
end)
test("truncated file explains how to make a binary-safe sidecar", function()
    local ok, err = pcall(Core.loadFile, "song.mid", function(path)
        assert(path == "song.mid", "missing sidecar"); return "MThd"
    end)
    assert(not ok and tostring(err):find("Convert-MIDI", 1, true))
    assert(tostring(err):find("song.mid.b64", 1, true))
end)
test("complete 61 and 88 key mappings", function()
    local limited, full = Core.keymap(false), Core.keymap(true)
    assert(count(limited) == 61 and count(full) == 88)
    assert(limited[36] == "1" and limited[60] == "t" and limited[96] == "m")
    assert(full[21] == "ctrl+1" and full[108] == "ctrl+j")
    assert(full[97] == "ctrl+y")
end)
test("five velocity curves return a valid 32-step key", function()
    assert(#Core.velocityKeys == 32)
    for _, curve in pairs(Core.curves) do
        assert(#curve == 32)
        for velocity = 1, 127 do assert(#Core.velocityKey(velocity, curve) == 1) end
    end
    assert(Core.velocityKey(1) == "1" and Core.velocityKey(127) == "c")
end)
test("play, pause and resume retain held notes", function()
    local p, log = setup(simple())
    p:play(); p:step(0.1)
    assert(count(p.voices) == 1 and p.playing)
    p:pause(); assert(not p.playing and count(p.voices) == 1 and not p.outputActive)
    local before = #log
    p:play(); assert(#log > before and p.outputActive)
    p:step(0.4); assert(not p.playing and count(p.voices) == 0)
end)
test("speed applies without shifting the playhead", function()
    local p = setup(simple())
    p:play(); p:step(0.1); p.speed = 2; p:step(0.1)
    near(p.position, 0.3)
end)
test("FIFO pairing for overlapping same-pitch notes", function()
    local song = Core.parse(midi({event(0, 144, 60, 90) .. event(0, 144, 60, 100) .. event(120, 128, 60, 0) .. event(120, 128, 60, 0) .. eot}))
    local p = setup(song)
    p:play(); p:step(0); assert(count(p.voices) == 2)
    p:step(0.125); assert(count(p.voices) == 1 and p.voices[2])
    p:step(0.125); assert(count(p.voices) == 0)
end)
test("seek reconstructs notes and pedal tails", function()
    local song = Core.parse(midi({event(0, 176, 64, 127) .. event(0, 144, 60, 90) .. event(240, 128, 60, 0) .. event(720, 176, 64, 0) .. eot}))
    local p, log = setup(song)
    p:seek(0.5); assert(count(p.voices) == 0 and count(p.tails) == 1 and p.pedals[1])
    p:play()
    assert(log[#log - 1][1] == "on" and log[#log][1] == "off")
    p:step(0.5); assert(count(p.tails) == 0 and not p.playing)
    p:seek(0.1); assert(count(p.voices) == 1 and count(p.tails) == 0)
end)
test("track solo, mute and drum filtering", function()
    local a = event(0, 144, 60, 90) .. event(480, 128, 60, 0) .. eot
    local b = event(0, 145, 64, 90) .. event(480, 129, 64, 0) .. eot
    local drums = event(0, 153, 67, 90) .. event(480, 137, 67, 0) .. eot
    local p = setup(Core.parse(midi({a, b, drums})))
    p:play(); p:step(0.1); assert(count(p.voices) == 2)
    p.song.tracks[1].solo = true; p:refresh(); assert(count(p.voices) == 1)
    p.song.tracks[1].muted = true; p:refresh(); assert(count(p.voices) == 0)
    p.song.tracks[1].solo = false; p.skipDrums = false; p:refresh(); assert(count(p.voices) == 2)
end)
test("transpose, octave folding and out-of-range counts", function()
    local p = setup(simple(24))
    p:play(); p:step(0.1); assert(count(p.voices) == 0 and p.skipped == 1)
    p.fold = true; p:refresh(); assert(count(p.voices) == 1)
    for _, voice in pairs(p.voices) do assert(voice.note == 36) end
    p.transpose = 12; p:refresh()
    for _, voice in pairs(p.voices) do assert(voice.note == 36) end
    p:stop(); near(p.position, 0); assert(count(p.voices) == 0)
end)
test("all-notes-off and all-sound-off controllers", function()
    local song = Core.parse(midi({event(0, 176, 64, 127) .. event(0, 144, 60, 90) .. event(120, 176, 123, 0) .. event(120, 176, 120, 0) .. event(480, 255, 47, 0)}))
    local p = setup(song)
    p:play(); p:step(0.125); assert(count(p.voices) == 0 and count(p.tails) == 1)
    p:step(0.125); assert(count(p.tails) == 0 and not p.pedals[1])
end)
test("stall recovery does not burst expired notes", function()
    local track = event(0, 144, 60, 90) .. event(120, 128, 60, 0) .. event(120, 144, 64, 90) .. event(240, 128, 64, 0) .. event(1440, 255, 47, 0)
    local p, log = setup(Core.parse(midi({track})))
    p:play(); local before = #log; p:step(1)
    assert(p.resyncs == 1 and count(p.voices) == 0)
    for i = before + 1, #log do assert(log[i][1] ~= "on") end
end)
test("loop releases keys and resets to the beginning", function()
    local p = setup(simple()); p.looped = true; p:play(); p:step(0.5)
    assert(p.playing and p.position == 0 and count(p.voices) == 0)
    p:step(0); assert(count(p.voices) == 1)
end)
test("stable simultaneous ordering and multi-track channels", function()
    local a = event(0, 144, 60, 90) .. event(480, 128, 60, 0) .. eot
    local b = event(0, 144, 60, 95) .. event(240, 128, 60, 0) .. event(240, 255, 47, 0)
    local p = setup(Core.parse(midi({a, b})))
    p:play(); p:step(0.25)
    assert(count(p.voices) == 1)
    for _, voice in pairs(p.voices) do assert(voice.track == 1) end
end)
print(string.format("%d core tests passed", passed))
