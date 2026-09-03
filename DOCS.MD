# OPlus Payload Mods: Developer and LLM Guide

This document is the fast path for understanding and extending the repository.
Read it together with `start-oplus.sh`; the script remains the source of truth.

## Project invariants

- Input is one OPlus full OTA ZIP or `payload.bin`.
- Device selection is automatic. Never guess a project ID and do not add a
  fallback device silently.
- A build is rejected unless the ARB value in `xbl_config` is zero.
- Device-specific super geometry and donor files belong in a device profile,
  not in common build logic.
- Only modified logical partitions are rebuilt. Rebuilt images retain the
  original payload image size where the filesystem builder supports it.
- Every filesystem edit must mark its owning partition as modified.
- All selected patches for a JAR operate on one shared smali tree. Each JAR is
  disassembled once and rebuilt once per build.
- AVB fstab patching and `DisableSafeMediaVolume` are always enabled.
- The flasher writes existing `/dev/block/by-name/*` devices and never changes
  GPT layout or resizes `super`.
- Preserve unrelated worktree changes. Do not commit or push unless explicitly
  requested.

## Repository map

| Path | Purpose |
| --- | --- |
| `start-oplus.sh` | CLI, validation, complete build pipeline, dependency selection, packaging |
| `functions.sh` | Logging, errors, modified-partition tracking, vendor fstab AVB helper |
| `devices/*/profile.sh` | Device detection IDs, super geometry, dynamic partitions and donors |
| `assets/*/donors/` | Profile-specific donor logical partitions and vulnerable ABL image |
| `bin/ddevice/DEBLOAT/` | Debloat allow-list and tree-removal logic |
| `bin/package/<Mod>/` | One independent modification and its patcher/resources |
| `bin/package/JarPatcher/functions.sh` | Shared register -> unpack -> patch -> pack JAR lifecycle |
| `bin/package/DISABLE_AVB/` | Vendor, boot and vendor_boot fstab patch tooling |
| `bin/package/GBL_CHAINLOAD/` | EFISP packager, GBL binary and chainload EFI payload |
| `bin/flasher/common/` | Recovery installer template and its ARM64 streaming tools |
| `bin/Linux/x86_64/` | Host-side payload, filesystem, ARB and super-image tools |
| `bin/fix_selinux.py` | Refresh filesystem config and SELinux contexts before repacking |
| `docs/` | Device/layout research that is useful but not part of runtime behavior |

Temporary build paths are created below `tmp/oplus-patch.XXXXXX`:

| Runtime path | Contents |
| --- | --- |
| `raw/` | Images extracted from the payload |
| `detect-raw/`, `detect-fs/` | Minimal `xbl_config`/`my_manifest` detection phase |
| `images/<partition>/` | Extracted filesystem trees that selected mods require |
| `images/config/` | Extracted `*_fs_config` and `*_file_contexts` metadata |
| `jars/<jar-id>/unpacked/` | Stable shared JAR contents and `classes*.dex.out` smali trees |
| `state/modified_partitions` | Append-only list consumed before logical partition repack |
| `built-images/` | Rebuilt logical, boot and vendor_boot images |
| `recovery-package/` | Staged recovery ZIP contents |

Use `--keep-workdir` when inspecting these paths.

## Build pipeline

The order in `start-oplus.sh` is intentional:

1. Validate the host, input, output directory, bundled tools and dependencies.
2. Read the payload manifest and require `my_manifest` plus `xbl_config`.
3. Extract only `xbl_config`, read ARB, and stop unless it is `0`.
4. Extract only `my_manifest`; read project IDs and `ro.build.display.id` from
   `my_manifest/build.prop`.
5. Match exactly one `devices/*/profile.sh`, then validate donor SHA-256 files.
6. Validate profile-required payload partitions and extract all non-donor
   payload images. Full extraction is required because the final package also
   contains unmodified firmware; mod skip flags only reduce filesystem-tree
   extraction and repacking.
7. Generate and inspect GBL Chainload mode 1 EFISP using the OTA's `abl.img`.
8. Extract only filesystem trees required by enabled modifications.
9. Detect Android SDK from the extracted `system/build.prop`.
10. Register required framework JARs, then call `unpack_jars` once.
11. Run filesystem and smali mods in the normal main flow.
12. Call `pack_jars` once; it also marks the owning partitions modified.
13. Patch vendor fstab, refresh metadata with `fix_selinux.py`, and repack only
    partitions listed in `state/modified_partitions`.
14. Patch boot and vendor_boot ramdisk fstabs.
15. Move firmware into the package, substitute the profile ABL donor, build a
    profile-sized sparse `super.img`, create reports and generate the final ZIP.

The payload ABL and donor ABL have different roles:

- OTA `abl.img`: input for generating `efisp-gbl-chainload-mode1.efi`.
- Profile `abl-<version>.img`: placed at the ZIP root and flashed to ABL so the
  required GBL vulnerability remains available.

## Device profiles

Current profiles:

| Profile | Project ID | Payload-backed dynamic set | Donor logical partitions | ABL donor |
| --- | --- | --- | --- | --- |
| `x9u` | `25211` | 15, without `system_dlkm_oki` and `my_company`/`my_preload` | `my_company`, `my_preload` | `abl-16.0.6.img` |
| `op15r` | `24877` | 15, without `my_company`/`my_preload` | `system_dlkm_oki`, `my_company`, `my_preload` | `abl-16.0.1.img` |

Each `profile.sh` defines:

```bash
DEVICE_ID=...
DEVICE_DISPLAY=...
OUTPUT_ZIP=...
SUPPORTED_PROJECT_IDS="..."
SUPER_SIZE=...
SUPER_GROUP_SIZE=...
SUPER_ALIGNMENT=...
SUPER_ALIGNMENT_OFFSET=...
SUPER_METADATA_SIZE=...
SUPER_METADATA_SLOTS=...
DYNAMIC_PARTITIONS=(...)
DONOR_PARTITIONS=(...)
DONOR_RELATIVE_DIR="assets/<device>/donors"
ABL_DONOR_IMAGE="abl-<version>.img"
ABL_DONOR_VERSION="<version>"
```

Detection reads `ro.product.supported_versions`, falling back to
`ro.oplus.image.my_product.type`. If none of the detected IDs match a profile,
the build must stop. There is deliberately no `--device` override.

### Adding a device

1. Obtain project ID(s) from the device OTA's `my_manifest/build.prop`.
2. Derive super geometry and both slot groups from authoritative super metadata;
   do not copy another profile merely because partition counts match.
3. List logical partitions supplied by the payload in `DYNAMIC_PARTITIONS`.
4. Put required replacement logical images and the versioned ABL donor in
   `assets/<device>/donors/`; list logical replacements in `DONOR_PARTITIONS`.
5. Create `SHA256SUMS` for every donor used by the profile. Verify that an image
   is real binary data rather than a Git LFS pointer.
6. Add `devices/<device>/profile.sh`, then test detection, `lpmake` allocation,
   output naming and the recovery project-ID check.

Some donor images are tracked with Git LFS according to `.gitattributes`.
Always run `git lfs pull` on a fresh clone and check `sha256sum -c SHA256SUMS`.

## Partition and mod dependency map

`needs_partition_tree()` controls which raw images become writable filesystem
trees. Keep it synchronized with every mod's actual paths.

| Modification | Default | Skip option | Required trees/JARs | Writes |
| --- | --- | --- | --- | --- |
| Debloat | On | `--skip-debloat` | `system_ext`, `my_product`, `my_stock` | Matching app directories; `my_product/etc/auto-install*` |
| YouTube Morphe | On | `--skip-youtube-morphe` | `my_product`, `system` | YouTube APK/libs in `my_product`; init rc in `system/etc/init` |
| GGPhotosUnlimited | On | `--skip-photos-spoof` | `system`; `framework.jar` | Framework smali and one new DEX tree |
| DisableFlagSecure | On | `--skip-secure-flag` | `system`; `services.jar` | Window/device-policy smali targets available in the ROM |
| LockAssistantBypass | On | `--skip-lock-assistant-bypass` | `system`, `my_stock`; `oplus-services.jar` | Removes LockAssistant from extracted app trees; patches two service methods |
| DisableSafeMediaVolume | Always | None | `system`; `services.jar` | `SoundDoseHelper.checkSafeMediaVolume_l(III)Z` returns false |
| AVB fstab removal | Always | None | `vendor`, raw `boot`, raw `vendor_boot` | Removes `avb`, `avb=`, `avb_keys=` and `verify` fstab flags |

LockAssistant removal scans any extracted `system`, `system_ext`, `my_product`
and `my_stock` trees, but only app roots named `app`, `priv-app`, `del-app` or
`del-app-pre`. Its dependency currently guarantees `system` and `my_stock`;
other trees are scanned only when another enabled mod caused their extraction.

Debloat matches directory basenames from `APPLIST.txt` only below those same app
root names. It additionally removes top-level `auto-install*` files from
`my_product/etc`.

Current smali targets are deliberately independent:

- `DisableSafeMediaVolume`: replaces
  `SoundDoseHelper.checkSafeMediaVolume_l(III)Z` with `false`.
- `LockAssistantBypass`: replaces
  `OplusCustomizeService.getOperator()I` with `0` and `getFeeState()I` with `5`.
- `DisableFlagSecure`: patches compatible `WindowState`/`WindowStateAnimator`,
  `DevicePolicyCacheImpl`, and OEM capture-display guards in `services.jar`.
  OEM targets vary by ROM, so missing optional capture-display anchors are
  warnings; the patch fails only when no compatible target is changed.
- `GGPhotosUnlimited`: injects hooks into `Instrumentation` and
  `ApplicationPackageManager`, then adds `GooglePhotosSpoof.smali` in a new DEX.

## Shared JAR lifecycle

Do not let an individual mod decode or rebuild a framework JAR. The lifecycle is:

```text
register_jar <id> <path>
        -> unpack_jars
        -> all selected patch.sh scripts edit jar_smali_root(<id>)
        -> pack_jars
```

Current registrations:

| JAR ID | Image path | Registered when |
| --- | --- | --- |
| `services` | `system/framework/services.jar` | Always |
| `oplus-services` | `system/framework/oplus-services.jar` | LockAssistantBypass enabled |
| `framework` | `system/framework/framework.jar` | GGPhotosUnlimited enabled |

Inside an extracted system-as-root image, `system_root` may resolve to either
`images/system` or `images/system/system`; always use the resolved
`$framework_dir` rather than hard-coding both layouts.

`register_jar` must finish before `unpack_jars`. Registering later, unpacking
twice, packing before unpack, or packing twice is intentionally fatal. A mod's
`patch.sh` receives exactly one prepared directory such as:

```text
$WORK_DIR/jars/services/unpacked
```

It contains archive resources plus `classes.dex.out`, `classes2.dex.out`, etc.
The original DEX files are removed during disassembly and recreated only by
`pack_jars`. Reuse an existing JAR ID when several mods target the same JAR.

## Adding a mod

### Smali/JAR mod

1. Create `bin/package/<ModName>/patch.sh` and a focused patcher. The shell
   wrapper must accept a prepared JAR directory; it must not run unzip,
   baksmali, smali, zipalign or copy the result back to the image.
2. Identify the exact source JAR and the partition containing it.
3. Add its enable/skip flag only if the feature is optional.
4. Update `needs_partition_tree()` so the owning filesystem is extracted.
5. Register its JAR before the single `unpack_jars` call. Reuse a registration
   if another mod already owns the same JAR.
6. Invoke the patch between `unpack_jars` and `pack_jars` with
   `"$(jar_smali_root <id>)"`.
7. Make the patcher validate class descriptors and full method signatures.
   Prefer exact expected target counts and fail before writing on incompatibility.
8. Update `patch-report.txt`, CLI help, README and this dependency table when
   user-visible behavior changes.

If a patch creates another DEX, choose an unused `classesN.dex.out` directory.
GGPhotosUnlimited is the current example. Avoid moving classes between DEX
trees unless necessary, because Android framework class-loader ordering matters.

### Filesystem mod

1. Put implementation and resources in `bin/package/<ModName>/`.
2. Restrict searches and deletions to explicit safe roots. Validate paths before
   recursive removal.
3. Call `mark_modified <partition>` or `mark_modified_path <changed-path>` for
   every partition written. This is mandatory; otherwise the edit is discarded
   because that partition will not be rebuilt.
4. Add every required tree to `needs_partition_tree()` under the same enable
   condition.
5. Run the mod in the main mod section, before `pack_jars` when it should share
   the unified modification phase.
6. Update the patch report and documentation.

For an always-on mod, omit a skip flag and make its partition/JAR dependencies
unconditional. `DisableSafeMediaVolume` is the current example.

## Repack and SELinux contract

`mark_modified_path` derives the partition from paths below `$IMAGES_DIR` and
appends it to `state/modified_partitions`. Before repack the list is sorted and
restricted to the fast-mode set: `system`, `system_ext`, `my_product`,
`my_stock`, and `vendor`. Extending mods to another logical partition requires
updating this allow-list as well as `needs_partition_tree()`.

`bin/fix_selinux.py` runs once for each modified tree before image creation. It:

- Preserves original fs-config and file-context ordering.
- Adds metadata for newly created files/directories.
- Escapes non-ASCII file-context paths into byte escapes accepted by EROFS.
- Uses partition-specific fallback labels for known partition families.

Do not sort `file_contexts`: moving a generic catch-all rule before a specific
rule can change labels and substantially increase a rebuilt EROFS image.

EXT images are built to their original payload size. EROFS uses `lz4hc,9` with
16 KiB physical clusters; `lpmake` later aligns each logical image to 4096 bytes
and rejects total allocation above the profile's group maximum.

## Recovery package contract

The builder generates these control files:

- `device-profile.conf`: device name, accepted project IDs, ABL donor metadata
  and expected super size.
- `required-images.txt`: generated from the package contents, never a fixed
  cross-device list.
- `patch-report.txt`: input/build IDs, enabled mods, allocation and donor hashes.

The recovery installer:

1. Loads and validates the device profile.
2. Checks `ro.boot.prjname` against the profile's project IDs.
3. Validates required entries, image sizes, streamer binaries and block targets.
4. Asks for one volume-key confirmation.
5. Flashes EFISP first, then the ABL donor, ordinary firmware, and sparse super.
6. Selects slot A and instructs the user to format Data.

Firmware images are flashed to both `_a` and `_b` when both block devices exist,
or to the unsuffixed block device otherwise. Sparse `super.img` is streamed from
the stored ZIP entry into `/dev/block/by-name/super`; it is not first expanded
to recovery storage. Recovery itself is skipped.

Keep `super.img` stored (`zip -0`). The custom `stored_zip_streamer` handles
ZIP64 streaming and `sparse_stream_writer` expands Android sparse chunks to the
existing block device.

## Verification checklist

Run the cheapest checks after every change, then test both device profiles when
the change is common:

```bash
bash -n start-oplus.sh functions.sh bin/package/*/*.sh
python3 -m py_compile bin/fix_selinux.py bin/package/*/patcher.py
git diff --check
git status --short
```

For a JAR change:

- Test against stock JARs from every supported ROM family.
- Confirm all required JARs are unpacked before the first patch log.
- Confirm each registered JAR is rebuilt exactly once at the end.
- Open rebuilt archives with `unzip -t` or `7z t`.
- Confirm expected `classes*.dex` files exist and disassemble the changed methods
  again to verify their final bodies.
- Test multiple enabled patches targeting the same JAR together.

For a complete build:

- Use a full OTA, verify detected project ID and `ro.build.display.id`.
- Check ARB output, donor checksums, selected filesystem extraction and modified
  partition report.
- Confirm the output name contains the ROM version.
- Inspect `required-images.txt`, `device-profile.conf`, and `patch-report.txt`.
- Confirm sparse super allocation is below `SUPER_GROUP_SIZE` and the ZIP has
  non-empty EFISP, ABL donor, firmware images and `super.img`.

Incremental OTAs are not supported unless the payload extractor is supplied the
required source images; the normal build expects a full OTA.
