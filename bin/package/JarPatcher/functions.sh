#!/usr/bin/env bash

declare -ag JAR_IDS=()
declare -Ag JAR_PATH_BY_ID=()
declare -Ag JAR_WORK_DIR_BY_ID=()
declare -Ag JAR_SMALI_ROOT_BY_ID=()
JAR_WORK_ROOT="$WORK_DIR/jars"
JARS_UNPACKED=false
JARS_PACKED=false

register_jar() {
    local jar_id="$1"
    local jar_path="$2"

    [[ "$JARS_UNPACKED" == false ]] || die "Cannot register JAR after unpack_jars"
    [[ "$jar_id" =~ ^[a-zA-Z0-9_-]+$ ]] || die "Invalid JAR ID: $jar_id"
    [[ -z "${JAR_PATH_BY_ID[$jar_id]+x}" ]] || die "JAR ID already registered: $jar_id"

    JAR_IDS+=("$jar_id")
    JAR_PATH_BY_ID["$jar_id"]="$jar_path"
}

jar_smali_root() {
    local jar_id="$1"
    [[ -n "${JAR_SMALI_ROOT_BY_ID[$jar_id]+x}" ]] \
        || die "JAR has not been unpacked: $jar_id"
    printf '%s\n' "${JAR_SMALI_ROOT_BY_ID[$jar_id]}"
}

unpack_jars() {
    local jar_id jar_path jar_name temp_dir jar_out dex dex_count

    [[ ${#JAR_IDS[@]} -gt 0 ]] || return 0
    [[ "$JARS_UNPACKED" == false ]] || die "unpack_jars was called more than once"
    [[ ! -e "$JAR_WORK_ROOT" ]] || die "JAR work directory already exists: $JAR_WORK_ROOT"
    mkdir -p "$JAR_WORK_ROOT"

    mods "Unpacking required JARs"
    for jar_id in "${JAR_IDS[@]}"; do
        jar_path="${JAR_PATH_BY_ID[$jar_id]}"
        [[ -f "$jar_path" ]] || die "Required JAR is missing: $jar_path"

        jar_name="$(basename "$jar_path")"
        temp_dir="$JAR_WORK_ROOT/$jar_id"
        jar_out="$temp_dir/unpacked"
        JAR_WORK_DIR_BY_ID["$jar_id"]="$temp_dir"
        JAR_SMALI_ROOT_BY_ID["$jar_id"]="$jar_out"
        mkdir -p "$jar_out"

        mods "Disassembling $jar_name"
        unzip -q "$jar_path" -d "$jar_out" || die "Unable to unpack $jar_path"

        dex_count=0
        for dex in "$jar_out"/classes*.dex; do
            [[ -f "$dex" ]] || continue
            dex_count=$((dex_count + 1))
            java -jar "$ROOT_DIR/bin/apktool/baksmaliv2.jar" d --api "$SDK_LEVEL" \
                "$dex" -o "$dex.out" \
                || die "baksmali failed for $jar_name/$(basename "$dex")"
            rm -f "$dex"
        done
        [[ "$dex_count" -gt 0 ]] || die "$jar_name contains no DEX files"
    done
    JARS_UNPACKED=true
}

pack_jars() {
    local jar_id jar_path jar_name temp_dir jar_out folder dex rebuilt_dex_count

    [[ ${#JAR_IDS[@]} -gt 0 ]] || return 0
    [[ "$JARS_UNPACKED" == true ]] || die "pack_jars was called before unpack_jars"
    [[ "$JARS_PACKED" == false ]] || die "pack_jars was called more than once"

    mods "Packing patched JARs"
    for jar_id in "${JAR_IDS[@]}"; do
        jar_path="${JAR_PATH_BY_ID[$jar_id]}"
        jar_name="$(basename "$jar_path")"
        temp_dir="${JAR_WORK_DIR_BY_ID[$jar_id]}"
        jar_out="${JAR_SMALI_ROOT_BY_ID[$jar_id]}"

        mods "Rebuilding $jar_name"
        rebuilt_dex_count=0
        for folder in "$jar_out"/classes*.dex.out; do
            [[ -d "$folder" ]] || continue
            rebuilt_dex_count=$((rebuilt_dex_count + 1))
            dex="${folder%.out}"
            java -jar "$ROOT_DIR/bin/apktool/smaliv2.jar" a --api "$SDK_LEVEL" \
                "$folder" -o "$dex" \
                || die "smali failed for $jar_name/$(basename "$folder")"
            rm -rf "$folder"
        done
        [[ "$rebuilt_dex_count" -gt 0 ]] || die "No DEX directories remained for $jar_name"

        (cd "$jar_out" && "$SEVENZIP" a -tzip -mx=0 "$temp_dir/unaligned.jar" . >/dev/null) \
            || die "Unable to rebuild $jar_name"
        zipalign -f 4 "$temp_dir/unaligned.jar" "$temp_dir/patched.jar" \
            || die "zipalign failed for $jar_name"
        cp -f "$temp_dir/patched.jar" "$jar_path"
        mark_modified_path "$jar_path"
        mods "$jar_name rebuilt with all selected patches"
    done
    JARS_PACKED=true
}
