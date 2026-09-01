#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT_DIR/functions.sh"

TOOLS_DIR="$ROOT_DIR/bin/Linux/$(uname -m)"
PAYLOAD_EXTRACT="$TOOLS_DIR/payload-extract"
GETTYPE="$TOOLS_DIR/gettype"
EXTRACT_EROFS="$TOOLS_DIR/extract.erofs"
MKFS_EROFS="$TOOLS_DIR/mkfs.erofs"
MAKE_EXT4FS="$TOOLS_DIR/make_ext4fs"

usage() {
    cat <<'EOF'
Usage: ./start-oplus.sh <payload.bin> [options]

Options:
  --output <dir>                Output directory (default: ./output)
  --youtube-morphe-url <url>    Pin a YouTube Morphe module ZIP
  --skip-debloat                Skip debloat
  --skip-youtube-morphe         Skip YouTube Morphe integration
  --skip-photos-spoof           Skip Google Photos Pixel XL spoof
  --skip-secure-flag            Skip secure-flag/screen-capture bypass
  --skip-avb                    Skip vendor_boot ramdisk AVB patch
  --keep-workdir                Keep temporary extracted files
  -h, --help                    Show this help
EOF
}

[[ $# -gt 0 ]] || { usage; exit 2; }

payload_input=""
output_dir="$ROOT_DIR/output"
youtube_morphe_url=""
enable_debloat=true
enable_youtube=true
enable_photos_spoof=true
enable_secure_flag=true
enable_avb=true
keep_workdir=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)
            [[ $# -ge 2 ]] || die "--output requires a directory"
            output_dir="$2"
            shift 2
            ;;
        --output=*) output_dir="${1#*=}"; shift ;;
        --youtube-morphe-url)
            [[ $# -ge 2 ]] || die "--youtube-morphe-url requires a URL"
            youtube_morphe_url="$2"
            shift 2
            ;;
        --youtube-morphe-url=*) youtube_morphe_url="${1#*=}"; shift ;;
        --skip-debloat) enable_debloat=false; shift ;;
        --skip-youtube-morphe) enable_youtube=false; shift ;;
        --skip-photos-spoof) enable_photos_spoof=false; shift ;;
        --skip-secure-flag) enable_secure_flag=false; shift ;;
        --skip-avb) enable_avb=false; shift ;;
        --keep-workdir) keep_workdir=true; shift ;;
        -h|--help) usage; exit 0 ;;
        -*) die "Unknown option: $1" ;;
        *)
            [[ -z "$payload_input" ]] || die "Only one payload input is supported"
            payload_input="$1"
            shift
            ;;
    esac
done

[[ -n "$payload_input" ]] || die "payload.bin is required"
[[ -f "$payload_input" ]] || die "Payload not found: $payload_input"
payload_input="$(realpath "$payload_input")"
output_dir="$(realpath -m "$output_dir")"

[[ "$youtube_morphe_url" == "" || "$youtube_morphe_url" == http://* || "$youtube_morphe_url" == https://* ]] \
    || die "YouTube Morphe URL must use HTTP(S)"

[[ "$(uname -s)" == "Linux" && "$(uname -m)" == "x86_64" ]] \
    || die "This tool currently supports Linux/WSL x86_64 only"

for tool in "$PAYLOAD_EXTRACT" "$GETTYPE" "$EXTRACT_EROFS" "$MKFS_EROFS" "$MAKE_EXT4FS"; do
    [[ -x "$tool" ]] || die "Bundled tool is missing or not executable: $tool"
done
for command in python3 java unzip zipalign sha256sum find sed awk grep realpath; do
    require_command "$command"
done
if command -v 7za >/dev/null 2>&1; then
    SEVENZIP=7za
elif command -v 7z >/dev/null 2>&1; then
    SEVENZIP=7z
else
    die "Missing required command: 7za or 7z"
fi
if [[ "$enable_youtube" == true ]]; then
    require_command aapt
    require_command aria2c
fi

if [[ -e "$output_dir" ]]; then
    [[ -d "$output_dir" ]] || die "Output path is not a directory: $output_dir"
    [[ -z "$(find "$output_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]] \
        || die "Output directory is not empty: $output_dir"
else
    mkdir -p "$output_dir"
fi

mkdir -p "$ROOT_DIR/tmp"
WORK_DIR="$(mktemp -d "$ROOT_DIR/tmp/oplus-patch.XXXXXX")"
RAW_DIR="$WORK_DIR/raw"
IMAGES_DIR="$WORK_DIR/images"
CONFIG_DIR="$IMAGES_DIR/config"
PATCH_STATE_DIR="$WORK_DIR/state"
mkdir -p "$RAW_DIR" "$IMAGES_DIR" "$CONFIG_DIR" "$PATCH_STATE_DIR"
: > "$PATCH_STATE_DIR/modified_partitions"

cleanup() {
    local status=$?
    if [[ "$keep_workdir" == true ]]; then
        warn "Keeping work directory: $WORK_DIR"
    else
        rm -rf -- "$WORK_DIR"
    fi
    exit "$status"
}
trap cleanup EXIT

export ROOT_DIR WORK_DIR RAW_DIR IMAGES_DIR CONFIG_DIR PATCH_STATE_DIR SEVENZIP
export YOUTUBE_MORPHE_URL="$youtube_morphe_url"
export PATH="$TOOLS_DIR:$PATH"

mods "Reading payload manifest"
partition_listing="$($PAYLOAD_EXTRACT list "$payload_input")" || die "Unable to read payload manifest"
mapfile -t payload_partitions < <(
    awk '
        /^[[:space:]]*[A-Za-z0-9_.-]+[[:space:]]+[0-9.]+[[:space:]]+(B|KB|MB|GB|TB)[[:space:]]+[0-9]+[[:space:]]*$/ {
            print $1
            next
        }
        {
            count = split($0, entries, ",")
            for (i = 1; i <= count; i++) {
                entry = entries[i]
                sub(/^[[:space:]]*/, "", entry)
                if (entry ~ /^[A-Za-z0-9_.-]+[[:space:]]*\(/) {
                    sub(/[[:space:]]*\(.*/, "", entry)
                    print entry
                }
            }
        }
    ' <<< "$partition_listing" | sort -u
)
[[ ${#payload_partitions[@]} -gt 0 ]] || die "No partitions found in payload"

has_partition() {
    local wanted="$1" part
    for part in "${payload_partitions[@]}"; do
        [[ "$part" == "$wanted" ]] && return 0
    done
    return 1
}

has_partition system || die "Payload has no system partition"
has_partition system_ext || die "Payload has no system_ext partition"
has_partition my_product || die "Payload has no my_product partition"
has_partition my_stock || die "Payload has no my_stock partition"

selected=(system system_ext my_product my_stock)
if [[ "$enable_avb" == true ]]; then
    has_partition vendor_boot || die "Payload has no vendor_boot partition"
    selected+=(vendor_boot)
fi

partition_csv="$(IFS=,; printf '%s' "${selected[*]}")"
mods "Extracting selected payload partitions"
"$PAYLOAD_EXTRACT" extract --output "$RAW_DIR" --partitions "$partition_csv" "$payload_input" \
    || die "Payload extraction failed (incremental OTAs require source images)"

declare -A FS_TYPE=()
declare -A ORIGINAL_SIZE=()

for image in "$RAW_DIR"/*.img; do
    [[ -f "$image" ]] || continue
    part="$(basename "$image" .img)"
    ORIGINAL_SIZE["$part"]="$(stat -c '%s' "$image")"
    [[ "$part" == vendor_boot ]] && continue
    fs="$($GETTYPE -i "$image" 2>/dev/null || true)"
    case "$fs" in
        ext)
            FS_TYPE["$part"]="EXT"
            mods "Extracting $part (EXT4)"
            python3 "$ROOT_DIR/bin/imgextractor/imgextractor.py" "$image" "$IMAGES_DIR" >/dev/null \
                || die "Failed to extract $part"
            ;;
        erofs)
            FS_TYPE["$part"]="EROFS"
            mods "Extracting $part (EROFS)"
            "$EXTRACT_EROFS" -x -i "$image" -o "$IMAGES_DIR" >/dev/null \
                || die "Failed to extract $part"
            ;;
        *) warn "Skipping non-filesystem partition $part" ;;
    esac
done

[[ -d "$IMAGES_DIR/system" ]] || die "system filesystem was not extracted"
[[ -d "$IMAGES_DIR/my_product" ]] || die "my_product filesystem was not extracted"

system_root="$IMAGES_DIR/system"
[[ -d "$system_root/system/framework" ]] && system_root="$system_root/system"
sdk_level="$(find "$system_root" -type f -name build.prop -exec sed -n 's/^ro.build.version.sdk=//p' {} + | head -n 1)"
[[ "$sdk_level" =~ ^[0-9]+$ ]] || die "Unable to determine Android SDK level"
export SDK_LEVEL="$sdk_level"
info "Detected Android SDK $SDK_LEVEL"

if [[ "$enable_debloat" == true ]]; then
    mods "Applying debloat"
    bash "$ROOT_DIR/bin/ddevice/DEBLOAT/debloat.sh"
fi

if [[ "$enable_youtube" == true ]]; then
    mods "Applying YouTube Morphe"
    bash "$ROOT_DIR/bin/package/YOUTUBE_MORPHE/update.sh"
fi

if [[ "$enable_secure_flag" == true ]]; then
    mods "Applying secure-flag patch"
    bash "$ROOT_DIR/bin/package/KouseiPatcher/secure_flag_patch.sh"
fi

if [[ "$enable_photos_spoof" == true ]]; then
    mods "Applying Google Photos spoof"
    bash "$ROOT_DIR/bin/package/KouseiPatcher/update.sh"
fi

repack_partition() {
    local part="$1"
    local tree="$IMAGES_DIR/$part"
    local output="$output_dir/$part.img"
    local original_size="${ORIGINAL_SIZE[$part]:-0}"
    local fs="${FS_TYPE[$part]:-}"
    local fs_config="$CONFIG_DIR/${part}_fs_config"
    local file_contexts="$CONFIG_DIR/${part}_file_contexts"

    [[ -d "$tree" ]] || die "Modified partition tree is missing: $part"
    [[ "$original_size" -gt 0 ]] || die "Original size is unknown for $part"
    [[ -f "$fs_config" && -f "$file_contexts" ]] \
        || die "Filesystem metadata is missing for $part"

    python3 "$ROOT_DIR/bin/fix_selinux.py" "$tree" "$fs_config" "$file_contexts" >/dev/null \
        || die "Failed to update SELinux metadata for $part"

    mods "Repacking $part ($fs)"
    case "$fs" in
        EXT)
            "$MAKE_EXT4FS" -J -T 1230768000 -S "$file_contexts" -l "$original_size" \
                -C "$fs_config" -L "$part" -a "$part" "$output" "$tree" >/dev/null \
                || die "Failed to repack $part as EXT4"
            ;;
        EROFS)
            "$MKFS_EROFS" --quiet -zlz4hc,9 -C 16384 --mount-point "$part" \
                --fs-config-file="$fs_config" --file-contexts="$file_contexts" \
                "$output" "$tree" >/dev/null \
                || die "Failed to repack $part as EROFS"
            ;;
        *) die "Unsupported filesystem for modified partition $part: $fs" ;;
    esac

    [[ -s "$output" ]] || die "Repacked image is empty: $output"
    new_size="$(stat -c '%s' "$output")"
    [[ "$new_size" -le "$original_size" ]] \
        || die "$part.img grew beyond its original partition size ($new_size > $original_size)"
}

mapfile -t modified_partitions < <(sort -u "$PATCH_STATE_DIR/modified_partitions")
[[ ${#modified_partitions[@]} -gt 0 || "$enable_avb" == true ]] || die "No partition was modified"
for part in "${modified_partitions[@]}"; do
    case "$part" in
        system|system_ext|my_product|my_stock) ;;
        *) die "Patch unexpectedly modified a partition outside fast mode: $part" ;;
    esac
    repack_partition "$part"
done

if [[ "$enable_avb" == true ]]; then
    mods "Removing AVB flags from vendor_boot ramdisk"
    bash "$ROOT_DIR/bin/package/DISABLE_AVB/HMATools/start" "$output_dir" vendor_boot
fi

report="$output_dir/patch-report.txt"
{
    printf 'Input: %s\n' "$payload_input"
    printf 'Android SDK: %s\n' "$SDK_LEVEL"
    printf 'Debloat: %s\nYouTube Morphe: %s\nGoogle Photos spoof: %s\nSecure flag: %s\nVendor boot AVB patch: %s\n' \
        "$enable_debloat" "$enable_youtube" "$enable_photos_spoof" "$enable_secure_flag" "$enable_avb"
    printf '\nOutput images:\n'
    for image in "$output_dir"/*.img; do
        [[ -f "$image" ]] || continue
        printf '%s  %s  %s bytes\n' "$(sha256sum "$image" | awk '{print $1}')" \
            "$(basename "$image")" "$(stat -c '%s' "$image")"
    done
} > "$report"

mods "Patch completed: $output_dir"
[[ "$enable_avb" == false ]] || warn "Flash the patched vendor_boot.img together with the modified filesystem images"
