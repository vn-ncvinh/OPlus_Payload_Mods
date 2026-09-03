# OPlus Payload Mods

Build a modded recovery-flashable ZIP from an OPlus `payload.bin` or full OTA
ZIP. The device profile is detected automatically from `my_manifest`.

## Supported devices

| Device | Project ID |
| --- | --- |
| OPPO Find X9 Ultra | `25211` |
| OnePlus 15R | `24877` |

Unknown project IDs are rejected.

## Default mods

- Remove apps listed in `bin/ddevice/DEBLOAT/APPLIST.txt`.
- Replace stock YouTube with YouTube Morphe (no microG).
- `GGPhotosUnlimited`: enable unlimited Google Photos backup spoof.
- `DisableFlagSecure`: allow screenshots and screen recording in restricted apps.
- `LockAssistantBypass`: make `getOperator()` return `0` and `getFeeState()`
  return `5`.
- Remove AVB flags from `vendor`, `boot`, and `vendor_boot` fstab files.
- Generate GBL chainload EFISP from the payload `abl.img`.
- Package and always flash the profile-specific versioned ABL donor.

Before building, the script checks `xbl_config` and stops unless ARB is `0`.

## Requirements

- Ubuntu or WSL on x86_64
- At least 50 GB of free space
- `python3`, Java 21, `aapt`, `aria2c`, `unzip`, `zip`, `7za` or `7z`,
  and `zipalign`
- Git LFS for bundled donor images

After cloning:

```bash
git lfs pull
chmod +x start-oplus.sh bin/Linux/x86_64/*
```

## Build

```bash
./start-oplus.sh /path/to/payload.bin
```

Full OTA ZIP input is also supported:

```bash
./start-oplus.sh /path/to/full-ota.zip
```

The output directory must be empty. To select another directory:

```bash
./start-oplus.sh /path/to/full-ota.zip --output /path/to/output
```

## Options

```text
--youtube-morphe-url <url>    Use a specific YouTube Morphe module
--skip-debloat                Keep stock apps
--skip-youtube-morphe         Keep stock YouTube
--skip-photos-spoof           Disable GGPhotosUnlimited
--skip-secure-flag            Disable DisableFlagSecure
--skip-lock-assistant-bypass  Disable LockAssistantBypass
--skip-avb                    Keep stock AVB fstab flags
--keep-workdir                Keep extracted temporary files
```

Run `./start-oplus.sh --help` for the complete CLI help.

## Output and flashing

The output filename includes `ro.build.display.id`, for example:

```text
X9U_Mods_CPH2841_16.0.10.500(EX01)_Recovery.zip
```

The recovery ZIP contains payload firmware, a profile-specific sparse
`super.img`, required donor partitions, a versioned ABL donor such as
`abl-16.0.6.img` at the ZIP root, and the generated GBL chainload EFISP. The
installer validates all required files before confirmation, then always flashes
EFISP and the profile ABL donor first, followed by the other firmware and
`super.img`, through `/dev/block/by-name/*`. It does not resize or modify the
GPT.

## Warning

This tool modifies and flashes critical partitions. Use only a matching full
OTA for a supported device. Keep a tested recovery or EDL restore method
available. The existing `super` partition must be at least:

- Find X9 Ultra: `20,451,426,304` bytes
- OnePlus 15R: `16,231,956,480` bytes
