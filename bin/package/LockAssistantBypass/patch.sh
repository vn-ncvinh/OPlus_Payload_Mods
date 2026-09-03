#!/usr/bin/env bash
set -Eeuo pipefail

source "$ROOT_DIR/functions.sh"

[[ $# -eq 1 && -d "$1" ]] || die "Usage: LockAssistantBypass/patch.sh <jar.out>"
python3 "$ROOT_DIR/bin/package/LockAssistantBypass/patcher.py" "$1" \
    || die "OplusCustomizeService targets are incompatible"
