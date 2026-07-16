# ONE MORE ITEM! project rules

## Git and task startup

- GitHub `kotonja/ONE-MORE-ITEM-` is the permanent source of truth.
- At every task start, fetch/pull, confirm the branch and working tree, and preserve newer or unrelated work.
- Never work directly on `main`, merge into `main`, force-push, rewrite published history, or discard work without explicit authorization.
- Use `codex/*` branches, make small working commits, push each meaningful milestone, and open a draft PR when supported.
- Never commit credentials, tokens, personal data, Roblox authentication, autosaves, caches, lock files, or temporary artifacts.
- No meaningful work may remain only local or only in an unsaved Studio session.

## Roblox Studio hierarchy and source control

- Use the `ONE_MORE_ITEM` namespace under `ReplicatedStorage` and `ONE_MORE_ITEM_Server` under `ServerScriptService`.
- Canonical Luau lives under `src/`; the source-controlled manifests under `studio/` map each phase into Studio. Generated blueprints under `.codex-cache/` are temporary.
- Repository-to-Studio synchronization must be folder-first, deterministic, idempotent, and conflict-safe; it must never silently replace or destroy a wrong-class instance.
- Never maintain a divergent Studio-only copy of a script.
- Permanent UI is authored as real `StarterGui` instances. Do not build permanent UI at runtime.
- Permanent map content is authored as real `Workspace` instances. Do not build the arena or permanent decoration at runtime.
- Permanent networking instances and development templates are authored through the manifest as real `ReplicatedStorage` instances. Runtime scripts may bind or clone them but may not recreate them.
- Treat `StarterPlayer.StarterPlayerScripts` as a built-in container, not a managed `Folder`; author children beneath it without replacing it.
- Runtime creation is limited to temporary gameplay/cosmetic objects cloned from prepared templates.
- `studio/phase02.manifest.json` remains the sole canonical owner for permanent Phase 02-and-later gameplay/profile/onboarding UI, remotes, templates, arena content, and mapped scripts unless an explicitly approved phase changes that ownership.

## Luau and architecture

- Every production and test Luau file begins with `--!strict`.
- Use explicit exported types where useful, focused modules, descriptive names, immutable configuration/content where practical, and deterministic integer-grid gameplay logic.
- Avoid mutable globals, circular dependencies, magic numbers, yielding solvers, frame loops, deprecated scheduling APIs, hidden Workspace/UI dependencies, and unverified external packages.
- Server authority is the future gameplay direction; never add client-authoritative placement results.
- Onboarding and starter-mission progress/rewards are server-authoritative. The only Phase 06 client mutation request is the narrowly validated `OnboardingNet.OnboardingActionRequest` skip action; never add a general profile or mission mutation remote.
- Analytics are server-only and best-effort. Studio and deterministic tests must use `MemoryAnalyticsAdapter` and make no real `AnalyticsService` call; published non-Studio servers use the Roblox adapter, and analytics failure must never affect gameplay, progression, assignment, snapshots, or saving.

## Testing

- Add deterministic tests for behavior changes and run them honestly in Studio or behind an explicit development flag.
- Test failures must be visible, include exact messages, and must never be reported as success.
- Keep fixed seeds for fuzz/property tests and record test totals, failures, seed/case count, and non-gating benchmark results.
- Do not claim a test passed unless fresh Output proves it.
- Phase 05 acceptance fixtures are Studio-only, disabled by default, and armed only by the three attributes on `ServerScriptService.ONE_MORE_ITEM_Server`: `ONE_MORE_ITEM_Phase05AcceptanceMode`, `ONE_MORE_ITEM_Phase05AcceptanceTargetUserId`, and `ONE_MORE_ITEM_Phase05AcceptanceExpiresAt`.
- An armed Phase 05 acceptance fixture selects the injected `MemoryProfileAdapter` for the entire test server, not only the targeted player. Allowed modes are `Unavailable`, `SaveDelayed`, and `Conflict`; expiry must be an integer no more than 600 seconds in the future.
- Clear all three Phase 05 acceptance attributes before any normal Studio-test persistence run, cloud save, or cloud reopen. Never save or publish a place while an acceptance fixture is armed, and never treat memory-fixture evidence as a substitute for real Studio-test-store persistence.
- Profile Schema Version 2 keeps `ONE_MORE_ITEM_PlayerProfiles_v1` and `ONE_MORE_ITEM_PlayerProfiles_StudioTest_v1`; never create a new store merely for an in-profile schema migration.

## Scope and status

- Follow the requested phase exactly and do not begin later phases automatically.
- Inspect before changing; do not add UI, maps, systems, or polish outside the active phase.
- Maintain `docs/DEVELOPMENT_STATUS.md` with phase, branch, completed work, tests, known issues, deferred work, exact next phase, and latest relevant commit SHA.
- Documentation must reflect reality; do not claim content was saved, committed, pushed, or tested unless verified.
