#!/usr/bin/env python3
import re
import sys
from pathlib import Path


CLASS_CUSTOMIZE_SERVICE = "Lcom/android/server/oplus/customize/OplusCustomizeService;"
CLASS_LOCK_OBSERVER = (
    "Lcom/android/server/oplus/customize/"
    "OplusCustomizeService$LockAssistantFileObserver;"
)

METHOD_GET_OPERATOR = "getOperator()I"
METHOD_GET_FEE_STATE = "getFeeState()I"
METHOD_LOCK_EVENT = "onEvent(ILjava/lang/String;)V"


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


def replace_method_body(lines: list[str], signature: str, body: list[str]) -> bool:
    bounds = find_method_bounds(lines, signature)
    if bounds is None:
        return False
    start, end = bounds
    lines[start + 1 : end] = body
    return True


def patch_int_return(lines: list[str], signature: str, value: int) -> bool:
    return replace_method_body(
        lines,
        signature,
        [
            "    .locals 1",
            "",
            f"    const/4 v0, 0x{value:x}",
            "",
            "    return v0",
        ],
    )


def patch_void_return(lines: list[str], signature: str) -> bool:
    return replace_method_body(
        lines,
        signature,
        [
            "    .locals 0",
            "",
            "    return-void",
        ],
    )


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: patcher.py <jar.out>", file=sys.stderr)
        return 2

    root = Path(sys.argv[1])
    if not root.is_dir():
        print(f"oplus-services smali directory not found: {root}", file=sys.stderr)
        return 2

    expected = {
        f"{CLASS_CUSTOMIZE_SERVICE}->{METHOD_GET_OPERATOR}",
        f"{CLASS_CUSTOMIZE_SERVICE}->{METHOD_GET_FEE_STATE}",
        f"{CLASS_LOCK_OBSERVER}->{METHOD_LOCK_EVENT}",
    }
    patched: set[str] = set()
    changed_files: dict[Path, list[str]] = {}

    for path in root.rglob("*.smali"):
        lines = read_lines(path)
        cls = class_name(lines)
        changed = False

        if cls == CLASS_CUSTOMIZE_SERVICE:
            if patch_int_return(lines, METHOD_GET_OPERATOR, 0):
                patched.add(f"{cls}->{METHOD_GET_OPERATOR}")
                changed = True
            if patch_int_return(lines, METHOD_GET_FEE_STATE, 5):
                patched.add(f"{cls}->{METHOD_GET_FEE_STATE}")
                changed = True
        elif cls == CLASS_LOCK_OBSERVER:
            if patch_void_return(lines, METHOD_LOCK_EVENT):
                patched.add(f"{cls}->{METHOD_LOCK_EVENT}")
                changed = True

        if changed:
            changed_files[path] = lines

    missing = sorted(expected - patched)
    unexpected = sorted(patched - expected)
    if missing or unexpected:
        for target in missing:
            print(f"[lock-assistant-bypass][error] Target not found: {target}", file=sys.stderr)
        for target in unexpected:
            print(f"[lock-assistant-bypass][error] Unexpected target: {target}", file=sys.stderr)
        return 1

    for path, lines in changed_files.items():
        write_lines(path, lines)
    for target in sorted(patched):
        print(f"[lock-assistant-bypass] patched {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
