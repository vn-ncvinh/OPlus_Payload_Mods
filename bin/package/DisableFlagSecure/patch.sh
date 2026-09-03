#!/usr/bin/env bash
set -Eeuo pipefail

source "$ROOT_DIR/functions.sh"

[[ $# -eq 1 && -d "$1" ]] || die "Usage: DisableFlagSecure/patch.sh <jar.out>"
python3 "$ROOT_DIR/bin/package/DisableFlagSecure/patcher.py" "$1" \
    || die "DisableFlagSecure targets are incompatible"
