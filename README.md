# ONE MORE ITEM!

**PACK THE BOX** — Fit it. Ship it. Or risk one more.

ONE MORE ITEM! is a premium, mobile-first Roblox packing game built around fitting irregular items into a deterministic snap-grid crate.

## Current development phase

Phase 06 — First-Time Player Experience, Starter Missions, and Retention Analytics: **implementation complete on `codex/phase-06-onboarding-starter-missions`; acceptance partial.** All six Node 24 gates are green. Fresh Studio suites passed both before cloud save and after the direct no-synchronization reopen: Foundation `69/69`, Phase 02 `94/94`, Phase 03 `65/65`, Phase 04 `119/119`, Phase 05 `130/130`, and Phase 06 `58/58`. Established-profile migration, onboarding including failure/retry, the 5/5 starter-path profile result, direct cloud persistence, and limited portrait/landscape touch checks are recorded.

Phase 06 is not yet accepted.

The remaining Phase 06 gates are not claimed as passed. Touch and skip acceptance are partial. Gamepad evidence currently covers prompts and focus only; hold-B skip and the complete ButtonL1/ButtonB flow remain pending. A two-player Local Server reached O1/O2 and proved one-player skip isolation, but the full matrix remains pending. The private-cloud save, complete Studio close, direct signed-in reopen, 1,004-path/89-source parity, fixture absence, fresh six-suite run, same-profile Version 2 reload/reward-no-replay evidence, client UI state, clean Output, and clean shutdown now pass. An integrated analytics-memory trace is still absent, so analytics no-replay is not claimed. Session E nevertheless ended with the durable Studio-test profile already at `5/5`, so no defined starter mission remains for Session F's separately required new same-profile reward; completing that literal subgate requires an explicitly approved alternate evidence route that preserves exact-once behavior. [Draft PR #7](https://github.com/kotonja/ONE-MORE-ITEM-/pull/7) remains draft and unmerged, the Phase 06 comment on [issue #4](https://github.com/kotonja/ONE-MORE-ITEM-/issues/4) has intentionally not been posted before acceptance, and Phase 07 has not begun. See [`docs/PHASE06_ONBOARDING_MISSIONS_ANALYTICS.md`](docs/PHASE06_ONBOARDING_MISSIONS_ANALYTICS.md) for the contract and evidence boundary.

Phase 05 was accepted and squash-merged through [PR #6](https://github.com/kotonja/ONE-MORE-ITEM-/pull/6) at `d644411b48e20cd9bb256d3d2c55a647efc2adfd`. Open [GitHub issue #4](https://github.com/kotonja/ONE-MORE-ITEM-/issues/4) retains the explicitly unpassed Phase 04 and Phase 05 pre-release QA; no physical-device or production-store result is claimed.

Phase 02 is complete and merged through PR #2 at `73b3428c5ff0068f1e57f89d2150ffb8dccfdf20`; its deterministic grid, authored single station, permanent HUD/remotes, desktop presentation, and server-authoritative session-only round loop remain the protected baseline. Phase 03 is limited to responsive safe-area UI, touch, gamepad, dynamic input prompts, responsive camera anchors, and mid-round local input-mode switching.

## Repository workflow

- `main` is protected by workflow: work happens on `codex/*` feature branches and is reviewed through pull requests.
- Phase 02 was merged through PR #2 at `73b3428c5ff0068f1e57f89d2150ffb8dccfdf20`.
- Phase 03 was squash-merged through PR #3 at `014ff3964eb63f22f8527894067cddb1b4f98070`.
- Phase 04 was squash-merged through PR #5 at `213f3581bd242523e34601cfefa5b5a74770ddee`.
- Phase 05 was squash-merged through PR #6 at `d644411b48e20cd9bb256d3d2c55a647efc2adfd` after its synchronized cloud-place and direct-reopen acceptance.
- Phase 06 implementation is complete and acceptance is partial on `codex/phase-06-onboarding-starter-missions` in [draft PR #7](https://github.com/kotonja/ONE-MORE-ITEM-/pull/7), which must remain unmerged until the outstanding Phase 06 gates pass.
- Pull before editing, never force-push, and keep every meaningful Studio/code change committed and pushed.
- `docs/DEVELOPMENT_STATUS.md` is updated on every task.
- GitHub Actions workflow `Phase 01–06 Node Validation` uses Node 24 with `actions/checkout@v7` and `actions/setup-node@v6`. It runs six dependency-free validations on pull requests targeting `main` and pushes to `main` or `codex/**`. Implementation-head evidence is recorded in `docs/DEVELOPMENT_STATUS.md`; final documentation-head evidence is recorded in the draft PR and final handoff.

## Studio source workflow

The repository is the only source of truth for scripts and permanent managed instances:

1. Edit canonical sources under `src/`. `studio/phase01.manifest.json` owns the foundation hierarchy, while the historically named `studio/phase02.manifest.json` remains the single canonical manifest for the authored vertical slice, Phase 03 responsive additions, Phase 04 arena, Phase 05 profile interfaces/shelves, and Phase 06 onboarding/mission UI, remotes, templates, and scripts.
2. In Roblox Studio Edit mode, begin from any place state, including a clean Baseplate. Do not manually create the managed folders.
3. Run `node tools/build_studio_blueprint.mjs` and `node tools/build_phase02_blueprint.mjs` from the repository root.
4. Run `node tools/test_studio_blueprint.mjs`, `node tools/test_phase02_blueprint.mjs`, `node tools/test_phase03_cross_platform.mjs`, `node tools/test_phase04_multiplayer_arena.mjs`, `node tools/test_phase05_persistent_progression.mjs`, and `node tools/test_phase06_onboarding_missions_analytics.mjs`; stop if any validation fails.
5. Apply the generated Phase 01 operations first and the extended vertical-slice operations second, preserving generated order.
6. Confirm parent-first creation, exact managed properties and sources, zero wrong-class paths or duplicates, and then run the Studio suites and required Play tests.

Phase 02 adds `studio/phase02.manifest.json`, `tools/build_phase02_blueprint.mjs`, and `tools/test_phase02_blueprint.mjs`. Phases 03-06 deliberately extend that manifest and test path instead of creating an overlapping owner. The authoring tool deterministically expands one Station_01 descriptor into eight explicit final station paths at 45-degree ring intervals, including one permanent Phase 05 collection shelf per station. Generated Edit-mode operations author permanent `Workspace`, `StarterGui`, `ReplicatedStorage`, `ServerScriptService`, and `StarterPlayerScripts` content with typed properties and attributes. Runtime gameplay code only binds those instances and creates explicitly temporary gameplay, profile-preview, showcase, shelf-proxy, or reward-presentation content.

Correct folders and scripts are reused or updated, and missing instances are created. A wrong-class instance at a managed path raises a clear error and is never silently destroyed. Repeating the complete operation list is idempotent and creates no duplicates.

The same build step also emits `.codex-cache/phase01-blueprint.json` for validation and preview. Both generated artifacts are temporary, ignored by Git, and rebuilt deterministically from the same canonical `src/` plus manifest; scripts must never be edited only in Studio.

## Running Phase 01 tests

1. Synchronize the canonical sources to Studio using the workflow above.
2. Confirm `ReplicatedStorage.ONE_MORE_ITEM.Shared.Config.GameConfig.DEVELOPMENT.RUN_FOUNDATION_TESTS` is `true` and run Play in Roblox Studio.
3. Read the Output window for `[ONE_MORE_ITEM][FoundationTests]` totals, exact failures, fuzz seed/case count, and benchmark timing.

The runner exits immediately outside Roblox Studio and fails visibly with `error()` if any test fails.

Phase 02 adds a separate Studio suite for round math, fair sequencing, state transitions, placement security, station ownership, serialization, world transforms, and runtime cleanup. Phase 03 adds an eight-suite deterministic Studio gate for preferred-input state, responsive layout geometry, touch tracking, gamepad repeat and routing, prompts, camera targets, character-control cleanup, and remote discipline. Phase 04 adds a 13-suite deterministic Studio gate for the eight-station registry, allocation and waiting, client rebinding, rotated transforms, concurrent isolation, immutable shipment records, bounded FIFO showcase behavior, shared displays, respawn, and cleanup. Phase 05 adds profile-schema/migration, memory-adapter, locking, progression, assignment, snapshot, shelf, presentation, autosave, and shutdown coverage. Phase 06 adds Schema Version 2 migration, onboarding, guided timing, exact-once starter missions, snapshot/presentation deduplication, analytics adapters/catalog, request security, and multiplayer isolation coverage. See the phase documents under `docs/` for complete contracts and evidence status.

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

Profile load and lock must reach Ready before station assignment. Globally unique server-created OutcomeIds make successful and failed round rewards idempotent. One server-to-client `ProfileNet.ProfileSnapshot` event copies presentation-safe state; the existing gameplay `Net` remains exactly six remotes and no client can submit progression. The permanent MetaBar, CollectionPanel, discovery/rank presentation, eight station shelves, and shelf template are authored before Play. `CollectionDefinitions` owns catalog order/count, `MasteryDefinitions` owns tier thresholds, and shelf rendering uses a deterministic presentation fingerprint so lifecycle/save-only snapshots return `UNCHANGED` without replacing valid proxies.

The Studio-only failure fixture is disabled by default and is armed on `ServerScriptService.ONE_MORE_ITEM_Server` with `ONE_MORE_ITEM_Phase05AcceptanceMode`, optional `ONE_MORE_ITEM_Phase05AcceptanceTargetUserId`, and a future `ONE_MORE_ITEM_Phase05AcceptanceExpiresAt` no more than 600 seconds ahead. `Unavailable`, `SaveDelayed`, and `Conflict` select the memory adapter for the entire test server. Clear all three attributes before a normal Studio-test persistence run, cloud save, or cloud reopen, and never save the place while armed. Memory-fixture evidence validates failure behavior only; it does not replace the two real Studio-test-store sessions.

See `docs/PHASE05_PERSISTENT_PROGRESSION.md` for the exact accepted evidence, the bridge-observable parity boundary, and the extended QA that remains explicitly unpassed.
