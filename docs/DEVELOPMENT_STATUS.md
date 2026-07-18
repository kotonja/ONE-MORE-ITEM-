# Development status

## Current phase and Git state

- **Phase result:** **Implementation complete and accepted.**
- **Current phase:** Phase 06 - First-Time Player Experience, Starter Missions, and Retention Analytics.
- **Current branch:** `codex/phase-06-onboarding-starter-missions`.
- **Protected base:** `main` and `origin/main` remain the accepted Phase 05 squash merge `d644411b48e20cd9bb256d3d2c55a647efc2adfd`.
- **Accepted implementation head:** `f877667b3ce9f032d0a0c676dafb348bb2ad6d8f`.
- **Final documentation head:** recorded in draft PR #7 and the final completion handoff after this documentation commit exists; this file intentionally does not self-reference its own commit SHA.
- **Current pull request:** [Draft PR #7 - Phase 06: Onboarding, Starter Missions, and Retention Analytics](https://github.com/kotonja/ONE-MORE-ITEM-/pull/7), open, draft, and unmerged.
- **Pre-release QA:** [Issue #4](https://github.com/kotonja/ONE-MORE-ITEM-/issues/4) remains open. Its [Phase 06 onboarding and analytics QA additions](https://github.com/kotonja/ONE-MORE-ITEM-/issues/4#issuecomment-5007354615) keep the broad checks explicitly unpassed.
- **Scope:** Phase 07 has not begun. No monetization, production-store rollout, final asset work, or unrelated redesign was added.

## Accepted Phase 06 implementation

- Profile Schema Version 2 migrates Version 1 inside the existing `ONE_MORE_ITEM_PlayerProfiles_v1` and `ONE_MORE_ITEM_PlayerProfiles_StudioTest_v1` stores.
- Five server-authoritative onboarding steps persist `NotStarted`, `InProgress`, `Completed`, or `Skipped`; guided placement remains 45 seconds and guided decision remains 12 seconds.
- Five exact-once starter missions (`first_fit`, `first_shipment`, `one_more`, `collector_three`, and `five_item_box`) remain worth 295 Tape and 210 Packing XP in total.
- Permanent onboarding and mission UI, five mission rows, the one narrow `OnboardingActionRequest` remote, remotes, templates, and scripts remain manifest-authored. No permanent UI, networking object, or map artifact is created at runtime.
- Studio uses `MemoryAnalyticsAdapter`; published non-Studio servers select the Roblox adapter. Analytics remains server-only, best-effort, and unable to alter gameplay, assignment, progression, snapshots, or saving.

## Source-quality corrections

### Deterministic onboarding completion presentation

The onboarding controller now uses an explicit `Idle` / `Pending` / `Showing` / `Consumed` reducer. Profile-first and round-first arrival both produce the same approved terminal presentation:

```text
SHIPMENT COMPLETE
TAPE IS SAVED
SHIPPED ITEMS JOIN YOUR COLLECTION
```

The presentation holds for exactly `0.95` seconds, displays once, cannot replay after duplicate snapshots or reload, and remains hidden while a player is unassigned. Cancellation consumes stale/cross-round work. `ClientBootstrap` subscribes to onboarding completion before mission presentation, while `StarterMissionUIController.SetPresentationBlocked` pauses and losslessly resumes a queued mission banner after the onboarding hold.

### Transactional analytics ordering

`StarterMissionService.ApplyEventDeferredAnalytics` returns a one-shot emitter: the profile mutation and snapshot happen first, then the caller emits the mission analytics exactly once at the correct transactional boundary. The first successful path now records:

1. First Fit starter-mission economy `+10`, ending balance `10`.
2. Shipment economy `+15`, ending balance `25`.
3. First Shipment starter-mission economy `+25`, ending balance `50`.

Each analytics call remains independently protected. A failure in one record cannot suppress later records or mutate the authoritative outcome.

## Automated validation

Fresh local Node 24 output passed every dependency-free gate:

```text
[StudioSyncSmoke] PASS checks=16 folders=7 scripts=10 deterministic=true
[Phase02StudioSyncSmoke] PASS criteria=28 instances=914 scripts=79 remotes=6 deterministic=true phase01=true
[Phase03CrossPlatformSmoke] PASS criteria=31 viewports=13 insetProfiles=5 layoutCases=65 remotes=6 deterministic=true phase01=true phase02=true
[Phase04MultiplayerArena] PASS criteria=42 instances=914 scripts=79 stations=8 pathNodes=16 remotes=6 deterministic=true prior=true
[Phase05PersistentProgression] PASS criteria=64 instances=914 scripts=79 gameplayRemotes=6 profileRemotes=1 shelves=8 collectionSlots=8 deterministic=true prior=true
[Phase06OnboardingMissionsAnalytics] PASS criteria=76 instances=914 scripts=79 gameplayRemotes=6 profileRemotes=1 onboardingRemotes=1 onboardingSteps=5 starterMissions=5 missionTape=295 missionXP=210 deterministic=true prior=true
```

The final clean pre-save Studio run passed:

| Suite | Result | Deterministic detail |
| --- | ---: | --- |
| Foundation | `69/69` | 15 suites; fuzz seed `24012026`, 1,000 cases; benchmark non-gating |
| Phase 02 | `94/94` | 11 suites; seed `24022026` |
| Phase 03 | `65/65` | 8 suites; seed `13072026` |
| Phase 04 | `119/119` | 13 suites; seed `14072026` |
| Phase 05 | `130/130` | 16 suites; seed `15072026`; memory adapter |
| Phase 06 | `75/75` | 18 suites; seed `16072026`; profile and analytics memory adapters |

The first attempted Phase 06 source-quality test run exposed a syntax defect in the integration harness. It was corrected in `f877667b3ce9f032d0a0c676dafb348bb2ad6d8f`; only the fresh passing run above is acceptance evidence.

## Integrated analytics trace

The accepted fresh-profile deterministic integration emitted exactly these 20 records in order:

1. `Onboarding:1`
2. `ProgressionStart:1`
3. `Mission:first_fit:started`
4. `Onboarding:2`
5. `CoreLoop:start`
6. `Onboarding:3`
7. `Economy:StarterMission:10:10`
8. `ProgressionComplete:1`
9. `Mission:first_fit:completed`
10. `ProgressionStart:2`
11. `Mission:first_shipment:started`
12. `Onboarding:4`
13. `Onboarding:5`
14. `Economy:Shipment:15:25`
15. `Economy:StarterMission:25:50`
16. `ProgressionComplete:2`
17. `Mission:first_shipment:completed`
18. `ProgressionStart:3`
19. `Mission:one_more:started`
20. `CoreLoop:ship`

The final authoritative state was Tape `50`, Packing XP `44`, onboarding `Completed`, First Fit and First Shipment rewarded, and the round in `Shipping`. Duplicate event delivery, explicit save, release, and reload produced no durable analytics replay and no reward replay. A run with 100 injected analytics failures reached and saved the same authoritative profile/round state while recording zero events. Both the normal and failure adapters were destroyed and remained empty after cleanup.

## Revised manual acceptance

### Desktop completion and mission ordering

A fresh controlled desktop Memory-adapter session accepted two items and completed First Fit. On Ship, the client showed the approved onboarding terminal copy approximately 120 ms after the authoritative shipment. It then released that presentation and showed the separate mission banner approximately 1.15 seconds later:

```text
SAFE SHIPMENT
MISSION COMPLETE
+25 TAPE +20 PACKING XP
```

The two banners did not overlap. The mission reward was not dropped or replayed.

### Unassigned waiting state

Reducer-level deterministic acceptance proves an unassigned player never shows onboarding completion or mission presentation, and that assignment/cross-round cancellation cannot replay stale work. No live ninth-player allocation is claimed.

### Persistent two-session skip

A separate two-session Memory-adapter acceptance advanced onboarding through steps 1 and 2, accepted skip, released, and reloaded the same stored profile. The reloaded state was `Skipped`, `HighestStep=2`, Tape `0`, Packing XP `0`, and `IsGuided=false`; starter missions remained active. A duplicate skip was a no-op, and the prior session's skip analytics did not replay. This is deterministic persistence acceptance for the injected Memory adapter, not a production DataStore or published Analytics claim.

### Terminal 5/5 reward waiver

The durable established profile already has all five defined starter missions rewarded. The literal request for another new starter-mission reward after reload is explicitly waived: there is no sixth approved mission to award. Rewinding a reward flag, editing stored data, inventing content, or substituting a different identity would invalidate exact-once evidence. Same-profile reload, zero reward replay, integrated first-time rewards, and analytics no-replay are green.

## Canonical synchronization and cloud persistence

- An external recovery copy was preserved outside Git at 303,613 bytes.
- Two ordered Phase 01 then Phase 02-06 canonical synchronization passes were deterministic and clean. On both passes, Phase 01 reused all 17 operations without mutation and Phase 02-06 updated all 993 operations while preserving 79 script backups; there were zero creations, failures, warnings, wrong-class replacements, or duplicates.
- Pre-save parity matched 1,004/1,004 managed paths, with zero missing, extra, duplicate, or wrong-class paths; 89/89 UTF-8 sources; 5,192/5,192 bridge-exposed properties; and 93/93 authored-attribute targets containing 150/150 keys. The remaining 958 declared properties are not exposed by that bridge read route and are not represented as independently compared.
- All three Phase 05 acceptance-fixture attributes were absent before the normal save.
- Roblox Studio reported `Saving to Roblox...` at `15:25:20.215` and `Saved new changes in "ONE MORE ITEM!" to Roblox.` at `15:25:24.793`.
- Every Studio process closed and the observed process count reached zero.
- A signed-in direct cloud reopen reached `ONE MORE ITEM!` at `PlaceId 134193642444044` / `GameId 10493030248` without running synchronization after reopen.
- **Post-reopen exact parity:** A read-only audit at `2026-07-17T20:37:21Z`, with no synchronization after reopen, matched 1,004 expected/live/unique paths; zero missing, extra, duplicate, or wrong-class paths; 89/89 SHA-exact sources; all 117 code-map entries without truncation or read failure; 5,192/5,192 exposed properties from 6,150 declared properties, with 958 unexposed and zero mismatches; and 93 authored-attribute targets / 150 keys with zero mismatches.
- **Post-reopen fresh Studio suites and Output review:** All six suites passed in the directly reopened no-sync place, then Play stopped and Studio returned to Edit mode. Fresh actionable/game-owned warnings and errors were zero.

```text
[ONE_MORE_ITEM][FoundationTests] RESULT suites=15 tests=69 passed=69 failed=0 duration=0.440950s fuzzCases=1000 fuzzSeed=24012026
[ONE_MORE_ITEM][Phase02Tests] RESULT suites=11 tests=94 passed=94 failed=0 duration=9.867540s seed=24022026
[ONE_MORE_ITEM][Phase03Tests] RESULT suites=8 tests=65 passed=65 failed=0 duration=0.008933s seed=13072026
[ONE_MORE_ITEM][Phase04Tests] RESULT suites=13 tests=119 passed=119 failed=0 duration=1.065426s seed=14072026
[ONE_MORE_ITEM][Phase05Tests] RESULT suites=16 tests=130 passed=130 failed=0 duration=0.476493s seed=15072026 adapter=memory
[ONE_MORE_ITEM][Phase06Tests] RESULT suites=18 tests=75 passed=75 failed=0 duration=0.045601s seed=16072026 profileAdapter=memory analyticsAdapter=memory
```

## GitHub Actions

Implementation head `f877667b3ce9f032d0a0c676dafb348bb2ad6d8f` is pushed on `codex/phase-06-onboarding-starter-missions`. Draft PR #7 remains open and unmerged. The exact final-documentation-head branch `push` and PR `pull_request` run/job URLs are recorded in PR #7 and the final completion handoff after both workflows finish; this file intentionally avoids an impossible self-reference to its own commit.

## Known issues

No known Phase 06 production blocker remains. Two non-game-owned Studio/plugin icon-load warnings were observed after reopen; no fresh game-owned warning or error was present.

## Deferred pre-release QA

Issue #4 remains open and explicitly tracks these unpassed checks:

- Published Analytics dashboard event appearance.
- Onboarding funnel population under real public traffic.
- Custom-event cardinality and daily aggregation review.
- Day-1, Day-7, and Day-30 retention monitoring.
- Physical-phone onboarding and tutorial skip.
- Physical-controller onboarding and hold-to-skip.
- Eight-player simultaneous first-session onboarding.
- Expanded touch/gamepad starter-panel matrix.
- Expanded two-player mixed onboarding/mission matrix.
- Long-session mission-presentation soak.
- Low-connectivity analytics-failure observation.
- Production mission-balance review.
- Tutorial skip-rate analysis.
- First-shipment conversion analysis.

These checks are not claimed as passed. Studio uses `MemoryAnalyticsAdapter`; no published Analytics dashboard result is inferred from Studio evidence. They are not Phase 06 implementation blockers.

## Deferred by design

Daily challenges/rewards, login streaks, offline income, additional catalog objects, final models/assets, cosmetics/ownership/store, Robux products, monetization, trading, pets, rebirths, multiple worlds, co-op packing, cheer reactions, persistent/global/OrderedDataStore leaderboards, experiments, quests beyond the five starter missions, final sound/music/VFX, haptics, functional mission/rank/mastery bonuses, and every Phase 07 system remain deferred.

## Exact next phase recommendation

PR #7 is ready for final review but remains draft and unmerged. Do not begin Phase 07. Merge or advance phases only after explicit authorization.
