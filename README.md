# ONE MORE ITEM!

**PACK THE BOX** — Fit it. Ship it. Or risk one more.

ONE MORE ITEM! is a premium, mobile-first Roblox packing game built around fitting irregular items into a deterministic snap-grid crate.

## Current development phase

Phase 02: Playable Station Vertical Slice. Phase 01's deterministic integer-grid foundation remains authoritative while this branch adds one source-controlled packing station, permanent gameplay HUD, authored remotes, desktop placement presentation, and a server-authoritative session-only round loop. The full arena, persistent progression/economy, mobile/gamepad controls, final assets, audio, monetization, and every later-phase system remain deferred.

## Repository workflow

- `main` is protected by workflow: work happens on `codex/*` feature branches and is reviewed through pull requests.
- Phase 02 uses `codex/phase-02-playable-station`.
- Pull before editing, never force-push, and keep every meaningful Studio/code change committed and pushed.
- `docs/DEVELOPMENT_STATUS.md` is updated on every task.
- GitHub Actions runs both dependency-free Studio blueprint smoke tests on pull requests targeting `main` and pushes to `main` or `codex/**`.

## Studio source workflow

The repository is the only source of truth for scripts and permanent managed instances:

1. Edit canonical sources under `src/` and mappings in `studio/phase01.manifest.json`.
2. In Roblox Studio Edit mode, begin from any place state, including a clean Baseplate. Do not manually create the managed folders.
3. Run `node tools/build_studio_blueprint.mjs` from the repository root.
4. Run `node tools/test_studio_blueprint.mjs` and stop if the smoke test fails.
5. Open `.codex-cache/phase01-command-bar.json` and execute every generated operation, in its generated order, through the Command Bar **Run** action.
6. Confirm that all parent-first `ensureFolder` operations completed before any `writeScript` operation, inspect the exact hierarchy, and run Play tests.

Phase 02 adds `studio/phase02.manifest.json`, `tools/build_phase02_blueprint.mjs`, and `tools/test_phase02_blueprint.mjs`. Its generated Edit-mode operations author permanent `Workspace`, `StarterGui`, `ReplicatedStorage`, `ServerScriptService`, and `StarterPlayerScripts` content with typed properties and attributes. Runtime gameplay code only binds those instances and creates explicitly temporary proxies.

Correct folders and scripts are reused or updated, and missing instances are created. A wrong-class instance at a managed path raises a clear error and is never silently destroyed. Repeating the complete operation list is idempotent and creates no duplicates.

The same build step also emits `.codex-cache/phase01-blueprint.json` for validation and preview. Both generated artifacts are temporary, ignored by Git, and rebuilt deterministically from the same canonical `src/` plus manifest; scripts must never be edited only in Studio.

## Running Phase 01 tests

1. Synchronize the canonical sources to Studio using the workflow above.
2. Confirm `ReplicatedStorage.ONE_MORE_ITEM.Shared.Config.GameConfig.DEVELOPMENT.RUN_FOUNDATION_TESTS` is `true` and run Play in Roblox Studio.
3. Read the Output window for `[ONE_MORE_ITEM][FoundationTests]` totals, exact failures, fuzz seed/case count, and benchmark timing.

The runner exits immediately outside Roblox Studio and fails visibly with `error()` if any test fails.

Phase 02 adds a separate Studio suite for round math, fair sequencing, state transitions, placement security, station ownership, serialization, world transforms, and runtime cleanup. See `docs/PHASE02_VERTICAL_SLICE.md` for the complete test and playtest procedure.

## Phase 01 persistence status

The original private cloud place is verified as persistent. After a controlled cloud publish/save, every Studio process was closed, one clean Studio session reopened the place directly from Roblox, the managed hierarchy matched `7/7` folders and `10/10` scripts with `10/10` exact source matches and zero duplicates, and all 69 foundation tests passed again. The earlier `Internal server error.` incidents were fixed-duration cloud publish timeouts; the later controlled session completed successfully, so no diagnostic replacement place was needed.

## Permanent authoring rule

Permanent UI must be authored as real instances under `StarterGui`, and permanent world content must be authored as real instances under `Workspace`. Runtime Lua may operate those instances but may not generate the permanent UI or arena. Phase 01 creates neither UI nor map content.
