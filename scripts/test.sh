#!/usr/bin/env bash
# Swift Testing ships with Command Line Tools but is not on SwiftPM's default
# search path. These flags put it there. Bare `swift test` fails without them.
set -euo pipefail

DEV="$(xcode-select -p)"
FW="$DEV/Library/Developer/Frameworks"
LIB="$DEV/Library/Developer/usr/lib"

if [[ -d "$FW" && -d "$LIB" ]]; then
  exec env DYLD_LIBRARY_PATH="$LIB" swift test \
    -Xswiftc -F -Xswiftc "$FW" \
    -Xlinker -F -Xlinker "$FW" \
    -Xlinker -rpath -Xlinker "$FW" \
    -Xlinker -rpath -Xlinker "$LIB" \
    "$@"
else
  exec swift test "$@"
fi
