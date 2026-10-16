-- SPDX-License-Identifier: GPL-3.0-only
-- Roblox UI and executor adapter. Called by the GitHub entrypoint.
return function(Core, DEMO_BASE64)
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

-- Executors disagree about input APIs. All availability checks are local; no
-- executor name/version is treated as a guarantee that key injection works.
local virtualInput
pcall(function() virtualInput = game:GetService("VirtualInputManager") end)
local nativeAvailable = type(keypress) == "function" and type(keyrelease) == "function"
local backend = { name = "Unavailable", used = false }
local requestedBackend = Config.Backend or "Auto"
if type(Config.SendKey) == "function" then backend.name = "Custom"
elseif requestedBackend == "Executor" and nativeAvailable then backend.name = "Executor"
elseif requestedBackend == "VirtualInput" and virtualInput then backend.name = "VirtualInput"
elseif requestedBackend == "Auto" then
    if nativeAvailable then backend.name = "Executor"
    elseif virtualInput then backend.name = "VirtualInput" end
end
function backend:send(info, down)
    if self.name == "Custom" then
        Config.SendKey(info.code, down, info.vk)
    elseif self.name == "Executor" then
        local ok, err = pcall(down and keypress or keyrelease, info.vk)
        if not ok and requestedBackend == "Auto" and not self.used and virtualInput then
            self.name = "VirtualInput"
            virtualInput:SendKeyEvent(down, info.code, false, game)
        elseif not ok then error("Executor input failed: " .. tostring(err), 0) end
    elseif self.name == "VirtualInput" then
        virtualInput:SendKeyEvent(down, info.code, false, game)
    else
        error("No input backend. Use an executor with keypress/keyrelease or permitted VirtualInputManager access.", 0)
    end
    self.used = true
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
local connections, rowConnections = {}, {}
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
local window = make("Frame", {Name = "Window", Size = UDim2.fromOffset(640, 642),
    Position = UDim2.new(0.5, 0, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundColor3 = colors.background, BorderSizePixel = 0, Active = true}, gui)
round(window, 12)
make("UIStroke", {Color = Color3.fromRGB(61, 76, 88), Thickness = 1}, window)
local scale = make("UIScale", {Scale = 1}, window)
local function scaleWindow()
    local camera = Workspace.CurrentCamera
    if camera then scale.Scale = math.clamp(math.min((camera.ViewportSize.X - 24) / 640, (camera.ViewportSize.Y - 24) / 642), 0.3, 1) end
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
label(header, "LUAU  /  VIRTUAL PIANO", 23, 37, 360, 16, 10, colors.muted)
local minimize = button(header, "_", 548, 16, 30, 30)
local close = button(header, "X", 586, 16, 30, 30)
local body = make("Frame", {Position = UDim2.fromOffset(0, 62), Size = UDim2.fromOffset(640, 580), BackgroundTransparency = 1}, window)
label(body, "MIDI SOURCE", 22, 3, 200, 20, 11, colors.muted)
local modeButton = button(body, "File", 22, 29, 78, 34)
local sourceBox = box(body, Config.DefaultFile or "MIDIPlusPlus/song.mid", "Path inside the executor workspace", 108, 29, 384, 34)
local loadButton = button(body, "Load", 500, 29, 116, 34, true)
local filesButton = button(body, "Files", 22, 71, 78, 26)
local demoButton = button(body, "Load demo", 108, 71, 104, 26)
label(body, "Files are relative to your executor's workspace.", 222, 72, 394, 24, 11, colors.muted)
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
local timeLabel = label(body, "0:00 / 0:00", 22, 231, 240, 20, 12, colors.muted)
local activityLabel = label(body, "", 280, 231, 336, 20, 11, colors.muted)
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

local fail
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
toggle("Loop", 422, 345, function() return player.looped end, function(value) player.looped = value end)
local curveButton = button(body, "Curve: " .. Keyboard.curveName, 22, 385, 192, 28)
label(body, "Velocity / 88 keys require matching piano controls.", 222, 386, 394, 26, 10, colors.muted)
label(body, "TRACKS", 22, 427, 180, 20, 11, colors.muted)
local resetTracks = button(body, "Reset tracks", 500, 422, 116, 25)
local tracksFrame = make("ScrollingFrame", {Position = UDim2.fromOffset(22, 455), Size = UDim2.fromOffset(594, 70),
    BackgroundColor3 = colors.panel, BorderSizePixel = 0, CanvasSize = UDim2.fromOffset(0, 0),
    ScrollBarThickness = 4, ScrollBarImageColor3 = colors.muted, ScrollingDirection = Enum.ScrollingDirection.Y}, body)
round(tracksFrame)
local statusLabel = label(body, "Input: " .. backend.name .. " (checked when playing)", 22, 533, 594, 24, 11, colors.accent)
statusLabel.TextWrapped, statusLabel.TextTruncate = true, Enum.TextTruncate.None
label(body, "F6 play/pause  /  F7 stop  /  F8 show/hide  /  F4 panic", 22, 560, 594, 16, 10, colors.muted)

local function status(message, failed)
    if not alive then return end
    statusLabel.Text = tostring(message):gsub("[\r\n]", " "):sub(1, 240)
    statusLabel.TextColor3 = failed and colors.danger or colors.accent
end
local function cancelStart()
    playVersion = playVersion + 1
    pendingPlay = false
end
fail = function(err)
    cancelStart()
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
local sourceMode, loading = "File", false
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
local function installSong(song, name)
    cancelStart()
    player:load(song)
    songLabel.Text = name
    local notes = 0
    for _, track in ipairs(song.tracks) do notes = notes + track.notes end
    metaLabel.Text = string.format("%s  /  %d tracks  /  %d notes  /  MIDI format %d", formatTime(song.duration), #song.tracks, notes, song.format)
    refreshTracks()
    status("Loaded. Open the game's piano, then press Play. Input: " .. backend.name)
end
local function loadSource(value, mode)
    if loading then status("A MIDI is already loading."); return end
    cancelStart()
    player:stop()
    loadVersion = loadVersion + 1
    local version = loadVersion
    loading, loadButton.Text = true, "Loading..."
    status("Loading MIDI...")
    task.spawn(function()
        local ok, songOrError = pcall(function()
            local data
            if mode == "Raw" then data = value
            elseif mode == "File" then
                assert(type(readfile) == "function", "This executor has no readfile. Use URL, Base64, or Demo.")
                data = readfile(value)
            elseif mode == "URL" then data = fetchMidi(value)
            elseif mode == "Base64" then
                assert(#value <= 24 * 1024 * 1024, "Base64 source is too large")
                data = Core.decodeBase64(value)
            else error("Unknown source mode") end
            return Core.parse(data)
        end)
        if not alive or version ~= loadVersion then return end
        loading, loadButton.Text = false, "Load"
        if ok then
            local name = mode == "Raw" and "Demo - MIDI++ Luau" or mode == "Base64" and "Base64 MIDI" or value:match("([^/\\?]+)%??[^/\\]*$") or "MIDI"
            local installed, err = pcall(installSong, songOrError, name:sub(1, 120))
            if not installed then fail(err) end
        else status(songOrError, true) end
    end)
end
connect(loadButton.Activated, safely(function() loadSource(trim(sourceBox.Text), sourceMode) end))
connect(demoButton.Activated, safely(function() loadSource(Core.decodeBase64(DEMO_BASE64), "Raw") end))

local fileList
connect(filesButton.Activated, safely(function()
    if fileList then fileList:Destroy(); fileList = nil; return end
    assert(type(listfiles) == "function", "This executor has no listfiles; type the relative file path instead")
    local folder = Config.Folder or "MIDIPlusPlus"
    if type(makefolder) == "function" then pcall(makefolder, folder) end
    local files, filtered = listfiles(folder), {}
    for _, file in ipairs(files) do
        if file:lower():match("%.midi?$") or file:lower():match("%.rmi$") then filtered[#filtered + 1] = file end
    end
    table.sort(filtered)
    fileList = make("ScrollingFrame", {Position = UDim2.fromOffset(22, 99), Size = UDim2.fromOffset(594, 158),
        BackgroundColor3 = colors.panel, BorderSizePixel = 0, ScrollBarThickness = 5, ZIndex = 20,
        CanvasSize = UDim2.fromOffset(0, math.max(1, #filtered) * 30)}, body)
    round(fileList)
    if #filtered == 0 then
        local empty = label(fileList, "No MIDI files in " .. folder .. ". Click Files to close.", 10, 0, 570, 30, 12)
        empty.ZIndex = 21
    end
    for i, path in ipairs(filtered) do
        local b = button(fileList, path, 4, (i - 1) * 30, 576, 28)
        b.ZIndex = 21
        -- Destroying the file menu also disconnects these Instance signals.
        b.Activated:Connect(function()
            setSourceMode("File"); sourceBox.Text = path
            fileList:Destroy(); fileList = nil
        end)
    end
end))

local function startOrPause()
    if player.playing or pendingPlay then
        cancelStart(); player:pause(); status("Paused."); return
    end
    if loading then status("Wait for the MIDI to finish loading."); return end
    if not player.song then status("Load a MIDI or the demo first.", true); return end
    if backend.name == "Unavailable" then status("No input backend is available in this executor.", true); return end
    local focused = UserInputService:GetFocusedTextBox()
    if focused then focused:ReleaseFocus() end
    cancelStart()
    local version = playVersion
    pendingPlay = true
    local delay = finite(Config.StartDelay) and math.clamp(Config.StartDelay, 0, 10) or 1.5
    status(string.format("Starting in %.1fs. Focus the game's piano.", delay))
    task.delay(delay, safely(function()
        if version ~= playVersion or not pendingPlay then return end
        pendingPlay = false
        if UserInputService:GetFocusedTextBox() then status("Close the text box before playing.", true); return end
        local ok, message = player:play()
        status(ok and ("Playing / " .. backend.name) or message, not ok)
    end))
end
local function stopPlayback()
    cancelStart(); player:stop(); status("Stopped. All piano keys released.")
end
connect(playButton.Activated, safely(startOrPause))
connect(stopButton.Activated, safely(stopPlayback))
connect(panicButton.Activated, safely(stopPlayback))
connect(restartButton.Activated, safely(function()
    cancelStart(); player:stop(); startOrPause()
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
    window.Size = UDim2.fromOffset(640, minimized and 62 or 642)
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
    if player.playing or pendingPlay then cancelStart(); player:pause(); status("Paused while typing. Press Play to resume.") end
end))
if bool(Config.PauseOnFocusLoss, true) then
    connect(UserInputService.WindowFocusReleased, safely(function()
        if player.playing or pendingPlay then cancelStart(); player:pause(); status("Paused because Roblox lost focus.") end
    end))
end
if bool(Config.Hotkeys, true) then
    connect(UserInputService.InputBegan, safely(function(input, processed)
        if input.KeyCode == Enum.KeyCode.F4 then stopPlayback(); return end
        if processed or UserInputService:GetFocusedTextBox() then return end
        if input.KeyCode == Enum.KeyCode.F6 then startOrPause()
        elseif input.KeyCode == Enum.KeyCode.F7 then stopPlayback()
        elseif input.KeyCode == Enum.KeyCode.F8 then window.Visible = not window.Visible end
    end))
end

local api = { Version = "1.0.0", InputBackend = function() return backend.name end }
function api:Destroy()
    if not alive then return end
    cancelStart()
    alive, loadVersion = false, loadVersion + 1
    player.playing = false
    Keyboard:panic()
    disconnectAll(connections)
    disconnectAll(rowConnections)
    if gui.Parent then gui:Destroy() end
    if environment.MIDIPlusPlus == self then environment.MIDIPlusPlus = nil end
end
function api:Play() if alive and not player.playing and not pendingPlay then startOrPause() end end
function api:Pause() if alive then cancelStart(); player:pause(); status("Paused.") end end
function api:Stop() if alive then stopPlayback() end end
function api:Seek(seconds) assert(alive and finite(seconds), "Seek expects a finite number"); player:seek(seconds) end
function api:SetSpeed(speed) assert(alive, "Player was destroyed"); setSpeed(speed) end
function api:SetTranspose(semitones) assert(alive, "Player was destroyed"); setTranspose(semitones) end
function api:LoadFile(path) assert(alive and type(path) == "string", "LoadFile expects a path"); loadSource(path, "File") end
function api:LoadURL(url) assert(alive and type(url) == "string", "LoadURL expects a URL"); loadSource(url, "URL") end
function api:LoadBase64(data) assert(alive and type(data) == "string", "LoadBase64 expects text"); loadSource(data, "Base64") end
function api:LoadData(data, name)
    assert(alive, "Player was destroyed")
    loadVersion = loadVersion + 1
    loading, loadButton.Text = false, "Load"
    installSong(Core.parse(data), name or "MIDI data")
end
function api:SetTrack(index, muted, solo)
    assert(alive and player.song and player.song.tracks[index], "Unknown track index")
    local track = player.song.tracks[index]
    if type(muted) == "boolean" then track.muted = muted end
    if type(solo) == "boolean" then track.solo = solo end
    player:refresh(); refreshTracks()
end
function api:Status()
    return { playing = player.playing, pending = pendingPlay, position = player.position,
        duration = player.song and player.song.duration or 0, backend = backend.name,
        speed = player.speed, transpose = player.transpose, skippedNotes = player.skipped, resyncs = player.resyncs }
end
environment.MIDIPlusPlus = api
connect(close.Activated, function() api:Destroy() end)
connect(gui.Destroying, function() api:Destroy() end)
local uiElapsed = 0
connect(RunService.Heartbeat, safely(function(delta)
    if gui.Parent == nil then api:Destroy(); return end
    local wasPlaying = player.playing
    player:step(delta)
    if wasPlaying and not player.playing then status("Finished. All piano keys released.") end
    uiElapsed = uiElapsed + delta
    if uiElapsed < 0.1 then return end
    uiElapsed = 0
    playButton.Text = player.playing and "Pause" or pendingPlay and "Cancel" or "Play"
    local duration = player.song and player.song.duration or 0
    seekFill.Size = UDim2.fromScale(duration > 0 and player.position / duration or 0, 1)
    timeLabel.Text = formatTime(player.position) .. " / " .. formatTime(duration)
    local active = 0
    for _ in pairs(player.voices) do active = active + 1 end
    activityLabel.Text = string.format("%d held  /  %d out of range  /  %s", active, player.skipped, backend.name)
end))
return api

end
