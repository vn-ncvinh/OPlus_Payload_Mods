#!/usr/bin/env python3
import os
import re
import sys
from pathlib import Path


CLASS_DEVICE_POLICY = "Lcom/android/server/devicepolicy/DevicePolicyCacheImpl;"
CLASS_WINDOW_STATE = {
    "Lcom/android/server/wm/WindowState;",
    "Lcom/android/server/wm/WindowStateAnimator;",
}
CLASS_WINDOW_MANAGER_SERVICE_IMPL = "Lcom/android/server/wm/WindowManagerServiceImpl;"

METHOD_SCREEN_CAPTURE_ALLOWED = "isScreenCaptureAllowed(I)Z"
METHOD_IS_SECURE_LOCKED = "isSecureLocked()Z"
METHOD_SET_SECURE_LOCKED = "setSecureLocked(Z)V"
METHOD_CAPTURE_DISPLAY = (
    "captureDisplay(ILandroid/window/ScreenCapture$CaptureArgs;"
    "Landroid/window/ScreenCapture$ScreenCaptureListener;)V"
)
METHOD_NOT_ALLOW_CAPTURE_DISPLAY = (
    "notAllowCaptureDisplay(Lcom/android/server/wm/RootWindowContainer;I)Z"
)
NOT_ALLOW_CAPTURE_CALL = (
    "->notAllowCaptureDisplay(Lcom/android/server/wm/RootWindowContainer;I)Z"
)


def read_lines(path: Path) -> list[str]:
    return path.read_text(encoding="utf-8", errors="replace").splitlines()


def write_lines(path: Path, lines: list[str]) -> None:
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def class_name(lines: list[str]) -> str | None:
    for line in lines[:20]:
        if line.startswith(".class "):
            parts = line.split()
            return parts[-1] if parts else None
    return None


def iter_smali(root: Path):
    yield from root.rglob("*.smali")


def find_method_bounds(lines: list[str], signature: str) -> tuple[int, int] | None:
    method_re = re.compile(r"^\s*\.method\b.*\s" + re.escape(signature) + r"\s*$")
    for start, line in enumerate(lines):
        if not method_re.match(line):
            continue
        for end in range(start + 1, len(lines)):
            if lines[end].strip() == ".end method":
                return start, end
        raise RuntimeError(f"Method has no .end method: {signature}")
    return None


def replace_method_body(lines: list[str], signature: str, body: list[str]) -> bool:
    bounds = find_method_bounds(lines, signature)
    if bounds is None:
        return False
    start, end = bounds
    lines[start + 1 : end] = body
    return True


def patch_boolean_return(lines: list[str], signature: str, value: bool) -> bool:
    const_value = "0x1" if value else "0x0"
    return replace_method_body(
        lines,
        signature,
        [
            "    .locals 1",
            "",
            f"    const/4 v0, {const_value}",
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


def patch_capture_display(lines: list[str]) -> int:
    bounds = find_method_bounds(lines, METHOD_CAPTURE_DISPLAY)
    if bounds is None:
        return 0

    start, end = bounds
    patched = 0
    i = start + 1
    while i < end:
        if NOT_ALLOW_CAPTURE_CALL not in lines[i]:
            i += 1
            continue

        j = i + 1
        while j < end and not lines[j].strip():
            j += 1

        if j < end:
            match = re.match(r"^(\s*)move-result\s+([vp]\d+)\s*$", lines[j])
            if match:
                indent, register = match.groups()
                replacement = f"{indent}const/4 {register}, 0x0"
                if lines[j + 1 : j + 2] != [replacement]:
                    lines.insert(j + 1, replacement)
                    end += 1
                    patched += 1
                i = j + 2
                continue

        print(
            "[disable-flag-secure][warn] Found notAllowCaptureDisplay call but no move-result after it",
            file=sys.stderr,
        )
        i += 1

    return patched


def main() -> int:
    if len(sys.argv) not in (2, 3):
        print("Usage: patcher.py [--allow-empty] <jar.out>", file=sys.stderr)
        return 2

    allow_empty = False
    args = sys.argv[1:]
    if args[0] == "--allow-empty":
        allow_empty = True
        args = args[1:]
    if len(args) != 1:
        print("Usage: patcher.py [--allow-empty] <jar.out>", file=sys.stderr)
        return 2

    root = Path(args[0])
    if not root.is_dir():
        print(f"services smali directory not found: {root}", file=sys.stderr)
        return 2

    patched_items: list[str] = []
    warnings: list[str] = []

    found_device_policy = False
    found_window_secure = False
    found_capture_display = False

    for path in iter_smali(root):
        lines = read_lines(path)
        cls = class_name(lines)
        changed = False

        if cls == CLASS_DEVICE_POLICY:
            found_device_policy = True
            if patch_boolean_return(lines, METHOD_SCREEN_CAPTURE_ALLOWED, True):
                changed = True
                patched_items.append(f"{cls}->{METHOD_SCREEN_CAPTURE_ALLOWED}")
            else:
                warnings.append(f"Method not found: {cls}->{METHOD_SCREEN_CAPTURE_ALLOWED}")

        if cls in CLASS_WINDOW_STATE:
            if patch_boolean_return(lines, METHOD_IS_SECURE_LOCKED, False):
                changed = True
                found_window_secure = True
                patched_items.append(f"{cls}->{METHOD_IS_SECURE_LOCKED}")
            if patch_void_return(lines, METHOD_SET_SECURE_LOCKED):
                changed = True
                found_window_secure = True
                patched_items.append(f"{cls}->{METHOD_SET_SECURE_LOCKED}")

        if cls == CLASS_WINDOW_MANAGER_SERVICE_IMPL:
            if patch_boolean_return(lines, METHOD_NOT_ALLOW_CAPTURE_DISPLAY, False):
                changed = True
                found_capture_display = True
                patched_items.append(f"{cls}->{METHOD_NOT_ALLOW_CAPTURE_DISPLAY}")

        count = patch_capture_display(lines)
        if count:
            changed = True
            found_capture_display = True
            patched_items.append(f"{cls}->{METHOD_CAPTURE_DISPLAY} ({count} block override)")

        if changed:
            write_lines(path, lines)

    if not found_device_policy:
        warnings.append(f"Class not found: {CLASS_DEVICE_POLICY}")
    if not found_window_secure:
        warnings.append("Window secure methods not found in WindowState/WindowStateAnimator")
    if not found_capture_display:
        warnings.append("captureDisplay notAllowCaptureDisplay block not found; skipped")

    for item in patched_items:
        print(f"[disable-flag-secure] patched {item}")
    for warning in warnings:
        print(f"[disable-flag-secure][warn] {warning}", file=sys.stderr)

    if not patched_items and not allow_empty:
        print("[disable-flag-secure][error] No compatible targets were patched", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
