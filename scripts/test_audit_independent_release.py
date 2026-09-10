#!/usr/bin/env python3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("audit_independent_release.py")


class IndependentReleaseAuditTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def write(self, relative_path: str, content: str) -> None:
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

    def test_accepts_independent_matedrive_release(self) -> None:
        self.write("MateDriveApp/App/MateDriveApp.swift", "struct MateDriveApp {}\n")
        self.write("LICENSE", "MIT License\n")

        result = self.run_audit()

        self.assertEqual(result.returncode, 0, msg=result.stdout)
        self.assertEqual(result.stdout, "")

    def test_rejects_legacy_brand_and_removed_source_chain(self) -> None:
        old_brand = "Mate" + "Droid"
        old_symbol = "Trip" + "Aggregator"
        self.write("README.md", f"Based on {old_brand}\n")
        self.write("MateDriveApp/Core/Legacy.swift", f"struct {old_symbol} {{}}\n")
        self.write("docs/release-notes.md", "Ported from Android\n")

        result = self.run_audit()

        self.assertEqual(result.returncode, 1)
        self.assertEqual(
            result.stdout.splitlines(),
            [
                "MateDriveApp/Core/Legacy.swift:1",
                "README.md:1",
                "docs/release-notes.md:1",
            ],
        )

    def test_rejects_vehicle_artwork_and_removed_locales(self) -> None:
        self.write("MateDriveApp/Resources/CarImages/vehicle.png", "fixture")
        self.write(
            "MateDriveApp/Resources/Localizable.xcstrings",
            '{"strings":{"Example":{"localizations":{"de":{"stringUnit":{"value":"Beispiel"}}}}}}',
        )

        result = self.run_audit()

        self.assertEqual(result.returncode, 1)
        self.assertEqual(
            result.stdout.splitlines(),
            [
                "MateDriveApp/Resources/CarImages:1",
                "MateDriveApp/Resources/Localizable.xcstrings:1",
            ],
        )


if __name__ == "__main__":
    unittest.main()
