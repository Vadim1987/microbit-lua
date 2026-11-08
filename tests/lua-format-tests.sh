#!/usr/bin/env bash
# Host test for source/lua-format.c: builds it and source/lua-number2str.c
# with the host's C compiler and checks what string.format's float items
# write.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
: > "$TMP/lua.h"   # lua-number2str.c includes it and uses none of it

cc -std=c99 -O2 -Wall -Wextra -I"$TMP" -o "$TMP/test" \
  "$ROOT/tests/lua-format-test.c" "$ROOT/source/lua-format.c" \
  "$ROOT/source/lua-number2str.c" -lm
"$TMP/test"
