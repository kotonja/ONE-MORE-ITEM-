# Phase 05 - Persistent Player Profiles, Tape, Collection, and Packing Rank

## Acceptance status

Phase 05 is **implementation complete and accepted** on `codex/phase-05-persistent-progression` at implementation head `07d887a11c4ff5256ee663f6f306e9ca41cfbedf`. The final correction made collection shelves idempotent and canonical-catalog driven, expanded deterministic coverage, synchronized canonical source twice to the private cloud place, saved normally, completely closed Studio, and reopened through the normal signed-in route without post-reopen synchronization. The bounded bridge-observable parity projection, all five post-reopen Studio suites, current-code Studio-test-store Sessions C/D, and focused touch/gamepad Collection checks in Studio emulators passed. Acceptance fixtures remained absent, and the final cleaned verification had zero fresh game-owned warnings/errors. Exact-head documentation CI is recorded externally in PR #6 and the final handoff rather than self-referenced here.

Phase 04 is the protected baseline merged through PR #5 at `213f3581bd242523e34601cfefa5b5a74770ddee`. Phase 05 was subsequently squash-merged through PR #6 as `d644411b48e20cd9bb256d3d2c55a647efc2adfd`. Issue #4 remains open, and its [Phase 05 persistence QA additions](https://github.com/kotonja/ONE-MORE-ITEM-/issues/4#issuecomment-4983229288) list the explicitly unpassed pre-release checks. Phase 06 is now isolated on `codex/phase-06-onboarding-starter-missions` in draft PR #7.

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

`CollectionShelfService` resolves all eight authored shelves and renders only after profile load and station ownership. Catalog order/count come from `CollectionDefinitions`; mastery tier comes from `MasteryDefinitions`; display data comes from `DevelopmentItemDefinitions`. Selection remains deterministic: up to three newest valid discoveries first, then remaining discoveries by mastery tier descending, mastery count descending, and catalog order. IDs do not repeat and at most six proxies exist.

Each station caches a stable presentation fingerprint containing only the displayed rank identity, canonical valid discoveries/mastery counts, recent order, selected featured IDs, and displayed collection count. Lifecycle state, SaveState, snapshot revision, presentation/session identifiers, receipts, undisplayed statistics, Tape, and XP that does not change displayed rank are excluded. A matching fingerprint returns `UNCHANGED` only after structural validation confirms the expected proxy count, ItemIds, slot placement, and proxy properties; it preserves labels and Instance identities. Changed presentation or malformed runtime clears/rebuilds once and returns `RENDERED`. Clear/release invalidates the cache and leaves Runtime empty, `ProfileRendered=false`, and `FeaturedItemCount=0`, so even a visually identical replacement owner receives fresh proxies. The service has no persistence responsibility, frame loop, heartbeat loop, or remote.

## Automated verification contract

Phase 05 retains the inherited Studio totals: Foundation 69, Phase 02 94, Phase 03 65, and Phase 04 119. The accepted Phase 05 total is now 130/130. `Phase05TestSuite` covers schema/migration, progression, privacy/revision ordering, memory adapter behavior, pure DataStore transforms, lock/save scheduling, assignment gating, monotonically versioned waiting snapshots, client presentation, autosave, eight-profile shutdown, and the focused shelf contracts below. No deterministic Studio test makes a live DataStore request.

Shelf coverage includes first render; identical render; save-only equivalent; XP change within one rank; rank transition; discovery order/deduplication; mastery count/tier/sort; clear/cache invalidation; identical owner replacement with fresh Instances; eight-station isolation; malformed-runtime recovery; ten repeated identical refreshes; and a real `MemoryProfileAdapter` reward -> Saving -> Saved lifecycle. The focused lifecycle reported one progression rebuild, `UNCHANGED` for save-only states, stable proxy identities/count, and cleanup to zero.

The dependency-free `tools/test_phase05_persistent_progression.mjs` first requires all four inherited Node gates and now validates 64 Phase 05 criteria, including canonical collection/mastery imports, no duplicated shelf thresholds or `/ 8 DISCOVERED` text, canonical ProfileUI slot mapping, authored slot/catalog parity, eight shelves/six shelf slots, six gameplay remotes, exactly one server-to-client profile remote, deterministic authoring, and tracked-file safety.

Fresh local Node 24 evidence passed exactly:

```text
[StudioSyncSmoke] PASS checks=16 folders=7 scripts=10 deterministic=true
[Phase02StudioSyncSmoke] PASS criteria=28 instances=833 scripts=65 remotes=6 deterministic=true phase01=true
[Phase03LayoutMatrix] PASS viewports=13 insetProfiles=5 cases=65 desktopCompatible=true safeContainment=true
[Phase03CrossPlatformSmoke] PASS criteria=31 viewports=13 insetProfiles=5 layoutCases=65 remotes=6 deterministic=true phase01=true phase02=true
[Phase04MultiplayerArena] PASS criteria=42 instances=833 scripts=65 stations=8 pathNodes=16 remotes=6 deterministic=true prior=true
[Phase05PersistentProgression] PASS criteria=64 instances=833 scripts=65 gameplayRemotes=6 profileRemotes=1 shelves=8 collectionSlots=8 deterministic=true prior=true
```

Post-reopen cloud-place Studio evidence passed exactly:

| Suite | Suites/tests/passed/failed | Seed, adapter, and duration |
| --- | --- | --- |
| Foundation | `15 / 69 / 69 / 0` | fuzz seed `24012026`, 1,000 cases, `0.256185s`; benchmark `0.115899s` non-gating |
| Phase 02 | `11 / 94 / 94 / 0` | seed `24022026`, `6.280816s` |
| Phase 03 | `8 / 65 / 65 / 0` | seed `13072026`, `0.004279s` |
| Phase 04 | `13 / 119 / 119 / 0` | seed `14072026`, `0.687169s` |
| Phase 05 | `16 / 130 / 130 / 0` | seed `15072026`, adapter `memory`, `0.341500s` |

The Phase 05 suite's memory adapter is deterministic test isolation. Normal Play separately used `ONE_MORE_ITEM_PlayerProfiles_StudioTest_v1`, never the production store. After unsaved observers were removed, final verification contained zero fresh game-owned warnings/errors; unrelated Studio/plugin diagnostics are not represented as game-owned failures.

Implementation head `07d887a11c4ff5256ee663f6f306e9ca41cfbedf` passed branch-push run `29428471528` / job `87396972732` and draft-PR run `29428474234` / job `87396981747`, with every Phase 01-05 step successful. The containing documentation commit and its exact-head runs are recorded externally in PR #6 and the final handoff.

## Manual and failure-state verification

Normal Studio-test-store Play proved Loading before station assignment, Ready/Saved state, exact-once Tape/XP/mastery/statistics, Pack Again retention, authoritatively updated profile UI/shelf presentation, and clean stop. Controlled memory fixtures separately passed:

- `Unavailable`: 5 bounded load attempts, normal movement with no station/round, visible `DATA UNAVAILABLE` / `REJOIN TO RETRY`.
- `SaveDelayed`: in-memory progression stayed stable, retry recovered on the configured later attempt, stored memory matched, and the checked outcome remained single-receipt. Exact hook logs and final Saved presentation passed; no transient amber frame is claimed.
- `Conflict`: target round cleared, station released, shelf runtime returned to zero, and visible conflict copy appeared while the unaffected player continued.
- Eight-profile deterministic coverage passed independent defaults/locks, mutations/saves, isolated failure/conflict, and bounded shutdown.

Focused touch acceptance used Studio Device Emulator with an iPhone XR profile, not a physical phone. The Collection button/panel remained inside the safe area across portrait/landscape, opened and closed once, exposed all eight readable authored slots with correct locked/discovered/mastery presentation, blocked underlying gameplay/touch activation, left no active placement touch, and sent no gameplay remote.

Focused gamepad acceptance used Studio Controller Emulator with the Xbox One virtual controller, not a physical controller. ButtonY opened once and focused the first discovered slot; locked slots stayed non-selectable; ButtonA sent no gameplay/profile mutation; gameplay bindings were suppressed while open; ButtonB closed and cleared focus; bindings did not double; and menu navigation sent no gameplay remote. The clickable emulator overlay changed PreferredInput to KeyboardMouse before closure, so the state-appropriate closed binding/action was zero/nil; the pre-open gamepad trace separately showed the normal three Results bindings and `RESTART` action.

## Current-code Session C/D persistence proof

Only `ONE_MORE_ITEM_PlayerProfiles_StudioTest_v1` was used. Sanitized evidence excludes player identifiers, store keys, lock tokens, OutcomeId values, and full payloads.

| Evidence | Verified result |
| --- | --- |
| Session C baseline | Ready/Saved, Rookie Packer, Tape `588`, XP `97`, Parcel mastery `5`, discovered `5`, successful shipments `5`, total items `10`, total Tape earned `588`, receipt count `27`, five proxies; no load-time reward replay or duplicate Tape/XP. |
| Session C one-Parcel shipment | Tape `603` (`+15`), XP `111` (`+14`), Parcel mastery `6` (`+1`), successful shipments `6` (`+1`), total items `11` (`+1`), total Tape earned `603` (`+15`), discovered count unchanged at `5`, receipt count `28` (`+1`), one reward reveal. |
| Session C Saving/Saved | The progression mutation caused one physical five-proxy replacement cycle. Saving and Saved preserved the replacement proxy identities/count, did not rebuild again, and did not replay the reward; final state Ready/Saved. |
| Session D reload | Loaded Tape `603`, XP `111`, Rookie Packer, Parcel mastery `6`, discovered `5`, successful shipments `6`, total items `11`, total Tape earned `603`, receipt count `28`, Ready/Saved, and five shelf proxies with no prior reward replay or gameplay request. |

## Earlier Session A/B Studio-test proof

The earlier proof also used only `ONE_MORE_ITEM_PlayerProfiles_StudioTest_v1`: Session A saved Tape `15`, XP `16`, Parcel mastery `1`, one discovery, and one shipment; after every Studio process closed, Session B direct no-sync reopen loaded those exact values, applied a second shipment once, and saved Tape `30`, XP `30`, Parcel mastery `2`, one discovery, and two shipments. This remains valid historical evidence. Repository tests and memory fixtures did not substitute for either A/B or current C/D.

## Cloud place persistence and parity proof

The canonical target contains 909 unique Phase 01 plus Phase 02-05 paths: 834 non-script instances and 75 sources. A temporary recovery copy remained outside Git. All three acceptance-fixture attributes were absent before synchronization, before save, and after reopen.

The corrected 898-operation Phase 02-05 synchronization ran twice, at `2026-07-15T15:33:38Z` and `2026-07-15T15:36:21Z`. Each apply reported `Created=0 Updated=898 Skipped=0 Failed=0 Warnings=0` and 65 script backups. Normal cloud save reported `Saving to Roblox...` and then `Saved new changes in "ONE MORE ITEM!" to Roblox.` Every Studio process closed and the process count reached zero.

Roblox Studio build `0.730.0.7300790` then reopened the original private place through the normal signed-in route in Edit mode; the observed reopened process count was two (editor plus a Studio-owned renderer/helper process), and the expected place/game identifiers matched. No repository synchronization ran after reopen.

The read-only audit passed:

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

Structure additionally passed `shelves=8/8`, `shelfSlots=48/48`, `emptyRuntime=8/8`, `collectionSlots=8/8`, `gameplayRemotes=6/6`, and `profileRemotes=1/1`, with MetaBar, DataStatus, CollectionPanel, DiscoveryReveal, RankUpBanner, Results progression fields, the shelf template, and no client-to-server profile mutation remote.

The parity helper reported `authored=5567`, `compared=5660`, and `helperUnobservable=383`. Therefore `properties=5660/5660` is full parity for the bridge-observable projection only; it is not a claim that the helper independently read back the 383 unsupported keys/attributes. Canonical UTF-8 source comparison was exact for all `75/75` sources.

The earlier TLS/no-join-snapshot block and offline recovery-copy limitation are preserved in the changelog as historical sequence. They do not imply that the later correction had already been cloud-saved during that blocked attempt.

## Known limitations and deferred pre-release QA

- No known Phase 05 implementation blocker remains.
- Phase 05 retains development geometry/text-only iconography; final models, external assets, audio, music, final VFX, haptics, and final Tape wrap remain absent.
- [Issue #4's Phase 05 persistence QA additions](https://github.com/kotonja/ONE-MORE-ITEM-/issues/4#issuecomment-4983229288) keep unpassed eight-player production DataStore budget observation, long autosave/heartbeat soak, abrupt shutdown/stale-lock/rapid-reconnect recovery, production-store rehearsal, Data Stores Manager inspection, low-connectivity Save Delayed presentation, physical phone/controller Collection testing, extended profile/receipt-memory observation, and station-release/shelf-cleanup soak visible while the issue remains open.
- A graphical eight-player DataStore stress test, physical device test, transient amber screenshot, and forced-leave shelf log are not Phase 05 implementation blockers and are not claimed as passed.
- No production store was opened from Studio and no production DataStore rollout is claimed.

## Deferred by design

Phase 05 excludes daily challenges, starter missions, offline income, cosmetics/ownership/store, Robux products, monetization, trading, pets, rebirths, multiple worlds, co-op packing, cheer reactions, persistent/global/OrderedDataStore leaderboards, analytics, quests, final models, external assets, sound/music, final VFX, haptics, final Tape wrap, item power, functional mastery bonuses, rank bonuses, and every Phase 06 system.

## Phase 06 cross-reference

Phase 06 builds on this accepted persistence boundary by migrating the same stores to profile Schema Version 2, adding durable onboarding and five exact-once starter missions, extending the existing ProfileSnapshot, authoring contextual mission UI plus one narrowly validated skip remote, and observing authoritative transitions through server-only analytics adapters. It does not alter the Phase 05 receipt, lock, save, collection, shelf, or store-separation guarantees. See `docs/PHASE06_ONBOARDING_MISSIONS_ANALYTICS.md` for the current contract and `docs/DEVELOPMENT_STATUS.md` for fresh evidence.

## Exact next recommendation

Phase 05 is merged and protected. Continue Phase 06 only on its draft PR #7 branch, keep issue #4 open for explicitly deferred QA, and do not begin Phase 07 from this document.
