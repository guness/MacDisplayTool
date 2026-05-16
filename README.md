# MacDisplayTool

A simple tool to manipulate displays on macOS.

Currently it can list all active displays, enable / disable a specific display,
and move the default audio output to follow the display (e.g. when disabling an
Apple Studio Display, audio falls back to the built-in speakers; when
re-enabling it, the display's audio device is reclaimed unless something better
like AirPods is already in use).

## Build

Requires the Swift 6.2 toolchain.

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
```

Refer to `DisplayTool help` for the full reference.

## License

[MIT License](LICENSE).
