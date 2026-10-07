# MacDisplayTool

**Soft-disconnect your Apple Studio Display from the command line — for free.**

A small menu bar app and Swift CLI that turn an external display on and off
without unplugging it, move audio along with it, and create custom-resolution
virtual displays for remote access. Built for the Studio Display, but the
display side works for any external display attached to an Apple Silicon Mac.

## What it does

- **Soft-disconnect a display.** Panel goes dark; macOS treats the display as
  unplugged. The USB-C cable stays connected, so the display keeps charging
  your MacBook.
- **Reconnect it just as fast.** Use the menu bar or a single CLI command.
- **Audio follows the display.** When you turn the Studio Display off, audio
  falls back to your MacBook speakers. When you turn it back on, the display
  reclaims output — unless you're already on AirPods, in which case it leaves
  you alone.
- **One-shot, hotkey-friendly.** `toggle` is a single command; bind it to a
  shortcut in Raycast, Hammerspoon, or Apple Shortcuts and you're done.
- **Custom resolution for remote access.** Create a virtual display with
  your own pixel dimensions, independent of a physical monitor's modes.

## How it compares

| Tool                   | Soft-disconnect | Audio follow | Price        |
| ---------------------- | --------------- | ------------ | ------------ |
| **MacDisplayTool**     | ✅              | ✅           | Free, MIT    |
| BetterDisplay Pro      | ✅              | ❌           | ~$20         |
| MonitorControl         | ❌              | ❌           | Free         |
| Built-in macOS         | Limited        | ❌           | —            |

- **vs BetterDisplay Pro:** the paid soft-disconnect feature, distilled into
  one focused tool, with the bonus that audio routing follows the display.
  Available from the CLI or the optional menu bar app, with no paid license.
- **vs MonitorControl:** MonitorControl is about brightness/volume over
  DDC/CI. It doesn't soft-disconnect.
- **vs macOS Connection Management:** the built-in toggle only handles the
  built-in laptop display auto-switching. There's no first-party way to
  soft-disconnect an arbitrary external display from a hotkey.

## Requirements

- Apple Silicon Mac
- macOS 13 or newer
- Swift 6.2 toolchain (for building)
- Full Xcode for building the SwiftUI menu bar app

## Build

```sh
swift build -c release
```

The binary is produced at `./.build/release/DisplayTool`.

To build the menu bar app (with the CLI included):

```sh
bash scripts/build-app.sh
open dist/MacDisplayTool.app
```

Copy `dist/MacDisplayTool.app` to Applications for a permanent installation.
The bundled CLI is at `MacDisplayTool.app/Contents/MacOS/DisplayTool`.

## Install

Symlink the release binary into `/usr/local/bin`:

```sh
sudo ln -sf "$PWD/.build/release/DisplayTool" /usr/local/bin/DisplayTool
```

After that, `DisplayTool` is available from anywhere — and rebuilding with
`swift build -c release` updates the symlinked binary automatically.

## Usage

```sh
DisplayTool list                              # list active display IDs
DisplayTool set <id> --disabled               # soft-disconnect (session-only)
DisplayTool set <id> --enabled                # reconnect
DisplayTool set <id> --disabled --persistent  # persist across reboots
DisplayTool toggle <id>                       # flip between enabled / disabled
DisplayTool virtual 2732 2048                 # custom display for a remote client
```

`DisplayTool help` shows the full reference.

### Menu bar app and saved resolution profiles

Open the app and choose **Profiles…** to add a name, pixel
width, height, and refresh rate. Select a saved profile from the menu to activate
it, or choose **Default** to use the Mac's normal display resolution. Default
is reserved as a built-in choice. The native macOS menu shows a checkmark next
to the selected resolution and uses the system's appearance.
The app owns the display, so terminal
and SSH sessions can close after activation. Quitting the app removes its display.
Select Default before editing or deleting an active profile.

The same menu includes **Toggle display**, individual physical display
disconnect controls, and a reconnect action for the last disabled display.
These use the same audio-follow behavior and last-display protection as the
original `toggle` command. Physical toggles apply to the current login session;
the CLI's `--persistent` flag is still available for permanent physical toggles.
Automatic toggles skip virtual displays created by this tool so they continue
to target your physical monitor when a resolution profile is active.

Enable **Launch at login** to start the app after logging in. The app remembers
your selected resolution, including Default. macOS may require approval
in Login Items settings. The app does not create a display before graphical login.

Virtual displays follow the active login session. Switching users releases the
previous session's display while retaining its selected profile; switching back
restores that profile. Inactive sessions show a paused state. A separate Screen
Sharing desktop may not be able to use these displays; connect to the active
desktop instead. Profiles and login settings belong to each user separately.

The CLI can manage and activate the same saved profiles:

```sh
DisplayTool app
DisplayTool profile add "Remote Tablet" 2732 2048
DisplayTool profile list
DisplayTool profile activate "Remote Tablet"
DisplayTool profile activate Default
DisplayTool profile status
DisplayTool profile off
DisplayTool profile remove "Remote Tablet"
DisplayTool toggle                            # original functionality preserved
```

Activation starts the app if needed and waits for its response. Profiles are
shared in `~/Library/Application Support/MacDisplayTool/profiles.json`. If the
app is installed elsewhere, set `MACDISPLAYTOOL_APP` to its `.app` path.
The app automatically imports the earlier persistent virtual display's settings
and removes its old LaunchAgent when taking ownership. Existing foreground
`virtual` commands and the older `--persistent` mode remain available, but use
saved profiles for displays managed by the menu bar app.

### Custom resolution for remote connections

```sh
DisplayTool virtual 2732 2048
DisplayTool virtual 3440 1440 --refresh-rate 60 --name "Remote Ultrawide"
```

This creates a new virtual display advertising the requested resolution,
rather than choosing from an existing physical display's configurations.
Dimensions are pixels at 1× scale. Width and height can each be 1–16384;
refresh rate can be 1–240 Hz (default 60). macOS may reject dimensions or
refresh rates it cannot support, so these ranges are input limits, not a
guarantee that every combination will work.

Keep the command running on the Mac being accessed. Select the printed display
ID or display name in your remote client, if it supports choosing a monitor.
The client must capture the host's displays; clients that create an independent
remote session may ignore this display. Use `Ctrl-C` or send `SIGTERM` to remove
it. For an SSH session, keep it alive in a terminal multiplexer such as `tmux`.
The display does not survive the process exiting or a reboot.

To keep the display after closing SSH and recreate it at login:

```sh
DisplayTool virtual 2732 2048 --persistent
DisplayTool virtual-stop                       # remove it and disable login startup
```

Persistent mode installs a user LaunchAgent in `~/Library/LaunchAgents`, starts
the display in the background, and returns immediately. Run the command again
to replace its resolution. Only one persistent display is managed per user.
macOS restarts it if its process exits. A graphical user login is required;
after a reboot, it starts when that user logs in, not at the pre-login screen.
Run without `sudo` and keep the executable at its installed path. Logs are in
`~/Library/Logs/MacDisplayTool/virtual.log`. `virtual-stop` does not stop displays
started separately in foreground mode.

This does not force unsupported timings onto your physical monitor. macOS's
physical display mode API requires a mode supplied by the driver. A virtual
display provides custom dimensions without relying on those modes. It is
created as an additional desktop; move windows there as needed.

### Typical hotkey workflow

Bind `DisplayTool toggle <id>` to a global shortcut (Raycast, Hammerspoon,
Apple Shortcuts → Run Shell Script). One tap puts the display to sleep and
moves audio to your MacBook. Another tap brings it back.

## How it works

- **Display:** wraps the private `CGSConfigureDisplayEnabled` SkyLight API,
  the same one macOS uses internally for connection management. Default
  commit mode is `.forSession`, so a logout or reboot is always an escape
  hatch. Use `--persistent` to opt into the old reboot-surviving behavior.
- **Audio:** uses `CoreAudio`'s default output property. Identifies the
  Studio Display's speakers by walking `IOKit` for the Apple vendor ID
  (`0x05AC`) and Studio Display product ID (`0x1114`) — purely structural,
  no name matching. System sounds (alerts, UI) follow main output.
- **Virtual display:** resolves the private `CGVirtualDisplay` classes at
  runtime and advertises a single custom mode. The foreground process owns
  the display and releases it on interruption.
- **Safety:** refuses to disable a display if it would leave you with no
  active screen.

## Caveats

- `CGSConfigureDisplayEnabled` is a private symbol. It's stable in current
  macOS releases but isn't an API Apple guarantees.
- `CGVirtualDisplay` is also private and can change between macOS releases.
  Creation fails with an error if the API is unavailable or macOS rejects
  the requested mode. Remote client support varies.
- The Studio Display can't actually be powered off via software — only
  unplugging it from the wall does that (per Apple).
- USB headphones plus Studio Display together: the audio-follow heuristic
  may pick the wrong device. Bluetooth headphones (AirPods etc.) are
  detected correctly and left alone.

## Credits

Originally based on [laosb/MacDisplayTool](https://github.com/laosb/MacDisplayTool).

## License

[MIT License](LICENSE).
