#!/usr/bin/env bash
set -Eeuo pipefail

source "$ROOT_DIR/functions.sh"

output_dir="${1:-}"
[[ -n "$output_dir" && -d "$output_dir" ]] || die "DISABLE_AVB requires an output directory"

patched_vbmeta=0
for part in vbmeta vbmeta_system vbmeta_vendor; do
    input="$RAW_DIR/$part.img"
    if [[ ! -f "$input" ]]; then
        warn "$part.img is absent; skipped"
        continue
    fi
    output="$output_dir/$part.img"
    cp -f "$input" "$output"
    python3 "$ROOT_DIR/bin/patch-vbmeta.py" "$output" >/dev/null \
        || die "Failed to patch $part.img"
    patched_vbmeta=$((patched_vbmeta + 1))
    mods "Patched $part.img"
done
[[ "$patched_vbmeta" -gt 0 ]] || die "No vbmeta image was available to patch"

bash "$ROOT_DIR/bin/package/DISABLE_AVB/HMATools/start" "$output_dir"
