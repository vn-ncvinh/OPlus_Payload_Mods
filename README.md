# OPlus Payload Mods

Minimal payload v2 patcher for ColorOS/OxygenOS layouts that use `my_product`.

This repository is a standalone extraction of the required tooling and patch logic from Xiaomi 8E5 Global Mods. It does not read or source files from that repository at runtime.

## Included patches

- Exact-name debloat using `bin/ddevice/DEBLOAT/APPLIST.txt`.
- YouTube Morphe without microG. The stock APK remains at `my_product/app/YouTube/YouTube.apk`; Android init bind-mounts Morphe over the OPlus `/product/app/YouTube` overlay view after Package Manager scans it.
- Independently selectable Google Photos Pixel XL spoof and secure-flag/screen-capture bypass patches.
- Optional `vendor_boot` ramdisk AVB-flag removal (`--skip-avb` disables it).

## Requirements

Run from Ubuntu/WSL x86_64. The large image tools are bundled in `bin/`; install these host packages/commands:

`python3`, `openjdk-21-jre`, `aapt`, `aria2`, `unzip`, `p7zip-full`, `zipalign`.

## Usage

```bash
chmod +x start-oplus.sh bin/Linux/x86_64/*
./start-oplus.sh /path/to/payload.bin
```

Use `./start-oplus.sh --help` for patch toggles and output options. The script emits raw partition images rather than rebuilding an OTA payload.

Use `--skip-photos-spoof` and `--skip-secure-flag` to disable the two framework patches independently.

EROFS images are rebuilt with `lz4hc,9` compression and 16 KiB physical clusters to keep modified images within their original partition sizes.

The current paths and patch anchors were checked against an unpacked CPH2841 Android 16 payload; see [`docs/cph2841-layout.md`](docs/cph2841-layout.md).

## Warning

Flashing modified Android partitions can make a device unbootable. Keep the original images and a tested recovery/EDL path. Output images are never flashed automatically.
