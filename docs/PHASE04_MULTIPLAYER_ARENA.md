# Phase 04 - Eight-Station Multiplayer Arena and Shared Shipment Showcase

Phase 04 converts the approved single-station vertical slice into an authored eight-station social packing arena while preserving the deterministic packing foundation, Phase 02 round authority, and Phase 03 responsive input contract.

## Current acceptance status

**Implementation complete and accepted.** The authored arena, station-generalized production architecture, concurrent isolation, shipment/showcase pipeline, one-shot overflow warning, displays, deterministic Studio tests, five-client Station_05 integration, final cleanup, normal cloud save, complete Studio close, and direct no-resynchronization reopen parity passed. Station_07 completion, the full cross-platform multiplayer matrix, physical-device coverage, and a visible 12-shipment soak remain unpassed extended QA in issue #4 and are not claimed here.

Phase 03 is merged through PR #3 at `014ff3964eb63f22f8527894067cddb1b4f98070`. Phase 04 is developed on `codex/phase-04-multiplayer-arena` in draft PR #5. Pre-release QA issue #4 remains open. `main` is unchanged and Phase 05 has not begun.

## Canonical ownership and authoring

`studio/phase02.manifest.json` remains the sole canonical permanent-instance manifest for the gameplay HUD, arena, all eight stations, six remotes, development templates, and Phase 02-04 scripts. Its filename is historical. There is no overlapping Phase 04 manifest.

`tools/build_phase02_blueprint.mjs` validates one complete Station_01 source descriptor plus eight ordered placement descriptors, then expands every station-owned path into eight explicit final managed operations. Expansion guarantees:

- exactly eight descriptors in stable `StationIndex` order;
- deterministic transforms and byte-stable output;
- parent-before-child creation;
- a complete hierarchy for every station;
- unique final managed paths;
- visible failure on wrong-class conflicts;
- no silent deletion;
- idempotent reapplication; and
- no runtime station cloning.

Permanent UI remains under `StarterGui` before Play. Permanent arena, station, display, dispatch, and path objects remain under `Workspace` before Play. Permanent network objects and templates remain under `ReplicatedStorage` before Play. Runtime creation is limited to temporary gameplay presentation and showcase clones.

## Arena hierarchy

The permanent arena is equivalent to:

```text
Workspace
`-- ONE_MORE_ITEM_WORLD
    `-- PlaytestArena
        |-- ArenaFloor
        |-- ArenaBackdrop
        |-- ArenaRails
        |-- SpectatorSpawn
        |-- CenterDispatch
        |   |-- Base
        |   |-- Lift
        |   |-- LiftTop
        |   |-- ShowcaseEntry
        |   |-- ArenaAnnouncement
        |   |   |-- BillboardGui
        |   |   |-- Headline
        |   |   `-- Detail
        |   `-- ServerBest
        |       |-- BillboardGui
        |       |-- PlayerName
        |       |-- ShipmentValue
        |       `-- ItemCount
        |-- ShowcaseLoop
        |   |-- PathNodes
        |   |   `-- Node_01 through Node_16
        |   `-- Runtime
        `-- Stations
            |-- Station_01
            |-- Station_02
            |-- Station_03
            |-- Station_04
            |-- Station_05
            |-- Station_06
            |-- Station_07
            `-- Station_08

ReplicatedStorage
`-- ONE_MORE_ITEM
    `-- Assets
        `-- Development
            `-- ShowcaseCrateTemplate
```

The center showcase path has 16 unique, indexed, anchored, invisible, non-colliding, non-touching, and non-queryable nodes on a 25-stud radius at Y=19. `ShowcaseLoop.Runtime` is authored empty. `ShowcaseCrateTemplate` contains the permanent crate shell and labels but no scripts.

## Station template and ring transforms

All stations share the same gameplay geometry. `StationRoot` is `18 x 1.5 x 24` studs, and each Model's local negative Z direction faces the arena center. Placement descriptors use a 38-stud radius and deterministic 45-degree intervals:

| Index | ID | Direction | World X | World Z | Yaw degrees |
| ---: | --- | --- | ---: | ---: | ---: |
| 1 | `station_01` | North | `0` | `-38` | `180` |
| 2 | `station_02` | North-east | `26.8701` | `-26.8701` | `135` |
| 3 | `station_03` | East | `38` | `0` | `90` |
| 4 | `station_04` | South-east | `26.8701` | `26.8701` | `45` |
| 5 | `station_05` | South | `0` | `38` | `0` |
| 6 | `station_06` | South-west | `-26.8701` | `26.8701` | `-45` |
| 7 | `station_07` | West | `-38` | `0` | `-90` |
| 8 | `station_08` | North-west | `-26.8701` | `-26.8701` | `-135` |

Each Model has unique `StationId` and `StationIndex` attributes plus `GridWidth=5`, `GridHeight=4`, `GridDepth=5`, `CellSize=2`, and `Active=true`. Every station includes:

- `StationRoot`, `PlayerStand`, `PresentationPoint`, and `DispatchPort`;
- `CameraAnchor`, `CameraAnchorTouchLandscape`, `CameraAnchorTouchPortrait`, and `CameraFocus`;
- the complete crate, `GridOrigin`, 25 permanent grid tiles, walls, lid, and `CrateFocus`;
- all four physical control-console buttons;
- owner name, station number, round state, and risk value display objects;
- a risk indicator Part and Light; and
- separate `PlacedItems` and `RuntimePresentation` folders.

Logical grid coordinates remain integer authoritative. Each station's authored `GridOrigin` supplies the world basis, so local X/Z rotate with the station and local Y remains vertical. The client never assumes a north-facing crate.

## Station definitions, discovery, and assignment

`Shared.World.StationDefinitions` exports the immutable ordered allowlist `station_01` through `station_08`, capacity eight, ID validation, and authored-Model resolution. It contains no mutable runtime ownership.

At server startup, `StationService` validates exactly eight active Models, all required station attributes, every required child path, unique IDs/indexes, exact definition order, and no unexpected active station. A malformed arena raises a visible error rather than silently omitting a station.

Assignment rules are server authoritative:

1. The first eligible player receives the lowest free `StationIndex`.
2. A player owns at most one station and a station has at most one owner.
3. The ninth and later eligible players enter one FIFO waiting queue.
4. Character respawn rebinds the current station and does not allocate again.
5. Removal releases the station and its temporary world state.
6. The oldest still-eligible waiter receives the exact released station and a fresh round snapshot.
7. A waiting client cannot place, decide, restart, or mutate an assigned station.
8. Clients never supply a desired StationId.

The public experience capacity was not changed during this phase. A current published `MaxPlayers` value has not yet been recorded in the acceptance evidence.

## Client station binding lifecycle

`StationContextController` owns only station-dependent client state. On an allowlisted authoritative assignment it resolves the authored Model, constructs `PlacementController` and `WorldMotionController` for that station, activates the station's responsive camera, and applies the existing reversible character-control lease.

On unassignment or reassignment it invalidates old callback epochs before destruction, clears fit/pending/grid observability, destroys the prior placement and motion controllers, clears temporary visuals/connections through those controllers, deactivates the camera, restores character controls, and then binds at most one new station. Shared responsive UI and input-mode state remain alive, while station-scoped pointer, touch, gamepad selection, ghost, camera, and placed-item references cannot leak into the next assignment.

A nil/empty assignment produces the waiting/spectator presentation. Station-dependent commands become no-ops, normal character controls return, the scripted station camera is inactive, and placement input is disabled. Production assignment logic contains no Station_01-only definition of ownership.

## Concurrent gameplay isolation

Each player has an independent authoritative round record containing station ID, round/version identity, occupancy grid, offer sequence, placement sequence, deadlines, placed-item presentation, unshipped value, result, and session-only Tape bank. Delayed callbacks carry the same player/round/version guards used by the Phase 02 state machine.

`PlacementService` derives station ownership from `StationService` and validates against that player's grid. `WorldItemService` tracks accepted Models by station and player and parents them only under the owned station's `PlacedItems`. Restart, timeout, failure, shipping, release, and service destruction clear the correct station without affecting neighbors.

The six-remotes surface remains unchanged:

- `ClientReadyRequest`
- `PlaceItemRequest`
- `DecisionRequest`
- `RestartRequest`
- `RoundSnapshot`
- `PlacementResponse`

No Phase 04 remote was added. Grid validity, placement, timers, next item, rewards, shipment capture, and station ownership remain server authoritative.

## Immutable ShipmentRecord

`ShipmentRecordService` captures only an authoritative successful round whose `PlayerUserId`, station, and placed-item count are internally consistent. The ID is `PlayerUserId:RoundId`; a repeated capture returns `DUPLICATE_SHIPMENT`.

The service deep-copies and freezes every placed-item presentation, freezes the array, and freezes the top-level record. A record contains:

- shipment, player, station, and round identity;
- sanitized player display name;
- item count, base-value sum, final ShipmentValue, and multiplier;
- copied item IDs, rotations, logical origins, and development colors;
- server creation time; and
- perfect-shipment status.

Showcase, announcement, and server-best consumers receive this read-only snapshot. They cannot change gameplay Tape or the original round.

## Shared showcase queue and rendering

`ShowcaseService` assigns each accepted record a monotonically increasing receipt sequence. Stable receipt order is the FIFO tie-breaker even for same-frame submissions.

Hard presentation limits are:

- `MAX_ACTIVE = 3`
- `MAX_PENDING = 16`
- `MAX_ITEM_PROXIES = 10` per active crate
- `PATH_NODE_COUNT = 16`
- `LAUNCH_SPACING = 1.25s`
- fixed update interval `1/30s`

Duplicate IDs are ignored. When the pending visual queue is full, only the newest cosmetic request is rejected as `QUEUE_FULL`; the authoritative shipment and Tape remain intact. `OverflowCount` increments for every rejection, while one exact concise warning is emitted only on the first overflow of a service lifetime. Production uses `warn`; deterministic tests inject a recorder so expected overflow does not pollute unrelated Output.

Each active record clones the authored script-free template into `ShowcaseLoop.Runtime`, writes the sanitized player/value/item labels, adds at most one coarse bounding-box proxy per packed item, and forces every BasePart anchored, non-colliding, non-touching, non-queryable, and massless. The model lifts from `ShowcaseEntry` for `0.60s`, traverses the loop for `9.0s`, exits/fades for `0.40s`, and is destroyed.

There is one shared conditional Heartbeat connection. It starts only when active visual work exists, advances all showcases at 30 Hz, stops when active work reaches zero, and resets its accumulator. Draining or destroying the service leaves `ShowcaseLoop.Runtime` empty and removes all temporary clones.

## Arena and station displays

`StationDisplayService` caches all eight permanent displays and updates them from authoritative owner/round events. Unowned stations show their station number and `AVAILABLE`. Assigned stations show the sanitized owner, packing/decision/shipping/failure/results status, and risk value. Risk colors are:

- fewer than six items: indicator off;
- six or seven items: amber;
- eight or nine items: red;
- ten items: gold with `IMPOSSIBLE SHIPMENT` presentation.

`ServerBestService` is server-session only. Higher ShipmentValue wins; ItemCount breaks value ties; a complete tie preserves the earlier shipment. Duplicate IDs do not change seen counts or the board.

`ArenaAnnouncementService` uses event priorities and epochs. High-risk milestones, large failures, perfect shipments, and new server bests cannot be overwritten by lower-priority messages before their guarded duration ends. All displayed player names pass through the shared sanitizer.

## Performance limits

The implementation has explicit worst-case bounds:

- Eight stations times ten accepted items gives at most 80 placed-item Models.
- Using the largest nine-cell development shape for every slot gives a conservative 720 detailed placed-item cell Parts.
- Three active showcase crates times seven template BaseParts plus ten item proxies gives at most 51 active showcase BaseParts.
- Sixteen pending showcase entries are immutable data records, not world Models.
- Showcase movement uses one shared 30 Hz loop and zero per-showcase/per-part frame connections.
- When showcase work drains, active Models, the update connection, and runtime children return to zero.

These are development-art limits, not final-device performance certification. Physical-device and lower-end-client profiling remains pre-release QA.

## Automated tests

### Local Node 24

All four dependency-free validations pass on the implementation head:

```text
[StudioSyncSmoke] PASS checks=16 folders=7 scripts=10 deterministic=true
[Phase02StudioSyncSmoke] PASS criteria=28 instances=616 scripts=45 remotes=6 deterministic=true phase01=true
[Phase03LayoutMatrix] PASS viewports=13 insetProfiles=5 cases=65 desktopCompatible=true safeContainment=true
[Phase03CrossPlatformSmoke] PASS criteria=31 viewports=13 insetProfiles=5 layoutCases=65 remotes=6 deterministic=true phase01=true phase02=true
[Phase04MultiplayerArena] PASS criteria=42 instances=616 scripts=45 stations=8 pathNodes=16 remotes=6 deterministic=true prior=true
```

The Phase 04 Node gate checks canonical ownership, eight explicit station Models and transforms, complete station contracts, permanent dispatch/path/template/display objects, strict source architecture, absence of Station_01-only production assignment, unchanged remotes, test runners, CI configuration, ignored generated/recovery files, and deterministic output.

### Fresh Studio Output

The latest clean baseline passed all suites with fixed seeds and zero failures:

```text
[ONE_MORE_ITEM][FoundationTests] RESULT suites=15 tests=69 passed=69 failed=0 duration=0.406397s fuzzCases=1000 fuzzSeed=24012026
[ONE_MORE_ITEM][Phase02Tests] RESULT suites=11 tests=94 passed=94 failed=0 duration=10.126511s seed=24022026
[ONE_MORE_ITEM][Phase03Tests] RESULT suites=8 tests=65 passed=65 failed=0 duration=0.006501s seed=13072026
[ONE_MORE_ITEM][Phase04Tests] RESULT suites=13 tests=119 passed=119 failed=0 duration=0.932559s seed=14072026
```

After the direct no-sync reopen, all four suites passed again: Foundation `69/69`, Phase 02 `94/94`, Phase 03 `65/65`, and Phase 04 `119/119`.

Phase 04 coverage includes exact authored discovery and missing-path failures, all eight rotated grid bases/cameras, Station_01-to-Station_05 rebind transforms, first-eight allocation, ninth-player waiting, release/FIFO promotion, respawn, persistent input identity, all-station client binding and cleanup, invalid/spectator assignment, eight simultaneous station-scoped rounds, isolated restart/same-frame shipping/same-frame failure/stale timers, promoted-owner world cleanup, exact immutable shipment copies without Player references, same-frame FIFO order, bounded overflow with one exact warning, 12-shipment drain stress, server-best survival after leave, ordinary shipping/risk displays, announcements, and cleanup baselines.

## Studio synchronization evidence

The latest Phase 02-04 blueprint contains 616 non-script authored instances and 45 scripts, for 661 operations. Both final Phase 02-04 synchronization passes reported:

```text
Created=0 Updated=661 Skipped=0 Failed=0
```

The combined Phase 01 plus Phase 02-04 canonical target is 672 managed paths: 617 non-script paths and 55 Luau sources. Before saving, five untruncated live roots totaled exactly 672 nodes/55 scripts, the eight stations and 16 path nodes were present, all six remotes were exact, and every live source matched its canonical UTF-8 SHA-256 value. The direct no-sync reopen passed the same `672/672` managed-path and `55/55` exact-source parity, with eight stations, 25 authored grid tiles per station, 16 path nodes, six remotes, and zero duplicate or wrong-class managed paths.

## Current live acceptance evidence

| Gate | Current result |
| --- | --- |
| Play Solo | **Passed for the recorded flow.** Station_01 shipped a valid item for `+15 TAPE`, reached Results, used Pack Again, later exercised failure, and returned showcase runtime to zero. |
| Rotated stations | **Accepted evidence complete for Station_03 and Station_05.** The earlier Station_03 shipment/One More/failure evidence remains valid, and the final five-client integration completed the legitimate Station_05 flow and cleanup. Station_07 completion remains unpassed extended QA. |
| Multiplayer integration | **Passed.** The earlier four-client unique-assignment and Station_02 release/replacement evidence was followed by a verified five-client Station_05 flow. Integrated shipment receipts remained unique, and the first tied best remained `-5:4` at value `15` with item count `1`. |
| Cross-platform multiplayer | **Deferred extended QA; not claimed as passed.** Phase 03 deterministic input/layout coverage remains green, but the full Phase 04 desktop/touch/gamepad multiplayer matrix remains open in issue #4. |
| Eight-session deterministic concurrency | **Passed in automated Studio tests.** Eight players start eight station-scoped rounds; a ninth waits; release/FIFO reassignment and isolation pass. |
| Eight-client graphical attempt | **Attempted.** Eight graphical sessions held unique Station_01 through Station_08 assignments; users five through eight occupied Station_05 through Station_08, Station_05/07 views were inspected, no crash was observed, and all sessions ended cleanly. This does not replace the missing prescribed action matrix. |
| Showcase stress | **Deterministic test passed; visible 12-shipment soak remains unpassed extended QA.** No visible 12-shipment soak is claimed. |
| Runtime cleanup | **Passed.** Final integrated observability was `Runtime=0 Active=0 Pending=0 Overflow=0 Loop=false`, and Station_05 cleanup completed. |
| Fresh Output | **Passed.** Fresh game-owned warning and error counts were both zero after the integrated flow and cleanup. |

Phase 04 implementation acceptance is complete; deferred extended-QA rows remain open in issue #4 and are intentionally not represented as passed.

## Cloud persistence

An external recovery copy was created outside Git and verified at 181,936 bytes. An earlier Team Create HTTP 500 and the first post-update login interruption were superseded: after the final double synchronization and green test run, Studio reported `Saved new changes in "ONE MORE ITEM!" to Roblox.`, every Studio process was closed, and the original private place reopened directly from Roblox without repository resynchronization.

The reopened place passed `672/672` managed paths, comprising 617 non-script instances and 55 scripts; `55/55` exact canonical sources; eight permanent stations with 25 authored grid tiles each; 16 showcase path nodes; exactly six remotes; and zero duplicate or wrong-class managed paths. Foundation `69/69`, Phase 02 `94/94`, Phase 03 `65/65`, and Phase 04 `119/119` passed again. The verified five-client Station_05 integration then completed with unique shipment receipts, first tied best `-5:4` at value `15` and item count `1`, final `Runtime=0 Active=0 Pending=0 Overflow=0 Loop=false`, and zero fresh game-owned warnings/errors.

## Known limitations and deferred pre-release QA

- Station_07 completion remains unpassed extended QA; no Station_07 completion claim is made.
- The full desktop/touch/gamepad Phase 04 multiplayer matrix remains unpassed extended QA; no physical-device result is claimed.
- The deterministic 12-shipment stress contract passes, but a visible 12-shipment soak remains unpassed extended QA.
- Documentation head `1d3069bd142d3dbae7d0b59609f6a14fb52eefc9` passed branch-push run `29364520534` / job `87192644103` and draft-PR run `29364523993` / job `87192655613`, with every individual step successful. The containing status-only commit's own runs are reported in PR #5 and the final handoff.
- Phase 04 cloud save, complete close, direct no-sync reopen, and post-reopen parity passed.
- Current published `MaxPlayers` has not been recorded; public experience settings were not changed.
- Physical phone/controller and lower-end-device performance checks remain pre-release QA in issue #4.
- The arena uses polished geometric development art, not final assets.

## Deferred by design

Phase 04 deliberately excludes persistent Tape, DataStores, packing XP, ranks, collection, object mastery, daily challenges, starter missions, cosmetics, store/monetization, trading, pets, rebirths, multiple worlds, co-op packing, cheer reactions, global/cross-server leaderboards, analytics, quests, final object models, external models, sound, music, final particles, final Tape-wrap presentation, driving, delivery gameplay, camera orbit, haptics, and every Phase 05 system.

## Exact next recommendation

The next recommended phase is Phase 05, but do not begin it in this task. First review and merge draft PR #5 through a separate authorized action; keep issue #4 open for the explicitly deferred extended QA and leave `main` unchanged until that review.
