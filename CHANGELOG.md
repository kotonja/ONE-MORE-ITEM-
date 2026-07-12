# Changelog

## 2026-07-12 — Phase 01 review corrections

- Made repository-to-Studio synchronization clean-place reproducible with parent-first folder operations, manifest validation, safe Script preparation, idempotent updates, and visible non-destructive conflict errors.
- Added a dependency-free Node smoke test covering source existence, operation order and counts, managed-path uniqueness, parent guarantees, non-destructive commands, path privacy, and byte-deterministic output.
- Added shared finite-integer validation at public grid boundaries and derived `BOX_CAPACITY` from the configured dimensions.
- Added focused clone, occupied-snapshot, enumeration-order, malformed/non-finite, irregular top-entry, and capacity-product contracts while retaining every original test.
- Verified a genuinely clean Baseplate twice with `7/7` folders, `10/10` scripts, `10/10` exact source matches, and zero duplicate managed instances.
- Verified 15 suites and 69 tests in the intended place: 69 passed, 0 failed, including 1,000 fixed-seed fuzz cases.
- Verified Save to File and read-only reopening preserve the synchronized hierarchy and pass all 69 tests again.
- Confirmed Roblox cloud persistence remains blocked: both normal `Ctrl+S` retries ended with `Internal server error.`; permanent Workspace and StarterGui construction remains blocked until normal saving is reliable.

## 2026-07-12 — Phase 01: Grid and Placement Foundation

- Established permanent project, Git, Studio authoring, testing, and documentation rules.
- Documented the frozen 5 × 5 × 4 integer-grid packing direction and Phase 01 architecture.
- Added eleven development shapes, validated normalized Y-axis rotations, and removed symmetric duplicates.
- Added atomic occupancy, collision/bounds checks, rigid top-entry auto-drop, deterministic legal-placement enumeration, offerability, fill accounting, and difficulty classification.
- Added 46 deterministic Studio tests across 10 suites, including 1,000 fixed-seed fuzz cases and a non-gating enumeration benchmark.
- Added a manifest-driven repository-to-Studio synchronization workflow with generated temporary Command Bar and blueprint artifacts.
