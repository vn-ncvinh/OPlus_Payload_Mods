#!/usr/bin/env bash
set -Eeuo pipefail

source "$ROOT_DIR/functions.sh"

temp_root="$(mktemp -d "$WORK_DIR/kousei-secure.XXXXXX")"
patched_total=0
index=0

while IFS= read -r -d '' jar_path; do
    index=$((index + 1))
    jar_name="$(basename "$jar_path")"
    temp_dir="$temp_root/$index"
    jar_out="$temp_dir/out"
    mkdir -p "$jar_out"

    unzip -q "$jar_path" -d "$jar_out" || die "Unable to unpack $jar_path"
    dex_count=0
    for dex in "$jar_out"/classes*.dex; do
        [[ -f "$dex" ]] || continue
        dex_count=$((dex_count + 1))
        java -jar "$ROOT_DIR/bin/apktool/baksmaliv2.jar" d --api "$SDK_LEVEL" "$dex" -o "$dex.out" \
            || die "baksmali failed for $jar_name/$(basename "$dex")"
        rm -f "$dex"
    done
    [[ "$dex_count" -gt 0 ]] || continue

    patch_log="$temp_dir/patch.log"
    python3 "$ROOT_DIR/bin/package/KouseiPatcher/services_secure_patcher.py" --allow-empty "$jar_out" \
        | tee "$patch_log"
    count="$(grep -c '^\[secure-flag\] patched ' "$patch_log" || true)"
    if [[ "$count" -eq 0 ]]; then
        continue
    fi

    for folder in "$jar_out"/classes*.dex.out; do
        [[ -d "$folder" ]] || continue
        dex="${folder%.out}"
        java -jar "$ROOT_DIR/bin/apktool/smaliv2.jar" a --api "$SDK_LEVEL" "$folder" -o "$dex" \
            || die "smali failed for $jar_name/$(basename "$folder")"
        rm -rf "$folder"
    done
    (cd "$jar_out" && "$SEVENZIP" a -tzip -mx=0 "$temp_dir/unaligned.jar" . >/dev/null) \
        || die "Unable to rebuild $jar_name"
    zipalign -f 4 "$temp_dir/unaligned.jar" "$temp_dir/patched.jar" \
        || die "zipalign failed for $jar_name"
    cp -f "$temp_dir/patched.jar" "$jar_path"
    mark_modified_path "$jar_path"
    patched_total=$((patched_total + count))
    mods "Secure-flag patch applied to $jar_path ($count targets)"
done < <(
    find "$IMAGES_DIR" -type f \
        \( -name services.jar -o -name oplus-services.jar -o -name miui-services.jar \) \
        -print0
)

[[ "$patched_total" -gt 0 ]] || die "No compatible secure-flag target was found"
mods "Secure-flag patch completed ($patched_total targets)"
