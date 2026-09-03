# OPlus Payload Mods

Build a modded, recovery-flashable ZIP from an OPlus full OTA ZIP or
`payload.bin`. The device and ROM version are read from
`my_manifest/build.prop`; there is no manual device selector.

## Supported devices

| Device | Accepted project ID | ABL donor | Required `super` size |
| --- | --- | --- | ---: |
| OPPO Find X9 Ultra | `25211` | `16.0.6` | `20,451,426,304` bytes |
| OnePlus 15R | `24877` | `16.0.1` | `16,231,956,480` bytes |

The build stops for an unknown project ID or when `xbl_config` reports a
non-zero anti-rollback (ARB) value.

## Applied modifications

Always enabled:

- Disable the classic safe headphone-volume check.
- Remove AVB/verify flags from fstab files in `vendor`, `boot`, and
  `vendor_boot`.
- Generate a GBL Chainload v2.3.4 mode 1 EFISP from the OTA's `abl.img`.
- Include and flash the device-specific, versioned vulnerable ABL donor.

Enabled by default, with individual skip options:

- Debloat using `bin/ddevice/DEBLOAT/APPLIST.txt`.
- Integrate YouTube Morphe without microG.
- `GGPhotosUnlimited`: apply the Google Photos Pixel XL spoof.
- `DisableFlagSecure`: bypass supported screenshot and screen-capture checks.
- `LockAssistantBypass`: remove the LockAssistant app and patch
  `OplusCustomizeService.getOperator()`/`getFeeState()`.

## Requirements

- Linux or WSL on x86_64
- At least 50 GB of free disk space
- Python 3, Java 21, `aapt`, `aria2c`, `unzip`, `zip`, `zipalign`, and either
  `7za` or `7z`
- Git LFS for donor images tracked through LFS

After cloning:

```bash
git lfs install
git lfs pull
chmod +x start-oplus.sh bin/Linux/x86_64/*
```

## Usage

```bash
./start-oplus.sh /path/to/full-ota.zip
```

`payload.bin` is also accepted. To choose an output directory:

```bash
./start-oplus.sh /path/to/payload.bin --output /path/to/empty-output
```

The output directory must not contain any files.

Options:

```text
--output <dir>                Set the output directory (default: ./output)
--youtube-morphe-url <url>    Use a specific YouTube Morphe module ZIP
--skip-debloat                Keep the listed stock apps
--skip-youtube-morphe         Do not integrate YouTube Morphe
--skip-photos-spoof           Do not apply GGPhotosUnlimited
--skip-secure-flag            Do not apply DisableFlagSecure
--skip-lock-assistant-bypass  Keep LockAssistant and its stock service methods
--keep-workdir                Preserve temporary files for inspection
```

There is intentionally no option to skip the safe-volume or AVB patches.

## Output and flashing

The filename includes `ro.build.display.id`, for example:

```text
X9U_Mods_CPH2841_16.0.10.500(EX01)_Recovery.zip
OP15R_Mods_CPH2767_16.0.10.500(EX01)_Recovery.zip
```

The installer validates its generated image list before confirmation and checks
each block target and size before writing it. It then flashes, in order:

1. `efisp-gbl-chainload-mode1.efi` to `/dev/block/by-name/efisp`.
2. The profile's ABL donor to both ABL slots when both exist.
3. Payload firmware images through `/dev/block/by-name/<partition>`.
4. The generated sparse `super.img` directly to `/dev/block/by-name/super`.

It does not resize the GPT or `super`, and it keeps the current recovery. Format
Data before booting the newly flashed ROM.

> [!WARNING]
> This project modifies and flashes critical partitions. Use only a matching
> full OTA for a supported device and keep a tested recovery or EDL restore
> method available.

## Development

See [DOCS.MD](DOCS.MD) for the repository architecture, build pipeline, mod
dependency map, and the checklist for adding devices or patches.
