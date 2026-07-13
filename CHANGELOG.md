# Changelog

## 2026-07-13 — Phase 02 final visual-truth and motion corrections

- Corrected the authored `DecisionPanel` target to `UDim2.new(0.5, 0, 0.96, 0)` with `AnchorPoint (0.5, 1)`, zero Y offset, and `Visible=false`; controller-owned 16-pixel entrance and exit motion now uses target-visibility tracking and transition epochs so repeated snapshots or delayed exits cannot restart or hide a reopened panel.
- Made `Preparing` an emitted authoritative state with guarded `0.12s` initial and `0.72s` restart windows before the existing `0.45s` item-presentation state.
- Added temporary `PresentationPoint` item travel, deterministic failure burst and cleanup, premium Pack Again lid/grid reset, `0.18s + 0.08s` rotation, `0.10s` authoritative accepted-placement snap, and response/snapshot arrival-order handling.
- Added authoritative Shipment, Session Bank, and Result Tape count animations and hardened the client store against lower-round and stale same-round snapshots.
- Replaced the warning-producing late-client wait in `cd4cf83` with an event-driven authored-child wait: `ClientBootstrap` checks `PlayerGui`, waits on `ChildAdded` without a deadline, retains the `ScreenGui` class check, and never calls `PlayerGui:WaitForChild` for the permanent gameplay UI. The Node contract rejects warning-producing or finite variants.
- Expanded Phase 02 Studio coverage from 9 suites / 71 tests to 11 suites / 94 tests and expanded the Phase 02 Node smoke from 18 to 24 criteria while retaining the 15-suite / 69-test Phase 01 gate and 16-check Phase 01 Node smoke.
- Synchronized the corrected 122-instance manifest twice with `Created=0 Updated=148 Skipped=0 Failed=0 Warnings=0 Backups=26`; all 36 canonical Luau sources matched Studio by SHA-256 and no managed paths were duplicated.
- Verified the authored layout contract at `1920×1080`, `1366×768`, `2560×1440`, and `1100×700`, then exercised real Play at the required desktop sizes. The narrow `1100×700` run placed an item successfully, showed the complete Decision panel and both actions, advanced through One More, lost 15 Tape on placement timeout, and later showed `PLAYER SHIPPED`, `+9 TAPE`, and `SESSION 30 TAPE` after manual Ship.
- Passed a fresh two-client session after `2ed3942`: both clients reached `READY`; the owner timed out, restarted, and then shipped successfully for 15 Tape, while the spectator stayed `SPECTATING` with `0 TAPE`, `BANK 0`, and Pack Again disabled.
- Fresh `2ed3942` server Output passed Phase 01 at 69/69 in `0.403734s` and Phase 02 at 94/94 in `6.000388s`, retaining the fixed seeds and 1,000 Phase 01 fuzz cases.
- Re-ran both dependency-free Node smokes after the warning fix: Phase 01 passed 16 checks, and Phase 02 passed 24 criteria with 122 instances, 26 scripts, and six remotes. The live corrected client source matched the canonical repository hash before save.
- Saved the warning-free corrected place normally at 2026-07-13 14:02:14 Eastern; Studio Output reported `Saved new changes in "ONE MORE ITEM!" to Roblox.` The external recovery copy `ONE_MORE_ITEM_phase02_final_warningfix_20260713.rbxl` was verified at 14:03:57 Eastern with a size of 159,447 bytes.
- Closed Studio cleanly and cold-reopened the place from Roblox cloud without resynchronization. `PlaceId 134193642444044` and `GameId 10493030248` matched the original place; Studio's internal label was `Place2` and did not change the authoritative identity.
- Passed the final cold-reopen audit at 157/157 managed paths and 36/36 repository-to-live Luau SHA-256 matches, with zero missing, duplicate, wrong-class, or conflicting instances. Live `ClientBootstrap` matched `sha256:2327d05560ce4b55e2eecdb45d3a27417e4f37dcb2b0c0a3000112a2c4ed6f02`; the authored `DecisionPanel` retained anchor `(0.5, 1)`, position `(0.5, 0, 0.96, 0)`, size `(0.5, 0, 0.3, 0)`, and `Visible=false`.
- Final post-reopen Play Solo passed Foundation 69/69 and Phase 02 94/94 with zero fresh actionable warnings or errors. Verified flows covered placement-timeout failure, Pack Again reset, decision-timeout Ship for `+15 TAPE / SESSION 15 TAPE`, One More followed by manual Ship for `+57 TAPE / SESSION 72 TAPE`, and packed-content failure for `LOST 15 TAPE / SESSION 72 TAPE`.
- Final runtime cleanup returned `RuntimePresentation=0` and `PlacedItems=0`. The final `cd4cf83` two-client run logged `READY` on both clients; Pack Again advanced the owner through round 2 `Preparing → PresentingItem → AwaitingPlacement`, while the spectator stayed visibly `SPECTATING` with `0 TAPE`, `BANK 0 TAPE`, and disabled Pack Again.
- Fresh bridge diagnostics returned `errors=0`, `matching=0`, and `latestActionable=null`; five plugin loops each reported `errors=0`. Studio stopped normally with only the main Edit window remaining.
- Kept draft PR #2 open and unmerged, left `main` unchanged, and did not begin Phase 03. Documentation-record commit `c86523c4c01beb1fa13550ded23c42b736a6a11b` passed both branch-push and draft-PR workflows; the completion report records the exact final status-only head and its green workflows because a commit cannot contain its own SHA.

## 2026-07-12 — Phase 02: Playable Station Vertical Slice initial baseline

- Authored a deterministic, typed Edit-mode Phase 02 manifest covering 122 permanent instances, including the single 5-wide × 4-high × 5-deep packing station, permanent `StarterGui` HUD, six permanent RemoteEvents, development block template, and all Phase 02 client/server/shared scripts.
- Implemented the server-authoritative round state machine, station assignment, placement validation, deterministic legal-item sequence, session-only Tape calculations, stale-timer protection, request sequencing/rate limits, reset behavior, and temporary authoritative item proxies.
- Implemented the initial desktop Play Solo presentation: stable station camera, mouse and keyboard placement controls, local valid/invalid ghost feedback, authored HUD binding, item previews, physical control response, basic state presentation, and character handling. The complete promised presentation, failure, reset, placement, and Tape motion was finished in the 2026-07-13 correction pass above.
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
