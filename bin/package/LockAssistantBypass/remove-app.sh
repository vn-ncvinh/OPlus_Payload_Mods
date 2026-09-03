#!/usr/bin/env bash
set -Eeuo pipefail

source "$ROOT_DIR/functions.sh"

for part in system system_ext my_product my_stock; do
    [[ -d "$IMAGES_DIR/$part" ]] || continue
    while IFS= read -r -d '' app_root; do
        while IFS= read -r -d '' app_dir; do
            mark_modified_path "$app_dir"
            info "Removing $app_dir"
            rm -rf -- "$app_dir"
        done < <(
            find "$app_root" -mindepth 1 -maxdepth 1 -type d \
                -name LockAssistant -print0
        )
    done < <(
        find "$IMAGES_DIR/$part" -type d \
            \( -name app -o -name priv-app -o -name del-app -o -name del-app-pre \) \
            -print0
    )
done
