#!/usr/bin/env python3
import argparse
import plistlib
import sys
from pathlib import Path


APP_BUNDLE_ID = "com.matedrive.ios"
WIDGET_BUNDLE_ID = "com.matedrive.ios.widget"


def load_plist(path: Path, blockers: list[str]) -> dict:
    try:
        return plistlib.loads(path.read_bytes())
    except (OSError, plistlib.InvalidFileException) as error:
        blockers.append(f"cannot read plist {path}: {error}")
        return {}


def audit_archive(archive: Path) -> list[str]:
    blockers: list[str] = []
    app = archive / "Products/Applications/MateDrive.app"
    widget = app / "PlugIns/MateDriveWidget.appex"

    archive_info = load_plist(archive / "Info.plist", blockers)
    app_info = load_plist(app / "Info.plist", blockers)
    widget_info = load_plist(widget / "Info.plist", blockers)

    properties = archive_info.get("ApplicationProperties", {})
    if properties.get("ApplicationPath") != "Applications/MateDrive.app":
        blockers.append("archive application path must be Applications/MateDrive.app")
    if properties.get("CFBundleIdentifier") != APP_BUNDLE_ID:
        blockers.append(f"archive bundle identifier must be {APP_BUNDLE_ID}")
    if archive_info.get("Name") != "MateDrive":
        blockers.append("archive name must be MateDrive")

    if app_info.get("CFBundleIdentifier") != APP_BUNDLE_ID:
        blockers.append(f"app bundle identifier must be {APP_BUNDLE_ID}")
    if app_info.get("CFBundleDisplayName") != "MateDrive":
        blockers.append("app display name must be MateDrive")
    if app_info.get("CFBundleExecutable") != "MateDrive":
        blockers.append("app executable must be MateDrive")
    if app_info.get("CFBundleShortVersionString") != properties.get("CFBundleShortVersionString"):
        blockers.append("app and archive marketing versions must match")
    if app_info.get("CFBundleVersion") != properties.get("CFBundleVersion"):
        blockers.append("app and archive build versions must match")

    if widget_info.get("CFBundleIdentifier") != WIDGET_BUNDLE_ID:
        blockers.append(f"widget bundle identifier must be {WIDGET_BUNDLE_ID}")
    if widget_info.get("CFBundleExecutable") != "MateDriveWidget":
        blockers.append("widget executable must be MateDriveWidget")
    if widget_info.get("CFBundleShortVersionString") != app_info.get("CFBundleShortVersionString"):
        blockers.append("app and widget marketing versions must match")
    if widget_info.get("CFBundleVersion") != app_info.get("CFBundleVersion"):
        blockers.append("app and widget build versions must match")

    required_files = [
        app / "MateDrive",
        app / "PrivacyInfo.xcprivacy",
        app / "zh-Hans.lproj/Localizable.strings",
        widget / "MateDriveWidget",
        widget / "PrivacyInfo.xcprivacy",
    ]
    for path in required_files:
        if not path.is_file():
            blockers.append(f"missing archive resource: {path.relative_to(archive)}")

    return blockers


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", nargs="?", type=Path, default=Path("build/MateDrive.xcarchive"))
    args = parser.parse_args()
    blockers = audit_archive(args.archive)
    print(f"release archive blockers: {len(blockers)}")
    for blocker in blockers:
        print(f"- {blocker}")
    return 1 if blockers else 0


if __name__ == "__main__":
    sys.exit(main())
