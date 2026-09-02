#!/usr/bin/env bash
set -Eeuo pipefail

source "$ROOT_DIR/functions.sh"

mapfile -d '' framework_jars < <(find "$IMAGES_DIR/system" -type f -name framework.jar -print0)
[[ ${#framework_jars[@]} -eq 1 ]] || die "Expected one framework.jar, found ${#framework_jars[@]}"
jar_path="${framework_jars[0]}"
temp_dir="$(mktemp -d "$WORK_DIR/kousei-framework.XXXXXX")"
jar_out="$temp_dir/framework.jar.out"
mkdir -p "$jar_out"

unzip -q "$jar_path" -d "$jar_out" || die "Unable to unpack framework.jar"
for dex in "$jar_out"/classes*.dex; do
    [[ -f "$dex" ]] || continue
    java -jar "$ROOT_DIR/bin/apktool/baksmaliv2.jar" d --api "$SDK_LEVEL" "$dex" -o "$dex.out" \
        || die "baksmali failed for $(basename "$dex")"
    rm -f "$dex"
done

python3 "$ROOT_DIR/bin/package/KouseiPatcher/photos_patcher.py" "$jar_out" \
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
cp -f "$ROOT_DIR/bin/package/KouseiPatcher/photos_smali/com/xiaomi/globalmods/framework/GooglePhotosSpoof.smali" \
    "$new_dex/com/xiaomi/globalmods/framework/GooglePhotosSpoof.smali"

for folder in "$jar_out"/classes*.dex.out; do
    [[ -d "$folder" ]] || continue
    dex="${folder%.out}"
    java -jar "$ROOT_DIR/bin/apktool/smaliv2.jar" a --api "$SDK_LEVEL" "$folder" -o "$dex" \
        || die "smali failed for $(basename "$folder")"
    rm -rf "$folder"
done

(cd "$jar_out" && "$SEVENZIP" a -tzip -mx=0 "$temp_dir/framework-unaligned.jar" . >/dev/null) \
    || die "Unable to rebuild framework.jar"
zipalign -f 4 "$temp_dir/framework-unaligned.jar" "$temp_dir/framework.jar" \
    || die "zipalign failed for framework.jar"
cp -f "$temp_dir/framework.jar" "$jar_path"
mark_modified_path "$jar_path"
mods "Google Photos spoof patched in $jar_path"
