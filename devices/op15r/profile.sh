DEVICE_ID=op15r
DEVICE_DISPLAY="OnePlus 15R"
OUTPUT_ZIP="OP15R_Mods_Recovery.zip"
SUPPORTED_PROJECT_IDS="24855 24877"
CARRIER_LOCK_SNAPSHOT=""

SUPER_SIZE=16231956480
SUPER_GROUP_SIZE=16227762176
SUPER_ALIGNMENT=1048576
SUPER_ALIGNMENT_OFFSET=0
SUPER_METADATA_SIZE=65536
SUPER_METADATA_SLOTS=3

DYNAMIC_PARTITIONS=(
    system system_ext vendor product my_product odm my_engineering vendor_dlkm
    system_dlkm my_stock my_heytap my_carrier my_region my_bigball my_manifest
)
DONOR_PARTITIONS=(system_dlkm_oki my_company my_preload)
DONOR_RELATIVE_DIR="assets/op15r/donors"
ABL_DONOR_IMAGE="abl-16.0.1.img"
ABL_DONOR_VERSION="16.0.1"
