#!/usr/bin/env python3
import argparse
import json
import plistlib
import re
import struct
import sys
from pathlib import Path


SUBMISSION_PATH = Path("docs/release/app-store-submission.md")
REQUIRED_SECTIONS = [
    "## App Name",
    "## Submission Status",
    "## Subtitle",
    "## Description",
    "## Keywords",
    "## Promotional Text",
    "## Support URL",
    "## Marketing URL",
    "## Review Notes",
    "## Pre-Submission Verification",
    "## Demo Account And Server",
    "## Privacy Summary",
    "## App Privacy Questionnaire Draft",
    "## Export Compliance",
    "## Screenshot Checklist",
]
FORBIDDEN_READY_MARKERS = [
    "Not ready for App Store submission yet.",
    "TBD",
]
SUPPORT_PLACEHOLDER_MARKERS = [
    "Before publishing this page",
    "Before publishing this policy",
]
PRIVATE_ENDPOINT_PATTERN = re.compile(
    r"(http://|localhost|127\.0\.0\.1|\b10\.\d{1,3}\.\d{1,3}\.\d{1,3}\b|"
    r"\b172\.(1[6-9]|2[0-9]|3[0-1])\.\d{1,3}\.\d{1,3}\b|"
    r"\b192\.168\.\d{1,3}\.\d{1,3}\b)"
)


def section_body(text: str, section: str) -> str:
    start = text.find(section)
    if start == -1:
        return ""
    rest = text[start + len(section):]
    next_section = rest.find("\n## ")
    if next_section == -1:
        return rest.strip()
    return rest[:next_section].strip()


def png_metadata(path: Path) -> tuple[int, int, bool]:
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise ValueError("not a PNG")
    width, height, _, color_type = struct.unpack(">IIBB", data[16:26])
    has_alpha = color_type in (4, 6) or b"tRNS" in data
    return width, height, has_alpha


def technical_blockers() -> list[str]:
    blockers = []
    info = plistlib.loads(Path("MateDroidIOS/Info.plist").read_bytes())
    privacy = plistlib.loads(Path("MateDroidIOS/PrivacyInfo.xcprivacy").read_bytes())
    project = Path("project.yml").read_text(encoding="utf-8")
    support_page = Path("docs/support/index.html")
    privacy_page = Path("docs/support/privacy.html")

    if info.get("CFBundleDisplayName") != "MateDrive":
        blockers.append("CFBundleDisplayName must be MateDrive")
    if info.get("ITSAppUsesNonExemptEncryption") is not False:
        blockers.append("ITSAppUsesNonExemptEncryption must be false")
    launch = info.get("UILaunchScreen", {})
    if launch.get("UIColorName") != "LaunchBackground" or launch.get("UIImageName") != "LaunchWordmark":
        blockers.append("UILaunchScreen must use the packaged MateDrive launch assets")
    if not re.fullmatch(r"\d+(\.\d+){0,2}", str(info.get("CFBundleShortVersionString", ""))):
        blockers.append("CFBundleShortVersionString must be numeric")
    if privacy.get("NSPrivacyTracking") is not False:
        blockers.append("privacy manifest must declare tracking false")
    reasons = {
        item.get("NSPrivacyAccessedAPIType"): item.get("NSPrivacyAccessedAPITypeReasons", [])
        for item in privacy.get("NSPrivacyAccessedAPITypes", [])
    }
    if "CA92.1" not in reasons.get("NSPrivacyAccessedAPICategoryUserDefaults", []):
        blockers.append("privacy manifest must declare UserDefaults reason CA92.1")
    if project.count('TARGETED_DEVICE_FAMILY: "1"') < 2:
        blockers.append("app and widget must explicitly target iPhone")
    if not support_page.exists() or "MateDrive Support" not in support_page.read_text(encoding="utf-8"):
        blockers.append("publishable MateDrive support page artifact is missing")
    if not privacy_page.exists() or "MateDrive Privacy Policy" not in privacy_page.read_text(encoding="utf-8"):
        blockers.append("publishable MateDrive privacy policy artifact is missing")

    icon_root = Path("MateDroidIOS/Resources/Assets.xcassets/AppIcon.appiconset")
    contents = json.loads((icon_root / "Contents.json").read_text(encoding="utf-8"))
    for image in contents.get("images", []):
        filename = image.get("filename")
        size = image.get("size")
        scale = image.get("scale")
        if not filename or not size or not scale:
            blockers.append(f"incomplete app icon slot: {image}")
            continue
        points = float(size.split("x")[0])
        multiplier = int(scale.removesuffix("x"))
        expected = int(round(points * multiplier))
        try:
            width, height, has_alpha = png_metadata(icon_root / filename)
        except (OSError, ValueError) as error:
            blockers.append(f"invalid app icon {filename}: {error}")
            continue
        if (width, height) != (expected, expected):
            blockers.append(f"app icon {filename} is {width}x{height}, expected {expected}x{expected}")
        if has_alpha:
            blockers.append(f"app icon {filename} contains an alpha channel")
    launch_root = Path("MateDroidIOS/Resources/Assets.xcassets/LaunchWordmark.imageset")
    for filename, expected_width, expected_height in [
        ("LaunchMark.png", 220, 64),
        ("LaunchMark@2x.png", 440, 128),
        ("LaunchMark@3x.png", 660, 192),
    ]:
        try:
            width, height, _ = png_metadata(launch_root / filename)
        except (OSError, ValueError) as error:
            blockers.append(f"invalid launch image {filename}: {error}")
            continue
        if (width, height) != (expected_width, expected_height):
            blockers.append(
                f"launch image {filename} is {width}x{height}, expected {expected_width}x{expected_height}"
            )
    return blockers


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--technical-only", action="store_true")
    args = parser.parse_args()
    text = SUBMISSION_PATH.read_text(encoding="utf-8")
    technical = technical_blockers()
    blockers = []

    for section in REQUIRED_SECTIONS:
        if section not in text:
            blockers.append(f"missing required section: {section}")

    for marker in FORBIDDEN_READY_MARKERS:
        if marker in text:
            blockers.append(f"replace/remove placeholder before submission: {marker}")
    for marker in SUPPORT_PLACEHOLDER_MARKERS:
        for path in [Path("docs/support/index.html"), Path("docs/support/privacy.html")]:
            if marker in path.read_text(encoding="utf-8"):
                blockers.append(f"replace support contact placeholder in {path}")

    support = section_body(text, "## Support URL")
    if not re.search(r"https://[^\s]+", support):
        blockers.append("support URL must be a reachable https:// URL")

    demo = section_body(text, "## Demo Account And Server")
    if "TeslaMate API base URL:" not in demo:
        blockers.append("demo server section must include TeslaMate API base URL")
    if "API token:" not in demo and "Basic Auth username:" not in demo and "Authentication:" not in demo:
        blockers.append("demo server section must include reviewer authentication guidance")

    if PRIVATE_ENDPOINT_PATTERN.search(text):
        blockers.append("submission copy must not contain local or private network URLs")
    if re.search(r"\bsk-[A-Za-z0-9_-]+", text):
        blockers.append("submission copy must not contain API-looking secrets")
    if "MateDroid" in text:
        blockers.append("submission copy must not contain legacy MateDroid branding")

    print(f"app-store technical blockers: {len(technical)}")
    for blocker in technical:
        print(f"- {blocker}")
    if args.technical_only:
        return 1 if technical else 0

    blockers = technical + blockers
    print(f"app-store submission blockers: {len(blockers)}")
    for blocker in blockers:
        print(f"- {blocker}")

    return 1 if blockers else 0


if __name__ == "__main__":
    sys.exit(main())
