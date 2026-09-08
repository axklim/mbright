# CLI reference

```
mbright [list]                       every display and its brightness
mbright get [-d <sel>]               one display, bare integer
mbright set <0-100> [-d <sel>|--all]
mbright up [<delta>] [-d <sel>|--all]     default 10, clamped at 100
mbright down [<delta>] [-d <sel>|--all]   default 10, clamped at 0
mbright daemon start|stop|status
mbright daemon enable-login [--no-ui]   start at login; --no-ui starts mbrightd alone
mbright daemon disable-login
mbright config [show]                   config path and current settings
mbright config init                     write the file from current settings
mbright config reload                   re-read a hand-edited file
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
  looked up next to the `mbright` binary first, then in `../Helpers` (its
  place in the app bundle), then on `PATH`. No-op if
  one is already running.
- `status`: prints version and socket; exit 1 when not running.
- `stop`: asks the daemon to exit. It replies, removes its socket, and exits.

Socket location and `XDG_RUNTIME_DIR` handling: `docs/architecture.md`.

## daemon status, login and config

`daemon status` prints the running line and then the login state:

```
mbrightd 0.4.0 is running on /var/folders/.../mbright/mbrightd.sock
login: enabled, starts the menu bar app
```

`enable-login` and `disable-login` print the resulting login line. Both
need the installed app (`make install`); from a build-directory daemon
`enable-login` fails naming the path it runs from. Takes effect at the next
login.

`config show` prints the path, whether the file exists, and the values:

```
~/.config/mbright/config.json (not written yet)
login: disabled
ui: menu bar app
```

`config init` writes that file once and never overwrites it. `config
reload` re-reads it after a hand edit and prints the same block; a
malformed file is an error and the daemon keeps its previous settings.
Only `mbrightd` touches the file, so every config command needs a running
daemon or `--daemon-autostart`.

## Menu bar app

`open -a mbright` (or Spotlight) puts a sun icon in the menu bar. Each display gets a
slider; unsupported displays are listed without one. The menu follows
hotplug and brightness changes made elsewhere. Settings has one option,
Launch at login, the same setting as `mbright daemon enable-login`; it
takes effect at the next login. Quit asks the daemon to stop before the app exits, so the CLI
needs `mbright daemon start` or `--daemon-autostart` afterwards.
