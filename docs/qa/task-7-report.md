# Task 7 Report: Vehicle Image Catalog Validation

## Commits

- Initial implementation: `0399198` `test: validate vehicle image catalog assets`
- Review remediation: `737ec59` `fix: harden vehicle image catalog validation`
- Second-review remediation: `845e831` `fix: close vehicle image validator bypasses`
- Final inventory/PNG remediation: `43bee34` `fix: validate inventory and PNG singleton chunks`

## RED

- The first fixture suite failed because the validator did not exist.
- The review-remediation suite then recorded 14 failures for unlisted short-name files,
  inventory-only files, abbreviated/duplicate/stale review records, shadow-diluted
  fringe contamination, symlink/trailing PNG paths, schema mismatch, duplicate
  generations, and invalid generation defaults/ranges.
- The inclusive threshold test also failed until range comparison became an explicit,
  shared helper.
- The second-review suite then recorded 10 failures for uppercase/mixed-case PNG
  discovery, permissive affirmative prefixes, symlinked image roots/components,
  valid-CRC duplicate/critical PNG chunks, and malformed catalog/inventory JSON.
- The final fixtures recorded failures for unsupported inventory schema versions,
  boolean inventory dimensions, and a valid-CRC duplicate `gAMA` legacy chunk.

## GREEN

- `python3 scripts/test_validate_vehicle_images.py`: 44 fixture-driven tests passed.
- `python3 scripts/validate_vehicle_images.py`: passed with all 97 `CarImages` PNGs
  matched exactly by `scripts/data/vehicle_image_legacy_inventory.json`.
- `make test-scripts vehicle-privacy-audit app-store-technical-audit`: passed; the
  App Store technical audit reported zero blockers.
- `git diff --check`: passed.

## Threshold Rationale

- Reviewed masters must be 1536x768. Every legacy PNG is a checked-in inventory
  member with an explicit width and height; all 97 currently declare 720x405.
- Reviewed bounds are left 10-25%, top 15-45%, right 75-95%, and bottom 65-85%; the
  baseline is 72-82%. Both endpoints are inclusive and covered by tests.
- The 2% edge threshold uses only low-alpha pixels directly adjacent to opaque
  content. Detached low-alpha soft-shadow pixels do not dilute the denominator.
- PNG validation checks signature, chunk ordering, CRCs, terminal zero-length IEND,
  trailing bytes, ASCII chunk names, reserved bits, singleton chunks, unknown critical
  chunks, dimensions, and alpha. Reviewed PNGs must also have no ancillary metadata
  chunks beyond palette/transparency support.
- Every PNG suffix is discovered case-insensitively. `CarImages` is anchored below the
  resolved Resources directory and rejects root, component, and final-file symlinks.
- Review cells accept only `Pass`, `Approved`, or `Yes`, optionally followed by a
  colon note. Catalog and inventory JSON shape/type checks run before semantic checks.
- Legacy inventory requires the exact schema version and strict integer dimensions;
  booleans are rejected. Singleton PNG chunks include the core, color-management,
  physical-metadata, and standard extension singleton chunks such as `gAMA`, `cHRM`,
  `iCCP`, `pHYs`, `tIME`, `eXIf`, and `acTL`.

## Concerns

- Legacy images keep their historical ancillary PNG metadata for compatibility, but
  every inventory member is now opened and checked for containment, PNG integrity,
  alpha, and its declared dimensions.
- Automation cannot prove vehicle generation details, trim accuracy, source licensing,
  or visual judgement. The complete affirmative review table in
  `docs/vehicle-image-review.md` remains mandatory before `reviewStatus: reviewed`.
- The validator mirrors the current Swift Codable record shape. Schema changes require
  updating both the Swift model and the Python validator tests in the same change.
- The review evidence is retained at `docs/qa/task-7-review.md`; no Task 7 report or
  review artifact remains at the repository root.
