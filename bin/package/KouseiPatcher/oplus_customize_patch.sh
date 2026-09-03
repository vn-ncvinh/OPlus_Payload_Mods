#!/usr/bin/env bash
set -Eeuo pipefail

source "$ROOT_DIR/functions.sh"

mapfile -d '' jars < <(find "$IMAGES_DIR/system" -type f -name oplus-services.jar -print0)
[[ ${#jars[@]} -eq 1 ]] || die "Expected one oplus-services.jar, found ${#jars[@]}"

jar_path="${jars[0]}"
temp_dir="$(mktemp -d "$WORK_DIR/oplus-customize.XXXXXX")"
jar_out="$temp_dir/out"
mkdir -p "$jar_out"

unzip -q "$jar_path" -d "$jar_out" || die "Unable to unpack $jar_path"
dex_count=0
for dex in "$jar_out"/classes*.dex; do
    [[ -f "$dex" ]] || continue
    dex_count=$((dex_count + 1))
    java -jar "$ROOT_DIR/bin/apktool/baksmaliv2.jar" d --api "$SDK_LEVEL" "$dex" -o "$dex.out" \
        || die "baksmali failed for oplus-services.jar/$(basename "$dex")"
    rm -f "$dex"
done
[[ "$dex_count" -gt 0 ]] || die "oplus-services.jar contains no DEX files"

python3 "$ROOT_DIR/bin/package/KouseiPatcher/oplus_customize_patcher.py" "$jar_out" \
    || die "OplusCustomizeService targets are incompatible"

for folder in "$jar_out"/classes*.dex.out; do
    [[ -d "$folder" ]] || continue
    dex="${folder%.out}"
    java -jar "$ROOT_DIR/bin/apktool/smaliv2.jar" a --api "$SDK_LEVEL" "$folder" -o "$dex" \
        || die "smali failed for oplus-services.jar/$(basename "$folder")"
    rm -rf "$folder"
done

(cd "$jar_out" && "$SEVENZIP" a -tzip -mx=0 "$temp_dir/unaligned.jar" . >/dev/null) \
    || die "Unable to rebuild oplus-services.jar"
zipalign -f 4 "$temp_dir/unaligned.jar" "$temp_dir/patched.jar" \
    || die "zipalign failed for oplus-services.jar"
cp -f "$temp_dir/patched.jar" "$jar_path"
mark_modified_path "$jar_path"
mods "OplusCustomizeService patch applied to $jar_path (3 targets)"
