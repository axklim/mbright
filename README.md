# mbright

Open-source brightness control for macOS displays, from the command line.

Works with displays that ignore DDC/CI — including the Apple Studio Display and
LG UltraFine — by going through Apple's own `DisplayServices` layer. No
background app, no root, no permission prompts.

## Why

`brightness` handles built-in laptop panels only. `m1ddc` and `ddcctl` need
DDC/CI, which neither the Studio Display nor the UltraFine speaks. MonitorControl
is a GUI. `betterdisplaycli` works but is closed source and needs its app running.

## Install

Requires macOS 14+ and the Swift toolchain (Xcode Command Line Tools is enough).

```bash
git clone <repo-url> && cd mac-brightness
swift build -c release
cp .build/release/mbright /usr/local/bin/
```

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

### `list`

```
$ mbright list
INDEX  NAME            VENDOR  ID  BRIGHTNESS
0*     Studio Display  APP     3   49%
1      LG UltraFine    GSM     2   49%
```

`*` after the index marks the main display. Both `INDEX` (0, 1, ...) and `ID`
(the display's `CGDirectDisplayID`) are valid values for `--display`.

The BRIGHTNESS column has three states:

- `37%` — a normal reading.
- `-` — the display reports no brightness control at all. This is a normal
  condition (e.g. an unsupported monitor) and `list` still exits 0.
- `ERROR` — the display claims to support brightness control, but reading it
  failed. When any display shows `ERROR`, `list` prints the failure details to
  stderr and exits non-zero, so a partial failure can never look like a clean
  run.

### `get`

`get` reports exactly one display by design, so its bare-integer output
composes cleanly in scripts (`brightness=$(mbright get -d studio)`). Because
of that, `get --all` is rejected as a usage error rather than printing
multiple numbers a script would have to parse apart:

```
$ mbright get --all
Error: get does not support --all; use 'mbright list'.
```

Use `mbright list` if you want brightness for every display at once.

### `up` / `down`

The delta argument to `up` and `down` must be between 0 and 100 inclusive;
anything outside that range is rejected as a usage error before any display
is touched:

```
$ mbright up 500
Error: Delta must be between 0 and 100.
```

There is no way to pass a negative delta to flip `up` into a decrease (or
`down` into an increase) — `mbright up -- -20` is a validation error, not a
20-point decrease. Use `down` for decreases.

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

48 tests, none requiring hardware. Most are pure-function tests; the controller tests run against a fake `BrightnessBackend`.

Swift Testing ships with Command Line Tools but is not on SwiftPM's default
search path, so `scripts/test.sh` supplies the framework and rpath flags. Bare
`swift test` fails with `no such module 'Testing'`. XCTest is unavailable
without full Xcode.

## Caveats

`DisplayServices` is a private framework with no public header. Apple can
change or remove it in any macOS release. If a required symbol disappears,
mbright fails at startup with a message naming the exact missing symbol,
rather than crashing or silently doing nothing.

mbright has only ever been run against one configuration: an Apple Studio
Display and an LG UltraFine, both connected to Apple Silicon. It has not been
tested on Intel Macs, built-in laptop panels, or any other external display.
It does not speak DDC/CI and is not expected to work with DDC/CI-only
monitors — everything goes through `DisplayServices`, keyed by
`CGDirectDisplayID`, not through DDC.

`set` permits 0, but setting a display to 0% brightness makes it look broken
(effectively off, with no obvious way back short of running `mbright set`
again from memory). Treat `set 0` as a footgun, not a feature.
