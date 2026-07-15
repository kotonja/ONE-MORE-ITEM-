# ONE MORE ITEM!

**PACK THE BOX** — Fit it. Ship it. Or risk one more.

ONE MORE ITEM! is a premium, mobile-first Roblox packing game built around fitting irregular items into a deterministic snap-grid crate.

## Current development phase

Phase 05 — Persistent Player Profiles, Tape, Collection, and Packing Rank: **implemented and substantially verified on `codex/phase-05-persistent-progression`, but not yet accepted.**

Draft [PR #6](https://github.com/kotonja/ONE-MORE-ITEM-/pull/6) remains open and unmerged. Fresh local Node gates, the last normal cloud Studio run, Play Solo, two Studio-test persistence sessions, multiplayer isolation, and controlled memory-adapter failure fixtures passed. Final review then corrected same-round waiting snapshots so each player's `StateVersion` advances across Loading, queued Ready, and Unavailable; commit `bf144fc3cb478823a80ceadaafc28cb78298bf12` passed all five suites in an offline recovery copy. That recovery copy could not access the Studio-test store, so it is suite proof only: the queue correction has not yet been synchronized or saved to the cloud place. Direct protocol opens failed TLS verification; the signed-in Studio Home route reached the correct place and Team Create server without a TLS error but stalled before the editor received a join snapshot. Final apply/save/close/reopen parity therefore remains unpassed, and manual phone/touch and gamepad collection-panel opening is also incomplete. Phase 04 was accepted and squash-merged through [PR #5](https://github.com/kotonja/ONE-MORE-ITEM-/pull/5) at `213f3581bd242523e34601cfefa5b5a74770ddee`, and open [GitHub issue #4](https://github.com/kotonja/ONE-MORE-ITEM-/issues/4) continues to track extended pre-release QA.

Phase 02 is complete and merged through PR #2 at `73b3428c5ff0068f1e57f89d2150ffb8dccfdf20`; its deterministic grid, authored single station, permanent HUD/remotes, desktop presentation, and server-authoritative session-only round loop remain the protected baseline. Phase 03 is limited to responsive safe-area UI, touch, gamepad, dynamic input prompts, responsive camera anchors, and mid-round local input-mode switching.

## Repository workflow

- `main` is protected by workflow: work happens on `codex/*` feature branches and is reviewed through pull requests.
- Phase 02 was merged through PR #2 at `73b3428c5ff0068f1e57f89d2150ffb8dccfdf20`.
- Phase 03 was squash-merged through PR #3 at `014ff3964eb63f22f8527894067cddb1b4f98070`.
- Phase 04 was squash-merged through PR #5 at `213f3581bd242523e34601cfefa5b5a74770ddee`.
- Phase 05 uses `codex/phase-05-persistent-progression`. Its implementation and two-session Studio-test persistence gates passed, but the final queue correction is repository/local-recovery verified only and still needs cloud synchronization, save, complete close, direct no-sync reopen/parity, and manual phone/gamepad collection QA, so no Phase 05 acceptance is claimed.
- Draft PR #6 remains open; `main` is unchanged.
- Pull before editing, never force-push, and keep every meaningful Studio/code change committed and pushed.
- `docs/DEVELOPMENT_STATUS.md` is updated on every task.
- GitHub Actions workflow `Phase 01–05 Node Validation` uses Node 24 with `actions/checkout@v7` and `actions/setup-node@v6`. It runs five dependency-free validations on pull requests targeting `main` and pushes to `main` or `codex/**`. Implementation head `bf144fc3cb478823a80ceadaafc28cb78298bf12` passed branch-push run `29398524215` / job `87297461413` and draft-PR run `29398526422` / job `87297468905`. The containing documentation commit and its exact-head runs are recorded in PR #6 and the final handoff rather than self-referenced by this tracked file.

## Studio source workflow

The repository is the only source of truth for scripts and permanent managed instances:

1. Edit canonical sources under `src/`. `studio/phase01.manifest.json` owns the foundation hierarchy, while the historically named `studio/phase02.manifest.json` remains the single canonical manifest for the authored vertical slice, Phase 03 responsive additions, Phase 04 arena, and Phase 05 profile interfaces, shelves, remotes, templates, and scripts.
2. In Roblox Studio Edit mode, begin from any place state, including a clean Baseplate. Do not manually create the managed folders.
3. Run `node tools/build_studio_blueprint.mjs` and `node tools/build_phase02_blueprint.mjs` from the repository root.
4. Run `node tools/test_studio_blueprint.mjs`, `node tools/test_phase02_blueprint.mjs`, `node tools/test_phase03_cross_platform.mjs`, `node tools/test_phase04_multiplayer_arena.mjs`, and `node tools/test_phase05_persistent_progression.mjs`; stop if any validation fails.
5. Apply the generated Phase 01 operations first and the extended vertical-slice operations second, preserving generated order.
6. Confirm parent-first creation, exact managed properties and sources, zero wrong-class paths or duplicates, and then run the Studio suites and required Play tests.

Phase 02 adds `studio/phase02.manifest.json`, `tools/build_phase02_blueprint.mjs`, and `tools/test_phase02_blueprint.mjs`. Phases 03-05 deliberately extend that manifest and test path instead of creating an overlapping owner. The authoring tool deterministically expands one Station_01 descriptor into eight explicit final station paths at 45-degree ring intervals, including one permanent Phase 05 collection shelf per station. Generated Edit-mode operations author permanent `Workspace`, `StarterGui`, `ReplicatedStorage`, `ServerScriptService`, and `StarterPlayerScripts` content with typed properties and attributes. Runtime gameplay code only binds those instances and creates explicitly temporary gameplay, profile-preview, showcase, or shelf-proxy content.

Correct folders and scripts are reused or updated, and missing instances are created. A wrong-class instance at a managed path raises a clear error and is never silently destroyed. Repeating the complete operation list is idempotent and creates no duplicates.

The same build step also emits `.codex-cache/phase01-blueprint.json` for validation and preview. Both generated artifacts are temporary, ignored by Git, and rebuilt deterministically from the same canonical `src/` plus manifest; scripts must never be edited only in Studio.

## Running Phase 01 tests

1. Synchronize the canonical sources to Studio using the workflow above.
2. Confirm `ReplicatedStorage.ONE_MORE_ITEM.Shared.Config.GameConfig.DEVELOPMENT.RUN_FOUNDATION_TESTS` is `true` and run Play in Roblox Studio.
3. Read the Output window for `[ONE_MORE_ITEM][FoundationTests]` totals, exact failures, fuzz seed/case count, and benchmark timing.

The runner exits immediately outside Roblox Studio and fails visibly with `error()` if any test fails.

Phase 02 adds a separate Studio suite for round math, fair sequencing, state transitions, placement security, station ownership, serialization, world transforms, and runtime cleanup. Phase 03 adds an eight-suite deterministic Studio gate for preferred-input state, responsive layout geometry, touch tracking, gamepad repeat and routing, prompts, camera targets, character-control cleanup, and remote discipline. Phase 04 adds a 13-suite deterministic Studio gate for the eight-station registry, allocation and waiting, client rebinding, rotated transforms, concurrent isolation, immutable shipment records, bounded FIFO showcase behavior, shared displays, respawn, and cleanup. Phase 05 adds profile-schema/migration, memory-adapter, locking, progression, assignment, snapshot, shelf, presentation, autosave, and shutdown coverage. See `docs/PHASE02_VERTICAL_SLICE.md`, `docs/PHASE03_CROSS_PLATFORM.md`, `docs/PHASE04_MULTIPLAYER_ARENA.md`, and `docs/PHASE05_PERSISTENT_PROGRESSION.md` for the complete contracts and evidence status.

## Phase 01 persistence status

The original private cloud place is verified as persistent. After a controlled cloud publish/save, every Studio process was closed, one clean Studio session reopened the place directly from Roblox, the managed hierarchy matched `7/7` folders and `10/10` scripts with `10/10` exact source matches and zero duplicates, and all 69 foundation tests passed again. The earlier `Internal server error.` incidents were fixed-duration cloud publish timeouts; the later controlled session completed successfully, so no diagnostic replacement place was needed.

## Permanent authoring rule

Permanent UI must be authored as real instances under `StarterGui`, and permanent world content must be authored as real instances under `Workspace`. Runtime Lua may operate those instances but may not generate the permanent UI or arena. Phase 01 creates neither UI nor map content.

## Phase 03 cross-platform contract

Phase 03 retains the same server round and six authored remotes. `UserInputService.PreferredInput` selects only local `KeyboardMouse`, `Touch`, or `Gamepad` presentation. Viewport geometry independently selects `Wide`, `CompactLandscape`, or `Portrait`; authored UI is constrained to Roblox-reported safe areas, and authored camera anchors keep the crate framed. Touch drag and gamepad grid movement update only the local ghost, while Place, Decision, and Pack Again continue through the existing server-authoritative requests.

## Phase 04 multiplayer arena contract

Phase 04 authors eight complete station Models in Edit mode on a 38-stud ring, all facing the center, plus the center dispatch, 16-node showcase loop, arena announcement, server-best board, owner/risk displays, and script-free showcase crate template. `StationService` validates and allocates the authored stations in deterministic index order; a FIFO waiting queue receives released stations. `StationContextController` binds one allowlisted station from each authoritative snapshot and tears down the old camera, character, placement, motion, pointer, touch, and gamepad state when assignment changes.

Every player round, occupancy grid, placed-item container, timer, sequence, and result remains station scoped and server authoritative. A successful shipment is copied into an immutable, deduplicated `ShipmentRecord`; the shared showcase accepts records in stable receipt order, displays at most three simultaneously, queues at most sixteen, moves through one shared 30 Hz loop, and returns its runtime folder to zero children after drain. Phase 04 accepted only a session Tape bank; Phase 05 replaces that canonical wallet with the persistent profile boundary without changing the Phase 04 showcase authority.

## Phase 05 persistent-progression contract

Phase 05 separates server-only profile storage from deterministic progression. Normal Roblox Studio persistence uses only `ONE_MORE_ITEM_PlayerProfiles_StudioTest_v1`; non-Studio servers are configured for `ONE_MORE_ITEM_PlayerProfiles_v1`, but no production-store test or rollout is claimed. Deterministic tests and explicitly armed failure acceptance fixtures use an injected `MemoryProfileAdapter`. Schema Version 1 persists Tape, Packing XP, collection/mastery, bounded receipt IDs, statistics, timestamps, and an owned session lock. Rank and all presentation values are derived.

Profile load and lock must reach Ready before station assignment. Globally unique server-created OutcomeIds make successful and failed round rewards idempotent. One server-to-client `ProfileNet.ProfileSnapshot` event copies presentation-safe state; the existing gameplay `Net` remains exactly six remotes and no client can submit progression. The permanent MetaBar, CollectionPanel, discovery/rank presentation, eight station shelves, and shelf template are authored before Play.

The Studio-only failure fixture is disabled by default and is armed on `ServerScriptService.ONE_MORE_ITEM_Server` with `ONE_MORE_ITEM_Phase05AcceptanceMode`, optional `ONE_MORE_ITEM_Phase05AcceptanceTargetUserId`, and a future `ONE_MORE_ITEM_Phase05AcceptanceExpiresAt` no more than 600 seconds ahead. `Unavailable`, `SaveDelayed`, and `Conflict` select the memory adapter for the entire test server. Clear all three attributes before a normal Studio-test persistence run, cloud save, or cloud reopen, and never save the place while armed. Memory-fixture evidence validates failure behavior only; it does not replace the two real Studio-test-store sessions.

See `docs/PHASE05_PERSISTENT_PROGRESSION.md` for exact evidence. Phase 05 remains unaccepted until the cloud editor opens, the repository queue correction is synchronized and saved, every Studio process closes, the place reopens directly without synchronization, and managed/source parity plus fresh suites/Output pass; manual collection-panel opening on phone/touch and gamepad also remains unverified.
