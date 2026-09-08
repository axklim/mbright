# mbright

Brightness control for macOS displays that ignore DDC/CI, such as the Apple
Studio Display and LG UltraFine. Command line and menu bar. Goes through
Apple's own `DisplayServices` layer: no root, no permission prompts.

## Install

Requires macOS 14+ and the Xcode Command Line Tools. Builds from source,
about a minute.

```bash
make install     # ~/Applications/mbright.app + ~/.local/bin/mbright
make uninstall
```

`make install` also launches the menu bar app; afterwards it is in
Spotlight and Raycast like any app. `~/.local/bin` must be on your `PATH`
for the CLI (`make install PREFIX=/usr/local` puts the symlink elsewhere).

Without make: `swift build -c release` and copy `mbright`, `mbrightd`, and
`mbright-menubar` from `.build/release/` into one directory on your `PATH`.

## Usage

```bash
mbright list                  # every display and its brightness (default)
mbright get -d ultrafine      # one display, bare integer for scripts
mbright set 80 --all          # absolute, 0-100
mbright up 10 -d studio       # relative, clamped
mbright down 10

mbright daemon start          # the CLI talks to mbrightd; start it once
mbright daemon stop
mbright daemon enable-login   # start at login (also in the app's Settings)
open -a mbright               # menu bar app with a slider per display
```

The CLI needs `mbrightd` running. Start it once, or pass `--daemon-autostart`
to any command. The menu bar app starts it by itself.

Full reference: [docs/cli.md](docs/cli.md). How it fits together:
[docs/architecture.md](docs/architecture.md).

## Caveats

- `DisplayServices` is private API. If Apple removes a symbol, mbright fails
  at startup naming it rather than misbehaving.
- Tested only with a Studio Display and an LG UltraFine on Apple Silicon.
  Not DDC/CI; DDC/CI-only monitors are not expected to work.
- `set 0` makes a display look off. Treat it as a footgun.

## Development

```bash
./scripts/test.sh             # not bare `swift test`; see docs/architecture.md
```

`make` on its own lists every target and the paths it resolves. It builds
into `$XDG_CACHE_HOME/mbright/build`; bare `swift build` still uses
`./.build`.

```bash
make                              # list targets
make run                          # stop the installed app, run this build
make test FILTER=Percent          # one suite
```

`make run` stops the installed app and daemon and runs the debug build in
the foreground. Ctrl-C (or Quit) stops it and its daemon; relaunch the
installed app from Spotlight.

Releasing: [docs/releasing.md](docs/releasing.md). License: MIT.
