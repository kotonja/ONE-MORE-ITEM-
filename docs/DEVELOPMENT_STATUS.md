# Development status

## Current phase and Git state

- **Phase result:** **Phase 06 active; not yet accepted.** Phase 05 is complete and merged, while every Phase 06 implementation, Studio, persistence, cloud-reopen, cross-platform, analytics, and exact-head CI gate remains pending until freshly verified.
- **Current phase:** Phase 06 - First-Time Player Experience, Starter Missions, and Retention Analytics.
- **Current branch:** `codex/phase-06-onboarding-starter-missions`.
- **Protected base:** `main` and `origin/main` are the accepted Phase 05 squash merge `d644411b48e20cd9bb256d3d2c55a647efc2adfd`.
- **Phase 05 merge:** [PR #6 - Phase 05: Persistent Profiles, Collection, and Packing Rank](https://github.com/kotonja/ONE-MORE-ITEM-/pull/6) is merged as `d644411b48e20cd9bb256d3d2c55a647efc2adfd`.
- **Current pull request:** pending the opening branch commit and initial push; one Phase 06 draft PR will be created from `codex/phase-06-onboarding-starter-missions` and must remain unmerged.
- **Latest implementation SHA:** no Phase 06 implementation commit exists yet; the opening status-correction commit starts the branch history.
- **Pre-release QA:** [Issue #4 - Pre-release cross-platform and multiplayer integration QA](https://github.com/kotonja/ONE-MORE-ITEM-/issues/4) remains open; its [Phase 05 persistence QA additions](https://github.com/kotonja/ONE-MORE-ITEM-/issues/4#issuecomment-4983229288) list the explicitly deferred and unpassed work.
- **Scope:** Phase 06 has begun. No Phase 07 system, monetization, production-store rollout, final asset work, or unrelated redesign is authorized.

## Phase 04 protected baseline

Phase 04 remains complete and merged at `213f3581bd242523e34601cfefa5b5a74770ddee`. Phase 05 extends that baseline without adding a gameplay remote, client-authoritative progression, or final-asset dependency. The existing six server-authoritative gameplay remotes and eight-station arena remain intact.

## Phase 05 implementation result

The accepted implementation includes:

- strict shared collection, mastery, rank, progression, and profile-network definitions;
- server-only Version 1 schema/migration, guarded DataStore adapter, deterministic memory adapter, lock-aware lifecycle, scheduler/autosave, snapshots, and deterministic progression;
- load-before-assignment, server-created OutcomeIds, exact-once receipts, persistent Tape/XP/statistics/discovery/mastery, and bounded release/shutdown behavior;
- one permanent server-to-client `ReplicatedStorage.ONE_MORE_ITEM.ProfileNet.ProfileSnapshot` event while retaining exactly six gameplay remotes;
- permanently authored MetaBar, DataStatus, CollectionPanel/eight slots, discovery/rank/results presentation, eight station shelves, and one script-free development shelf proxy template; and
- `studio/phase02.manifest.json` as the sole permanent-instance owner for Phase 02-05.

The canonical target remains 909 unique managed paths: 834 non-script instances and 75 Luau sources. The Phase 02-05 blueprint remains 898 operations and 65 sources.

## Final shelf and catalog correction

`CollectionShelfService` now derives its rank label, valid discoveries, canonical mastery counts, recent order, and featured item list before calculating a stable presentation fingerprint. Lifecycle state, SaveState, snapshot revision, session identifiers, receipts, undisplayed statistics, Tape, and XP that does not change displayed rank are excluded.

- A valid matching runtime returns `true, "UNCHANGED"`, preserves proxy identities/count, and rewrites no unchanged label.
- Changed presentation or malformed runtime clears and rebuilds once, stores the new fingerprint, and returns `true, "RENDERED"`.
- `Clear`/`ClearAll` invalidate cached presentation. Release leaves Runtime empty, `ProfileRendered=false`, `FeaturedItemCount=0`, and no owner cache; an identical replacement owner therefore gets fresh proxies.
- The six-proxy maximum and station isolation remain enforced. No shelf loop, remote, or persistence responsibility was added.
- `CollectionDefinitions.OrderedItemIds`, `CollectionDefinitions.TotalCount`, and catalog indexes are canonical for shelves and collection slots. `MasteryDefinitions.GetMasteryTier` owns tier thresholds; shelf code no longer duplicates 5/20/50.
- `ProfileUIController` maps authored slots from canonical catalog order, resolves display data through `DevelopmentItemDefinitions`, validates exact slot/catalog count and uniqueness at startup, and creates no runtime slots.

Focused regressions cover first/identical/save-only/in-rank-XP rendering, rank/discovery/mastery changes, clear/reassignment, eight-station isolation, malformed recovery, ten identical cycles, and a memory-adapter reward -> Saving -> Saved lifecycle. The focused memory lifecycle produced one progression rebuild, stable proxy identities/count through Saving/Saved, and cleanup back to zero.

## Profile storage and fixture safety

| Contract | Accepted result |
| --- | --- |
| Schema | Version `1`; deterministic defaults, Version 0 migration, Version 1 normalization/copy, and future-version rejection. |
| Production configuration | `ONE_MORE_ITEM_PlayerProfiles_v1` outside Studio. **No production-store access, test, or rollout is claimed.** |
| Normal Studio persistence | `ONE_MORE_ITEM_PlayerProfiles_StudioTest_v1` only. Memory fixtures were not used as persistence proof. |
| Deterministic/failure storage | Injected `MemoryProfileAdapter`; network-free behavior evidence only. |
| Writes and bounds | Guarded `UpdateAsync` with non-yielding transforms; bounded retries, locks, receipts, scheduler concurrency, and shutdown. |

The three Studio-only acceptance attributes were `nil`, `nil`, `nil` before synchronization, before cloud save, and after direct reopen:

```text
ONE_MORE_ITEM_Phase05AcceptanceMode
ONE_MORE_ITEM_Phase05AcceptanceTargetUserId
ONE_MORE_ITEM_Phase05AcceptanceExpiresAt
```

No place save or publish occurred while a fixture was armed. The useful default-off fixture remains in source for controlled `Unavailable`, `SaveDelayed`, and `Conflict` checks.

## Local Node 24 validation

Fresh local output passed all five dependency-free gates:

```text
[StudioSyncSmoke] PASS checks=16 folders=7 scripts=10 deterministic=true
[Phase02StudioSyncSmoke] PASS criteria=28 instances=833 scripts=65 remotes=6 deterministic=true phase01=true
[Phase03LayoutMatrix] PASS viewports=13 insetProfiles=5 cases=65 desktopCompatible=true safeContainment=true
[Phase03CrossPlatformSmoke] PASS criteria=31 viewports=13 insetProfiles=5 layoutCases=65 remotes=6 deterministic=true phase01=true phase02=true
[Phase04MultiplayerArena] PASS criteria=42 instances=833 scripts=65 stations=8 pathNodes=16 remotes=6 deterministic=true prior=true
[Phase05PersistentProgression] PASS criteria=64 instances=833 scripts=65 gameplayRemotes=6 profileRemotes=1 shelves=8 collectionSlots=8 deterministic=true prior=true
```

`git diff --check` passes for the corrected source/documentation tree.

## Post-reopen Studio suites

All five suites passed in the directly reopened cloud place:

| Suite | Suites/tests | Failed | Seed and timing |
| --- | ---: | ---: | --- |
| Foundation | `15 / 69/69` | `0` | fuzz seed `24012026`, 1,000 cases, `0.256185s`; benchmark `0.115899s` non-gating |
| Phase 02 | `11 / 94/94` | `0` | seed `24022026`, `6.280816s` |
| Phase 03 | `8 / 65/65` | `0` | seed `13072026`, `0.004279s` |
| Phase 04 | `13 / 119/119` | `0` | seed `14072026`, `0.687169s` |
| Phase 05 | `16 / 130/130` | `0` | seed `15072026`, `0.341500s`, deterministic adapter `memory` |

The Phase 05 suite's injected memory adapter is deterministic test isolation only. The normal Play server separately used the Studio-test store. After unsaved acceptance observers were removed, the final clean verification contained zero fresh game-owned warnings/errors; unrelated Studio/plugin diagnostics are not represented as game-owned failures.

## Canonical cloud synchronization, save, and reopen

- A recovery copy was kept outside Git; no place file, recovery path, log, screenshot, or generated cache is tracked.
- With acceptance attributes absent, the Phase 02-05 apply ran at `2026-07-15T15:33:38Z` and again at `2026-07-15T15:36:21Z`. Each pass reported `Updated=898`, `Created=0`, `Skipped=0`, `Failed=0`, `Warnings=0`, with 65 script backups.
- Save to Roblox completed normally with `Saving to Roblox...` followed by `Saved new changes in "ONE MORE ITEM!" to Roblox.`
- Every Studio process closed and the process count reached `0`.
- Roblox Studio build `0.730.0.7300790` reopened the original private place through the normal signed-in route. The observed reopened process count was `2` (the editor plus a Studio-owned renderer/helper process), the place was in Edit mode, and the expected place/game identifiers matched.
- No repository synchronization ran after reopen.
- The earlier TLS/no-join-snapshot incident remains preserved as historical evidence in `CHANGELOG.md`; it is not rewritten as though the correction had been cloud-saved before this successful pass.

## Post-reopen parity audit

The read-only audit passed the helper's bounded observable projection:

```text
managed=909/909
uniqueLive=909
classes=909/909
properties=5660/5660
sources=75/75
missing=0
unexpected=0
duplicate=0
wrongClass=0
propertyMismatch=0
sourceDivergence=0
structureFailure=0
```

Structural proof additionally reported `shelves=8/8`, `shelfSlots=48/48`, `emptyRuntime=8/8`, `collectionSlots=8/8`, `gameplayRemotes=6/6`, and `profileRemotes=1/1`, with no client-to-server profile mutation remote. MetaBar, DataStatus, CollectionPanel, DiscoveryReveal, RankUpBanner, Results progression fields, and `CollectionShelfItemTemplate` were present.

Parity coverage reported `authored=5567`, `compared=5660`, and `helperUnobservable=383`. Accordingly, `properties=5660/5660` means every bridge-observable comparison passed; it is not a claim that the helper independently read back the 383 unsupported keys/attributes. Exact canonical source comparison was `75/75` using UTF-8 SHA-256.

## Current-code profile persistence

Current synchronized source received a fresh Session C/D confirmation against the normal Studio-test store. Sanitized evidence only is recorded; no player identifier, store key, lock token, OutcomeId value, or full profile payload appears here.

| Evidence | Accepted result |
| --- | --- |
| Session C baseline | Ready/Saved, Rookie Packer, Tape `588`, XP `97`, Parcel mastery `5`, discovered `5`, successful shipments `5`, total items `10`, total Tape earned `588`, receipt count `27`, five shelf proxies. Previously saved progression loaded without reward replay or duplicate Tape/XP; station assignment followed Ready. |
| Session C one-Parcel result | Tape `603` (`+15`), XP `111` (`+14`), Parcel mastery `6` (`+1`), successful shipments `6` (`+1`), total items `11` (`+1`), total Tape earned `603` (`+15`), discovered count unchanged at `5`, receipt count `28` (`+1`), one reward reveal. |
| Session C save behavior | Snapshot order included Loading -> Saved -> Saving -> Saved and settled Ready/Saved. The progression change caused exactly one physical five-proxy replacement cycle; Saving/Saved preserved the replacement proxy identities and child count and did not replay the reward. |
| Session D direct second Play | Loaded Tape `603`, XP `111`, Rookie Packer, Parcel mastery `6`, discovered `5`, successful shipments `6`, total items `11`, total Tape earned `603`, and receipt count `28`; Ready/Saved, five shelf proxies, no prior reward replay, and no gameplay request at load. |

This supplements rather than erases the earlier Session A/B proof, which remains valid historical evidence from the isolated Studio-test store. Controlled memory-fixture wallets were never substituted for either proof.

## Focused touch and gamepad Collection acceptance

The touch check used Studio Device Emulator with an iPhone XR profile, first portrait and then landscape (`896x414` reported in landscape). It does **not** claim a physical phone. The Collection button and panel stayed within the Roblox-reported safe area, one tap opened once, all eight authored slots were reachable/readable with correct locked/discovered treatment and readable mastery progress, panel interception prevented underlying Results/gameplay activation, one close tap closed cleanly, no active placement touch remained, and open/close produced no gameplay-remote delta.

The gamepad check used Studio Controller Emulator with the Xbox One virtual controller. It does **not** claim a physical controller. In Results, the normal gamepad trace showed three bound actions, `RESTART`, and Pack Again selected. ButtonY changed the panel to open once, selected the first discovered slot, and suppressed bindings to zero with no selected gameplay action. Locked slots remained non-selectable/non-interactable; ButtonA on the discovered slot sent no gameplay or profile mutation; ButtonB closed the panel and cleared focus. The emulator's clickable overlay changed PreferredInput back to KeyboardMouse before closure, so the state-appropriate closed value was zero/nil; the trace does not fabricate a gamepad restore while mouse input is preferred. No binding duplication or gameplay-remote delta occurred.

## Controlled failure and earlier persistence evidence

Controlled default-off memory fixtures previously passed bounded Unavailable loading, SaveDelayed retry/recovery without reward loss or replay, Conflict station/round/shelf cleanup, unaffected-player isolation, and deterministic eight-profile capacity/shutdown. The transient amber Save Delayed frame and a forced-leave shelf cleanup log were not manually captured; these are non-blocking presentation/soak items, not claims of failure.

Earlier real Session A/B Studio-test-store proof remains documented in the Phase 05 contract: Session A persisted Tape `15`, XP `16`, Parcel mastery `1`, and one shipment; a complete close/direct no-sync reopen loaded those values; Session B applied a second reward once and persisted Tape `30`, XP `30`, Parcel mastery `2`, and two shipments. The later blocked cloud-reopen incident and offline recovery-copy limitation remain preserved in the changelog as historical sequence.

## GitHub Actions

- **Workflow:** `Phase 01–05 Node Validation`; Node 24; `actions/checkout@v7`; `actions/setup-node@v6`; `contents: read`; no dependency install or third-party package.
- **Triggers:** pull requests targeting `main`, pushes to `main`, and pushes to `codex/**`.
- **Implementation head:** `07d887a11c4ff5256ee663f6f306e9ca41cfbedf`.
- **Branch-push:** run `29428471528`, job `87396972732`, success.
- **Draft PR:** run `29428474234`, job `87396981747`, success.
- Both implementation-head runs completed setup, checkout, Node setup, Phase 01, Phase 02, Phase 03, Phase 04, Phase 05, post steps, and workflow completion successfully.
- The final documentation commit and its exact-head branch/PR runs are recorded in PR #6 and the final handoff.

## Known issues and deferred pre-release QA

There is no known Phase 05 implementation blocker. The following remain unpassed in open [issue #4's Phase 05 persistence QA additions](https://github.com/kotonja/ONE-MORE-ITEM-/issues/4#issuecomment-4983229288); they do not weaken the accepted deterministic, Studio-test persistence, cloud-save/reopen, or bounded parity evidence:

- eight-player production DataStore request-budget observation;
- long-session autosave and lock-heartbeat soak;
- abrupt-server-shutdown, stale-lock, and rapid-reconnect recovery;
- production-store rollout rehearsal and Data Stores Manager inspection;
- low-connectivity Save Delayed presentation;
- physical phone and physical controller Collection testing;
- extended profile-entry/receipt-memory observation; and
- extended station-release and shelf-cleanup soak.

No production DataStore rollout, current published `MaxPlayers`, lower-end-device result, or final-art result is claimed. Development geometry and text-only iconography remain non-final.

## Deferred by design

Daily challenges, starter missions, offline income, cosmetics/ownership/store, Robux products, monetization, trading, pets, rebirths, multiple worlds, co-op packing, cheer reactions, persistent/global/OrderedDataStore leaderboards, analytics, quests, final object models, external assets, sound/music, final VFX, haptics, final Tape wrap, item power, functional mastery bonuses, rank power bonuses, and every Phase 06 system remain deferred.

## Exact next phase recommendation

PR #6 is complete and ready for final review, but it must remain draft and unmerged until that review is intentionally concluded. Keep issue #4 open for the deferred pre-release QA above. Do not begin Phase 06 in this task.
