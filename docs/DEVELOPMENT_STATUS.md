# Development status

## Current phase and Git state

- **Phase result:** **Partial.** Phase 04 implementation, deterministic gates, final Edit-mode synchronization, and cloud save are complete, but required manual cross-platform/live-stress gates and the direct no-resync cloud-reopen proof are incomplete.
- **Current phase:** Phase 04 - Eight-Station Multiplayer Arena and Shared Shipment Showcase.
- **Current branch:** `codex/phase-04-multiplayer-arena`.
- **Protected base:** `main` and `origin/main` remain at the accepted Phase 03 merge `014ff3964eb63f22f8527894067cddb1b4f98070`.
- **Previous pull request:** [PR #3 - Phase 03: Cross-Platform Interaction and Responsive UI](https://github.com/kotonja/ONE-MORE-ITEM-/pull/3), merged.
- **Current draft pull request:** [PR #5 - Phase 04: Multiplayer Arena and Shared Shipment Showcase](https://github.com/kotonja/ONE-MORE-ITEM-/pull/5), draft and unmerged.
- **Latest pushed implementation SHA before documentation:** `f5334da63db37d6d930da3113fc30e5331b08df5` (`test: close Phase 04 acceptance coverage`).
- **Documentation record:** This file records implementation head `f5334da63db37d6d930da3113fc30e5331b08df5`; the containing documentation commit is identified by Git and the draft PR rather than predicted inside itself.
- **Pre-release QA:** [Issue #4 - Pre-release cross-platform and multiplayer integration QA](https://github.com/kotonja/ONE-MORE-ITEM-/issues/4) remains open.
- **Main protection:** No Phase 04 commit has been merged into `main`; Phase 05 has not begun.

Phase 04 is not accepted until the prescribed manual cross-platform and visible showcase-stress gates pass, the final documentation head passes both Actions triggers, and complete direct no-resync cloud-reopen parity is observed. Passing deterministic tests alone does not override unfinished manual gates.

## Completed Phase 04 implementation

- `studio/phase02.manifest.json` remains the sole canonical owner for Phase 02-04 permanent instances.
- Eight complete real station Models exist in the generated Edit-mode hierarchy before Play. They occupy a deterministic 38-stud ring at 45-degree intervals, face the center, and have unique `station_01` through `station_08` IDs/indexes.
- Every station contains the same crate/grid, three responsive camera anchors, presentation/dispatch points, four physical controls, owner/status/risk displays, and isolated `PlacedItems`/`RuntimePresentation` folders.
- Permanent arena content includes floor/backdrop/rails, spectator spawn, center dispatch/lift/entry, arena announcement, server-best board, 16-node showcase loop, empty runtime folder, and a script-free showcase crate template.
- `StationDefinitions` supplies the immutable allowlist/order/capacity. `StationService` validates the complete authored contract, assigns the lowest free station, preserves ownership across respawn, maintains FIFO wait order, and promotes the oldest eligible waiter into a released station.
- `StationContextController` binds one allowlisted snapshot station and cleanly tears down old placement, world-motion, camera, character-control, pointer/touch/gamepad, and temporary visual state before unassignment or reassignment.
- Player rounds, grids, deadlines, sequences, placed-item Models, Tape, and results remain isolated and server authoritative. The existing six-remotes surface is unchanged.
- `ShipmentRecordService` validates, deep-copies, freezes, and deduplicates successful shipment records before presentation consumers receive them.
- `ShowcaseService` provides stable FIFO receipt order, at most three active displays, at most sixteen pending records, up to ten coarse item proxies per crate, 1.25-second launch spacing, one conditional 30 Hz loop, safe temporary Parts, overflow isolation, one concise warning per service lifetime, and baseline cleanup.
- `ServerBestService`, `StationDisplayService`, and `ArenaAnnouncementService` provide session-best ranking, sanitized owner/status/risk boards, and guarded shared announcements.
- Persistent Tape, DataStores, monetization, final art/audio/VFX, and every Phase 05 system remain absent.

The full architecture and operational limits are in `docs/PHASE04_MULTIPLAYER_ARENA.md`.

## Canonical managed content and synchronization

- **Phase 02-04 blueprint:** 616 non-script instances and 45 scripts, 661 total operations.
- **Combined Phase 01 plus Phase 02-04 canonical target:** 672 managed paths: 617 non-script paths and 55 Luau sources.
- **Final double synchronization:** Phase 01 pass 1 and pass 2 each reported `Created=0 Updated=0 Skipped=17 Failed=0`; Phase 02-04 pass 1 and pass 2 each reported `Created=0 Updated=661 Skipped=0 Failed=0`, with 45 safe script backups and no warnings.
- **Live Edit-mode key hierarchy:** eight Station Models, 16 path nodes, center dispatch, showcase template, six remotes, and all expected server services confirmed.
- **Pre-save live parity:** five untruncated managed roots totaled 672 nodes and 55 scripts; all 55 live sources matched their canonical UTF-8 SHA-256 values, including the two Unicode-bearing client sources.
- **Zero-duplicate status:** deterministic generation and both final reapplies passed with no creation or wrong-class failure. Post-reopen confirmation remains pending.
- **Source parity status:** pre-save `55/55` exact-source parity passed. Post-reopen `55/55` parity remains pending and is not claimed.

## Local Node 24 validation

Fresh local results after the latest implementation correction:

```text
[StudioSyncSmoke] PASS checks=16 folders=7 scripts=10 deterministic=true
[Phase02StudioSyncSmoke] PASS criteria=28 instances=616 scripts=45 remotes=6 deterministic=true phase01=true
[Phase03LayoutMatrix] PASS viewports=13 insetProfiles=5 cases=65 desktopCompatible=true safeContainment=true
[Phase03CrossPlatformSmoke] PASS criteria=31 viewports=13 insetProfiles=5 layoutCases=65 remotes=6 deterministic=true phase01=true phase02=true
[Phase04MultiplayerArena] PASS criteria=42 instances=616 scripts=45 stations=8 pathNodes=16 remotes=6 deterministic=true prior=true
```

The four commands are:

```text
node tools/test_studio_blueprint.mjs
node tools/test_phase02_blueprint.mjs
node tools/test_phase03_cross_platform.mjs
node tools/test_phase04_multiplayer_arena.mjs
```

## Fresh automated Studio tests

Final pre-save run: `2026-07-14T19:45:54Z`.

```text
[ONE_MORE_ITEM][FoundationTests] RESULT suites=15 tests=69 passed=69 failed=0 duration=0.406397s fuzzCases=1000 fuzzSeed=24012026
[ONE_MORE_ITEM][FoundationTests] PASS: all 69 tests passed
[ONE_MORE_ITEM][Phase02Tests] RESULT suites=11 tests=94 passed=94 failed=0 duration=10.126511s seed=24022026
[ONE_MORE_ITEM][Phase02Tests] PASS: all 94 tests passed
[ONE_MORE_ITEM][Phase03Tests] RESULT suites=8 tests=65 passed=65 failed=0 duration=0.006501s seed=13072026
[ONE_MORE_ITEM][Phase03Tests] PASS: all 65 tests passed
[ONE_MORE_ITEM][Phase04Tests] RESULT suites=13 tests=119 passed=119 failed=0 duration=0.932559s seed=14072026
[ONE_MORE_ITEM][Phase04Tests] PASS: all 119 tests passed seed=14072026
```

The server then reported readiness with `stations=8`, `remotes=6`, and `showcasePathNodes=16`. Fresh actionable game-owned Output errors after the baseline were zero.

## Deterministic Phase 04 coverage

- Exactly eight authored stations validate in deterministic order with unique IDs/indexes and complete required paths.
- Logical origin/axes, pointer-to-grid transforms, and desktop/touch camera anchors are covered across all eight rotations, including Station_05 opposite Station_01.
- The first eight players receive eight unique stations; the ninth waits; release promotes the oldest valid waiter into the exact released station; respawn keeps ownership.
- All eight station IDs bind through one client lifecycle; invalid/no-station assignments unbind and enter safe spectator behavior.
- Eight players start eight independent station-scoped rounds; placement, world-item cleanup, rewards, and failure remain isolated.
- Shipment records copy every server value and placed-item field exactly, retain no `Player` reference, remain immutable/idempotent, and survive round restart and player departure.
- Same-frame shipments and failures remain isolated. Stale timers cannot alter replacement rounds or neighbors.
- Same-frame showcase submissions retain FIFO receipt order; active/pending limits, newest-cosmetic overflow, duplicate rejection, exactly one warning across three rejected requests with `OverflowCount=3`, 12-shipment drain stress, update-loop stop, and zero-runtime cleanup pass.
- Server-best comparisons, owner/status boards, six/eight/ten-item risk states, announcement priority, and display-name sanitization pass.

## Manual acceptance status

| Required gate | Result |
| --- | --- |
| Play Solo | **Passed for the recorded flow.** Station_01 shipped a valid item for `+15 TAPE`, reached Results, used Pack Again, and later exercised failure; runtime showcase content returned to zero. |
| Rotated-station tests | **Partial.** A real Station_03 round shipped for `+15 TAPE`, accepted One More, and then failed on the second item. Station_05 and Station_07 were inspected in legitimate rotated client views, but complete prescribed placement/decision/shipment flows at both were not recorded. |
| Four-client live multiplayer | **Partial.** Four clients received unique Station_01 through Station_04 assignments and progressed independently. Station_03 shipped, accepted One More, and later failed without corrupting neighbors. Removing Station_02's owner released it and a replacement fifth user inherited Station_02. The full prescribed per-client action matrix and final visible cleanup were not all recorded. |
| Cross-platform multiplayer | **Not passed.** Phase 03 deterministic input/layout gates remain green, but the required Phase 04 desktop/touch/gamepad multiplayer session is not complete. |
| Eight-session deterministic test | **Passed.** Automated Studio coverage proves eight unique station-scoped rounds, ninth-player waiting, FIFO release/reassignment, and isolation. |
| Eight-client graphical attempt | **Attempted.** Eight graphical sessions received unique Station_01 through Station_08 assignments; clients five through eight occupied Station_05 through Station_08, legitimate Station_05/07 rotated views were inspected, no client crash was observed, and all sessions ended cleanly. This is an attempt record, not a substitute for the required action matrix. |
| Showcase stress test | **Automated pass; live graphical gate pending.** The deterministic 12-shipment FIFO/bounds/drain test passes. The prescribed visible multi-shipment live spectacle is not complete. |
| Runtime cleanup | **Observed after a live shipment.** `ShowcaseLoop.Runtime` returned to zero children. Full post-stress multiplayer cleanup remains pending. |
| Output | **Clean for the latest baseline and recorded Play.** Fresh actionable game-owned warnings/errors were zero. Plugin icon, bridge request-limit, and Team Create transport messages were external. |

Partial rows do not satisfy Phase 04 acceptance.

## Performance accounting

- Maximum accepted-item Models: `8 stations x 10 items = 80`.
- Conservative detailed item-cell Parts: `8 x 10 x 9 = 720`, using the largest nine-cell development shape for every slot.
- Maximum active showcase BaseParts: `3 x (7 template BaseParts + 10 proxies) = 51`.
- Pending showcase entries: at most 16 immutable data records and no pending world Models.
- Showcase update: one shared conditional 30 Hz loop; no per-part or per-player frame loop.
- Idle/drained showcase baseline: zero active Models, zero runtime children, and no update connection.

These are deterministic development-art bounds. Physical-device performance remains pre-release QA.

## GitHub Actions

- **Workflow/job:** `Phase 01-04 Node Validation`.
- **Runtime/actions:** Node 24, `actions/checkout@v7`, `actions/setup-node@v6`.
- **Permissions/configuration:** `contents: read`, dependency cache disabled, no package install, no third-party dependency.
- **Triggers:** pull requests to `main`, pushes to `main`, and pushes to `codex/**`.
- **Commands:** all four Node validations run in order.
- **Latest implementation-head status:** branch-push run `29364192500` / job `87191541084` and draft-PR run `29364191719` / job `87191538408` passed at `f5334da63db37d6d930da3113fc30e5331b08df5`; setup, checkout, Node 24 setup, all four validation steps, and post steps succeeded. Final documentation-head runs must still be recorded after the documentation commit.

## Cloud persistence

- An external recovery copy was created outside Git and verified at 181,936 bytes.
- An earlier Team Create cloud commit returned HTTP 500; it was superseded by a later successful normal save of the original private place.
- **Cloud save:** Passed. Studio reported `Saved new changes in "ONE MORE ITEM!" to Roblox.` after the final double synchronization and final green test run.
- **Complete Studio close:** Passed; zero Roblox Studio windows remained after the save.
- **Direct cloud reopen without resynchronization:** Blocked at the current machine state. Roblox Studio updated to `0.730.0.7300790` and requires the account holder to sign in before the place can be opened. One clean Studio startup process is waiting at the login screen, and no repository synchronization has run in it.
- **Post-reopen eight-station parity:** Pending.
- **Post-reopen source parity:** Pending.
- **Post-reopen zero duplicate/wrong-class audit:** Pending.
- **Post-reopen Studio suites and required rounds:** Pending.

Persistence is not yet accepted: save and full close passed, but the original place must still reopen directly from Roblox without source synchronization, retain `672/672` managed paths and `55/55` exact sources plus six remotes and zero conflicts, rerun all suites, and produce fresh clean Output.

## Known issues and deferred pre-release QA

- [Issue #4](https://github.com/kotonja/ONE-MORE-ITEM-/issues/4) remains open for extended controller, hybrid, multiplayer-soak, physical-device, and integration QA.
- The remaining Phase 04 manual gates are the complete Station_05/Station_07 action flows, three-mode desktop/touch/gamepad multiplayer matrix, visible 12-shipment showcase stress, and its final cleanup proof.
- Final documentation-head GitHub Actions and direct no-resync cloud-reopen parity remain unverified.
- Current published `MaxPlayers` was not observed; experience settings were not changed.
- No known deterministic production-code failure remains in the latest local Node or Studio suites.
- External plugin-icon and bridge-rate messages are not game-owned warnings. The earlier HTTP 500 is superseded by the successful save, but the post-update login gate still prevents direct-reopen proof.

## Deferred by design

Persistent Tape/DataStores, packing XP, ranks, collection, mastery, daily challenges, missions, cosmetics, store/monetization, trading, pets, rebirths, multiple worlds, co-op packing, cheer reactions, global/cross-server leaderboards, analytics, quests, final models/assets/audio/VFX, final Tape-wrap sequence, driving/delivery gameplay, camera orbit, haptics, and every Phase 05 system remain deferred.

## Exact next phase recommendation

Do not begin Phase 05 yet. Finish the remaining Phase 04 rotated-station, cross-platform, visible stress, final-documentation CI, and direct no-resync cloud-reopen gates on `codex/phase-04-multiplayer-arena`. Keep PR #5 draft and unmerged, keep issue #4 open, and leave `main` unchanged. If every acceptance criterion then passes, review and merge Phase 04 before opening a separately scoped Phase 05 branch.
