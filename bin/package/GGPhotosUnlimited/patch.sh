#!/usr/bin/env bash
set -Eeuo pipefail

source "$ROOT_DIR/functions.sh"

[[ $# -eq 1 && -d "$1" ]] || die "Usage: GGPhotosUnlimited/patch.sh <jar.out>"
jar_out="$1"
python3 "$ROOT_DIR/bin/package/GGPhotosUnlimited/patcher.py" "$jar_out" \
    || die "Google Photos smali anchors were not found"

max_dex=1
for folder in "$jar_out"/classes*.dex.out; do
    [[ -d "$folder" ]] || continue
    name="$(basename "$folder")"
    number="${name#classes}"
    number="${number%.dex.out}"
    [[ -z "$number" ]] && number=1
    (( number > max_dex )) && max_dex=$number
done
new_dex="$jar_out/classes$((max_dex + 1)).dex.out"
mkdir -p "$new_dex/com/xiaomi/globalmods/framework"

for class in Instrumentation.smali ApplicationPackageManager.smali; do
    class_path="$(find "$jar_out" -type f -name "$class" -print -quit)"
    [[ -n "$class_path" ]] || die "$class not found after patching"
    relative="${class_path#*.dex.out/}"
    mkdir -p "$new_dex/$(dirname "$relative")"
    mv "$class_path" "$new_dex/$relative"
done
cp -f "$ROOT_DIR/bin/package/GGPhotosUnlimited/smali/com/xiaomi/globalmods/framework/GooglePhotosSpoof.smali" \
    "$new_dex/com/xiaomi/globalmods/framework/GooglePhotosSpoof.smali"
