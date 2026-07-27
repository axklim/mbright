# mbright — macOS brightness CLI

**Date:** 2026-07-27
**Status:** Approved design

## Problem

No open-source CLI can set brightness on this machine's displays.

Target hardware: Apple M4 desktop, no built-in panel, two external displays —
Apple Studio Display (main) and LG UltraFine.

Existing tools were evaluated and ruled out:

| Tool | Why it fails here |
| --- | --- |
| `brightness` (nriley) | Built-in laptop panels only, via private CoreDisplay APIs |
| `m1ddc`, `ddcctl` | Require DDC/CI; neither the Studio Display nor the UltraFine speaks it |
| MonitorControl | Open source, but a menubar GUI with no CLI or scripting hook |
| `asdbctl`, `studi`, `asdcontrol` | Implement the right USB-HID protocol, but are Linux-only |
| `betterdisplaycli` | Works, but closed source, and requires the BetterDisplay app running |

The goal is to replace `betterdisplaycli` for brightness: a self-contained
open-source binary with no background app. Success means BetterDisplay can be
uninstalled.

## Feasibility evidence

The original plan was to port `asdbctl`'s USB-HID protocol to `IOHIDManager`.
A probe found a far simpler path and made that unnecessary.

`/System/Library/PrivateFrameworks/DisplayServices.framework` exports
brightness functions keyed by `CGDirectDisplayID`. A throwaway Swift probe
(`dlopen`, enumerate via `CGGetOnlineDisplayList`, then read and write back the
value just read) produced:

```
--- display[0] id=3 vendor=0x610  (APP = Apple) main=true  2880x1620
  CanChangeBrightness -> true
  GetBrightness       -> rc=0 value=0.374
  SetBrightness       -> rc=0 WRITABLE

--- display[1] id=2 vendor=0x9e6d (GSM = LG)    main=false 1620x2880
  CanChangeBrightness -> true
  GetBrightness       -> rc=0 value=0.493
  SetBrightness       -> rc=0 WRITABLE
```

Both displays are readable and writable with no root, no TCC prompt, and no HID
access. Apple's layer already handles each display's wire protocol, so both are
addressed identically. This removes the entire HID subsystem from scope.

## Architecture

Swift 6 package built with SwiftPM, producing a single `mbright` binary.
One dependency: `swift-argument-parser`.

Three layers, each independently testable:

```
Commands (ArgumentParser)  ->  BrightnessController  ->  DisplayServicesShim
list/get/set/up/down           display resolution,       dlopen + 4 symbols
                               percent<->float, clamping
```

### Modules

| File | Responsibility | Depends on |
| --- | --- | --- |
| `DisplayServicesShim.swift` | `dlopen`/`dlsym` the private framework; expose the four raw calls. No policy. | dlfcn, CoreGraphics |
| `DisplayRegistry.swift` | Enumerate online displays; attach friendly names; resolve a selector to a display. | CoreGraphics, AppKit |
| `BrightnessController.swift` | Percent<->float conversion, clamping, orchestration. Talks to `BrightnessBackend`. | protocol only |
| `Commands/*.swift` | One file per subcommand; parsing and output formatting only. | controller |
| `main.swift` | Entry point, root command registration. | commands |

`BrightnessController` depends on a `BrightnessBackend` protocol, not on the
shim directly. `DisplayServicesShim` is the production conformer; tests use a
fake. This is what keeps the logic testable without hardware.

### The shim

Four symbols, resolved at runtime:

```swift
DisplayServicesCanChangeBrightness(CGDirectDisplayID) -> Bool
DisplayServicesGetBrightness(CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
DisplayServicesSetBrightness(CGDirectDisplayID, Float) -> Int32
DisplayServicesSetBrightnessSmooth(CGDirectDisplayID, Float) -> Int32
```

`Int32` return is 0 on success. `SetBrightnessSmooth` is resolved but unused in
v1; it is listed here because it is the natural implementation of a future
`--fade` flag and costs nothing to bind now.

## Units

DisplayServices speaks `Float` in 0.0–1.0. The CLI speaks integer percent
0–100. Conversion happens only at the `BrightnessController` boundary, so all
rounding lives in one tested place.

- To device: `Float(percent) / 100.0`
- From device: `Int((value * 100).rounded())`

Round-tripping is not exact — the device returns a continuous value, so
`set 37` then `get` may report `37` from `0.3700001`. Rounding on read makes
this invisible at the CLI surface.

## Display targeting

`--display <selector>` / `-d <selector>` accepts, in strict precedence order:

1. Exact index from `list` (`0`, `1`)
2. Raw `CGDirectDisplayID`
3. Case-insensitive substring of the display's name (`studio`, `lg`, `ultrafine`)

Indices and display IDs share a numeric namespace and **do** collide in
practice: on the target machine the indices are 0 and 1 while the display IDs
are 3 and 2. Resolution is therefore strictly ordered, not best-match — a
numeric selector is looked up as an index first, and only if no such index
exists is it tried as a display ID. So `-d 0` and `-d 1` always mean indices,
and `-d 2`/`-d 3` mean display IDs because no index 2 or 3 exists. `list`
prints both columns so the mapping is never guesswork. Because indices shift
when displays are added or reordered, scripts should prefer name substrings.

Names come from `NSScreen.localizedName` — public API, no private calls.
Vendor is derived from `CGDisplayVendorNumber` decoded as an EDID PnP ID
(`0x610` -> `APP`, `0x9e6d` -> `GSM`) for display in `list`.

`--all` targets every online display. With neither flag, commands default to
the main display (`CGDisplayIsMain`).

A substring matching more than one display is an error listing the candidates —
never a silent pick. `--display` and `--all` together is a usage error.

## Commands

```
mbright list                     # table: index, name, vendor, id, brightness
mbright get [-d <sel>]           # prints bare integer, for scripting
mbright set <0-100> [-d <sel>|--all]
mbright up <delta> [-d <sel>|--all]
mbright down <delta> [-d <sel>|--all]
```

`get` prints a bare integer with no label or suffix so it composes in scripts.
`get --all` is a usage error: a bare-integer contract cannot represent multiple
displays; use `list` instead.

`set` accepts only 0–100; out-of-range is a usage error. `up`/`down` clamp at
the boundaries, since a hotkey pressed repeatedly at max should be a no-op
rather than an error. Setting 0 is allowed and makes a display appear off; this
matches BetterDisplay and is left to the user.

## Error handling

The one real fragility is that DisplayServices is private API with no header.
Failure modes, all exiting non-zero with a specific message:

| Condition | Behavior |
| --- | --- |
| `dlopen` fails | Report the path and `dlerror()`; state the framework is missing |
| `dlsym` returns null | Name the missing symbol and the macOS version; do not crash, do not silently no-op |
| `CanChangeBrightness` false | Name the display and say it does not support brightness control |
| `Get`/`Set` returns non-zero | Report the display and the return code |
| Selector matches nothing | List available displays |
| Selector is ambiguous | List the matching candidates |

Under `--all`, a failure on one display does not abort the others: each is
attempted, errors are collected and reported, and the exit code is non-zero if
any failed. A partial success must never look like a clean run.

## Testing

Unit tests against a fake `BrightnessBackend`, no hardware required:

- Percent<->float conversion, including rounding at boundaries (0, 1, 99, 100)
- Clamping for `up`/`down` at both ends
- Selector resolution: by index, by id, by substring, case-insensitivity
- Ambiguous selector produces an error naming all candidates
- Unmatched selector produces an error listing available displays
- `set` range validation rejects negatives and >100
- `--all` with a mid-list failure still attempts the rest and exits non-zero
- `get --all` and `-d` + `--all` are rejected as usage errors

`DisplayServicesShim` is the untestable edge (~40 lines, no branching). It is
verified manually against the real displays using the probe's no-op-write
technique: read the current value, write it back, assert rc == 0.

## Out of scope for v1

Deliberately excluded, per YAGNI:

- Contrast and volume control
- Smooth fades (`SetBrightnessSmooth` is bound but unused)
- Presets, profiles, persisted state
- A daemon, hotkey handling, or time-based schedules
- Homebrew tap and distribution packaging
- Any HID or DDC/CI code path

## Risks

**DisplayServices is private API.** Apple can rename or remove these symbols in
a macOS release. Mitigation is honest failure: `dlsym` is checked and reports
exactly which symbol vanished. Recovery, if it ever happens, is the HID port
that this design avoided — the `BrightnessBackend` protocol is the seam where an
alternate implementation would drop in.

**No CI coverage of the shim.** Hardware-dependent code is verified manually.
Accepted: the shim is small, branch-free, and changes rarely.
