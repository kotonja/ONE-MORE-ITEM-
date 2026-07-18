# Project architecture

## Coordinates and shapes

The crate uses zero-based integer coordinates: X is left/right, Y is vertical, and Z is front/back. Valid default cells are X `0..4`, Y `0..3`, and Z `0..4`.

A shape is an ID plus a list of unique integer `{X, Y, Z}` cells. Normalization translates every cell so the minimum coordinate on every axis is zero, then sorts cells lexicographically by X, Y, Z. The canonical key joins that sorted representation, making equality independent of input order.

Y-axis rotation applies integer quarter turns, normalizes after rotation, and removes rotations with duplicate canonical keys. Rotation never consults world transforms.

## Occupancy grid

`OccupancyGrid` stores occupied cells in a private key set keyed as `x:y:z`. Public methods validate bounds and collision, apply an already validated placement atomically, clone the grid without sharing state, count occupied cells, and return a fill ratio in `[0, 1]`.

The configured grid is 5 × 5 × 4, but construction accepts explicit positive integer dimensions so the foundation remains testable.

## Finite-integer validation

Grid-facing integers pass one shared runtime rule: the value must have type `number`, equal itself so NaN is rejected, be strictly between negative and positive infinity, and have no fractional component. The check remains small and independent of game policy.

Public boundaries apply policy-specific behavior after that shared check:

- Invalid shape coordinates and invalid quarter turns raise clear validation errors.
- Invalid grid dimensions raise a positive-finite-integer error.
- Malformed or non-finite cell coordinates make `IsInsideBounds` and `CanOccupyCells` return `false` before an occupancy key is formatted.
- Invalid or non-finite solver X/Z requests return `nil` before arithmetic or placement-key formatting.
- Invalid, negative, fractional, NaN, infinite, or non-number difficulty counts raise a non-negative-finite-integer error.

## Auto-drop and enumeration

For a rotation and X/Z origin, auto-drop begins at the highest Y where the complete shape fits within the box. If the item cannot occupy that entry layer, no placement exists. Otherwise the rigid item descends one integer layer at a time and rests immediately before the next move would hit the floor or an occupied cell. This preserves bridging/overhang while preventing teleportation through upper obstructions.

Legal placements enumerate in deterministic order:

1. Unique rotation index
2. X origin ascending
3. Z origin ascending
4. Resting Y (determined by auto-drop)

Placement keys include the shape ID, canonical rotation key, and integer origin. They support deduplication, future server validation, tests, and analytics without unordered table iteration.

## Difficulty

Thresholds are centralized in `GameConfig`: 10+ placements is Easy, 4–9 is Tight, 1–3 is Brutal, and 0 is Impossible. Impossible candidates are not offerable.

## Public modules

- `GameConfig`: immutable dimensions, thresholds, item limit, and development flags.
- `GridTypes`: shared strict types for cells, shapes, rotations, placements, and solver-facing grid contracts.
- `ShapeRotation`: validation, normalization, Y rotation, canonical keys, and unique rotations.
- `OccupancyGrid`: bounds/collision checks, atomic application, cloning, and accounting.
- `PlacementSolver`: complete validation, top-entry auto-drop, deterministic enumeration, and offerability.
- `DifficultyClassifier`: configured placement-count classification.
- `ShapeDefinitions`: immutable development-only shape data with no visual dependency.

World-space physics is not authoritative because floating-point contacts and replication are unsuitable for deterministic packing validation. Future visuals will derive transforms from accepted integer placements.

## Edit-mode hierarchy synchronization

`tools/build_studio_blueprint.mjs` validates the complete Studio manifest and loads every canonical source before writing either generated artifact. Validation covers supported service roots, nonempty paths, unique folder/script paths, cross-kind collisions, valid managed parents, supported script classes, source existence, and real-path containment inside the repository.

Folder paths are ordered parent-first with a stable code-unit comparison. Every generated `ensureFolder` operation precedes every `writeScript` operation. Correct existing instances are reused or updated; missing instances are created; and a missing parent or wrong-class conflict fails visibly without deleting content. New `Script` instances remain disabled while Source and parenting are prepared and are restored to their manifest-enabled state only after a successful write. `ModuleScript` instances have no enabled state.

Running the complete generated list repeatedly is idempotent. Generated blueprint and Command Bar JSON are byte-deterministic, ignored artifacts; `src/`, `studio/phase01.manifest.json`, and the tools remain authoritative. This workflow is Edit-mode authoring only and never creates the permanent hierarchy at runtime.

## Phase 02 permanent-instance authoring

Phase 02 extends the dependency-free manifest workflow across `Workspace`, `StarterGui`, `ReplicatedStorage`, `ServerScriptService`, and `StarterPlayer`. Its typed schema covers booleans, numbers, strings, enum items, colors, vectors, dimensions, and transforms. Parent instances are emitted before children, correct instances are reused, managed properties and attributes are updated, and wrong-class conflicts fail without deletion. `StarterPlayer.StarterPlayerScripts` is a declared built-in parent rather than a replaceable folder.

Permanent station geometry, HUD surfaces, `RemoteEvent` instances, and the development cell template are therefore present in Edit mode. Runtime code is structurally unable to substitute a map or `ScreenGui` builder; it may create only temporary ghosts, proxy item cells, placed-item visuals, viewport contents, highlights, and short-lived presentation effects.

## Phase 02 authority and round loop

`StationService` discovers authored stations and enforces exclusive ownership. `RoundService` owns the seven-state round machine, round/version identity, deadlines, current/preview items, occupancy, shipment totals, session bank, and stale-callback guards. `PlacementService` validates the complete placement request against the Phase 01 integer solver before applying once. `SequenceService` deterministically filters impossible candidates and preserves offer fairness. `WorldItemService` renders accepted cells from the authored development template, and `RequestRateLimiter` protects the four client request surfaces.

The client receives copied presentation snapshots and predicts only ghost validity, input response, camera, UI, and motion. It never chooses the next item, commits occupancy, grants Tape, or decides timeout/shipping outcomes.

## Phase 02 client presentation

The client bootstrap composes focused controllers for round snapshots, camera, character controls, desktop input, ghost placement, HUD state, viewport previews, and physical-world motion. Controllers bind existing authored paths and clean their temporary children/connections on state changes. The stable camera and grid-to-world transform derive from authored anchors and Phase 01 integer coordinates rather than physical contacts.

The full hierarchy, network contracts, timings, development items, and test flow are documented in `docs/PHASE02_VERTICAL_SLICE.md`.

## Phase 03 permanent responsive authoring

The historically named `studio/phase02.manifest.json` remains the sole owner of the permanent vertical-slice paths. Phase 03 extends it with the transparent `TouchDragSurface`, five authored focus strokes, five authored compact-action constraints, and two invisible responsive camera anchors. It does not create a second overlapping manifest.

`ONE_MORE_ITEM_Gameplay` is authored with `ScreenInsets = DeviceSafeInsets`, `ClipToDeviceSafeArea = true`, `SafeAreaCompatibility = None`, and `IgnoreGuiInset = true`. Permanent UI remains present under `StarterGui` before Play. Runtime may resize, reposition, relabel, reveal, and animate those objects, but it cannot create a replacement ScreenGui, permanent controls, or focus outlines.

The touch-landscape and portrait camera anchors are real Parts under `Station_01`. Like the original camera anchor, they are anchored, invisible, non-colliding, non-queryable, non-touching, script-free, and source controlled.

## Phase 03 input architecture

`InputModeStore` maps `UserInputService.PreferredInput` to exactly `KeyboardMouse`, `Touch`, or `Gamepad`. It deduplicates repeated modes and owns listener cleanup. Input mode is local presentation state; it never chooses a permanent device class or mutates authoritative round state.

`InputController` coordinates the focused implementations:

- `ResponsiveLayout` is pure deterministic geometry over viewport size and safe insets.
- `ResponsiveUIController` applies geometry to authored panels/buttons and retargets layout tweens.
- `TouchInputController` owns one active placement touch and emits only local pointer rays.
- `GamepadInputController` owns high-priority action bindings, fixed-clock cell repeat, and safe GUI selection.
- `InputPromptController` updates authored text and strokes for the active mode.

Keyboard/mouse, touch, and gamepad feed the same local `PlacementController` ghost. Place, Ship/One More, and Pack Again are routed to the existing `PlaceItemRequest`, `DecisionRequest`, and `RestartRequest` families. Pointer rays, touch/stick positions, movement, rotation, input mode, layout, camera, focus, and ghost state never cross the network. The six Phase 02 remotes and all server validation remain unchanged.

## Phase 03 responsive geometry and camera

Layout classification uses the safe usable aspect ratio independently of input: below `1.10` is `Portrait`; below `1.45`, or a usable height no greater than 500 pixels, is `CompactLandscape`; larger landscape viewports are `Wide`. Targets use scale-only `UDim2` values. `Wide` retains the exact approved Phase 02 geometry, while compact and portrait profiles enlarge primary actions and reposition authored panels inside Roblox-reported safe areas.

Initial geometry applies immediately. A viewport change cancels and retargets independent AnchorPoint, Position, and Size tweens over `0.25s` with Quart Out so controller-owned visibility and count transitions are not replaced by competing geometry tweens.

`CameraController` uses `CameraAnchor` for Wide and non-touch compact layouts, `CameraAnchorTouchLandscape` for compact touch, and `CameraAnchorTouchPortrait` for every portrait mode. Initial assignment retains the `0.60s` arrival; later target changes use a `0.25s` retarget. Impulse epochs prevent a placement, shipping, or failure settle from returning to an obsolete responsive target.

## Phase 03 character-control lease

An assigned client leases PlayerModule controls and suppresses movement/jump with high-priority ContextActionService fallbacks. It records whether controls were enabled and the exact prior Humanoid `AutoRotate` value. Unassignment or destruction restores only state changed by the lease. Respawn and late Humanoid replacement reapply suppression while assignment remains active. Spectators retain ordinary controls.

The complete mappings, responsive matrix, safe-area contract, tests, verified evidence, and pending acceptance gates are documented in `docs/PHASE03_CROSS_PLATFORM.md`.

## Phase 04 permanent arena authoring

The historically named `studio/phase02.manifest.json` remains the sole canonical owner of every Phase 02-05 permanent path. Its `stationPlacements` array defines eight ordered descriptors. `tools/build_phase02_blueprint.mjs` validates that exact order and expands the complete Station_01 subtree into eight explicit, independently auditable final station paths. Expansion is deterministic, parent-first, idempotent, and conflict safe; it never clones stations at runtime and never silently replaces a wrong-class object.

Stations occupy a 38-stud ring at 45-degree intervals. Their local negative Z axis points toward the arena center. The authored transforms are:

| Station | Direction | X | Z | Yaw |
| --- | --- | ---: | ---: | ---: |
| `station_01` | North | `0` | `-38` | `180` |
| `station_02` | North-east | `26.8701` | `-26.8701` | `135` |
| `station_03` | East | `38` | `0` | `90` |
| `station_04` | South-east | `26.8701` | `26.8701` | `45` |
| `station_05` | South | `0` | `38` | `0` |
| `station_06` | South-west | `-26.8701` | `26.8701` | `-45` |
| `station_07` | West | `-38` | `0` | `-90` |
| `station_08` | North-west | `-26.8701` | `-26.8701` | `-135` |

Every station carries a unique `StationId`/`StationIndex`, the same `5 x 5 x 4` integer grid with two-stud cells, all three responsive camera anchors, the complete crate/console/owner/risk contract, and separate `PlacedItems` and `RuntimePresentation` containers. `GridWorldTransform` composes each authored `GridOrigin` transform with logical integer offsets, so station yaw changes presentation without changing placement authority.

The center arena is also permanent Edit-mode content: `CenterDispatch` contains the lift, entry, arena announcement, and server-best display; `ShowcaseLoop.PathNodes` contains exactly 16 indexed, non-physical path Parts on a 25-stud radius at height 19; and `ReplicatedStorage.ONE_MORE_ITEM.Assets.Development.ShowcaseCrateTemplate` is a script-free source template. `ShowcaseLoop.Runtime` is the empty destination for temporary server clones.

## Phase 04 station registry and assignment

`StationDefinitions` is the immutable allowlist and deterministic order for `station_01` through `station_08`. At startup, `StationService` discovers the authored Models, validates attributes and required direct/descendant paths, rejects duplicate IDs/indexes and unexpected active Models, sorts by index, and requires exactly eight valid stations before gameplay begins.

Assignment is server authoritative. The first eight eligible players receive the lowest free indexes. Additional players enter one FIFO waiting list in join order. Removal releases ownership and station-scoped world state; the oldest still-eligible waiter receives the exact released station and a fresh authoritative snapshot. Respawn rebinds the existing owner to the same `PlayerStand` rather than allocating a new station. No client request contains or chooses station ownership.

## Phase 04 client station lifecycle

`StationContextController` resolves only allowlisted snapshot station IDs. Binding constructs one station-scoped placement controller and world-motion controller, activates the station's responsive camera anchors, and applies the reversible character-control lease. Unbinding invalidates callback epochs first, clears fit/pending/observability state, destroys station-scoped controllers, deactivates the camera, restores character controls, and leaves the shared round UI/input-mode controller intact. Reassignment always unbinds before resolving and binding the new authored Model, preventing old camera, ghost, placed-item, pointer, touch, or gamepad state from leaking.

A nil, empty, or invalid station assignment enters waiting/spectator behavior: station-dependent placement calls become no-ops, the station camera is inactive, character controls are restored, touch placement is disabled, and gamepad selection is cleared by the coordinating input layer. Production assignment does not special-case `station_01`.

## Phase 04 concurrent round isolation

`RoundService` continues to own authoritative state, but each player record carries its validated station ID and an independent occupancy grid, round/version identity, deadlines, sequence state, placed-item presentation, shipment value, and session-only Tape bank. `PlacementService` resolves the calling player's owned station; `WorldItemService` tracks temporary accepted-item Models by station and player and parents them only under that station's `PlacedItems` folder. Restart, failure, shipping, release, and destruction clear only the affected station. One player's input cannot name or mutate another station.

The network surface remains the same six authored Phase 02 RemoteEvents. Station assignment travels only in server snapshots; no Phase 04 remote, client-authored placement result, or persistent progression channel was added.

## Phase 04 shipment and showcase pipeline

`ShipmentRecordService` captures a successful authoritative round once using `PlayerUserId:RoundId` as the shipment ID. It verifies player/round ownership, station presence, and placed-item count, then deep-copies and freezes every placed-item presentation and the record. The immutable record contains display-safe player identity, station/round IDs, item/value/multiplier totals, copied placed items, creation time, and perfect-shipment status. Duplicate capture is rejected before any presentation consumer runs.

`ShowcaseService` consumes records independently of reward authority. Accepted records receive monotonically increasing receipt sequences and enter a stable FIFO queue. At most three showcases are active and at most sixteen are pending; a seventeenth pending cosmetic request is rejected without modifying the gameplay shipment. Launches are spaced by 1.25 seconds. Each clone is non-colliding, non-touching, non-queryable, anchored, and script-free, and contains at most ten coarse item bounding-box proxies.

The overflow path records `OverflowCount`, returns `QUEUE_FULL`, and emits exactly one concise Studio warning per service lifetime. The warning sink is injectable for deterministic tests; the production default uses `warn`. Repeated overflow cannot spam Output and cannot change the authoritative shipment or Tape.

One conditional Heartbeat connection accumulates fixed `1/30`-second steps while showcases are active. Each model lifts for `0.60s`, follows the 16-node loop for `9.0s`, exits/fades over `0.40s`, and is destroyed. When the active set drains, the connection stops and `ShowcaseLoop.Runtime` returns to zero children. Destroying the service disconnects the loop, clears pending state, and removes all temporary models.

`ServerBestService` is session-only and deduplicates shipment IDs. Higher ShipmentValue wins; ItemCount breaks value ties; an exact tie preserves the earlier record. `StationDisplayService` sanitizes owner names, exposes round state and risk value, and uses amber at six items, red at eight, and gold at ten. `ArenaAnnouncementService` applies priority/epoch guards so a lower-priority event cannot overwrite an active higher-priority high-risk, failure, perfect-shipment, or server-best message.

## Phase 04 performance boundaries

- Eight stations can hold at most 80 accepted item Models at the ten-item round cap. Using the largest nine-cell development shape as a conservative upper bound gives 720 detailed placed-item cell Parts across the arena.
- The showcase holds at most three active clones. The authored crate contributes seven BaseParts and each clone adds at most ten item proxies, for a conservative maximum of 51 active showcase BaseParts.
- Pending showcase records are data only and are capped at sixteen.
- Showcase motion uses one shared 30 Hz update connection only while active; it does not create per-part or per-player frame loops.
- Completed, failed, restarted, released, and drained state is explicitly destroyed so temporary runtime containers return to baseline.

The complete hierarchy, operational limits, tests, current live evidence, and unfinished acceptance gates are documented in `docs/PHASE04_MULTIPLAYER_ARENA.md`.

## Phase 05 profile ownership boundary

Phase 05 replaces the Phase 04 session-only wallet with a server-owned Version 1 profile. `ProfileService` owns loaded profile tables, lifecycle, dirty revisions, lock ownership, one shared due-save scheduler, copied snapshots, bounded release, and shutdown. `ProgressionService` is a separate deterministic mutation boundary; it calculates rewards and never calls a DataStore. `RoundService` keeps round authority but asks progression to commit the outcome before publishing cosmetic shipment events. `CollectionShelfService` reads copied profile state and station ownership but contains no persistence logic.

This dependency direction prevents circular ownership:

```text
DataStoreProfileAdapter / MemoryProfileAdapter
                    |
              ProfileService
                    |
           ProgressionService
                    |
              RoundService

StationService -> ServerBootstrap coordination <- CollectionShelfService
```

Client profile presentation is similarly separate. `ClientProfileStore` accepts only copied `ProfileSnapshot` values and is not merged into `ClientRoundStore`. `ProfileUIController` correlates round and reward presentation by server-created OutcomeId without delaying or changing gameplay.

## Phase 05 schema, stores, and locking

The canonical profile persists only schema version, Tape, Packing XP, statistics, collection discovery/mastery/recent IDs, the bounded processed-outcome list, timestamps, and an optional server session. Rank, progress percentages, content display properties, world/grid/round state, and UI state are derived or transient.

Non-Studio servers are configured to select `ONE_MORE_ITEM_PlayerProfiles_v1`; normal Studio persistence selects `ONE_MORE_ITEM_PlayerProfiles_StudioTest_v1`; deterministic tests inject `MemoryProfileAdapter`. No production-store test or rollout is claimed. `DataStoreProfileAdapter` is server-only and uses guarded `UpdateAsync` transforms for claim, save, heartbeat, and release. Transforms are synchronous non-yielding table operations; retry, request-budget waiting, and backoff occur outside them. `ProfileSchema` deep-copies and deterministically migrates nil, documented Version 0, or Version 1 data and rejects future versions.

One identifier is created per server process, and each loaded player receives one secret lock token. A 60-second-or-less heartbeat and 180-second stale timeout govern ownership. Load may claim no lock, refresh the identical token, or take over a stale lock. Save/release verify the exact token. Losing ownership transitions the profile to Conflict and blocks further rewards rather than overwriting another server. Lock tokens and heartbeat metadata never replicate.

## Phase 05 progression and receipts

Every round creates `{UserId}:{ServerSessionId}:{RoundId}` at start. The same OutcomeId identifies its one possible successful or failed progression result. The profile retains at most 128 processed IDs; a duplicate returns an explicit zero-delta result, so Tape, XP, discovery, mastery, and statistics cannot be applied twice.

Successful progression adds ShipmentValue Tape, formula-derived XP, discovery in immutable shipment order, one mastery count per shipped occurrence, and all shipment statistics. Failure adds only bounded consolation XP and the failed-round statistic. Every placed-item ID is validated before mutation, making the in-memory change atomic. Rank and mastery tiers are derived from strict shared definitions. Shelf/showcase presentation runs only after the authoritative mutation and cannot undo it.

## Phase 05 load, save, and assignment lifecycle

Player startup is join -> Loading -> Ready -> station assignment or FIFO waiting -> round. ClientReady may precede or follow load; neither condition assigns alone. Loading, Unavailable, and Conflict profiles cannot consume a station or enter reward-bearing gameplay. Waiting snapshots use a per-player monotonic `StateVersion`, so Loading, queued Ready, and Unavailable transitions at `RoundId=0` cannot be rejected as stale by the client store.

One shared scheduler coalesces dirty mutations using a five-second debounce, catches them on a 60-second autosave interval, performs heartbeats, and caps simultaneous saves at eight. A captured save revision clears dirty state only if no newer mutation arrived. Failed owned writes become SaveDelayed and remain dirty for bounded retry; ownership loss becomes Conflict. Player removal closes mutation and releases round/station/shelf before the slow store path. `BindToClose` runs bounded concurrent final save/release work within a 25-second deadline.

## Phase 05 Studio-only failure acceptance fixture

The acceptance fixture is disabled by default and can run only when `RunService:IsStudio()` is true. It reads three attributes from `ServerScriptService.ONE_MORE_ITEM_Server`: `ONE_MORE_ITEM_Phase05AcceptanceMode`, optional `ONE_MORE_ITEM_Phase05AcceptanceTargetUserId`, and `ONE_MORE_ITEM_Phase05AcceptanceExpiresAt`. The only allowed modes are `Unavailable`, `SaveDelayed`, and `Conflict`; expiry must be a finite integer later than the current time and no more than 600 seconds ahead. An invalid or expired arming request is rejected.

A valid fixture replaces the storage adapter for the entire test server with one `MemoryProfileAdapter`; the optional target only chooses which player receives the injected failure. This prevents any controlled outage or conflict test from touching the Studio-test or production store. The three attributes must be absent before every normal Studio-test persistence run, cloud save, or cloud reopen, and the place must never be saved or published while the fixture is armed. Fixture logs validate failure behavior, but cannot substitute for real Session A/B Studio-test-store persistence.

## Phase 05 permanent UI, networking, and shelves

The six gameplay remotes remain unchanged. `ReplicatedStorage.ONE_MORE_ITEM.ProfileNet.ProfileSnapshot` is a separate permanent server-to-client event with no mutation counterpart. Its presentation-safe session ID and monotonic revision let the client reject stale/duplicate snapshots while allowing a new profile presentation session. The snapshot exposes derived/copied Tape, XP, rank, collection, statistics, lifecycle, save state, and last reward, never receipts, lock data, keys, or internal tables.

The canonical manifest permanently authors MetaBar, DataStatus, CollectionPanel with eight complete slots, DiscoveryReveal, RankUpBanner, Results additions, eight six-slot station shelves, and one script-free shelf proxy template. Runtime creates only temporary previews and at most six proxy Parts per shelf. Shelf selection is deterministic: up to three newest valid discoveries, then mastery tier, mastery count, and catalog order. Clear-before-render and station-scoped ownership prevent one player inheriting another player's display.

The detailed contracts, exact formulas and thresholds, completed deterministic and Studio-test persistence evidence, accepted cloud close/reopen proof, and explicitly deferred physical-device/production checks are documented in `docs/PHASE05_PERSISTENT_PROGRESSION.md`.

## Phase 06 schema and retention boundaries

Phase 06 advances the in-profile schema to Version 2 without changing either store namespace. `ProfileSchema` explicitly migrates Version 1 through an input-immutable, non-yielding boundary, preserves every existing persistent value and session owner, and normalizes the new onboarding and starter-mission state from shared canonical definitions. Unsupported future versions still reject. Current round state, input mode, UI state, analytics records, and presentation queues are never persisted.

`OnboardingService` and `StarterMissionService` are focused server-owned mutation boundaries above `ProfileService`. Onboarding accepts only monotonic authoritative step transitions or a narrowly validated persistent skip. Starter missions consume only server-created placement, decision, shipment, and reconciliation events; one profile draft applies progress, exact-once rewards, Tape/XP/statistics, and rank transitions atomically. The rewarded mission map is canonical truth, so duplicate callbacks and reconciliation cannot grant twice.

```text
authoritative round/station/profile events
                 |
       OnboardingService   StarterMissionService
                 \         /
                   ProfileService
                         |
              ProfileSnapshot V2
```

Guided timing is captured once when a round is created from the durable onboarding status. That round keeps its original deadline even if onboarding completes or is skipped mid-round; only later rounds switch back to the normal timing. The snapshot exposes only copied onboarding/mission presentation data plus a bounded ephemeral mission-reward batch. Save-state snapshots may repeat that batch, so the client deduplicates deterministic RewardIds within one presentation session.

## Phase 06 server-only analytics

`GameAnalyticsService` is a best-effort observer with no gameplay or profile authority. Studio and deterministic tests select `MemoryAnalyticsAdapter`; published non-Studio servers select `RobloxAnalyticsAdapter`. The Roblox adapter wraps every current AnalyticsService log call in `pcall`, while the memory adapter deep-copies bounded records for deterministic ordering and failure-injection assertions. Analytics runs only after the corresponding authoritative mutation and snapshot, and failure cannot roll back progression, block assignment/saving, or suppress round/showcase presentation.

The event catalog is fixed. Onboarding funnel names come from `OnboardingDefinitions`; core-loop, One More, starter-mission, skip, and session events accept only allowlisted bounded fields. Tape economy events use authoritative deltas and ending balances, while StarterPath progression uses canonical mission indexes/names. Event names are never built from player, round, station, outcome, or item identifiers, and custom fields exclude personal/session/store data.

## Phase 06 authored UI and client input ownership

The existing Phase 02 manifest permanently authors the onboarding overlay, skip control/progress, compact starter card, full five-row starter path, mission-complete banner, and the sole new request remote `OnboardingNet.OnboardingActionRequest`. Runtime controllers bind and animate those instances but never create permanent UI or mission rows. The existing gameplay Net remains six remotes, and the existing ProfileNet remains one server-to-client snapshot remote.

`OnboardingUIController` combines copied profile state, ordinary round state, local fit state, and current input mode for contextual presentation only. `StarterMissionUIController` reads snapshot mission state, gates the full panel to non-active round states, and queues unseen RewardIds. Named client modal blockers allow Collection and Starter Path surfaces to suppress underlying keyboard, touch, and gamepad actions without racing one another. Responsive geometry continues to use Wide, CompactLandscape, and Portrait safe-area targets with scale-only authored coordinates.

The full Phase 06 contracts and acceptance evidence are recorded in `docs/PHASE06_ONBOARDING_MISSIONS_ANALYTICS.md` and `docs/DEVELOPMENT_STATUS.md`.

## Phase 07 permanent presentation ownership

The historically named `studio/phase02.manifest.json` remains the sole canonical owner for Phase 02 through Phase 07 permanent content. Phase 07 extends the supported managed roots to `ReplicatedFirst` and `Lighting` while retaining `Workspace`, `StarterGui`, `ReplicatedStorage`, `ServerScriptService`, and children below the built-in `StarterPlayer.StarterPlayerScripts`. It does not add a competing manifest or a runtime world/UI builder.

Permanent first-frame and gameplay curtains, camera anchors, station/crate/console geometry, arena shell, center dispatch, showcase supports, signs, UI, lighting, post-processing, remotes, templates, and mapped scripts exist before Play. The builder remains parent-first, deterministic, idempotent, and conflict safe. Correct paths are reused, missing paths are authored, and wrong-class conflicts fail without deletion. Runtime creation remains limited to temporary ghosts, placed-item proxies, showcase clones, shelf proxies, and short-lived presentation effects cloned or derived from prepared content.

Phase 07 presentation work has no authority over integer placement, round transitions, station ownership, rewards, persistence, missions, or analytics. The gameplay `Net` remains six remotes, `ProfileNet` remains one server-to-client snapshot remote, and `OnboardingNet` remains the one narrowly validated skip request remote.

## Phase 07 visual definitions and first-frame handoff

`VisualThemeDefinitions` centralizes semantic environment, text, and state colors. Green and red are state-only, amber is shipping/reward, purple is collection/mastery, and cyan is navigation/station identity. `VisualFraming` is a pure module for safe-viewport rectangles, projection, world bounds, crate/console rectangles, pitch, occupancy ratios, and line-of-sight samples; it performs no instance search.

`ReplicatedFirst.ONE_MORE_ITEM_FirstFrame.FirstFrameBootstrap` immediately owns an authored opaque first-frame curtain and keeps it mounted through a bounded minimum hold. `FirstFrameHandoffPolicy` coordinates its covered handoff to the authored `StarterGui` curtain only after the canonical curtain reports a safe Scriptable camera, without revealing raw sky, a default character camera, or uninitialized station geometry. `ArrivalCurtainController` then presents honest Loading, Unavailable, Conflict, assigned Ready, or waiting Ready states and reveals the world only after the selected station camera is safe. These controllers send no server request and retain no permanent frame loop; cancellation and destruction clean tweens and connections.

## Phase 07 station framing and local presentation

The logical crate stays `5 x 5 x 4` with two-stud cells. Authored responsive camera anchors target a `48-52` degree FOV, roughly `50-58` degrees downward pitch, and deterministic screen occupancy. Line-of-sight fixtures sample every layer-zero cell, upper corners, `CrateFocus`, `GridOrigin`, and the ghost. The low front rim, low console, stand, signs, shelf, neighbor stations, shell, and dispatch may not obstruct those rays; only compliant non-refractive side/rear panes may intersect them.

`CameraController` binds the appropriate authored station anchor and maintains epoch-guarded local arrival/retarget/impulse motion. Ordinary grid movement cannot move or orbit the camera. `WorldLabelController` applies local, adjacent, and distant station tiers on assignment and meaningful camera/responsive changes; it creates no permanent UI, sends no remote, owns no full per-frame loop, and cleans all connections. `ResponsiveLayout` and `ProfileResponsiveLayout` continue to apply scale-based safe-area geometry to authored panels while keeping the projected crate rectangle clear.

## Phase 07 crate, arena, and lighting composition

The crate's authored front is a low solid rim rather than a full sheet. Side and rear panes use thin non-refractive SmoothPlastic; managed station crate descendants reject `Enum.Material.Glass`. A warm opaque floor and 25 individually legible tiles preserve cell readability, a thin graphite frame defines containment, one restrained task light illuminates the interior, and the authored lid remains the moving closure component. Temporary item/ghost visuals preserve authoritative cells, station isolation, and existing cleanup.

Eight equivalent bays remain at 45-degree intervals on a wider visual ring, each containing a crate, low console, stand, compact shelf, integrated owner/status display, small risk indicator, and task-light support. The authored circular/octagonal warehouse shell, enclosed floor, support system, entry, restrained branding, and central dispatch establish a shared arena silhouette without changing station allocation. The existing 16-node showcase route, FIFO limits, reward independence, and shared motion loop remain intact.

Lighting and its restrained BloomEffect and ColorCorrectionEffect are managed permanent instances. Neon is limited to small semantic accents; large floors, walls, consoles, crate faces, spheres, and arena borders are rejected unless explicitly allowlisted and visually justified. No depth-of-field gameplay blur, motion blur, per-frame lighting update, particle system, physics-driven environment, per-station frame loop, or per-label frame loop is introduced.

## Phase 07 shipping, failure, and evidence boundary

`WorldMotionController` visually refines the accepted states without changing their authority or timing contract: shipping keeps the arrangement visible while the lid closes and sends the showcase toward dispatch; failure exposes the impact and burst through the open front; reset visibly raises the lid and clears stale presentation. Temporary objects return to their established baseline.

Architecture/configuration validation is necessary but not visual acceptance. The final candidate still requires seven fresh Node gates, seven fresh Studio suites, the full viewport and line-of-sight matrices, opening/desktop/touch/opposite-station/multiplayer live review, the external screenshot set and continuous recording, two clean authoring passes, cloud save, complete close, and direct no-sync reopen parity. The detailed contract and pending evidence ledger are in `docs/PHASE07_VISUAL_READABILITY_ARENA_REBUILD.md` and `docs/DEVELOPMENT_STATUS.md`.
