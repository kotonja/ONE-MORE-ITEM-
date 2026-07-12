# Changelog

## 2026-07-12 — Phase 01: Grid and Placement Foundation

- Established permanent project, Git, Studio authoring, testing, and documentation rules.
- Documented the frozen 5 × 5 × 4 integer-grid packing direction and Phase 01 architecture.
- Added eleven development shapes, validated normalized Y-axis rotations, and removed symmetric duplicates.
- Added atomic occupancy, collision/bounds checks, rigid top-entry auto-drop, deterministic legal-placement enumeration, offerability, fill accounting, and difficulty classification.
- Added 46 deterministic Studio tests across 10 suites, including 1,000 fixed-seed fuzz cases and a non-gating enumeration benchmark.
- Added a manifest-driven repository-to-Studio synchronization workflow with generated temporary Command Bar and blueprint artifacts.
