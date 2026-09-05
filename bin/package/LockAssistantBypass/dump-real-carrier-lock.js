Java.perform(() => {
    const LockDataProcessor = Java.use(
        "com.oplus.channellock.carrierlock.LockDataProcessor"
    );

    const SimInterface = Java.use(
        "com.oplus.sim.SimInterface"
    );

    const Resp = Java.use(
        "com.oplus.radio.SubsysRadioResponse"
    );

    function hex(data) {
        if (data === null)
            return "<null>";

        return Array.from(data)
            .map(x => (x & 0xff).toString(16).padStart(2, "0"))
            .join(" ");
    }

    /*
     * Hook raw response trực tiếp từ subsys/modem.
     */
    const getResp = Resp.getCarrierLockStatusResponse.overload(
        "vendor.oplus.hardware.subsys_interface.subsys.SubsysResponseInfo",
        "[B"
    );

    getResp.implementation = function (info, data) {
        console.log("");
        console.log("========== GET CARRIER LOCK RESPONSE ==========");
        console.log(
            "serial=" + info.serial.value +
            " error=" + info.error.value +
            " type=" + info.type.value
        );

        console.log("length=" + (data !== null ? data.length : 0));
        console.log("RAW=" + hex(data));

        // Parse TLV để nhìn dễ hơn
        if (data !== null) {
            const bytes = Array.from(data).map(x => x & 0xff);
            let i = 0;

            while (i + 3 <= bytes.length) {
                const tag = bytes[i];
                const len =
                    (bytes[i + 1] << 8) |
                    bytes[i + 2];

                if (i + 3 + len > bytes.length) {
                    console.log(
                        "[!] Invalid TLV: offset=" + i +
                        " tag=0x" + tag.toString(16) +
                        " len=" + len
                    );
                    break;
                }

                const value = bytes.slice(
                    i + 3,
                    i + 3 + len
                );

                console.log(
                    "TAG 0x" +
                    tag.toString(16).padStart(2, "0") +
                    " LEN=" + len +
                    " VALUE=" +
                    value.map(x =>
                        x.toString(16).padStart(2, "0")
                    ).join(" ")
                );

                if (tag === 0x03) {
                    let raw = 0;

                    for (const b of value)
                        raw = (raw << 8) | b;

                    const logical =
                        raw === 0xff ? -1 : raw;

                    console.log(
                        ">>> OPERATOR raw=0x" +
                        raw.toString(16)
                            .padStart(len * 2, "0") +
                        " logical=" + logical
                    );
                }

                i += 3 + len;
            }
        }

        console.log("===============================================");

        return getResp.call(this, info, data);
    };

    /*
     * Chủ động gửi query xuống modem.
     */
    const sim = SimInterface.getDefaultInstance();

    const request =
        LockDataProcessor.TLV_CONTENT_ALL.value;

    console.log(
        "[+] Request TLV = " + hex(request)
    );

    sim.getCarrierLockStatus
        .overload("[B", "android.os.Message")
        .call(
            sim,
            request,
            null
        );

    console.log(
        "[+] getCarrierLockStatus() sent to modem"
    );
});
