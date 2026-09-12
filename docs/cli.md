# CLI reference

```
mbright [list]                       every display and its brightness
mbright get [-d <sel>]               one display, bare integer
mbright set <0-100> [-d <sel>|--all]
mbright up [<delta>] [-d <sel>|--all]     default 10, clamped at 100
mbright down [<delta>] [-d <sel>|--all]   default 10, clamped at 0
mbright sync [off|full|relative]     other displays follow the main display
mbright debug [on|off]               write debug logs
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

## sync

Without an argument prints the mode. With one, saves it to the config
and prints the result. `full` sets every other display to the main
display's value, at once and on every later change. `relative` moves
every other display by the same amount as the main display and keeps
each display's own level; adjusting a secondary changes its distance
from main. Both react to any change to main: the CLI, the menu bar,
keyboard keys, System Settings, or auto-brightness. `set`, `up` and
`down` with `--all` write every display once; sync does not add to
that. A failed write to a secondary is reported the way `--all` reports
one.

## debug

Without an argument prints the state. With one, saves it to the config
and prints the result. When on, `mbrightd` writes `mbrightd.log` and the
menu bar app writes `mbright-menubar.log` under
`$XDG_STATE_HOME/mbright/` (`~/.local/state/mbright/` by default). Both
react at once; no restart. The files are append-only and never rotated,
so turn it off when done. What they contain: every request and reply,
every display reconfiguration callback and what the displays reported
after it settled, brightness notifications, sync decisions, and the menu
bar app's readings and menu rebuilds.

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

`enable-login` and `disable-login` print the resulting login line.
`enable-login` needs the installed app (`make install`); from a
build-directory daemon it fails naming the path it runs from.
`disable-login` works from any daemon, installed or not. Takes effect at
the next login.

`config show` prints the path, whether the file exists, and the values:

```
~/.config/mbright/config.json (not written yet)
login: disabled
ui: menu bar app
sync: off
debug: off
hotkeys:
  lopt+f1  main down 10
  lopt+f2  main up 10
  ropt+f1  secondary down 10
  ropt+f2  secondary up 10
```

`config init` writes that file once and never overwrites it. `config
reload` re-reads it after a hand edit and prints the same block; a
malformed file is an error and the daemon keeps its previous settings.
Only `mbrightd` touches the file, so every config command needs a running
daemon or `--daemon-autostart`.

## Keyboard shortcuts

The menu bar app listens for the shortcuts in the config's `hotkeys`
list. The default is Left Option + F1/F2 for the main display and Right
Option + F1/F2 for the secondary display (the first one that is not
main), 10 points per press; holding the key repeats. Shortcuts need
Accessibility access for mbright (System Settings > Privacy & Security >
Accessibility); the app asks once and Settings shows a button while it is
missing. On Apple keyboards F1 and F2 are the brightness keys unless "Use
F1, F2, etc. keys as standard function keys" is on; otherwise hold Fn as
well.

To change them, `mbright config init` once, edit the file, then `mbright
config reload`:

```json
"hotkeys": [
  { "keys": "lopt+f1", "action": "down", "display": "main" },
  { "keys": "lopt+f2", "action": "up",   "display": "main" },
  { "keys": "ropt+f1", "action": "down", "display": "secondary" },
  { "keys": "ropt+f2", "action": "up",   "display": "secondary" }
]
```

| Field | Values | Default |
| --- | --- | --- |
| `keys` | modifiers and one key joined by `+` | required |
| `action` | `up`, `down` | required |
| `display` | `main`, `secondary`, `all`, or a `--display` selector | `main` |
| `step` | 1 to 100 | 10 |

`keys` is case-insensitive. Modifiers: `cmd`, `ctrl`, `opt`, `shift`
(`command`, `control`, `option`, `alt` also work), each optionally
prefixed with `l` or `r` for one side only: `lopt`, `ropt`, `rcmd`,
`lshift`, ... An unsided modifier accepts either key. Keys: `f1` to
`f20`, `a` to `z`, `0` to `9`, `up`, `down`, `left`, `right`, `space`,
`tab`, `return`, `escape`, `delete`, `forwarddelete`, `home`, `end`,
`pageup`, `pagedown`, and `-` `=` `[` `]` `\` `;` `'` `,` `.` `/` `` ` ``.
Letters name the key at that position on a US layout. Anything but an
F-key needs at least one modifier. The other modifiers must not be held:
`lopt+f1` does not fire for Shift + Left Option + F1. Fn and Caps Lock
are ignored.

`"hotkeys": []` turns shortcuts off. A file with a binding that does not
parse is rejected as a whole by `config reload`, naming the binding, and
the daemon keeps its previous settings. Shortcuts need the menu bar app;
`enable-login --no-ui` starts no listener.

## Menu bar app

`open -a mbright` (or Spotlight) puts a sun icon in the menu bar. Each display gets a
slider; unsupported displays are listed without one. The menu follows
hotplug and brightness changes made elsewhere. Settings has Launch at login,
the same setting as `mbright daemon enable-login` (takes effect at the next
login), and Sync with main display, the same setting as `mbright sync`. Quit
asks the daemon to stop before the app exits, so the CLI
needs `mbright daemon start` or `--daemon-autostart` afterwards.
