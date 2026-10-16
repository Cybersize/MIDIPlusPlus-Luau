-- MIDI++ Luau GitHub entrypoint.
-- SPDX-License-Identifier: GPL-3.0-only
-- https://github.com/Cybersize/MIDIPlusPlus-Luau
-- Core/UI libraries use one immutable source commit to keep them compatible.
local LIBRARY_BASE = "https://raw.githubusercontent.com/Cybersize/MIDIPlusPlus-Luau/e6536cf72df1f47be505131ccad03653bf45bd5b/"
local DEMO_BASE64 = "TVRoZAAAAAYAAAABAeBNVHJrAAAAsQD/AxBNSURJKysgTHVhdSBEZW1vAP9RAwehIACQPFqCaIA8AHj/AQAAkEBagmiAQAB4/wEAAJBDWoJogEMAeP8BAACQSFqCaIBIAHj/AQAAkENagmiAQwB4/wEAAJBAWoJogEAAeP8BAACQPlqCaIA+AHj/AQAAkEFagmiAQQB4/wEAALBAfwCQPGQAkEBkAJBDZACQSGSDYIA8AACAQAAAgEMAAIBIAINgsEAAAP8vAA=="

assert(type(loadstring) == "function", "MIDI++ needs the executor's loadstring function")
local function importLibrary(path)
    local ok, source = pcall(function() return game:HttpGet(LIBRARY_BASE .. path) end)
    assert(ok, "MIDI++ could not download " .. path .. ": " .. tostring(source))
    assert(type(source) == "string" and #source > 0, "MIDI++ received an empty library: " .. path)
    local chunk, compileError = loadstring(source, "@MIDIPlusPlus/" .. path)
    assert(chunk, "MIDI++ could not compile " .. path .. ": " .. tostring(compileError))
    local initialized, result = pcall(chunk)
    assert(initialized, "MIDI++ could not initialize " .. path .. ": " .. tostring(result))
    return result
end

local Core = importLibrary("lib/Core.lua")
assert(type(Core) == "table" and type(Core.parse) == "function" and type(Core.newPlayer) == "function",
    "MIDI++ Core library has an invalid export")
local createPlayer = importLibrary("lib/Player.lua")
assert(type(createPlayer) == "function", "MIDI++ Player library has an invalid export")
return createPlayer(Core, DEMO_BASE64)
