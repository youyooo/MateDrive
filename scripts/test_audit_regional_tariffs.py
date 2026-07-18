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
CATALOG = ROOT / "MateDroidIOS/Resources/RegionalChargingTariffs.json"


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

    def test_checked_in_catalog_passes(self) -> None:
        result = self.run_audit(self.catalog)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("31 region records (1 verified, 30 no verified dedicated tariff)", result.stdout)

    def test_duplicate_region_code_fails(self) -> None:
        catalog = deepcopy(self.catalog)
        catalog["regions"][1]["regionCode"] = "CN-11"
        self.assertNotEqual(self.run_audit(catalog).returncode, 0)

    def test_non_https_numeric_tariff_source_fails(self) -> None:
        catalog = deepcopy(self.catalog)
        catalog["regions"][17]["tariffs"][0]["sourceURL"] = "http://fgw.hunan.gov.cn/document"
        self.assertNotEqual(self.run_audit(catalog).returncode, 0)

    def test_expired_active_tariff_fails(self) -> None:
        catalog = deepcopy(self.catalog)
        catalog["regions"][17]["tariffs"][0]["status"] = "active"
        self.assertNotEqual(self.run_audit(catalog).returncode, 0)

    def test_uncovered_minutes_fail(self) -> None:
        catalog = deepcopy(self.catalog)
        catalog["regions"][17]["tariffs"][0]["timeSegments"] = [
            { "id": "partial", "startMinuteOfDay": 0, "endMinuteOfDay": 100, "pricePerKWh": 0.5 }
        ]
        self.assertNotEqual(self.run_audit(catalog).returncode, 0)

    def test_invalid_weekday_fails(self) -> None:
        catalog = deepcopy(self.catalog)
        catalog["regions"][17]["tariffs"][0]["applicableWeekdays"] = [0]
        self.assertNotEqual(self.run_audit(catalog).returncode, 0)


if __name__ == "__main__":
    unittest.main()
