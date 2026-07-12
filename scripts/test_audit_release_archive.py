#!/usr/bin/env python3
import plistlib
import tempfile
import unittest
from pathlib import Path

from audit_release_archive import audit_archive


class ReleaseArchiveAuditTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.archive = Path(self.temporary_directory.name) / "MateDrive.xcarchive"
        self.app = self.archive / "Products/Applications/MateDrive.app"
        self.widget = self.app / "PlugIns/MateDriveWidget.appex"
        self.widget.mkdir(parents=True)
        (self.app / "zh-Hans.lproj").mkdir()

        self.write_plist(
            self.archive / "Info.plist",
            {
                "Name": "MateDrive",
                "ApplicationProperties": {
                    "ApplicationPath": "Applications/MateDrive.app",
                    "CFBundleIdentifier": "com.matedrive.ios",
                    "CFBundleShortVersionString": "1.0",
                    "CFBundleVersion": "1",
                },
            },
        )
        self.write_plist(
            self.app / "Info.plist",
            {
                "CFBundleIdentifier": "com.matedrive.ios",
                "CFBundleDisplayName": "MateDrive",
                "CFBundleExecutable": "MateDrive",
                "CFBundleShortVersionString": "1.0",
                "CFBundleVersion": "1",
            },
        )
        self.write_plist(
            self.widget / "Info.plist",
            {
                "CFBundleIdentifier": "com.matedrive.ios.widget",
                "CFBundleExecutable": "MateDriveWidget",
                "CFBundleShortVersionString": "1.0",
                "CFBundleVersion": "1",
            },
        )
        for path in [
            self.app / "MateDrive",
            self.app / "PrivacyInfo.xcprivacy",
            self.app / "zh-Hans.lproj/Localizable.strings",
            self.widget / "MateDriveWidget",
            self.widget / "PrivacyInfo.xcprivacy",
        ]:
            path.touch()

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def write_plist(self, path: Path, value: dict) -> None:
        path.write_bytes(plistlib.dumps(value))

    def test_accepts_complete_archive(self) -> None:
        self.assertEqual(audit_archive(self.archive), [])

    def test_reports_missing_widget_privacy_manifest(self) -> None:
        (self.widget / "PrivacyInfo.xcprivacy").unlink()
        blockers = audit_archive(self.archive)
        self.assertTrue(any("MateDriveWidget.appex/PrivacyInfo.xcprivacy" in item for item in blockers))

    def test_reports_version_mismatch(self) -> None:
        widget_info = plistlib.loads((self.widget / "Info.plist").read_bytes())
        widget_info["CFBundleVersion"] = "2"
        self.write_plist(self.widget / "Info.plist", widget_info)
        self.assertIn("app and widget build versions must match", audit_archive(self.archive))


if __name__ == "__main__":
    unittest.main()
