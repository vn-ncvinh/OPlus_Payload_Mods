# GBL chainload host bundle

Files in this directory were selected from the Linux
`gbl-chainload-tools-linux-v2.3.4` release bundle:

- `efisp-package.py`
- `bin/gbl`
- `gbl-chainload-v2.3.4.efi`
- `VERSION`

The ROM builder runs mode 1 with `--oem oplus`, validates the resulting GBLP1
container with `gbl inspect`, and packages `efisp-gbl-chainload-mode1.efi` at
the ZIP root. The recovery installer always flashes that file to
`/dev/block/by-name/efisp` without an additional prompt.

`vbmeta-graft.py` is intentionally not included because mode 1 does not use it.
The supplied release bundle did not contain a license file.
