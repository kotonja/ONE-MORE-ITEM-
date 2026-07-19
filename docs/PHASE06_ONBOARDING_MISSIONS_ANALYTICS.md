# Phase 06 - First-Time Player Experience, Starter Missions, and Retention Analytics

## Status

Phase 06 is implementation-complete and accepted on `codex/phase-06-onboarding-starter-missions` at implementation head `f877667b3ce9f032d0a0c676dafb348bb2ad6d8f`. [PR #7](https://github.com/kotonja/ONE-MORE-ITEM-/pull/7) was subsequently squash-merged into `main` as `4c606ae4f5e7a5e3d5fa431775c94469ecea1b67`. Phase 07 is now active and unaccepted on `codex/phase-07-visual-readability-arena-rebuild`; [PR #8](https://github.com/kotonja/ONE-MORE-ITEM-/pull/8) remains open, draft, and unmerged.

This document defines the Phase 06 implementation and accepted evidence boundary. `docs/DEVELOPMENT_STATUS.md` records the current fresh Studio, persistence, cloud-reopen, analytics, and CI evidence. Broad pre-release QA remains explicitly unpassed as listed below.

## Canonical ownership and permanent authoring

Canonical Luau remains under `src/`. The historically named `studio/phase02.manifest.json` remains the sole permanent-instance owner for Phase 02 through Phase 06 gameplay UI, profile UI, onboarding UI, starter-mission UI, arena content, remotes, templates, and scripts.

Permanent Phase 06 UI must exist beneath `StarterGui.ONE_MORE_ITEM_Gameplay.Root` before Play. The one onboarding request remote must exist beneath `ReplicatedStorage.ONE_MORE_ITEM.OnboardingNet` before Play. Runtime code may update and animate authored instances, reposition the authored tutorial pointer, and create temporary reward effects, but it may not construct permanent onboarding panels, mission rows, remotes, profile fields, or world content.

The authoring path remains parent-first, deterministic, idempotent, conflict-safe, and non-destructive. A wrong-class managed path fails visibly. Reapplying the complete Phase 01 plus Phase 02-06 operation sets must create no duplicate managed paths.

## Profile Schema Version 2

Schema Version 2 keeps the existing store namespaces:

| Environment | Store |
| --- | --- |
| Published non-Studio server | `ONE_MORE_ITEM_PlayerProfiles_v1` |
| Normal Roblox Studio persistence | `ONE_MORE_ITEM_PlayerProfiles_StudioTest_v1` |
| Deterministic tests and controlled fixtures | injected `MemoryProfileAdapter` |

The store-name suffix and profile schema version are independent. Studio never opens the production store.

Version 2 preserves every Version 1 field and adds:

```text
Onboarding = {
    Version = 1,
    Status = NotStarted | InProgress | Completed | Skipped,
    HighestStep = integer 0..5,
    CompletedAt = non-negative Unix timestamp
}

StarterMissions = {
    Version = 1,
    Progress = { [MissionId] = non-negative integer },
    Completed = { [MissionId] = true },
    Rewarded = { [MissionId] = true },
    PathCompleted = boolean,
    CompletedAt = non-negative Unix timestamp
}

Stats.TotalMissionTapeEarned = non-negative integer
Stats.TotalStarterMissionsCompleted = non-negative integer
```

Current input mode, highlighted tutorial target, mission-panel visibility, pointer position, UI animation state, analytics records/retry state, round state, and any client-selected mission remain transient.

## Version 1 migration

The migration boundary is deterministic, non-yielding, and input-immutable:

- `nil` creates a Version 2 default.
- Version 0 migrates through the documented Version 1 shape and then into Version 2.
- Version 1 preserves Tape, Packing XP, all existing statistics, collection discovery/mastery/recent order, bounded receipts, timestamps, and session ownership while adding default onboarding, starter missions, and zeroed mission statistics.
- Version 2 is copied and normalized.
- Future unsupported versions reject rather than downgrade.
- Unknown onboarding status normalizes safely; `HighestStep` is clamped to `0..5`; Completed implies step 5; Skipped remains distinct.
- Unknown mission IDs are removed; progress is capped at the canonical goal; Rewarded implies Completed; `PathCompleted` is derived from all five reward states.
- Completion timestamps are normalized without exposing or altering lock data.

Receipt bounds, session-lock ownership, stale-lock takeover, guarded `UpdateAsync`, save scheduling, and release/shutdown behavior remain Phase 05 contracts.

## Onboarding states and durable steps

`OnboardingDefinitions` owns exactly five stable funnel steps:

| Step | Stable name | Authoritative trigger |
| ---: | --- | --- |
| 1 | `PROFILE READY` | ProfileService reaches Ready |
| 2 | `STATION ASSIGNED` | StationService successfully assigns the profile-ready player |
| 3 | `FIRST ITEM PLACED` | Server accepts and applies a legal placement |
| 4 | `FIRST DECISION SHOWN` | Server enters Decision with at least one placed item |
| 5 | `FIRST SHIPMENT COMPLETED` | Persistent successful-shipment progression succeeds |

Steps advance monotonically. The first durable advance changes NotStarted to InProgress. Step 5 changes the status to Completed. Completed and Skipped are terminal. Failure does not reset progress, and neither completion nor skipping grants Tape or XP.

`OnboardingService` mutates only through `ProfileService`. It returns a copied immutable result with previous/new state and step, completion/skip flags, and whether anything changed. Duplicate or lower steps are no-ops. Conflict blocks mutation. Analytics runs only after the mutation and snapshot succeed; analytics failure cannot undo onboarding.

## Guided timing

An incomplete, non-skipped onboarding profile receives:

- guided placement duration: `45` seconds;
- guided decision duration: `12` seconds.

Normal `30`-second placement and `8`-second decision durations remain unchanged after completion or skip. Guided state is captured once when a round starts and copied to the round snapshot as `GuidedOnboarding`; completing or skipping during that round does not retime its existing deadlines. Subsequent rounds use the new terminal state.

Guidance does not change the `5 x 5 x 4` grid, first Parcel, legal-placement validation, candidate fairness, item sequence, reward formula, One More risk, or safe Ship timeout default.

## Skip request contract

The only new client-to-server Phase 06 remote is:

```text
ReplicatedStorage.ONE_MORE_ITEM.OnboardingNet.OnboardingActionRequest
```

The only accepted payload shape is:

```text
{
    Action = "SKIP",
    ClientSequence = finite positive integer
}
```

The server requires a loaded mutable profile, incomplete onboarding, exact `SKIP`, a newer sequence, and the `2 requests/second` limit. It tracks at most ten accepted/rejected onboarding requests per player session before one concise warning. Client-supplied Tape, XP, rank, mission, reward, profile, or arbitrary value fields are never trusted.

An accepted skip persists `Skipped`, publishes the next profile snapshot, hides the overlay, leaves starter missions active, records the fixed skip analytics event, grants nothing, and does not alter the current round.

Desktop and touch use the authored `SkipButton`. Gamepad requires an approximately one-second ButtonB hold, with authored progress and early-release cancellation. Escape never skips and no generated touch button exists.

## Starter mission definitions

`StarterMissionDefinitions` owns exactly five immutable missions in this order:

| # | ID | Name | Authoritative goal | Goal | Tape | XP |
| ---: | --- | --- | --- | ---: | ---: | ---: |
| 1 | `first_fit` | FIRST FIT | AcceptedPlacement | 1 | 10 | 10 |
| 2 | `first_shipment` | SAFE SHIPMENT | SuccessfulShipment | 1 | 25 | 20 |
| 3 | `one_more` | ONE MORE! | OneMoreAccepted | 1 | 35 | 30 |
| 4 | `collector_three` | START A COLLECTION | DiscoveredCount | 3 | 75 | 50 |
| 5 | `five_item_box` | PACK IT TIGHT | ShipmentItemCount | 5 | 150 | 100 |

The starter path totals exactly `295 Tape` and `210 Packing XP`. There is no claim button, random mission, daily reset, streak, premium mission, hidden mission, functional bonus, or extra path-completion reward.

## Mission progression, rewards, and reconciliation

All five missions may accumulate progress concurrently, while the UI spotlights the first incomplete mission. Server-created events are limited to AcceptedPlacement, SuccessfulShipment, OneMoreAccepted, and ProfileReconcile.

`StarterMissionService` applies one atomic draft through `ProfileService`:

- progress caps at the canonical goal;
- Completed becomes true at the goal;
- Rewarded becomes true only when Tape and XP are applied atomically;
- Rewarded is the exact-once source of truth;
- multiple completions return in definition order;
- deterministic reward ID is `starter:v1:{MissionId}`;
- `TotalTapeEarned` and `TotalMissionTapeEarned` increase by mission Tape;
- `TotalStarterMissionsCompleted` increments once per rewarded mission;
- Packing rank is derived from authoritative XP;
- mission rewards never alter shipment statistics;
- PathCompleted becomes true only after all five rewards and grants nothing extra.

Profile reconciliation uses `TotalSuccessfulShipments`, discovered count, and `HighestItemsInShipment` for `first_shipment`, `collector_three`, and `five_item_box`. `one_more` uses its own persisted progress. `first_fit` records only after the first accepted placement. Reconciliation never replays an already rewarded mission.

Shipment progression succeeds first. Mission reconciliation/rewards follow in a separate authoritative mutation. A mission mutation failure cannot undo the shipment and can be recovered by later profile reconciliation.

## ProfileSnapshot extensions

The existing single server-to-client `ProfileNet.ProfileSnapshot` is extended; no second profile snapshot remote is added. Version 2 presentation adds copied/frozen:

- `SchemaVersion`;
- onboarding status, highest step, and completion state;
- mission progress;
- ordered completed and rewarded mission IDs;
- current mission, completed count, total count, and path completion;
- a bounded ephemeral `LastMissionRewards` batch.

The snapshot still excludes lock tokens, heartbeats, receipt history, DataStore keys, internal services, analytics memory records, and mutable profile references. Save-state-only snapshots may repeat a mission batch, so clients deduplicate by RewardId. A new profile presentation session begins with no stale batch.

## Analytics adapters

Analytics remain a server-only best-effort boundary:

```text
Services.Analytics
  AnalyticsAdapter
  MemoryAnalyticsAdapter
  RobloxAnalyticsAdapter
  AnalyticsEventDefinitions
  GameAnalyticsService
```

Studio and deterministic tests select MemoryAnalyticsAdapter, which makes no AnalyticsService call and stores deep-copied records for ordering, filtering, payload, and injected-failure assertions. Published non-Studio servers select RobloxAnalyticsAdapter.

The Roblox adapter uses current `LogOnboardingFunnelStepEvent`, `LogCustomEvent`, `LogEconomyEvent`, `LogProgressionStartEvent`, `LogProgressionCompleteEvent`, and `LogProgressionFailEvent` calls inside `pcall`. Deprecated `FireCustomEvent`, `FireEvent`, `FireInGameEconomyEvent`, and `FirePlayerProgressionEvent` are prohibited.

Analytics failure never rolls back Tape, XP, onboarding, mission state, snapshots, station assignment, round results, saving, showcase, or Results. Non-Studio warnings are concise and rate-limited; Studio injected failures remain deterministic test evidence.

## Fixed analytics catalog

Durable onboarding Steps 1-5 use the names from `OnboardingDefinitions` and log only after a successful durable step mutation.

Fixed custom events are:

- `CoreLoopRound` with phase `start`, `ship`, or `fail`, bounded item-count bucket, and allowlisted reason;
- `OneMoreAccepted` with bounded item-count bucket and difficulty;
- `StarterMission` with bounded mission ID and status `started`, `completed`, or `path_completed`;
- `OnboardingSkipped` with bounded highest step;
- `SessionDuration` with clamped whole seconds and booleans for profile-ready/station-assigned state.

Tape economy events use flow Source, currency `Tape`, source `Shipment` or `StarterMission`, authoritative amount, authoritative ending balance, and bounded item SKU (`shipment` or `starter:{MissionId}`).

Starter-path progression events use path `StarterPath`, mission index as level, and canonical mission name as level name. Start logs once when a mission first becomes the spotlight; complete logs once when the reward applies. Ordinary incomplete progress does not log failure.

## Analytics event ordering

Required ordering is:

```text
Onboarding mutation -> ProfileSnapshot -> onboarding analytics

Shipment progression -> starter mission reconciliation/reward
                     -> profile snapshots
                     -> economy/custom analytics
                     -> cosmetic showcase

Mission mutation -> ProfileSnapshot
                 -> mission Tape economy event
                 -> progression complete
                 -> mission custom complete
```

Fixed custom fields never contain UserId, DisplayName, profile-session ID, lock data, DataStore keys, OutcomeId, raw RoundId, arbitrary client text, device identifiers, IP information, or chat. Event names are not dynamically constructed from player or gameplay identifiers. Custom events use no more than three bounded fields.

## Permanent UI hierarchy

The authored Root adds:

```text
OnboardingOverlay
  Prompt
  Instruction
  InputHint
  StepProgress
  TutorialPointer
  SkipButton
  SkipHoldProgress
StarterMissionCard
  Header
  MissionName
  Description
  ProgressText
  ProgressBar
    Background
    Fill
  RewardText
  OpenPathButton
StarterPathPanel
  Header
  Summary
  CloseButton
  Missions
    Mission_01 ... Mission_05
MissionCompleteBanner
  Header
  MissionName
  RewardText
  PathProgress
```

Every mission row permanently authors Status, MissionName, Description, ProgressText, RewardText, ProgressBar/Fill, Corner, and Stroke. Rows are presentation/focus surfaces only and perform no server mutation.

The visual direction uses compact dark toy-industrial panels, cyan guidance, green confirmation, amber Ship emphasis, risk red only for One More explanation, Gotham typography, and existing cancellable motion tokens. The crate remains the focus; there is no full-screen lesson, NPC dialogue, forced camera tour, repeated flash, or permanent center-screen obstruction.

## Responsive and cross-platform controls

The existing responsive classifier remains authoritative:

- Wide;
- CompactLandscape;
- Portrait.

All target positions and sizes use scale-only UDim2 values within Roblox-reported safe areas. The required desktop, phone, landscape-phone, and tablet matrix covers the overlay, compact mission card, full mission panel, mission banner, and existing Collection/Results/MetaBar surfaces. Layout changes retarget existing tweens without stacking and send no server event.

Desktop uses authored buttons, `M` to open the starter path when allowed, and Escape to close. Touch uses authored open/close buttons and suppresses underlying drag while the full panel is open. Gamepad uses ButtonL1 to open when allowed, ButtonB to close, and safe selection among visible rows/Close only. Gameplay input is suppressed beneath a modal panel, the panel closes on active-round entry, and neither mission rows nor panel navigation mutates the server.

The compact card appears after the first accepted placement or terminal onboarding state and remains until PathCompleted, then collapses. Mission banners deduplicate by RewardId, queue in definition order, shorten safely when a new round begins, and never block Pack Again.

## Automated test contract

Phase 06 retains Foundation `69`, Phase 02 `94`, Phase 03 `65`, Phase 04 `119`, and Phase 05 `130` tests. `Phase06TestSuite` contains 18 suites / 75 tests for deterministic schema/migration, onboarding, guided timing, completion arrival ordering, missions, snapshots, client presentation, analytics ordering, request security, multiplayer isolation, persistence, replay prevention, and failure isolation using fixed clocks, server-session IDs, adapters, and sinks. No deterministic test makes a live DataStore or AnalyticsService request.

The dependency-free `tools/test_phase06_onboarding_missions_analytics.mjs` validates 76 Phase 06 criteria and requires every inherited Node gate before validating the Phase 06 source, authoring, security, analytics, UI, workflow, determinism, and tracked-file contracts. CI uses Node 24 and runs all six Node commands on pull requests to main and pushes to main or `codex/**`.

## Studio-test migration Sessions E/F - accepted revised policy

Only `ONE_MORE_ITEM_PlayerProfiles_StudioTest_v1` may be used.

Session E loaded the accepted Version 1 Studio-test profile, migrated it to Version 2 while preserving Tape, XP, rank, collection, mastery, receipts, and all prior statistics, exercised onboarding and exact-once starter rewards, reached Ready/Saved, and closed every Studio process. The durable profile ended at the terminal `5/5` starter path with all five defined rewards already applied.

The literal Session F request for one additional starter-mission reward is explicitly waived: no sixth mission or path-completion bonus exists, and resetting or extending the durable profile merely to manufacture a reward would invalidate the proof and exceed scope. Accepted Session F evidence is the direct no-sync Version 2 reload with prior progression preserved, all five rewards still exact-once, `LastMissionRewards` empty, no reward-presentation replay, no completion-analytics replay, and a clean stop. Evidence is sanitized; no complete profile payload, player identifier, store key, lock token, or OutcomeId is printed or committed.

## Cloud save and direct reopen contract

After implementation and all six local gates pass, create an external recovery copy, use one Studio process, confirm all Phase 05 acceptance attributes are absent, build canonical artifacts, and apply Phase 01 then Phase 02-06 synchronization twice. Verify exact managed paths/classes/properties/sources, permanent UI, eight stations/shelves, six gameplay remotes, one profile remote, one onboarding request remote, and no generic profile-mutation remote.

Run all six Studio suites, save normally to the original private place, fully close Studio, and reopen directly without synchronization. Reverify authored UI/remotes, source parity, zero duplicate/wrong-class paths, absent fixtures, all six suites, durable onboarding/mission persistence without reward or analytics replay, and zero fresh actionable game-owned warnings/errors.

No cloud-persistence claim is valid without the complete close and direct reopen.

## Known limitations and deferred pre-release QA

Issue #4 remains the single open pre-release QA tracker. Published Analytics dashboard appearance, real-traffic funnel population, cardinality/daily aggregation review, D1/D7/D30 retention, physical phone/controller onboarding, eight-player simultaneous first sessions, long mission-presentation soak, low-connectivity analytics failure, mission balance, skip rate, and first-shipment conversion remain unpassed until explicitly verified.

Studio uses only the memory analytics adapter. Published analytics verification is pre-release QA rather than a Phase 06 implementation blocker.

## Deferred by design

Phase 06 excludes daily challenges/rewards, login streaks, offline income, additional catalog objects, final models/assets, cosmetics/ownership/store, Robux products, monetization, trading, pets, rebirths, multiple worlds, co-op packing, cheer reactions, persistent/global/OrderedDataStore leaderboards, experiments, quests beyond the five starter missions, final sound/music/VFX, haptics, functional mission/rank/mastery bonuses, and every Phase 07 system.

## Current acceptance evidence - accepted (2026-07-17)

**Implementation complete and accepted.** The accepted implementation head is `f877667b3ce9f032d0a0c676dafb348bb2ad6d8f`. PR #7 subsequently squash-merged as `4c606ae4f5e7a5e3d5fa431775c94469ecea1b67`; current Phase 07 status is recorded in `docs/PHASE07_VISUAL_READABILITY_ARENA_REBUILD.md` and `docs/DEVELOPMENT_STATUS.md`.

### Automated evidence

All six local Node gates passed at the implemented 914-manifest-instance / 79-manifest-script target; the synchronized place separately matched all 89 managed source hashes:

```text
[StudioSyncSmoke] PASS checks=16 folders=7 scripts=10 deterministic=true
[Phase02StudioSyncSmoke] PASS criteria=28 instances=914 scripts=79 remotes=6 deterministic=true phase01=true
[Phase03CrossPlatformSmoke] PASS criteria=31 viewports=13 insetProfiles=5 layoutCases=65 remotes=6 deterministic=true phase01=true phase02=true
[Phase04MultiplayerArena] PASS criteria=42 instances=914 scripts=79 stations=8 pathNodes=16 remotes=6 deterministic=true prior=true
[Phase05PersistentProgression] PASS criteria=64 instances=914 scripts=79 gameplayRemotes=6 profileRemotes=1 shelves=8 collectionSlots=8 deterministic=true prior=true
[Phase06OnboardingMissionsAnalytics] PASS criteria=76 instances=914 scripts=79 gameplayRemotes=6 profileRemotes=1 onboardingRemotes=1 onboardingSteps=5 starterMissions=5 missionTape=295 missionXP=210 deterministic=true prior=true
```

Fresh pre-save Studio Output passed Foundation `69/69`, Phase 02 `94/94`, Phase 03 `65/65`, Phase 04 `119/119`, Phase 05 `130/130`, and Phase 06 at 18 suites / `75/75`. The source-quality run covers deterministic completion presentation, both arrival orders, no replay, assignment gating, lossless mission-banner deferral, transactional analytics ordering, the integrated 20-event trace, duplicate/save/reload no-replay, 100 injected failures, adapter cleanup, and two-session Memory skip persistence.

Exact-head branch-push and pull-request CI URLs for the final documentation commit are recorded in draft PR #7 and the final completion handoff after both workflows finish; this committed document intentionally does not attempt to self-reference its own commit.

### Manual and persistence evidence

| Gate | Result | Evidence and limitation |
| --- | --- | --- |
| Completion presentation | Pass | Both profile-first and round-first arrival produce the same approved three-line copy for `0.95` seconds exactly once. Terminal/reload baselines, cross-round cancellation, unassigned hiding, and lossless mission-banner deferral are covered. |
| Desktop ordering | Pass | A fresh Memory session showed the terminal onboarding copy about 120 ms after Ship, then the separate `SAFE SHIPMENT` mission banner about 1.15 seconds later. The banners did not overlap and neither replayed. |
| Starter path | Pass | Exact-once mission rewards, path progression, save/reload no-replay, and authoritative economy ending balances are green. The literal extra reward on the already-terminal 5/5 profile is explicitly waived because no sixth approved mission exists. |
| Persistent skip | Pass within deterministic Memory-adapter scope | Session 1 advanced steps 1-2 and skipped; Session 2 reloaded `Skipped` / `HighestStep=2`, Tape/XP `0`, guided mode off, missions active, duplicate skip a no-op, and no old analytics replay. No production DataStore or published Analytics claim is made. |
| Waiting/unassigned | Pass at reducer level | The completion presentation remains hidden and stale work is consumed when no station is assigned. No live ninth-player allocation is claimed. |
| Integrated analytics trace | Pass | The exact 20-event fresh-player trace, balances `10` / `25` / `50`, duplicate/save/reload no-replay, 100 injected failures, unchanged authoritative state, and adapter cleanup all pass. |
| Canonical synchronization | Pass | Two ordered synchronization passes were clean. Pre-save parity passed 1,004/1,004 paths, 89/89 sources, 5,192/5,192 exposed properties, and 93 authored-attribute targets / 150 keys. Fixtures were absent. |
| Cloud save and full close | Pass | The place saved normally to Roblox, a 303,613-byte external recovery copy exists outside Git, and every Studio process closed to a verified count of zero. |
| Direct cloud reopen and parity | Pass | The correct `PlaceId 134193642444044` / `GameId 10493030248` reopened without synchronization. A read-only audit at `2026-07-17T20:37:21Z` matched 1,004 expected/live/unique paths, 89/89 SHA-exact sources, all 117 code-map entries without truncation, 5,192/5,192 exposed properties, and 93 targets / 150 authored keys, with zero missing, extra, duplicate, wrong-class, source, property, or attribute mismatches. |
| Post-reopen Studio suites | Pass | Fresh direct-reopen Output passed Foundation 15 suites / `69/69`, Phase 02 11 suites / `94/94`, Phase 03 8 suites / `65/65`, Phase 04 13 suites / `119/119`, Phase 05 16 suites / `130/130`, and Phase 06 18 suites / `75/75`, with the fixed seeds and memory adapters. The fresh actionable/game-owned warning/error count was zero; Play stopped and Studio returned to Edit mode. |
| Broad device, multiplayer, and production analytics QA | Explicitly unpassed, deferred | These checks remain open in issue #4 and are not Phase 06 implementation blockers. |

### Integrated trace and replay proof

The deterministic fresh-player integration recorded this exact order:

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

The final state was Tape `50`, Packing XP `44`, onboarding `Completed`, and the round in `Shipping`. Duplicate delivery, save, release, and reload produced no reward or analytics replay. A separate 100-failure injection reached and saved the same authoritative state with zero recorded analytics events. Adapter destruction left no residual records.

### Revised Session F acceptance

Session E ended with the durable Studio-test profile at all five defined missions rewarded. The literal request for another new starter-mission reward in Session F is explicitly waived: there is no approved sixth mission. Rewinding a reward flag, adding content, editing the store, or substituting an identity would invalidate the exact-once contract. The accepted replacement evidence combines same-profile reload with zero reward replay, the integrated exact-once First Fit and First Shipment awards, the exact analytics trace, and save/reload no-replay.

### Acceptance boundary

No known Phase 06 production blocker remains. Two non-game-owned Studio/plugin icon-load warnings were observed after reopen; no fresh game-owned warning or error was present.

Issue #4 remains open for the explicitly unpassed physical-device, expanded emulator, multiplayer, production Analytics, public-traffic retention, soak, low-connectivity, and mission-balance checks. Studio uses the memory adapter; no published Analytics or production DataStore result is inferred. These are pre-release QA, not Phase 06 implementation blockers.

PR #7 subsequently squash-merged as `4c606ae4f5e7a5e3d5fa431775c94469ecea1b67`. Phase 07 is active but unaccepted in draft PR #8. Its current candidate has green automated, synchronized-Studio, canonical double-synchronization, manual spot-check, normal cloud publish, complete-close, direct no-sync reopen, and final parity evidence, but its accepted recording and final screenshot set remain pending. Those Phase 07 results do not alter this Phase 06 acceptance record. Do not begin Phase 08.
