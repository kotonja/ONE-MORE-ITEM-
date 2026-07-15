# Changelog

## 2026-07-14 - Phase 04 implementation complete and accepted

- Reopened the original private place directly from Roblox after a complete Studio close without running repository synchronization. The reopened place passed `672/672` managed-path parity, comprising 617 non-script instances and `55/55` exact Luau sources, with eight permanent stations, 25 authored grid tiles per station, 16 showcase path nodes, and exactly six remotes.
- Re-ran every Studio suite after reopen: Foundation `69/69`, Phase 02 `94/94`, Phase 03 `65/65`, and Phase 04 `119/119` passed.
- Re-ran all four dependency-free Node 24 validations successfully: Phase 01 `16` checks, Phase 02 `28` criteria, Phase 03 `31` criteria across `65` layout cases, and Phase 04 `42` criteria.
- Completed the verified five-client Station_05 integration flow and final cleanup. Integrated shipment receipts remained unique; the first tied server-best record remained `-5:4` with value `15` and item count `1`; final showcase observability was `Runtime=0 Active=0 Pending=0 Overflow=0 Loop=false`; and fresh game-owned warnings/errors were zero.
- Accepted the Phase 04 implementation while preserving the remaining extended QA honestly. No Station_07 completion, full cross-platform multiplayer matrix, physical-device result, published `MaxPlayers` value, or visible 12-shipment soak is claimed; those checks remain open in issue #4.
- Kept draft PR #5 open and unmerged, left `main` at `014ff3964eb63f22f8527894067cddb1b4f98070`, kept issue #4 open, and did not begin Phase 05.

## 2026-07-14 - Phase 04 multiplayer arena implementation and partial acceptance

- Expanded the historical `studio/phase02.manifest.json` as the sole canonical permanent-instance owner with eight complete authored stations on a deterministic 38-stud ring, a center dispatch, 16-node showcase path, arena announcement, server-best board, per-station owner/risk displays, and a script-free showcase crate template.
- Generalized production client and server code from one station to the allowlisted `station_01` through `station_08` set. The server validates the authored station contract, assigns the lowest free index, preserves ownership across respawn, maintains a FIFO waiting queue, and releases/reassigns stations without accepting client-supplied ownership.
- Added focused station-context lifecycle, per-station world-item isolation, immutable/idempotent shipment capture, a stable FIFO showcase with three active and sixteen pending visual slots, one conditional 30 Hz movement loop, session-only server-best rules, and shared arena/station display updates.
- Added the required one-shot showcase-overflow warning while preserving reward authority: over-capacity requests reject only the newest cosmetic copy, increment observability, and never remove the shipment or Tape. An injected warning sink makes the exact non-spamming contract deterministic in Studio tests.
- Preserved the existing six RemoteEvents, server-authoritative round/placement/Tape boundary, permanent authored UI, and Phase 01-03 behavior. Persistent progression, DataStores, monetization, final art/audio/VFX, and Phase 05 systems were not added.
- Added 13 Phase 04 Studio suites with 119 tests and a dependency-free 42-criterion Phase 04 Node gate. Fresh Studio Output passed Foundation `69/69`, Phase 02 `94/94`, Phase 03 `65/65`, and Phase 04 `119/119`; all four local Node 24 validations passed.
- Reapplied the 616-instance/45-script Phase 02-04 blueprint twice at the final source state; Phase 01 was unchanged and both Phase 02-04 applies reported `Created=0`, `Updated=661`, `Failed=0`. Before saving, the combined live tree matched 672 managed nodes and all 55 canonical Luau sources.
- Recorded partial live evidence honestly: Play Solo shipped one item for `+15 TAPE`, reached Results, and used Pack Again; a rotated Station_03 client shipped, accepted One More, and later failed; four clients received unique Station_01 through Station_04 assignments; a replacement client inherited released Station_02; and an eight-client graphical attempt assigned Station_01 through Station_08 without a crash. Station_05/Station_07 were inspected in legitimate rotated views, but the prescribed three-mode cross-platform multiplayer matrix and visible 12-shipment stress remain incomplete.
- Saved the original private cloud place successfully after the final double synchronization and closed every Studio process. Direct no-resync reopen is still incomplete because Roblox Studio updated to `0.730.0.7300790` and requires the account holder to sign in before the cloud place can be opened; no repository synchronization has been run in the new Studio session.
- Kept draft PR #5 unmerged, left `main` at the Phase 03 merge `014ff3964eb63f22f8527894067cddb1b4f98070`, and kept pre-release QA issue #4 open.

## 2026-07-14 — Phase 03 implementation acceptance

- Accepted the Phase 03 cross-platform implementation with zero known production blockers.
- Accepted the completed six-profile touch matrix, phone/tablet orientation coverage, and deterministic simultaneous second-touch rejection contract.
- Retained green automated and persistence gates: Foundation `69/69`, Phase 02 `94/94`, Phase 03 `65/65`, all three Node 24 validations, `180/180` managed paths, `44/44` exact sources, exactly six approved remotes, and zero duplicate or wrong-class paths.
- Moved the still-unpassed extended controller, uninterrupted hybrid, multiplayer-soak, and physical-device checks to [pre-release QA issue #4](https://github.com/kotonja/ONE-MORE-ITEM-/issues/4); they are not Phase 03 implementation blockers.
- Made no gameplay, manifest, test, workflow, UI, world, Studio-instance, or Roblox-place change during this documentation and metadata closeout.
- Kept PR #3 draft and unmerged. Phase 04 has not begun.

## 2026-07-14 — Phase 03 final non-waived acceptance attempt

- Accepted the completed six-profile touch/orientation matrix under the updated policy and removed simultaneous second-touch emulation as a Phase 03 blocker. Physical simultaneous multi-touch is deferred to later physical-device QA; neither a physical phone nor a physical controller was tested.
- Used Studio Controller Emulator with Generic Gamepad. The final trace proved Gamepad mode, exactly three bound actions, safe Results/Pack Again focus, one restart, disconnect cleanup, reconnect with three rather than six bindings, and exit to keyboard/mouse. The complete controller-only A-J trace, uninterrupted hybrid round, fresh two-player regression, and prescribed ten-round soak remain incomplete, so Phase 03 stays partial.
- Removed the transient `Phase03AcceptanceProbe` from Edit mode and made no production Luau, manifest, permanent-instance, authored UI, authored world, or remote changes. No Studio synchronization or save was performed for this documentation-only pass.
- Reused the existing successful private-cloud proof (`180/180` managed paths, `44/44` exact sources, six canonical remotes, zero duplicate or wrong-class paths) because no Studio-managed content changed.
- Fresh post-probe Studio Output passed Foundation `69/69`, Phase 02 `94/94`, and Phase 03 `65/65`, followed by zero fresh actionable Output errors or warnings. PR #3 remains draft and unmerged, `main` remains unchanged, and Phase 04 was not started.

## 2026-07-14 — Phase 03 manual acceptance correction and persistence

- Exercised all six required Studio touch profiles at actual viewports `373×666`, `392×758`, `665×374`, `749×368`, `767×1022`, and `1022×767`; every profile passed safe-area, camera, default-control, center/corner mapping, drag/release, multi-rotation Chair, Place, both Ship and One More, failure, Results, Pack Again, and cleanup checks. The later acceptance-policy update waived simultaneous second-touch emulation as a merge blocker.
- Reproduced the controller confirmation defect twice: Results Button A could leave Pack Again unsubmitted, and native One More selection could disagree with `SelectedGamepadAction`.
- Kept placement confirmation exclusively `ContextActionService`-owned, routed Decision/Results confirmation through the exact selected authored button, synchronized logical and native GUI selection, and added focused deterministic Studio/Node regression contracts.
- Changed the expected `NO_STATION` spectator diagnostic from warning severity to ordinary Output; a fresh two-client startup retained visible spectator isolation with zero game-owned warnings/errors.
- Expanded Phase 03 Studio coverage from 63 to 65 tests and the Phase 03 Node gate from 29 to 31 criteria. Fresh Studio Output passed Phase 01 `69/69`, Phase 02 `94/94`, and Phase 03 `65/65`; all three dependency-free Node validations passed.
- Rebuilt and applied both canonical synchronization paths twice, saved the corrected private cloud place normally, closed every Studio process, reopened directly from cloud without resynchronization, and passed `180/180` managed paths, `44/44` source parity, exactly six canonical remotes, and zero duplicate paths.
- Kept PR #3 draft and unmerged, left `main` unchanged, did not begin Phase 04, and recorded the still-open controller, hybrid, two-player owner-gameplay, and ten-round soak gates honestly.

## 2026-07-13 — Phase 03 cross-platform implementation, acceptance in progress

- Extended the historical `studio/phase02.manifest.json` as the single vertical-slice source of truth with device-safe ScreenGui properties, an authored transparent `TouchDragSurface`, five authored `FocusStroke` objects, five compact-action `UISizeConstraint` objects, and the touch-landscape and portrait camera anchors.
- Added focused strict client modules for `PreferredInput` mode state, responsive classification and geometry, authored-UI application, single-touch drag tracking, deterministic gamepad repeat/action routing, adaptive prompts, and coordinating local input without changing the authoritative round.
- Preserved the Phase 02 keyboard/mouse controls and six-remotes network surface. Touch and gamepad movement/rotation stay local; only Place, Decision, and Restart use their existing requests.
- Added responsive `Wide`, `CompactLandscape`, and `Portrait` profiles across 13 required viewports and five simulated safe-inset profiles. Geometry uses scale-only `UDim2`, compact primary actions enforce `72×64` or `120×64` minimums, and layout retargets over `0.25s` with Quart Out.
- Added deterministic gamepad mapping with `0.55` deadzone, immediate first step, `0.28s` initial delay, `0.12s` repeat interval, Ship-safe Decision focus, deliberate One More selection, and no Button B risk action or generated touch controls.
- Extended camera targeting to authored responsive anchors with `0.25s` retargeting and epoch-safe impulse settlement. Hardened character-control leases so PlayerModule controls and the exact prior Humanoid `AutoRotate` state restore across unassignment, respawn, Humanoid replacement, and destruction.
- Added eight Phase 03 Studio suites with 63 tests and a dependency-free Phase 03 Node gate. Fresh Studio Output passed Phase 01 `69/69`, Phase 02 `94/94`, and Phase 03 `63/63`; fresh actionable Output warnings/errors were zero.
- Passed local Node 24 validation at Phase 01 16 checks, Phase 02 24 criteria with 135 manifest instances and 34 scripts, and Phase 03 29 criteria plus all 65 layout/inset cases. Both push and draft-PR GitHub Actions checks passed on implementation head `8bc43880c48164547e6bd0e63a634f683304d078`.
- Applied the canonical Phase 01 and extended vertical-slice blueprints twice. The pre-save audit passed `180/180` managed paths with zero missing, wrong-class, duplicate, or unexpected paths, and all `44/44` Luau sources matched exactly.
- Created an external recovery copy outside Git, saved Phase 03 normally to the original private cloud place, closed every Studio process, and reopened directly from Roblox without synchronization. Post-reopen parity passed the same `180/180` paths, `44/44` sources, exact six-remotes surface, responsive properties, and authored anchors; the post-reopen command audit contained zero mutating synchronization calls.
- Completed a desktop timeout/reset/One More/shipment/Results flow and a `667×375` touch-landscape drag/invalid-feedback/Place/Ship/Results/Pack Again flow. Generic Gamepad prompts and safe Pack Again focus were visible; the full controller-only round remains pending.
- Updated CI to `actions/checkout@v7`, retained `actions/setup-node@v6` and Node 24, and kept `contents: read`, dependency caching disabled, and no install step.
- Opened draft PR #3 from `codex/phase-03-cross-platform-input` and left `main` unchanged.
- A later Roblox reconnect returned `RCC-277` after transport connected without a join snapshot. The earlier cloud persistence proof remains valid. Documentation/CI record head `1c3675f36ed0a078baad526831746e50a5438a31` passed both branch-push and draft-PR workflows with zero annotations. Phase 03 remains incomplete pending five touch-emulator profiles, the full controller-only flow, complete hybrid and two-player checks, and ten mixed-input rounds.

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
