# ONE MORE ITEM!

**PACK THE BOX** — Fit it. Ship it. Or risk one more.

ONE MORE ITEM! is a premium, mobile-first Roblox packing game built around fitting irregular items into a deterministic snap-grid crate.

## Current development phase

Phase 03 — Cross-Platform Interaction and Responsive UI: **Implementation complete and accepted.** Implementation head `f04a507eb7cae76a34573cf7d8ba6aaf8b4d7b68` passes the three local Node 24 validations, all 69 Phase 01 tests, all 94 Phase 02 tests, all 65 Phase 03 tests, and corrected-cloud `180/180` managed-path plus `44/44` source parity with exactly six approved remotes and zero duplicate or wrong-class paths. The completed six-profile touch/orientation matrix and deterministic simultaneous second-touch rejection contract are accepted. PR #3 remains draft pending final merge review. Extended controller, hybrid, multiplayer-soak, and physical-device QA remains unpassed and is tracked in [GitHub issue #4](https://github.com/kotonja/ONE-MORE-ITEM-/issues/4); those checks are pre-release QA, not Phase 03 implementation blockers. Phase 04 has not started.

Phase 02 is complete and merged through PR #2 at `73b3428c5ff0068f1e57f89d2150ffb8dccfdf20`; its deterministic grid, authored single station, permanent HUD/remotes, desktop presentation, and server-authoritative session-only round loop remain the protected baseline. Phase 03 is limited to responsive safe-area UI, touch, gamepad, dynamic input prompts, responsive camera anchors, and mid-round local input-mode switching.

## Repository workflow

- `main` is protected by workflow: work happens on `codex/*` feature branches and is reviewed through pull requests.
- Phase 02 was merged through PR #2 at `73b3428c5ff0068f1e57f89d2150ffb8dccfdf20`.
- Phase 03 uses `codex/phase-03-cross-platform-input`; draft PR #3 must remain unmerged.
- Pull before editing, never force-push, and keep every meaningful Studio/code change committed and pushed.
- `docs/DEVELOPMENT_STATUS.md` is updated on every task.
- GitHub Actions uses Node 24 with `actions/checkout@v7` and `actions/setup-node@v6` and runs all three dependency-free validations on pull requests targeting `main` and pushes to `main` or `codex/**`.

## Studio source workflow

The repository is the only source of truth for scripts and permanent managed instances:

1. Edit canonical sources under `src/`. `studio/phase01.manifest.json` owns the foundation hierarchy, while the historically named `studio/phase02.manifest.json` remains the single canonical manifest for the authored vertical slice and Phase 03 responsive additions.
2. In Roblox Studio Edit mode, begin from any place state, including a clean Baseplate. Do not manually create the managed folders.
3. Run `node tools/build_studio_blueprint.mjs` and `node tools/build_phase02_blueprint.mjs` from the repository root.
4. Run `node tools/test_studio_blueprint.mjs`, `node tools/test_phase02_blueprint.mjs`, and `node tools/test_phase03_cross_platform.mjs`; stop if any validation fails.
5. Apply the generated Phase 01 operations first and the extended vertical-slice operations second, preserving generated order.
6. Confirm parent-first creation, exact managed properties and sources, zero wrong-class paths or duplicates, and then run the Studio suites and required Play tests.

Phase 02 adds `studio/phase02.manifest.json`, `tools/build_phase02_blueprint.mjs`, and `tools/test_phase02_blueprint.mjs`. Phase 03 deliberately extends that manifest and test path instead of creating an overlapping owner. Its generated Edit-mode operations author permanent `Workspace`, `StarterGui`, `ReplicatedStorage`, `ServerScriptService`, and `StarterPlayerScripts` content with typed properties and attributes. Runtime gameplay code only binds those instances and creates explicitly temporary proxies.

Correct folders and scripts are reused or updated, and missing instances are created. A wrong-class instance at a managed path raises a clear error and is never silently destroyed. Repeating the complete operation list is idempotent and creates no duplicates.

The same build step also emits `.codex-cache/phase01-blueprint.json` for validation and preview. Both generated artifacts are temporary, ignored by Git, and rebuilt deterministically from the same canonical `src/` plus manifest; scripts must never be edited only in Studio.

## Running Phase 01 tests

1. Synchronize the canonical sources to Studio using the workflow above.
2. Confirm `ReplicatedStorage.ONE_MORE_ITEM.Shared.Config.GameConfig.DEVELOPMENT.RUN_FOUNDATION_TESTS` is `true` and run Play in Roblox Studio.
3. Read the Output window for `[ONE_MORE_ITEM][FoundationTests]` totals, exact failures, fuzz seed/case count, and benchmark timing.

The runner exits immediately outside Roblox Studio and fails visibly with `error()` if any test fails.

Phase 02 adds a separate Studio suite for round math, fair sequencing, state transitions, placement security, station ownership, serialization, world transforms, and runtime cleanup. Phase 03 adds an eight-suite deterministic Studio gate for preferred-input state, responsive layout geometry, touch tracking, gamepad repeat and routing, prompts, camera targets, character-control cleanup, and remote discipline. See `docs/PHASE02_VERTICAL_SLICE.md` and `docs/PHASE03_CROSS_PLATFORM.md` for the complete procedures and verified evidence.

## Phase 01 persistence status

The original private cloud place is verified as persistent. After a controlled cloud publish/save, every Studio process was closed, one clean Studio session reopened the place directly from Roblox, the managed hierarchy matched `7/7` folders and `10/10` scripts with `10/10` exact source matches and zero duplicates, and all 69 foundation tests passed again. The earlier `Internal server error.` incidents were fixed-duration cloud publish timeouts; the later controlled session completed successfully, so no diagnostic replacement place was needed.

## Permanent authoring rule

Permanent UI must be authored as real instances under `StarterGui`, and permanent world content must be authored as real instances under `Workspace`. Runtime Lua may operate those instances but may not generate the permanent UI or arena. Phase 01 creates neither UI nor map content.

## Phase 03 cross-platform contract

Phase 03 retains the same server round and six authored remotes. `UserInputService.PreferredInput` selects only local `KeyboardMouse`, `Touch`, or `Gamepad` presentation. Viewport geometry independently selects `Wide`, `CompactLandscape`, or `Portrait`; authored UI is constrained to Roblox-reported safe areas, and authored camera anchors keep the crate framed. Touch drag and gamepad grid movement update only the local ghost, while Place, Decision, and Pack Again continue through the existing server-authoritative requests.
