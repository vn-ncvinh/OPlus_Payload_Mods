DEVICE_ID=x9u
DEVICE_DISPLAY="OPPO Find X9 Ultra"
OUTPUT_ZIP="X9U_Mods_Recovery.zip"
SUPPORTED_PROJECT_IDS="25021 25022 25211"
CARRIER_LOCK_SNAPSHOT="devices/x9u/carrier-lock-status.hex"

SUPER_SIZE=20451426304
SUPER_GROUP_SIZE=20447232000
SUPER_ALIGNMENT=524288
SUPER_ALIGNMENT_OFFSET=81920
SUPER_METADATA_SIZE=65536
SUPER_METADATA_SLOTS=3

DYNAMIC_PARTITIONS=(
    system system_ext product vendor odm my_product my_engineering vendor_dlkm
    system_dlkm my_stock my_heytap my_carrier my_region my_bigball my_manifest
)
DONOR_PARTITIONS=(my_company my_preload)
DONOR_RELATIVE_DIR="assets/x9u/donors"
ABL_DONOR_IMAGE="abl-16.0.6.img"
ABL_DONOR_VERSION="16.0.6"
