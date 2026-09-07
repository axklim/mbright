# mbright

Open-source brightness control for macOS displays, from the command line and
the menu bar.

Works with displays that ignore DDC/CI — including the Apple Studio Display and
LG UltraFine — by going through Apple's own `DisplayServices` layer. No root,
no permission prompts.

Three binaries ship together:

- `mbright` — the CLI.
- `mbright-menubar` — a menu bar app with one slider per display.
- `mbrightd` — the daemon both of them talk to. It is the only process that
  touches the displays. You start it deliberately, with `mbright daemon start`,
  the menu bar app, or `--daemon-autostart`, and it runs until you stop it.

## Why

`brightness` handles built-in laptop panels only. `m1ddc` and `ddcctl` need
DDC/CI, which neither the Studio Display nor the UltraFine speaks. MonitorControl
is a GUI. `betterdisplaycli` works but is closed source and needs its app running.

## Install

Requires macOS 14+ and the Swift toolchain (Xcode Command Line Tools is
enough). There is no prebuilt binary — mbright compiles from source either
way, which takes about a minute.

### Homebrew

```bash
brew tap axklim/mbright https://github.com/axklim/mbright
brew trust --formula axklim/mbright/mbright
brew install axklim/mbright/mbright
```

### From source

```bash
git clone https://github.com/axklim/mbright.git && cd mbright
swift build -c release
cp .build/release/mbright .build/release/mbrightd .build/release/mbright-menubar /usr/local/bin/
```

All three binaries must end up in the same directory: the CLI and the menu
bar app look for `mbrightd` next to themselves before falling back to `PATH`.

## Usage

```bash
mbright list                  # every display and its brightness
mbright get                   # main display, bare integer for scripting
mbright get -d ultrafine      # by name substring
mbright set 80                # main display
mbright set 80 --all          # every display
mbright up 10 -d studio       # relative, clamped at 100
mbright down 10 --all         # relative, clamped at 0
```

`list` is the default subcommand, so bare `mbright` is the same as `mbright list`.

### Menu bar app

```bash
mbright-menubar &
```

Puts a sun icon in the menu bar. The menu lists every connected display with
a slider; dragging a slider sets that display's brightness immediately.
Displays that appear or disappear while the app runs show up in the menu
without a restart. Displays without brightness control are listed with no
slider.

Brightness changed elsewhere, by the CLI, System Settings, a keyboard key, or
the display's own auto-brightness, shows up in the open menu within a moment:
the daemon subscribes to the system's brightness change notifications and
pushes them to the app.

**Settings…** has one option, *Launch at login*, which writes
`~/Library/LaunchAgents/com.axklim.mbright.menubar.plist`. It takes effect at
the next login and is removed again by unchecking the box. If
`XDG_RUNTIME_DIR` is set when you enable it, that value is written into the
plist, because launchd does not pass your shell environment to the app;
change the variable later and you need to re-enable the checkbox. **Quit** stops the
menu bar app only; `mbrightd` keeps running until `mbright daemon stop`.

### The daemon

`mbrightd` listens on a Unix socket at `$XDG_RUNTIME_DIR/mbright/mbrightd.sock`,
per the XDG Base Directory specification. macOS does not set
`XDG_RUNTIME_DIR`, so by default that resolves to the per-user temp directory
launchd provides (`/var/folders/.../T/mbright/`). Set `XDG_RUNTIME_DIR` to
move it; the clients pass their environment on to the daemon they spawn.

The daemon never starts or stops on its own. The CLI needs one running:

```bash
mbright daemon start          # start in the background; no-op if running
mbright daemon status         # exit 0 if running, 1 if not
mbright daemon stop           # ask it to exit; removes the socket
mbright list                  # error if no daemon is running
mbright list --daemon-autostart   # start one first if needed
```

Every CLI command accepts `--daemon-autostart`. Without it, a missing daemon
is an error that names both ways to start one. The menu bar app always
starts the daemon if none is running, since launching the app is itself the
request for one.

`mbrightd` runs in the foreground until SIGTERM or `mbright daemon stop`.
Starting a second copy on the same socket fails with an error instead of
evicting the first one.

### Selecting a display: `--display` / `-d`

`--display` accepts, in this exact order of precedence:

1. A list index (the `INDEX` column from `list`).
2. A `CGDirectDisplayID` (the `ID` column from `list`).
3. A case-insensitive substring of the display's name.

The lookup tries each form in that order and stops at the first match — it is
not a best-match search.

This matters because indices and display IDs share a numeric namespace and
*do* collide in practice. On the machine this was built and tested on, the
list indices are 0 and 1, while the underlying display IDs are 3 and 2. A
numeric `--display` value is always tried as an index first; it only falls
through to an ID lookup if no display has that index. So `--display 2` on
this machine resolves to index 2 (which doesn't exist, so it falls through)
and then to ID 2 — the LG UltraFine — while `--display 1` resolves to index 1
directly and never reaches ID matching at all. Since indices shift whenever
displays are unplugged, replugged, or reordered, but IDs are more stable and
names are stable, **scripts should prefer name substrings** (`-d studio`,
`-d ultrafine`) over numeric selectors.

## Development

```bash
./scripts/test.sh             # NOT bare `swift test` — see below
```

76 tests, none requiring hardware. Most are pure-function tests; the
controller and daemon request-handler tests run against a fake
`BrightnessBackend`, and the socket tests run a real `mbrightd` server loop
in-process against a temporary socket.

Package layout:

| Target | What it is |
| --- | --- |
| `MBrightCore` | Display enumeration, `DisplayServices` backend, brightness logic |
| `MBrightIPC` | Wire messages, JSON-lines codec, Unix socket server and clients |
| `MBrightMenuBar` | Status item, sliders, settings window, launch agent |
| `mbright`, `mbrightd`, `mbright-menubar` | The three executables |

The design, including the architecture diagram, is in
`docs/superpowers/specs/2026-09-06-menu-bar-app-design.md`.

Swift Testing ships with Command Line Tools but is not on SwiftPM's default
search path, so `scripts/test.sh` supplies the framework and rpath flags. Bare
`swift test` fails with `no such module 'Testing'`. XCTest is unavailable
without full Xcode.

### Releasing

Homebrew pins each release to a tag's tarball and that tarball's checksum, so
a release is a tag plus a formula bump, in this order:

1. Bump `Version.current` in `Sources/MBrightCore/Version.swift` and commit.
2. Tag and push:

   ```bash
   git tag -a v0.2.0 -m "mbright 0.2.0" && git push origin v0.2.0
   ```

3. Read the checksum of the tarball GitHub generates for the tag:

   ```bash
   curl -sL https://github.com/axklim/mbright/archive/refs/tags/v0.2.0.tar.gz | shasum -a 256
   ```

4. Put the new `url` and `sha256` into `Formula/mbright.rb` and push to
   `main`. Users pick it up with `brew update && brew upgrade`.

Never move a published tag. Homebrew caches downloads by checksum, so a moved
tag makes every other machine fail with a checksum mismatch.

The formula deliberately omits `depends_on xcode:`. Homebrew's Xcode
requirement is satisfied only by a full Xcode.app, and this package builds
with the Command Line Tools alone — adding that line would cost users a
multi-gigabyte install for nothing.

## Caveats

`DisplayServices` is a private framework with no public header. Apple can
change or remove it in any macOS release. If a required symbol disappears,
mbright fails at startup with a message naming the exact missing symbol,
rather than crashing or silently doing nothing.

`mbright-menubar` is a bare executable, not an `.app` bundle, so it has no
icon in the Dock or in System Settings and cannot use the modern login-item
API; Launch at login is a LaunchAgent plist instead.

mbright has only ever been run against one configuration: an Apple Studio
Display and an LG UltraFine, both connected to Apple Silicon. It has not been
tested on Intel Macs, built-in laptop panels, or any other external display.
It does not speak DDC/CI and is not expected to work with DDC/CI-only
monitors — everything goes through `DisplayServices`, keyed by
`CGDirectDisplayID`, not through DDC.

`set` permits 0, but setting a display to 0% brightness makes it look broken
(effectively off, with no obvious way back short of running `mbright set`
again from memory). Treat `set 0` as a footgun, not a feature.
