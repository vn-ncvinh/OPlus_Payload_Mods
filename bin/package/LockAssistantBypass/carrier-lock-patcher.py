#!/usr/bin/env python3
import re
import sys
from pathlib import Path


PROCESSOR = "Lcom/oplus/channellock/carrierlock/LockDataProcessor;"
HELPER = "Lcom/oplus/channellock/carrierlock/CarrierLockInfoSpoof;"
PARSE = "parseDataFromTlv([BZ)I"


HELPER_SMALI = r'''.class final Lcom/oplus/channellock/carrierlock/CarrierLockInfoSpoof;
.super Ljava/lang/Object;


.method private static decode(Ljava/lang/String;)[B
    .registers 8

    invoke-virtual {p0}, Ljava/lang/String;->length()I
    move-result v0
    div-int/lit8 v1, v0, 0x2
    new-array v1, v1, [B
    const/4 v2, 0x0

    :loop
    if-ge v2, v0, :done
    invoke-virtual {p0, v2}, Ljava/lang/String;->charAt(I)C
    move-result v3
    const/16 v4, 0x10
    invoke-static {v3, v4}, Ljava/lang/Character;->digit(CI)I
    move-result v3
    shl-int/lit8 v3, v3, 0x4
    add-int/lit8 v5, v2, 0x1
    invoke-virtual {p0, v5}, Ljava/lang/String;->charAt(I)C
    move-result v5
    invoke-static {v5, v4}, Ljava/lang/Character;->digit(CI)I
    move-result v5
    or-int/2addr v3, v5
    div-int/lit8 v5, v2, 0x2
    int-to-byte v6, v3
    aput-byte v6, v1, v5
    add-int/lit8 v2, v2, 0x2
    goto :loop

    :done
    return-object v1
.end method


# Replace every modem query/indication with the captured unlocked snapshot.
.method static rewrite([B)[B
    .registers 2

    const-string v0, "@CANONICAL_HEX@"
    invoke-static {v0}, Lcom/oplus/channellock/carrierlock/CarrierLockInfoSpoof;->decode(Ljava/lang/String;)[B
    move-result-object v0
    return-object v0
.end method
'''


def read_lines(path: Path) -> list[str]:
    return path.read_text(encoding="utf-8", errors="strict").splitlines()


def write_lines(path: Path, lines: list[str]) -> None:
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def class_name(lines: list[str]) -> str | None:
    for line in lines[:20]:
        if line.startswith(".class "):
            return line.split()[-1]
    return None


def find_method_bounds(lines: list[str], signature: str) -> tuple[int, int] | None:
    pattern = re.compile(r"^\s*\.method\b.*\s" + re.escape(signature) + r"\s*$")
    matches: list[tuple[int, int]] = []
    for start, line in enumerate(lines):
        if not pattern.match(line):
            continue
        for end in range(start + 1, len(lines)):
            if lines[end].strip() == ".end method":
                matches.append((start, end))
                break
        else:
            raise RuntimeError(f"Method has no .end method: {signature}")
    if len(matches) > 1:
        raise RuntimeError(f"Method occurs more than once: {signature}")
    return matches[0] if matches else None


def load_snapshot(path: Path) -> str:
    try:
        snapshot_hex = "".join(path.read_text(encoding="ascii").split()).lower()
        data = bytes.fromhex(snapshot_hex)
    except (OSError, UnicodeError, ValueError) as exc:
        raise RuntimeError(f"Invalid carrier-lock snapshot: {exc}") from exc

    index = 0
    operator_count = 0
    while index < len(data):
        if index + 3 > len(data):
            raise RuntimeError("Carrier-lock snapshot has a truncated TLV header")
        tag = data[index]
        length = int.from_bytes(data[index + 1 : index + 3], "big")
        end = index + 3 + length
        if end > len(data):
            raise RuntimeError(f"Carrier-lock snapshot has a truncated tag {tag}")
        if tag == 3:
            operator_count += 1
            if length == 0 or int.from_bytes(data[index + 3 : end], "big") != 0xFF:
                raise RuntimeError("Carrier-lock snapshot operator must encode 0xFF")
        index = end

    if operator_count != 1:
        raise RuntimeError(f"Expected one operator tag, found {operator_count}")
    return snapshot_hex


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: patcher.py <subsys-channel-lock-plugin.jar.out> <snapshot.hex>", file=sys.stderr)
        return 2

    root = Path(sys.argv[1])
    snapshot_path = Path(sys.argv[2])
    if not root.is_dir():
        print(f"Channel Lock smali directory not found: {root}", file=sys.stderr)
        return 2
    try:
        snapshot_hex = load_snapshot(snapshot_path)
    except RuntimeError as exc:
        print(f"[lock-assistant-bypass][carrier-lock][error] {exc}", file=sys.stderr)
        return 1

    found: tuple[Path, list[str], int, int] | None = None
    for path in root.rglob("*.smali"):
        lines = read_lines(path)
        if class_name(lines) != PROCESSOR:
            continue
        bounds = find_method_bounds(lines, PARSE)
        if bounds is None:
            continue
        if found is not None:
            print("[lock-assistant-bypass][carrier-lock][error] Parser occurs more than once", file=sys.stderr)
            return 1
        found = (path, lines, *bounds)

    if found is None:
        print(f"[lock-assistant-bypass][carrier-lock][error] Target not found: {PROCESSOR}->{PARSE}", file=sys.stderr)
        return 1

    path, lines, start, end = found
    data_alias = "move-object/from16 v2, p1"
    aliases = [i for i in range(start + 1, end) if lines[i].strip() == data_alias]
    if len(aliases) != 1:
        print(
            f"[lock-assistant-bypass][carrier-lock][error] Expected one parser data alias, found {len(aliases)}",
            file=sys.stderr,
        )
        return 1

    marker = f"invoke-static {{v2}}, {HELPER}->rewrite([B)[B"
    helper_path = path.with_name("CarrierLockInfoSpoof.smali")
    if any(line.strip() == marker for line in lines[start:end]):
        if not helper_path.is_file():
            print("[lock-assistant-bypass][carrier-lock][error] Snapshot hook exists but helper is missing", file=sys.stderr)
            return 1
        print("[lock-assistant-bypass][carrier-lock] snapshot hook already present")
        return 0
    if helper_path.exists():
        print(f"[lock-assistant-bypass][carrier-lock][error] Helper already exists: {helper_path}", file=sys.stderr)
        return 1

    alias = aliases[0]
    lines[alias + 1 : alias + 1] = [
        "",
        "    # CarrierLockInfoSpoof: replace modem data with the canonical snapshot.",
        f"    {marker}",
        "",
        "    move-result-object v2",
    ]
    write_lines(path, lines)
    helper_path.write_text(
        HELPER_SMALI.replace("@CANONICAL_HEX@", snapshot_hex), encoding="utf-8"
    )

    print(
        f"[lock-assistant-bypass][carrier-lock] injects a {len(snapshot_hex) // 2}-byte snapshot before "
        f"{PROCESSOR}->{PARSE}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
