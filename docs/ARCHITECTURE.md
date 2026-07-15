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

The historically named `studio/phase02.manifest.json` remains the sole canonical owner of every Phase 02-04 permanent path. Its `stationPlacements` array defines eight ordered descriptors. `tools/build_phase02_blueprint.mjs` validates that exact order and expands the complete Station_01 subtree into eight explicit, independently auditable final station paths. Expansion is deterministic, parent-first, idempotent, and conflict safe; it never clones stations at runtime and never silently replaces a wrong-class object.

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
