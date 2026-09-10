#!/usr/bin/env python3
"""Audit the bundled mainland residential EV tariff catalog without network access."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import math
import sys
from pathlib import Path
from urllib.parse import urlparse


EXPECTED_REGION_CODES = {
    "CN-11", "CN-12", "CN-13", "CN-14", "CN-15",
    "CN-21", "CN-22", "CN-23", "CN-31", "CN-32", "CN-33", "CN-34", "CN-35", "CN-36", "CN-37",
    "CN-41", "CN-42", "CN-43", "CN-44", "CN-45", "CN-46",
    "CN-50", "CN-51", "CN-52", "CN-53", "CN-54",
    "CN-61", "CN-62", "CN-63", "CN-64", "CN-65",
}
VALID_AVAILABILITY = {"verified", "noVerifiedDedicatedTariff"}
VALID_STATUS = {"active", "historical", "superseded"}
VALID_CHARGE_TYPES = {"ac", "dc", "teslaSupercharger", "otherDC"}

# Hosts outside the government namespace require an explicit, reviewed addition here.
AUDITED_OFFICIAL_SOURCE_HOST_ALLOWLIST: frozenset[str] = frozenset()


def parse_date(value: object, label: str) -> dt.date:
    if not isinstance(value, str):
        fail(f"{label} must be a YYYY-MM-DD string")
    try:
        parsed = dt.date.fromisoformat(value)
    except ValueError:
        fail(f"{label} is not a valid YYYY-MM-DD date")
    if parsed.isoformat() != value:
        fail(f"{label} is not a canonical YYYY-MM-DD date")
    return parsed


def require_nonnegative_number(value: object, label: str) -> None:
    if not isinstance(value, (int, float)) or isinstance(value, bool) or not math.isfinite(value) or value < 0:
        fail(f"{label} must be a finite nonnegative number")


def fail(message: str) -> None:
    raise ValueError(message)


def is_audited_official_source(value: object) -> bool:
    if not isinstance(value, str):
        return False
    parsed = urlparse(value)
    host = parsed.hostname.lower().rstrip(".") if parsed.hostname else ""
    is_government_host = host == "gov.cn" or host.endswith(".gov.cn")
    return parsed.scheme == "https" and bool(host) and (
        is_government_host or host in AUDITED_OFFICIAL_SOURCE_HOST_ALLOWLIST
    )


def minutes_in_segment(segment: dict[str, object], label: str) -> list[int]:
    start = segment.get("startMinuteOfDay")
    end = segment.get("endMinuteOfDay")
    if not isinstance(start, int) or isinstance(start, bool) or not 0 <= start <= 1_439:
        fail(f"{label}.startMinuteOfDay must be within 0 through 1439")
    if not isinstance(end, int) or isinstance(end, bool) or not 0 <= end <= 1_439:
        fail(f"{label}.endMinuteOfDay must be within 0 through 1439")
    require_nonnegative_number(segment.get("pricePerKWh"), f"{label}.pricePerKWh")
    return list(range(start, end + 1)) if start <= end else list(range(start, 1_440)) + list(range(0, end + 1))


def audit(catalog: dict[str, object], today: dt.date | None = None) -> tuple[int, int]:
    if not isinstance(catalog.get("regions"), list):
        fail("catalog.regions must be an array")

    regions = catalog["regions"]
    codes = [region.get("regionCode") for region in regions if isinstance(region, dict)]
    if len(regions) != 31 or len(codes) != 31 or set(codes) != EXPECTED_REGION_CODES:
        fail("catalog must contain exactly the 31 required mainland ISO 3166-2 region codes")
    if len(set(codes)) != len(codes):
        fail("catalog contains a duplicate region code")

    seen_tariff_ids: set[str] = set()
    verified_count = 0
    for region in regions:
        if not isinstance(region, dict):
            fail("each region must be an object")
        code = region["regionCode"]
        availability = region.get("availability")
        if availability not in VALID_AVAILABILITY:
            fail(f"{code}.availability is invalid")
        parse_date(region.get("verifiedAt"), f"{code}.verifiedAt")
        tariffs = region.get("tariffs")
        if not isinstance(tariffs, list):
            fail(f"{code}.tariffs must be an array")
        if availability == "noVerifiedDedicatedTariff":
            if tariffs:
                fail(f"{code} has no verified dedicated tariff but contains tariffs")
            continue
        if not tariffs:
            fail(f"{code} is verified but contains no tariffs")
        verified_count += 1
        audit_region_tariffs(code, tariffs, seen_tariff_ids, today or dt.date.today())

    return len(regions), verified_count


def audit_region_tariffs(code: str, tariffs: list[object], seen_tariff_ids: set[str], today: dt.date) -> None:
    date_ranges: list[tuple[dt.date, dt.date, str]] = []
    for index, tariff in enumerate(tariffs):
        label = f"{code}.tariffs[{index}]"
        if not isinstance(tariff, dict):
            fail(f"{label} must be an object")
        tariff_id = tariff.get("id")
        if not isinstance(tariff_id, str) or not tariff_id:
            fail(f"{label}.id must be a nonempty string")
        if tariff_id in seen_tariff_ids:
            fail(f"duplicate tariff id {tariff_id}")
        seen_tariff_ids.add(tariff_id)
        if tariff.get("status") not in VALID_STATUS:
            fail(f"{label}.status is invalid")
        if tariff.get("customerClass") != "residential-ev":
            fail(f"{label}.customerClass must be residential-ev")
        if tariff.get("chargeType") not in VALID_CHARGE_TYPES:
            fail(f"{label}.chargeType is invalid")
        if tariff.get("currencyCode") != "CNY":
            fail(f"{label}.currencyCode must be CNY")
        document_id = tariff.get("documentID")
        if not isinstance(document_id, str) or not document_id.strip():
            fail(f"{label}.documentID is required")
        source_url = tariff.get("sourceURL")
        if not is_audited_official_source(source_url):
            fail(f"{label}.sourceURL must use an audited official government host")

        effective_from = parse_date(tariff.get("effectiveFromDate"), f"{label}.effectiveFromDate")
        raw_effective_to = tariff.get("effectiveToDate")
        effective_to = parse_date(raw_effective_to, f"{label}.effectiveToDate") if raw_effective_to is not None else dt.date.max
        if effective_from > effective_to:
            fail(f"{label} effective date range is inverted")
        if tariff["status"] == "active" and effective_to < today:
            fail(f"{label} is expired but marked active")
        date_ranges.append((effective_from, effective_to, tariff_id))

        for fee in ("basePricePerKWh", "serviceFeePerKWh", "sessionFee"):
            require_nonnegative_number(tariff.get(fee), f"{label}.{fee}")
        validate_applicability(tariff.get("applicableWeekdays"), range(1, 8), f"{label}.applicableWeekdays")
        validate_applicability(tariff.get("applicableMonths"), range(1, 13), f"{label}.applicableMonths")

        segments = tariff.get("timeSegments")
        if not isinstance(segments, list) or not segments:
            fail(f"{label}.timeSegments must be a nonempty array")
        occupied = [False] * 1_440
        for segment_index, segment in enumerate(segments):
            if not isinstance(segment, dict):
                fail(f"{label}.timeSegments[{segment_index}] must be an object")
            for minute in minutes_in_segment(segment, f"{label}.timeSegments[{segment_index}]"):
                if occupied[minute]:
                    fail(f"{label}.timeSegments overlap at minute {minute}")
                occupied[minute] = True
        if not all(occupied):
            fail(f"{label}.timeSegments do not cover every minute of the day")

    for current, following in zip(sorted(date_ranges), sorted(date_ranges)[1:]):
        if following[0] <= current[1]:
            fail(f"{code} tariff date ranges overlap: {current[2]} and {following[2]}")


def validate_applicability(value: object, allowed: range, label: str) -> None:
    if value is None:
        return
    if not isinstance(value, list) or not value:
        fail(f"{label} must be null or a nonempty array")
    if any(not isinstance(item, int) or isinstance(item, bool) or item not in allowed for item in value):
        fail(f"{label} contains an invalid value")
    if len(set(value)) != len(value):
        fail(f"{label} contains duplicate values")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--catalog", type=Path, default=Path("MateDriveApp/Resources/RegionalChargingTariffs.json"))
    parser.add_argument("--today", type=dt.date.fromisoformat, default=dt.date.today())
    args = parser.parse_args()
    try:
        with args.catalog.open(encoding="utf-8") as handle:
            catalog = json.load(handle)
        region_count, verified_count = audit(catalog, args.today)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"Regional tariff audit failed: {error}", file=sys.stderr)
        return 1

    print(
        f"Regional tariff audit passed: {region_count} region records "
        f"({verified_count} verified, {region_count - verified_count} no verified dedicated tariff)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
