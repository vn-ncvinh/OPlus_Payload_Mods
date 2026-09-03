#!/usr/bin/env bash
set -Eeuo pipefail

source "$ROOT_DIR/functions.sh"

[[ $# -eq 1 && -d "$1" ]] || die "Usage: DisableSafeMediaVolume/patch.sh <jar.out>"
python3 "$ROOT_DIR/bin/package/DisableSafeMediaVolume/patcher.py" "$1" \
    || die "SoundDoseHelper target is incompatible"
