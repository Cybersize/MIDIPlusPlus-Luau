# MIDI++ Luau

A Roblox Luau MIDI piano player inspired by [Zephkek/MIDIPlusPlus](https://github.com/Zephkek/MIDIPlusPlus). It uses virtual keyboard input, so it does not need a particular game's remotes or internal scripts. Hosted at [Cybersize/MIDIPlusPlus-Luau](https://github.com/Cybersize/MIDIPlusPlus-Luau).

## Run in Project Real

Paste this into Project Real's script editor and execute it in Roblox:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Cybersize/MIDIPlusPlus-Luau/main/MIDIPlusPlus.lua?v=1.0.8"))()
```

1. The loader downloads the player from this repository and opens its GUI.
2. Open or sit at the piano in your game. Enable that game's computer-keyboard piano controls if needed.
3. Click **Load demo**, then **Play**. Playback starts after 1.5 seconds. If you hear the demo, the input backend and piano layout work together.
4. Put your MIDI files in Project Real's `workspace/MIDIPlusPlus` folder. The usual Windows location is `%LOCALAPPDATA%\Real\workspace\MIDIPlusPlus`; use your installation's actual workspace. Standard `.mid` files can load directly through Real's binary `readfile` API. If Thai filenames fail, run the included `Convert-MIDI.cmd` once (Python 3), then click **Refresh**.
5. Enter `MIDIPlusPlus/song.mid` in the player's **File** field, click **Load**, and click **Play**.

You can also select **URL** and paste a direct link to a binary `.mid` file, or select **Base64** and paste encoded MIDI bytes. A GitHub file-view URL or a YouTube URL is not a MIDI download. **Files** lists MIDI files inside the `MIDIPlusPlus` workspace folder when `listfiles` is available. **Refresh** rescans the folder and opens the updated list while the current song keeps playing.

The included `demo.mid` is the same original short melody as the built-in demo. The entrypoint downloads `lib/Core.lua` and `lib/Player.lua` from one fixed source commit, so both libraries use the same version. No third-party UI library is used. Song URLs load MIDI data only.

If you prefer a self-contained file, copy the entire contents of `MIDIPlusPlus-standalone.lua` into the executor instead. It contains the same player and does not download code. `Loader.lua` contains the short GitHub startup command; library files are dependencies and are not run directly.

## Queue songs and refresh the list

Version 1.0.5 displays only song names in the file list, queue, and playing title.
For example, `MIDIPlusPlus\Queen - Bohemian Rhapsody.mid` appears as
**Queen - Bohemian Rhapsody**. MIDI extensions and `.b64` sidecar suffixes are
hidden from names; selecting or queueing an entry still uses its full file path.

Version 1.0.4 adds an **UP NEXT** queue. Click **Files** or **Refresh**, then **+ Queue** beside each song in the order you want. The menu stays open so you can add several songs. The **+ Queue** beside the source field also adds a typed File, URL, or Base64 source. **Queue all** rescans the folder and adds its songs in filename order, hiding duplicate `.b64` sidecars.

Press **Play** to begin. If a song is already loaded, it plays first; **Next** skips directly to the first queued song. Each song automatically advances to the next with a 0.5-second gap. **Remove** deletes an individual pending entry; **Clear queue** removes all pending songs. Adding songs, clearing pending entries, and refreshing the file list keep the current song playing. The queue holds up to 128 entries and loads each MIDI when its turn arrives. Unreadable entries are skipped; check the executor console for the failed filename and reason.

**Pause**, **Stop**, and applicable focus checks cancel pending starts. Typing does so only with **Play while typing: OFF**. If a queued song is still downloading, Pause/Stop cancels its pending playback and returns the entry to the front of the queue. Late download results cannot restart the player. **Loop ON** repeats the current song; turn it off for automatic queue progression or use **Next** to skip. Loading another song manually keeps pending queue entries. Closing or rerunning the player clears the queue.

**Refresh** scans only the configured executor folder, not your Downloads folder. If a file such as `Queen - Bohemian Rhapsody.mid` is missing, copy it into your current executor's `workspace/MIDIPlusPlus` and click **Refresh**. Spaces and hyphens in filenames are supported. Files ending in `.mid`, `.midi`, `.rmi`, and their `.b64` sidecars are listed directly inside that folder; subfolders are not scanned recursively.

## Filename and binary compatibility

### Thai and other Unicode filenames

Version 1.0.6 added Thai names such as **ดาวนำทาง** in Files, the queue,
the playing title and UTF-8 MIDI track names. Display limits count complete
Unicode characters instead of cutting a multibyte character in half.

If your executor cannot open or list a Thai-named file, run **Convert-MIDI.cmd**, then
click **Refresh**. Alongside normal `.b64` sidecars, the converter creates
`MIDIPlusPlus-files.txt` and a `.midipp-cache` folder. These contain an ASCII
filename index and ASCII-named MIDI copies. The player displays the original
Thai title while loading its compatibility copy. This also works when native
`listfiles` fails, and supports a `.mid.b64` file without its original `.mid`.
Original filenames and original MIDI bytes are preserved. Run the converter
again after adding or changing songs; the player never renames your files.

Version 1.0.7 detects Project Real's usual workspace first, with Xeno as a fallback.
Pass a folder explicitly for another installation, or use `--executor xeno` to
choose Xeno when both are installed. MIDI Studio 1.2.3 uses the same detection;
**Save to Project Real piano folder** updates the index automatically.
The index contains only filenames and generated cache IDs;
it does not contain or execute Lua. Paths in the index are restricted to a
basename and a generated cache filename.

The ASCII aliases avoid relying on native Unicode path handling. This includes
filename encoding limitations visible in a
[published Xeno filesystem implementation](https://github.com/tyronetheqt/Xeno/blob/main/Xeno/src/server.cpp),
which uses narrow Windows paths. It does not change the executor itself.

### Binary-safe MIDI bytes

Version 1.0.1 supports binary-safe `.mid.b64` files. A text-mode file bridge can truncate a MIDI at byte `0x1A` (Ctrl+Z), causing an error about a track length exceeding the remaining file bytes. The original MIDI file can still be valid. One [published Xeno source version](https://github.com/tyronetheqt/Xeno/blob/main/Xeno/src/server.cpp#L72) opens files as a text stream.

Run `Convert-MIDI.cmd`, or use:

```powershell
python Convert-MIDI.py "C:\path\to\workspace\MIDIPlusPlus"
```

With no path, the converter prefers `%LOCALAPPDATA%\Real\workspace\MIDIPlusPlus` if Real's workspace exists, then `%LOCALAPPDATA%\Xeno\workspace\MIDIPlusPlus`. `python Convert-MIDI.py --executor real` selects Real explicitly. It writes ASCII base64 files such as `song.mid.b64` beside the original files. It leaves the `.mid` files untouched and performs no network requests. Run it again after adding or changing songs.

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
| Play while typing ON/OFF | Keep playback, countdowns, queued songs and Test keys running with a Roblox text box focused |
| Files / Refresh | Open the MIDI folder list / rescan it for newly added files |
| + Queue / Queue all | Append one source / append the folder's songs in filename order |
| Next | Skip the current or downloading song and start the next queued song |
| Remove / Clear queue | Delete one pending entry / clear all pending entries |

Drag the title bar to move the window. Minimize with `_`. Close with `X` to release input and unload the script. Executing the script again replaces the previous instance.

Version 1.0.8 enables **Play while typing: ON** by default. Focusing another
script's editor or any other Roblox text box no longer pauses the player,
cancels a start, or interrupts queued songs. Starting playback or Test keys
also keeps that text box focused. The toggle beside **Reset tracks** restores
the old pause-on-typing behavior when switched OFF. Turning it OFF while a
text box is already focused pauses active playback immediately. Turning it
ON does not automatically resume a paused song; click Play. F4 still stops
and releases injected keys while typing; the other hotkeys ignore text boxes.

Injected note keys can also enter the focused text box. A game's piano can
consume or ignore keys while its text UI is focused, so continuing the player
does not guarantee that every game accepts those notes.

Background playback is enabled by default for virtual input; turn it off with the title-bar button to pause when switching away from Roblox. Press Play/F6 to resume a paused song when no text box is focused. Seeking and resuming reconstruct held notes and MIDI pedal state; already-released notes under a pedal are retriggered to approximate their tails.

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

Project Real's documented `readfile` returns binary bytes, `listfiles` returns workspace-relative paths, and `keypress`/`keyrelease` accept Windows virtual-key numbers. The player uses those API signatures. Real's native key functions require Roblox to be the active window. See Real's [file API](https://docs.projectreal.gg/en/reference/filesystem/readfile) and [keyboard API](https://docs.projectreal.gg/en/reference/input/keypress). The same generic adapters retain Xeno support. Automated checks mock the documented API contracts; live Project Real piano playback has not been verified here.

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
    QueueDelay = 0.5, -- countdown before each queued song (0 to 10 seconds)
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
    PlayWhileTyping = true, -- false restores pausing when a Roblox text box is focused
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

`PlayWhileTyping` defaults to true independently of Background mode. Change it
with the **Play while typing** toggle or `SetPlayWhileTyping`. Native executor
input still requires Roblox window focus even when typing is allowed.

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
midi:SetPlayWhileTyping(true) -- keep playing when another script focuses a text box
midi:EnqueueFile("MIDIPlusPlus/next song.mid") -- returns entry ID, or nil + error
-- midi:EnqueueURL("https://your-host.example/next.mid")
-- midi:EnqueueBase64("...")
print(midi:GetQueue()) -- ordered snapshots: id, name, mode, loading
midi:RemoveQueued(1) -- index in GetQueue(), including an entry currently loading
midi:Next() -- starts the next queued song after QueueDelay
-- midi:ClearQueue()
-- midi:RefreshFiles() -- rescans, opens the menu, and returns the file paths
print(midi:Status().backend)
print(midi:Status().playWhileTyping)
print(midi:Status().midiBpm, midi:Status().bpm) -- original / speed-adjusted tempo
print(midi:Status().song, midi:Status().queueCount, midi:Status().loading)
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

The parser/playback core passed 31 tests with the official Luau CLI. The full script passed 55 integration tests using mock Roblox services and executor APIs to check UI wiring, loading, input selection, proxy compatibility, input observation, BPM, background behavior, queues, file refresh, download cancellation, Unicode filenames and cleanup. Six new typing regressions cover ongoing playback, starting/restarting with a focused editor, countdowns, key tests, queued downloads and automatic next-song starts, the UI/API toggle, optional pause behavior and F4 cleanup. These checks also ensure allowed typing does not release the editor's focus. This includes direct binary loading under Thai paths with Real's documented API signatures and ASCII alias loading when native Unicode reads fail. Seven Python converter tests check byte preservation and executor selection. The GitHub entrypoint is also tested with mocked HTTP requests. The base64 loading path was checked with 14 real MIDI files, including files whose bytes are truncated by a simulated text-mode reader and `Queen - Bohemian Rhapsody.mid`. These are local checks; real game compatibility, Mois7 interaction and visual behavior need an in-game run.

To run the included parser and converter regressions locally:

```powershell
luau tests/core.spec.luau
luau tests/runtime.spec.luau
python -B -m unittest discover -s tests -p "test_*.py"
```

Original source and attribution are recorded in `NOTICE.md`. The editable Lua files contain the full implementation. See `LICENSE` for GNU GPL version 3.

References: [original MIDIPlusPlus](https://github.com/Zephkek/MIDIPlusPlus), [Roblox RunService](https://create.roblox.com/docs/reference/engine/classes/RunService), [VirtualInputManager documentation](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/VirtualInputManager.yaml), and [Standard MIDI Files](https://midi.org/standard-midi-files).
