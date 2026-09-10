#!/usr/bin/env python3
"""Focused mutation tests for the regional tariff catalog audit."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from copy import deepcopy
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
AUDIT = ROOT / "scripts/audit_regional_tariffs.py"
CATALOG = ROOT / "MateDriveApp/Resources/RegionalChargingTariffs.json"


class RegionalTariffAuditTests(unittest.TestCase):
    def setUp(self) -> None:
        self.catalog = json.loads(CATALOG.read_text(encoding="utf-8"))

    def run_audit(self, catalog: dict) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "RegionalChargingTariffs.json"
            path.write_text(json.dumps(catalog), encoding="utf-8")
            return subprocess.run(
                [sys.executable, str(AUDIT), "--catalog", str(path), "--today", "2026-07-18"],
                text=True,
                capture_output=True,
                check=False,
            )

    def assert_audit_fails(self, catalog: dict, message: str) -> None:
        result = self.run_audit(catalog)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(message, result.stderr)

    def hunan_tariff(self, catalog: dict) -> dict:
        region = next(region for region in catalog["regions"] if region["regionCode"] == "CN-43")
        return region["tariffs"][0]

    def test_checked_in_catalog_passes(self) -> None:
        self.assertEqual(
            self.hunan_tariff(self.catalog)["sourceURL"],
            "https://fgw.hunan.gov.cn/fgw/xxgk_70899/zcfg/dfxfg/202407/t20240708_33349442.html",
        )
        result = self.run_audit(self.catalog)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("31 region records (1 verified, 30 no verified dedicated tariff)", result.stdout)

    def test_duplicate_region_code_fails(self) -> None:
        catalog = deepcopy(self.catalog)
        catalog["regions"][1]["regionCode"] = "CN-11"
        self.assertNotEqual(self.run_audit(catalog).returncode, 0)

    def test_required_region_missing_fails(self) -> None:
        catalog = deepcopy(self.catalog)
        catalog["regions"] = [region for region in catalog["regions"] if region["regionCode"] != "CN-65"]
        self.assert_audit_fails(
            catalog,
            "catalog must contain exactly the 31 required mainland ISO 3166-2 region codes",
        )

    def test_non_https_numeric_tariff_source_fails(self) -> None:
        catalog = deepcopy(self.catalog)
        self.hunan_tariff(catalog)["sourceURL"] = "http://fgw.hunan.gov.cn/document"
        self.assert_audit_fails(catalog, "sourceURL must use an audited official government host")

    def test_arbitrary_https_tariff_source_fails(self) -> None:
        catalog = deepcopy(self.catalog)
        self.hunan_tariff(catalog)["sourceURL"] = "https://example.com/document"
        self.assert_audit_fails(catalog, "sourceURL must use an audited official government host")

    def test_expired_active_tariff_fails(self) -> None:
        catalog = deepcopy(self.catalog)
        self.hunan_tariff(catalog)["status"] = "active"
        self.assert_audit_fails(catalog, "is expired but marked active")

    def test_uncovered_minutes_fail(self) -> None:
        catalog = deepcopy(self.catalog)
        self.hunan_tariff(catalog)["timeSegments"][0]["endMinuteOfDay"] = 418
        self.assert_audit_fails(catalog, "timeSegments do not cover every minute of the day")

    def test_overlapping_minutes_fail(self) -> None:
        catalog = deepcopy(self.catalog)
        self.hunan_tariff(catalog)["timeSegments"][0]["endMinuteOfDay"] = 420
        self.assert_audit_fails(catalog, "timeSegments overlap at minute 420")

    def test_invalid_weekday_fails(self) -> None:
        catalog = deepcopy(self.catalog)
        self.hunan_tariff(catalog)["applicableWeekdays"] = [0]
        self.assert_audit_fails(catalog, "applicableWeekdays contains an invalid value")

    def test_invalid_month_fails(self) -> None:
        catalog = deepcopy(self.catalog)
        self.hunan_tariff(catalog)["applicableMonths"] = [13]
        self.assert_audit_fails(catalog, "applicableMonths contains an invalid value")

    def test_negative_fees_fail(self) -> None:
        for field in ("basePricePerKWh", "serviceFeePerKWh", "sessionFee"):
            with self.subTest(field=field):
                catalog = deepcopy(self.catalog)
                self.hunan_tariff(catalog)[field] = -0.01
                self.assert_audit_fails(catalog, f".{field} must be a finite nonnegative number")

    def test_invalid_catalog_classifications_fail(self) -> None:
        cases = (
            ("currencyCode", "USD", "currencyCode must be CNY"),
            ("customerClass", "commercial", "customerClass must be residential-ev"),
            ("chargeType", "wireless", "chargeType is invalid"),
        )
        for field, value, message in cases:
            with self.subTest(field=field):
                catalog = deepcopy(self.catalog)
                self.hunan_tariff(catalog)[field] = value
                self.assert_audit_fails(catalog, message)

    def test_malformed_effective_date_fails(self) -> None:
        catalog = deepcopy(self.catalog)
        self.hunan_tariff(catalog)["effectiveFromDate"] = "2024-02-30"
        self.assert_audit_fails(catalog, "effectiveFromDate is not a valid YYYY-MM-DD date")

    def test_numeric_tariff_missing_effective_from_date_fails(self) -> None:
        catalog = deepcopy(self.catalog)
        del self.hunan_tariff(catalog)["effectiveFromDate"]
        self.assert_audit_fails(catalog, "effectiveFromDate must be a YYYY-MM-DD string")

    def test_malformed_effective_to_date_fails(self) -> None:
        catalog = deepcopy(self.catalog)
        self.hunan_tariff(catalog)["effectiveToDate"] = "2025-02-30"
        self.assert_audit_fails(catalog, "effectiveToDate is not a valid YYYY-MM-DD date")

    def test_inverted_effective_dates_fail(self) -> None:
        catalog = deepcopy(self.catalog)
        self.hunan_tariff(catalog)["effectiveFromDate"] = "2025-07-01"
        self.assert_audit_fails(catalog, "effective date range is inverted")

    def test_overlapping_tariff_date_ranges_fail(self) -> None:
        catalog = deepcopy(self.catalog)
        overlapping_tariff = deepcopy(self.hunan_tariff(catalog))
        overlapping_tariff["id"] = "cn43-overlapping-residential-ev"
        overlapping_tariff["effectiveFromDate"] = "2025-01-01"
        overlapping_tariff["effectiveToDate"] = "2025-12-31"
        next(region for region in catalog["regions"] if region["regionCode"] == "CN-43")["tariffs"].append(
            overlapping_tariff
        )
        self.assert_audit_fails(
            catalog,
            "CN-43 tariff date ranges overlap: cn43-2024-residential-ev and cn43-overlapping-residential-ev",
        )


if __name__ == "__main__":
    unittest.main()
