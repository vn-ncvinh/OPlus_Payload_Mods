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
LPMAKE="$TOOLS_DIR/lpmake"
ARBEXTRACT="$TOOLS_DIR/arbextract"
GBL_DIR="$ROOT_DIR/bin/package/GBL_CHAINLOAD"
GBL_TOOL="$GBL_DIR/bin/gbl"
GBL_EFI="$GBL_DIR/gbl-chainload-v2.3.4.efi"

usage() {
    cat <<'EOF'
Usage: ./start-oplus.sh <payload.bin|ota.zip> [options]

Options:
  --output <dir>                Recovery ZIP output directory (default: ./output)
  --youtube-morphe-url <url>    Pin a YouTube Morphe module ZIP
  --skip-debloat                Skip debloat
  --skip-youtube-morphe         Skip YouTube Morphe integration
  --skip-photos-spoof           Skip Google Photos Pixel XL spoof
  --skip-secure-flag            Skip secure-flag/screen-capture bypass
  --skip-lock-assistant-bypass  Skip LockAssistantBypass
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
enable_lock_assistant_bypass=true
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
        --skip-lock-assistant-bypass) enable_lock_assistant_bypass=false; shift ;;
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

FLASHER_TEMPLATE="$ROOT_DIR/bin/flasher/common"

[[ -n "$payload_input" ]] || die "A payload.bin or OTA ZIP input is required"
[[ -f "$payload_input" ]] || die "Payload/OTA input not found: $payload_input"
payload_input="$(realpath "$payload_input")"
output_dir="$(realpath -m "$output_dir")"

[[ "$youtube_morphe_url" == "" || "$youtube_morphe_url" == http://* || "$youtube_morphe_url" == https://* ]] \
    || die "YouTube Morphe URL must use HTTP(S)"

[[ "$(uname -s)" == "Linux" && "$(uname -m)" == "x86_64" ]] \
    || die "This tool currently supports Linux/WSL x86_64 only"

for tool in "$PAYLOAD_EXTRACT" "$GETTYPE" "$EXTRACT_EROFS" "$MKFS_EROFS" "$MAKE_EXT4FS" "$LPMAKE" "$ARBEXTRACT"; do
    [[ -x "$tool" ]] || die "Bundled tool is missing or not executable: $tool"
done
for command in python3 java unzip zip zipalign sha256sum find sed awk grep realpath; do
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

[[ -x "$FLASHER_TEMPLATE/META-INF/com/google/android/update-binary" ]] \
    || die "Recovery flasher template is missing"
[[ -x "$FLASHER_TEMPLATE/tools/arm64/sparse_stream_writer" ]] \
    || die "Sparse stream writer is missing"
[[ -x "$FLASHER_TEMPLATE/tools/arm64/stored_zip_streamer" ]] \
    || die "ZIP streamer is missing"
[[ -x "$GBL_TOOL" && -f "$GBL_DIR/efisp-package.py" && -f "$GBL_EFI" ]] \
    || die "GBL chainload v2.3.4 tools are missing"
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
BUILT_IMAGES_DIR="$WORK_DIR/built-images"
PACKAGE_DIR="$WORK_DIR/recovery-package"
OTA_DIR="$PACKAGE_DIR/OTA_FILES_HERE"
DETECT_RAW_DIR="$WORK_DIR/detect-raw"
DETECT_FS_DIR="$WORK_DIR/detect-fs"
mkdir -p "$RAW_DIR" "$IMAGES_DIR" "$CONFIG_DIR" "$PATCH_STATE_DIR" \
    "$BUILT_IMAGES_DIR" "$OTA_DIR" "$DETECT_RAW_DIR" "$DETECT_FS_DIR"
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

has_partition my_manifest || die "Payload has no my_manifest partition for device detection"
has_partition xbl_config || die "Payload has no xbl_config partition for anti-rollback check"

mods "Checking anti-rollback metadata"
"$PAYLOAD_EXTRACT" extract --output "$DETECT_RAW_DIR" \
    --partitions xbl_config "$payload_input" \
    || die "Unable to extract xbl_config for anti-rollback check"

arb_output="$("$ARBEXTRACT" "$DETECT_RAW_DIR/xbl_config.img" 2>&1)" \
    || die "Unable to read anti-rollback metadata from xbl_config.img"
arb_value="$(awk -F: '
    /ARB \(Anti-Rollback\)/ {
        gsub(/[[:space:]]/, "", $2)
        print $2
        exit
    }
' <<< "$arb_output")"
[[ "$arb_value" =~ ^[0-9]+$ ]] \
    || die "Unable to parse ARB value from xbl_config.img"
if [[ ! "$arb_value" =~ ^0+$ ]]; then
    warn "Anti-rollback is enabled in xbl_config.img (ARB=$arb_value)"
    die "Refusing to build a package with non-zero ARB"
fi
info "Anti-rollback check passed (ARB=0)"

mods "Detecting device profile from payload"
"$PAYLOAD_EXTRACT" extract --output "$DETECT_RAW_DIR" \
    --partitions my_manifest "$payload_input" \
    || die "Unable to extract my_manifest for device detection"

for detect_part in my_manifest; do
    detect_image="$DETECT_RAW_DIR/$detect_part.img"
    [[ -s "$detect_image" ]] || die "Extracted detection image is missing: $detect_part.img"
    detect_fs="$($GETTYPE -i "$detect_image" 2>/dev/null || true)"
    case "$detect_fs" in
        ext)
            python3 "$ROOT_DIR/bin/imgextractor/imgextractor.py" \
                "$detect_image" "$DETECT_FS_DIR" >/dev/null \
                || die "Failed to inspect $detect_part for device detection"
            ;;
        erofs)
            "$EXTRACT_EROFS" -x -i "$detect_image" -o "$DETECT_FS_DIR" >/dev/null \
                || die "Failed to inspect $detect_part for device detection"
            ;;
        *) die "Unsupported $detect_part filesystem for device detection: $detect_fs" ;;
    esac
done

manifest_build_prop="$DETECT_FS_DIR/my_manifest/build.prop"
[[ -f "$manifest_build_prop" ]] \
    || die "my_manifest/build.prop is missing"
project_ids="$(awk -F= '
    $1 == "ro.product.supported_versions" {
        supported_versions=$2
    }
    $1 == "ro.oplus.image.my_product.type" {
        my_product_type=$2
    }
    END {
        if (supported_versions != "") print supported_versions
        else print my_product_type
    }
' "$manifest_build_prop")"
project_ids="$(tr ',' ' ' <<< "$project_ids" | awk '{$1=$1; print}')"
[[ -n "$project_ids" ]] \
    || die "Unable to read the project ID from my_manifest/build.prop"
[[ "$project_ids" =~ ^[0-9]+([[:space:]]+[0-9]+)*$ ]] \
    || die "Invalid project ID in my_manifest/build.prop: $project_ids"

build_display_id="$(awk -F= '
    $1 == "ro.build.display.id" {
        sub(/^[^=]*=/, "")
        print
        exit
    }
' "$manifest_build_prop")"
[[ -n "$build_display_id" ]] \
    || die "Unable to read ro.build.display.id from my_manifest/build.prop"
safe_build_display_id="$(sed 's/[^A-Za-z0-9._()-]/_/g' <<< "$build_display_id")"
[[ -n "$safe_build_display_id" ]] || die "Invalid ro.build.display.id: $build_display_id"

device_id=""
for profile_file in "$ROOT_DIR"/devices/*/profile.sh; do
    [[ -f "$profile_file" ]] || continue
    profile_match="$(bash -c '
        source "$1"
        for detected in $2; do
            case " $SUPPORTED_PROJECT_IDS " in
                *" $detected "*) printf "%s\n" "$DEVICE_ID"; exit 0 ;;
            esac
        done
    ' _ "$profile_file" "$project_ids")"
    [[ -z "$profile_match" ]] || {
        [[ -z "$device_id" || "$device_id" == "$profile_match" ]] \
            || die "Project ID $project_ids matches multiple device profiles"
        device_id="$profile_match"
    }
done
[[ -n "$device_id" ]] \
    || die "Unsupported project ID from payload: $project_ids"

PROFILE_FILE="$ROOT_DIR/devices/$device_id/profile.sh"
source "$PROFILE_FILE"
DONOR_DIR=""
[[ -n "$DONOR_RELATIVE_DIR" ]] && DONOR_DIR="$ROOT_DIR/$DONOR_RELATIVE_DIR"
[[ -n "${ABL_DONOR_IMAGE:-}" ]] || die "$DEVICE_DISPLAY profile has no ABL donor image"
[[ -n "${ABL_DONOR_VERSION:-}" ]] || die "$DEVICE_DISPLAY profile has no ABL donor version"
ABL_DONOR="$DONOR_DIR/$ABL_DONOR_IMAGE"
info "Detected $DEVICE_DISPLAY (project ID: $project_ids, build: $build_display_id)"

if [[ ${#DONOR_PARTITIONS[@]} -gt 0 ]]; then
    [[ -f "$DONOR_DIR/SHA256SUMS" ]] || die "$DEVICE_DISPLAY donor checksums are missing"
    (
        cd "$DONOR_DIR"
        sha256sum -c SHA256SUMS
    ) >/dev/null || die "$DEVICE_DISPLAY donor image is missing, is an LFS pointer, or has the wrong checksum"
fi

for part in "${DYNAMIC_PARTITIONS[@]}"; do
    has_partition "$part" || die "Payload has no required dynamic partition: $part"
done
has_partition abl || die "Payload has no abl partition required for GBL chainload"
has_partition vendor_boot || die "Payload has no vendor_boot partition"
has_partition boot || die "Payload has no boot partition required for AVB patching"

mv "$DETECT_RAW_DIR/my_manifest.img" "$RAW_DIR/my_manifest.img"
mv "$DETECT_RAW_DIR/xbl_config.img" "$RAW_DIR/xbl_config.img"

selected=()
for part in "${payload_partitions[@]}"; do
    case "$part" in
        my_manifest|xbl_config) ;;
        *)
            is_profile_donor=false
            for donor_part in "${DONOR_PARTITIONS[@]}"; do
                [[ "$part" == "$donor_part" ]] && is_profile_donor=true
            done
            [[ "$is_profile_donor" == true ]] || selected+=("$part")
            ;;
    esac
done

if [[ ${#selected[@]} -gt 0 ]]; then
    partition_csv="$(IFS=,; printf '%s' "${selected[*]}")"
    mods "Extracting remaining payload partitions"
    "$PAYLOAD_EXTRACT" extract --output "$RAW_DIR" --partitions "$partition_csv" "$payload_input" \
        || die "Payload extraction failed (incremental OTAs require source images)"
fi

mods "Building GBL chainload mode 1 EFISP"
python3 "$GBL_DIR/efisp-package.py" \
    --abl "$RAW_DIR/abl.img" \
    --mode 1 \
    --efi "$GBL_EFI" \
    --oem oplus \
    --out "$PACKAGE_DIR/efisp-gbl-chainload-mode1.efi" \
    || die "Failed to build GBL chainload EFISP"
"$GBL_TOOL" inspect "$PACKAGE_DIR/efisp-gbl-chainload-mode1.efi" >/dev/null \
    || die "Generated GBL chainload EFISP failed validation"

declare -A FS_TYPE=()
declare -A ORIGINAL_SIZE=()

needs_partition_tree() {
    case "$1" in
        system)
            return 0
            ;;
        system_ext) [[ "$enable_debloat" == true ]] ;;
        my_stock) [[ "$enable_debloat" == true || "$enable_lock_assistant_bypass" == true ]] ;;
        my_product) [[ "$enable_debloat" == true || "$enable_youtube" == true ]] ;;
        vendor) return 0 ;;
        *) return 1 ;;
    esac
}

for image in "$RAW_DIR"/*.img; do
    [[ -f "$image" ]] || continue
    part="$(basename "$image" .img)"
    ORIGINAL_SIZE["$part"]="$(stat -c '%s' "$image")"
    needs_partition_tree "$part" || continue
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

for part in system system_ext my_product my_stock vendor; do
    needs_partition_tree "$part" || continue
    [[ -d "$IMAGES_DIR/$part" ]] || die "$part filesystem was not extracted"
done

SDK_LEVEL="n/a"
if [[ -d "$IMAGES_DIR/system" ]]; then
    system_root="$IMAGES_DIR/system"
    [[ -d "$system_root/system/framework" ]] && system_root="$system_root/system"
    system_build_prop="$system_root/build.prop"
    [[ -f "$system_build_prop" ]] || die "system build.prop is missing"
    sdk_level="$(sed -n 's/^ro.build.version.sdk=//p' "$system_build_prop" | awk 'NF {print; exit}')"
    [[ "$sdk_level" =~ ^[0-9]+$ ]] || die "Unable to determine Android SDK level"
    SDK_LEVEL="$sdk_level"
    info "Detected Android SDK $SDK_LEVEL"
fi
export SDK_LEVEL

source "$ROOT_DIR/bin/package/JarPatcher/functions.sh"
framework_dir="$system_root/framework"
register_jar services "$framework_dir/services.jar"
[[ "$enable_lock_assistant_bypass" == true ]] \
    && register_jar oplus-services "$framework_dir/oplus-services.jar"
[[ "$enable_photos_spoof" == true ]] \
    && register_jar framework "$framework_dir/framework.jar"
unpack_jars

if [[ "$enable_debloat" == true ]]; then
    mods "Applying debloat"
    bash "$ROOT_DIR/bin/ddevice/DEBLOAT/debloat.sh"
fi

if [[ "$enable_youtube" == true ]]; then
    mods "Applying YouTube Morphe"
    bash "$ROOT_DIR/bin/package/YOUTUBE_MORPHE/update.sh"
fi

if [[ "$enable_lock_assistant_bypass" == true ]]; then
    mods "Removing LockAssistant app"
    bash "$ROOT_DIR/bin/package/LockAssistantBypass/remove-app.sh"
fi

if [[ "$enable_secure_flag" == true ]]; then
    mods "Applying DisableFlagSecure"
    bash "$ROOT_DIR/bin/package/DisableFlagSecure/patch.sh" "$(jar_smali_root services)"
fi

mods "Applying DisableSafeMediaVolume"
bash "$ROOT_DIR/bin/package/DisableSafeMediaVolume/patch.sh" "$(jar_smali_root services)"

if [[ "$enable_lock_assistant_bypass" == true ]]; then
    mods "Applying LockAssistantBypass"
    bash "$ROOT_DIR/bin/package/LockAssistantBypass/patch.sh" \
        "$(jar_smali_root oplus-services)"
fi

if [[ "$enable_photos_spoof" == true ]]; then
    mods "Applying GGPhotosUnlimited"
    bash "$ROOT_DIR/bin/package/GGPhotosUnlimited/patch.sh" "$(jar_smali_root framework)"
fi

pack_jars

repack_partition() {
    local part="$1"
    local tree="$IMAGES_DIR/$part"
    local output="$BUILT_IMAGES_DIR/$part.img"
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
    info "$part.img repacked: $new_size bytes (payload image: $original_size bytes)"
}

mods "Removing AVB flags from vendor fstab"
if disable_avb_verify "$IMAGES_DIR/vendor"; then
    mark_modified vendor
else
    warn "No AVB fstab flags were found in vendor"
fi

mapfile -t modified_partitions < <(sort -u "$PATCH_STATE_DIR/modified_partitions")
for part in "${modified_partitions[@]}"; do
    case "$part" in
        system|system_ext|my_product|my_stock|vendor) ;;
        *) die "Patch unexpectedly modified a partition outside fast mode: $part" ;;
    esac
    repack_partition "$part"
done

mods "Removing AVB flags from boot and vendor_boot ramdisks"
bash "$ROOT_DIR/bin/package/DISABLE_AVB/HMATools/start" "$BUILT_IMAGES_DIR" boot vendor_boot

is_dynamic_partition() {
    local wanted="$1" candidate
    for candidate in "${DYNAMIC_PARTITIONS[@]}"; do
        [[ "$candidate" == "$wanted" ]] && return 0
    done
    return 1
}

is_donor_partition() {
    local wanted="$1" candidate
    for candidate in "${DONOR_PARTITIONS[@]}"; do
        [[ "$candidate" == "$wanted" ]] && return 0
    done
    return 1
}

align_up() {
    local value="$1" alignment="$2"
    printf '%s\n' "$(( (value + alignment - 1) / alignment * alignment ))"
}

mods "Preparing $DEVICE_DISPLAY recovery package"
cp -a "$FLASHER_TEMPLATE/." "$PACKAGE_DIR/"

{
    printf "DEVICE_ID='%s'\n" "$DEVICE_ID"
    printf "DEVICE_DISPLAY='%s'\n" "$DEVICE_DISPLAY"
    printf "SUPPORTED_PROJECT_IDS='%s'\n" "$SUPPORTED_PROJECT_IDS"
    printf "ABL_DONOR_IMAGE='%s'\n" "$ABL_DONOR_IMAGE"
    printf "ABL_DONOR_VERSION='%s'\n" "$ABL_DONOR_VERSION"
    printf 'TARGET_SUPER_BYTES=%s\n' "$SUPER_SIZE"
} > "$PACKAGE_DIR/device-profile.conf"

for part in "${payload_partitions[@]}"; do
    is_dynamic_partition "$part" && continue
    is_donor_partition "$part" && continue
    raw_image="$RAW_DIR/$part.img"
    source_image="$raw_image"
    [[ -f "$raw_image" ]] || die "Extracted payload image is missing: $part.img"
    if [[ "$part" == abl ]]; then
        [[ -s "$ABL_DONOR" ]] || die "$DEVICE_DISPLAY ABL donor is missing"
        cp -- "$ABL_DONOR" "$PACKAGE_DIR/$ABL_DONOR_IMAGE"
        rm -f -- "$raw_image"
        continue
    fi
    if [[ ( "$part" == boot || "$part" == vendor_boot ) && -f "$BUILT_IMAGES_DIR/$part.img" ]]; then
        source_image="$BUILT_IMAGES_DIR/$part.img"
    fi
    mv "$source_image" "$OTA_DIR/$part.img"
    if [[ "$source_image" != "$raw_image" ]]; then
        rm -f -- "$raw_image"
    fi
done

declare -a lp_args=(
    --metadata-size "$SUPER_METADATA_SIZE"
    --metadata-slots "$SUPER_METADATA_SLOTS"
    --super-name super
    --device "super:$SUPER_SIZE:$SUPER_ALIGNMENT:$SUPER_ALIGNMENT_OFFSET"
    --block-size 4096
    --group "qti_dynamic_partitions_a:$SUPER_GROUP_SIZE"
    --group "qti_dynamic_partitions_b:$SUPER_GROUP_SIZE"
    --virtual-ab
    --sparse
    --output "$OTA_DIR/super.img"
)

total_logical_size=0
for part in "${DYNAMIC_PARTITIONS[@]}" "${DONOR_PARTITIONS[@]}"; do
    if is_donor_partition "$part"; then
        source_image="$DONOR_DIR/${part}_a.img"
    elif [[ -f "$BUILT_IMAGES_DIR/$part.img" ]]; then
        source_image="$BUILT_IMAGES_DIR/$part.img"
    else
        source_image="$RAW_DIR/$part.img"
    fi

    [[ -s "$source_image" ]] || die "Logical partition image is missing: $part"
    image_size="$(stat -c '%s' "$source_image")"
    partition_size="$(align_up "$image_size" 4096)"
    total_logical_size=$((total_logical_size + partition_size))
    lp_args+=(
        --partition "${part}_a:readonly:$partition_size:qti_dynamic_partitions_a"
        --image "${part}_a=$source_image"
        --partition "${part}_b:readonly:0:qti_dynamic_partitions_b"
    )
done

[[ "$total_logical_size" -le "$SUPER_GROUP_SIZE" ]] \
    || die "Logical images exceed the $DEVICE_DISPLAY super group ($total_logical_size > $SUPER_GROUP_SIZE)"

mods "Building sparse super.img ($total_logical_size/$SUPER_GROUP_SIZE bytes allocated)"
"$LPMAKE" "${lp_args[@]}" >/dev/null || die "Failed to build $DEVICE_DISPLAY super.img"
[[ -s "$OTA_DIR/super.img" ]] || die "lpmake produced an empty super.img"

report="$PACKAGE_DIR/patch-report.txt"
{
    printf 'Input: %s\n' "$payload_input"
    printf 'Device profile: %s (%s)\n' "$DEVICE_DISPLAY" "$DEVICE_ID"
    printf 'Payload project ID: %s\n' "$project_ids"
    printf 'Build display ID: %s\n' "$build_display_id"
    printf 'ABL donor version: %s\n' "$ABL_DONOR_VERSION"
    printf 'Anti-rollback: %s\n' "$arb_value"
    printf 'Android SDK: %s\n' "$SDK_LEVEL"
    printf 'Super logical allocation: %s / %s bytes\n' "$total_logical_size" "$SUPER_GROUP_SIZE"
    printf 'Debloat: %s\nYouTube Morphe: %s\nGoogle Photos spoof: %s\nSecure flag: %s\nLockAssistantBypass: %s\nDisableSafeMediaVolume: true\nVendor/boot/vendor_boot AVB fstab patch: true\n' \
        "$enable_debloat" "$enable_youtube" "$enable_photos_spoof" "$enable_secure_flag" \
        "$enable_lock_assistant_bypass"
    printf 'GBL chainload: v2.3.4 mode 1, OEM oplus\n'
    (cd "$PACKAGE_DIR" && sha256sum efisp-gbl-chainload-mode1.efi)
    printf '\nPatched logical partitions:\n'
    printf '%s\n' "${modified_partitions[@]:-none}"
    if [[ ${#DONOR_PARTITIONS[@]} -gt 0 ]]; then
        printf '\nDonor images:\n'
        (cd "$DONOR_DIR" && sha256sum -c SHA256SUMS)
    fi
} > "$report"

(
    cd "$PACKAGE_DIR"
    {
        find OTA_FILES_HERE -maxdepth 1 -type f -name '*.img' -print
        printf '%s\n' "$ABL_DONOR_IMAGE" efisp-gbl-chainload-mode1.efi
    } | sort > required-images.txt
)
[[ -s "$PACKAGE_DIR/required-images.txt" ]] || die "No required image list was generated"

zip_name="${OUTPUT_ZIP%_Recovery.zip}_${safe_build_display_id}_Recovery.zip"
zip_path="$WORK_DIR/$zip_name"
mods "Creating recovery ZIP (stored entries)"
(
    cd "$PACKAGE_DIR"
    zip -0 -q -r "$zip_path" META-INF OTA_FILES_HERE tools patch-report.txt device-profile.conf \
        required-images.txt efisp-gbl-chainload-mode1.efi "$ABL_DONOR_IMAGE"
) || die "Failed to create recovery ZIP"
[[ -s "$zip_path" ]] || die "Recovery ZIP is empty"

final_zip="$output_dir/$(basename "$zip_path")"
mv -f "$zip_path" "$final_zip"
mods "Recovery flasher completed: $final_zip"
