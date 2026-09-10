#!/usr/bin/env python3
from __future__ import annotations

import struct
import tempfile
import unittest
import zlib
from pathlib import Path

from validate_app_store_screenshots import EXPECTED_NAMES, screenshot_blockers


def write_png(
    path: Path,
    width: int,
    height: int,
    seed: int,
    *,
    varied: bool = True,
) -> None:
    def chunk(kind: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + kind
            + data
            + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
        )

    raw = bytearray()
    for row_index in range(height):
        raw.append(0)
        for column_index in range(width):
            if varied:
                raw.extend(
                    (
                        (column_index * 7 + row_index * 3 + seed * 11) & 0xFF,
                        (column_index * 2 + row_index * 13 + seed * 17) & 0xFF,
                        (column_index * 19 + row_index * 5 + seed * 23) & 0xFF,
                    )
                )
            else:
                raw.extend((seed, seed, seed))
    contents = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(raw), level=1))
        + chunk(b"IEND", b"")
    )
    path.write_bytes(contents)


class AppStoreScreenshotValidationTests(unittest.TestCase):
    def test_accepts_complete_unique_screenshot_set(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for index, name in enumerate(sorted(EXPECTED_NAMES), start=1):
                write_png(root / name, 1242, 2688, index)
            self.assertEqual(screenshot_blockers(root), [])

    def test_rejects_missing_wrong_size_small_and_duplicate_screenshots(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            names = sorted(EXPECTED_NAMES)
            write_png(root / names[0], 400, 800, 1)
            (root / names[1]).write_bytes((root / names[0]).read_bytes())
            write_png(root / names[2], 1242, 2688, 3, varied=False)
            blockers = screenshot_blockers(root)
            self.assertTrue(any("missing required screenshots" in item for item in blockers))
            self.assertTrue(any("expected an accepted" in item for item in blockers))
            self.assertTrue(any("too little visual variation" in item for item in blockers))
            self.assertTrue(any("duplicates" in item for item in blockers))


if __name__ == "__main__":
    unittest.main()
