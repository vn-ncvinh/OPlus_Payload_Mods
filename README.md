# OPlus Payload Mods

Payload v2 patcher and OPPO Find X9 Ultra recovery-flasher builder for
ColorOS/OxygenOS layouts that use `my_product`.

This repository is a standalone extraction of the required tooling and patch logic from Xiaomi 8E5 Global Mods. It does not read or source files from that repository at runtime.

## Included patches

- Exact-name debloat using `bin/ddevice/DEBLOAT/APPLIST.txt`.
- YouTube Morphe without microG. The stock APK remains at `my_product/app/YouTube/YouTube.apk`; Android init bind-mounts Morphe over the OPlus `/product/app/YouTube` overlay view after Package Manager scans it.
- Independently selectable Google Photos Pixel XL spoof and secure-flag/screen-capture bypass patches.
- Optional AVB-flag removal from `vendor` fstab plus the `boot` and `vendor_boot`
  ramdisks (`--skip-avb` disables it).

## Requirements

Run from Ubuntu/WSL x86_64 with at least 50 GB of free workspace. The large
image tools are bundled in `bin/`; install these host packages/commands:

`python3`, `openjdk-21-jre`, `aapt`, `aria2`, `unzip`, `zip`, `p7zip-full`,
`zipalign`, and `git-lfs`.

The Thai `my_preload` donor with bundled APKs removed is stored with Git LFS. Run `git lfs pull`
after cloning; the build aborts if the donor is missing or is still an LFS
pointer.

## Usage

```bash
chmod +x start-oplus.sh bin/Linux/x86_64/*
./start-oplus.sh /path/to/payload.bin
```

Use `./start-oplus.sh --help` for patch toggles and output options. The output
directory receives one `X9U_Mods_Recovery.zip`. It contains firmware from the
input payload and a sparse `super.img` assembled from untouched payload images,
the patched images, the stock Thai `my_company`, and the debloated Thai
`my_preload` donor.

Use `--skip-photos-spoof` and `--skip-secure-flag` to disable the two framework patches independently.

EROFS images are rebuilt with `lz4hc,9` compression and 16 KiB physical
clusters. A modified logical image may grow beyond its old allocation as long
as all images still fit the X9 Ultra dynamic-partition group.

The current paths and patch anchors were checked against an unpacked CPH2841 Android 16 payload; see [`docs/cph2841-layout.md`](docs/cph2841-layout.md).

## Warning

The generated installer is only for unlocked Find X9 Ultra project IDs
`25021`/`25022` with the expected `sda14` super and `sda15` userdata GPT
layout. It may resize the physical super partition and requires formatting
data. Keep a tested recovery/EDL path and review the on-device confirmation
screen before flashing.
