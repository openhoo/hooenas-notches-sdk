#!/usr/bin/env python3
"""Validate tracked documentation links, legal resources and showcase/store assets."""

import binascii
import json
import re
import struct
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parent.parent


def gif_details(path):
    data = path.read_bytes()
    if data[:6] not in (b"GIF87a", b"GIF89a"):
        raise ValueError("Invalid GIF signature")
    width, height, packed = struct.unpack_from("<HHB", data, 6)
    position = 13 + (3 * (2 ** ((packed & 7) + 1)) if packed & 128 else 0)
    frames, duration, delay = 0, 0, 0
    loops = None

    def blocks(offset):
        chunks = []
        while data[offset]:
            size = data[offset]
            chunks.append(data[offset + 1 : offset + 1 + size])
            offset += size + 1
        return b"".join(chunks), offset + 1

    while data[position] != 0x3B:
        marker = data[position]
        if marker == 0x21:
            label = data[position + 1]
            payload, position = blocks(position + 2)
            if label == 0xF9:
                delay = int.from_bytes(payload[1:3], "little")
            if label == 0xFF and payload[:11] == b"NETSCAPE2.0" and payload[11] == 1:
                loops = int.from_bytes(payload[12:14], "little")
        elif marker == 0x2C:
            packed = data[position + 9]
            position += 10
            if packed & 128:
                position += 3 * 2 ** ((packed & 7) + 1)
            _, position = blocks(position + 1)
            frames += 1
            duration += delay * 10
            delay = 0
        else:
            raise ValueError(f"Unknown GIF block {marker}")
    return width, height, frames, duration, loops


def check_png(path):
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("Invalid PNG signature")
    width, height, depth, color, *_ = struct.unpack_from(">IIBBBBB", data, 16)
    if (width, height, depth, color) != (2880, 1800, 8, 2):
        raise ValueError("Store screenshots must be 2880×1800, opaque 8-bit RGB")
    position = 8
    while position < len(data):
        size = int.from_bytes(data[position : position + 4], "big")
        chunk = data[position + 4 : position + 8 + size]
        checksum = int.from_bytes(data[position + 8 + size : position + 12 + size], "big")
        if len(chunk) != size + 4 or binascii.crc32(chunk) != checksum:
            raise ValueError("Invalid PNG chunk checksum")
        if chunk[:4] == b"tRNS":
            raise ValueError("Store screenshots must not contain transparency")
        position += size + 12
        if chunk[:4] == b"IEND":
            if position != len(data):
                raise ValueError("Unexpected data after PNG IEND")
            return
    raise ValueError("Missing PNG IEND")


def main():
    failures = []
    files = (
        subprocess.check_output(["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=ROOT)
        .decode()
        .split("\0")
    )
    for filename in files:
        path = ROOT / filename
        if path.suffix not in {".md", ".html"} or not path.is_file():
            continue
        text = path.read_text()
        links = (
            re.findall(r"\[[^\]]*\]\(([^\s)]+)\)", text)
            if path.suffix == ".md"
            else re.findall(r'(?:href|src)=["\']([^"\']+)["\']', text)
        )
        for link in links:
            parsed = urlsplit(link)
            if parsed.scheme or parsed.netloc or not parsed.path or parsed.path.startswith("/"):
                continue
            target = path.parent / unquote(parsed.path)
            if not target.exists():
                failures.append(f"{filename}: missing local link {link}")
    for name in ["LICENSE", "THIRD_PARTY_NOTICES.md", "LICENSES/Cua-Spaces-Notch-LICENSE.txt"]:
        if not (ROOT / name).is_file():
            failures.append(f"Missing legal resource: {name}")
    for style in ["contour", "capsule", "glass"]:
        path = ROOT / f"docs/showcase/{style}.gif"
        try:
            width, height, frames, duration, loops = gif_details(path)
            if width != 840 or not 500 <= height <= 560 or (frames, duration, loops) != (100, 5000, 0):
                failures.append(
                    f"{path.name}: expected 840px wide, 100 frames, 5-second infinite loop; got {(width, height, frames, duration, loops)}"
                )
        except (OSError, ValueError, IndexError, struct.error) as error:
            failures.append(f"{path.name}: {error}")
    metadata = ROOT / "app-store/metadata.json"
    if metadata.exists():
        for filename in json.loads(metadata.read_text())["screenshots"]:
            try:
                check_png(metadata.parent / filename)
            except (OSError, ValueError, IndexError, struct.error) as error:
                failures.append(f"{filename}: {error}")
    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    print("Documentation links, legal resources and media checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
