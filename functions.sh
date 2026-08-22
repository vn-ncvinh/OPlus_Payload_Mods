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
