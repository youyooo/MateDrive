#!/usr/bin/env python3
import json
import re
import subprocess
import sys
from pathlib import Path


LOCALIZATION_PATH = Path("MateDriveApp/Resources/Localizable.xcstrings")
APP_SHORTCUTS_LOCALIZATION_PATH = Path("MateDriveApp/Resources/AppShortcuts.xcstrings")
SWIFT_SOURCE_ROOTS = [Path("MateDriveApp"), Path("MateDriveWidget")]
CHINESE_LOCALES = ("zh-Hans", "zh-Hant")
SUPPORTED_LOCALES = ("en", "zh-Hans", "zh-Hant")

REQUIRED_CHINESE_TRANSLATIONS = {
    "Settings": {"zh-Hans": "设置", "zh-Hant": "設定"},
    "Loading": {"zh-Hans": "正在加载", "zh-Hant": "正在載入"},
    "No data": {"zh-Hans": "无数据", "zh-Hant": "無資料"},
    "No curve data": {"zh-Hans": "暂无曲线数据", "zh-Hant": "暫無曲線資料"},
    "Vehicle": {"zh-Hans": "车辆", "zh-Hant": "車輛"},
    "Charge Detail": {"zh-Hans": "充电详情", "zh-Hant": "充電詳情"},
    "Follow System": {"zh-Hans": "跟随系统", "zh-Hant": "跟隨系統"},
}

ENGLISH_UI_WORDS = re.compile(
    r"\b("
    r"drives?|Charge|Charging|Sentry|Mileage|Weather|Settings|Dashboard|"
    r"History|Current|Compare|Trip|Trips|Stats|Software|Updates|Regions|"
    r"Countries|Battery|Vehicle|Vehicles"
    r")\b"
)

SWIFTUI_LITERAL = re.compile(
    r"\b(Text|Label|Button|Picker|Toggle|Section|navigationTitle|"
    r"accessibilityLabel|accessibilityHint|help)\(\s*\"([^\"]*[A-Za-z][^\"]*)\""
)

RAW_ERROR_PRESENTATION = re.compile(
    r"\b(?:Text|Label)\(\s*(?:error|message|errorMessage|auditError|exportError)\b"
)

SOURCE_LOCALIZED_PAIR = re.compile(
    r"""(?:\bt|\blocalized|AppText\.localized)\(
        \s*"((?:[^"\\]|\\.)*)"
        \s*,\s*"((?:[^"\\]|\\.)*)"
    """,
    re.DOTALL | re.VERBOSE,
)

HAN_TEXT = re.compile(r"[\u3400-\u9fff]")
ALLOWED_NON_HAN_CHINESE_FALLBACKS = {
    "--",
    "AC",
    "DC",
    "HTTP",
    "MateDrive",
    "Model S",
    "Model 3",
    "Model X",
    "Model Y",
    "MyTesS AK/SK",
    "Open-Meteo",
    "SOC",
    "SSL",
    "TeslaMate",
    "URL",
    "iCloud",
    "iOS",
    "kW",
    "kWh",
    "km",
}

SOURCE_LOCALIZATION_MARKERS = (
    't("',
    "localized(",
    "DashboardTextFormatter",
    "MateDriveUnitFormatter",
    "UserFacingErrorLocalizer",
    "String(format:",
    "Text(verbatim:",
)

ALLOWED_SWIFTUI_LITERALS = {
    "MateDrive",
}


def swift_source_paths():
    for root in SWIFT_SOURCE_ROOTS:
        if not root.exists():
            continue
        yield from sorted(root.rglob("*.swift"))


def looks_like_hardcoded_english_ui(line: str, literal: str) -> bool:
    if "\\(" in literal:
        return False
    if literal in ALLOWED_SWIFTUI_LITERALS:
        return False
    if any(marker in line for marker in SOURCE_LOCALIZATION_MARKERS):
        return False
    return bool(ENGLISH_UI_WORDS.search(literal))


def main() -> int:
    compiled_resources = subprocess.run(
        [sys.executable, "scripts/generate_strings_resources.py", "--check"],
        check=False,
    )
    data = json.loads(LOCALIZATION_PATH.read_text())
    strings = data.get("strings", {})
    missing = {locale: [] for locale in CHINESE_LOCALES}
    english_like = {locale: [] for locale in CHINESE_LOCALES}
    translation_mismatches = []
    hardcoded_swiftui = []
    raw_error_presentations = []
    shortcut_localization_errors = []
    source_fallback_errors = []
    source_pairs_checked = 0

    for key, value in sorted(strings.items()):
        for locale in CHINESE_LOCALES:
            localization = value.get("localizations", {}).get(locale)
            text = ""
            if localization:
                text = localization.get("stringUnit", {}).get("value", "")
            if not text:
                missing[locale].append(key)
                continue
            if ENGLISH_UI_WORDS.search(text):
                english_like[locale].append((key, text))

    for key, expected_by_locale in REQUIRED_CHINESE_TRANSLATIONS.items():
        for locale, expected in expected_by_locale.items():
            actual = strings.get(key, {}).get("localizations", {}).get(locale, {}).get("stringUnit", {}).get("value")
            if actual != expected:
                translation_mismatches.append((key, locale, expected, actual))

    for path in swift_source_paths():
        source = path.read_text()
        for match in SOURCE_LOCALIZED_PAIR.finditer(source):
            raw_key, raw_chinese = match.groups()
            if "\\(" in raw_key or "\\" in raw_key or "\\" in raw_chinese:
                continue
            source_pairs_checked += 1
            if not raw_chinese.strip():
                source_fallback_errors.append((path, raw_key, "empty Chinese fallback"))
            elif (
                re.search(r"[A-Za-z]", raw_key)
                and not HAN_TEXT.search(raw_chinese)
                and raw_chinese not in ALLOWED_NON_HAN_CHINESE_FALLBACKS
            ):
                source_fallback_errors.append((path, raw_key, f"Chinese fallback remains {raw_chinese!r}"))

        for line_number, line in enumerate(source.splitlines(), start=1):
            for match in SWIFTUI_LITERAL.finditer(line):
                literal = match.group(2)
                if looks_like_hardcoded_english_ui(line, literal):
                    hardcoded_swiftui.append((path, line_number, literal))
            if RAW_ERROR_PRESENTATION.search(line) and "UserFacingErrorLocalizer" not in line:
                raw_error_presentations.append((path, line_number, line.strip()))

    shortcut_data = json.loads(APP_SHORTCUTS_LOCALIZATION_PATH.read_text())
    for key, value in sorted(shortcut_data.get("strings", {}).items()):
        for locale in SUPPORTED_LOCALES:
            values = (
                value.get("localizations", {})
                .get(locale, {})
                .get("stringSet", {})
                .get("values", [])
            )
            if not values or not all(text.strip() for text in values):
                shortcut_localization_errors.append((key, locale, "missing translation"))
                continue
            if any(text.count("${applicationName}") != 1 for text in values):
                shortcut_localization_errors.append((key, locale, "invalid applicationName placeholder"))

    print(f"localization keys: {len(strings)}")
    for locale in CHINESE_LOCALES:
        print(f"missing {locale} values: {len(missing[locale])}")
        print(f"english-like {locale} values: {len(english_like[locale])}")
    print(f"required Chinese translation mismatches: {len(translation_mismatches)}")
    print(f"hardcoded SwiftUI English literals: {len(hardcoded_swiftui)}")
    print(f"raw runtime error presentations: {len(raw_error_presentations)}")
    print(f"literal localized source pairs checked: {source_pairs_checked}")
    print(f"source fallback errors: {len(source_fallback_errors)}")
    print(f"App Shortcut localization errors: {len(shortcut_localization_errors)}")

    for locale in CHINESE_LOCALES:
        if missing[locale]:
            print(f"\nMissing {locale}:")
            for key in missing[locale]:
                print(f"- {key}")

        if english_like[locale]:
            print(f"\nEnglish-looking {locale} values:")
            for key, text in english_like[locale]:
                print(f"- {key}: {text}")

    if translation_mismatches:
        print("\nRequired Chinese translation mismatches:")
        for key, locale, expected, actual in translation_mismatches:
            print(f"- {key} [{locale}]: expected {expected!r}, got {actual!r}")

    if hardcoded_swiftui:
        print("\nHardcoded SwiftUI English literals:")
        for path, line_number, literal in hardcoded_swiftui:
            print(f"- {path}:{line_number}: {literal}")

    if raw_error_presentations:
        print("\nRaw runtime error presentations:")
        for path, line_number, line in raw_error_presentations:
            print(f"- {path}:{line_number}: {line}")

    if source_fallback_errors:
        print("\nSource fallback errors:")
        for path, key, reason in source_fallback_errors:
            print(f"- {path}: {key}: {reason}")

    if shortcut_localization_errors:
        print("\nApp Shortcut localization errors:")
        for key, locale, reason in shortcut_localization_errors:
            print(f"- {key} [{locale}]: {reason}")

    has_missing = any(missing.values())
    has_english_like = any(english_like.values())
    return 1 if compiled_resources.returncode or has_missing or has_english_like or translation_mismatches or hardcoded_swiftui or raw_error_presentations or source_fallback_errors or shortcut_localization_errors else 0


if __name__ == "__main__":
    sys.exit(main())
