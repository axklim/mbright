# CLI reference

```
mbright [list]                       every display and its brightness
mbright get [-d <sel>]               one display, bare integer
mbright set <0-100> [-d <sel>|--all]
mbright up [<delta>] [-d <sel>|--all]     default 10, clamped at 100
mbright down [<delta>] [-d <sel>|--all]   default 10, clamped at 0
mbright daemon start|stop|status
```

Every command accepts `--daemon-autostart`. Without it, a missing daemon is
an error:

```
Error: mbrightd is not running. Start it with 'mbright daemon start' or pass --daemon-autostart.
```

## list

```
INDEX  NAME            VENDOR  ID  BRIGHTNESS
0*     Studio Display  APP     3   49%
1      LG UltraFine    GSM     2   49%
```

`*` marks the main display. `INDEX` and `ID` (the `CGDirectDisplayID`) are
both valid `--display` values. BRIGHTNESS is `37%`, `-` (no brightness
control; still exit 0), or `ERROR` (control claimed but the read failed;
details on stderr and a non-zero exit, so a partial failure never looks
clean).

## get

Prints one bare integer so it composes in scripts. `get --all` is a usage
error; use `list`.

## set, up, down

`set` accepts 0 to 100. `up` and `down` accept a delta of 0 to 100 and
clamp at the ends, so a hotkey held at the limit is a no-op, not an error.
A negative delta is a usage error; use `down`. Under `--all`, a failure on
one display does not abort the others; every failure is reported and the
exit is non-zero.

## Selecting a display: `--display` / `-d`

Strict precedence, first match wins:

1. list index (`INDEX` column)
2. `CGDirectDisplayID` (`ID` column)
3. case-insensitive substring of the name

Indices and IDs share a numeric namespace and do collide: on the reference
machine indices are 0 and 1 while IDs are 3 and 2, so `-d 2` falls through
index 2 (none) to ID 2. Indices shift on replug; names do not. Scripts
should use name substrings. A substring matching several displays is an
error listing them.

`--display` and `--all` together is a usage error.

## daemon

- `start`: spawns `mbrightd` detached (own session, stdio to `/dev/null`),
  looked up next to the `mbright` binary first, then on `PATH`. No-op if
  one is already running.
- `status`: prints version and socket; exit 1 when not running.
- `stop`: asks the daemon to exit. It replies, removes its socket, and exits.

Socket location and `XDG_RUNTIME_DIR` handling: `docs/architecture.md`.

## Menu bar app

`mbright-menubar &` puts a sun icon in the menu bar. Each display gets a
slider; unsupported displays are listed without one. The menu follows
hotplug and brightness changes made elsewhere. Settings has one option,
Launch at login, which writes a LaunchAgent plist and takes effect at the
next login. Quit stops the app only; the daemon keeps running until
`mbright daemon stop`.
