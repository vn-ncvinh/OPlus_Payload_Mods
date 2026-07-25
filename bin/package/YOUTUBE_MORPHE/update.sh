#!/usr/bin/env bash
set -Eeuo pipefail

source "$ROOT_DIR/functions.sh"

module_url="${YOUTUBE_MORPHE_URL:-}"
update_json_url="${YOUTUBE_MORPHE_UPDATE_JSON_URL:-https://raw.githubusercontent.com/j-hc/revanced-magisk-module/refs/heads/update/youtube-morphe-update.json}"
package_name="com.google.android.youtube"

if [[ -z "$module_url" ]]; then
    mods "Resolving latest YouTube Morphe module URL"
    module_url="$(python3 - "$update_json_url" <<'PY'
import json
import sys
from urllib.request import urlopen

with urlopen(sys.argv[1], timeout=30) as response:
    payload = json.load(response)
url = payload.get("zipUrl", "")
if not isinstance(url, str) or not url.startswith(("http://", "https://")):
    raise SystemExit("zipUrl not found in update JSON")
print(url)
PY
    )" || die "Failed to resolve YouTube Morphe module URL"
fi

temp_dir="$(mktemp -d "$WORK_DIR/youtube-morphe.XXXXXX")"
module_zip="$temp_dir/module.zip"
module_out="$temp_dir/module"

mods "Downloading YouTube Morphe module"
aria2c --allow-overwrite=true --auto-file-renaming=false --file-allocation=none \
    -s 8 -x 8 -j 1 -d "$temp_dir" -o module.zip "$module_url" >/dev/null \
    || die "YouTube Morphe download failed"
unzip -q "$module_zip" -d "$module_out" || die "Invalid YouTube Morphe module ZIP"

mapfile -d '' module_props < <(find "$module_out" -type f -name module.prop -print0)
[[ ${#module_props[@]} -eq 1 ]] || die "Expected exactly one module.prop"
module_root="$(dirname "${module_props[0]}")"
module_prop="$module_root/module.prop"
module_config="$module_root/config"
patched_apk="$module_root/base.apk"
stock_apk="$module_root/stock/base.apk"

tr -d '\r' < "$module_prop" | grep -q '^id=youtube-morphe-jhc$' \
    || die "ZIP is not a j-hc YouTube Morphe module"
[[ -f "$module_config" ]] || die "YouTube Morphe config is missing"
tr -d '\r' < "$module_config" | grep -q '^PKG_NAME=com.google.android.youtube$' \
    || die "Unexpected package name in module config"
[[ -s "$patched_apk" && -s "$stock_apk" ]] || die "Module stock/patched APK is missing"

apk_badging() { aapt dump badging "$1" 2>/dev/null; }
apk_package() { apk_badging "$1" | sed -n "s/^package: name='\([^']*\)'.*/\1/p"; }
apk_version() { apk_badging "$1" | sed -n "s/^package:.*versionName='\([^']*\)'.*/\1/p"; }

stock_package="$(apk_package "$stock_apk")"
patched_package="$(apk_package "$patched_apk")"
stock_version="$(apk_version "$stock_apk")"
patched_version="$(apk_version "$patched_apk")"
expected_version="$(tr -d '\r' < "$module_config" | sed -n 's/^PKG_VER=//p')"

[[ "$stock_package" == "$package_name" && "$patched_package" == "$package_name" ]] \
    || die "Unexpected YouTube package name in module"
[[ -n "$stock_version" && "$stock_version" == "$patched_version" ]] \
    || die "Stock/Morphe version mismatch: $stock_version vs $patched_version"
[[ -n "$expected_version" && "$expected_version" == "$patched_version" ]] \
    || die "APK/module version mismatch: $patched_version vs $expected_version"

mods "Removing existing YouTube packages"
while IFS= read -r -d '' apk; do
    if [[ "$(apk_package "$apk" || true)" == "$package_name" ]]; then
        apk_parent="$(dirname "$apk")"
        case "$(realpath -m "$apk_parent")" in
            "$IMAGES_DIR"/*/*)
                mark_modified_path "$apk_parent"
                info "Removing $apk_parent"
                rm -rf -- "$apk_parent"
                ;;
            *) die "Refusing to remove unsafe APK directory: $apk_parent" ;;
        esac
    fi
done < <(find "$IMAGES_DIR" -type f -iname '*.apk' -ipath '*youtube*' -print0)

my_product="$IMAGES_DIR/my_product"
system_root="$IMAGES_DIR/system"
[[ -d "$system_root/system/framework" ]] && system_root="$system_root/system"
stock_target="$my_product/app/YouTube"
patched_target="$my_product/etc/youtube-morphe"
init_target="$system_root/etc/init"

rm -rf -- "$stock_target" "$patched_target"
mkdir -p "$stock_target/lib/arm64" "$patched_target/lib/arm64" "$init_target"
cp -f "$stock_apk" "$stock_target/YouTube.apk"
cp -f "$patched_apk" "$patched_target/YouTube.apk"
cp -f "$ROOT_DIR/bin/package/YOUTUBE_MORPHE/youtube-morphe.rc" "$init_target/youtube-morphe.rc"

mapfile -t native_libs < <(unzip -Z1 "$stock_apk" | grep '^lib/arm64-v8a/.*\.so$' || true)
[[ ${#native_libs[@]} -gt 0 ]] || die "Stock YouTube APK has no arm64-v8a libraries"
unzip -q -j "$stock_apk" 'lib/arm64-v8a/*.so' -d "$stock_target/lib/arm64"
unzip -q -j "$stock_apk" 'lib/arm64-v8a/*.so' -d "$patched_target/lib/arm64"

find "$stock_target" "$patched_target" -type d -exec chmod 0755 {} +
find "$stock_target" "$patched_target" -type f -exec chmod 0644 {} +
chmod 0644 "$init_target/youtube-morphe.rc"
mark_modified my_product
mark_modified system

mods "YouTube Morphe $patched_version integrated into my_product"
warn "Disable automatic YouTube updates in Play Store"
