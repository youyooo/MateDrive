#!/usr/bin/env python3
"""Read-only validation for the bundled vehicle image catalog."""

import argparse
import json
import re
import struct
import sys
import zlib
from collections import Counter, defaultdict
from datetime import date
from pathlib import Path
from typing import Any

from PIL import Image, UnidentifiedImageError


SCHEMA_VERSION = 1
MASTER_DIMENSIONS = (1536, 768)
NORMALIZED_BOUNDS = {"left": (0.10, 0.25), "top": (0.15, 0.45), "right": (0.75, 0.95), "bottom": (0.65, 0.85)}
BASELINE_RANGE = (0.72, 0.82)
EDGE_ALPHA_LIMIT = 64
EDGE_CONTAMINATION_RATIO = 0.02
HIGH_ALPHA_EDGE_MIN = 128
HIGH_ALPHA_EDGE_MAX = 254
HIGH_ALPHA_EDGE_OUTWARD_DROP = 32
HIGH_ALPHA_EDGE_OPAQUE_MIN = 200
HIGH_ALPHA_EDGE_INWARD_RISE = 16
HIGH_ALPHA_EDGE_BRIGHTNESS_MIN = 220
HIGH_ALPHA_EDGE_BRIGHTNESS_DELTA = 48
HIGH_ALPHA_EDGE_CONTAMINATION_RATIO = 0.01
EDGE_DIRECTIONS = ((-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1))
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
SAFE_PNG_CHUNKS = {b"IHDR", b"PLTE", b"IDAT", b"IEND", b"tRNS"}
PNG_SINGLETON_CHUNKS = {
    b"IHDR", b"PLTE", b"tRNS", b"cHRM", b"gAMA", b"iCCP", b"sBIT", b"sRGB",
    b"bKGD", b"hIST", b"pHYs", b"tIME", b"pCAL", b"sCAL", b"oFFs", b"eXIf",
    b"acTL", b"IEND",
}
REVIEW_HEADERS = ["Asset ID", "Generation", "Trim", "Lamps/Fascia", "Brightwork", "Wheel", "Caliper", "Paint", "Perspective", "Scale", "Shadow", "Edge", "Reviewer", "Date", "Source Reference"]
CHECKLIST_FIELDS = REVIEW_HEADERS[1:12]
AFFIRMATIVE_VALUE = re.compile(r"^(?:pass|approved|yes)(?::\s*\S.*)?$", re.IGNORECASE)


def resources(root: Path) -> Path:
    return root / "MateDroidIOS/Resources"


def relative_image_path(value: object) -> str | None:
    if not isinstance(value, str) or not value.startswith("CarImages/"):
        return None
    path = Path(value)
    if path.is_absolute() or ".." in path.parts or path.suffix.lower() != ".png":
        return None
    return path.as_posix()


def in_range(value: float, limits: tuple[float, float]) -> bool:
    return limits[0] <= value <= limits[1]


def contained_file(root: Path, path_value: str) -> tuple[Path | None, str | None]:
    resource_directory = resources(root).resolve()
    image_directory = resources(root) / "CarImages"
    if image_directory.is_symlink():
        return None, "CarImages directory must not be a symlink"
    try:
        image_directory.resolve().relative_to(resource_directory)
    except ValueError:
        return None, "CarImages directory must be contained inside Resources"
    relative = Path(path_value).relative_to("CarImages")
    candidate = image_directory / relative
    component = image_directory
    for part in relative.parts[:-1]:
        component = component / part
        if component.is_symlink():
            return None, "image path contains a symlink component"
    if candidate.is_symlink():
        return None, "asset must be a regular file inside CarImages"
    try:
        candidate.resolve().relative_to(image_directory.resolve())
    except ValueError:
        return None, "asset must be contained inside CarImages"
    if not candidate.is_file():
        return None, f"missing file {path_value}"
    return candidate, None


def png_chunks(path: Path) -> set[bytes]:
    data = path.read_bytes()
    if not data.startswith(PNG_SIGNATURE):
        raise ValueError("not a PNG")
    offset, chunks, seen_idat, idat_finished = len(PNG_SIGNATURE), set(), False, False
    while offset < len(data):
        if offset + 12 > len(data):
            raise ValueError("truncated PNG chunk")
        length = struct.unpack_from(">I", data, offset)[0]
        chunk_type = data[offset + 4 : offset + 8]
        if len(chunk_type) != 4 or any(not (65 <= byte <= 90 or 97 <= byte <= 122) for byte in chunk_type):
            raise ValueError("invalid PNG chunk type")
        if chunk_type[2] & 0x20:
            raise ValueError("PNG chunk reserved bit must be uppercase")
        if not (chunk_type[0] & 0x20) and chunk_type not in {b"IHDR", b"PLTE", b"IDAT", b"IEND"}:
            raise ValueError(f"unknown critical PNG chunk {chunk_type.decode()}")
        end = offset + 12 + length
        if end > len(data):
            raise ValueError("truncated PNG chunk")
        chunk_data = data[offset + 8 : offset + 8 + length]
        expected_crc = struct.unpack_from(">I", data, offset + 8 + length)[0]
        if zlib.crc32(chunk_type + chunk_data) & 0xFFFFFFFF != expected_crc:
            raise ValueError("PNG chunk CRC mismatch")
        if not chunks and (chunk_type != b"IHDR" or length != 13):
            raise ValueError("IHDR must be the first chunk")
        if chunk_type in PNG_SINGLETON_CHUNKS and chunk_type in chunks:
            raise ValueError(f"duplicate {chunk_type.decode()} chunk")
        if chunk_type == b"IDAT":
            if idat_finished:
                raise ValueError("non-contiguous IDAT chunks")
            seen_idat = True
        elif seen_idat:
            idat_finished = True
        if chunk_type in {b"PLTE", b"tRNS"} and seen_idat:
            raise ValueError(f"{chunk_type.decode()} must precede IDAT")
        chunks.add(chunk_type)
        offset = end
        if chunk_type == b"IEND":
            if length != 0 or not seen_idat:
                raise ValueError("invalid IEND chunk")
            if offset != len(data):
                raise ValueError("trailing bytes after IEND")
            return chunks
    raise ValueError("missing IEND chunk")


def inspect_png(path: Path, label: str, dimensions: tuple[int, int]) -> tuple[Image.Image | None, set[bytes], list[str]]:
    try:
        chunks = png_chunks(path)
        with Image.open(path) as source:
            source.verify()
        with Image.open(path) as source:
            source.load()
            if "A" not in source.getbands() and "transparency" not in source.info:
                return None, chunks, [f"{label}: PNG must contain an alpha channel"]
            findings = []
            if source.size != dimensions:
                findings.append(f"{label}: dimensions must be {dimensions[0]}x{dimensions[1]}, got {source.width}x{source.height}")
            return source.convert("RGBA"), chunks, findings
    except (OSError, UnidentifiedImageError, ValueError, struct.error) as error:
        return None, set(), [f"{label}: invalid PNG ({error})"]


def load_inventory(root: Path) -> tuple[dict[str, tuple[int, int]], list[str]]:
    path = root / "scripts/data/vehicle_image_legacy_inventory.json"
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return {}, [f"legacy inventory: invalid JSON ({error})"]
    if not isinstance(payload, dict):
        return {}, ["legacy inventory: root must be an object"]
    if type(payload.get("schemaVersion")) is not int:
        return {}, ["legacy inventory: schemaVersion must be an integer"]
    if payload["schemaVersion"] != SCHEMA_VERSION:
        return {}, [f"legacy inventory: unsupported schemaVersion {payload['schemaVersion']}"]
    if not isinstance(payload.get("assets"), list):
        return {}, ["legacy inventory: assets must be an array"]
    inventory, findings = {}, []
    for entry in payload["assets"]:
        path_value = relative_image_path(entry.get("path")) if isinstance(entry, dict) else None
        width = entry.get("width") if isinstance(entry, dict) else None
        height = entry.get("height") if isinstance(entry, dict) else None
        if path_value is None or type(width) is not int or type(height) is not int or width <= 0 or height <= 0:
            findings.append("legacy inventory: entries require contained PNG paths and positive integer dimensions")
        elif path_value in inventory:
            findings.append(f"legacy inventory: duplicate path {path_value}")
        else:
            inventory[path_value] = (width, height)
    return inventory, findings


def review_records(path: Path) -> tuple[dict[str, dict[str, str]], list[str]]:
    if not path.exists():
        return {}, []
    records, findings, header = {}, [], None
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip().startswith("|"):
            header = None
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if header is None:
            if "Asset ID" in cells:
                if cells != REVIEW_HEADERS:
                    findings.append("review: Reviewed Assets table must use the complete header")
                else:
                    header = cells
            continue
        if all(cell and set(cell) <= {"-", ":"} for cell in cells):
            continue
        if len(cells) != len(header):
            findings.append("review: malformed Reviewed Assets row")
            continue
        record = dict(zip(header, cells))
        asset_id = record["Asset ID"]
        if asset_id in records:
            findings.append(f"review: duplicate asset row {asset_id}")
        else:
            records[asset_id] = record
    return records, findings


def review_findings(asset_id: str, record: dict[str, str] | None) -> list[str]:
    if record is None:
        return [f"{asset_id}: missing human review record"]
    findings = []
    for field in CHECKLIST_FIELDS:
        if not AFFIRMATIVE_VALUE.fullmatch(record.get(field, "").strip()):
            findings.append(f"{asset_id}: review {field} must be affirmative")
    if not record.get("Reviewer", "").strip() or not record.get("Source Reference", "").strip():
        findings.append(f"{asset_id}: review reviewer and source reference are required")
    try:
        date.fromisoformat(record.get("Date", ""))
    except ValueError:
        findings.append(f"{asset_id}: review date must be ISO-8601")
    return findings


def edge_contamination_ratios(image: Image.Image) -> tuple[float, float]:
    pixels, width, height = list(image.getdata()), image.width, image.height
    low_candidate_weight = low_contaminated_weight = 0
    high_candidates = high_contaminated = 0
    for index, pixel in enumerate(pixels):
        brightness, alpha = sum(pixel[:3]) / 3, pixel[3]
        x, y = index % width, index // width
        if 0 < alpha <= EDGE_ALPHA_LIMIT:
            opaque_neighbors = [pixels[ny * width + nx] for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)) if 0 <= nx < width and 0 <= ny < height and pixels[ny * width + nx][3] >= 200]
            if opaque_neighbors:
                low_candidate_weight += alpha
                if (brightness >= 245 or brightness <= 10) and any(abs(sum(neighbor[:3]) / 3 - brightness) >= 64 for neighbor in opaque_neighbors):
                    low_contaminated_weight += alpha
        elif HIGH_ALPHA_EDGE_MIN <= alpha <= HIGH_ALPHA_EDGE_MAX:
            required_inward_alpha = max(HIGH_ALPHA_EDGE_OPAQUE_MIN, min(255, alpha + HIGH_ALPHA_EDGE_INWARD_RISE))
            has_directional_pair = contaminated_directional_pair = False
            for dx, dy in EDGE_DIRECTIONS:
                outward_x, outward_y = x + dx, y + dy
                inward_x, inward_y = x - dx, y - dy
                if not (0 <= outward_x < width and 0 <= outward_y < height and 0 <= inward_x < width and 0 <= inward_y < height):
                    continue
                outward = pixels[outward_y * width + outward_x]
                inward = pixels[inward_y * width + inward_x]
                if outward[3] > alpha - HIGH_ALPHA_EDGE_OUTWARD_DROP or inward[3] < required_inward_alpha:
                    continue
                has_directional_pair = True
                if brightness >= HIGH_ALPHA_EDGE_BRIGHTNESS_MIN and brightness - sum(inward[:3]) / 3 >= HIGH_ALPHA_EDGE_BRIGHTNESS_DELTA:
                    contaminated_directional_pair = True
            if has_directional_pair:
                high_candidates += 1
                if contaminated_directional_pair:
                    high_contaminated += 1
    low_ratio = low_contaminated_weight / low_candidate_weight if low_candidate_weight else 0
    high_ratio = high_contaminated / high_candidates if high_candidates else 0
    return low_ratio, high_ratio


def edge_contaminated(image: Image.Image) -> bool:
    low_ratio, high_ratio = edge_contamination_ratios(image)
    return low_ratio > EDGE_CONTAMINATION_RATIO or high_ratio > HIGH_ALPHA_EDGE_CONTAMINATION_RATIO


def required_string(record: dict[str, Any], path: str, field: str, findings: list[str]) -> bool:
    if not isinstance(record.get(field), str):
        findings.append(f"{path}.{field}: required string")
        return False
    return True


def required_string_list(record: dict[str, Any], path: str, field: str, findings: list[str]) -> bool:
    value = record.get(field)
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        findings.append(f"{path}.{field}: required string array")
        return False
    return True


def valid_option_records(record: dict[str, Any], path: str, field: str, findings: list[str]) -> bool:
    values = record.get(field)
    if not isinstance(values, list):
        findings.append(f"{path}.{field}: required array")
        return False
    valid = True
    for index, value in enumerate(values):
        item_path = f"{path}.{field}[{index}]"
        if not isinstance(value, dict):
            findings.append(f"{item_path}: required object")
            valid = False
            continue
        valid = required_string(value, item_path, "id", findings) and valid
        valid = required_string_list(value, item_path, "aliases", findings) and valid
        valid = required_string(value, item_path, "localizationKey", findings) and valid
    return valid


def valid_generation_record(record: object, index: int, findings: list[str]) -> bool:
    path = f"catalog.generations[{index}]"
    if not isinstance(record, dict):
        findings.append(f"{path}: required object")
        return False
    valid = True
    for field in ("id", "model", "localizationKey", "defaultTrimID", "defaultWheelID", "defaultColorID"):
        valid = required_string(record, path, field, findings) and valid
    valid = required_string_list(record, path, "aliases", findings) and valid
    for field in ("yearStart", "matcherPriority"):
        if type(record.get(field)) is not int:
            findings.append(f"{path}.{field}: required integer")
            valid = False
    if "yearEnd" in record and record["yearEnd"] is not None and type(record["yearEnd"]) is not int:
        findings.append(f"{path}.yearEnd: required integer or null")
        valid = False
    for field in ("trims", "wheels", "colors"):
        valid = valid_option_records(record, path, field, findings) and valid
    fallback = record.get("legacyFallback")
    if not isinstance(fallback, dict):
        findings.append(f"{path}.legacyFallback: required object")
        return False
    valid = required_string(fallback, f"{path}.legacyFallback", "assetID", findings) and valid
    valid = required_string(fallback, f"{path}.legacyFallback", "path", findings) and valid
    return valid


def valid_asset_record(record: object, index: int, findings: list[str]) -> bool:
    path = f"catalog.assets[{index}]"
    if not isinstance(record, dict):
        findings.append(f"{path}: required object")
        return False
    valid = True
    for field in ("id", "generationID", "trimID", "wheelID", "colorID", "path", "reviewStatus"):
        valid = required_string(record, path, field, findings) and valid
    return valid


def validate_catalog(catalog: dict[str, Any], inventory: dict[str, tuple[int, int]]) -> tuple[list[str], list[dict[str, Any]], set[str]]:
    findings = []
    if type(catalog.get("schemaVersion")) is not int:
        findings.append("catalog.schemaVersion: required integer")
    elif catalog.get("schemaVersion") != SCHEMA_VERSION:
        findings.append(f"catalog: unsupported schemaVersion {catalog.get('schemaVersion')}")
    raw_assets, raw_generations = catalog.get("assets"), catalog.get("generations")
    if not isinstance(raw_assets, list) or not isinstance(raw_generations, list):
        return findings + ["catalog: assets and generations must be arrays"], [], set()
    generations = [generation for index, generation in enumerate(raw_generations) if valid_generation_record(generation, index, findings)]
    assets = [asset for index, asset in enumerate(raw_assets) if valid_asset_record(asset, index, findings)]
    for identifier, count in Counter(g.get("id") for g in generations if isinstance(g, dict)).items():
        if isinstance(identifier, str) and count > 1:
            findings.append(f"duplicate catalog generation ID: {identifier}")
    for identifier, count in Counter(a.get("id") for a in assets if isinstance(a, dict)).items():
        if isinstance(identifier, str) and count > 1:
            findings.append(f"duplicate catalog asset ID: {identifier}")
    generations_by_id = {g["id"]: g for g in generations if isinstance(g, dict) and isinstance(g.get("id"), str)}
    assets_by_id = {a["id"]: a for a in assets if isinstance(a, dict) and isinstance(a.get("id"), str)}
    priorities: dict[str, Counter[int]] = defaultdict(Counter)
    for generation_id, generation in generations_by_id.items():
        if isinstance(generation.get("yearEnd"), int) and generation["yearStart"] > generation["yearEnd"]:
            findings.append(f"{generation_id}: yearStart must not exceed yearEnd")
        ids = {name: {item.get("id") for item in generation.get(name, []) if isinstance(item, dict)} for name in ("trims", "wheels", "colors")}
        for default, collection in (("defaultTrimID", "trims"), ("defaultWheelID", "wheels"), ("defaultColorID", "colors")):
            if generation.get(default) not in ids[collection]:
                findings.append(f"{generation_id}: {default} is not declared")
        if isinstance(generation.get("model"), str) and isinstance(generation.get("matcherPriority"), int):
            priorities[generation["model"]][generation["matcherPriority"]] += 1
        fallback = generation.get("legacyFallback", {})
        fallback_asset = assets_by_id.get(fallback.get("assetID")) if isinstance(fallback, dict) else None
        if not isinstance(fallback_asset, dict) or fallback_asset.get("generationID") != generation_id or fallback_asset.get("path") != fallback.get("path"):
            findings.append(f"{generation_id}: legacy fallback must match its catalog asset")
    for model, counts in priorities.items():
        for priority, count in counts.items():
            if count > 1:
                findings.append(f"ambiguous matcher priority: {model} priority {priority}")
    paths = set()
    assets_by_key: dict[tuple[object, ...], list[dict[str, Any]]] = defaultdict(list)
    for asset in assets:
        if not isinstance(asset, dict):
            findings.append("catalog: asset record must be an object")
            continue
        asset_id, path_value = asset.get("id", "<unnamed>"), relative_image_path(asset.get("path"))
        generation = generations_by_id.get(asset.get("generationID"))
        if generation is None:
            findings.append(f"{asset_id}: references missing generation")
        else:
            valid = [asset.get(field) in {item.get("id") for item in generation.get(collection, []) if isinstance(item, dict)} for field, collection in (("trimID", "trims"), ("wheelID", "wheels"), ("colorID", "colors"))]
            if not all(valid):
                findings.append(f"{asset_id}: references an unsupported generation variant")
        if path_value is None:
            findings.append(f"{asset_id}: path must be a PNG under CarImages")
            continue
        paths.add(path_value)
        status = asset.get("reviewStatus")
        if status == "legacy":
            if path_value not in inventory:
                findings.append(f"{asset_id}: legacy asset is not an inventory member")
        elif status != "reviewed":
            findings.append(f"{asset_id}: reviewStatus must be legacy or reviewed")
        key = tuple(asset.get(field) for field in ("generationID", "trimID", "wheelID", "colorID"))
        assets_by_key[key].append(asset)
    for key, matching_assets in assets_by_key.items():
        if len(matching_assets) <= 1:
            continue
        generation = generations_by_id.get(key[0])
        fallback = generation.get("legacyFallback", {}) if isinstance(generation, dict) else {}
        is_reviewed_replacement_pair = (
            len(matching_assets) == 2
            and {asset.get("reviewStatus") for asset in matching_assets} == {"legacy", "reviewed"}
            and any(
                asset.get("reviewStatus") == "legacy"
                and asset.get("id") == fallback.get("assetID")
                and asset.get("path") == fallback.get("path")
                for asset in matching_assets
            )
        )
        if not is_reviewed_replacement_pair:
            findings.append(f"duplicate catalog asset key: {key}")
    return findings, [a for a in assets if isinstance(a, dict)], paths


def audit_repository(root: Path) -> list[str]:
    try:
        catalog = json.loads((resources(root) / "VehicleImageCatalog.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return [f"catalog: invalid JSON ({error})"]
    inventory, findings = load_inventory(root)
    if not isinstance(catalog, dict):
        return findings + ["catalog: root must be an object"]
    catalog_findings, assets, catalog_paths = validate_catalog(catalog, inventory)
    findings.extend(catalog_findings)
    records, review_errors = review_records(root / "docs/vehicle-image-review.md")
    findings.extend(review_errors)
    reviewed_ids = {asset.get("id") for asset in assets if asset.get("reviewStatus") == "reviewed"}
    for asset_id in records:
        if asset_id not in reviewed_ids:
            findings.append(f"review: stale asset row {asset_id}")
    for asset in assets:
        asset_id, path_value = asset.get("id", "<unnamed>"), relative_image_path(asset.get("path"))
        if path_value is None:
            continue
        file, error = contained_file(root, path_value)
        if error:
            findings.append(f"{asset_id}: {error}")
            continue
        dimensions = inventory[path_value] if asset.get("reviewStatus") == "legacy" and path_value in inventory else MASTER_DIMENSIONS
        image, chunks, image_findings = inspect_png(file, str(asset_id), dimensions)
        findings.extend(image_findings)
        if asset.get("reviewStatus") == "reviewed":
            findings.extend(review_findings(str(asset_id), records.get(str(asset_id))))
            if image is not None:
                bbox = image.getchannel("A").getbbox()
                if bbox is None:
                    findings.append(f"{asset_id}: image must contain non-transparent pixels")
                else:
                    left, top, right, bottom = bbox
                    values = (left / image.width, top / image.height, right / image.width, bottom / image.height)
                    if any(not in_range(value, NORMALIZED_BOUNDS[name]) for name, value in zip(("left", "top", "right", "bottom"), values)):
                        findings.append(f"{asset_id}: normalized bounding box is outside the framing tolerance")
                    if not in_range(values[3], BASELINE_RANGE):
                        findings.append(f"{asset_id}: baseline is outside the tolerance")
                    if edge_contaminated(image):
                        findings.append(f"{asset_id}: transparent-edge contamination exceeds the threshold")
                if chunks - SAFE_PNG_CHUNKS:
                    findings.append(f"{asset_id}: PNG metadata must be stripped")
    for path_value, dimensions in inventory.items():
        file, error = contained_file(root, path_value)
        label = f"legacy inventory member {path_value}"
        if error:
            findings.append(f"{label}: {error}")
        elif file is not None:
            _, _, image_findings = inspect_png(file, label, dimensions)
            findings.extend(image_findings)
    image_directory = resources(root) / "CarImages"
    if image_directory.is_dir():
        allowed = catalog_paths | set(inventory)
        for path in image_directory.rglob("*"):
            if not path.is_file() or path.suffix.lower() != ".png":
                continue
            relative = path.relative_to(resources(root)).as_posix()
            if relative not in allowed:
                findings.append(f"unreferenced image: {relative}")
    return sorted(set(findings))


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate bundled vehicle image assets and their catalog.")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent, help="repository root")
    args = parser.parse_args()
    findings = audit_repository(args.root.resolve())
    for finding in findings:
        print(finding)
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
