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

## Decision interface layout contract

`DecisionPanel` stores its visible target in the manifest: `Position = UDim2.new(0.5, 0, 0.96, 0)`, `AnchorPoint = Vector2.new(0.5, 1)`, `Size = UDim2.new(0.5, 0, 0.30, 0)`, and `Visible = false`. The manifest does not store an off-screen hidden position. `RoundUIController` owns a temporary 16-pixel vertical offset, a `0.30s` entrance, and a `0.20s` exit. Target-visibility state and transition epochs prevent repeated snapshots from restarting an entrance and prevent delayed exits from hiding a panel that has reopened.

The source-controlled bounds contract covers every required viewport:

| Viewport | DecisionPanel bounds | ShipButton bounds | OneMoreButton bounds |
| --- | --- | --- | --- |
| `1920×1080` | `(480, 712.8)–(1440, 1036.8)` | `(768, 910.44)–(1056, 991.44)` | `(1094.4, 910.44)–(1401.6, 991.44)` |
| `1366×768` | `(341.5, 506.88)–(1024.5, 737.28)` | `(546.4, 647.42)–(751.3, 705.02)` | `(778.62, 647.42)–(997.18, 705.02)` |
| `2560×1440` | `(640, 950.4)–(1920, 1382.4)` | `(1024, 1213.92)–(1408, 1321.92)` | `(1459.2, 1213.92)–(1868.8, 1321.92)` |
| `1100×700` | `(275, 462)–(825, 672)` | `(440, 590.1)–(605, 642.6)` | `(627, 590.1)–(803, 642.6)` |

The static calculation also keeps `CurrentItemCard`, `ShipmentCard`, `PlacementControls`, and `ResultsPanel` inside the viewport and proves that the top cards do not cover either decision action. Permanent UI remains authored under `StarterGui`.

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

The client store rejects a lower `RoundId`; for the same round it rejects a `StateVersion` less than or equal to the stored version. A higher round remains valid even when its state version restarts at zero, and every accepted snapshot is copied before storage. Accepted placement presentation is keyed by round and client sequence so either `PlacementResponse` or the authoritative state-changing `RoundSnapshot` may arrive first without duplicating the impact, locking input, or treating `Failing` as acceptance.

Late clients use a warning-free event-driven authored-child wait for Roblox to clone `ONE_MORE_ITEM_Gameplay` into `PlayerGui`. The helper first checks `FindFirstChild`, then waits on `ChildAdded` without a deadline and retains the required `ScreenGui` class check. `ClientBootstrap` does not call `PlayerGui:WaitForChild` for this permanent UI. The Node architecture contract requires the event-driven wait and rejects warning-producing or finite variants.

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

`StartRound` now emits the authoritative `Preparing` snapshot before scheduling its transition. The first session uses `INITIAL_PREPARING_DURATION = 0.12`; Pack Again uses `RESTART_PREPARING_DURATION = 0.72`. A guarded `Preparing` timer advances to `PresentingItem`, whose separate `0.45s` timer advances to `AwaitingPlacement`. Placement cannot succeed during `Preparing`, and the client never selects the preparation mode.

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

The HUD animates only between server-provided totals: Shipment value counts over `0.25–0.40s`, Session Bank over `0.55–0.80s`, and Result value over `0.30s`. A newer snapshot cancels or retargets an older count. Failure and spectator snapshots cannot create false rewards.

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

- Initial Preparing: `0.12s`; restart Preparing: `0.72s`
- Item presentation: `0.35s` travel, `0.06s` settle, and `0.04s` hold
- Ghost grid interpolation: `0.08–0.10s`
- Rotation: `0.12`-stud lift, `0.18s` rise/turn with no more than four degrees of overshoot, then `0.08s` exact settle
- Accepted placement snap: approximately `0.10s`
- Rejected-placement nudge: `0.12s`
- Panel entrance: `16` pixels over `0.30s`; exit: `0.20s`
- One More transition: approximately `0.45s` through item presentation
- Successful shipping lid close: `0.75s` plus approximately `0.10s` pause
- Failure: `0.20s` failed lid attempt, `0.14s` impact pause, and `0.64s` deterministic burst inside the `1.0s` authoritative failure window; Pack Again remains available within `1.6s`
- Reset: `0.72s` authoritative Preparing window, including `0.35s` lid rise and one cyan grid sweep
- Tape counts: Shipment `0.25–0.40s`, Session Bank `0.55–0.80s`, Result `0.30s`

The temporary presentation proxy and `FailureBurst` live only under `RuntimePresentation`. State/item/round epochs cancel stale motion; restart and destruction clear debris, restore locally suppressed authoritative parts, and return the runtime container to baseline. UI tokens centralize instant, snap, quick, panel, and hero motion. No element bounces continuously.

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

## Current correction verification

- The corrected manifest synchronized twice before save with `Created=0 Updated=148 Skipped=0 Failed=0 Warnings=0 Backups=26`. After a clean no-resync cloud reopen, the full audit passed 157/157 managed paths with zero missing, duplicate, wrong-class, or conflicting instances.
- All 36 canonical Phase 01 and Phase 02 Luau sources matched their live Studio sources by SHA-256. Live `ClientBootstrap` matched `sha256:2327d05560ce4b55e2eecdb45d3a27417e4f37dcb2b0c0a3000112a2c4ed6f02`.
- The reopened authored `DecisionPanel` retained `AnchorPoint = (0.5, 1)`, `Position = (0.5, 0, 0.96, 0)`, `Size = (0.5, 0, 0.3, 0)`, and `Visible = false`.
- The dependency-free Node smokes passed after the warning fix at `[StudioSyncSmoke] PASS checks=16 folders=7 scripts=10 deterministic=true` and `[Phase02StudioSyncSmoke] PASS criteria=24 instances=122 scripts=26 remotes=6 deterministic=true phase01=true`.
- The static layout contract passed at all four sizes in the table above. Real `1920×1080`, `1366×768`, and narrow `1100×700` Play runs kept the full Decision panel and both actions on-screen. At `1366×768`, the visual center resolved to logical `(2, 2)` and the four visible crate corners to `(0, 0)`, `(4, 0)`, `(0, 4)`, and `(4, 4)` without a top-bar shift.
- Final post-reopen Play Solo passed Phase 01 at 69/69 across 15 suites and Phase 02 at 94/94 across 11 suites. The fixed seeds remain `24012026` with 1,000 Phase 01 fuzz cases and `24022026`; fresh actionable Output warnings and errors were both zero.
- Final flows covered placement-timeout failure, Pack Again reset, decision-timeout Ship for `+15 TAPE` and `SESSION 15 TAPE`, One More followed by manual Ship for `+57 TAPE` and `SESSION 72 TAPE`, and a packed-content failure for `LOST 15 TAPE` while `SESSION 72 TAPE` remained banked.
- A final 60 FPS focused capture confirmed the reset-to-placement sequence, temporary PresentationPoint handoff, multi-frame rotation of an irregular One More ghost, accepted Parcel transition into Decision, and Shipment Tape counting through intermediate values before reaching the exact authoritative total.
- Final cleanup returned `RuntimePresentation=0` and `PlacedItems=0`.
- The final two-client run after `cd4cf83` logged `READY` on both clients. Pack Again started owner round 2 and progressed through `Preparing → PresentingItem → AwaitingPlacement`; the spectator remained visibly `SPECTATING` with `0 TAPE`, `BANK 0 TAPE`, and disabled Pack Again.
- Fresh bridge diagnostics returned `errors=0`, `matching=0`, and `latestActionable=null`; five plugin loops each reported `errors=0`. Studio ended normally with only the main Edit window remaining.
- Studio saved the warning-free corrected place normally at 2026-07-13 14:02:14 Eastern and reported `Saved new changes in "ONE MORE ITEM!" to Roblox.` The external recovery copy `ONE_MORE_ITEM_phase02_final_warningfix_20260713.rbxl` was verified at 14:03:57 Eastern with a size of 159,447 bytes.
- Studio closed cleanly and cold-reopened the cloud place without source resynchronization. The active identity remained `PlaceId 134193642444044` and `GameId 10493030248`; Studio's internal `Place2` label is only a local display label and does not override those IDs.
- Only final documentation-head GitHub Actions and local/remote/PR-head equality remain pending; this section does not claim those gates have passed.

## Known limitations and out of scope

Phase 02 intentionally excludes mobile/gamepad controls, camera orbit, seven additional stations, final models, sounds/music, final VFX, Tape-wrap/dispatch/showcase shipping, persistent DataStores/economy, XP/ranks/collection/mastery/dailies/missions, cosmetics/store/monetization, analytics/quests/trading/pets/rebirths, multiple worlds, co-op, tutorial screens, and the final launch arena.
