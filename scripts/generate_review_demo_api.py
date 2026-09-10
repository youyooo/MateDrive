#!/usr/bin/env python3
"""Generate a read-only, synthetic TeslaMate API for App Review."""

from __future__ import annotations

import argparse
import json
import shutil
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any


CAR_ID = 1
DRIVE_IDS = tuple(range(1008, 1000, -1))
CHARGE_IDS = tuple(range(2005, 2000, -1))
MARKER = ".generated-review-demo-api"

HOME = (31.22255, 121.44521)
OFFICE = (31.23168, 121.47431)
MALL = (31.23982, 121.49642)
PARK = (31.21472, 121.48715)


def iso(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def write_json(root: Path, relative: str, payload: Any) -> None:
    destination = root / relative / "index.html"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(
        json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )


def interpolate(
    start: tuple[float, float],
    end: tuple[float, float],
    progress: float,
) -> tuple[float, float]:
    return (
        start[0] + ((end[0] - start[0]) * progress),
        start[1] + ((end[1] - start[1]) * progress),
    )


def drive_summary(
    drive_id: int,
    start: datetime,
    start_name: str,
    end_name: str,
    distance: float,
    duration: int,
    odometer_start: float,
    start_soc: int,
    end_soc: int,
    energy: float,
) -> dict[str, Any]:
    consumption = round((energy * 1_000) / distance, 1)
    rated_start = round(start_soc * 4.63, 1)
    rated_end = round(end_soc * 4.63, 1)
    return {
        "drive_id": drive_id,
        "car_id": CAR_ID,
        "start_date": iso(start),
        "end_date": iso(start + timedelta(minutes=duration)),
        "duration_min": duration,
        "duration_str": f"{duration} min",
        "start_address": start_name,
        "end_address": end_name,
        "average_speed": round(distance / (duration / 60), 1),
        "speed_max": 78 + (drive_id % 4) * 4,
        "speed_avg": round(distance / (duration / 60), 1),
        "power_max": 54 + (drive_id % 5) * 4,
        "power_min": -24 - (drive_id % 3) * 3,
        "odometer_details": {
            "odometer_start": round(odometer_start, 1),
            "odometer_end": round(odometer_start + distance, 1),
            "odometer_distance": distance,
        },
        "battery_details": {
            "start_battery_level": start_soc,
            "end_battery_level": end_soc,
            "is_range_ideal": False,
        },
        "range_rated": {
            "start_range": rated_start,
            "end_range": rated_end,
            "range_diff": round(rated_end - rated_start, 1),
        },
        "outside_temp_avg": 24.0 + (drive_id % 4),
        "inside_temp_avg": 22.5,
        "energy_consumed_net": energy,
        "consumption_net": consumption,
    }


def drive_detail(
    summary: dict[str, Any],
    start_coordinate: tuple[float, float],
    end_coordinate: tuple[float, float],
) -> dict[str, Any]:
    start = datetime.fromisoformat(summary["start_date"].replace("Z", "+00:00"))
    duration = summary["duration_min"]
    start_soc = summary["battery_details"]["start_battery_level"]
    end_soc = summary["battery_details"]["end_battery_level"]
    positions: list[dict[str, Any]] = []
    sample_count = 24
    for index in range(sample_count):
        progress = index / (sample_count - 1)
        latitude, longitude = interpolate(start_coordinate, end_coordinate, progress)
        wave = (index % 7) - 3
        positions.append(
            {
                "date": iso(start + timedelta(minutes=duration * progress)),
                "latitude": round(latitude, 6),
                "longitude": round(longitude, 6),
                "speed": max(0, int(72 * (1 - abs((progress * 2) - 1))) + wave * 2),
                "power": -18 if index in {8, 17} else max(2, 9 + wave * 4),
                "battery_level": round(start_soc + ((end_soc - start_soc) * progress)),
                "elevation": 8 + (index % 6),
                "tpms_pressure_fl": 2.92,
                "tpms_pressure_fr": 2.95,
                "tpms_pressure_rl": 2.90,
                "tpms_pressure_rr": 2.93,
                "tire_pressure_gap": 0.05,
                "climate_info": {
                    "inside_temp": 22.5,
                    "outside_temp": round(summary["outside_temp_avg"] + (progress * 0.8), 1),
                    "is_climate_on": index < 15,
                    "fan_status": 2,
                    "driver_temp_setting": 22.0,
                    "passenger_temp_setting": 22.0,
                },
                "battery_info": {
                    "battery_heater": False,
                    "battery_heater_on": False,
                    "battery_heater_no_power": False,
                },
            }
        )

    detail = dict(summary)
    detail["drive_details"] = positions
    return {
        "data": {
            "car": {"car_id": CAR_ID, "car_name": "Model 3 Performance"},
            "drive": detail,
            "units": {
                "unit_of_length": "km",
                "unit_of_pressure": "bar",
                "unit_of_temperature": "C",
            },
        }
    }


def charge_summary(
    charge_id: int,
    start: datetime,
    address: str,
    energy_added: float,
    energy_used: float,
    cost: float,
    duration: int,
    start_soc: int,
    end_soc: int,
    power: float,
    phases: int,
    coordinate: tuple[float, float],
    odometer: float,
) -> dict[str, Any]:
    return {
        "charge_id": charge_id,
        "car_id": CAR_ID,
        "start_date": iso(start),
        "end_date": iso(start + timedelta(minutes=duration)),
        "address": address,
        "charge_energy_added": energy_added,
        "charge_energy_used": energy_used,
        "cost": cost,
        "duration_min": duration,
        "duration_str": f"{duration} min",
        "charger_power": power,
        "charger_phases": phases,
        "battery_details": {
            "start_battery_level": start_soc,
            "end_battery_level": end_soc,
        },
        "range_rated": {
            "start_range": round(start_soc * 4.63, 1),
            "end_range": round(end_soc * 4.63, 1),
        },
        "outside_temp_avg": 23.5,
        "odometer": odometer,
        "latitude": coordinate[0],
        "longitude": coordinate[1],
        "start_battery_level": start_soc,
        "end_battery_level": end_soc,
    }


def charge_detail(summary: dict[str, Any]) -> dict[str, Any]:
    start = datetime.fromisoformat(summary["start_date"].replace("Z", "+00:00"))
    duration = summary["duration_min"]
    start_soc = summary["battery_details"]["start_battery_level"]
    end_soc = summary["battery_details"]["end_battery_level"]
    energy_added = summary["charge_energy_added"]
    is_dc = summary["charger_phases"] == 0
    points: list[dict[str, Any]] = []
    sample_count = 12
    for index in range(sample_count):
        progress = index / (sample_count - 1)
        power = int(summary["charger_power"] * (1 - (progress * 0.28))) if is_dc else int(summary["charger_power"])
        points.append(
            {
                "date": iso(start + timedelta(minutes=duration * progress)),
                "battery_level": round(start_soc + ((end_soc - start_soc) * progress)),
                "charge_energy_added": round(energy_added * progress, 2),
                "outside_temp": round(summary["outside_temp_avg"] + (progress * 0.5), 1),
                "conn_charge_cable": "GB_DC" if is_dc else "IEC",
                "charger_details": {
                    "charger_power": power,
                    "charger_voltage": 384 if is_dc else 230,
                    "charger_actual_current": 260 if is_dc else 32,
                    "charger_phases": summary["charger_phases"],
                },
                "fast_charger_info": {
                    "fast_charger_present": is_dc,
                    "fast_charger_brand": "Demo Fast Charge" if is_dc else None,
                    "fast_charger_type": "GB" if is_dc else None,
                },
                "battery_info": {
                    "rated_battery_range_km": round(
                        (start_soc + ((end_soc - start_soc) * progress)) * 4.63,
                        1,
                    ),
                    "usable_battery_level": round(
                        start_soc + ((end_soc - start_soc) * progress)
                    ),
                },
            }
        )
    detail = dict(summary)
    detail["charge_details"] = points
    detail["is_charging"] = False
    return {
        "data": {
            "car": {"car_id": CAR_ID, "car_name": "Model 3 Performance"},
            "charge": detail,
        }
    }


def build_payloads(now: datetime) -> dict[str, Any]:
    now = now.astimezone(timezone.utc).replace(microsecond=0)
    route_specs = [
        ("Demo Home", "Demo Office", HOME, OFFICE, 18.6, 31, 80, 73, 3.05),
        ("Demo Office", "Demo Home", OFFICE, HOME, 19.1, 36, 72, 64, 3.22),
        ("Demo Home", "Riverside Demo", HOME, PARK, 11.8, 24, 80, 75, 1.82),
        ("Riverside Demo", "Demo Home", PARK, HOME, 12.1, 27, 75, 70, 1.91),
        ("Demo Home", "Demo Office", HOME, OFFICE, 18.4, 29, 80, 73, 2.88),
        ("Demo Office", "Demo Mall", OFFICE, MALL, 9.7, 22, 70, 66, 1.48),
        ("Demo Mall", "Demo Home", MALL, HOME, 15.3, 34, 66, 60, 2.41),
        ("Demo Home", "Demo Office", HOME, OFFICE, 18.8, 32, 80, 73, 2.96),
    ]
    drives: list[dict[str, Any]] = []
    drive_details: dict[int, dict[str, Any]] = {}
    odometer = 118_612.4
    for offset, (drive_id, spec) in enumerate(zip(DRIVE_IDS, route_specs)):
        start_name, end_name, start_coordinate, end_coordinate, distance, duration, start_soc, end_soc, energy = spec
        start = (now - timedelta(days=offset + 1)).replace(
            hour=0 if offset % 2 else 23,
            minute=20 + (offset % 3) * 5,
            second=0,
        )
        summary = drive_summary(
            drive_id,
            start,
            start_name,
            end_name,
            distance,
            duration,
            odometer,
            start_soc,
            end_soc,
            energy,
        )
        drives.append(summary)
        drive_details[drive_id] = drive_detail(summary, start_coordinate, end_coordinate)
        odometer += distance

    charge_specs = [
        ("Demo Home", 10.9, 11.6, 5.8, 74, 70, 80, 7.2, 3, HOME),
        ("Demo Fast Charge", 31.4, 34.2, 34.5, 28, 22, 68, 128.0, 0, MALL),
        ("Demo Office", 18.2, 19.5, 13.8, 96, 48, 80, 11.0, 3, OFFICE),
        ("Demo Home", 12.4, 13.1, 6.6, 82, 68, 80, 7.2, 3, HOME),
        ("Demo Mall", 20.6, 22.0, 25.0, 42, 35, 66, 60.0, 0, MALL),
    ]
    charges: list[dict[str, Any]] = []
    charge_details: dict[int, dict[str, Any]] = {}
    for offset, (charge_id, spec) in enumerate(zip(CHARGE_IDS, charge_specs)):
        (
            address,
            added,
            used,
            cost,
            duration,
            start_soc,
            end_soc,
            power,
            phases,
            coordinate,
        ) = spec
        start = (now - timedelta(days=(offset * 2) + 1)).replace(
            hour=16 if phases == 0 else 0,
            minute=5 + offset * 3,
            second=0,
        )
        summary = charge_summary(
            charge_id,
            start,
            address,
            added,
            used,
            cost,
            duration,
            start_soc,
            end_soc,
            power,
            phases,
            coordinate,
            118_760.0 - offset * 34.2,
        )
        charges.append(summary)
        charge_details[charge_id] = charge_detail(summary)

    activities = [
        {
            "id": drives[0]["drive_id"],
            "type": "drive",
            "start_date": drives[0]["start_date"],
            "duration_min": drives[0]["duration_min"],
            "kwh": -drives[0]["energy_consumed_net"],
            "soc_diff": drives[0]["battery_details"]["end_battery_level"]
            - drives[0]["battery_details"]["start_battery_level"],
            "distance_km": drives[0]["odometer_details"]["odometer_distance"],
            "start_address": drives[0]["start_address"],
            "end_address": drives[0]["end_address"],
            "stats": {
                "regen_utilization": 0.94,
                "hard_braking_count": 0,
                "is_new_place": False,
                "commute_route_id": 1,
                "evaluations": [
                    {
                        "type": "golden_foot",
                        "priority": 1,
                        "title_key": "drive_eval_golden_foot_title",
                        "message_key": "drive_eval_golden_foot_message",
                        "data": {"consumption": drives[0]["consumption_net"]},
                    }
                ],
            },
        },
        {
            "id": charges[0]["charge_id"],
            "type": "charge",
            "start_date": charges[0]["start_date"],
            "duration_min": charges[0]["duration_min"],
            "kwh": charges[0]["charge_energy_added"],
            "kwh_used": charges[0]["charge_energy_used"],
            "cost": charges[0]["cost"],
            "soc_diff": charges[0]["end_battery_level"] - charges[0]["start_battery_level"],
            "address": charges[0]["address"],
        },
        {
            "id": 3001,
            "type": "park",
            "start_date": iso(now - timedelta(hours=14)),
            "duration_min": 615,
            "range_diff_km": -2.8,
            "soc_diff": -1,
            "address": "Demo Home",
        },
    ]

    coordinates = [
        {
            "drive_id": drives[0]["drive_id"],
            "latitude": point["latitude"],
            "longitude": point["longitude"],
            "speed": point["speed"],
            "elevation": point["elevation"],
            "outside_temp": point["climate_info"]["outside_temp"],
            "date": point["date"],
            "type": "drive",
        }
        for point in drive_details[drives[0]["drive_id"]]["data"]["drive"]["drive_details"]
    ]

    date_labels = [
        (now - timedelta(days=days)).date().isoformat() for days in range(7, 0, -1)
    ]
    payloads: dict[str, Any] = {
        "api/v1/version": {
            "data": {
                "api_version": "2.5.1",
                "mt_api_version": "2.5.1",
                "build_info": "MateDrive synthetic read-only review data",
            }
        },
        "api/v1/cars": {
            "data": {
                "cars": [
                    {
                        "car_id": CAR_ID,
                        "display_name": "Model 3 Performance",
                        "car_details": {
                            "model": "3",
                            "trim_badging": "P",
                            "efficiency": 155.0,
                        },
                        "car_exterior": {
                            "exterior_color": "MidnightSilver",
                            "wheel_type": "Uberturbine20",
                        },
                        "car_settings": {"free_supercharging": False},
                        "teslamate_stats": {
                            "total_charges": len(charges),
                            "total_drives": len(drives),
                            "total_updates": 3,
                        },
                    }
                ]
            },
            "demo": True,
        },
        f"api/v1/cars/{CAR_ID}/status": {
            "data": {
                "status": {
                    "display_name": "Model 3 Performance",
                    "state": "asleep",
                    "state_since": iso(now - timedelta(hours=6, minutes=20)),
                    "odometer": round(odometer, 1),
                    "car_status": {
                        "healthy": True,
                        "locked": True,
                        "sentry_mode": False,
                        "windows_open": False,
                        "doors_open": False,
                        "trunk_open": False,
                        "frunk_open": False,
                        "is_user_present": False,
                        "center_display_state": "0",
                    },
                    "car_geodata": {
                        "geofence": "Demo Home",
                        "latitude": HOME[0],
                        "longitude": HOME[1],
                    },
                    "car_versions": {
                        "version": "2026.26.3",
                        "update_available": False,
                    },
                    "climate_details": {
                        "is_climate_on": False,
                        "inside_temp": 25.0,
                        "outside_temp": 27.0,
                        "is_preconditioning": False,
                    },
                    "battery_details": {
                        "battery_level": 72,
                        "usable_battery_level": 71,
                        "est_battery_range": 326.0,
                        "rated_battery_range": 333.4,
                        "ideal_battery_range": 348.0,
                    },
                    "charging_details": {
                        "plugged_in": False,
                        "charging_state": "Disconnected",
                        "charge_energy_added": 0.0,
                        "charge_limit_soc": 80,
                        "charge_port_door_open": False,
                        "charger_phases": None,
                        "charger_power": 0,
                    },
                    "tpms_details": {
                        "tpms_pressure_fl": 2.92,
                        "tpms_pressure_fr": 2.95,
                        "tpms_pressure_rl": 2.90,
                        "tpms_pressure_rr": 2.93,
                        "tpms_soft_warning_fl": False,
                        "tpms_soft_warning_fr": False,
                        "tpms_soft_warning_rl": False,
                        "tpms_soft_warning_rr": False,
                    },
                },
                "units": {
                    "unit_of_length": "km",
                    "unit_of_pressure": "bar",
                    "unit_of_temperature": "C",
                },
            },
            "demo": True,
        },
        f"api/v1/cars/{CAR_ID}/drives": {"data": {"drives": drives}, "demo": True},
        f"api/v1/cars/{CAR_ID}/charges": {"data": {"charges": charges}, "demo": True},
        f"api/v1/cars/{CAR_ID}/charges/current": {"data": None, "demo": True},
        f"api/v1/cars/{CAR_ID}/battery": {
            "data": {
                "battery": {
                    "car_id": CAR_ID,
                    "usable_battery_level": 71,
                    "battery_level": 72,
                    "rated_battery_range_km": 333.4,
                    "ideal_battery_range_km": 348.0,
                    "est_battery_range_km": 326.0,
                    "efficiency": 155.0,
                }
            },
            "demo": True,
        },
        f"api/v1/cars/{CAR_ID}/battery-health": {
            "data": {
                "battery_health": {
                    "max_range": 491.0,
                    "current_range": 468.2,
                    "max_capacity": 75.0,
                    "current_capacity": 71.4,
                    "rated_efficiency": 155.0,
                    "battery_health_percentage": 95.2,
                }
            },
            "demo": True,
        },
        f"api/v1/cars/{CAR_ID}/battery-health/history": {
            "data": {
                "car": {"car_id": CAR_ID, "car_name": "Model 3 Performance"},
                "charts": {
                    "capacity": [
                        {
                            "date": (now - timedelta(days=90 - (index * 15))).date().isoformat(),
                            "odometer": 116_900 + index * 315,
                            "capacity": round(72.0 - (index * 0.1), 2),
                        }
                        for index in range(7)
                    ],
                    "capacity_median": [
                        {
                            "bucket": f"demo-{index}",
                            "date": (now - timedelta(days=90 - (index * 15))).date().isoformat(),
                            "odometer": 116_900 + index * 315,
                            "capacity": round(72.0 - (index * 0.1), 2),
                        }
                        for index in range(7)
                    ],
                    "range": [
                        {
                            "date": (now - timedelta(days=90 - (index * 15))).date().isoformat(),
                            "odometer": 116_900 + index * 315,
                            "range": round(472.0 - (index * 0.6), 1),
                        }
                        for index in range(7)
                    ],
                },
                "efficiency": {
                    "value": 15.5,
                    "source": "derived",
                    "ready": True,
                    "qualifying_charge_count": len(charges),
                    "required_charge_count": 2,
                    "min_duration_min": 20,
                    "max_end_battery_level": 90,
                },
                "units": {
                    "unit_of_length": "km",
                    "unit_of_temperature": "C",
                    "unit_of_energy": "kWh",
                },
            },
            "demo": True,
        },
        f"api/v1/cars/{CAR_ID}/updates": {
            "data": {
                "updates": [
                    {
                        "update_id": 3,
                        "version": "2026.26.3 demo",
                        "start_date": iso(now - timedelta(days=14, minutes=35)),
                        "end_date": iso(now - timedelta(days=14)),
                    },
                    {
                        "update_id": 2,
                        "version": "2026.20.6 demo",
                        "start_date": iso(now - timedelta(days=48, minutes=42)),
                        "end_date": iso(now - timedelta(days=48)),
                    },
                    {
                        "update_id": 1,
                        "version": "2026.14.8 demo",
                        "start_date": iso(now - timedelta(days=92, minutes=38)),
                        "end_date": iso(now - timedelta(days=92)),
                    },
                ]
            },
            "demo": True,
        },
        "api/v1/globalsettings": {
            "data": {
                "settings": {
                    "teslamate_units": {
                        "unit_of_length": "km",
                        "unit_of_temperature": "C",
                        "unit_of_pressure": "bar",
                    },
                    "teslamate_webgui": {
                        "language": "en",
                        "preferred_range": "rated",
                    },
                }
            },
            "demo": True,
        },
        f"api/v1/cars/{CAR_ID}/activities": {
            "data": activities,
            "pagination": {
                "total_records": len(activities),
                "total_pages": 1,
                "page": 1,
                "limit": 20,
            },
            "units": {
                "unit_of_length": "km",
                "unit_of_pressure": "bar",
                "unit_of_temperature": "C",
            },
            "demo": True,
        },
        f"api/v1/cars/{CAR_ID}/stats": {
            "summary": {
                "total_distance_km": round(sum(item["odometer_details"]["odometer_distance"] for item in drives), 1),
                "total_charging_cost": round(sum(item["cost"] for item in charges), 2),
                "avg_consumption_net": 161.8,
                "avg_consumption_gross": 188.4,
                "avg_speed_kmh": 38.2,
                "avg_temp_c": 25.4,
                "total_elevation_change_m": 126.0,
                "avg_cost_per_kwh": 0.92,
                "zero_cost_charge_count": 0,
                "avg_regen_capture_rate": 0.94,
                "total_hard_braking_count": 2,
                "avg_hard_braking_per100km": 1.6,
                "commute_route_count": 1,
                "smart_commute_count": 4,
                "total_standby_range_loss_km": 7.8,
                "avg_drain_rate_km_h": 0.08,
                "avg_drain_rate_pct24h": 0.6,
                "parking_event_count": 9,
                "evaluations": {
                    "golden_foot_count": 3,
                    "short_trip_hvac_count": 1,
                },
            },
            "data": [
                {
                    "date": label,
                    "display": label,
                    "driving_duration_min": 45 + index * 3,
                    "distance_km": 28.0 + index * 2.6,
                    "trip_count": 2,
                    "total_energy_kwh": 4.7 + index * 0.3,
                    "charging_cost": 5.8 if index % 3 == 0 else 0.0,
                    "charge_count": 1 if index % 3 == 0 else 0,
                    "consumption_net": 158.0 + index * 1.5,
                    "consumption_gross": 183.0 + index * 1.8,
                }
                for index, label in enumerate(date_labels)
            ],
            "pagination": {
                "total_records": len(date_labels),
                "total_pages": 1,
                "page": 1,
                "limit": 50,
            },
            "units": {
                "unit_of_length": "km",
                "unit_of_pressure": "bar",
                "unit_of_temperature": "C",
            },
            "demo": True,
        },
        f"api/v1/cars/{CAR_ID}/stats/cost-charging-detail": {
            "contract_version": 1,
            "data": {
                "range": {
                    "start_date": iso(now - timedelta(days=7)),
                    "end_date": iso(now),
                    "period": "day",
                },
                "summary": {
                    "recorded_spend": round(sum(item["cost"] for item in charges), 2),
                    "estimated_use_cost": 72.4,
                    "charging_cost": round(sum(item["cost"] for item in charges), 2),
                    "parking_cost": 0.0,
                    "estimated_driving_energy_cost": 42.3,
                    "estimated_standby_energy_cost": 3.1,
                    "total_distance_km": round(sum(item["distance"] if "distance" in item else item["odometer_details"]["odometer_distance"] for item in drives), 1),
                    "drive_count": len(drives),
                    "charge_count": len(charges),
                    "cost_recorded_charge_count": len(charges),
                    "missing_charge_cost_count": 0,
                    "parking_event_count": 9,
                    "missing_parking_cost_count": 0,
                    "zero_parking_cost_count": 9,
                },
                "data_quality": {
                    "has_any_activity": True,
                    "has_stats_summary": True,
                    "charging_cost": {
                        "event_count": len(charges),
                        "cost_recorded_count": len(charges),
                        "missing_cost_count": 0,
                        "zero_cost_count": 0,
                        "cost_coverage": 1.0,
                    },
                    "parking_cost": {
                        "event_count": 9,
                        "cost_recorded_count": 9,
                        "missing_cost_count": 0,
                        "zero_cost_count": 9,
                        "cost_coverage": 1.0,
                    },
                    "energy_estimate": {
                        "is_available": True,
                        "price_per_kwh": 0.68,
                        "consumption_wh_per_km": 161.8,
                    },
                },
                "buckets": [
                    {
                        "id": f"day:{index}",
                        "date_from": int((now - timedelta(days=7-index)).timestamp() * 1000),
                        "date_to": int((now - timedelta(days=6-index)).timestamp() * 1000),
                        "granularity": "day",
                        "estimated_use_cost": 8.2 + index,
                        "recorded_spend": 5.8 if index % 3 == 0 else 0.0,
                        "charging_spend": 5.8 if index % 3 == 0 else 0.0,
                        "estimated_driving_energy_cost": 5.4 + index * 0.4,
                        "estimated_standby_energy_cost": 0.4,
                        "parking_cost": 0.0,
                        "charging_energy_kwh": 10.9 if index % 3 == 0 else 0.0,
                        "charge_count": 1 if index % 3 == 0 else 0,
                        "drive_count": 2,
                    }
                    for index in range(7)
                ],
                "charging_modes": [
                    {
                        "mode": "AC",
                        "charge_count": 3,
                        "energy_kwh": 41.5,
                    },
                    {
                        "mode": "DC",
                        "charge_count": 2,
                        "energy_kwh": 52.0,
                    },
                ],
                "place_rankings": {
                    "charging": [
                        {
                            "kind": "charging",
                            "place_id": 1,
                            "display_name": "Demo Home",
                            "charge_count": 3,
                            "total_energy_kwh": 41.5,
                            "total_cost": 19.0,
                            "cost_recorded_count": 3,
                            "missing_cost_count": 0,
                            "zero_cost_count": 0,
                        }
                    ],
                    "parking": [],
                    "standby": [],
                    "parking_zero_cost_confirmed": True,
                },
                "comparison": {
                    "previous_range": {
                        "start_date": iso(now - timedelta(days=14)),
                        "end_date": iso(now - timedelta(days=7)),
                        "period": "day",
                    },
                    "estimated_use_cost": {
                        "is_eligible": True,
                        "current_value": 72.4,
                        "previous_value": 78.1,
                        "delta": -5.7,
                        "percentage_change": -7.3,
                        "reason_codes": [],
                    },
                },
                "records": {
                    "top_charges": [
                        {
                            "id": charges[1]["charge_id"],
                            "type": "charge",
                            "title": charges[1]["address"],
                            "start_date": charges[1]["start_date"],
                            "energy_kwh": charges[1]["charge_energy_added"],
                            "cost": charges[1]["cost"],
                            "duration_min": charges[1]["duration_min"],
                        }
                    ],
                    "missing_charge_costs": [],
                    "missing_parking_costs": [],
                },
            },
            "units": {
                "unit_of_length": "km",
                "unit_of_pressure": "bar",
                "unit_of_temperature": "C",
            },
            "demo": True,
        },
        f"api/v1/cars/{CAR_ID}/drive-stats": {
            "data": {
                "car": {"car_id": CAR_ID, "car_name": "Model 3 Performance"},
                "drive_stats": [
                    {
                        "start_latitude": HOME[0],
                        "start_longitude": HOME[1],
                        "end_latitude": OFFICE[0],
                        "end_longitude": OFFICE[1],
                        "start_address": "Demo Home",
                        "end_address": "Demo Office",
                        "drive_count": 4,
                        "total_distance_km": 74.6,
                        "avg_distance_km": 18.65,
                        "total_duration_min": 128,
                        "avg_duration_min": 32,
                        "avg_speed_kmh": 35.0,
                        "total_energy_kwh": 11.85,
                        "avg_energy_kwh": 2.96,
                        "avg_power_kw": 12.4,
                        "consumption_wh_km": 158.8,
                        "last_drive_date": drives[0]["start_date"],
                        "most_common_hour": 7,
                    }
                ],
                "units": {
                    "unit_of_length": "km",
                    "unit_of_pressure": "bar",
                    "unit_of_temperature": "C",
                },
            },
            "demo": True,
        },
        f"api/v1/cars/{CAR_ID}/states": {
            "data": {
                "states": [
                    {
                        "state": "asleep",
                        "start_date": iso(now - timedelta(hours=6, minutes=20)),
                        "end_date": None,
                    },
                    {
                        "state": "online",
                        "start_date": iso(now - timedelta(hours=7)),
                        "end_date": iso(now - timedelta(hours=6, minutes=20)),
                    },
                ]
            },
            "demo": True,
        },
        f"api/v1/cars/{CAR_ID}/driving-coordinates": {
            "data": {
                "car_id": CAR_ID,
                "coordinates": coordinates,
                "original_points": len(coordinates),
                "simplified_points": len(coordinates),
                "units": {"length": "km", "temperature": "C"},
            },
            "demo": True,
        },
        f"api/v1/cars/{CAR_ID}/environment-history": {
            "data": {
                "series": [
                    {
                        "date": drives[index]["start_date"],
                        "drive_id": drives[index]["drive_id"],
                        "tpms_pressure_fl": 2.92 - index * 0.002,
                        "tpms_pressure_fr": 2.95 - index * 0.002,
                        "tpms_pressure_rl": 2.90 - index * 0.002,
                        "tpms_pressure_rr": 2.93 - index * 0.002,
                        "tire_pressure_gap": 0.05,
                        "outside_temp": drives[index]["outside_temp_avg"],
                        "inside_temp": drives[index]["inside_temp_avg"],
                        "consumption_wh_per_unit": drives[index]["consumption_net"],
                        "sample_count": 24,
                        "sample_policy": "synthetic_review",
                    }
                    for index in range(min(7, len(drives)))
                ],
                "summary": {
                    "point_count": min(7, len(drives)),
                    "sample_count": min(7, len(drives)) * 24,
                    "average_pressure_gap": 0.05,
                    "average_outside_temp": 25.4,
                },
                "temperature_energy_buckets": [
                    {
                        "temperature_from": 20,
                        "temperature_to": 25,
                        "median_consumption_wh_per_unit": 160.2,
                        "average_consumption_wh_per_unit": 161.4,
                        "drive_count": 4,
                        "distance": 62.3,
                    },
                    {
                        "temperature_from": 25,
                        "temperature_to": 30,
                        "median_consumption_wh_per_unit": 164.1,
                        "average_consumption_wh_per_unit": 165.0,
                        "drive_count": 4,
                        "distance": 63.4,
                    },
                ],
                "leak_observations": [],
                "metadata": {
                    "requested_grain": "day",
                    "resolved_grain": "day",
                    "sample_policy": "synthetic_review",
                    "start_date": iso(now - timedelta(days=30)),
                    "end_date": iso(now),
                    "timezone": "UTC",
                    "min_samples": 2,
                },
            },
            "units": {
                "unit_of_length": "km",
                "unit_of_pressure": "bar",
                "unit_of_temperature": "C",
            },
            "demo": True,
        },
        f"api/v1/cars/{CAR_ID}/standby-drain": {
            "data": {
                "latitude": HOME[0],
                "longitude": HOME[1],
                "radius_meters": 180,
                "period_days": 30,
                "total_parking_events": 9,
                "total_parking_days": 8.2,
                "avg_drain_rate_km_h": 0.08,
                "avg_drain_rate_pct24h": 0.6,
                "total_range_loss_km": 7.8,
                "min_drain_rate_km_h": 0.03,
                "max_drain_rate_km_h": 0.15,
            },
            "units": {"length": "km"},
            "demo": True,
        },
        f"api/v1/cars/{CAR_ID}/top-drain-locations": {
            "locations": [
                {
                    "address": "Demo Home",
                    "latitude": HOME[0],
                    "longitude": HOME[1],
                    "total_range_loss_km": 7.8,
                    "avg_drain_rate_pct24h": 0.6,
                    "avg_drain_rate_km_h": 0.08,
                    "parking_count": 9,
                    "total_duration_min": 11_808,
                }
            ],
            "units": {
                "unit_of_length": "km",
                "unit_of_pressure": "bar",
                "unit_of_temperature": "C",
            },
            "demo": True,
        },
        f"api/v1/cars/{CAR_ID}/commute-routes": {
            "routes": [
                {
                    "id": 1,
                    "start_latitude": HOME[0],
                    "start_longitude": HOME[1],
                    "end_latitude": OFFICE[0],
                    "end_longitude": OFFICE[1],
                    "start_address": "Demo Home",
                    "end_address": "Demo Office",
                    "trip_count": 4,
                    "smart_commute_count": 4,
                    "avg_duration_min": 32,
                    "min_duration_min": 29,
                    "max_duration_min": 36,
                    "total_distance_km": 74.6,
                    "avg_regen_capture_rate": 0.94,
                    "total_hard_braking_count": 1,
                    "avg_hard_braking_per100km": 1.3,
                    "total_elevation_gain": 42,
                    "total_elevation_loss": 39,
                    "avgpctspeed020": 0.18,
                    "avgpctspeed2040": 0.29,
                    "avgpctspeed4080": 0.48,
                    "avgpctspeed80120": 0.05,
                    "avg_pct_speed120_plus": 0.0,
                }
            ],
            "summary": {
                "total_commute_routes": 1,
                "total_commute_drives": 4,
                "total_smart_commutes": 4,
                "golden_foot_count": 3,
                "short_trip_hvac_count": 1,
            },
            "units": {
                "unit_of_length": "km",
                "unit_of_pressure": "bar",
                "unit_of_temperature": "C",
            },
            "demo": True,
        },
        f"api/v1/cars/{CAR_ID}/stats/extremes": {
            "extremes": [
                {
                    "type": "lowest_consumption",
                    "value": min(item["consumption_net"] for item in drives),
                    "unit": "Wh/km",
                    "date": drives[4]["start_date"],
                    "drive_id": drives[4]["drive_id"],
                },
                {
                    "type": "longest_drive",
                    "value": max(item["odometer_details"]["odometer_distance"] for item in drives),
                    "unit": "km",
                    "date": drives[1]["start_date"],
                    "drive_id": drives[1]["drive_id"],
                },
            ],
            "units": {
                "unit_of_length": "km",
                "unit_of_pressure": "bar",
                "unit_of_temperature": "C",
            },
            "demo": True,
        },
        f"api/v1/cars/{CAR_ID}/places": {
            "data": [
                {
                    "id": 1,
                    "display_name": "Demo Home",
                    "latitude": HOME[0],
                    "longitude": HOME[1],
                    "radius_meters": 180,
                    "primary_kind": "home",
                    "role": "home",
                    "role_confidence": "confirmed",
                    "role_group": "residential",
                    "visit_count": 12,
                    "active_days": 8,
                    "drive_start_count": 5,
                    "drive_end_count": 5,
                    "charge_count": 3,
                    "park_count": 9,
                    "first_seen": iso(now - timedelta(days=90)),
                    "last_seen": iso(now - timedelta(hours=6)),
                    "total_drive_distance_km": 126.2,
                    "total_drive_duration_min": 225,
                    "total_charge_kwh": 41.5,
                    "total_charge_cost": 19.0,
                    "missing_charge_cost_count": 0,
                    "total_parking_duration_min": 11_808,
                    "longest_parking_duration_min": 780,
                    "parking_range_loss_km": 7.8,
                    "has_driving": True,
                    "has_charging": True,
                    "has_parking": True,
                },
                {
                    "id": 2,
                    "display_name": "Demo Office",
                    "latitude": OFFICE[0],
                    "longitude": OFFICE[1],
                    "radius_meters": 160,
                    "primary_kind": "work",
                    "role": "work",
                    "role_confidence": "inferred",
                    "role_group": "workplace",
                    "visit_count": 7,
                    "active_days": 5,
                    "drive_start_count": 3,
                    "drive_end_count": 4,
                    "charge_count": 1,
                    "park_count": 5,
                    "first_seen": iso(now - timedelta(days=60)),
                    "last_seen": drives[0]["end_date"],
                    "total_drive_distance_km": 93.2,
                    "total_drive_duration_min": 168,
                    "total_charge_kwh": 18.2,
                    "total_charge_cost": 13.8,
                    "missing_charge_cost_count": 0,
                    "total_parking_duration_min": 2_460,
                    "longest_parking_duration_min": 540,
                    "parking_range_loss_km": 2.1,
                    "has_driving": True,
                    "has_charging": True,
                    "has_parking": True,
                },
            ],
            "pagination": {
                "total_records": 2,
                "total_pages": 1,
                "page": 1,
                "limit": 100,
            },
            "units": {
                "unit_of_length": "km",
                "unit_of_pressure": "bar",
                "unit_of_temperature": "C",
            },
            "demo": True,
        },
        f"api/v1/cars/{CAR_ID}/achievements": {
            "data": {
                "achievements": [
                    {
                        "id": "efficient_commute",
                        "current_value": 4,
                        "unit": "drives",
                        "tiers": [
                            {
                                "tier": 1,
                                "threshold": 3,
                                "unlocked": True,
                                "unlocked_at": drives[0]["end_date"],
                                "unlocked_drive_id": drives[0]["drive_id"],
                                "progress": 1.0,
                            }
                        ],
                    }
                ],
                "summary": {"total": 1, "unlocked": 1},
                "units": {
                    "unit_of_length": "km",
                    "unit_of_pressure": "bar",
                    "unit_of_temperature": "C",
                },
            },
            "demo": True,
        },
    }
    for drive_id, payload in drive_details.items():
        payloads[f"api/v1/cars/{CAR_ID}/drives/{drive_id}"] = payload
    for charge_id, payload in charge_details.items():
        payloads[f"api/v1/cars/{CAR_ID}/charges/{charge_id}"] = payload
    return payloads


def generate(output: Path, now: datetime | None = None) -> None:
    output = output.resolve()
    if output.exists():
        marker = output / MARKER
        if not marker.exists():
            raise RuntimeError(f"Refusing to replace unmarked directory: {output}")
        shutil.rmtree(output)
    output.mkdir(parents=True)
    (output / MARKER).write_text("Generated synthetic review data. Do not edit.\n", encoding="utf-8")
    (output / "index.html").write_text(
        """<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><meta name="robots" content="noindex,nofollow"><title>MateDrive Review Demo API</title></head>
<body>
<main>
<h1>MateDrive Review Demo API</h1>
<p>This endpoint contains synthetic, read-only vehicle data for App Review. It contains no user data or credentials.</p>
</main>
</body>
</html>
""",
        encoding="utf-8",
    )
    for relative, payload in build_payloads(now or datetime.now(timezone.utc)).items():
        write_json(output, relative, payload)


def parse_now(value: str | None) -> datetime | None:
    if value is None:
        return None
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("docs/support/review-demo"),
    )
    parser.add_argument(
        "--now",
        help="Optional ISO-8601 timestamp used for deterministic tests.",
    )
    args = parser.parse_args()
    generate(args.output, parse_now(args.now))
    print(f"Generated synthetic review API at {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
