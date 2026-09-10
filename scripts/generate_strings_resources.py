#!/usr/bin/env python3
import argparse
import json
import plistlib
import sys
from pathlib import Path


RESOURCE_ROOT = Path("MateDriveApp/Resources")
OUTPUT_ROOT = RESOURCE_ROOT / "CompiledLocalizations"
CATALOGS = {
    "Localizable": RESOURCE_ROOT / "Localizable.xcstrings",
    "InfoPlist": RESOURCE_ROOT / "InfoPlist.xcstrings",
    "AppShortcuts": RESOURCE_ROOT / "AppShortcuts.xcstrings",
}
SUPPORTED_LOCALES = ("en", "zh-Hans", "zh-Hant")


def localized_value(entry: dict, locale: str) -> str | None:
    localization = entry.get("localizations", {}).get(locale, {})
    string_unit = localization.get("stringUnit")
    if string_unit:
        return string_unit.get("value")
    string_set = localization.get("stringSet")
    if string_set:
        values = string_set.get("values", [])
        return values[0] if values else None
    return None


def expected_resources() -> dict[Path, bytes]:
    resources: dict[Path, bytes] = {}
    for table, path in CATALOGS.items():
        catalog = json.loads(path.read_text())
        for locale in SUPPORTED_LOCALES:
            values = {}
            for key, entry in catalog.get("strings", {}).items():
                value = localized_value(entry, locale)
                if value:
                    values[key] = value
            destination = OUTPUT_ROOT / f"{locale}.lproj" / f"{table}.strings"
            resources[destination] = plistlib.dumps(values, fmt=plistlib.FMT_XML, sort_keys=True)
    return resources


def check(resources: dict[Path, bytes]) -> int:
    errors = []
    expected_paths = set(resources)
    existing_paths = set(OUTPUT_ROOT.glob("*.lproj/*.strings")) if OUTPUT_ROOT.exists() else set()
    for path, content in resources.items():
        if not path.exists():
            errors.append(f"missing {path}")
        elif path.read_bytes() != content:
            errors.append(f"outdated {path}")
    for path in sorted(existing_paths - expected_paths):
        errors.append(f"unexpected {path}")
    if errors:
        print("compiled localization resources are out of date:")
        for error in errors:
            print(f"- {error}")
        return 1
    print(f"compiled localization resources: {len(resources)} files current")
    return 0


def write(resources: dict[Path, bytes]) -> int:
    for path, content in resources.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
    for path in OUTPUT_ROOT.glob("*.lproj/*.strings"):
        if path not in resources:
            path.unlink()
    print(f"generated {len(resources)} compiled localization resources")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    resources = expected_resources()
    return check(resources) if args.check else write(resources)


if __name__ == "__main__":
    sys.exit(main())
