# OPlus Payload Mods

Multi-device payload v2 patcher and recovery-flasher builder for OPlus
ColorOS/OxygenOS layouts that use `my_product`.

This repository is a standalone extraction of the required tooling and patch logic from Xiaomi 8E5 Global Mods. It does not read or source files from that repository at runtime.

## Included patches

- Exact-name debloat using `bin/ddevice/DEBLOAT/APPLIST.txt`.
- YouTube Morphe without microG. The stock APK remains at `my_product/app/YouTube/YouTube.apk`; Android init bind-mounts Morphe over the OPlus `/product/app/YouTube` overlay view after Package Manager scans it.
- Independent `GGPhotosUnlimited` Pixel XL spoof and `DisableFlagSecure`
  screen-capture bypass patches.
- Optional AVB-flag removal from `vendor` fstab plus the `boot` and `vendor_boot`
  ramdisks (`--skip-avb` disables it).
- Early `xbl_config` anti-rollback inspection; only ARB `0` is accepted.
- GBL chainload v2.3.4 mode 1 EFISP generated from the payload `abl.img` with
  the OPlus OEM patch, stored at the ZIP root, then always flashed to
  `/dev/block/by-name/efisp` without an additional prompt.

## Requirements

Run from Ubuntu/WSL x86_64 with at least 50 GB of free workspace. The large
image tools are bundled in `bin/`; install these host packages/commands:

`python3`, `openjdk-21-jre`, `aapt`, `aria2`, `unzip`, `zip`, `p7zip-full`,
`zipalign`, and `git-lfs`.

The Find X9 Ultra Thai `my_preload` donor with bundled APKs removed is stored
with Git LFS. Run `git lfs pull` after cloning; X9U builds abort if the donor
is missing or is still an LFS pointer. OnePlus 15R uses its own donor set from
`assets/op15r/donors`: `system_dlkm_oki`, `my_company`, and the `34604038`
variant of `my_preload` corresponding to metadata/NV ID `10100001`.

## Usage

```bash
chmod +x start-oplus.sh bin/Linux/x86_64/*
./start-oplus.sh /path/to/payload.bin
./start-oplus.sh /path/to/full-ota.zip
```

Use `./start-oplus.sh --help` for patch toggles and output options. The script
first extracts only `xbl_config` for the ARB gate, then extracts only
`my_manifest` and reads its project-ID properties to automatically select the
matching device profile. Project ID `24877` selects OnePlus 15R; `25021`,
`25022`, or `25211`
selects Find X9 Ultra. Unknown IDs stop the build. The filename includes
`ro.build.display.id` read from `my_manifest/build.prop`, for example
`OP15R_Mods_CPH2767_16.0.10.500(EX01)_Recovery.zip`. Each ZIP contains firmware
from its input payload, a profile-specific sparse `super.img`, and a generated
`required-images.txt` checked before flash confirmation. Each profile supplies
its own donor partition list; donor images replace the corresponding payload
images inside `super.img` and are not also flashed as standalone partitions.

The bundled `arbextract` binary comes from
[`koaaN/arbextract` release 1.0](https://github.com/koaaN/arbextract/releases/tag/1.0).
The build stops before applying any mods when `xbl_config` reports non-zero ARB.

Use `--skip-photos-spoof` and `--skip-secure-flag` to disable the two framework patches independently.
Disabled mods no longer cause unrelated filesystem trees to be unpacked: debloat
uses `system_ext`, `my_product`, and `my_stock`; YouTube Morphe uses `system`
and `my_product`; both framework patches use only `system`.

EROFS images are rebuilt with `lz4hc,9` compression and 16 KiB physical
clusters. A modified logical image may grow beyond its old allocation as long
as all images still fit the selected device's dynamic-partition group.

The current paths and patch anchors were checked against an unpacked CPH2841 Android 16 payload; see [`docs/cph2841-layout.md`](docs/cph2841-layout.md).

## Warning

Supported recovery targets are Find X9 Ultra project IDs
`25021`/`25022`/`25211` and OnePlus 15R project ID `24877`. The installer
never resizes or otherwise modifies the GPT. The existing `super` must be at
least 20,451,426,304 bytes for X9U or 16,231,956,480 bytes for OnePlus 15R. Keep a
tested recovery/EDL path and review the on-device confirmation screen before
flashing.
