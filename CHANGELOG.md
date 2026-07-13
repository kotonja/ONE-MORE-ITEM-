# Changelog

## 2026-07-12 — Phase 02: Playable Station Vertical Slice

- Authored a deterministic, typed Edit-mode Phase 02 manifest covering 122 permanent instances, including the single 5-wide × 4-high × 5-deep packing station, permanent `StarterGui` HUD, six permanent RemoteEvents, development block template, and all Phase 02 client/server/shared scripts.
- Implemented the server-authoritative round state machine, station assignment, placement validation, deterministic legal-item sequence, session-only Tape calculations, stale-timer protection, request sequencing/rate limits, reset behavior, and temporary authoritative item proxies.
- Implemented the desktop Play Solo presentation: stable station camera, mouse and keyboard placement controls, local valid/invalid ghost feedback, authored HUD binding, item previews, physical control response, shipping/failure/reset motion, and character handling.
- Added Phase 02 deterministic Studio tests and expanded branch CI without removing Phase 01 validation. Fresh Studio Output passed Phase 01 at 69/69 and Phase 02 at 71/71; both dependency-free Node synchronization smoke tests also passed.
- Verified Play Solo failure on placement timeout, automatic timeout shipping for 15 Tape, a two-item One More shipment for 74 Tape, and preservation of the resulting 89-Tape session bank after a later failed round.
- Verified 122 permanent manifest instances, 26 Phase 02 scripts, six remotes, zero duplicate managed paths, and exact Studio source parity for all 36 Phase 01 and Phase 02 Luau sources before Play.
- Fixed multiplayer client startup against delayed descendant replication in `02b2aeb`, then passed a real two-player Studio run with one player assigned Station 01, one player shown the spectator state, and zero fresh game warnings or errors.
- Saved the original cloud place (`PlaceId 134193642444044`, `GameId 10493030248`), closed every Studio process, and reopened that same place from Roblox. Fresh bridge Studio session `d81093b5-5bae-4347-ae97-eb21720124ba` verified Edit mode, the exact managed trees with zero duplicates, and SHA-256 source parity for all 36 Luau sources.
- After the cloud reopen, fresh Studio Output passed Phase 01 at 69/69 and Phase 02 at 71/71, and a successful one-item shipment banked 15 Tape with a 15-Tape session total and zero fresh warnings or errors.
- Opened draft PR #2 from `codex/phase-02-playable-station`; the implementation-head push and pull-request workflows passed, and the final documentation-only head must also remain green before handoff.
- Kept Phase 03 and all later-phase systems out of scope.

## 2026-07-12 — Phase 01 persistence recovery and CI gate

- Added the dependency-free `Phase 01 Node Validation` GitHub Actions job for pull requests targeting `main` and pushes to `main` or `codex/phase-01-grid-foundation`.
- Diagnosed the earlier Studio cloud failures as two fixed-duration publish-request timeouts that surfaced as `Internal server error.`; the log exposed no HTTP status, Roblox error code, correlation ID, or response body.
- Created a temporary backup outside the repository, closed all duplicate Studio sessions, and restarted with exactly one Studio process.
- Successfully published/saved the original private cloud place, closed Studio, and reopened that place directly from Roblox.
- Verified the reopened place at `7/7` folders, `10/10` scripts, `10/10` exact source matches, zero duplicates, and 69/69 passing foundation tests with the fixed 1,000-case fuzz run.
- Kept the existing draft PR and Phase 01 scope intact; no diagnostic replacement place or Phase 02 content was created.

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
