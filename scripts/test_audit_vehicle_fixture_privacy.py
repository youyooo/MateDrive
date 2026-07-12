#!/usr/bin/env python3
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib
from pathlib import Path


SCRIPT = Path(__file__).with_name("audit_vehicle_fixture_privacy.py")


def png_text_chunk(keyword: str, text: str) -> bytes:
    chunk_data = f"{keyword}\0{text}".encode("latin-1")
    chunk_type = b"tEXt"
    return struct.pack(">I", len(chunk_data)) + chunk_type + chunk_data + struct.pack(
        ">I", zlib.crc32(chunk_type + chunk_data) & 0xFFFFFFFF
    )


def png_itxt_chunk(text: str) -> bytes:
    chunk_type = b"iTXt"
    chunk_data = b"Comment\0\1\0en\0\0" + zlib.compress(text.encode("utf-8"))
    return struct.pack(">I", len(chunk_data)) + chunk_type + chunk_data + struct.pack(
        ">I", zlib.crc32(chunk_type + chunk_data) & 0xFFFFFFFF
    )


def png_chunk(chunk_type: bytes, chunk_data: bytes) -> bytes:
    return struct.pack(">I", len(chunk_data)) + chunk_type + chunk_data + struct.pack(
        ">I", zlib.crc32(chunk_type + chunk_data) & 0xFFFFFFFF
    )


def minimal_png(metadata: str, metadata_chunk=png_text_chunk) -> bytes:
    signature = b"\x89PNG\r\n\x1a\n"
    ihdr_data = struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0)
    ihdr_type = b"IHDR"
    ihdr = struct.pack(">I", len(ihdr_data)) + ihdr_type + ihdr_data + struct.pack(
        ">I", zlib.crc32(ihdr_type + ihdr_data) & 0xFFFFFFFF
    )
    iend_type = b"IEND"
    iend = struct.pack(">I", 0) + iend_type + struct.pack(">I", zlib.crc32(iend_type) & 0xFFFFFFFF)
    return signature + ihdr + metadata_chunk("Comment", metadata) + iend


def minimal_png_with_itxt(metadata: str) -> bytes:
    signature = b"\x89PNG\r\n\x1a\n"
    ihdr_data = struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0)
    ihdr_type = b"IHDR"
    ihdr = struct.pack(">I", len(ihdr_data)) + ihdr_type + ihdr_data + struct.pack(
        ">I", zlib.crc32(ihdr_type + ihdr_data) & 0xFFFFFFFF
    )
    iend_type = b"IEND"
    iend = struct.pack(">I", 0) + iend_type + struct.pack(">I", zlib.crc32(iend_type) & 0xFFFFFFFF)
    return signature + ihdr + png_itxt_chunk(metadata) + iend


def minimal_png_with_chunks(chunks: list[bytes]) -> bytes:
    signature = b"\x89PNG\r\n\x1a\n"
    ihdr_data = struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0)
    ihdr_type = b"IHDR"
    ihdr = struct.pack(">I", len(ihdr_data)) + ihdr_type + ihdr_data + struct.pack(
        ">I", zlib.crc32(ihdr_type + ihdr_data) & 0xFFFFFFFF
    )
    iend_type = b"IEND"
    iend = struct.pack(">I", 0) + iend_type + struct.pack(">I", zlib.crc32(iend_type) & 0xFFFFFFFF)
    return signature + ihdr + b"".join(chunks) + iend


class VehicleFixturePrivacyAuditTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)

        self.tesla_vin = "5YJ" + "3E1EA7KF000001"
        self.credential_url = "https://api-reader" + ":correct-horse-battery-staple@teslamate.internal/api"
        self.coordinates = "37.3317" + ", " + "-122.0301"
        self.synthetic_vin = "TSTMODEL3N0000000"

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def write_text(self, relative_path: str, content: str) -> None:
        path = self.root / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    def run_audit(self) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--root", str(self.root)],
            capture_output=True,
            text=True,
            check=False,
        )

    def test_rejects_private_vehicle_fixture_values_without_echoing_them(self) -> None:
        self.write_text("Sources/Vehicle.swift", f'let vin = "{self.tesla_vin}"\n')
        self.write_text("Tests/VehicleFixtureTests.swift", f'let url = "{self.credential_url}"\n')
        json_fixture = (
            '{"coordinates": [' + "37.3317" + ', ' + "-122.0301" + ']}\n'
        )
        self.write_text("Fixtures/vehicle.json", json_fixture)
        self.write_text("docs/fixture-notes.md", f"Recorded coordinates: {self.coordinates}\n")
        png_path = self.root / "Fixtures/vehicle.png"
        png_path.parent.mkdir(parents=True, exist_ok=True)
        png_path.write_bytes(minimal_png(self.credential_url))

        result = self.run_audit()

        self.assertEqual(
            result.returncode,
            1,
            msg=result.stderr or result.stdout,
        )
        self.assertEqual(
            result.stdout.splitlines(),
            [
                "Fixtures/vehicle.json:1",
                "Fixtures/vehicle.png:1",
                "Sources/Vehicle.swift:1",
                "Tests/VehicleFixtureTests.swift:1",
                "docs/fixture-notes.md:1",
            ],
        )
        self.assertEqual(result.stderr, "")
        for secret in [self.tesla_vin, self.credential_url, self.coordinates]:
            self.assertNotIn(secret, result.stdout)

    def test_accepts_synthetic_fixture_values(self) -> None:
        self.write_text(
            "Sources/Vehicle.swift",
            f'let vin = "{self.synthetic_vin}"\nlet url = "https://example.test/api"\n',
        )
        self.write_text("docs/fixture-notes.md", "No private location data is present.\n")

        result = self.run_audit()

        self.assertEqual(result.returncode, 0, msg=result.stderr or result.stdout)
        self.assertEqual(result.stdout, "")
        self.assertEqual(result.stderr, "")

    def test_rejects_private_data_in_compressed_png_itxt_metadata(self) -> None:
        png_path = self.root / "Fixtures/vehicle.png"
        png_path.parent.mkdir(parents=True, exist_ok=True)
        png_path.write_bytes(minimal_png_with_itxt(self.credential_url))

        result = self.run_audit()

        self.assertEqual(result.returncode, 1, msg=result.stderr or result.stdout)
        self.assertEqual(result.stdout.splitlines(), ["Fixtures/vehicle.png:1"])
        self.assertNotIn(self.credential_url, result.stdout)

    def test_rejects_credentialed_urls_on_reserved_hosts(self) -> None:
        reserved_host_url = "https://api-reader" + ":reserved-secret@example.test/api"
        test_net_url = "http://api-reader" + ":test-net-secret@192.0.2.10/api"
        self.write_text("Fixtures/reserved-hosts.md", f"{reserved_host_url}\n{test_net_url}\n")

        result = self.run_audit()

        self.assertEqual(result.returncode, 1, msg=result.stderr or result.stdout)
        self.assertEqual(
            result.stdout.splitlines(),
            ["Fixtures/reserved-hosts.md:1", "Fixtures/reserved-hosts.md:2"],
        )
        self.assertNotIn(reserved_host_url, result.stdout)
        self.assertNotIn(test_net_url, result.stdout)

    def test_rejects_coordinate_fields_and_arrays_in_any_order_or_format(self) -> None:
        latitude_value = "37." + "3317"
        longitude_value = "-122." + "0301"
        self.write_text(
            "Fixtures/coordinates.json",
            '{"latitude": ' + latitude_value + ', "longitude": ' + longitude_value + '}\n'
            '{"longitude" = ' + longitude_value + '; "latitude" = ' + latitude_value + '}\n',
        )
        self.write_text(
            "Fixtures/coordinates.md",
            "coordinates [" + latitude_value + "; " + longitude_value + "]\n"
            "gps = [" + longitude_value + ", " + latitude_value + "]\n",
        )

        result = self.run_audit()

        self.assertEqual(result.returncode, 1, msg=result.stderr or result.stdout)
        self.assertEqual(
            result.stdout.splitlines(),
            [
                "Fixtures/coordinates.json:1",
                "Fixtures/coordinates.json:2",
                "Fixtures/coordinates.md:1",
                "Fixtures/coordinates.md:2",
            ],
        )

    def test_ignores_unrelated_numeric_source_arrays(self) -> None:
        self.write_text(
            "Sources/Math.swift",
            "let bounds = [37.3317, -122.0301]\nlet samples = [1.0, 2.0]\n",
        )

        result = self.run_audit()

        self.assertEqual(result.returncode, 0, msg=result.stderr or result.stdout)
        self.assertEqual(result.stdout, "")

    def test_rejects_multiline_json_and_swift_coordinate_fields_at_first_field_line(self) -> None:
        latitude_value = "37." + "3317"
        longitude_value = "-122." + "0301"
        self.write_text(
            "Fixtures/multiline.json",
            "{\n  \"latitude\": " + latitude_value + ",\n  \"longitude\": " + longitude_value + "\n}\n",
        )
        self.write_text(
            "Sources/Vehicle.swift",
            "let latitude = " + latitude_value + "\nlet longitude = " + longitude_value + "\n",
        )
        self.write_text(
            "Tests/VehicleFixtureTests.swift",
            "let longitude = " + longitude_value + "\nlet latitude = " + latitude_value + "\n",
        )

        result = self.run_audit()

        self.assertEqual(result.returncode, 1, msg=result.stderr or result.stdout)
        self.assertEqual(
            result.stdout.splitlines(),
            [
                "Fixtures/multiline.json:2",
                "Sources/Vehicle.swift:1",
                "Tests/VehicleFixtureTests.swift:1",
            ],
        )

    def test_rejects_multiline_swift_initializer_label_fields(self) -> None:
        latitude_value = "37." + "3317"
        longitude_value = "-122." + "0301"
        self.write_text(
            "Sources/VehicleInitializer.swift",
            "let vehicle = Vehicle(\n"
            "    latitude: " + latitude_value + ",\n"
            "    longitude: " + longitude_value + "\n"
            ")\n",
        )
        self.write_text(
            "Tests/VehicleInitializerTests.swift",
            "let fixture = Vehicle(\n"
            "    longitude: " + longitude_value + ",\n"
            "    latitude: " + latitude_value + "\n"
            ")\n",
        )

        result = self.run_audit()

        self.assertEqual(result.returncode, 1, msg=result.stderr or result.stdout)
        self.assertEqual(
            result.stdout.splitlines(),
            [
                "Sources/VehicleInitializer.swift:2",
                "Tests/VehicleInitializerTests.swift:2",
            ],
        )

    def test_continues_after_malformed_png_metadata_chunk(self) -> None:
        malformed_ztxt = png_chunk(b"zTXt", b"Comment\0\0not-zlib")
        sensitive_text = png_text_chunk("Comment", self.credential_url)
        png_path = self.root / "Fixtures/malformed-then-sensitive.png"
        png_path.parent.mkdir(parents=True, exist_ok=True)
        png_path.write_bytes(minimal_png_with_chunks([malformed_ztxt, sensitive_text]))

        result = self.run_audit()

        self.assertEqual(result.returncode, 1, msg=result.stderr or result.stdout)
        self.assertEqual(result.stdout.splitlines(), ["Fixtures/malformed-then-sensitive.png:1"])
        self.assertNotIn(self.credential_url, result.stdout)

    def test_excludes_build_superpowers_and_private_integration_files(self) -> None:
        self.write_text(".superpowers/fixture.json", f'{{"vin": "{self.tesla_vin}"}}\n')
        self.write_text(".build/DerivedData/fixture.swift", f'let vin = "{self.tesla_vin}"\n')
        self.write_text("build/output.md", f"{self.credential_url}\n")
        self.write_text(".matedrive-integration.env", f"MATEDRIVE_VIN={self.tesla_vin}\n")

        result = self.run_audit()

        self.assertEqual(result.returncode, 0, msg=result.stderr or result.stdout)
        self.assertEqual(result.stdout, "")
        self.assertEqual(result.stderr, "")


if __name__ == "__main__":
    unittest.main()
