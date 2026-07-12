# ONE MORE ITEM!

**PACK THE BOX** — Fit it. Ship it. Or risk one more.

ONE MORE ITEM! is a premium, mobile-first Roblox packing game built around fitting irregular items into a deterministic snap-grid crate.

## Current development phase

Phase 01: Grid and Placement Foundation. This phase contains only integer-grid shape, rotation, occupancy, auto-drop, placement enumeration, difficulty classification, and Studio-only development tests. UI, world art, rounds, progression, networking, and monetization are intentionally deferred.

## Repository workflow

- `main` is protected by workflow: work happens on `codex/*` feature branches and is reviewed through pull requests.
- Phase 01 uses `codex/phase-01-grid-foundation`.
- Pull before editing, never force-push, and keep every meaningful Studio/code change committed and pushed.
- `docs/DEVELOPMENT_STATUS.md` is updated on every task.

## Studio source workflow

The repository is the only source of truth for Phase 01 scripts:

1. Edit canonical sources under `src/`.
2. Run `node tools/build_studio_blueprint.mjs` from the repository root.
3. From the installed StudioBridge helper repository, run `tools\bridge.cmd blueprint validate "<repo>\.codex-cache\phase01-blueprint.json"`, then `tools\bridge.cmd blueprint apply "<repo>\.codex-cache\phase01-blueprint.json"`.
4. Inspect the live hierarchy and run the Studio test runner.

The generated `.codex-cache/phase01-blueprint.json` is temporary and ignored by Git. It is always rebuilt from `src/` plus `studio/phase01.manifest.json`; scripts must never be edited only in Studio.

## Running Phase 01 tests

1. Synchronize the canonical sources to Studio using the workflow above.
2. Confirm `ReplicatedStorage.ONE_MORE_ITEM.Shared.Config.GameConfig.DEVELOPMENT.RUN_FOUNDATION_TESTS` is `true` and run Play in Roblox Studio.
3. Read the Output window for `[ONE_MORE_ITEM][FoundationTests]` totals, exact failures, fuzz seed/case count, and benchmark timing.

The runner exits immediately outside Roblox Studio and fails visibly with `error()` if any test fails.

## Permanent authoring rule

Permanent UI must be authored as real instances under `StarterGui`, and permanent world content must be authored as real instances under `Workspace`. Runtime Lua may operate those instances but may not generate the permanent UI or arena. Phase 01 creates neither UI nor map content.
