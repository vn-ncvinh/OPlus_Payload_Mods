#!/usr/bin/env bash
set -Eeuo pipefail

source "$ROOT_DIR/functions.sh"

[[ ( $# -eq 1 || $# -eq 3 ) && -d "$1" ]] \
    || die "Usage: LockAssistantBypass/patch.sh <oplus-services.jar.out> [<subsys-channel-lock-plugin.jar.out> <snapshot.hex>]"
python3 "$ROOT_DIR/bin/package/LockAssistantBypass/patcher.py" "$1" \
    || die "OplusCustomizeService targets are incompatible"

if [[ $# -eq 3 ]]; then
    [[ -d "$2" && -f "$3" ]] \
        || die "LockAssistantBypass carrier-lock inputs are missing"
    python3 "$ROOT_DIR/bin/package/LockAssistantBypass/carrier-lock-patcher.py" "$2" "$3" \
        || die "LockAssistantBypass carrier-lock target is incompatible"
fi
