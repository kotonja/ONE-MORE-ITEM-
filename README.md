# ONE MORE ITEM!

**PACK THE BOX** — Fit it. Ship it. Or risk one more.

ONE MORE ITEM! is a mobile-first Roblox packing game targeting a premium visual bar, built around fitting irregular items into a deterministic snap-grid crate.

## Current development phase

Phase 07 — Visual Readability and Arena Art-Direction Rebuild: **Active and unaccepted.** Work is isolated on `codex/phase-07-visual-readability-arena-rebuild`. [PR #8](https://github.com/kotonja/ONE-MORE-ITEM-/pull/8) remains open, draft, and unmerged. The current implementation candidate at `a057cbb7fd23cb16f387142dec3e988efa213247` has green seven-gate Node, final direct-reopen seven-suite Studio, deterministic projection/line-of-sight, canonical double-synchronization, normal cloud publish, verified zero-process close, and final direct no-sync reopen parity. The screenshot evidence is now accepted at `15/15`, including the genuine same-session four-client contact sheet in frame 12 and the authored collection shelf/proxies in frame 15. Phase 07 nevertheless remains unaccepted until the complete unedited 3–6 minute replacement recording is accepted; [issue #4](https://github.com/kotonja/ONE-MORE-ITEM-/issues/4) remains open, and no Phase 08 work has begun. See [`docs/PHASE07_VISUAL_READABILITY_ARENA_REBUILD.md`](docs/PHASE07_VISUAL_READABILITY_ARENA_REBUILD.md) for the contract and exact evidence boundary.

Phase 06 — First-Time Player Experience, Starter Missions, and Retention Analytics is complete and accepted. [PR #7](https://github.com/kotonja/ONE-MORE-ITEM-/pull/7) was squash-merged into `main` as `4c606ae4f5e7a5e3d5fa431775c94469ecea1b67`.

The completion presentation is now deterministic for both profile-first and round-first arrival. It shows exactly `SHIPMENT COMPLETE` / `TAPE IS SAVED` / `SHIPPED ITEMS JOIN YOUR COLLECTION` for `0.95` seconds, cannot replay after completion or reload, remains hidden while a player is unassigned, and losslessly defers the mission banner until the onboarding presentation releases it. Authoritative economy analytics preserve mutation order: First Fit records `+10` ending at `10`, Shipment records `+15` ending at `25`, then First Shipment records `+25` ending at `50`.

All six local Node 24 gates are green, including Phase 06 at `76` criteria. Fresh Studio Output passed Foundation `69/69`, Phase 02 `94/94`, Phase 03 `65/65`, Phase 04 `119/119`, Phase 05 `130/130`, and Phase 06 at 18 suites / `75/75` before cloud save. The deterministic integrated run recorded the exact 20-event onboarding, core-loop, mission, progression, and economy trace; duplicate delivery, save, and reload produced no replay; 100 injected analytics failures left profile state and recorded events unchanged; and adapter cleanup passed. A separate two-session Memory-adapter run preserved `Skipped` with `HighestStep=2`, zero Tape/XP, no replay, and active starter missions. The terminal profile's literal additional reward at `5/5` is explicitly waived because no sixth starter mission exists.

Two ordered canonical synchronization passes were clean. With every acceptance-fixture attribute cleared, the private cloud place saved normally, every Studio process closed, and the correct `PlaceId 134193642444044` / `GameId 10493030248` reopened directly without synchronization. Exact pre-save and read-only post-reopen parity passed at 1,004/1,004 managed paths, 89/89 sources, 5,192/5,192 bridge-exposed properties, and 93 authored-attribute targets containing 150 keys. The direct-reopen no-sync Play then passed Foundation `69/69`, Phase 02 `94/94`, Phase 03 `65/65`, Phase 04 `119/119`, Phase 05 `130/130`, and Phase 06 `75/75`, with zero fresh actionable/game-owned warnings or errors. Full evidence is recorded in [`docs/DEVELOPMENT_STATUS.md`](docs/DEVELOPMENT_STATUS.md).

Broad physical-device, expanded emulator, multiplayer, published Analytics dashboard, public-traffic funnel, retention, soak, low-connectivity, and production-balance QA remain explicitly unpassed in open [issue #4](https://github.com/kotonja/ONE-MORE-ITEM-/issues/4). These are pre-release QA, not Phase 06 implementation blockers. See [`docs/PHASE06_ONBOARDING_MISSIONS_ANALYTICS.md`](docs/PHASE06_ONBOARDING_MISSIONS_ANALYTICS.md) for the accepted contract and evidence boundary.

Phase 05 was accepted and squash-merged through [PR #6](https://github.com/kotonja/ONE-MORE-ITEM-/pull/6) at `d644411b48e20cd9bb256d3d2c55a647efc2adfd`. Open [GitHub issue #4](https://github.com/kotonja/ONE-MORE-ITEM-/issues/4) retains the explicitly unpassed Phase 04 and Phase 05 pre-release QA; no physical-device or production-store result is claimed.

Phase 02 is complete and merged through PR #2 at `73b3428c5ff0068f1e57f89d2150ffb8dccfdf20`; its deterministic grid, authored single station, permanent HUD/remotes, desktop presentation, and server-authoritative session-only round loop remain the protected baseline. Phase 03 is limited to responsive safe-area UI, touch, gamepad, dynamic input prompts, responsive camera anchors, and mid-round local input-mode switching.

## Repository workflow

- `main` is protected by workflow: work happens on `codex/*` feature branches and is reviewed through pull requests.
- Phase 02 was merged through PR #2 at `73b3428c5ff0068f1e57f89d2150ffb8dccfdf20`.
- Phase 03 was squash-merged through PR #3 at `014ff3964eb63f22f8527894067cddb1b4f98070`.
- Phase 04 was squash-merged through PR #5 at `213f3581bd242523e34601cfefa5b5a74770ddee`.
- Phase 05 was squash-merged through PR #6 at `d644411b48e20cd9bb256d3d2c55a647efc2adfd` after its synchronized cloud-place and direct-reopen acceptance.
- Phase 06 was squash-merged through [PR #7](https://github.com/kotonja/ONE-MORE-ITEM-/pull/7) at `4c606ae4f5e7a5e3d5fa431775c94469ecea1b67`.
- Phase 07 is active on `codex/phase-07-visual-readability-arena-rebuild`; [PR #8](https://github.com/kotonja/ONE-MORE-ITEM-/pull/8) remains open, draft, and unmerged, and Phase 07 is not accepted until its complete evidence boundary passes.
- Pull before editing, never force-push, and keep every meaningful Studio/code change committed and pushed.
- `docs/DEVELOPMENT_STATUS.md` is updated on every task.
- GitHub Actions workflow `Phase 01–07 Node Validation` uses Node 24 with `actions/checkout@v7` and `actions/setup-node@v6`. It runs seven dependency-free validations on pull requests targeting `main` and pushes to `main` or `codex/**`. Implementation head `a057cbb7fd23cb16f387142dec3e988efa213247` passed push run `29662807404` / job `88128209680` and draft-PR run `29662808244` / job `88128211869`; the later documentation head must receive its own exact-head result.

## Studio source workflow

The repository is the only source of truth for scripts and permanent managed instances:

1. Edit canonical sources under `src/`. `studio/phase01.manifest.json` owns the foundation hierarchy, while the historically named `studio/phase02.manifest.json` remains the single canonical manifest for the authored vertical slice through Phase 07, including responsive UI, arena/stations, profile/onboarding/mission surfaces, first-frame presentation, Lighting, remotes, templates, and scripts.
2. In Roblox Studio Edit mode, begin from any place state, including a clean Baseplate. Do not manually create the managed folders.
3. Run `node tools/build_studio_blueprint.mjs` and `node tools/build_phase02_blueprint.mjs` from the repository root.
4. Run `node tools/test_studio_blueprint.mjs`, `node tools/test_phase02_blueprint.mjs`, `node tools/test_phase03_cross_platform.mjs`, `node tools/test_phase04_multiplayer_arena.mjs`, `node tools/test_phase05_persistent_progression.mjs`, `node tools/test_phase06_onboarding_missions_analytics.mjs`, and `node tools/test_phase07_visual_readability.mjs`; stop if any validation fails.
5. Apply the generated Phase 01 operations first and the extended vertical-slice operations second, preserving generated order.
6. Confirm parent-first creation, exact managed properties and sources, zero wrong-class paths or duplicates, and then run the Studio suites and required Play tests.

Phase 02 adds `studio/phase02.manifest.json`, `tools/build_phase02_blueprint.mjs`, and `tools/test_phase02_blueprint.mjs`. Phases 03-07 deliberately extend that manifest and test path instead of creating an overlapping owner. The authoring tool deterministically expands one Station_01 descriptor into eight explicit final station paths at 45-degree intervals. Generated Edit-mode operations author permanent `Workspace`, `StarterGui`, `ReplicatedFirst`, `ReplicatedStorage`, `ServerScriptService`, `StarterPlayerScripts`, and `Lighting` content with typed properties and attributes. Runtime gameplay code only binds those instances and creates explicitly temporary gameplay or cosmetic content.

Correct folders and scripts are reused or updated, and missing instances are created. A wrong-class instance at a managed path raises a clear error and is never silently destroyed. Repeating the complete operation list is idempotent and creates no duplicates.

The same build step also emits `.codex-cache/phase01-blueprint.json` for validation and preview. Both generated artifacts are temporary, ignored by Git, and rebuilt deterministically from the same canonical `src/` plus manifest; scripts must never be edited only in Studio.

## Running Phase 01 tests

1. Synchronize the canonical sources to Studio using the workflow above.
2. Confirm `ReplicatedStorage.ONE_MORE_ITEM.Shared.Config.GameConfig.DEVELOPMENT.RUN_FOUNDATION_TESTS` is `true` and run Play in Roblox Studio.
3. Read the Output window for `[ONE_MORE_ITEM][FoundationTests]` totals, exact failures, fuzz seed/case count, and benchmark timing.

The runner exits immediately outside Roblox Studio and fails visibly with `error()` if any test fails.

Phase 02 adds a separate Studio suite for round math, fair sequencing, state transitions, placement security, station ownership, serialization, world transforms, and runtime cleanup. Phase 03 adds deterministic input and responsive-layout coverage; Phase 04 covers the multiplayer arena and showcase; Phase 05 covers persistent profiles and shelves; and Phase 06 covers onboarding, exact-once starter missions, and failure-isolated analytics. Phase 07 adds deterministic authored-hierarchy, camera projection, line-of-sight, no-Glass, Neon-area, first-frame, label, and cleanup contracts. The current candidate passed all seven Node gates and all seven Studio suites after the final direct no-sync reopen, and all `15/15` required screenshots are accepted. Those results, the screenshot set, and final persistence parity do not replace the still-pending complete unedited 3–6 minute replacement recording.

## Phase 01 persistence status

The original private cloud place is verified as persistent. After a controlled cloud publish/save, every Studio process was closed, one clean Studio session reopened the place directly from Roblox, the managed hierarchy matched `7/7` folders and `10/10` scripts with `10/10` exact source matches and zero duplicates, and all 69 foundation tests passed again. The earlier `Internal server error.` incidents were fixed-duration cloud publish timeouts; the later controlled session completed successfully, so no diagnostic replacement place was needed.

## Permanent authoring rule

Permanent gameplay UI must be authored as real instances under `StarterGui`; the permanent pre-game first-frame curtain is authored under `ReplicatedFirst`; permanent world content is authored under `Workspace`; and permanent lighting/post-processing is authored under `Lighting`. Runtime Lua may operate or animate those instances but may not generate permanent UI, the arena, or the environment. Phase 01 creates none of those presentation surfaces.

## Phase 03 cross-platform contract

Phase 03 retains the same server round and six authored remotes. `UserInputService.PreferredInput` selects only local `KeyboardMouse`, `Touch`, or `Gamepad` presentation. Viewport geometry independently selects `Wide`, `CompactLandscape`, or `Portrait`; authored UI is constrained to Roblox-reported safe areas, and authored camera anchors keep the crate framed. Touch drag and gamepad grid movement update only the local ghost, while Place, Decision, and Pack Again continue through the existing server-authoritative requests.

## Phase 04 multiplayer arena contract

Phase 04 authors eight complete station Models in Edit mode on a 38-stud ring, all facing the center, plus the center dispatch, 16-node showcase loop, arena announcement, server-best board, owner/risk displays, and script-free showcase crate template. `StationService` validates and allocates the authored stations in deterministic index order; a FIFO waiting queue receives released stations. `StationContextController` binds one allowlisted station from each authoritative snapshot and tears down the old camera, character, placement, motion, pointer, touch, and gamepad state when assignment changes.

Every player round, occupancy grid, placed-item container, timer, sequence, and result remains station scoped and server authoritative. A successful shipment is copied into an immutable, deduplicated `ShipmentRecord`; the shared showcase accepts records in stable receipt order, displays at most three simultaneously, queues at most sixteen, moves through one shared 30 Hz loop, and returns its runtime folder to zero children after drain. Phase 04 accepted only a session Tape bank; Phase 05 replaces that canonical wallet with the persistent profile boundary without changing the Phase 04 showcase authority.

## Phase 05 persistent-progression contract

Phase 05 separates server-only profile storage from deterministic progression. Normal Roblox Studio persistence uses only `ONE_MORE_ITEM_PlayerProfiles_StudioTest_v1`; non-Studio servers are configured for `ONE_MORE_ITEM_PlayerProfiles_v1`, but no production-store test or rollout is claimed. Deterministic tests and explicitly armed failure acceptance fixtures use an injected `MemoryProfileAdapter`. Schema Version 1 persists Tape, Packing XP, collection/mastery, bounded receipt IDs, statistics, timestamps, and an owned session lock. Rank and all presentation values are derived.

Profile load and lock must reach Ready before station assignment. Globally unique server-created OutcomeIds make successful and failed round rewards idempotent. One server-to-client `ProfileNet.ProfileSnapshot` event copies presentation-safe state; the existing gameplay `Net` remains exactly six remotes and no client can submit progression. The permanent MetaBar, CollectionPanel, discovery/rank presentation, eight station shelves, and shelf template are authored before Play. `CollectionDefinitions` owns catalog order/count, `MasteryDefinitions` owns tier thresholds, and shelf rendering uses a deterministic presentation fingerprint so lifecycle/save-only snapshots return `UNCHANGED` without replacing valid proxies.

The Studio-only failure fixture is disabled by default and is armed on `ServerScriptService.ONE_MORE_ITEM_Server` with `ONE_MORE_ITEM_Phase05AcceptanceMode`, optional `ONE_MORE_ITEM_Phase05AcceptanceTargetUserId`, and a future `ONE_MORE_ITEM_Phase05AcceptanceExpiresAt` no more than 600 seconds ahead. `Unavailable`, `SaveDelayed`, and `Conflict` select the memory adapter for the entire test server. Clear all three attributes before a normal Studio-test persistence run, cloud save, or cloud reopen, and never save the place while armed. Memory-fixture evidence validates failure behavior only; it does not replace the two real Studio-test-store sessions.

See `docs/PHASE05_PERSISTENT_PROGRESSION.md` for the exact accepted evidence, the bridge-observable parity boundary, and the extended QA that remains explicitly unpassed.

## Phase 06 onboarding, missions, and analytics contract

Phase 06 preserves server authority while adding durable contextual onboarding, five fixed exact-once starter missions, and best-effort server-only analytics. Profile Schema Version 2 remains inside the existing production and Studio-test store names. The client may request only the narrowly validated onboarding skip action; it cannot submit progress, rewards, balances, mission completion, or analytics truth. Phase 06 was accepted and squash-merged through PR #7 at `4c606ae4f5e7a5e3d5fa431775c94469ecea1b67`.

## Phase 07 visual-readability contract

Phase 07 recomposes presentation without changing gameplay. The crate must dominate every active view; all 25 floor cells and four layers remain readable; the console, avatar, UI, labels, and permanent geometry cannot obscure the packing volume. The authored first-frame curtain hides uninitialized world/camera state, station anchors use deterministic responsive framing, crate panes are non-refractive, and the eight stations sit inside a controlled circular/octagonal warehouse with a legible center dispatch.

Permanent first-frame UI, gameplay UI, world geometry, lighting, post-processing, labels, camera anchors, remotes, templates, and scripts remain manifest-authored before Play. Phase 07 adds no authority, remote, progression, final asset, audio, monetization, or Phase 08 feature. Its detailed targets, proven automated/manual/persistence checks, rejected preliminary evidence, and remaining external evidence gates are recorded in [`docs/PHASE07_VISUAL_READABILITY_ARENA_REBUILD.md`](docs/PHASE07_VISUAL_READABILITY_ARENA_REBUILD.md).
