# mbright

macOS display brightness tool: `mbright` CLI, `mbrightd` daemon,
`mbright-menubar` app. Read `docs/architecture.md` before changing how the
pieces talk to each other.

## Build and test

- `swift build`; `./scripts/test.sh` for tests. Never bare `swift test`:
  Swift Testing is not on SwiftPM's search path with Command Line Tools, and
  XCTest is unavailable. Tests need no hardware.
- `make` wraps both and lists its targets. It builds into
  `$XDG_CACHE_HOME/mbright/build`, not `./.build`. `make install` puts all
  three binaries inside `~/Applications/mbright.app`: the clients in
  `Contents/MacOS`, `mbrightd` in `Contents/Helpers`. Clients look for
  `mbrightd` next to their own executable, then in `../Helpers`. The CLI is
  a symlink into the bundle. Keep the daemon out of `Contents/MacOS`, or
  LaunchServices treats a running daemon as the running app and launching
  the app does nothing.
  `make run` stops the installed app and runs the debug build in its place.
  Bare `swift build` still uses `./.build`.
- The project must keep building with Command Line Tools only, no Xcode.
  The `.app` is a plain directory `make install` writes from
  `scripts/Info.plist.in`; there is no Xcode project and no `SMAppService`.
- Version lives in `Sources/MBrightCore/Version.swift`. Release steps:
  `docs/releasing.md`.

## Rules

- `DisplayServices` is private API. Every symbol goes through `dlsym` with a
  checked result: required symbols fail at startup naming the symbol,
  optional ones degrade. Validate every value read from it.
- Only `mbrightd` may touch the displays. Clients speak the typed protocol in
  `MBrightIPC`; add a `Request`/`Response`/`Event` case rather than a side
  channel.
- Paths follow XDG Base Directory. `XDG_RUNTIME_DIR` is the only knob for
  the socket; do not add env or flag overrides. LaunchAgent plists are the
  one exception (launchd reads only `~/Library/LaunchAgents`).
- The daemon never starts or exits unasked. Keep it that way.
- Errors cross the wire as `MBrightError`; the CLI must print the same
  messages and exit codes it did in-process.

## Verifying on hardware

The dev machine has a Studio Display (main) and an LG UltraFine. Use a
scratch `XDG_RUNTIME_DIR=/tmp/<name>` so a test daemon never collides with
a real one, and `pkill -TERM -f mbrightd` afterwards. Add a scratch
`XDG_CONFIG_HOME` too. A scratch daemon never rewrites the login plist,
and a build-directory daemon cannot enable login; only the installed
bundle can. Use the LG for value assertions: the Studio Display has
auto-brightness on and its reading drifts by itself. Restore brightness
when done.

`screencapture -x` and System Events scripting work from a terminal here;
a bare executable's status item is `menu bar item 1 of menu bar 1`.

## Docs

Design specs go in `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`
with DOT diagrams. User-facing docs: `README.md` (minimal), `docs/cli.md`,
`docs/architecture.md`, `docs/releasing.md`.
