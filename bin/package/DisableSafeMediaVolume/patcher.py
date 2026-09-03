#!/usr/bin/env python3
import re
import sys
from pathlib import Path


CLASS_SOUND_DOSE_HELPER = "Lcom/android/server/audio/SoundDoseHelper;"
METHOD_CHECK_SAFE_MEDIA_VOLUME = "checkSafeMediaVolume_l(III)Z"


def read_lines(path: Path) -> list[str]:
    return path.read_text(encoding="utf-8", errors="strict").splitlines()


def write_lines(path: Path, lines: list[str]) -> None:
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def class_name(lines: list[str]) -> str | None:
    for line in lines[:20]:
        if line.startswith(".class "):
            parts = line.split()
            return parts[-1] if parts else None
    return None


def find_method_bounds(lines: list[str], signature: str) -> tuple[int, int] | None:
    method_re = re.compile(r"^\s*\.method\b.*\s" + re.escape(signature) + r"\s*$")
    matches: list[tuple[int, int]] = []
    for start, line in enumerate(lines):
        if not method_re.match(line):
            continue
        for end in range(start + 1, len(lines)):
            if lines[end].strip() == ".end method":
                matches.append((start, end))
                break
        else:
            raise RuntimeError(f"Method has no .end method: {signature}")

    if len(matches) > 1:
        raise RuntimeError(f"Method occurs more than once in a class: {signature}")
    return matches[0] if matches else None


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: patcher.py <services.jar.out>", file=sys.stderr)
        return 2

    root = Path(sys.argv[1])
    if not root.is_dir():
        print(f"services smali directory not found: {root}", file=sys.stderr)
        return 2

    target = f"{CLASS_SOUND_DOSE_HELPER}->{METHOD_CHECK_SAFE_MEDIA_VOLUME}"
    match: tuple[Path, list[str], int, int] | None = None

    for path in root.rglob("*.smali"):
        lines = read_lines(path)
        if class_name(lines) != CLASS_SOUND_DOSE_HELPER:
            continue
        bounds = find_method_bounds(lines, METHOD_CHECK_SAFE_MEDIA_VOLUME)
        if bounds is None:
            continue
        if match is not None:
            print(f"[disable-safe-media-volume][error] Target occurs more than once: {target}", file=sys.stderr)
            return 1
        match = (path, lines, *bounds)

    if match is None:
        print(f"[disable-safe-media-volume][error] Target not found: {target}", file=sys.stderr)
        return 1

    path, lines, start, end = match
    lines[start + 1 : end] = [
        "    .locals 1",
        "",
        "    const/4 v0, 0x0",
        "",
        "    return v0",
    ]
    write_lines(path, lines)
    print(f"[disable-safe-media-volume] patched {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
