#!/usr/bin/env bash
set -Eeuo pipefail

source "$ROOT_DIR/functions.sh"

declare -A debloat_apps=()
while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    debloat_apps["$line"]=1
done < "$ROOT_DIR/bin/ddevice/DEBLOAT/APPLIST.txt"

remove_path() {
    local path="$1"
    [[ -e "$path" ]] || return 0
    mark_modified_path "$path"
    info "Removing $path"
    rm -rf -- "$path"
}

if [[ -d "$IMAGES_DIR/my_product" ]]; then
    while IFS= read -r -d '' path; do
        remove_path "$path"
    done < <(find "$IMAGES_DIR/my_product/etc" -maxdepth 1 -name 'auto-install*' -print0 2>/dev/null || true)
    remove_path "$IMAGES_DIR/my_product/app/Updater"
    remove_path "$IMAGES_DIR/my_product/etc/permissions/cn.google.services.xml"
fi

while IFS= read -r -d '' app_dir; do
    app_name="${app_dir##*/}"
    if [[ -n "${debloat_apps[$app_name]+x}" ]]; then
        remove_path "$app_dir"
    fi
done < <(find "$IMAGES_DIR" -depth -type d -print0)

mods "Debloat completed"
