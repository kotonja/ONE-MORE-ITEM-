# Development status

## Current phase and Git state

- **Phase result:** **In progress and unaccepted.**
- **Current phase:** Phase 07 - Visual Readability and Arena Art-Direction Rebuild.
- **Current branch:** `codex/phase-07-visual-readability-arena-rebuild`.
- **Protected base:** `main` and `origin/main` remain the accepted Phase 06 squash merge `4c606ae4f5e7a5e3d5fa431775c94469ecea1b67`.
- **Phase 06 merge:** [PR #7](https://github.com/kotonja/ONE-MORE-ITEM-/pull/7) is merged as `4c606ae4f5e7a5e3d5fa431775c94469ecea1b67`.
- **Latest committed Phase 07 implementation head:** `a057cbb7fd23cb16f387142dec3e988efa213247`. This is the last committed implementation head observed while this documentation was prepared; later documentation commits must be recorded in PR #8 and the handoff because a commit cannot contain its own SHA.
- **Current pull request:** [PR #8](https://github.com/kotonja/ONE-MORE-ITEM-/pull/8) remains open, draft, and unmerged.
- **Pre-release QA:** [Issue #4](https://github.com/kotonja/ONE-MORE-ITEM-/issues/4) remains open. Its [Phase 06 onboarding and analytics QA additions](https://github.com/kotonja/ONE-MORE-ITEM-/issues/4#issuecomment-5007354615) keep the broad checks explicitly unpassed.
- **Scope:** Phase 07 changes visual presentation only. Automated, screenshot, cloud, complete-close, direct-reopen, and parity gates are green; Phase 07 remains unaccepted until its unedited continuous-recording gate passes. No Phase 08 system, monetization, production-store rollout, final external asset, audio, or unrelated gameplay change is permitted.
- **Evidence warning:** source, manifest, configuration, or deterministic-test success does not by itself prove that the crate, arena, UI, or motion is visibly correct.

## Phase 07 implementation and evidence ledger

The reconstruction contract is documented in `docs/PHASE07_VISUAL_READABILITY_ARENA_REBUILD.md`. The current implementation candidate has fresh automated, synchronized-Studio, double-authoring, viewport/opposite-station/four-client/Edit-mode spot-check, 15/15 accepted screenshot frames, exact-head Actions, normal cloud publish, complete-close, direct no-sync reopen, and final read-only parity evidence. It is not an accepted Phase 07 release candidate until the remaining unedited continuous-recording evidence is accepted.

| Required status field | Current truthful state |
| --- | --- |
| Phase 06 merge SHA | `4c606ae4f5e7a5e3d5fa431775c94469ecea1b67` through merged PR #7. |
| Phase 07 branch | `codex/phase-07-visual-readability-arena-rebuild`. |
| Draft PR | PR #8 is open, draft, and unmerged. |
| Latest committed implementation SHA | `a057cbb7fd23cb16f387142dec3e988efa213247` at documentation preparation time; the next containing commit cannot self-reference and must be reported externally. |
| Issue #4 | Remains open; the Phase 07 acceptance-time QA comment has not been represented as posted. |
| Current managed-path count | Final post-publish direct-reopen parity matched `1,453` expected managed paths against `1,454` unique live paths including only the allowlisted unmanaged `Workspace.Baseplate.Texture`, with zero missing/duplicate/wrong-class paths. |
| Current managed-source count | Final post-publish direct-reopen parity matched `97/97` exact canonical sources. |
| Current permanent BasePart count | `824` generated permanent BaseParts, `+346` from the accepted Phase 06 generated tree. |
| Lighting configuration | Canonical manifest intent is Future; Brightness `2`, ClockTime `14.5`, Exposure `-0.25`, Ambient `28,35,45`, OutdoorAmbient `20,25,32`, diffuse `0.35`, specular `0.55`, GlobalShadows `true`, ShadowSoftness `0.35`; Bloom `0.14 / 16 / 1.45`; ColorCorrection brightness `-0.02`, contrast `0.09`, saturation `-0.07`, tint `255,249,242`. `Lighting.Technology` is protected and bridge-unexposed, so no independent live readback is claimed; final production-device review remains deferred. |
| Camera FOV and pitch | FOV `48`; desktop pitch approximately `55.6` degrees; touch landscape/portrait approximately `50.0` degrees. Deterministic camera checks and targeted wide, narrow, touch, and opposite-station checks pass. |
| Crate screen occupancy | Deterministic projection fixtures pass across eight stations and all three anchor profiles. Exact 1920x1080, 1366x768, 1100x700, touch portrait, and touch landscape spot checks passed. |
| Line of sight | Phase 07 Studio passed `768/768` deterministic rays: 32 samples x eight stations x three anchor profiles. Targeted live views confirmed the crate remained unobstructed. |
| No-Glass result | Zero `Glass` descendants under all eight gameplay station crates. Four Glass walls remain only in the off-world development showcase template, not gameplay panes. |
| Neon-area result | 80 small managed Neon accents; maximum second-largest dimension `0.9` studs; no giant-surface allowlist. Final live exposure review pending. |
| Foundation result | Node `16` checks; Studio 15 suites / `69/69`, seed `24012026`, 1,000 fuzz cases. |
| Phase 02 result | Node `28` criteria; Studio 11 suites / `94/94`, seed `24022026`. |
| Phase 03 result | Node `31` criteria across 65 layout cases; Studio 8 suites / `65/65`, seed `13072026`. |
| Phase 04 result | Node `42` criteria; Studio 13 suites / `119/119`, seed `14072026`. |
| Phase 05 result | Node `64` criteria; Studio 16 suites / `130/130`, seed `15072026`, memory adapter. |
| Phase 06 result | Node `76` criteria; Studio 18 suites / `75/75`, seed `16072026`, profile/analytics memory adapters. |
| Phase 07 result | Node `160` criteria; final direct-reopen Studio 12 suites / `64/64`, seed `17072026`, 768 LOS rays; 15/15 external screenshot frames accepted. The unedited continuous recording remains pending. |
| All seven Node summaries | Green at implementation head `a057cbb7fd23cb16f387142dec3e988efa213247`: Phase 01 `16`; Phase 02 `28`; Phase 03 `31`; Phase 04 `42`; Phase 05 `64`; Phase 06 `76`; Phase 07 `160`. A later documentation head requires a fresh run. |
| Opening sequence | Passed first-frame curtain and controlled arrival checks; the accepted continuous recording must retain this sequence. |
| Desktop / narrow desktop | Exact 1920x1080, 1366x768, and 1100x700 visual checks passed. |
| Touch portrait / landscape | Both required Phase 07 emulator visual spot checks passed. No physical-phone result is claimed. |
| Station_05 | Passed legitimate opposite-side assignment, camera, pointer, Place, and Ship. Station_03 and Station_07 camera-clearance spot checks also passed. |
| Four-client visual flow | Exact four-client cold-start assignment and four distinct occupied station bays passed with clean station allocation. Accepted frame 12 is a genuine 2x2 tiled contact sheet of four views from that same concurrent four-client session, showing Station_01/Player1 through Station_04/Player4; SHA-256 `B5EA6DE52397200227823E8500CB59AFC2FBA55693032004EA35121376F52A7A`. |
| Shipping / failure / reset | Successful shipment, visible closure, failure burst, Pack Again, and clean reset passed in Play; one continuous accepted recording must still contain the full sequence. |
| Edit-mode arena inspection | Top-down, entrance, eye-level ring, dispatch, showcase, Station_01, Station_05, and shelf views passed; the accepted recording must retain the flyover and Station_05 views. |
| Screenshot and recording status | Required evidence remains outside Git. All 15/15 screenshot frames are accepted. Frame 12 is the genuine same-session four-client tiled contact sheet (SHA-256 `B5EA6DE52397200227823E8500CB59AFC2FBA55693032004EA35121376F52A7A`); frame 15 shows the physical authored collection shelf and its geometric development proxies (SHA-256 `09C0D21E22A28A308C5507F3D73E32A1E36F2668CBED16482EDF729AA0B993ED`). The sole remaining visual-acceptance blocker is the replacement unedited continuous recording of approximately 3-6 minutes. |
| Canonical synchronization | Two ordered Phase 01 then Phase 02-07 passes completed. Phase 01 reused 17 operations; each extended pass updated 1,443 operations and preserved 87 backups with zero creation/failure. Each extended pass emitted one known protected `Lighting.Technology` capability warning. |
| Direct no-sync read-only checkpoint | Passed against PlaceId `134193642444044` / GameId `10493030248` without synchronization: paths `1,453` expected / `1,454` unique live with one allowlisted extra and zero missing/duplicate/wrong-class; sources `97/97`; properties `7,813/7,813` bridge-exposed from 9,512 declared with 1,699 unexposed; attributes 94 targets / 152 keys with zero mismatch. |
| Cloud save | Passed normal publish to the original private cloud place with all Phase 05 fixture attributes absent. |
| Direct no-sync reopen | Passed after closing every Studio process to a verified zero count and reopening the original private place directly from Roblox without synchronization. |
| Final post-reopen parity | Passed: paths `1,453` expected / `1,454` unique live with only the allowlisted extra; zero missing/duplicate/wrong-class; sources `97/97`; exposed properties `7,813/7,813`; attributes 94 targets / 152 keys with zero mismatch. |
| GitHub Actions | Implementation head passed push run `29662807404` / job `88128209680` and draft-PR run `29662808244` / job `88128211869`. The next documentation head requires its own exact-head run. |
| Known limitations | Final object models, external assets, images, audio/music, final particles/VFX, haptics, production-device review, and broad pre-release QA remain deferred. |
| Exact Phase 08 recommendation | Do not begin Phase 08. Complete Phase 07 evidence and keep PR #8 draft/unmerged first. |

## Current Phase 07 automated and final persistence evidence

Fresh Node 24 output at implementation head `a057cbb7fd23cb16f387142dec3e988efa213247` passed:

```text
[StudioSyncSmoke] PASS checks=16 folders=7 scripts=10 deterministic=true
[Phase02StudioSyncSmoke] PASS criteria=28 instances=1355 scripts=87 remotes=6 deterministic=true phase01=true
[Phase03CrossPlatformSmoke] PASS criteria=31 viewports=13 insetProfiles=5 layoutCases=65 remotes=6 deterministic=true phase01=true phase02=true
[Phase04MultiplayerArena] PASS criteria=42 instances=1355 scripts=87 stations=8 pathNodes=16 remotes=6 deterministic=true prior=true
[Phase05PersistentProgression] PASS criteria=64 instances=1355 scripts=87 gameplayRemotes=6 profileRemotes=1 shelves=8 collectionSlots=8 deterministic=true prior=true
[Phase06OnboardingMissionsAnalytics] PASS criteria=76 instances=1355 scripts=87 gameplayRemotes=6 profileRemotes=1 onboardingRemotes=1 onboardingSteps=5 starterMissions=5 missionTape=295 missionXP=210 deterministic=true prior=true
[Phase07VisualReadability] PASS criteria=160 instances=1355 scripts=87 stations=8 losRays=768 pointLights=20 deterministic=true prior=true
```

Fresh direct-reopen Studio Output passed without any post-reopen synchronization:

```text
[ONE_MORE_ITEM][FoundationTests] RESULT suites=15 tests=69 passed=69 failed=0 duration=0.333691s fuzzCases=1000 fuzzSeed=24012026
[ONE_MORE_ITEM][Phase02Tests] RESULT suites=11 tests=94 passed=94 failed=0 duration=6.775828s seed=24022026
[ONE_MORE_ITEM][Phase03Tests] RESULT suites=8 tests=65 passed=65 failed=0 duration=0.007074s seed=13072026
[ONE_MORE_ITEM][Phase04Tests] RESULT suites=13 tests=119 passed=119 failed=0 duration=3.483551s seed=14072026
[ONE_MORE_ITEM][Phase05Tests] RESULT suites=16 tests=130 passed=130 failed=0 duration=0.553133s seed=15072026 adapter=memory
[ONE_MORE_ITEM][Phase06Tests] RESULT suites=18 tests=75 passed=75 failed=0 duration=0.036370s seed=16072026 profileAdapter=memory analyticsAdapter=memory
[ONE_MORE_ITEM][Phase07Tests] RESULT suites=12 tests=64 passed=64 failed=0 duration=1.654351s seed=17072026 losRays=768
```

No fresh game-owned warning or error was present in the direct-reopen run. Exact wide/narrow/touch, Station_05, Station_03/07, four-client, top-down Edit-mode, successful shipment, and failure/reset checks passed, and all 15/15 screenshot frames are accepted. Visual acceptance remains blocked only by the complete unedited continuous recording; the issue #4 acceptance-time comment has not been posted, and final documentation plus exact-head CI follow only after that recording passes.

## Accepted Phase 06 implementation

- Profile Schema Version 2 migrates Version 1 inside the existing `ONE_MORE_ITEM_PlayerProfiles_v1` and `ONE_MORE_ITEM_PlayerProfiles_StudioTest_v1` stores.
- Five server-authoritative onboarding steps persist `NotStarted`, `InProgress`, `Completed`, or `Skipped`; guided placement remains 45 seconds and guided decision remains 12 seconds.
- Five exact-once starter missions (`first_fit`, `first_shipment`, `one_more`, `collector_three`, and `five_item_box`) remain worth 295 Tape and 210 Packing XP in total.
- Permanent onboarding and mission UI, five mission rows, the one narrow `OnboardingActionRequest` remote, remotes, templates, and scripts remain manifest-authored. No permanent UI, networking object, or map artifact is created at runtime.
- Studio uses `MemoryAnalyticsAdapter`; published non-Studio servers select the Roblox adapter. Analytics remains server-only, best-effort, and unable to alter gameplay, assignment, progression, snapshots, or saving.

## Accepted Phase 06 source-quality corrections

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

## Accepted Phase 06 automated validation

The results in this section are the accepted Phase 06 baseline. They are not the fresh Phase 07 integrated evidence recorded above and must not be substituted for it.

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

## Accepted Phase 06 integrated analytics trace

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

## Accepted Phase 06 revised manual acceptance

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

## Accepted Phase 06 canonical synchronization and cloud persistence

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

Phase 06 implementation head `f877667b3ce9f032d0a0c676dafb348bb2ad6d8f` was reviewed and [PR #7](https://github.com/kotonja/ONE-MORE-ITEM-/pull/7) was squash-merged as `4c606ae4f5e7a5e3d5fa431775c94469ecea1b67`. Phase 07 implementation head `a057cbb7fd23cb16f387142dec3e988efa213247` passed push run `29662807404` / job `88128209680` and draft-PR run `29662808244` / job `88128211869`; all seven Node steps completed successfully. The later documentation commit cannot be self-recorded here and must receive fresh exact-head Actions evidence before handoff.

## Known issues

No known Phase 06 production blocker remains.

Phase 07 is active and unaccepted. Automated Node/Studio gates, double synchronization, targeted viewport/opposite-station/four-client/Edit-mode checks, all 15/15 screenshot frames, normal cloud publish, complete close, fresh direct no-sync reopen, post-reopen parity/suites/success/failure, and clean Output are green. The complete unedited 3-6 minute replacement recording remains the sole visual-acceptance blocker; the issue #4 Phase 07 acceptance-time comment remains intentionally unposted until that recording passes.

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

After Phase 07 acceptance, issue #4 must also retain these explicitly unpassed visual checks under the required `Phase 07 visual and arena QA additions` comment:

- Physical-phone crate readability.
- Physical-controller visual flow.
- Low-end-device lighting and transparency performance.
- Color-vision-deficiency review.
- Eight-player long-session world-label clutter.
- Eight-player simultaneous showcase visibility.
- Long-session camera and label cleanup.
- Production screenshot and thumbnail review.
- Final object-model replacement.
- Final sound/music/VFX integration.
- Final art consistency review.
- Public-beta visual feedback.
- Production-device bloom/exposure review.

That comment has not yet been posted because Phase 07 acceptance is incomplete. None of these checks is claimed passed, they are not Phase 07 implementation blockers, and issue #4 must remain open.

## Deferred by design

Daily challenges/rewards, login streaks, offline income, additional catalog objects, final models/assets, cosmetics/ownership/store, Robux products, monetization, trading, pets, rebirths, multiple worlds, co-op packing, cheer reactions, persistent/global/OrderedDataStore leaderboards, experiments, quests beyond the five starter missions, final sound/music/VFX, haptics, functional mission/rank/mastery bonuses, and every Phase 08 system remain deferred.

## Exact next phase recommendation

Complete Phase 07 only on `codex/phase-07-visual-readability-arena-rebuild`, keep its pull request draft and unmerged, and preserve issue #4. Do not begin Phase 08.
