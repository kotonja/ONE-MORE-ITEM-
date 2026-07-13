# Development status

- **Current phase:** Phase 03 — Cross-Platform Interaction and Responsive UI is active; Phase 03 has not yet passed its implementation, Studio, cloud-persistence, or CI gates
- **Current branch:** `codex/phase-03-cross-platform-input`
- **Phase 02 merge:** PR #2 is merged at `73b3428c5ff0068f1e57f89d2150ffb8dccfdf20`
- **Phase 03 draft PR:** Not opened yet; it must target `main` from `codex/phase-03-cross-platform-input` and remain draft and unmerged
- **Main base SHA:** `73b3428c5ff0068f1e57f89d2150ffb8dccfdf20`
- **Latest verified implementation SHA before documentation closeout:** `cd4cf83b01081ccc99e4306a15524d23f0025a65` (`fix: avoid delayed UI replication warning`)
- **Latest verified documentation-record SHA:** `c86523c4c01beb1fa13550ded23c42b736a6a11b` (`docs: record Phase 02 visual correction results`)
- **Documentation-head note:** A commit cannot contain its own SHA; the final documentation commit and branch-head equality must be reported from live Git/GitHub state after this file is committed.
- **Phase 03 opening gate:** Clean `main` and both existing dependency-free Node smokes passed before branching; no Phase 03 implementation or Studio result is claimed yet

## Final review findings

The correction audit found twelve gaps between the approved Phase 02 specification and the initial implementation:

1. `DecisionPanel` stored a permanent `+260` Y offset and could render below the viewport.
2. The Node smoke had no reusable authored-GUI bounds contract.
3. The server created `Preparing` but advanced before emitting it, making restart presentation unreachable.
4. Pack Again did not receive the full lid-rise, neutral-color, grid-sweep, and runtime-cleanup presentation.
5. The authored `PresentationPoint` was not used for incoming-item motion.
6. Failure lacked the promised burst of the current ghost and already placed unshipped contents.
7. Rotation tokens existed but ordinary ghost movement replaced the promised turn and settle.
8. Accepted placement had no event-order-safe authoritative `0.10s` completion.
9. Shipment, bank, and result Tape values jumped instead of counting to authoritative totals.
10. The client store could accept an older round when that snapshot carried a higher version.
11. Mouse-to-grid alignment required real viewport and GUI-inset verification.
12. Panel motion could restart on repeated snapshots, hide immediately on exit, or let a stale exit hide a reopened panel.

## Exact corrections implemented

- `DecisionPanel` is authored at `UDim2.new(0.5, 0, 0.96, 0)` with `AnchorPoint = Vector2.new(0.5, 1)`, `Size = UDim2.new(0.5, 0, 0.30, 0)`, zero Y offset, and `Visible=false`. `RoundUIController` owns the temporary 16-pixel offset, `0.30s` entrance, `0.20s` exit, target-visibility tracking, and transition epochs.
- `StartRound` emits authoritative `Preparing`; the server schedules guarded `0.12s` initial or `0.72s` restart preparation before `PresentingItem`, then schedules the existing `0.45s` presentation before `AwaitingPlacement`. Every delayed transition retains player, round, version, and expected-state guards.
- The client clones the script-free development cell template into `RuntimePresentation`, centers it at `PresentationPoint`, travels for `0.35s`, settles for `0.06s`, holds for `0.04s`, and hands off to the normal placement ghost. Epoch cleanup removes stale presentation models on every relevant transition and destruction.
- Failure captures the active ghost and placed unshipped proxies before cleanup, locally suppresses the authoritative copies, performs a `0.20s` failed lid attempt and `0.14s` pause, then moves/fades deterministic `FailureBurst` copies for `0.64s`. Reset or destruction removes debris and restores suppressed parts.
- Pack Again now uses the replicated restart `Preparing` window: Results exits, controls stay hidden, the lid returns to its authored color while rising for `0.35s`, the tiles perform one cyan sweep, runtime effects clear, and the presentation point returns to baseline.
- Rotation lifts the ghost `0.12` studs, turns for `0.18s` with at most four degrees of overshoot, and settles for `0.08s` at exact `GridWorldTransform` positions. Accepted placement snaps for `0.10s`; rejection retains its `0.12s` nudge.
- Pending placement visuals are keyed by round and client sequence. Response-first and snapshot-first acceptance complete once, release input correctly, and preserve delayed correlation; `Failing` never counts as acceptance.
- Shipment counts over `0.25–0.40s`, Session Bank over `0.55–0.80s`, and Result value over `0.30s`. Counts only target server values, and newer snapshots cancel or retarget old counts.
- The client store rejects lower round IDs and same-round versions less than or equal to the stored version, accepts a higher round whose version restarts, and preserves deep-copy isolation.
- `GetMouseLocation` is paired with `ViewportPointToRay`, avoiding a second GUI-inset subtraction while leaving keyboard placement unchanged.
- Late clients now use a warning-free event-driven authored-child wait: the helper checks `PlayerGui:FindFirstChild`, waits on `ChildAdded` without a deadline, and retains the required `ScreenGui` class check. `ClientBootstrap` no longer calls the warning-producing `PlayerGui:WaitForChild` for the permanent gameplay UI. The Node architecture contract requires this event-driven path and rejects warning-producing or finite variants.

## Permanent instance, synchronization, and source parity

- **Phase 02 managed instances:** 122 permanent instances.
- **Phase 02 script operations:** 26 scripts.
- **Permanent remotes:** 6 `RemoteEvent` instances.
- **Final cold-reopen managed-path audit:** 157/157 paths passed with zero missing, duplicate, wrong-class, or conflicting instances.
- **Final cold-reopen Luau source parity:** 36/36 canonical Phase 01 and Phase 02 sources matched Studio by SHA-256.
- **Warning-fix live source:** `ClientBootstrap` matched `sha256:2327d05560ce4b55e2eecdb45d3a27417e4f37dcb2b0c0a3000112a2c4ed6f02` after the no-resync cold reopen.
- **Reopened DecisionPanel:** `AnchorPoint = (0.5, 1)`, `Position = (0.5, 0, 0.96, 0)`, `Size = (0.5, 0, 0.3, 0)`, and `Visible = false`.
- **Authoring result:** The corrected Phase 02 blueprint synchronized twice with `Created=0 Updated=148 Skipped=0 Failed=0 Warnings=0 Backups=26`, proving idempotent folder-first reuse without duplicate paths or wrong-class conflicts.
- **Authored-content boundary:** Permanent UI remains under `StarterGui`; permanent station/world content remains under `Workspace`; networking and the development template remain authored under `ReplicatedStorage`; no gameplay runtime builder was introduced.
- **Post-correction cloud-reopen parity:** Passed with the exact path, class, conflict, duplicate, property, and source results above.

## Automated tests

### Phase 01 foundation

- **Suites:** 15
- **Tests:** 69
- **Passed:** 69
- **Failed:** 0
- **Fuzz:** 1,000 cases, seed `24012026`
- **Final cold-reopen result:** `[ONE_MORE_ITEM][FoundationTests] RESULT suites=15 tests=69 passed=69 failed=0 duration=0.399727s fuzzCases=1000 fuzzSeed=24012026`
- **Exact pass line:** `[ONE_MORE_ITEM][FoundationTests] PASS: all 69 tests passed`
- **Final cold-reopen diagnostics:** Fresh actionable Output warnings and errors were both zero.

### Phase 02 vertical slice

- **Suites:** 11
- **Tests:** 94
- **Passed:** 94
- **Failed:** 0
- **Seed:** `24022026`
- **Final cold-reopen result:** `[ONE_MORE_ITEM][Phase02Tests] RESULT suites=11 tests=94 passed=94 failed=0 duration=7.024051s seed=24022026`
- **Exact pass line:** `[ONE_MORE_ITEM][Phase02Tests] PASS: all 94 tests passed`
- **Suite distribution:** Round math 16, Sequence fairness 8, Placement security 15, Round state 19, Client round store 5, Serialization 3, World transform 5, Station assignment 4, Rate limiting 4, Client motion cleanup 12, Runtime cleanup 3.
- **Added coverage:** The correction pass added 23 tests across authoritative Preparing and timer guards, monotonic round storage, copied snapshots, presentation replacement and cleanup, failure suppression/restoration, ten reset cycles, response-first and snapshot-first accepted placement, rejection recovery, and Failing non-acceptance.
- **Final cold-reopen diagnostics:** Fresh actionable Output warnings and errors were both zero.

### Node synchronization smoke

- **Phase 01:** `[StudioSyncSmoke] PASS checks=16 folders=7 scripts=10 deterministic=true`
- **Phase 02:** `[Phase02StudioSyncSmoke] PASS criteria=24 instances=122 scripts=26 remotes=6 deterministic=true phase01=true`
- Phase 02 increased naturally from 18 to 24 criteria by adding authored-layout, decision-action containment, top-card overlap, terminal-failure, and authoritative terminal-shipping contracts. The authored-client architecture criterion requires the event-driven `ScreenGui` wait and rejects `PlayerGui:WaitForChild`, warning-producing indefinite waits, and finite clone deadlines. Both dependency-free commands passed again after `cd4cf83`, and Phase 01 remains part of the generalized workflow.

## Viewport layout verification

The authored screen-space calculation passed for all required static sizes:

| Viewport | DecisionPanel bounds | ShipButton bounds | OneMoreButton bounds |
| --- | --- | --- | --- |
| `1920×1080` | `(480, 712.8)–(1440, 1036.8)` | `(768, 910.44)–(1056, 991.44)` | `(1094.4, 910.44)–(1401.6, 991.44)` |
| `1366×768` | `(341.5, 506.88)–(1024.5, 737.28)` | `(546.4, 647.42)–(751.3, 705.02)` | `(778.62, 647.42)–(997.18, 705.02)` |
| `2560×1440` | `(640, 950.4)–(1920, 1382.4)` | `(1024, 1213.92)–(1408, 1321.92)` | `(1459.2, 1213.92)–(1868.8, 1321.92)` |
| `1100×700` | `(275, 462)–(825, 672)` | `(440, 590.1)–(605, 642.6)` | `(627, 590.1)–(803, 642.6)` |

At every static size, both decision buttons are contained, have positive usable dimensions, and do not overlap `CurrentItemCard` or `ShipmentCard`; `PlacementControls`, `ResultsPanel`, and both top cards remain inside the viewport.

## Studio Play Solo visual verification

- Real Play was exercised at `1920×1080`, `1366×768`, and narrow desktop `1100×700`. The complete Decision panel and both Ship and One More actions remained visible at every required live size.
- At `1920×1080`, a successful placement reached Decision with readable Ship and One More actions; decision timeout shipped safely and displayed `+15 TAPE` with `SESSION 15 TAPE`.
- At `1366×768`, the visual center mapped to logical `(2, 2)`. Rear-left, rear-right, front-left, and front-right mapped to `(0, 0)`, `(4, 0)`, `(0, 4)`, and `(4, 4)` respectively, proving that the top bar/GUI inset did not shift the ray. Successful placement, One More, manual Ship, decision timeout, placement timeout, and Pack Again were exercised during the correction run.
- At exact `1100×700`, a valid item was placed and the entire Decision panel remained visible with both actions usable. One More advanced to the next item/round; a later placement-timeout failure displayed `TOO MUCH` and `LOST 15 TAPE`; a later manual Ship displayed `PLAYER SHIPPED`, `+9 TAPE`, and `SESSION 30 TAPE`.
- Final post-reopen flows covered placement-timeout failure, Pack Again reset, decision-timeout Ship for `+15 TAPE / SESSION 15 TAPE`, One More followed by manual Ship for `+57 TAPE / SESSION 72 TAPE`, and packed-content failure for `LOST 15 TAPE / SESSION 72 TAPE`.
- A final 60 FPS focused capture confirmed the reset-to-placement sequence, the temporary PresentationPoint item handoff, a multi-frame rotation of an irregular One More ghost, the accepted Parcel transition into Decision, and Shipment Tape counting through intermediate values before reaching the exact authoritative total.
- Final cleanup returned `RuntimePresentation=0` and `PlacedItems=0`; the ten-cycle automated motion test also returned to baseline.
- Final post-reopen Studio Output passed Foundation 69/69 and Phase 02 94/94 with fresh actionable warnings `0` and errors `0`. Helper/plugin request-limit chatter is not treated as a game-code pass or failure.

## Two-client multiplayer

- **Final warning-fix result:** Passed after `cd4cf83`; both clients logged `READY` through the warning-free event-driven authored-UI startup path.
- Pack Again started owner round 2 and advanced it through `Preparing → PresentingItem → AwaitingPlacement`.
- The spectator remained visibly `SPECTATING` with `0 TAPE`, `BANK 0 TAPE`, and disabled Pack Again, proving action, restart, and reward isolation.
- Fresh bridge diagnostics returned `errors=0`, `matching=0`, and `latestActionable=null`; five plugin loops each reported `errors=0`.
- Studio ended normally with only the main Edit window remaining.

## GitHub Actions

- **Workflow:** `Phase 01 and Phase 02 Node Validation`
- **Commands:** `node tools/test_studio_blueprint.mjs` and `node tools/test_phase02_blueprint.mjs`
- **Triggers:** Pull requests targeting `main`, pushes to `main`, and pushes to `codex/**`.
- **Permissions/dependencies:** `contents: read`, no dependency installation, and no npm package requirement.
- **Warning-fix implementation-head result:** Commit `cd4cf83b01081ccc99e4306a15524d23f0025a65` passed both the [branch-push run](https://github.com/kotonja/ONE-MORE-ITEM-/actions/runs/29272062349) ([job](https://github.com/kotonja/ONE-MORE-ITEM-/actions/runs/29272062349/job/86891938174)) and [draft-PR run](https://github.com/kotonja/ONE-MORE-ITEM-/actions/runs/29272066325) ([job](https://github.com/kotonja/ONE-MORE-ITEM-/actions/runs/29272066325/job/86891950607)); checkout, Node setup, Phase 01 smoke, Phase 02 smoke, and completion steps were green.
- **Documentation-record head result:** Commit `c86523c4c01beb1fa13550ded23c42b736a6a11b` passed both the [branch-push run](https://github.com/kotonja/ONE-MORE-ITEM-/actions/runs/29277371368) ([job](https://github.com/kotonja/ONE-MORE-ITEM-/actions/runs/29277371368/job/86909708796)) and [draft-PR run](https://github.com/kotonja/ONE-MORE-ITEM-/actions/runs/29277374496) ([job](https://github.com/kotonja/ONE-MORE-ITEM-/actions/runs/29277374496/job/86909719607)); all eight steps completed successfully with no failures, cancellations, or skips.
- **Exact final status-only head:** This document cannot contain its own commit SHA. The completion report records that SHA, both exact-head workflow URLs, and local/remote/PR-head equality after the final status-only commit passes.

## Cloud persistence

- **Original private place:** `PlaceId 134193642444044`, `GameId 10493030248`.
- The earlier Phase 02 baseline proved that the original place could be saved, fully closed, reopened directly from Roblox, and verified. That earlier result does not prove persistence of the current correction commits.
- **External recovery copy:** Passed outside Git. `ONE_MORE_ITEM_phase02_final_warningfix_20260713.rbxl` was downloaded and verified at 2026-07-13 14:03:57 Eastern with a size of 159,447 bytes; no machine-specific path is recorded.
- **Normal save of warning-free corrected content:** Passed at 2026-07-13 14:02:14 Eastern. Studio Output reported `Saved new changes in "ONE MORE ITEM!" to Roblox.`
- **Clean close and cold reopen:** Passed without source resynchronization. Studio closed cleanly and the place reopened directly from Roblox cloud.
- **Reopened identity:** Passed at `PlaceId 134193642444044`, `GameId 10493030248`. Studio's internal place label is `Place2`; that display label does not override the authoritative IDs.
- **Full final post-reopen audit:** Passed 157/157 managed paths, 36/36 source hashes, zero missing/duplicate/wrong-class/conflicting instances, exact `DecisionPanel` properties, and exact `ClientBootstrap` hash as recorded above.
- **Post-reopen tests and flows:** Passed Foundation 69/69, Phase 02 94/94, every required failure/reset/decision-timeout/One More/manual-Ship flow, and zero-child runtime cleanup.

## Known issues and remaining gates

- Roblox Studio may emit unrelated plugin/bridge request-limit noise; only fresh game-owned failures are gating.
- The transient cloud-save internal-server error from the first save attempt was recovered without losing the corrected content; the normal retry, recovery copy, clean close, and no-resync cloud reopen all passed.
- No Phase 02 game, persistence, parity, cleanup, multiplayer, or merge blocker remains. PR #2 is merged at the Phase 03 base SHA.
- Phase 03 remains incomplete until responsive safe-area authoring, touch/gamepad/hybrid input, deterministic tests, Studio emulator and multiplayer checks, cloud save/reopen parity, and final-head CI all pass.

## Deferred by design

The full eight-player arena, seven additional stations, camera orbit, final models/animations, audio/music/final VFX, final shipping and dispatch systems, social/leaderboard features, DataStores and permanent economy, progression/collection/challenges/missions, cosmetics/store/monetization, analytics, quests, trading, pets, rebirths, multiple worlds, co-op, tutorial screens, final launch map, and every Phase 04 system remain unstarted. Phase 03 is limited to cross-platform interaction and responsive presentation for the existing single station.

## Exact next step

Implement and verify Phase 03 on `codex/phase-03-cross-platform-input`, push meaningful milestones, and keep its pull request draft and unmerged. Do not begin Phase 04.
