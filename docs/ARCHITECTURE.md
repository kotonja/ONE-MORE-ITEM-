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
