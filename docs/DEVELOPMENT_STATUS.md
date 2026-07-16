# Development status

## Current phase and Git state

- **Phase result:** **Partial.** Phase 06 implementation is complete and its automated gates are green, but the complete manual/persistence acceptance contract is not yet satisfied.
- **Current phase:** Phase 06 - First-Time Player Experience, Starter Missions, and Retention Analytics.
- **Current branch:** `codex/phase-06-onboarding-starter-missions`.
- **Protected base:** `main` and `origin/main` remain the accepted Phase 05 squash merge `d644411b48e20cd9bb256d3d2c55a647efc2adfd`.
- **Current implementation head:** `4fe9c97a1ab5eeef4e18c34a6a584e2ed1ec8701` before this evidence-only documentation update. The production implementation commit is `5541c21434386104aac8fd85ccd934477ba8c23e`; `4fe9c97` contains the focused Phase 06 conflict-fixture correction.
- **Current pull request:** [Draft PR #7 - Phase 06: Onboarding, Starter Missions, and Retention Analytics](https://github.com/kotonja/ONE-MORE-ITEM-/pull/7), open, draft, and unmerged.
- **Pre-release QA:** [Issue #4](https://github.com/kotonja/ONE-MORE-ITEM-/issues/4) remains open. Its Phase 06 comment has intentionally not been posted because technical acceptance is still partial.
- **Scope:** No Phase 07 system, monetization, production-store rollout, final asset work, or unrelated redesign has begun.

## Implemented Phase 06 scope

- Profile schema Version 2 with an explicit Version 1-to-2 migration while retaining `ONE_MORE_ITEM_PlayerProfiles_v1` and `ONE_MORE_ITEM_PlayerProfiles_StudioTest_v1`.
- Server-authoritative five-step onboarding with `NotStarted`, `InProgress`, `Completed`, and `Skipped` states; 45-second guided placement; 12-second guided decision; failure/retry; exact-once skip; and persistent progress.
- Five authoritative starter missions (`first_fit`, `first_shipment`, `one_more`, `collector_three`, and `five_item_box`) worth exactly 295 Tape and 210 XP in total, with reconciliation, exact-once rewards, and path completion.
- `MemoryAnalyticsAdapter` in Studio and `RobloxAnalyticsAdapter` outside Studio, with fixed onboarding, core-loop, mission, economy, and starter-path event catalogs and bounded low-cardinality fields.
- Permanent manifest-authored `OnboardingOverlay`, `StarterMissionCard`, `StarterPathPanel` with five authored mission rows, `MissionCompleteBanner`, and one `OnboardingActionRequest` remote.
- Server validation, rate/sequence checks, player-scoped state, cleanup, responsive layout, and deterministic test seams.

No permanent UI, networking object, or map artifact is created at runtime. The manifest remains the permanent-instance owner and source under `src/` remains canonical.

## Canonical Studio state before cloud save

- Phase 01 and the extended Phase 02-06 synchronization were each applied twice without duplicates, wrong classes, creation failures, or warnings.
- The live place contained 1,004 unique managed paths: 915 non-script instances and 89 Luau sources.
- All 89 canonical source hashes matched. The bridge compared every supported managed property without a mismatch; helper-unobservable keys remained covered by static validation and the deterministic double-apply result.
- Structural checks found eight stations, eight shelves, 48 shelf slots, six gameplay remotes, one profile snapshot remote, one onboarding request remote, and four Phase 06 UI roots.
- The three Phase 05 acceptance attributes printed `nil`, `nil`, `nil` immediately before cloud save. No fixture was armed when the place was saved.

## Automated validation

Fresh local Node 24 output passed all six dependency-free gates:

```text
[StudioSyncSmoke] PASS checks=16 folders=7 scripts=10 deterministic=true
[Phase02StudioSyncSmoke] PASS criteria=28 instances=914 scripts=79 remotes=6 deterministic=true phase01=true
[Phase03LayoutMatrix] PASS viewports=13 insetProfiles=5 cases=65 desktopCompatible=true safeContainment=true
[Phase03CrossPlatformSmoke] PASS criteria=31 viewports=13 insetProfiles=5 layoutCases=65 remotes=6 deterministic=true phase01=true phase02=true
[Phase04MultiplayerArena] PASS criteria=42 instances=914 scripts=79 stations=8 pathNodes=16 remotes=6 deterministic=true prior=true
[Phase05PersistentProgression] PASS criteria=64 instances=914 scripts=79 gameplayRemotes=6 profileRemotes=1 shelves=8 collectionSlots=8 deterministic=true prior=true
[Phase06OnboardingMissionsAnalytics] PASS criteria=69 instances=914 scripts=79 gameplayRemotes=6 profileRemotes=1 onboardingRemotes=1 onboardingSteps=5 starterMissions=5 missionTape=295 missionXP=210 deterministic=true prior=true
```

Fresh pre-cloud-save Studio Output passed all six suites:

| Suite | Result | Deterministic detail |
| --- | ---: | --- |
| Foundation | `69/69` | fuzz seed `24012026`, 1,000 cases; benchmark non-gating |
| Phase 02 | `94/94` | seed `24022026` |
| Phase 03 | `65/65` | seed `13072026` |
| Phase 04 | `119/119` | seed `14072026` |
| Phase 05 | `130/130` | seed `15072026`; memory adapter |
| Phase 06 | `58/58` | seed `16072026`; profile and analytics memory adapters |

The first Phase 06 Studio run exposed a test-fixture defect: its conflict case saved a clean profile and therefore never exercised a conflict. Only the deterministic test fixture was corrected to dirty both sessions and assert `CONFLICT`; the fresh rerun passed `58/58`. No production source defect was found.

## Manual Studio evidence

### Established-profile migration and onboarding

- The accepted Phase 05 Studio-test profile loaded from `ONE_MORE_ITEM_PlayerProfiles_StudioTest_v1`, migrated to Version 2, and kept its recorded Tape, XP, rank, collection, and gameplay statistics. Full mastery and receipt values were not captured before migration, so the complete field-by-field Session E preservation checklist is not claimed.
- Historical statistics reconciled `first_shipment`, `collector_three`, and `five_item_box` exactly once for `+250 Tape` and `+170 XP`.
- A failed guided round remained at onboarding Step 3 and the next round remained guided.
- The first accepted placement awarded exactly `+10 Tape` and `+10 XP`, advanced Step 4, and showed the mission presentation once.
- A successful first shipment completed onboarding, hid the overlay, and switched to normal timing. Because `first_shipment` had already reconciled from historical statistics, the shipment correctly did not replay that mission reward.
- A normal One More path awarded `+35 Tape` and `+30 XP`. The durable profile reached 5/5 missions, 295 total mission Tape, 210 total mission XP, and Saved.
- Clean shutdown reported one success, zero failures, and zero skipped profiles.

This was an established-profile Session E path, not the prescribed isolated truly fresh-profile Play fixture. That exact fresh-profile manual gate remains unpassed.

### Cross-platform presentation

- Desktop onboarding, failure/retry, first shipment, mission banners, compact mission card, and normal timing were visually exercised.
- Studio Device Emulator provided partial phone portrait and landscape touch evidence. Touch copy contained no keyboard labels, drag/place controls responded, Results/Pack Again remained safe-area contained, and orientation changes did not reset durable progress. The complete Ship, SkipButton/mission-card safe-area, starter-panel, and underlying-drag suppression matrix remains unpassed. No physical-phone claim is made.
- Studio Controller Emulator at 1920x1080 showed controller movement copy, `[X]`, `[A]`, and `[L1]` prompts plus gamepad focus. The complete hold-B cancellation/completion, L1/B panel flow, and binding-duplication matrix remains unpassed. No physical-controller claim is made.
- Skip acceptance remains partial. Deterministic coverage verifies strict validation, no reward, and exact-once state transitions, while the two-player memory test below proves per-player UI isolation. Dedicated mouse/touch acceptance, hold-B gamepad cancellation/completion, rejoin persistence, next-round normal timing, one analytics emission, and duplicate no-op were not all manually completed.

### Two-player Local Server

- A two-client Local Server launched with isolated memory profiles and distinct `O1`/`O2` station state.
- Skipping Player B hid only Player B's onboarding and exposed only Player B's starter mission card while Player A remained in onboarding.
- The prescribed starting fixture (Player A new, Player B onboarding-complete with partial starter path) and the complete timing, placement, One More, reward, analytics, shelf, revision, and conflict-isolation matrix remain unpassed.

## Analytics evidence

Deterministic Studio coverage passes event naming, onboarding steps, core-loop, mission, economy, progression, ordering, privacy/cardinality, cleanup, and injected-failure isolation without an AnalyticsService network call. The attachment's additional single integrated interactive memory-sink trace for one complete fresh-player path was not separately captured and remains unpassed.

## Profile persistence Sessions E/F

Session E reached Ready/Saved as Version 2 and the Studio process shut down cleanly. Session F is incomplete because the required direct cloud reopen did not finish.

Session E ended with the current durable Studio-test profile at all five defined missions rewarded, leaving no defined new mission event for Session F's requested same-profile exact reward. Rewinding a reward flag, inventing a sixth mission/path reward, or silently substituting another profile would violate the contract. Same-profile reload/no-replay can still be tested, while exact one-reward behavior is separately proven with deterministic memory integration; completing this gate now requires a user-approved recovery or alternate evidence route.

## Cloud save and reopen

- An external recovery copy was created outside Git.
- The original private place (`PlaceId 134193642444044`, `GameId 10493030248`) reported `Saving to Roblox...` followed by `Saved new changes in "ONE MORE ITEM!" to Roblox.`
- Every Studio process closed and the observed Studio process count reached zero.
- Two direct, no-synchronization reopen attempts selected the correct cloud experience. Studio fetched the correct place/universe, completed preloading, connected to the Roblox edit server, initialized the schema, and assigned a peer ID, but the UI remained indefinitely at `Connecting to server...`.
- Because the editor never completed the direct reopen, post-reopen hierarchy/source parity, fixture absence, six-suite rerun, Session F reload/no-replay, one additional onboarding/mission/save proof, and fresh Output review remain unpassed.

The normal cloud save and full close are confirmed. This document does **not** claim successful direct reopen or full Phase 06 cloud persistence acceptance.

## GitHub Actions

At implementation head `4fe9c97a1ab5eeef4e18c34a6a584e2ed1ec8701`, both exact-head checks passed:

- push run `29526402031`, job `87715799209`;
- pull-request run `29526404937`, job `87715808683`.

Both jobs ran all six Node validations. A documentation/evidence commit requires fresh push and pull-request checks before its SHA can be called the final exact head.

## Known issues and remaining Phase 06 acceptance

- Prescribed truly fresh-profile desktop Play path is not yet manually proven.
- Full gamepad hold-B and starter-panel control matrix is incomplete.
- Full two-player Local Server isolation matrix is incomplete.
- One integrated interactive analytics-memory trace is not captured.
- Session F direct reload/no-replay and its current 5/5 durable-profile evidence constraint remain incomplete.
- Direct cloud reopen, post-reopen parity, post-reopen suites, and post-reopen clean Output remain incomplete.
- Issue #4 has no Phase 06 comment yet by design; the comment is permitted only after technical acceptance.

No confirmed Phase 06 production-code blocker is known. The remaining problems are acceptance evidence gaps, a direct Studio cloud-join failure, and the Session E/F test-sequencing constraint described above.

## Deferred pre-release QA

Issue #4 remains the single tracker for published Analytics dashboard appearance, real-traffic funnel population, custom-event cardinality/daily aggregation, D1/D7/D30 retention, physical phone/controller onboarding, eight-player simultaneous first sessions, long mission-presentation soak, low-connectivity analytics observation, production mission balance, tutorial skip rate, and first-shipment conversion. None is claimed as passed.

## Deferred by design

Daily challenges/rewards, login streaks, offline income, additional catalog objects, final models/assets, cosmetics/ownership/store, Robux products, monetization, trading, pets, rebirths, multiple worlds, co-op packing, cheer reactions, persistent/global/OrderedDataStore leaderboards, experiments, quests beyond the five starter missions, final sound/music/VFX, haptics, functional mission/rank/mastery bonuses, and every Phase 07 system remain deferred.

## Exact next phase recommendation

Phase 07 is the only next phase, but it must not begin until the remaining Phase 06 acceptance gates and Session F evidence route are resolved. Keep PR #7 draft and unmerged, and keep issue #4 open.

Complete the direct reopen/parity/manual gaps, refresh the final exact-head checks, and then request explicit review/merge authorization.
