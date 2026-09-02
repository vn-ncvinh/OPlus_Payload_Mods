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
fi

for part in system_ext my_product my_stock; do
    [[ -d "$IMAGES_DIR/$part" ]] || continue
    while IFS= read -r -d '' app_root; do
        while IFS= read -r -d '' app_dir; do
            app_name="${app_dir##*/}"
            if [[ -n "${debloat_apps[$app_name]+x}" ]]; then
                remove_path "$app_dir"
            fi
        done < <(find "$app_root" -mindepth 1 -maxdepth 1 -type d -print0)
    done < <(
        find "$IMAGES_DIR/$part" -type d \
            \( -name app -o -name priv-app -o -name del-app -o -name del-app-pre \) \
            -print0
    )
done

mods "Debloat completed"
