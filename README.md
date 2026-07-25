# OPlus Payload Mods

Minimal payload v2 patcher for ColorOS/OxygenOS layouts that use `my_product`.

This repository is a standalone extraction of the required tooling and patch logic from Xiaomi 8E5 Global Mods. It does not read or source files from that repository at runtime.

## Included patches

- Exact-name debloat using `bin/ddevice/DEBLOAT/APPLIST.txt`.
- YouTube Morphe without microG, installed under `my_product` and activated by Android init.
- Kousei Google Photos Pixel XL spoof and secure-flag/screen-capture bypass.
- Full DISABLE_AVB flow: `vbmeta*`, vendor fstab, `boot` and `vendor_boot` ramdisks.

## Requirements

Run from Ubuntu/WSL x86_64. The large image tools are bundled in `bin/`; install these host packages/commands:

`python3`, `openjdk-21-jre`, `aapt`, `aria2`, `unzip`, `p7zip-full`, `zipalign`.

## Usage

```bash
chmod +x start-oplus.sh bin/Linux/x86_64/*
./start-oplus.sh /path/to/payload.bin
```

Use `./start-oplus.sh --help` for patch toggles and output options. The script emits raw partition images rather than rebuilding an OTA payload.

## Warning

Modified Android partitions and disabled verified boot can make a device unbootable. Keep the original images and a tested recovery/EDL path. Output images are never flashed automatically.
