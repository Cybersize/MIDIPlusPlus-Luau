# MIDI++ Luau

A Roblox Luau MIDI piano player inspired by [Zephkek/MIDIPlusPlus](https://github.com/Zephkek/MIDIPlusPlus). It uses virtual keyboard input, so it does not need a particular game's remotes or internal scripts. Hosted at [Cybersize/MIDIPlusPlus-Luau](https://github.com/Cybersize/MIDIPlusPlus-Luau).

## Run in Xeno

Paste this into Xeno's script editor and execute it in Roblox:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Cybersize/MIDIPlusPlus-Luau/main/MIDIPlusPlus.lua?v=1.0.3"))()
```

1. The loader downloads the player from this repository and opens its GUI.
2. Open or sit at the piano in your game. Enable that game's computer-keyboard piano controls if needed.
3. Click **Load demo**, then **Play**. Playback starts after 1.5 seconds. If you hear the demo, the input backend and piano layout work together.
4. Put your own MIDI file in the executor's workspace, for example `workspace/MIDIPlusPlus/song.mid`. For Xeno, run the included `Convert-MIDI.cmd` once to create text-safe copies beside your MIDI files (requires Python 3). Use the executor's actual workspace folder; its location varies by installation.
5. Enter `MIDIPlusPlus/song.mid` in the player's **File** field, click **Load**, and click **Play**.

You can also select **URL** and paste a direct link to a binary `.mid` file, or select **Base64** and paste encoded MIDI bytes. A GitHub file-view URL or a YouTube URL is not a MIDI download. **Files** lists MIDI files inside the `MIDIPlusPlus` workspace folder when `listfiles` is available.

The included `demo.mid` is the same original short melody as the built-in demo. The entrypoint downloads `lib/Core.lua` and `lib/Player.lua` from one fixed source commit, so both libraries use the same version. No third-party UI library is used. Song URLs load MIDI data only.

If you prefer a self-contained file, copy the entire contents of `MIDIPlusPlus-standalone.lua` into the executor instead. It contains the same player and does not download code. `Loader.lua` contains the short GitHub startup command; library files are dependencies and are not run directly.

## Fix for incomplete binary reads in Xeno

Version 1.0.1 supports binary-safe `.mid.b64` files. A text-mode file bridge can truncate a MIDI at byte `0x1A` (Ctrl+Z), causing an error about a track length exceeding the remaining file bytes. The original MIDI file can still be valid. One [published Xeno source version](https://github.com/tyronetheqt/Xeno/blob/main/Xeno/src/server.cpp#L72) opens files as a text stream.

Run `Convert-MIDI.cmd`, or use:

```powershell
python Convert-MIDI.py "C:\path\to\workspace\MIDIPlusPlus"
```

With no path, the converter uses `%LOCALAPPDATA%\Xeno\workspace\MIDIPlusPlus`. It writes ASCII base64 files such as `song.mid.b64` beside the original files. It leaves the `.mid` files untouched and performs no network requests. Run it again after adding or changing songs.

Continue choosing `song.mid` in the player: a matching `.mid.b64` file is preferred automatically. You can also load a `.mid.b64` file directly. The status line confirms when the text-safe file was used, and the file menu hides duplicate sidecars. Both paths use the same MIDI parser and preserve all original note bytes; incomplete MIDI data is still rejected.

## Controls

| Control | Action |
| --- | --- |
| Play / F6 | Start, pause, or cancel a pending start |
| Stop / F7 | Release keys and return to the beginning |
| Restart | Return to the beginning and start after the countdown |
| Panic / F4 | Stop immediately and attempt to release every injected key |
| F8 | Show or hide the player |
| Timeline | Click to seek |
| -5 sec / +5 sec | Seek backward or forward |
| Speed | 0.10–4.00 times the MIDI's original tempo |
| Transpose | -48 to +48 semitones |
| Mute / Solo | Enable or isolate individual MIDI tracks |
| 88 keys | Use the original project's extended Ctrl key layout |
| Skip drums | Ignore MIDI channel 10; enabled by default |
| Fold octaves | Move out-of-range notes by octaves into the chosen range |
| Sustain | Convert MIDI CC64 to the Space pedal key |
| Velocity / Alt | Send the original project's 32-step Alt key velocity controls |
| Loop | Repeat the song |
| Input | Cycle the available keyboard output modes |
| Test keys | Send T, U, O and report how many key events reach Roblox |
| Background ON/OFF | Keep virtual-input playback running after switching away from Roblox |

Drag the title bar to move the window. Minimize with `_`. Close with `X` to release input and unload the script. Executing the script again replaces the previous instance.

Typing in a Roblox text box pauses playback. Background playback is enabled by default for virtual input; turn it off with the title-bar button to pause when switching away from Roblox. Press Play/F6 to resume a paused song. Seeking and resuming reconstruct held notes and MIDI pedal state; already-released notes under a pedal are retriggered to approximate their tails.

## Play while Roblox is unfocused

Version 1.0.3 adds **Background** in the title bar. With **Background: ON** and a virtual-input backend selected, the song, start countdown, and Test keys continue after Alt+Tab. Auto mode prefers virtual input when background playback is enabled. Enabling Background while using another adapter selects virtual input when it is available.

Open the piano, start the song, and switch to another window. To check delivery, click **Test keys** and switch away during its countdown; after it finishes, return to Roblox to read the result. Roblox or a game's piano can still reject input while unfocused, and a minimized client can throttle playback. Live background playback has not been verified by the local mock tests.

Native `Executor` and arbitrary custom SendKey adapters remain subject to focus checks in this player. They pause on focus loss, and the player prevents new foreground key presses while it detects Roblox is inactive. Use **VirtualInput** or **VirtualInputService** for background playback. **Background: N/A** means the selected adapter cannot provide background input in this player. The title-bar button can select an available virtual adapter.

To stop, return to Roblox and click Stop/Panic or press F4. The script's hotkeys listen inside Roblox.

## If the piano is silent

First confirm that pressing **T** manually plays a note while the piano is open. Click **Test keys**; initially test with Roblox focused. The test sends T, U, O one at a time. It works without loading a MIDI. Once focused input works, repeat while unfocused with **Background: ON**.

- **3/3 keys reached Roblox:** keyboard events were observed by UserInputService. If the piano remains silent, check the game's active piano, keyboard layout, and any UI consuming input. Receiving a key event does not prove that the game's sound handler accepted it.
- **Keys sent; Roblox received none:** select the next **Input** mode and test again. Some executor functions exist but perform no input.
- **Input error:** the selected API is unavailable or denied in that session. Select another Input mode.
- **Paused/focus message:** enable Background with a virtual-input mode, or click the Roblox game window and press F6. Foreground key adapters require Roblox focus.

Version 1.0.2 passes a real Roblox Instance to virtual-input methods instead of the executor's `game` proxy. It prefers a dedicated VirtualInputManager instance and offers the service instance as a separate mode. When `identifyexecutor` reports Xeno, Auto prefers virtual input over native key functions. [Published Xeno source](https://github.com/tyronetheqt/Xeno/blob/main/Xeno/include/client.lua) illustrates the game proxy and dedicated virtual input object; behavior can vary by executor release.

## BPM and tempo

Tempo is automatic: the parser reads embedded MIDI tempo events and follows changes throughout the song. With **Speed 1.00**, the original tempo is used. A file without tempo metadata uses the MIDI default of **120 BPM**. This reads timing information from the file; it does not estimate BPM from audio.

The timeline shows the current effective BPM, including the Speed multiplier: 120 BPM at Speed 1.50 displays 180 BPM. Seeking updates the displayed tempo. SMPTE-timed files use fixed time divisions and display **Timing: SMPTE** instead.

## Piano layouts

The default 61-key layout follows the original project: MIDI 36 (C2) is `1`, MIDI 60 (C4) is `t`, and MIDI 96 (C7) is `m`. Uppercase letters and shifted digit symbols use Shift. The extended 88-key layout adds MIDI 21–35 and 97–108 using Ctrl combinations.

Your piano must support the same layout. Enable the game's 88-key mode before enabling **88 keys** here. Velocity is **off by default**: enable it only if the piano uses Alt plus `1234567890qwertyuiopasdfghjklzxc` for velocity. The five curves are adapted from MIDIPlusPlus: Linear, Fine, Soft, Log, and Exp. Ordinary keyboard input cannot apply per-note velocity unless the game implements such controls.

## Executor compatibility

This version targets the common APIs used by Xeno-style executor environments. GUI initialization has been observed in Xeno; end-to-end piano playback remains unverified by the automated checks. Passing in one executor does not establish compatibility with every other executor.

The default **Auto** backend prefers a dedicated VirtualInputManager when background playback is enabled or Xeno is detected. In other foreground sessions it uses `keypress` and `keyrelease` when both exist, or virtual input otherwise. It can fall back when the first native input call raises an error. A failed first virtual-input call can try the service object in Auto mode. **Test keys** checks for observed Roblox key events to help expose silent no-ops. Roblox documents VirtualInputManager as an internal service; access depends on the executor's permissions.

If Play shows an input error, or no notes are heard, use the **Input** button to switch backends and click **Test keys**. The status line reports input errors and the selected backend. If no backend is permitted, a plain script cannot provide keyboard input in that environment.

| API | Purpose | Alternative |
| --- | --- | --- |
| `keypress`, `keyrelease` | Keyboard output using Windows virtual key codes | VirtualInputManager or custom SendKey |
| VirtualInputManager | Keyboard output using Roblox KeyCodes | Native key functions or custom SendKey |
| `readfile` | Local MIDI or `.mid.b64` files | URL, Base64, built-in demo |
| `listfiles` | File menu | Type the file path |
| `request`, `http_request`, or `syn.request` | MIDI download | `game:HttpGet` if no request API exists; otherwise local files/Base64 |
| `gethui` | Optional GUI parent | Local player's PlayerGui |

## Optional configuration

Put this **before the short loader command** in the executor editor, or before the contents of `MIDIPlusPlus-standalone.lua` when using that version. Only include settings you want to change.

```lua
getgenv().MIDIPlusPlusConfig = {
    Backend = "Auto", -- "Auto", "Executor", "VirtualInput", or "VirtualInputService"
    DefaultFile = "MIDIPlusPlus/song.mid",
    Folder = "MIDIPlusPlus",
    StartDelay = 1.5,
    Full88Keys = false,
    SkipDrums = true,
    FoldOutOfRange = false,
    Sustain = true,
    SustainKey = "Space",
    Velocity = false,
    Curve = "Linear", -- "Linear", "Fine", "Soft", "Log", "Exp"
    Speed = 1,
    Transpose = 0,
    Loop = false,
    BackgroundPlayback = true,
    Hotkeys = true,
    Keymap = {
        -- Keys are MIDI note numbers; entries override the chosen layout.
        -- [60] = "t",
        -- [61] = "shift+t", -- "T" also means Shift+t
        -- [21] = "ctrl+1",
        -- [36] = false, -- disable this note
    },
}
```

You can change the input backend with the GUI's **Input** button, or set `Backend` in the startup config. Other configuration settings are read at initialization. Changing the configuration table after execution does not update an existing player.

Background mode can also be changed at runtime with the title-bar button or `SetBackgroundPlayback`. The old `PauseOnFocusLoss` option is used only when `BackgroundPlayback` is absent: true disables background, false enables it. With neither setting supplied, background is enabled.

If adapting to another keyboard API, supply `SendKey = function(keyCode, isDown, virtualKeyCode) ... end` in the config. This takes priority over Backend. The function must return promptly, preserve key order, and raise an error when input fails. Mapping entries support a letter, digit, common US punctuation, Space, Tab, Enter, Backspace, Delete, Escape, arrow key, or F1–F12, optionally prefixed with `ctrl+`, `shift+`, or `alt+`. Do not map note keys to the pedal key or modifier keys. Disable Hotkeys when mapping notes to F4/F6/F7/F8.

## Script API

After execution, `getgenv().MIDIPlusPlus` exposes:

```lua
local midi = getgenv().MIDIPlusPlus
midi:LoadFile("MIDIPlusPlus/song.mid")
-- midi:LoadURL("https://your-host.example/song.mid")
-- midi:LoadBase64("...")
-- midi:LoadData(binaryString, "Song name")
midi:SetSpeed(0.8)
midi:SetTranspose(0)
midi:SetTrack(1, false, true) -- track index, muted, solo (indices start at 1)
midi:Seek(15) -- seconds in the MIDI's original timeline
midi:Play() -- idempotent; respects StartDelay
midi:Pause()
midi:Stop()
midi:SetBackend("VirtualInput") -- pause and select an available input mode
midi:TestInput() -- three-note test; results are in midi:Status().inputTest
midi:SetBackgroundPlayback(true) -- pauses; selects virtual input when available
print(midi:Status().backend)
print(midi:Status().midiBpm, midi:Status().bpm) -- original / speed-adjusted tempo
-- midi:Destroy()
```

File/URL/Base64 loading is asynchronous. Wait until the UI reports that loading has finished before Play. `LoadData` parses synchronously. API callers should use `pcall` to handle invalid arguments and errors.

## Supported MIDI and limits

- Standard MIDI formats 0 and 1; PPQN tempo changes, running status, and SMPTE divisions, including 29.97 fps.
- RIFF/RMID containers, track names, note-on/off, velocity-zero note-offs, sustain, and CC120/121/123 cleanup.
- Tracks merge into one shared timeline. Tracks with no notes remain available because they may contain pedal controls.
- Limits: 16 MiB MIDI data, 250,000 source events, and 256 tracks. Oversized or malformed files display an error.
- Playback runs on Roblox Heartbeat. Timing depends on client frame rate, executor input behavior, and the game's piano. There is no sub-millisecond latency guarantee.
- After a client stall over half a second, or a frame with more than 4,096 due events, the player rebuilds the current note state instead of sending all expired notes. Dense black MIDI can exceed practical client/input limits.
- Keyboard output has physical key constraints. Notes sharing a base key, such as `t` and `T`, can retrigger or release differently depending on the game. MIDI sustain channels merge into one Space pedal. Full independent MIDI polyphony/pedals/velocity cannot be guaranteed through a keyboard interface.
- This adaptation does not include native MIDI-device connections, Windows audio-volume control, the original native timing engine, automatic key/genre estimation, or MIDI format 2. It does not synthesize audio itself; the game's piano produces sound. Pitch bend, instruments, and most MIDI controllers are ignored.

## Validation and source

The parser/playback core passed 29 tests with the official Luau CLI. The full script passed 31 integration tests using mock Roblox services and executor APIs to check UI wiring, loading, input selection, proxy compatibility, input observation, BPM, background behavior, and cleanup. The GitHub entrypoint is also tested with mocked HTTP requests. The base64 loading path was checked with 13 real MIDI files, including files whose bytes are truncated by a simulated text-mode reader. These are local checks; real game compatibility and visual behavior need an in-game run.

To run the included parser and converter regressions locally:

```powershell
luau tests/core.spec.luau
luau tests/runtime.spec.luau
python -B -m unittest discover -s tests -p "test_*.py"
```

Original source and attribution are recorded in `NOTICE.md`. The editable Lua files contain the full implementation. See `LICENSE` for GNU GPL version 3.

References: [original MIDIPlusPlus](https://github.com/Zephkek/MIDIPlusPlus), [Roblox RunService](https://create.roblox.com/docs/reference/engine/classes/RunService), [VirtualInputManager documentation](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/VirtualInputManager.yaml), and [Standard MIDI Files](https://midi.org/standard-midi-files).
