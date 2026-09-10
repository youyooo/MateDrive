#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import struct
import zlib
from pathlib import Path


ACCEPTED_PORTRAIT_SIZES = {
    (1242, 2688),
    (1284, 2778),
}
EXPECTED_NAMES = {
    "01-dashboard.png",
    "02-activity.png",
    "03-features.png",
    "04-drive-detail.png",
    "05-charge-detail.png",
    "06-battery.png",
}
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def paeth_predictor(left: int, above: int, upper_left: int) -> int:
    estimate = left + above - upper_left
    left_distance = abs(estimate - left)
    above_distance = abs(estimate - above)
    upper_left_distance = abs(estimate - upper_left)
    if left_distance <= above_distance and left_distance <= upper_left_distance:
        return left
    if above_distance <= upper_left_distance:
        return above
    return upper_left


def png_size_and_visual_diversity(path: Path) -> tuple[tuple[int, int], int]:
    with path.open("rb") as handle:
        if handle.read(8) != PNG_SIGNATURE:
            raise ValueError("not a PNG")
        width = height = bit_depth = color_type = None
        compressed = bytearray()
        while True:
            length_bytes = handle.read(4)
            if len(length_bytes) != 4:
                raise ValueError("truncated PNG")
            length = struct.unpack(">I", length_bytes)[0]
            chunk_type = handle.read(4)
            data = handle.read(length)
            if len(data) != length or len(handle.read(4)) != 4:
                raise ValueError("truncated PNG chunk")
            if chunk_type == b"IHDR":
                if length != 13:
                    raise ValueError("invalid PNG IHDR")
                width, height, bit_depth, color_type, _, _, interlace = struct.unpack(
                    ">IIBBBBB", data
                )
                if interlace != 0:
                    raise ValueError("interlaced PNG screenshots are unsupported")
            elif chunk_type == b"IDAT":
                compressed.extend(data)
            elif chunk_type == b"IEND":
                break

    if width is None or height is None:
        raise ValueError("missing PNG IHDR")
    if bit_depth != 8 or color_type not in {2, 6}:
        raise ValueError("PNG screenshot must use 8-bit RGB or RGBA pixels")

    channels = 3 if color_type == 2 else 4
    row_length = width * channels
    decoded = zlib.decompress(compressed)
    expected_length = height * (row_length + 1)
    if len(decoded) != expected_length:
        raise ValueError("unexpected PNG raster length")

    previous = bytearray(row_length)
    colors: set[tuple[int, int, int]] = set()
    row_step = max(1, height // 128)
    column_step = max(1, width // 64)
    offset = 0
    for row_index in range(height):
        filter_type = decoded[offset]
        offset += 1
        filtered = decoded[offset : offset + row_length]
        offset += row_length
        current = bytearray(row_length)
        for index, value in enumerate(filtered):
            left = current[index - channels] if index >= channels else 0
            above = previous[index]
            upper_left = previous[index - channels] if index >= channels else 0
            if filter_type == 0:
                reconstructed = value
            elif filter_type == 1:
                reconstructed = value + left
            elif filter_type == 2:
                reconstructed = value + above
            elif filter_type == 3:
                reconstructed = value + ((left + above) // 2)
            elif filter_type == 4:
                reconstructed = value + paeth_predictor(left, above, upper_left)
            else:
                raise ValueError(f"unsupported PNG filter {filter_type}")
            current[index] = reconstructed & 0xFF

        if row_index % row_step == 0:
            for column in range(0, width, column_step):
                pixel = column * channels
                colors.add(tuple(current[pixel : pixel + 3]))
                if len(colors) >= 256:
                    return (width, height), len(colors)
        previous = current

    return (width, height), len(colors)


def screenshot_blockers(directory: Path) -> list[str]:
    blockers: list[str] = []
    if not directory.is_dir():
        return [f"screenshot directory does not exist: {directory}"]

    screenshots = sorted(directory.glob("*.png"))
    actual_names = {path.name for path in screenshots}
    missing_names = sorted(EXPECTED_NAMES - actual_names)
    extra_names = sorted(actual_names - EXPECTED_NAMES)
    if missing_names:
        blockers.append(f"missing required screenshots: {', '.join(missing_names)}")
    if extra_names:
        blockers.append(f"unexpected screenshots: {', '.join(extra_names)}")

    digests: dict[str, str] = {}
    for path in screenshots:
        try:
            size, visual_diversity = png_size_and_visual_diversity(path)
        except (OSError, ValueError, struct.error) as error:
            blockers.append(f"{path.name} is not a valid PNG: {error}")
            continue
        if size not in ACCEPTED_PORTRAIT_SIZES:
            blockers.append(
                f"{path.name} is {size[0]}x{size[1]}, expected an accepted 6.5-inch portrait size"
            )
        if visual_diversity < 32:
            blockers.append(f"{path.name} has too little visual variation and may be blank")

        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest in digests:
            blockers.append(f"{path.name} duplicates {digests[digest]}")
        else:
            digests[digest] = path.name

    return blockers


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "directory",
        nargs="?",
        default="build/app-store-screenshots/zh-Hans",
        type=Path,
    )
    args = parser.parse_args()

    blockers = screenshot_blockers(args.directory)
    print(f"app-store screenshot blockers: {len(blockers)}")
    for blocker in blockers:
        print(f"- {blocker}")
    return 1 if blockers else 0


if __name__ == "__main__":
    raise SystemExit(main())
