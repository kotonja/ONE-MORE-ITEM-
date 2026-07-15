# Phase 05 - Persistent Player Profiles, Tape, Collection, and Packing Rank

## Acceptance status

Phase 05 is implemented on `codex/phase-05-persistent-progression` in draft PR #6, but it is **not yet accepted**. All five local Node 24 gates, Play Solo, controlled two-player isolation, deterministic eight-profile coverage, two real Studio-test-store sessions, and controlled memory-adapter failure behavior passed. The last normal cloud Studio run/save/close also passed. Final review then corrected per-player waiting-snapshot `StateVersion`; all five suites passed again in an offline recovery copy, but that local file could not access the Studio-test store and the correction has not been synchronized or saved to cloud. Final apply/save/close/direct no-sync reopen/parity is blocked by the local Studio/network path: direct protocol opens failed TLS verification, while signed-in Home retries reached the correct Team Create server and then stalled without a join snapshot. Manual phone/touch and gamepad Collection opening remains incomplete. Exact-head documentation CI is recorded externally in PR #6 and the final handoff rather than self-referenced here.

Phase 04 is the protected baseline merged through PR #5 at `213f3581bd242523e34601cfefa5b5a74770ddee`. Issue #4 remains open for pre-release QA and has not received a Phase 05 acceptance comment. Phase 06 must not begin in this task.

## Canonical ownership and permanent authoring

Canonical Luau remains under `src/`. The historically named `studio/phase02.manifest.json` remains the sole owner of permanent Phase 02-05 gameplay UI, profile UI, arena content, station shelves, remotes, templates, and scripts. No overlapping Phase 05 manifest is permitted.

Permanent profile interfaces exist as real `StarterGui` descendants before Play. Collection shelves exist as real `Workspace` descendants before Play. `ProfileNet.ProfileSnapshot`, the six existing gameplay remotes, and the shelf item template exist as real `ReplicatedStorage` descendants before Play. Runtime code may bind permanent content and may create only temporary ViewportFrame models, reveal previews, number-animation presentation, and at most six temporary shelf proxies per occupied station.

The deterministic authoring contract remains parent-first, idempotent, conflict-safe, and non-destructive. A wrong-class managed path is an error; synchronization never silently replaces it. Reapplying the canonical operation list must not create duplicates.

## Profile schema version 1

The server-only persisted profile shape is:

```text
SchemaVersion = 1
Tape = non-negative integer
PackingXP = non-negative integer
Stats = {
    TotalSuccessfulShipments,
    TotalItemsShipped,
    HighestItemsInShipment,
    BestShipmentValue,
    PerfectShipments,
    TotalFailedRounds,
    TotalTapeEarned
}
Collection = {
    Discovered = { [ItemId] = true },
    MasteryCounts = { [ItemId] = non-negative integer },
    RecentDiscoveries = { ItemId }
}
Receipts = {
    ProcessedOutcomeIds = { string }
}
CreatedAt = integer Unix timestamp
UpdatedAt = integer Unix timestamp
Session = {
    Token,
    JobId,
    PlaceId,
    AcquiredAt,
    HeartbeatAt
} or nil
```

The default profile has zero Tape, zero Packing XP, zeroed statistics, empty collection maps/lists, empty receipts, valid timestamps, and no session. Every default table is independently allocated.

Rank name/index/progress, collection completion, item display data, current round, grid, player, client UI state, and temporary presentation are derived or transient and are not persisted. The profile stores no display name, chat, IP, device information, credentials, Roblox authentication, or other personal data. The server derives the data key from `Player.UserId`; real keys and lock tokens are never sent to clients or written to logs.

## Migration and normalization

`ProfileSchema` provides a deterministic, non-yielding migration boundary that never mutates its input:

- `nil` becomes a default Version 1 profile.
- The documented Version 0 fixture (`Tape`, `PackingXP`, `DiscoveredItems`, and `Mastery`) migrates explicitly to Version 1.
- Version 1 data is copied and normalized; missing fields receive defaults and unknown fields are omitted.
- Negative or non-finite Tape, XP, statistics, and mastery values normalize safely to non-negative integers within the accepted numeric bound.
- Unknown catalog IDs are removed from discovery and mastery data.
- Recent discoveries contain unique valid IDs only and remain bounded to 12. The stable convention is oldest to newest, so the newest discovery is last.
- Receipt IDs must be non-empty bounded strings, are deduplicated in first-seen order, and remain bounded to the newest 128 accepted IDs.
- Invalid timestamps receive the injected safe current timestamp.
- A future unsupported `SchemaVersion` is rejected and is never silently downgraded.

Migration calls no DataStore, scheduler, coroutine, task wait, or external callback.

## Store separation and storage adapters

Studio and production use distinct stores:

| Environment | Store |
| --- | --- |
| Non-Studio Roblox server | `ONE_MORE_ITEM_PlayerProfiles_v1` |
| Roblox Studio | `ONE_MORE_ITEM_PlayerProfiles_StudioTest_v1` |
| Deterministic tests | Injected `MemoryProfileAdapter` only |

Studio must never open or mutate the production store. If Studio API access is disabled, the only account-holder action requested is **Experience Settings > Security > Enable Studio Access to API Services**. Credentials, cookies, passwords, and tokens are never requested.

The focused server storage boundary is:

- `ProfileStoreAdapter`: typed `LoadAndLock`, `Save`, `Heartbeat`, `Release`, budget/environment, and structured-result contract.
- `DataStoreProfileAdapter`: server-only `DataStoreService` boundary. Load/claim, save, heartbeat, and release use `UpdateAsync`; every request is protected by `pcall`; budget waits and bounded retries happen outside transforms. Normal writes do not use `SetAsync`.
- `MemoryProfileAdapter`: network-free deterministic adapter with deep-copy isolation and fixtures for missing/existing profiles, active/stale locks, read/write failure, budget delay, conflict, release, and simulated crash.
- `ProfileService`: owns loaded profiles, lifecycle, dirty revisions, save scheduling, locks, safe copied snapshots, release, and shutdown. It does not calculate rewards.
- `ProgressionService`: deterministically applies successful or failed outcomes to a mutation draft and contains no DataStore call.

An `UpdateAsync` transform is pure synchronous table work. It does not yield, call `task.wait`, make a nested DataStore request, or invoke an external callback. A lock mismatch returns no replacement value, preventing an overwrite.

### Studio-only failure acceptance fixture

Controlled failure presentation uses a default-off fixture that can activate only in Studio. It reads three attributes from `ServerScriptService.ONE_MORE_ITEM_Server`:

```text
ONE_MORE_ITEM_Phase05AcceptanceMode
ONE_MORE_ITEM_Phase05AcceptanceTargetUserId
ONE_MORE_ITEM_Phase05AcceptanceExpiresAt
```

Mode must be exactly `Unavailable`, `SaveDelayed`, or `Conflict`. The expiry must be a finite integer later than `os.time()` and no more than 600 seconds ahead. Target is optional; when absent, the first joining player becomes the target. Invalid, expired, or non-Studio arming is ignored. A valid fixture selects one injected `MemoryProfileAdapter` for the **entire test server**; the target controls only which player receives the injected failure.

Example Edit-mode Command Bar arming for a five-minute test:

```lua
local host = game:GetService("ServerScriptService"):WaitForChild("ONE_MORE_ITEM_Server")
host:SetAttribute("ONE_MORE_ITEM_Phase05AcceptanceMode", "Unavailable") -- or SaveDelayed / Conflict
host:SetAttribute("ONE_MORE_ITEM_Phase05AcceptanceTargetUserId", nil) -- first joining player
host:SetAttribute("ONE_MORE_ITEM_Phase05AcceptanceExpiresAt", os.time() + 300)
```

Mandatory cleanup, run in Edit mode before any normal Studio-test persistence, cloud save, or cloud reopen:

```lua
local host = game:GetService("ServerScriptService"):WaitForChild("ONE_MORE_ITEM_Server")
host:SetAttribute("ONE_MORE_ITEM_Phase05AcceptanceMode", nil)
host:SetAttribute("ONE_MORE_ITEM_Phase05AcceptanceTargetUserId", nil)
host:SetAttribute("ONE_MORE_ITEM_Phase05AcceptanceExpiresAt", nil)
```

Never save or publish the place while the fixture is armed. Fixture wallets, receipts, conflicts, and saves exist only in memory and cannot replace the Session A/B Studio-test-store persistence proof.

## Session locking

One server-session identifier is created once per server process from non-empty `game.JobId`, or one generated GUID in Studio/test. Every player load receives a unique secret lock token. Tests inject clocks, server-session IDs, and tokens.

Configured bounds are:

- Heartbeat: 60 seconds or less.
- Stale-lock timeout: 180 seconds.
- Load attempts: at most 5.
- Save attempts: at most 5.

Load-and-lock migrates the stored value and claims an absent or stale lock. The exact same token may refresh its own lock. A different non-stale lock returns an active-lock conflict. Save and heartbeat verify the token before writing. Release clears only the exact owned token. Lock loss transitions the profile to `Conflict`, blocks progression, ends reward-bearing gameplay, releases the station, and clears the shelf; a stale process cannot overwrite or release the new owner.

The secret token and heartbeat never enter `ProfileSnapshot` or logs. `ProfileSessionId` is a separate presentation-safe identifier used only to scope client revision ordering.

## Outcome IDs and receipt deduplication

Every round receives an immutable server-created identifier at round start:

```text
{UserId}:{ServerSessionId}:{RoundId}
```

The client cannot supply or choose any component. `RoundId` is the player's server-local ordinal; `ServerSessionId` prevents collisions after restart. Tests inject deterministic identifiers and enforce a bounded identifier length.

A successful `ShipmentRecord` uses `OutcomeId` as its persistent receipt. A failed round uses the same round `OutcomeId`. A profile stores an ordered maximum of 128 processed IDs. The first valid result mutates progression and appends once; a repeat returns an explicit immutable `Duplicate` reward with zero deltas. Shipment and failure cannot both process one ID. Receipt eviction changes no current progression, and globally unique identifiers prevent ordinary post-eviction collisions.

## Profile lifecycle and assignment gating

The lifecycle states are:

| State | Gameplay and presentation contract |
| --- | --- |
| `Loading` | No station or round; normal movement; `LOADING PROFILE` / `LOADING YOUR PROFILE`. |
| `Ready` | Profile may receive a station or enter the existing FIFO queue. |
| `Saving` | Gameplay may continue; `SAVING`. |
| `SaveDelayed` | Lock is still owned, dirty data remains in memory, retry remains scheduled, gameplay may continue temporarily; `SAVE DELAYED`. |
| `Unavailable` | Initial load exhausted bounded retries; no station or progression-bearing round; normal movement; `DATA UNAVAILABLE` and `REJOIN TO RETRY`. |
| `Conflict` | Ownership is lost or active elsewhere; no new rewards, active reward-bearing round stops safely, station/shelf release; `PROFILE OPEN ELSEWHERE`. |
| `Releasing` | New mutations are rejected while final bounded save/release runs. |
| `Released` | No profile is available to gameplay services. |

Bootstrap order is join -> Loading -> Ready -> station assignment/queue -> round. `ClientReadyRequest` may arrive before or after load; both readiness conditions are retained without assigning early. Loading, Unavailable, and Conflict do not consume a station. A ninth Ready player joins the existing FIFO queue, and promotion rechecks profile readiness. A Ready player without a station sees `WAITING FOR A PACKING STATION`. Round requests from a non-Ready profile are rejected. Per-player waiting snapshots monotonically advance `StateVersion` across Loading, queued Ready, and Unavailable even while `RoundId` stays `0`, preventing `ClientRoundStore` from rejecting a real lifecycle transition as stale.

On player removal, mutation closes first; the round and temporary content are invalidated; the station and shelf release promptly; bounded profile save/release begins independently; then request-rate and client-facing state are cleared. A slow store request never holds the station.

## Save lifecycle, heartbeat, and shutdown

A progression mutation increments the in-memory revision and marks the profile dirty. One shared scheduler coalesces rapid mutations with a 5-second dirty-save debounce, catches dirty profiles on a 60-second autosave interval, and maintains heartbeat at 60 seconds or less. Save concurrency is bounded to 8; there is no per-profile frame loop and no unbounded task spawning.

A save captures its mutation revision. It clears dirty state only when no newer mutation occurred while the request was in flight. Request-budget delay and bounded exponential backoff occur outside `UpdateAsync`. A failed owned write becomes `SaveDelayed`; later success becomes `Ready`/`Saved`. Lock loss becomes `Conflict`. The UI never says `SAVED` until a real successful write returns.

`BindToClose` stops new mutations, marks loaded profiles Releasing, starts bounded concurrent final save/release work, preserves each lock until its final data write succeeds or bounded attempts end, and waits no longer than the documented 25-second deadline. One profile failure cannot block the others. Shutdown logs only concise success/failure counts and never profile payloads or tokens.

## Persistent Tape, XP, and reward ordering

The profile, not `RoundService`, is the canonical Tape wallet. Shipment reward is:

```text
TapeDelta = ShipmentValue
NewTape = OldTape + TapeDelta
```

Tape is a finite non-negative integer. The client supplies neither delta nor balance. Duplicate outcomes add nothing. Showcase rejection/failure cannot alter an accepted reward. The round snapshot's compatibility bank value is sourced from canonical profile Tape, and player-facing copy says `TAPE`.

Successful shipment XP is:

```text
10 + (4 * ItemCount) + floor(ShipmentValue / 100)
    + 25 when ItemCount reaches the maximum shipment size
```

Failure consolation XP is `min(ItemCount * 2, 10)`; a zero-item failure gives zero. Failure gives no Tape, discovery, or mastery. XP is a bounded non-negative integer and rank is always derived from canonical total XP.

Progression executes before cosmetic shipment consumers. A profile mutation failure cannot be presented as a successful reward; a later cosmetic failure never reverses a successful mutation.

## Packing ranks

Ranks are strict, ordered, unique, and derived rather than persisted:

| Index | Rank | XP threshold |
| --- | --- | ---: |
| 1 | Rookie Packer | 0 |
| 2 | Box Handler | 300 |
| 3 | Space Saver | 1,000 |
| 4 | Packing Optimizer | 2,500 |
| 5 | Master Packer | 5,000 |
| 6 | Legendary Shipper | 9,000 |
| 7 | Impossible Shipper | 15,000 |

Pure APIs resolve rank, index, threshold, next rank, and progress at every boundary. The maximum rank has no next threshold. One reward may cross multiple thresholds; presentation shows only the final rank with a `+{count} RANKS` indicator when more than one rank was crossed.

## Collection, discovery, and mastery

The stable catalog references the existing development item definitions in their canonical order: Parcel, Long Package, Lamp Blockout, Table Blockout, Chair Blockout, L Package, T Package, and Heavy Cargo. Player data stores IDs only; display name, development shape/color, and value remain content data. No final models are introduced.

Only a successful immutable shipment discovers items. The service validates every placed-item ID before any mutation, so an unknown ID rejects the entire outcome without partial Tape, XP, statistics, discovery, mastery, or receipt changes. Discovery follows placed-item order, appears once in `NewDiscoveries`, and updates the bounded recent list using the documented oldest-to-newest convention. A duplicate item in one shipment increments mastery once per occurrence.

Mastery is persistent count plus derived tier:

| Tier | Successful shipped occurrences |
| --- | ---: |
| Locked | 0 and undiscovered |
| Discovered | 1-4 |
| Bronze | 5-19 |
| Silver | 20-49 |
| Gold | 50+ |

Pure APIs resolve tier, next threshold, and progress. A mastery result reports item ID, previous/new counts, and previous/new tiers. Failure and duplicate outcomes change nothing. Mastery grants no power, value, or placement benefit.

## Persistent statistics and reward result

One successful shipment updates exactly once:

- `TotalSuccessfulShipments += 1`
- `TotalItemsShipped += ItemCount`
- `HighestItemsInShipment = max(previous, ItemCount)`
- `BestShipmentValue = max(previous, ShipmentValue)`
- `PerfectShipments += 1` for a maximum-size shipment
- `TotalTapeEarned += ShipmentValue`

One failed round updates `TotalFailedRounds += 1`. All fields remain server-authoritative non-negative integers.

The immutable progression result contains `OutcomeId`, `RoundId`, type, Tape delta/new balance, XP delta/previous/new totals, previous/new rank, new discoveries, mastery changes, copied updated statistics, and `Duplicate`. It is the single result used by presentation, `LastReward`, tests, and dirtying. It exposes no receipt history, lock/session token, storage object, internal profile reference, or DataStore metadata.

## ProfileSnapshot and client ordering

The six gameplay RemoteEvents remain exactly unchanged under `ReplicatedStorage.ONE_MORE_ITEM.Net`. The only profile remote is the permanent server-to-client event:

```text
ReplicatedStorage.ONE_MORE_ITEM.ProfileNet.ProfileSnapshot
```

There is no client-to-server profile mutation remote. The snapshot contains presentation session ID, monotonically increasing revision, lifecycle/save state, Tape, Packing XP, derived rank progress, ordered discoveries, copied mastery counts, collection counts, copied statistics, and copied `LastReward`. It contains no secret session token, heartbeat, receipt list, DataStore key, or mutable server table.

`ClientProfileStore` deep-copies accepted snapshots, rejects duplicate/lower revisions within one presentation session, accepts revision reset only with a new safe `ProfileSessionId`, notifies subscribers only for accepted state, and clears subscribers on destroy. It is independent from `ClientRoundStore`. The server publishes fresh snapshots after lifecycle/load changes, successful or failed progression, save-state changes, conflict, and release when useful; it does not replicate per frame.

Round and profile snapshots may arrive in either order. Outcome and round IDs correlate them. Save-state updates with the same reward do not replay presentation; duplicate snapshots do not replay; reconnect does not replay an already processed reward; and one client session reveals each accepted outcome at most once. Presentation never delays authoritative gameplay.

## Permanent UI hierarchy and controls

`StarterGui.ONE_MORE_ITEM_Gameplay.Root` permanently authors:

```text
MetaBar
  TapeLabel
  TapeValue
  RankName
  RankProgressBar
    Background
    Fill
  RankProgressText
  CollectionButton
  DataStatus
CollectionPanel
  Header
  CloseButton
  CollectionSummary
  RankSummary
  StatsSummary
  Slots
    Slot_01 ... Slot_08
DiscoveryReveal
  ItemViewport
  ItemName
  DiscoveryLabel
  MasteryLabel
RankUpBanner
  RankLabel
  RankName
ResultsPanel
  XPReward
  RankProgress
  DiscoverySummary
```

Every authored collection slot contains `ItemViewport`, `ItemName`, `LockOverlay`, `MasteryTier`, `MasteryCount`, `MasteryProgress`, `Corner`, and `Stroke`. Slots are never created at runtime.

The toy-industrial visual language remains: amber/gold Tape, cyan/white ranks, purple discovery/mastery accents, dark collection panels, and gold reserved for maximum-rank or rank-up emphasis. Loading/Saving are cyan, Saved is subdued green, Save Delayed is amber, and Unavailable/Conflict are red. Saved does not pulse continuously and there is no full-screen loading menu.

Tape remains visible during gameplay. Collection opens only in Results, waiting, spectator, or Ready-between-rounds state; it closes on an active round and never pauses the server. It remains disabled/subdued during placement, decision, shipping, failure, Loading, Conflict, and Unavailable. Desktop uses button click, `C`, and Escape; touch uses authored open/close buttons with no hidden gesture; gamepad uses ButtonY/ButtonB and safe selection cleanup. No ContextActionService touch button is generated, no menu input mutates the server, and open profile UI prevents activation of gameplay controls beneath it.

Locked slots use a consistent `???` name and silhouette treatment with mastery hidden. Discovered slots show the development shape/color, name, tier, successful shipped count, and progress to the next threshold. Gold displays `50+ SHIPMENTS`.

## Motion and reward presentation

All number motion is cancellable, retargetable, and ends at exact authoritative values:

- Tape counts from the prior accepted balance over about 0.55-0.80 seconds for a reward.
- XP counts over about 0.55 seconds; the rank bar traverses thresholds continuously.
- Only affected mastery counts animate, over about 0.35 seconds.
- Save-state-only and duplicate snapshots do not replay number motion.

New discoveries queue in shipment order. Each card scales from about 92% to 100%, turns the preview once, changes silhouette to development color, shows `NEW ITEM DISCOVERED`, item name, and authoritative mastery, holds about 1.0-1.2 seconds, then exits. Mastery tier-ups reuse the focused reveal with `MASTERY BRONZE`, `MASTERY SILVER`, or `MASTERY GOLD`. Discovery and mastery events for one reward use a deterministic sequence.

Rank-up presentation enters from upper center, lightly dims the background, shows `PACKING RANK UP` and the final new rank, holds about 1.2 seconds, then exits. Pack Again remains available; beginning a new round may shorten pending presentation but never duplicates it. Phase 05 adds no sound asset, only a future audio hook.

## Station collection shelves

Every permanent `Station_01` through `Station_08` authors:

```text
CollectionShelf
  ShelfBase
  ShelfLabel
    BillboardGui
      RankName
      CollectionCount
  Slot_01 ... Slot_06
  Runtime
```

`ReplicatedStorage.ONE_MORE_ITEM.Assets.Development.CollectionShelfItemTemplate` is one script-free anchored, non-colliding, non-touching, non-queryable simplified development proxy. It is not final art and shelves do not clone full cell-shape models.

`CollectionShelfService` resolves all eight authored shelves, renders only after profile load and station ownership, shows derived rank/discovered count, clears prior runtime children before refresh, and creates at most six temporary proxies. Selection is deterministic: up to three newest valid discoveries first, then remaining discoveries by mastery tier descending, mastery count descending, and catalog order. IDs do not repeat. Release/conflict clears only the affected shelf; a new owner starts clean; one render failure cannot remove an accepted progression reward; shelf refresh never writes profile data.

## Automated verification contract

Phase 05 retains the exact inherited Studio totals: Foundation 69, Phase 02 94, Phase 03 65, and Phase 04 119. `Phase05TestSuite` and `RunPhase05Tests` cover schema defaults/migration, rank/mastery boundaries, OutcomeId uniqueness, success/failure rewards, snapshot privacy/revision ordering, memory adapter behavior, pure DataStore transforms, profile lifecycle/save scheduling, station gating, monotonically versioned Loading/queue/Unavailable snapshots at one round ID, round ordering, shelves, client presentation, autosave, and bounded eight-profile shutdown with fixed clocks, schedulers, identifiers, and adapters. No deterministic Studio test makes a live DataStore request.

The dependency-free `tools/test_phase05_persistent_progression.mjs` first requires all four inherited Node validations and then checks schema/store separation, server-only DataStore access, `UpdateAsync` discipline, non-yielding transforms, memory adapter, locks/receipts/outcome IDs, rank/mastery/catalog contracts, permanent ProfileNet/UI/shelves/template, exactly six gameplay remotes, strict sources/tests, deterministic/idempotent authoring, non-destructive conflicts, tracked-file safety, workflow coverage, Phase 04 merge documentation, issue #4, and Phase 05 status.

The workflow is `Phase 01–05 Node Validation`, uses Node 24, `actions/checkout@v7`, `actions/setup-node@v6`, `contents: read`, disabled package-manager cache, no package install, and no third-party dependency. It runs all five Node gates for pull requests to `main` and pushes to `main` or `codex/**`.

Fresh local Node 24 evidence passed exactly:

```text
[StudioSyncSmoke] PASS checks=16 folders=7 scripts=10 deterministic=true
[Phase02StudioSyncSmoke] PASS criteria=28 instances=833 scripts=65 remotes=6 deterministic=true phase01=true
[Phase03LayoutMatrix] PASS viewports=13 insetProfiles=5 cases=65 desktopCompatible=true safeContainment=true
[Phase03CrossPlatformSmoke] PASS criteria=31 viewports=13 insetProfiles=5 layoutCases=65 remotes=6 deterministic=true phase01=true phase02=true
[Phase04MultiplayerArena] PASS criteria=42 instances=833 scripts=65 stations=8 pathNodes=16 remotes=6 deterministic=true prior=true
[Phase05PersistentProgression] PASS criteria=56 instances=833 scripts=65 gameplayRemotes=6 profileRemotes=1 shelves=8 collectionSlots=8 deterministic=true prior=true
```

The last normal cloud Studio-test run before the queue correction passed Foundation `69/69` with fuzz seed `24012026` and 1,000 cases, Phase 02 `94/94` with seed `24022026`, Phase 03 `65/65` with seed `13072026`, Phase 04 `119/119` with seed `14072026`, and Phase 05 `123/123` with seed `15072026`. The Phase 05 deterministic suite used memory; the normal server separately reported `profileStore=StudioTest`. Normal stop logged shutdown `successes=1 failures=0 skipped=0`, followed by zero fresh actionable game-owned errors/warnings. After commit `bf144fc3cb478823a80ceadaafc28cb78298bf12` added the queue regression contract, a fresh offline recovery-copy Play run passed the same `69/69`, `94/94`, `65/65`, `119/119`, and `123/123` totals. Its expected `Profile store unavailable for StudioTest` error makes it suite-only evidence, not a new persistence or clean-Output result.

Implementation head `bf144fc3cb478823a80ceadaafc28cb78298bf12` passed branch-push run `29398524215` / job `87297461413` and draft-PR run `29398526422` / job `87297468905`, with every Phase 01-05 step successful. The containing documentation commit and its exact-head runs are recorded externally in PR #6 and the final handoff.

## Manual and failure-state verification

Play Solo proved Loading before Station_01 assignment, persistent Tape/XP/rank/collection presentation, one Parcel shipment at exactly `+15` Tape and `+14` XP, a later one-item failure at `+2` XP with no Tape/discovery/mastery, Pack Again retention, owner-shelf presentation, a real Saved state, normal shutdown, and zero fresh actionable game-owned Output. The final normal run loaded Tape `30`, XP `30`, Ready/Saved, and Station_01 from the Studio-test store.

The controlled two-player memory run gave Player1 Station_01 and Player2 Station_02 with distinct user/session/revision state. The target reached Tape `30`/XP `28` after two one-item shipments while the unaffected player remained Tape `0`/XP `0`; no cross-player contamination appeared. One client was forcibly terminated to simulate abrupt departure, but no explicit manual shelf-release log was captured from that termination. Release/isolation is covered deterministically; the missing manual log is not claimed as passed.

Controlled failure evidence used only the explicitly armed memory fixture:

- `Unavailable`: 5 bounded load attempts, normal movement with no station/round, visible `DATA UNAVAILABLE` / `REJOIN TO RETRY`.
- `SaveDelayed`: in-memory progression remained stable, retry recovered at save attempt 4, stored memory progression matched, OutcomeId stayed stable, and the checked outcome had one receipt. Exact hook logs and final Saved presentation passed; the transient amber `SAVE DELAYED` visual was not captured.
- `Conflict`: target round cleared, station released, shelf runtime returned to `0`, final state became Conflict, and visible copy showed `PROFILE OPEN ELSEWHERE` / `CLOSE THE OTHER SESSION AND REJOIN`; unaffected Player2 remained Saved at Station_02.
- Eight-profile deterministic coverage passed independent defaults/locks, eight mutations/saves, isolated failure/conflict, and bounded shutdown.

Desktop collection presentation was exercised. The gamepad prompt displayed `C/Y`, but ButtonY/ButtonB open/close was not completed, and phone/touch collection opening was not manually exercised. Deterministic layout/input coverage remains green but does not replace those manual gates. No physical phone/controller result is claimed.

## Required two-session Studio-test persistence proof

Only `ONE_MORE_ITEM_PlayerProfiles_StudioTest_v1` may be used. Evidence must avoid full payloads, real keys, and lock tokens.

This proof passed:

| Evidence | Verified result |
| --- | --- |
| Session A baseline | Tape `0`, XP `0`, Parcel mastery `0`, discovered `0`, successful shipments `0`. |
| Session A post-play | Tape `15`, XP `16`, Parcel mastery `1`, discovered `1/8`, successful shipments `1`, failed rounds `7`, total Tape earned `15`. The deliberate one-item failure supplied the additional `+2` XP. |
| Session A save/close | Saved/clean; shutdown `successes=1 failures=0 skipped=0`; every Studio process then closed. |
| Session B direct no-sync reopen | Loaded the exact Session A values: Tape `15`, XP `16`, Parcel mastery `1`, discovered `1`, successful shipments `1`. |
| Session B second shipment | Added exactly `+15` Tape and `+14` XP, raised Parcel mastery to `2`, retained one discovery, raised successful shipments to `2`, and did not replay Session A. |
| Session B final save | Tape `30`, XP `30`, Parcel mastery `2`, discovered `1/8`, successful shipments `2`, failed rounds `10`, total Tape earned `30`, Saved; shutdown `successes=1 failures=0 skipped=0`. |

This is real Studio-test-store persistence evidence. Repository tests and in-memory fixtures did not substitute for it. The passed Session B reopen occurred before the acceptance-hook/UI synchronization and queue correction and therefore does not satisfy the later final cloud-place apply/save/reopen/parity gate below.

## Cloud place persistence proof

The canonical target contains 909 unique Phase 01 plus Phase 02-05 paths: 834 non-script instances and 75 sources. A recovery copy was saved outside Git (261,264 bytes; SHA-256 `18C06C0874C256A58E30E33882812A77D9FACB3A26A4A283514A1EC673BBAFF2`). Its personal filesystem path is intentionally omitted.

The 898-operation Phase 02-05 blueprint was rebuilt and applied twice at the then-current pre-queue-correction source state. Both applies reported `Created=0 Updated=898 Failed=0`; the apply captured 65 script backups. Acceptance attributes were confirmed cleared before that normal Studio-test run and cloud save. All five suites passed, the normal Studio-test profile loaded Tape `30`/XP `30`, shutdown succeeded, and a fresh Output baseline contained zero actionable game-owned warnings/errors. The cloud save completed with no unsaved marker, then all Studio processes closed. Commit `bf144fc3cb478823a80ceadaafc28cb78298bf12` was subsequently verified only in the offline recovery copy and has not been synchronized or saved to the cloud place.

Final direct reopen is **blocked, not passed**. Two direct protocol opens returned `Studio is unable to connect. Check your network connection and try again.` Those logs report `HttpError: TlsVerificationFail` and OpenSSL `unable to get local issuer certificate (20)` on Roblox API requests while Avast HTTPS interception was active. Two later opens through the signed-in Studio Home page had zero TLS-verification failures, recorded the correct PlaceId `134193642444044`, universe `10493030248`, and Team Create endpoint, but stalled before a join snapshot completed and the editor appeared. Because the place did not finish reopening, no final `909/909` managed-path parity, `75/75` source parity, zero duplicate/wrong-class result, permanent UI/shelf/remote parity, post-reopen Studio suites, or post-reopen Output claim is made.

The earlier successful Session B no-sync reopen proves the Studio-test profile persisted between Sessions A and B. It does not prove the last pre-queue-correction cloud state survived the later close, and it does not prove the repository queue correction reached cloud. Phase 04's accepted cloud reopen remains historical evidence only.

## Known limitations and deferred pre-release QA

- Phase 05 has development geometry and text-only iconography; no final object models, external assets, audio, music, final VFX, haptics, or final Tape-wrap presentation are included.
- A graphical eight-player DataStore stress test is not required. Deterministic eight-profile isolation is the Phase 05 gate.
- Final cloud completion is blocked by the local Roblox Studio/Avast network path: protocol TLS failures were followed by a no-join-snapshot Team Create stall. The repository queue correction remains unsaved to cloud, and post-save direct-reopen managed/source/UI/shelf/remote parity plus fresh suites/Output remain unpassed.
- Manual phone/touch and gamepad Collection opening/closing remains incomplete. The transient amber SaveDelayed visual was also not captured, although exact memory-fixture recovery logs and final Saved presentation passed.
- Issue #4 remains open. Only after Phase 05 acceptance may one concise comment add future eight-player production DataStore budget observation, long-session autosave/heartbeat soak, abrupt-shutdown recovery, rapid reconnect after stale-lock expiry, production-store rollout rehearsal, Data Stores Manager inspection, low-connectivity save-delay presentation, and extended profile-memory observation. None is currently claimed as passed, and none replaces deterministic or two-session proof.
- No production store is opened from Studio and no production DataStore rollout is claimed.

## Deferred by design

Phase 05 excludes daily challenges, starter missions, offline income, cosmetics/ownership/store, Robux products, monetization, trading, pets, rebirths, multiple worlds, co-op packing, cheer reactions, persistent/global/OrderedDataStore leaderboards, analytics, quests, final models, external assets, sound/music, final VFX, haptics, final Tape wrap, item power, functional mastery bonuses, rank bonuses, and every Phase 06 system.

## Exact next recommendation

Do not begin Phase 06. First repair the local Roblox Studio/Avast network path so PlaceId `134193642444044` opens in the editor; synchronize commit `bf144fc3cb478823a80ceadaafc28cb78298bf12`; save normally; close every Studio process; and reopen directly without synchronization. Then verify `909/909` managed paths, `75/75` exact sources, zero duplicate/wrong-class paths, permanent profile UI/eight shelves, exactly six gameplay remotes plus one ProfileSnapshot remote, all five Studio suites, and zero fresh actionable game-owned Output. Complete manual phone/touch and gamepad Collection open/close and confirm the exact-head branch/PR CI recorded in PR #6. Only after those gates pass may Phase 05 be accepted and issue #4 receive its concise follow-up.
