# CPH2841 payload layout

Reference layout verified from an unpacked Android 16 / SDK 36 payload:

- Stock YouTube: `/my_product/app/YouTube/YouTube.apk`.
- Runtime app view: `/product/app/YouTube`, provided by the overlayfs lowerdir `/my_product/app` in `vendor/etc/fstab.qcom`.
- Android framework: `/system/system/framework/framework.jar` inside the extracted system-as-root image.
- Secure-flag targets: `/system/system/framework/services.jar`; `oplus-services.jar` is also inspected for compatible OEM targets.
- Init scripts: `/system/system/etc/init` in the extracted tree, mounted as `/system/etc/init`.
- OPlus partitions such as `my_product`, `my_stock`, `my_region`, and `odm` are independent EROFS images rather than directories owned by `system.img`.

The source images use EROFS with per-partition build options. Modified images are rebuilt with `lz4hc,9` compression and 16 KiB physical clusters to keep them within their original partition sizes.
