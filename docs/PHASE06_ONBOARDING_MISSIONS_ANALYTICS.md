# Phase 06 - First-Time Player Experience, Starter Missions, and Retention Analytics

## Status

Phase 06 is active on `codex/phase-06-onboarding-starter-missions` in draft PR #7. Phase 05 is the protected baseline, squash-merged through PR #6 at `d644411b48e20cd9bb256d3d2c55a647efc2adfd`.

This document defines the Phase 06 implementation and acceptance contract. It does not claim that Studio, persistence, cloud-reopen, cross-platform, analytics, or CI gates have passed until `docs/DEVELOPMENT_STATUS.md` records fresh evidence.

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

Phase 06 retains Foundation `69`, Phase 02 `94`, Phase 03 `65`, Phase 04 `119`, and Phase 05 `130` tests. `Phase06TestSuite` adds deterministic schema/migration, onboarding, guided timing, missions, snapshots, client presentation, analytics, request security, multiplayer isolation, and persistence coverage using fixed clocks, server-session IDs, adapters, and sinks. No deterministic test makes a live DataStore or AnalyticsService request.

The dependency-free `tools/test_phase06_onboarding_missions_analytics.mjs` requires every inherited Node gate before validating the Phase 06 source, authoring, security, analytics, UI, workflow, determinism, and tracked-file contracts. CI uses Node 24 and runs all six Node commands on pull requests to main and pushes to main or `codex/**`.

## Studio-test migration Sessions E/F

Only `ONE_MORE_ITEM_PlayerProfiles_StudioTest_v1` may be used.

Session E must load the accepted Version 1 Studio-test profile, migrate it to Version 2 while preserving Tape, XP, rank, collection, mastery, receipts, and all prior statistics, apply at least one onboarding step and the exact-once `first_fit` reward, reach Ready/Saved, and then close every Studio process.

Session F must reopen directly without synchronization, load the same Version 2 profile, preserve all prior progression and onboarding/mission state without reward or analytics-memory replay, apply one new starter mission event exactly once, reach Saved, and stop cleanly. Evidence is sanitized; no complete profile payload, player identifier, store key, lock token, or OutcomeId is printed or committed.

## Cloud save and direct reopen contract

After implementation and all six local gates pass, create an external recovery copy, use one Studio process, confirm all Phase 05 acceptance attributes are absent, build canonical artifacts, and apply Phase 01 then Phase 02-06 synchronization twice. Verify exact managed paths/classes/properties/sources, permanent UI, eight stations/shelves, six gameplay remotes, one profile remote, one onboarding request remote, and no generic profile-mutation remote.

Run all six Studio suites, save normally to the original private place, fully close Studio, and reopen directly without synchronization. Reverify authored UI/remotes, source parity, zero duplicate/wrong-class paths, absent fixtures, all six suites, one onboarding flow, one mission reward, save/reload persistence, and zero fresh actionable game-owned warnings/errors.

No cloud-persistence claim is valid without the complete close and direct reopen.

## Known limitations and deferred pre-release QA

Issue #4 remains the single open pre-release QA tracker. Published Analytics dashboard appearance, real-traffic funnel population, cardinality/daily aggregation review, D1/D7/D30 retention, physical phone/controller onboarding, eight-player simultaneous first sessions, long mission-presentation soak, low-connectivity analytics failure, mission balance, skip rate, and first-shipment conversion remain unpassed until explicitly verified.

Studio uses only the memory analytics adapter. Published analytics verification is pre-release QA rather than a Phase 06 implementation blocker.

## Deferred by design

Phase 06 excludes daily challenges/rewards, login streaks, offline income, additional catalog objects, final models/assets, cosmetics/ownership/store, Robux products, monetization, trading, pets, rebirths, multiple worlds, co-op packing, cheer reactions, persistent/global/OrderedDataStore leaderboards, experiments, quests beyond the five starter missions, final sound/music/VFX, haptics, functional mission/rank/mastery bonuses, and every Phase 07 system.

## Current acceptance evidence - partial (2026-07-16)

Phase 06 production implementation is complete, but the attachment's complete acceptance contract is not. The pull request remains draft and unmerged and Phase 07 has not begun.

### Automated evidence

All six local Node gates passed at the implemented 914-instance, 79-source target:

```text
[StudioSyncSmoke] PASS checks=16 folders=7 scripts=10 deterministic=true
[Phase02StudioSyncSmoke] PASS criteria=28 instances=914 scripts=79 remotes=6 deterministic=true phase01=true
[Phase03LayoutMatrix] PASS viewports=13 insetProfiles=5 cases=65 desktopCompatible=true safeContainment=true
[Phase03CrossPlatformSmoke] PASS criteria=31 viewports=13 insetProfiles=5 layoutCases=65 remotes=6 deterministic=true phase01=true phase02=true
[Phase04MultiplayerArena] PASS criteria=42 instances=914 scripts=79 stations=8 pathNodes=16 remotes=6 deterministic=true prior=true
[Phase05PersistentProgression] PASS criteria=64 instances=914 scripts=79 gameplayRemotes=6 profileRemotes=1 shelves=8 collectionSlots=8 deterministic=true prior=true
[Phase06OnboardingMissionsAnalytics] PASS criteria=69 instances=914 scripts=79 gameplayRemotes=6 profileRemotes=1 onboardingRemotes=1 onboardingSteps=5 starterMissions=5 missionTape=295 missionXP=210 deterministic=true prior=true
```

Fresh pre-cloud-save Studio Output passed Foundation `69/69`, Phase 02 `94/94`, Phase 03 `65/65`, Phase 04 `119/119`, Phase 05 `130/130`, and Phase 06 `58/58`. The Phase 06 conflict case initially exposed a clean-profile test-fixture mistake; the fixture was corrected to dirty both sessions and assert the real conflict path, after which `58/58` passed. No production source defect was found.

At implementation head `4fe9c97a1ab5eeef4e18c34a6a584e2ed1ec8701`, branch-push run `29526402031` and pull-request run `29526404937` both passed all six Node validations. A later evidence commit requires fresh exact-head checks.

### Manual and persistence evidence

| Gate | Result | Evidence and limitation |
| --- | --- | --- |
| Established-profile Version 1-to-2 migration | Partial pass | The accepted Phase 05 Studio-test profile migrated, preserved the recorded Tape/XP/rank/collection/statistics, and reached Ready/Saved. Complete pre-migration mastery and receipt values were not captured, so full field-by-field preservation is not claimed. |
| Desktop onboarding | Partial pass | Failure/retry stayed guided; steps, first accepted placement, first shipment, completion, overlay hide, normal timing, and mission presentation were exercised. This was the established profile, not the prescribed truly fresh profile. |
| Starter path | Pass for core service/profile result | The profile reached 5/5 with 295 mission Tape and 210 mission XP. `first_fit` and `one_more` were rewarded through live play; `first_shipment`, `collector_three`, and `five_item_box` reconciled from authoritative historical statistics. A later successful shipment completed onboarding without replaying `first_shipment`. No reward replay was observed before close. |
| Touch emulator | Partial | Phone portrait and landscape showed the recorded safe-area containment, touch-only copy, working drag/place/Pack Again, and preserved durable progress. The complete Ship, SkipButton/mission-card safe-area, starter-panel, and underlying-drag suppression matrix remains unpassed. No physical-phone claim is made. |
| Gamepad emulator | Partial | Controller movement copy, `[X]`, `[A]`, `[L1]`, and gamepad focus were visible. Hold-B cancel/complete, the complete L1/B panel flow, and binding-duplication checks remain unpassed. |
| Skip | Partial | Deterministic coverage verifies validation, no reward, and exact-once state. The two-player memory test verified UI isolation. Dedicated mouse/touch, hold-B gamepad, rejoin persistence, next-round timing, analytics-once, and duplicate no-op acceptance remain incomplete. |
| Two-player Local Server | Partial | Two memory clients had distinct `O1`/`O2` state. Skipping Player B hid only B's overlay and exposed only B's mission card while Player A remained onboarding. The complete required isolation matrix remains unpassed. |
| Integrated analytics memory trace | Pending | Deterministic Studio tests pass event, ordering, privacy, cleanup, and failure-isolation coverage, but one separately captured integrated interactive fresh-player sink trace is absent. |
| Session E | Partial pass | Version 2 reached Saved and the test server shut down cleanly. The full pre-migration mastery/receipt ledger was not captured. |
| Session F | Partial pass with a current-state blocker | Direct same-profile reload now proves Schema Version 2, Ready/Saved, onboarding Completed at Step 5, all five missions completed/rewarded, 295 mission Tape, 5/5 path completion, no current mission, `LastMissionRewards=0`, complete client rows, hidden onboarding/reward banners, and clean shutdown. Session E ended with the durable profile at 5/5, leaving no defined new starter mission for the requested additional same-profile reward. An explicitly approved alternate proof is still required for that literal subgate. |
| Cloud save and full close | Pass | Fixture attributes printed `nil nil nil`; the private place reported a successful normal Roblox save; every Studio process then closed. |
| Direct cloud reopen and parity | Pass | The later signed-in no-sync reopen completed on `PlaceId 134193642444044` / `GameId 10493030248`. Fixtures remained absent. Live parity passed 1,004/1,004 managed paths, 89/89 UTF-8 sources, zero missing/extra/duplicate/wrong-class paths, all 93 authored-attribute targets, and all 5,192 bridge-exposed manifest properties. All six Studio suites passed again and the fresh game-owned warning/error count was zero. |

### Session F current-state blocker

Session E ended with the same durable Studio-test profile at every one of the five defined missions rewarded. Applying any existing mission event must correctly produce no new reward. Rewinding a `Rewarded` flag, adding a sixth mission/path reward, editing the DataStore key, or silently substituting a different profile would violate this contract. Same-profile reload/reward-no-replay now passes: the direct-reopen snapshot showed the five completed/rewarded IDs, `LastMissionRewards=0`, no reward banner, and no reward delta; a clean stop saved and released the profile. No integrated `MemoryAnalyticsAdapter` record trace was captured, so analytics-memory no-replay remains pending. Exact one-reward behavior is separately proven with deterministic memory integration, but completing the literal additional-reward portion of Session F still requires an explicitly approved alternate evidence route.

The direct-reopen client snapshot was intentionally sanitized. It recorded Schema `2`, lifecycle `Ready`, save state `Saved`, Tape `3502`, XP `593`, rank index `2`, collection `7/8`, 17 successful shipments, 34 shipped items, highest shipment count `10`, best shipment value `2225`, one perfect shipment, 34 failed rounds, mission Tape `295`, five completed starter missions, onboarding `Completed` at Step `5`, all five stable mission IDs in both completed and rewarded lists, `5/5` path completion, no current mission, and an empty last-mission-reward batch. It did not print a player identifier, profile session identifier, store key, lock token, receipt, or full payload.

Fresh post-reopen Studio Output at `2026-07-17T00:42:26Z` through `00:42:28Z` reported Foundation `69/69`, Phase 02 `94/94`, Phase 03 `65/65`, Phase 04 `119/119`, Phase 05 `130/130`, and Phase 06 `58/58`; the server selected `profileStore=StudioTest analytics=Memory`. The fresh warning/error watch returned zero issues. Clean stop printed `[ONE_MORE_ITEM][Profile] shutdown successes=1 failures=0 skipped=0`.

### Remaining technical acceptance

- Run the prescribed truly fresh-profile desktop path.
- Finish the complete touch Ship, skip, mission-panel, safe-area, and underlying-drag suppression matrix.
- Finish the complete manual skip input, persistence, timing, duplicate-no-op, no-reward, and analytics-once matrix.
- Finish the full gamepad hold-B and starter-panel control matrix.
- Finish the complete two-player timing/gameplay/reward/analytics/shelf/revision/conflict matrix.
- Capture the prescribed integrated analytics-memory sequence.
- Resolve the Session F additional-reward evidence route explicitly without modifying the 5/5 durable profile.
- Refresh documentation, PR evidence, and exact-head branch/PR checks.

Issue #4 remains open and unchanged. Its Phase 06 QA comment is intentionally withheld until technical acceptance. Phase 07 is the only next phase, but it must not begin until these Phase 06 gates are resolved.
