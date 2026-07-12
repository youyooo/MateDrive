# Task 7 Review: Vehicle Image Catalog Validation

**Verdict: CHANGES_REQUESTED**

The supplied report records successful execution of the 15 fixture tests, the
repository validator, the script/technical Makefile gates, and `git diff --check`.
Those evidenced commands were not rerun for this review. Static review found the
following bypasses and validation gaps.

## Findings

### [P1] Legacy treatment is filename-based, not an explicit exemption

`scripts/validate_vehicle_images.py:175-180` rejects `legacy` only when the basename
starts with `vehicle_`, while `scripts/validate_vehicle_images.py:311-316` reports
unreferenced files only under that same naming convention. A newly added PNG can
therefore be named anything else and either be ignored entirely or cataloged as
`legacy`, bypassing 1536x768 dimensions, framing, baseline, edge, metadata, and human
review checks.

This is active in the current tree: there are 97 PNGs, 12 unique catalog paths, and
85 PNGs that the validator does not open or validate. The report's statement that the
validator passed against all 97 legacy PNGs is therefore inaccurate. Replace the
prefix heuristic with a checked-in, exact legacy inventory (path plus declared
optimized dimensions, or equivalent immutable catalog data), validate every
inventory member under legacy rules, and reject every image outside the catalog and
explicit inventory. Add fixtures proving that a short-named new file and a
short-named `legacy` catalog record both fail.

### [P1] A reviewed asset can pass without completing the human checklist

`scripts/validate_vehicle_images.py:82-104` recognizes any table containing only
`Asset ID`, `Reviewer`, `Date`, and `Source Reference`, then validates only those four
fields. The passing fixture at `scripts/test_validate_vehicle_images.py:110-119`
deliberately uses that abbreviated table. Consequently, every Generation through
Edge checklist result can be absent while the asset is accepted as reviewed.

Require the complete documented header and an affirmative, non-empty value for each
checklist field, plus reviewer, valid date, and source-reference note. Reject duplicate
asset rows and stale review rows that do not map to a reviewed catalog asset. Add
fixtures for an incomplete row, a duplicate row, and an abbreviated table.

### [P2] Soft-shadow pixels can dilute edge contamination below the threshold

`scripts/validate_vehicle_images.py:224-244` increments `edge_pixels` for every pixel
with alpha 1-64 before determining whether it is an object-edge candidate adjacent to
opaque content. A large legitimate soft shadow can therefore become the denominator
and let a substantial white/dark fringe fall below 2%. The existing contamination
fixture contains no shadow, so it cannot detect this bypass.

Define the denominator from actual edge candidates (or use a documented connected
edge/matte metric), then add fixtures combining a valid soft shadow with a failing
fringe. Include exact pass/fail boundary cases for the 2% ratio and the declared
bounds/baseline limits.

### [P2] Lexical paths and the custom PNG scan do not establish a contained, complete PNG

`scripts/validate_vehicle_images.py:43-49` rejects `..` but later follows symlinks via
`is_file()` and `Image.open()`, so a catalog entry under `CarImages/` can resolve
outside the repository. Resolve both the image root and candidate and require the
candidate to remain beneath the image root; reject symlinks if catalog assets must be
regular bundled files.

Separately, `scripts/validate_vehicle_images.py:52-68` returns immediately on the first
`IEND` without requiring it to be the final bytes, checking CRCs, or validating chunk
ordering. Appended data or ancillary chunks after `IEND` are invisible to the metadata
gate. Use Pillow's parsed PNG information plus a robust PNG parser/library, or harden
this scanner to validate CRC, legal ordering, zero-length/final `IEND`, and no trailing
data. Add malformed/trailing-data and symlink-escape fixtures.

### [P2] Catalog validation can disagree with the runtime catalog contract

`scripts/validate_vehicle_images.py:128-208` never checks `schemaVersion`, duplicate
generation IDs, generation defaults, or year ranges. Duplicate generation IDs are
silently collapsed by the dictionary comprehension. The runtime validator in
`MateDroidIOS/Core/Domain/VehicleImageCatalog.swift:29-90` rejects these states, so the
release image audit can report success for a catalog the app will reject.

Mirror the runtime structural invariants in this validator (or validate through one
shared generated schema) and add fixtures for schema mismatch and duplicate generation
IDs at minimum. This also keeps the claimed catalog audit from depending on unrelated
XCTest execution.

## Requirements Assessment

- Makefile wiring is present for `preflight`, `verify`, and
  `app-store-technical-audit`.
- The requested nominal fixtures exist, but the legacy, review-record, contamination,
  path, malformed-PNG, and catalog-consistency cases above leave the gates bypassable.
- The human checklist contains all requested categories, but its completion is not
  enforced.
- `task-7-report.md` is a tracked task artifact at repository root. This is
  non-blocking, but moving review evidence under a project documentation/review
  directory would keep the root focused on durable project entry points.
