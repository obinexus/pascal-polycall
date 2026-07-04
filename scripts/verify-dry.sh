#!/usr/bin/env sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

if grep -E -n 'fopen|open\(|CreateFile|sscanf|strtok|socket\(|connect\(' \
    "$root/src/pascal_polycall.c" "$root/src/PascalPolycall.pas"; then
    echo "pascal-polycall must not parse configuration or implement runtime logic" >&2
    exit 1
fi

grep -F -q 'polycall_ffi_run_config(config_path, 1)' \
    "$root/src/pascal_polycall.c"
grep -F -q 'PAnsiChar(StablePath)' "$root/src/PascalPolycall.pas"
grep -F -q 'raise EPolycallError.Create(Status)' \
    "$root/src/PascalPolycall.pas"

echo "pascal-polycall thin-adapter check: PASS"
