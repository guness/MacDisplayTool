# MacDisplayTool

**Soft-disconnect your Apple Studio Display from the command line — for free.**

A tiny Swift CLI that turns an external display on and off without unplugging
it, and moves audio along with it. Built for the Studio Display, but the
display side works for any external display attached to an Apple Silicon Mac.

## What it does

- **Soft-disconnect a display.** Panel goes dark; macOS treats the display as
  unplugged. The USB-C cable stays connected, so the display keeps charging
  your MacBook.
- **Reconnect it just as fast.** No menu bars, no system settings.
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
  No background daemon, no menu bar app, no license.
- **vs MonitorControl:** MonitorControl is about brightness/volume over
  DDC/CI. It doesn't soft-disconnect.
- **vs macOS Connection Management:** the built-in toggle only handles the
  built-in laptop display auto-switching. There's no first-party way to
  soft-disconnect an arbitrary external display from a hotkey.

## Requirements

- Apple Silicon Mac
- macOS 13 or newer
- Swift 6.2 toolchain (for building)

## Build

```sh
swift build -c release
```

The binary is produced at `./.build/release/DisplayTool`.

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
