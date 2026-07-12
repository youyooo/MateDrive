#!/usr/bin/env python3
import json
import os
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

from PIL import Image, PngImagePlugin
import validate_vehicle_images as validator


SCRIPT = Path(__file__).with_name("validate_vehicle_images.py")
REVIEW_HEADERS = [
    "Asset ID", "Generation", "Trim", "Lamps/Fascia", "Brightwork", "Wheel",
    "Caliper", "Paint", "Perspective", "Scale", "Shadow", "Edge", "Reviewer",
    "Date", "Source Reference",
]


def png_chunk(chunk_type: bytes, chunk_data: bytes) -> bytes:
    return (
        struct.pack(">I", len(chunk_data))
        + chunk_type
        + chunk_data
        + struct.pack(">I", zlib.crc32(chunk_type + chunk_data) & 0xFFFFFFFF)
    )


class VehicleImageValidatorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        self.resources = self.root / "MateDroidIOS/Resources"
        self.images = self.resources / "CarImages"
        self.images.mkdir(parents=True)
        self.inventory = self.root / "scripts/data/vehicle_image_legacy_inventory.json"

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def reviewed_asset(self, **overrides: object) -> dict[str, object]:
        asset: dict[str, object] = {
            "id": "reviewed-car",
            "generationID": "model-3",
            "trimID": "performance",
            "wheelID": "uberturbine-20",
            "colorID": "pearl-white",
            "path": "CarImages/vehicle_model-3_performance_midnight-silver_uberturbine-20.png",
            "reviewStatus": "reviewed",
        }
        asset.update(overrides)
        return asset

    def legacy_asset(self, **overrides: object) -> dict[str, object]:
        asset: dict[str, object] = {
            "id": "legacy-car",
            "generationID": "model-3",
            "trimID": "performance",
            "wheelID": "uberturbine-20",
            "colorID": "midnight-silver",
            "path": "CarImages/m3_PPSW_W32D.png",
            "reviewStatus": "legacy",
        }
        asset.update(overrides)
        return asset

    def generation(self, **overrides: object) -> dict[str, object]:
        generation: dict[str, object] = {
            "id": "model-3",
            "model": "Model 3",
            "aliases": ["model 3"],
            "yearStart": 2021,
            "matcherPriority": 10,
            "localizationKey": "vehicle.generation.model-3",
            "trims": [{"id": "performance", "aliases": [], "localizationKey": "vehicle.trim.performance"}],
            "wheels": [{"id": "uberturbine-20", "aliases": [], "localizationKey": "vehicle.wheel.uberturbine-20"}],
            "colors": [
                {"id": "midnight-silver", "aliases": [], "localizationKey": "vehicle.color.midnight-silver"},
                {"id": "pearl-white", "aliases": [], "localizationKey": "vehicle.color.pearl-white"},
            ],
            "defaultTrimID": "performance",
            "defaultWheelID": "uberturbine-20",
            "defaultColorID": "midnight-silver",
            "legacyFallback": {"assetID": "legacy-car", "path": "CarImages/m3_PPSW_W32D.png"},
        }
        generation.update(overrides)
        return generation

    def write_catalog(
        self,
        assets: list[dict[str, object]],
        generations: list[dict[str, object]] | None = None,
        inventory: list[dict[str, object]] | None = None,
    ) -> None:
        catalog = {
            "schemaVersion": 1,
            "generations": generations or [self.generation()],
            "assets": assets,
        }
        (self.resources / "VehicleImageCatalog.json").write_text(
            json.dumps(catalog), encoding="utf-8"
        )
        if inventory is None:
            inventory = [
                self.inventory_entry(asset)
                for asset in assets
                if asset.get("reviewStatus") == "legacy"
            ]
        self.write_inventory(inventory)

    def inventory_entry(self, asset: dict[str, object]) -> dict[str, object]:
        dimensions = asset.get("optimizedDimensions", {"width": 720, "height": 405})
        return {"path": asset["path"], **dimensions}

    def write_inventory(self, assets: list[dict[str, object]]) -> None:
        self.inventory.parent.mkdir(parents=True, exist_ok=True)
        self.inventory.write_text(
            json.dumps({"schemaVersion": 1, "assets": assets}),
            encoding="utf-8",
        )

    def write_image(
        self,
        name: str,
        *,
        size: tuple[int, int] = (1536, 768),
        mode: str = "RGBA",
        bounds: tuple[int, int, int, int] | None = None,
        metadata: bool = False,
        contaminated_edge: bool = False,
        edge_candidates: int = 0,
        contaminated_candidates: int = 0,
        contaminated_candidate_alpha: int = 16,
        high_alpha_edge_candidates: int = 0,
        high_alpha_contaminated_candidates: int = 0,
        high_alpha_mixed_neighbor_candidates: int = 0,
        soft_shadow_pixels: int = 0,
    ) -> None:
        image = Image.new(mode, size, (0, 0, 0, 0) if mode == "RGBA" else (32, 32, 32))
        if mode == "RGBA":
            left, top, right, bottom = bounds or (240, 240, 1296, 590)
            image.paste((80, 80, 80, 255), (left, top, right, bottom))
            if contaminated_edge:
                for y in range(top, bottom):
                    image.putpixel((left - 1, y), (255, 255, 255, 16))
            for offset in range(edge_candidates):
                color = (255, 255, 255, contaminated_candidate_alpha) if offset < contaminated_candidates else (80, 80, 80, 16)
                image.putpixel((left - 1, top + offset), color)
            for offset in range(high_alpha_edge_candidates):
                y = top + 1 + offset * 3
                inward = (80, 80, 80, 255) if offset < high_alpha_contaminated_candidates else (220, 220, 220, 255)
                for inward_y in range(y - 1, y + 2):
                    image.putpixel((left, inward_y), inward)
                image.putpixel((left - 1, y), (230, 230, 230, 201))
            for offset in range(high_alpha_mixed_neighbor_candidates):
                x, y = left - 1, top + 1 + offset * 3
                for support_x, support_y in ((x - 1, y - 1), (x - 1, y + 1), (x, y + 1)):
                    image.putpixel((support_x, support_y), (230, 230, 230, 255))
                for inward_y in range(y - 1, y + 2):
                    image.putpixel((x + 1, inward_y), (225, 225, 225, 255))
                image.putpixel((x, y - 1), (40, 40, 40, 255))
                image.putpixel((x, y), (230, 230, 230, 201))
            shadow_y = min(size[1] - 1, bottom + 20)
            for offset in range(soft_shadow_pixels):
                shadow_width = max(1, right - left - 40)
                x = left + 20 + (offset % shadow_width)
                y = shadow_y + (offset // shadow_width)
                if y >= size[1]:
                    break
                image.putpixel((x, y), (80, 80, 80, 16))
        png_info = PngImagePlugin.PngInfo() if metadata else None
        if png_info:
            png_info.add_text("Comment", "must be stripped")
        path = self.images / name
        path.parent.mkdir(parents=True, exist_ok=True)
        image.save(path, format="PNG", pnginfo=png_info)

    def insert_before_idat(self, name: str, *chunks: bytes) -> None:
        path = self.images / name
        data = path.read_bytes()
        offset = data.index(b"IDAT") - 4
        path.write_bytes(data[:offset] + b"".join(chunks) + data[offset:])

    def write_review_record(
        self,
        asset_id: str = "reviewed-car",
        *,
        headers: list[str] | None = None,
        values: dict[str, str] | None = None,
        extra_rows: list[dict[str, str]] | None = None,
    ) -> None:
        review = self.root / "docs/vehicle-image-review.md"
        review.parent.mkdir(parents=True, exist_ok=True)
        headers = headers or REVIEW_HEADERS
        values = {
            "Asset ID": asset_id,
            "Generation": "Pass",
            "Trim": "Pass",
            "Lamps/Fascia": "Pass",
            "Brightwork": "Pass",
            "Wheel": "Pass",
            "Caliper": "Pass",
            "Paint": "Pass",
            "Perspective": "Pass",
            "Scale": "Pass",
            "Shadow": "Pass",
            "Edge": "Pass",
            "Reviewer": "QA Reviewer",
            "Date": "2026-07-13",
            "Source Reference": "synthetic reference",
            **(values or {}),
        }
        rows = [values, *(extra_rows or [])]
        lines = ["## Reviewed Assets", "", "| " + " | ".join(headers) + " |", "| " + " | ".join("---" for _ in headers) + " |"]
        lines.extend("| " + " | ".join(row.get(header, "") for header in headers) + " |" for row in rows)
        review.write_text(
            "\n".join(lines) + "\n",
            encoding="utf-8",
        )

    def run_validator(self) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--root", str(self.root)],
            capture_output=True,
            text=True,
            check=False,
        )

    def assert_fails(self, expected: str) -> None:
        result = self.run_validator()
        self.assertEqual(result.returncode, 1, msg=result.stderr or result.stdout)
        self.assertIn(expected, result.stdout)
        self.assertEqual(result.stderr, "")

    def test_accepts_reviewed_master_and_catalog_declared_legacy_size(self) -> None:
        legacy = self.legacy_asset(
            optimizedDimensions={"width": 100, "height": 50},
        )
        self.write_catalog([self.reviewed_asset(), legacy])
        self.write_image("vehicle_model-3_performance_midnight-silver_uberturbine-20.png")
        self.write_image("m3_PPSW_W32D.png", size=(100, 50), bounds=(15, 15, 85, 38))
        self.write_review_record()

        result = self.run_validator()

        self.assertEqual(result.returncode, 0, msg=result.stderr or result.stdout)
        self.assertEqual(result.stdout, "")
        self.assertEqual(result.stderr, "")

    def test_rejects_wrong_reviewed_master_dimensions(self) -> None:
        self.write_catalog([self.reviewed_asset(), self.legacy_asset()])
        self.write_image("vehicle_model-3_performance_midnight-silver_uberturbine-20.png", size=(1535, 768))
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record()

        self.assert_fails("reviewed-car: dimensions must be 1536x768")

    def test_rejects_asset_without_alpha_channel(self) -> None:
        self.write_catalog([self.reviewed_asset(), self.legacy_asset()])
        self.write_image("vehicle_model-3_performance_midnight-silver_uberturbine-20.png", mode="RGB")
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record()

        self.assert_fails("reviewed-car: PNG must contain an alpha channel")

    def test_rejects_excessive_transparent_edge_contamination(self) -> None:
        self.write_catalog([self.reviewed_asset(), self.legacy_asset()])
        self.write_image(
            "vehicle_model-3_performance_midnight-silver_uberturbine-20.png",
            contaminated_edge=True,
        )
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record()

        self.assert_fails("reviewed-car: transparent-edge contamination")

    def test_rejects_two_percent_high_opacity_light_rim_contamination(self) -> None:
        name = "vehicle_model-3_performance_midnight-silver_uberturbine-20.png"
        self.write_catalog([self.reviewed_asset(), self.legacy_asset()])
        self.write_image(
            name,
            high_alpha_edge_candidates=100,
            high_alpha_contaminated_candidates=2,
        )
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record()

        with Image.open(self.images / name) as image:
            low_alpha_ratio, high_alpha_ratio = validator.edge_contamination_ratios(image.convert("RGBA"))
        self.assertEqual(low_alpha_ratio, 0)
        self.assertEqual(high_alpha_ratio, 0.02)
        self.assert_fails("reviewed-car: transparent-edge contamination")

    def test_accepts_exact_one_percent_high_opacity_rim_boundary(self) -> None:
        name = "vehicle_model-3_performance_midnight-silver_uberturbine-20.png"
        self.write_catalog([self.reviewed_asset(), self.legacy_asset()])
        self.write_image(
            name,
            high_alpha_edge_candidates=100,
            high_alpha_contaminated_candidates=1,
        )
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record()

        with Image.open(self.images / name) as image:
            _, high_alpha_ratio = validator.edge_contamination_ratios(image.convert("RGBA"))
        result = self.run_validator()

        self.assertEqual(validator.HIGH_ALPHA_EDGE_CONTAMINATION_RATIO, 0.01)
        self.assertEqual(high_alpha_ratio, 0.01)
        self.assertEqual(result.returncode, 0, msg=result.stderr or result.stdout)

    def test_accepts_high_opacity_silver_edge_when_inward_color_is_similar(self) -> None:
        name = "vehicle_model-3_performance_midnight-silver_uberturbine-20.png"
        self.write_catalog([self.reviewed_asset(), self.legacy_asset()])
        self.write_image(
            name,
            high_alpha_edge_candidates=100,
        )
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record()

        with Image.open(self.images / name) as image:
            _, high_alpha_ratio = validator.edge_contamination_ratios(image.convert("RGBA"))
        result = self.run_validator()

        self.assertEqual(high_alpha_ratio, 0)
        self.assertEqual(result.returncode, 0, msg=result.stderr or result.stdout)

    def test_accepts_silver_edge_with_unrelated_orthogonal_dark_neighbor(self) -> None:
        name = "vehicle_model-3_performance_midnight-silver_uberturbine-20.png"
        self.write_catalog([self.reviewed_asset(), self.legacy_asset()])
        self.write_image(
            name,
            high_alpha_mixed_neighbor_candidates=100,
        )
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record()

        with Image.open(self.images / name) as image:
            _, high_alpha_ratio = validator.edge_contamination_ratios(image.convert("RGBA"))
        result = self.run_validator()

        self.assertEqual(high_alpha_ratio, 0)
        self.assertEqual(result.returncode, 0, msg=result.stderr or result.stdout)

    def test_rejects_normalized_bounding_box_drift(self) -> None:
        self.write_catalog([self.reviewed_asset(), self.legacy_asset()])
        self.write_image(
            "vehicle_model-3_performance_midnight-silver_uberturbine-20.png",
            bounds=(20, 100, 700, 500),
        )
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record()

        self.assert_fails("reviewed-car: normalized bounding box")

    def test_rejects_baseline_drift(self) -> None:
        self.write_catalog([self.reviewed_asset(), self.legacy_asset()])
        self.write_image(
            "vehicle_model-3_performance_midnight-silver_uberturbine-20.png",
            bounds=(240, 240, 1296, 700),
        )
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record()

        self.assert_fails("reviewed-car: baseline")

    def test_rejects_duplicate_catalog_asset_key(self) -> None:
        duplicate = self.reviewed_asset(
            id="reviewed-car-copy",
            path="CarImages/vehicle_model-3_performance_midnight-silver_copy.png",
        )
        self.write_catalog([self.reviewed_asset(), duplicate, self.legacy_asset()])
        self.write_image("vehicle_model-3_performance_midnight-silver_uberturbine-20.png")
        self.write_image("vehicle_model-3_performance_midnight-silver_copy.png")
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record()

        self.assert_fails("duplicate catalog asset key")

    def test_accepts_reviewed_replacement_with_same_key_as_declared_legacy_fallback(self) -> None:
        legacy = self.legacy_asset(colorID="pearl-white")
        self.write_catalog([self.reviewed_asset(), legacy])
        self.write_image("vehicle_model-3_performance_midnight-silver_uberturbine-20.png")
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record()

        result = self.run_validator()

        self.assertEqual(result.returncode, 0, msg=result.stderr or result.stdout)
        self.assertEqual(result.stdout, "")
        self.assertEqual(result.stderr, "")

    def test_rejects_ambiguous_generation_matcher_priority(self) -> None:
        second_generation = self.generation(
            id="model-3-second",
            legacyFallback={"assetID": "legacy-car-second", "path": "CarImages/m3_second.png"},
        )
        second_asset = self.legacy_asset(
            id="legacy-car-second",
            generationID="model-3-second",
            path="CarImages/m3_second.png",
        )
        self.write_catalog([self.legacy_asset(), second_asset], [self.generation(), second_generation])
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_image("m3_second.png", size=(720, 405), bounds=(100, 100, 620, 310))

        self.assert_fails("ambiguous matcher priority")

    def test_rejects_asset_variant_not_declared_by_its_generation(self) -> None:
        invalid_asset = self.reviewed_asset(colorID="not-a-generation-color")
        self.write_catalog([invalid_asset, self.legacy_asset()])
        self.write_image("vehicle_model-3_performance_midnight-silver_uberturbine-20.png")
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record()

        self.assert_fails("reviewed-car: references an unsupported generation variant")

    def test_rejects_legacy_fallback_that_does_not_match_its_asset_record(self) -> None:
        mismatched_generation = self.generation(
            legacyFallback={"assetID": "legacy-car", "path": "CarImages/other.png"}
        )
        self.write_catalog([self.reviewed_asset(), self.legacy_asset()], [mismatched_generation])
        self.write_image("vehicle_model-3_performance_midnight-silver_uberturbine-20.png")
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record()

        self.assert_fails("model-3: legacy fallback must match its catalog asset")

    def test_rejects_new_vehicle_filename_marked_as_legacy(self) -> None:
        mislabeled_asset = self.reviewed_asset(reviewStatus="legacy")
        self.write_catalog(
            [mislabeled_asset, self.legacy_asset()],
            inventory=[self.inventory_entry(self.legacy_asset())],
        )
        self.write_image(
            "vehicle_model-3_performance_midnight-silver_uberturbine-20.png",
            size=(720, 405),
            bounds=(100, 100, 620, 310),
        )
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))

        self.assert_fails("reviewed-car: legacy asset is not an inventory member")

    def test_rejects_catalog_asset_with_missing_file(self) -> None:
        self.write_catalog([self.reviewed_asset(), self.legacy_asset()])
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record()

        self.assert_fails("reviewed-car: missing file")

    def test_rejects_unreferenced_new_vehicle_asset(self) -> None:
        self.write_catalog([self.reviewed_asset(), self.legacy_asset()])
        self.write_image("vehicle_model-3_performance_midnight-silver_uberturbine-20.png")
        self.write_image("vehicle_unreferenced.png")
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record()

        self.assert_fails("unreferenced image: CarImages/vehicle_unreferenced.png")

    def test_rejects_png_metadata_on_reviewed_asset(self) -> None:
        self.write_catalog([self.reviewed_asset(), self.legacy_asset()])
        self.write_image("vehicle_model-3_performance_midnight-silver_uberturbine-20.png", metadata=True)
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record()

        self.assert_fails("reviewed-car: PNG metadata must be stripped")

    def test_rejects_reviewed_asset_without_human_review_record(self) -> None:
        self.write_catalog([self.reviewed_asset(), self.legacy_asset()])
        self.write_image("vehicle_model-3_performance_midnight-silver_uberturbine-20.png")
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))

        self.assert_fails("reviewed-car: missing human review record")

    def test_rejects_unlisted_short_named_image(self) -> None:
        self.write_catalog([self.reviewed_asset(), self.legacy_asset()])
        self.write_image("vehicle_model-3_performance_midnight-silver_uberturbine-20.png")
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_image("short-named-new.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record()

        self.assert_fails("unreferenced image: CarImages/short-named-new.png")

    def test_rejects_short_named_legacy_catalog_record_not_in_inventory(self) -> None:
        legacy = self.legacy_asset(id="short-legacy", path="CarImages/short-named-new.png")
        generation = self.generation(
            legacyFallback={"assetID": "short-legacy", "path": "CarImages/short-named-new.png"}
        )
        self.write_catalog([self.reviewed_asset(), legacy], [generation], inventory=[])
        self.write_image("vehicle_model-3_performance_midnight-silver_uberturbine-20.png")
        self.write_image("short-named-new.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record()

        self.assert_fails("short-legacy: legacy asset is not an inventory member")

    def test_validates_unreferenced_legacy_inventory_member(self) -> None:
        detached = {"path": "CarImages/legacy-unreferenced.png", "width": 720, "height": 405}
        self.write_catalog(
            [self.reviewed_asset(), self.legacy_asset()],
            inventory=[self.inventory_entry(self.legacy_asset()), detached],
        )
        self.write_image("vehicle_model-3_performance_midnight-silver_uberturbine-20.png")
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_image("legacy-unreferenced.png", size=(720, 405), mode="RGB")
        self.write_review_record()

        self.assert_fails("legacy inventory member CarImages/legacy-unreferenced.png: PNG must contain an alpha channel")

    def test_rejects_abbreviated_review_table_header(self) -> None:
        self.write_catalog([self.reviewed_asset(), self.legacy_asset()])
        self.write_image("vehicle_model-3_performance_midnight-silver_uberturbine-20.png")
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record(headers=["Asset ID", "Reviewer", "Date", "Source Reference"])

        self.assert_fails("review: Reviewed Assets table must use the complete header")

    def test_rejects_review_row_with_non_affirmative_checklist_value(self) -> None:
        self.write_catalog([self.reviewed_asset(), self.legacy_asset()])
        self.write_image("vehicle_model-3_performance_midnight-silver_uberturbine-20.png")
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record(values={"Generation": ""})

        self.assert_fails("reviewed-car: review Generation must be affirmative")

    def test_rejects_duplicate_review_rows(self) -> None:
        self.write_catalog([self.reviewed_asset(), self.legacy_asset()])
        self.write_image("vehicle_model-3_performance_midnight-silver_uberturbine-20.png")
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record(extra_rows=[{"Asset ID": "reviewed-car"}])

        self.assert_fails("review: duplicate asset row reviewed-car")

    def test_rejects_stale_review_row(self) -> None:
        self.write_catalog([self.reviewed_asset(), self.legacy_asset()])
        self.write_image("vehicle_model-3_performance_midnight-silver_uberturbine-20.png")
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record(extra_rows=[{"Asset ID": "removed-review"}])

        self.assert_fails("review: stale asset row removed-review")

    def test_rejects_three_percent_fringe_even_with_large_soft_shadow(self) -> None:
        self.write_catalog([self.reviewed_asset(), self.legacy_asset()])
        self.write_image(
            "vehicle_model-3_performance_midnight-silver_uberturbine-20.png",
            edge_candidates=100,
            contaminated_candidates=3,
            soft_shadow_pixels=10000,
        )
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record()

        self.assert_fails("reviewed-car: transparent-edge contamination")

    def test_accepts_exact_two_percent_edge_contamination_boundary(self) -> None:
        self.write_catalog([self.reviewed_asset(), self.legacy_asset()])
        self.write_image(
            "vehicle_model-3_performance_midnight-silver_uberturbine-20.png",
            edge_candidates=100,
            contaminated_candidates=2,
            soft_shadow_pixels=10000,
        )
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record()

        result = self.run_validator()

        self.assertEqual(result.returncode, 0, msg=result.stderr or result.stdout)

    def test_accepts_sparse_nearly_transparent_rgb_residue_by_opacity_weight(self) -> None:
        name = "vehicle_model-3_performance_midnight-silver_uberturbine-20.png"
        self.write_catalog([self.reviewed_asset(), self.legacy_asset()])
        self.write_image(
            name,
            edge_candidates=100,
            contaminated_candidates=3,
            contaminated_candidate_alpha=1,
        )
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record()

        with Image.open(self.images / name) as image:
            low_alpha_ratio, _ = validator.edge_contamination_ratios(image.convert("RGBA"))
        result = self.run_validator()

        self.assertEqual(low_alpha_ratio, 3 / (3 + 97 * 16))
        self.assertEqual(result.returncode, 0, msg=result.stderr or result.stdout)

    def test_rejects_symlinked_catalog_asset(self) -> None:
        self.write_catalog([self.reviewed_asset(), self.legacy_asset()])
        outside = self.root / "outside.png"
        image = Image.new("RGBA", (1536, 768), (0, 0, 0, 0))
        image.paste((80, 80, 80, 255), (240, 240, 1296, 590))
        image.save(outside)
        os.symlink(outside, self.images / "vehicle_model-3_performance_midnight-silver_uberturbine-20.png")
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record()

        self.assert_fails("reviewed-car: asset must be a regular file inside CarImages")

    def test_rejects_png_with_trailing_bytes_after_iend(self) -> None:
        self.write_catalog([self.reviewed_asset(), self.legacy_asset()])
        self.write_image("vehicle_model-3_performance_midnight-silver_uberturbine-20.png")
        path = self.images / "vehicle_model-3_performance_midnight-silver_uberturbine-20.png"
        path.write_bytes(path.read_bytes() + b"trailing bytes")
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record()

        self.assert_fails("reviewed-car: invalid PNG")

    def test_rejects_png_with_bad_chunk_crc(self) -> None:
        self.write_catalog([self.reviewed_asset(), self.legacy_asset()])
        self.write_image("vehicle_model-3_performance_midnight-silver_uberturbine-20.png")
        path = self.images / "vehicle_model-3_performance_midnight-silver_uberturbine-20.png"
        data = bytearray(path.read_bytes())
        data[29] ^= 0x01
        path.write_bytes(data)
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record()

        self.assert_fails("reviewed-car: invalid PNG")

    def test_rejects_unsupported_catalog_schema_version(self) -> None:
        self.write_catalog([self.reviewed_asset(), self.legacy_asset()])
        payload = json.loads((self.resources / "VehicleImageCatalog.json").read_text(encoding="utf-8"))
        payload["schemaVersion"] = 999
        (self.resources / "VehicleImageCatalog.json").write_text(json.dumps(payload), encoding="utf-8")
        self.write_image("vehicle_model-3_performance_midnight-silver_uberturbine-20.png")
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record()

        self.assert_fails("catalog: unsupported schemaVersion 999")

    def test_rejects_duplicate_generation_id(self) -> None:
        self.write_catalog([self.reviewed_asset(), self.legacy_asset()], [self.generation(), self.generation()])
        self.write_image("vehicle_model-3_performance_midnight-silver_uberturbine-20.png")
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record()

        self.assert_fails("duplicate catalog generation ID: model-3")

    def test_rejects_invalid_generation_year_range_and_default(self) -> None:
        invalid_generation = self.generation(yearEnd=2020, defaultWheelID="not-a-wheel")
        self.write_catalog([self.reviewed_asset(), self.legacy_asset()], [invalid_generation])
        self.write_image("vehicle_model-3_performance_midnight-silver_uberturbine-20.png")
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record()

        self.assert_fails("model-3: yearStart must not exceed yearEnd")
        self.assert_fails("model-3: defaultWheelID is not declared")

    def test_tolerance_bounds_and_baseline_are_inclusive_at_exact_limits(self) -> None:
        self.assertTrue(validator.in_range(0.10, validator.NORMALIZED_BOUNDS["left"]))
        self.assertTrue(validator.in_range(0.25, validator.NORMALIZED_BOUNDS["left"]))
        self.assertTrue(validator.in_range(0.72, validator.BASELINE_RANGE))
        self.assertTrue(validator.in_range(0.82, validator.BASELINE_RANGE))
        self.assertFalse(validator.in_range(0.099999, validator.NORMALIZED_BOUNDS["left"]))
        self.assertFalse(validator.in_range(0.820001, validator.BASELINE_RANGE))

    def test_rejects_unreferenced_uppercase_and_mixed_case_pngs(self) -> None:
        self.write_catalog([self.reviewed_asset(), self.legacy_asset()])
        self.write_image("vehicle_model-3_performance_midnight-silver_uberturbine-20.png")
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_image("short-name.PNG", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_image("mixed-name.PnG", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record()

        self.assert_fails("unreferenced image: CarImages/short-name.PNG")
        self.assert_fails("unreferenced image: CarImages/mixed-name.PnG")

    def test_rejects_near_prefix_review_affirmative_value(self) -> None:
        self.write_catalog([self.reviewed_asset(), self.legacy_asset()])
        self.write_image("vehicle_model-3_performance_midnight-silver_uberturbine-20.png")
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record(values={"Generation": "Passenger"})

        self.assert_fails("reviewed-car: review Generation must be affirmative")

    def test_rejects_symlinked_carimages_root(self) -> None:
        self.write_catalog([self.reviewed_asset(), self.legacy_asset()])
        outside = self.root / "outside-images"
        outside.mkdir()
        self.images.rmdir()
        os.symlink(outside, self.images, target_is_directory=True)
        self.write_image("vehicle_model-3_performance_midnight-silver_uberturbine-20.png")
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record()

        self.assert_fails("reviewed-car: CarImages directory must not be a symlink")

    def test_rejects_symlinked_intermediate_image_component(self) -> None:
        reviewed = self.reviewed_asset(path="CarImages/nested/reviewed.png")
        self.write_catalog([reviewed, self.legacy_asset()])
        (self.images / "actual").mkdir()
        self.write_image("actual/reviewed.png")
        os.symlink(self.images / "actual", self.images / "nested", target_is_directory=True)
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record()

        self.assert_fails("reviewed-car: image path contains a symlink component")

    def test_rejects_duplicate_plte_with_valid_crc(self) -> None:
        self.write_catalog([self.reviewed_asset(), self.legacy_asset()])
        self.write_image("vehicle_model-3_performance_midnight-silver_uberturbine-20.png")
        self.insert_before_idat(
            "vehicle_model-3_performance_midnight-silver_uberturbine-20.png",
            png_chunk(b"PLTE", b"\0\0\0"),
            png_chunk(b"PLTE", b"\0\0\0"),
        )
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record()

        self.assert_fails("reviewed-car: invalid PNG")

    def test_rejects_unknown_critical_png_chunk_with_valid_crc(self) -> None:
        self.write_catalog([self.reviewed_asset(), self.legacy_asset()])
        self.write_image("vehicle_model-3_performance_midnight-silver_uberturbine-20.png")
        self.insert_before_idat(
            "vehicle_model-3_performance_midnight-silver_uberturbine-20.png",
            png_chunk(b"ABCD", b""),
        )
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record()

        self.assert_fails("reviewed-car: invalid PNG")

    def test_reports_missing_asset_id_without_crashing(self) -> None:
        legacy = self.legacy_asset()
        del legacy["id"]
        self.write_catalog([self.reviewed_asset(), legacy])
        self.write_image("vehicle_model-3_performance_midnight-silver_uberturbine-20.png")
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record()

        self.assert_fails("catalog.assets[1].id: required string")

    def test_reports_missing_required_generation_field_without_crashing(self) -> None:
        generation = self.generation()
        del generation["model"]
        self.write_catalog([self.reviewed_asset(), self.legacy_asset()], [generation])
        self.write_image("vehicle_model-3_performance_midnight-silver_uberturbine-20.png")
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record()

        self.assert_fails("catalog.generations[0].model: required string")

    def test_reports_wrong_required_field_type_without_crashing(self) -> None:
        generation = self.generation(yearStart="2021")
        self.write_catalog([self.reviewed_asset(), self.legacy_asset()], [generation])
        self.write_image("vehicle_model-3_performance_midnight-silver_uberturbine-20.png")
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record()

        self.assert_fails("catalog.generations[0].yearStart: required integer")

    def test_reports_non_object_inventory_root_without_crashing(self) -> None:
        self.write_catalog([self.reviewed_asset(), self.legacy_asset()])
        self.inventory.write_text("[]", encoding="utf-8")
        self.write_image("vehicle_model-3_performance_midnight-silver_uberturbine-20.png")
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record()

        self.assert_fails("legacy inventory: root must be an object")

    def test_rejects_unsupported_legacy_inventory_schema_version(self) -> None:
        self.write_catalog([self.reviewed_asset(), self.legacy_asset()])
        inventory = json.loads(self.inventory.read_text(encoding="utf-8"))
        inventory["schemaVersion"] = 2
        self.inventory.write_text(json.dumps(inventory), encoding="utf-8")
        self.write_image("vehicle_model-3_performance_midnight-silver_uberturbine-20.png")
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record()

        self.assert_fails("legacy inventory: unsupported schemaVersion 2")

    def test_rejects_boolean_legacy_inventory_dimensions(self) -> None:
        legacy_entry = self.inventory_entry(self.legacy_asset())
        legacy_entry["width"] = True
        self.write_catalog([self.reviewed_asset(), self.legacy_asset()], inventory=[legacy_entry])
        self.write_image("vehicle_model-3_performance_midnight-silver_uberturbine-20.png")
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.write_review_record()

        self.assert_fails("legacy inventory: entries require contained PNG paths and positive integer dimensions")

    def test_rejects_duplicate_gama_legacy_chunk_with_valid_crc(self) -> None:
        self.write_catalog([self.reviewed_asset(), self.legacy_asset()])
        self.write_image("vehicle_model-3_performance_midnight-silver_uberturbine-20.png")
        self.write_image("m3_PPSW_W32D.png", size=(720, 405), bounds=(100, 100, 620, 310))
        self.insert_before_idat(
            "m3_PPSW_W32D.png",
            png_chunk(b"gAMA", struct.pack(">I", 45455)),
            png_chunk(b"gAMA", struct.pack(">I", 45455)),
        )
        self.write_review_record()

        self.assert_fails("legacy inventory member CarImages/m3_PPSW_W32D.png: invalid PNG")


if __name__ == "__main__":
    unittest.main()
