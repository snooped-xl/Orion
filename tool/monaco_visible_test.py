#!/usr/bin/env python3
"""Verify Monaco glyphs in the final, visible Linux desktop composition.

This helper only reads an owned, isolated Xvfb display. Start Xvfb/openbox for
the test and export ORION_TEST_XVFB_PID before launching the fixture. The crop
must be the native editor's screen rectangle, supplied by Flutter's test entry
point. This deliberately does not use WebKit snapshots or Monaco's DOM state:
both can succeed while another native layer obscures the editor on screen.
"""
from pathlib import Path
import argparse
import json
import os
import re
import subprocess
import sys


def property_value(window, name):
    return subprocess.check_output(
        ["xprop", "-id", str(window), name], text=True, stderr=subprocess.DEVNULL
    )


def owned_xvfb():
    display = os.environ.get("DISPLAY", "")
    match = re.fullmatch(r"(?:(?:localhost|127\.0\.0\.1):|:)(\d+)(?:\.\d+)?", display)
    if not match:
        raise RuntimeError("Visible readback requires a local isolated Xvfb display")
    server_pid = int(os.environ.get("ORION_TEST_XVFB_PID", "0"))
    if server_pid <= 0:
        raise RuntimeError("Set ORION_TEST_XVFB_PID to the owned test Xvfb process")
    process = Path(f"/proc/{server_pid}")
    command = (process / "cmdline").read_bytes().split(b"\0")
    if process.stat().st_uid != os.getuid():
        raise RuntimeError("Test Xvfb belongs to a different user")
    if Path(os.fsdecode(command[0])).name != "Xvfb":
        raise RuntimeError("The test display process is not Xvfb")
    if f":{match[1]}".encode() not in command:
        raise RuntimeError("DISPLAY does not match the owned Xvfb process")
    lock_pid = int(Path(f"/tmp/.X{match[1]}-lock").read_text().strip())
    if lock_pid != server_pid:
        raise RuntimeError("Xvfb display lock does not match the test process")


def owner_bounds(pid):
    listing = subprocess.check_output(
        ["xprop", "-root", "_NET_CLIENT_LIST_STACKING"], text=True
    )
    for identifier in reversed(re.findall(r"0x[0-9a-fA-F]+", listing)):
        try:
            value = property_value(identifier, "_NET_WM_PID")
            if not re.search(r"=\s*" + str(pid) + r"\s*$", value):
                continue
            geometry = subprocess.check_output(
                ["xwininfo", "-id", identifier, "-stats"], text=True
            )
            if "Map State: IsViewable" not in geometry:
                continue
            def field(name):
                return int(re.search(r"\b" + name + r":\s*(-?\d+)", geometry)[1])
            yield (field("Absolute upper-left X"), field("Absolute upper-left Y"),
                   field("Width"), field("Height"))
        except (subprocess.CalledProcessError, TypeError):
            continue


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pid", required=True, type=int)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--x", required=True, type=int)
    parser.add_argument("--y", required=True, type=int)
    parser.add_argument("--width", required=True, type=int)
    parser.add_argument("--height", required=True, type=int)
    args = parser.parse_args()
    owned_xvfb()
    if args.width < 100 or args.height < 100:
        raise RuntimeError("Editor crop is too small for the glyph regression")
    if not any(args.x >= x and args.y >= y and
               args.x + args.width <= x + width and
               args.y + args.height <= y + height
               for x, y, width, height in owner_bounds(args.pid)):
        raise RuntimeError("Editor crop is outside this Orion process's visible window")

    import gi
    gi.require_version("Gdk", "3.0")
    from gi.repository import Gdk
    display = Gdk.Display.open(os.environ["DISPLAY"])
    if display is None:
        raise RuntimeError("Xvfb root window is unavailable")
    root = display.get_default_screen().get_root_window()
    if args.x < 0 or args.y < 0 or args.x + args.width > root.get_width() or \
            args.y + args.height > root.get_height():
        raise RuntimeError("Editor crop is outside the isolated display")
    image = Gdk.pixbuf_get_from_window(
        root, args.x, args.y, args.width, args.height
    )
    if image is None:
        raise RuntimeError("Final desktop readback failed")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    image.savev(str(args.output), "png", [], [])
    pixels = image.get_pixels()
    stride, channels = image.get_rowstride(), image.get_n_channels()
    # Exclude the line-number gutter, borders and current-line left decoration.
    # White fixture identifiers remain bright under every tested theme. The
    # isolated desktop is dark, so transparency cannot supply false glyphs.
    rows = []
    for y in range(5, min(args.height - 5, 220)):
        count = 0
        for x in range(65, args.width - 5):
            offset = y * stride + x * channels
            if min(pixels[offset:offset + 3]) >= 100:
                count += 1
        rows.append(count)
    bands = []
    for y, count in enumerate(rows):
        if count >= 3:
            if bands and y <= bands[-1]["last"] + 3:
                bands[-1]["last"] = y
                bands[-1]["pixels"] += count
            else:
                bands.append({"first": y, "last": y, "pixels": count})
    bands = [band for band in bands if band["pixels"] >= 10]
    bright_pixels = sum(rows)
    report = {
        "success": bright_pixels >= 200 and len(bands) >= 4,
        "pid": args.pid,
        "source": "isolated-xvfb-final-root-composition",
        "crop": {"x": args.x, "y": args.y, "width": args.width,
                 "height": args.height},
        "brightGlyphPixels": bright_pixels,
        "textRows": len(bands),
        "bands": bands,
        "image": str(args.output),
    }
    args.output.with_suffix(".json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report))
    return 0 if report["success"] else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print(json.dumps({"success": False, "error": str(error)}), file=sys.stderr)
        sys.exit(2)
