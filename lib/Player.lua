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
label(header, "LUAU  /  VIRTUAL PIANO  /  1.0.6", 23, 37, 360, 16, 10, colors.muted)
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
    statusLabel.Text = Core.displayText(tostring(message):gsub("[\r\n]", " "), 240)
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
    local name = path:match("([^/\\]+)$") or "MIDI"
    name = name:gsub("%.[bB]64$", ""):gsub("%.[mM][iI][dD][iI]?$", ""):gsub("%.[rR][mM][iI]$", "")
    return Core.displayText(name ~= "" and name or "MIDI", 120)
end
local fileAliases = {}
local function fileIdentity(path)
    return path:gsub("\\", "/"):gsub("^%./", ""):lower():gsub("%.b64$", "")
end
local function readFileIndex()
    local folder = Config.Folder or "MIDIPlusPlus"
    table.clear(fileAliases)
    if type(readfile) ~= "function" then return {} end
    local ok, text = pcall(readfile, folder .. "/MIDIPlusPlus-files.txt")
    if not ok then return {} end
    local parsed, entries = pcall(Core.readFileIndex, text, folder)
    if not parsed then return {} end
    for _, entry in ipairs(entries) do fileAliases[fileIdentity(entry.path)] = entry.readPath end
    return entries
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
    if mode == "File" then
        readFileIndex()
        local alias = fileAliases[fileIdentity(value)]
        local selected = value:find("[\128-\255]") and alias or value
        local ok, song, info = pcall(Core.loadFile, selected, readfile)
        local fallback = selected == alias and value or alias
        if not ok and fallback and fallback ~= selected then ok, song, info = pcall(Core.loadFile, fallback, readfile) end
        if not ok then
            if value:find("[\128-\255]") and not alias then
                error("Could not open this Unicode filename. Run Convert-MIDI.cmd, then Refresh and load it again. " .. tostring(song))
            end
            error(song)
        end
        if selected == alias or info.path == alias then info.originalPath = value end
        return song, info
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
    local folder = Config.Folder or "MIDIPlusPlus"
    if type(makefolder) == "function" then pcall(makefolder, folder) end
    local indexed = readFileIndex()
    local ok, files = pcall(function()
        assert(type(listfiles) == "function", "This executor has no listfiles")
        return listfiles(folder)
    end)
    assert(ok and type(files) == "table" or #indexed > 0,
        "Could not list files. Run Convert-MIDI.cmd for this folder, then Refresh. " .. tostring(files))
    if not ok or type(files) ~= "table" then files = {} end
    local filtered, choices = {}, {}
    for _, file in ipairs(files) do
        local lower = tostring(file):lower()
        local base = lower:gsub("%.b64$", "")
        if type(file) == "string" and utf8.len(file) ~= nil and not file:find("?", 1, true)
            and (base:match("%.midi?$") or base:match("%.rmi$")) then
            local canonical = base:gsub("\\", "/"):gsub("^%./", "")
            if not choices[canonical] or not lower:match("%.b64$") then choices[canonical] = file end
        end
    end
    for _, entry in ipairs(indexed) do
        local identity = fileIdentity(entry.path)
        if not choices[identity] then choices[identity] = entry.path end
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
        local b = button(fileList, sourceName(path, "File"), 4, (i - 1) * 30, 490, 28)
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

local api = { Version = "1.0.6", InputBackend = function() return backend.name end }
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
