#!/usr/bin/env python3
"""Reject legacy branding, removed source chains, and vehicle artwork."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


EXCLUDED_PARTS = {
    ".git",
    ".build",
    ".superpowers",
    "DerivedData",
    "build",
    "xcuserdata",
    "__pycache__",
}
EXCLUDED_FILES = {
    "audit_independent_release.py",
    "test_audit_independent_release.py",
}
TEXT_SUFFIXES = {
    ".entitlements",
    ".html",
    ".json",
    ".md",
    ".plist",
    ".py",
    ".sh",
    ".swift",
    ".xcprivacy",
    ".xcstrings",
    ".xcscheme",
    ".yml",
}


def forbidden_terms() -> list[str]:
    legacy_brand = "Mate" + "Droid"
    return [
        legacy_brand.casefold(),
        ("vide/" + legacy_brand).casefold(),
        "android",
        "安卓",
        "trip" + "aggregator",
        "trip" + "detector",
        "short" + "entryfilter",
        "charge" + "statscalculator",
        "car" + "imageresolver",
        "vehicle" + "imageresolver",
        "vehicle" + "imagecatalog",
    ]


def candidate_files(root: Path):
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        if path.name in EXCLUDED_FILES or any(part in EXCLUDED_PARTS for part in path.parts):
            continue
        if path.suffix.casefold() in TEXT_SUFFIXES or path.name in {"LICENSE", "NOTICE", "Makefile"}:
            yield path


def audit(root: Path) -> list[str]:
    findings: set[str] = set()
    terms = forbidden_terms()

    for path in candidate_files(root):
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except UnicodeDecodeError:
            continue
        for line_number, line in enumerate(lines, start=1):
            folded = line.casefold()
            if any(term in folded for term in terms):
                findings.add(f"{path.relative_to(root)}:{line_number}")

    car_images = root / "MateDriveApp" / "Resources" / "CarImages"
    if car_images.exists() and any(path.is_file() for path in car_images.rglob("*")):
        findings.add("MateDriveApp/Resources/CarImages:1")

    for catalog_path in [
        root / "MateDriveApp" / "Resources" / "VehicleImageCatalog.json",
        root / "scripts" / "data" / "vehicle_image_legacy_inventory.json",
    ]:
        if catalog_path.exists():
            findings.add(f"{catalog_path.relative_to(root)}:1")

    for catalog_path in [
        root / "MateDriveApp" / "Resources" / "Localizable.xcstrings",
        root / "MateDriveApp" / "Resources" / "AppShortcuts.xcstrings",
        root / "MateDriveWidget" / "Localizable.xcstrings",
    ]:
        if not catalog_path.exists():
            continue
        try:
            payload = json.loads(catalog_path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            continue
        serialized = json.dumps(payload.get("strings", {}), ensure_ascii=False)
        for locale in ('"de"', '"es"', '"it"', '"ca"'):
            if locale in serialized:
                findings.add(f"{catalog_path.relative_to(root)}:1")
                break

    return sorted(findings)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path.cwd())
    args = parser.parse_args()
    findings = audit(args.root.resolve())
    for finding in findings:
        print(finding)
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
