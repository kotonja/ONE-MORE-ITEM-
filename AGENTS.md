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

## Luau and architecture

- Every production and test Luau file begins with `--!strict`.
- Use explicit exported types where useful, focused modules, descriptive names, immutable configuration/content where practical, and deterministic integer-grid gameplay logic.
- Avoid mutable globals, circular dependencies, magic numbers, yielding solvers, frame loops, deprecated scheduling APIs, hidden Workspace/UI dependencies, and unverified external packages.
- Server authority is the future gameplay direction; never add client-authoritative placement results.

## Testing

- Add deterministic tests for behavior changes and run them honestly in Studio or behind an explicit development flag.
- Test failures must be visible, include exact messages, and must never be reported as success.
- Keep fixed seeds for fuzz/property tests and record test totals, failures, seed/case count, and non-gating benchmark results.
- Do not claim a test passed unless fresh Output proves it.

## Scope and status

- Follow the requested phase exactly and do not begin later phases automatically.
- Inspect before changing; do not add UI, maps, systems, or polish outside the active phase.
- Maintain `docs/DEVELOPMENT_STATUS.md` with phase, branch, completed work, tests, known issues, deferred work, exact next phase, and latest relevant commit SHA.
- Documentation must reflect reality; do not claim content was saved, committed, pushed, or tested unless verified.
