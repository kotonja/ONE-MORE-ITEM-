# Phase 02 — Playable Station Vertical Slice

Phase 02 proves the complete active packing loop at one authored station. It is a controlled desktop vertical slice, not the launch arena.

## Permanent world hierarchy

The permanent world is authored in Edit mode from `studio/phase02.manifest.json`; gameplay code never builds it.

```text
Workspace
└── ONE_MORE_ITEM_WORLD
    └── PlaytestArena
        ├── ArenaFloor
        ├── ArenaBackdrop
        └── Stations
            └── Station_01
                ├── StationRoot
                ├── PlayerStand
                ├── CameraAnchor
                ├── CameraFocus
                ├── PresentationPoint
                ├── Crate
                │   ├── Base
                │   ├── GridOrigin
                │   ├── GridTiles
                │   │   └── Cell_0_0 through Cell_4_4
                │   ├── WallFront
                │   ├── WallBack
                │   ├── WallLeft
                │   ├── WallRight
                │   ├── Lid
                │   └── CrateFocus
                ├── ControlConsole
                │   ├── RotateButton
                │   ├── PlaceButton
                │   ├── ShipButton
                │   └── OneMoreButton
                ├── PlacedItems
                └── RuntimePresentation
```

`Station_01` is tagged with the station ID, `5 wide × 4 high × 5 deep` logical dimensions, two-stud cell size, and active status. Those attributes support discovery but do not replace server state.

## Permanent UI hierarchy

The `ScreenGui`, all panels, buttons, labels, timers, constraints, and `ViewportFrame` surfaces exist under `StarterGui` before Play. Runtime controllers only bind and animate them.

```text
StarterGui
└── ONE_MORE_ITEM_Gameplay
    └── Root
        ├── CurrentItemCard
        │   ├── ItemViewport
        │   ├── ItemName
        │   ├── FitState
        │   └── PlacementTimer
        ├── ShipmentCard
        │   ├── UnshippedLabel
        │   ├── ShipmentValue
        │   ├── ItemCount
        │   ├── Multiplier
        │   └── SessionBank
        ├── PlacementControls
        │   ├── RotateButton
        │   ├── PlaceButton
        │   └── ControlHint
        ├── DecisionPanel
        │   ├── NextItemViewport
        │   ├── NextItemName
        │   ├── NextDifficulty
        │   ├── DecisionTimer
        │   ├── GuaranteedValue
        │   ├── PossibleValue
        │   ├── ShipButton
        │   └── OneMoreButton
        ├── StatusBanner
        ├── ResultsPanel
        │   ├── ResultTitle
        │   ├── ResultReason
        │   ├── ResultValue
        │   ├── SessionTotal
        │   └── PackAgainButton
        └── DevelopmentDebug
            ├── RoundState
            ├── RoundId
            ├── StateVersion
            ├── GridPosition
            └── ServerResponse
```

The debug panel is disabled by default and is never part of normal presentation.

## Station dimensions and grid transform

- Logical volume: `5 wide × 5 deep × 4 high` integer cells.
- Cell size: `2` studs.
- Interior volume: `10 × 10 × 8` studs.
- `GridOrigin` is the center transform of logical cell `{0, 0, 0}`.
- World transform: `GridOrigin * CFrame.new(x * 2, y * 2, z * 2)`.
- X/Z cell centers relative to crate center are `-4, -2, 0, 2, 4` studs.
- Y layer centers relative to the floor are `1, 3, 5, 7` studs.

`GridWorldTransform` is the single mapping contract. Physics contacts never determine placement validity.

## Authored networking

Six permanent `RemoteEvent` instances exist under `ReplicatedStorage.ONE_MORE_ITEM.Net`:

- `ClientReadyRequest`
- `PlaceItemRequest`
- `DecisionRequest`
- `RestartRequest`
- `RoundSnapshot`
- `PlacementResponse`

`PlaceItemRequest` carries only round/version/item identity, quarter turns, X/Z origin, and client sequence. `DecisionRequest` carries only round/version, `SHIP` or `ONE_MORE`, and sequence. The server validates ownership, state, time, shape rotation, auto-drop, collision, bounds, sequence freshness, and rate limits.

Snapshots contain fresh serialized presentation data. They never expose the grid object, mutable server tables, valid solution coordinates, reward authority, or internal service objects.

## Authority boundary

The server owns station assignment, round IDs and versions, state transitions, occupancy, current and next item, placements, timers, rewards, banked session Tape, shipping, failure, and reset.

The client predicts only input response, ghost transform and color, camera motion, physical-button motion, and HUD presentation. A predicted ghost cannot mutate authoritative occupancy or reward state.

## Round state machine

```text
Preparing → PresentingItem → AwaitingPlacement → Decision
                                  │                ├── SHIP → Shipping → Results
                                  │                └── ONE_MORE → PresentingItem
                                  └── timeout → Failing → Results

Results → PACK AGAIN → Preparing
Decision timeout → Shipping
No legal candidate → Shipping (BOX_FULL)
Maximum item count → Shipping (MAX_ITEMS)
```

Every transition increments `StateVersion`. Delayed work captures player, round ID, and version and becomes a no-op when any value is stale.

## Sequence fairness

- The first item is always Parcel / `SingleCube`.
- Candidate evaluation enumerates Phase 01 legal placements against a cloned grid.
- Zero-placement candidates are excluded.
- Immediate repetition is avoided when alternatives exist.
- More than two consecutive offers from one shape family are avoided when alternatives exist.
- Selection is deterministic for stable player/round seed data.
- The client never selects the next item.

Player-facing difficulty remains `EASY FIT` for 10+, `TIGHT FIT` for 4–9, and `BRUTAL FIT` for 1–3 legal placements. Zero is never offered.

## Development items

| Item | Shape | Base value | Development color |
| --- | --- | ---: | --- |
| Parcel | SingleCube | 15 | Cardboard amber |
| Long Package | HorizontalBar2 | 25 | Cyan |
| Lamp Blockout | VerticalColumn3 | 35 | Warm yellow |
| Table Blockout | FlatSquare2x2 | 40 | Blue |
| Chair Blockout | Chair | 50 | Green |
| L Package | FlatL | 45 | Purple |
| T Package | FlatT | 55 | Orange |
| Heavy Cargo | LargeIrregular | 95 | Red-orange |

All proxy cells clone the authored, script-free `ReplicatedStorage.ONE_MORE_ITEM.Assets.Development.CellBlockTemplate`.

## Session-only Tape

Tape is deliberately non-persistent. Shipment value is `floor(base-value sum × item-count multiplier)` using multipliers `1.00, 1.15, 1.35, 1.60, 1.90, 2.25, 2.65, 3.20, 3.90, 5.00` for one through ten items.

Shipping banks exactly once. A failed unshipped round loses only that round value; Tape banked earlier in the current server session remains. Phase 02 does not use DataStores.

## Desktop controls and camera

- Mouse: intersect the crate selection plane and place with left click when UI is not consuming input.
- WASD / arrow keys: move one logical X/Z cell.
- `R`: rotate clockwise by 90 degrees.
- `Space`: request placement.
- `Q`: Ship during Decision.
- `E`: One More during Decision.
- `Enter`: Pack Again during Results.

The assigned character is moved to `PlayerStand`, faces the crate, remains visible, and has walking controls disabled locally while assigned. Respawn rebinds the station without permanently changing the avatar.

The gameplay camera is stable and scriptable at approximately 48 degrees field of view. Arrival eases to the authored anchor over 0.60 seconds. Ordinary grid movement never moves the camera; placement, shipping, and failure use restrained centralized impulses.

## Motion timings

- Item presentation: `0.45s`
- Ghost grid interpolation: `0.08–0.10s`
- Rotation: `0.18s` rise/turn plus `0.08s` settle
- Accepted placement snap: approximately `0.10s`
- Rejected-placement nudge: `0.12s`
- Decision-panel entrance: approximately `0.30s`
- One More transition: `0.45–0.55s`
- Lid close: `0.75s` plus approximately `0.10s` pause
- Failure presentation: approximately `1.0s`; Pack Again available within `1.6s`
- Reset: `0.70–0.85s`, including `0.35s` lid rise

UI tokens centralize instant, snap, quick, panel, and hero motion. No element bounces continuously.

## Visual direction

The authored station uses a toy-industrial game-show warehouse palette: charcoal sealed floor, matte raised metal, transparent acrylic crate walls, cyan navigation edges, amber shipping accents, green validity, and restrained risk red. The single station remains the focal point; there is no expanded warehouse, NPC, shop, portal, or decorative clutter.

The HUD uses scale-based placement, dark translucent rounded panels, restrained strokes, Gotham typography, and large readable state/value text while keeping most of the screen open for the crate.

## Test procedure

1. Run `node tools/test_studio_blueprint.mjs`.
2. Run `node tools/test_phase02_blueprint.mjs`.
3. Synchronize both generated Edit-mode blueprints into the original private place.
4. Confirm permanent hierarchy and exact source parity before Play.
5. Run Play Solo through placement, One More, Ship, timeout failure, and Pack Again.
6. Run the fixed-seed Phase 01 and Phase 02 Studio suites.
7. Run a two-player Studio session and verify Station 01 isolation.
8. Save to Roblox, close every Studio process, reopen directly from Roblox, and repeat parity/tests plus one successful round.

Exact run results belong in `docs/DEVELOPMENT_STATUS.md` after they are observed.

## Verified Phase 02 acceptance result

- The original cloud place (`PlaceId 134193642444044`, `GameId 10493030248`) was saved normally, every Studio process was closed, and the user reopened that same place from Roblox.
- Fresh bridge Studio session `d81093b5-5bae-4347-ae97-eb21720124ba` verified the reopened place in Edit mode, its exact managed trees with zero duplicate paths, and SHA-256 parity for all 36 canonical Luau sources.
- Post-reopen Studio Output passed the Phase 01 suite at 69/69 and the Phase 02 suite at 71/71.
- A post-reopen one-item shipment banked 15 Tape and displayed a 15-Tape session total; the fresh verification baseline contained zero warnings and zero errors.
- The real two-player run passed after replication-delay fix `02b2aeb`: one player owned Station 01 and the other received the authored spectator state, with zero fresh actionable game errors.
- No Avast setting was changed; the successful direct reopen made the proposed launcher exception unnecessary.

## Known limitations and out of scope

Phase 02 intentionally excludes mobile/gamepad controls, camera orbit, seven additional stations, final models, sounds/music, final VFX, Tape-wrap/dispatch/showcase shipping, persistent DataStores/economy, XP/ranks/collection/mastery/dailies/missions, cosmetics/store/monetization, analytics/quests/trading/pets/rebirths, multiple worlds, co-op, tutorial screens, and the final launch arena.
