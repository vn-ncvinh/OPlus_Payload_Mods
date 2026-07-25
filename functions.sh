#!/usr/bin/env bash

log() { printf '[%s] %s\n' "$1" "$2"; }
info() { log INFO "$*"; }
mods() { log MODS "$*"; }
warn() { log WARN "$*" >&2; }
error() { log ERROR "$*" >&2; }
die() { error "$*"; exit 1; }

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

partition_from_path() {
    local path
    path="$(realpath -m "$1")"
    case "$path" in
        "$IMAGES_DIR"/*)
            path="${path#"$IMAGES_DIR"/}"
            printf '%s\n' "${path%%/*}"
            ;;
        *) return 1 ;;
    esac
}

mark_modified() {
    local partition="$1"
    [[ -n "$partition" ]] || die "Cannot mark an empty partition name"
    printf '%s\n' "$partition" >> "$PATCH_STATE_DIR/modified_partitions"
}

mark_modified_path() {
    local partition
    partition="$(partition_from_path "$1")" || die "Path is outside extracted images: $1"
    mark_modified "$partition"
}

disable_avb_verify() {
    local root="$1"
    local changed=1
    local file before after

    while IFS= read -r -d '' file; do
        before="$(sha256sum "$file" | awk '{print $1}')"
        sed -i -E \
            -e 's/,avb_keys=[^,[:space:]]+//g' \
            -e 's/,avb=[^,[:space:]]+//g' \
            -e 's/,avb//g' \
            -e 's/,verify//g' \
            "$file"
        after="$(sha256sum "$file" | awk '{print $1}')"
        if [[ "$before" != "$after" ]]; then
            info "Disabled AVB flags in $file"
            changed=0
        fi
    done < <(find "$root" -type f -iname '*fstab*' -print0)

    return "$changed"
}
