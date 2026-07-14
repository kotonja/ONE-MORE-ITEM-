# Phase 03 — Cross-Platform Interaction and Responsive UI

Phase 03 adapts the existing single-station, server-authoritative packing round for keyboard/mouse, touch, gamepad, and hybrid input. It does not change the round authority model, add gameplay remotes, or begin the eight-station launch arena.

The implementation is present on `codex/phase-03-cross-platform-input`. Static validation, all three Studio test suites, canonical synchronization, exact source parity, desktop completion, one small-landscape touch completion, and the Phase 03 cloud save/close/direct-reopen gate are verified. The remaining touch-device matrix, complete controller-only flow, hybrid and two-player runs, and ten-round cleanup gate remain pending; Phase 03 is therefore still partial and PR #3 must remain draft and unmerged.

## Permanent authored content

`studio/phase02.manifest.json` remains the single permanent source for the vertical slice despite its historical filename. Phase 03 extends it rather than creating a competing manifest.

The authored additions are present before Play:

- `StarterGui.ONE_MORE_ITEM_Gameplay.Root.TouchDragSurface`, a transparent full-root `Frame` at `ZIndex = 0`. Runtime code enables it only for an assigned touch player in `AwaitingPlacement`.
- A `FocusStroke` `UIStroke` beneath Rotate, Place, Ship, One More, and Pack Again. Every stroke is authored at `Thickness = 3`, `Transparency = 1`, and `Enabled = false`; runtime presentation enables the strokes and reveals only the selected gamepad action.
- A `CompactMinimum` `UISizeConstraint` beneath each of the five primary actions. The authored baselines are `72 × 44` for Rotate/Place/Ship/One More and `120 × 44` for Pack Again. Responsive runtime values enforce `72 × 64` for Rotate/Place and `120 × 64` for Ship/One More/Pack Again outside `Wide`; `Wide` retains the Phase 02 geometry.
- `Workspace.ONE_MORE_ITEM_WORLD.PlaytestArena.Stations.Station_01.CameraAnchorTouchLandscape` at `(0, 21, 22)` with orientation `(-40, 0, 0)` degrees.
- `Workspace.ONE_MORE_ITEM_WORLD.PlaytestArena.Stations.Station_01.CameraAnchorTouchPortrait` at `(0, 28, 30)` with orientation `(-43, 0, 0)` degrees.

Both responsive anchors are anchored, invisible, non-colliding, non-queryable, non-touching Parts with no scripts. Runtime code still creates only temporary ghost, placed-item, viewport, and presentation objects.

## Safe-area configuration

The final authored `StarterGui.ONE_MORE_ITEM_Gameplay` combination is:

```text
ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
ClipToDeviceSafeArea = true
SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
IgnoreGuiInset = true
```

Responsive layout reads Roblox-provided `DeviceSafeInsets` and `CoreUISafeInsets` through `GuiService`; it does not hard-code a notch, top-bar, or home-indicator size. Root-level targets are resolved inside the usable rectangle. Wide layouts preserve the exact Phase 02 scale geometry when it already clears the top bar, while narrow layouts reserve the reported safe area.

Mouse and touch coordinates use `Camera:ViewportPointToRay` directly with `UserInputService` positions. No second GUI-inset subtraction is applied.

The authored property contract and 65-case simulated safe-inset matrix pass. Visual notch, rounded-corner, top-bar, and orientation behavior in Studio device emulation remains an acceptance gate.

## Input modes

`InputModeStore` defines exactly three local presentation modes:

| `UserInputService.PreferredInput` | Presentation mode |
| --- | --- |
| `Enum.PreferredInput.KeyboardAndMouse` | `KeyboardMouse` |
| `Enum.PreferredInput.Touch` | `Touch` |
| `Enum.PreferredInput.Gamepad` | `Gamepad` |

The store subscribes to `PreferredInput`, suppresses repeated identical notifications, and removes its source subscription and listeners on destroy. A mode change only reroutes local input, prompts, gamepad focus, responsive presentation, and camera target selection. It does not restart the round, clear the ghost, mutate a snapshot, or send a server request.

`InputController` coordinates the mode store and the focused touch, gamepad, and prompt controllers while preserving the Phase 02 keyboard/mouse bindings.

## Responsive layout classes

Classification uses the safe usable viewport, not the input mode:

- `Portrait`: aspect ratio below `1.10`.
- `CompactLandscape`: aspect ratio from `1.10` to below `1.45`, or usable height at most `500` pixels.
- `Wide`: larger landscape geometry.

All responsive target positions and sizes use scale-only `UDim2` values. Initial application is immediate. Later viewport or orientation changes cancel and retarget separate AnchorPoint, Position, and Size tweens over `0.25s` with Quart Out, preserving panel visibility, count animation targets, gamepad selection, and placement state.

The deterministic matrix covers:

| Category | Viewports | Expected class |
| --- | --- | --- |
| Desktop | `1920×1080`, `1366×768`, `2560×1440`, `1100×700` | `Wide` |
| Phone portrait | `360×640`, `390×844`, `393×852`, `430×932` | `Portrait` |
| Phone landscape | `640×360`, `844×390`, `932×430` | `CompactLandscape` |
| Tablet portrait | `768×1024` | `Portrait` |
| Tablet landscape | `1024×768` | `CompactLandscape` |

Five inset profiles are applied to all 13 viewports: none, top, left/right, bottom, and combined. The resulting 65 cases keep core panels and primary actions inside the simulated safe rectangle, preserve action containment, and retain the minimum compact action sizes. The `Wide` profile remains exactly compatible with the approved Phase 02 desktop geometry.

## Touch interaction

Touch placement uses the authored `TouchDragSurface`:

1. A touch may begin only in touch mode while the local player owns Station 01 and the round is awaiting placement.
2. A touch beginning over another visible active GUI object is ignored.
3. The first allowed touch becomes the sole active placement touch; simultaneous touches are ignored.
4. Start and movement positions update the ordinary local ghost through a viewport ray. Movement below one pixel is ignored.
5. A state or ownership change cancels the active touch.
6. Releasing the touch leaves the ghost at its final cell and never places automatically.
7. The authored Rotate and Place buttons perform those actions.

The controller does not use swipe grid movement, pinch, two-finger rotation, or generated `ContextActionService` touch buttons. Touch movement and rotation remain local and do not send remotes.

The automated touch tracker contracts pass. A real `667 × 375` small-landscape device-emulator run verified drag tracking, invalid-placement feedback, a valid placement, Ship, Results, Pack Again, and visibly contained UI. The remaining portrait/tablet profiles, the full center/corner coordinate matrix, and orientation-change mapping remain pending.

## Gamepad mapping and safe focus

Gamepad actions are bound through `ContextActionService:BindActionAtPriority` at `Enum.ContextActionPriority.High.Value + 100` with `createTouchButton = false`.

| Round state | Input | Action |
| --- | --- | --- |
| AwaitingPlacement | Left stick or D-pad | Move one grid cell |
| AwaitingPlacement | Button X | Rotate |
| AwaitingPlacement | Button A | Place |
| Decision | Left stick horizontal or D-pad left/right | Select Ship or One More |
| Decision | Button A | Confirm the selected decision |
| Results | Button A | Pack Again |

Button B has no risky binding. Decision always starts with Ship selected; One More requires deliberate horizontal selection followed by Button A. Results starts with Pack Again selected. Placement clears GUI selection. Leaving gamepad mode, losing assignment, or disconnecting clears focus and repeat state; reconnecting restores the safe state-appropriate default.

Stick repeat is deterministic:

- Deadzone: `0.55`.
- First step: immediate.
- Initial repeat delay: `0.28s`.
- Repeat interval: `0.12s`.
- Dominant axis wins; equal diagonals choose X.
- A poll emits at most one cell even after a late frame.
- Release, direction change, state change, pending placement, disconnect, and destruction reset or gate repeat state as appropriate.

The pure gamepad routing, safe-default, and fixed-clock repeat tests pass. Studio's Generic Gamepad emulator visibly produced the expected placement prompts and safe Results-state Pack Again focus. A complete controller-only round, held-stick/D-pad observation, deliberate One More confirmation, and disconnect/reconnect remain pending. Temporary emulator mappings used during diagnosis were restored to their defaults.

## Dynamic prompts and focus defaults

| Mode | Rotate | Place | Control or confirmation hint | Pack Again |
| --- | --- | --- | --- | --- |
| Keyboard/mouse | `ROTATE  [R]` | `PLACE  [SPACE]` | `MOUSE / WASD / ARROWS TO MOVE` | `PACK AGAIN  [ENTER]` |
| Touch | `ROTATE` | `PLACE` | `DRAG TO MOVE` | `PACK AGAIN` |
| Gamepad | `ROTATE  [X]` | `PLACE  [A]` | `LEFT STICK / D-PAD TO MOVE`; Decision uses `SELECT  ◀  ▶` and `CONFIRM  [A]` | `PACK AGAIN  [A]` |

Ship and One More retain authoritative guaranteed/possible Tape values and difficulty text. Keyboard adds `[Q]` and `[E]`; touch and gamepad decision labels omit keyboard keys. Gamepad selection reveals only the authored stroke for the logical selected action. No external button-icon asset or runtime-created focus outline is used.

## Responsive camera

Camera target selection is:

| Presentation | Anchor |
| --- | --- |
| `Wide` | `CameraAnchor` |
| Touch `CompactLandscape` | `CameraAnchorTouchLandscape` |
| Any `Portrait` input mode | `CameraAnchorTouchPortrait` |
| Non-touch `CompactLandscape` | `CameraAnchor` |

Initial station assignment retains the approved `0.60s` arrival. A responsive target change cancels the active camera tween and retargets over `0.25s` with Quart Out without replaying arrival. The camera remains Scriptable and looks at `CameraFocus`. Placement, shipping, and failure impulses are epoch-guarded so an obsolete impulse cannot settle over a newer orientation target.

Static selection/retarget/impulse tests and authored-anchor parity pass. Real portrait/landscape camera composition in every required state remains pending.

## Character-control behavior

While the local player owns Station 01, `CharacterController` leases the existing PlayerModule controls, disables them when they were previously enabled, and applies high-priority movement/jump sinks as a defensive fallback. It suppresses the current Humanoid's `AutoRotate` and records the exact prior value.

Unassignment or destruction removes the fallback bindings and restores only controls changed by this controller. Respawn reapplies the lease while assigned, including a late Humanoid, and restores the previous AutoRotate value when the tracked Humanoid changes. Spectators are not modified. The controller does not destroy `TouchGui` or permanently modify CoreGui.

The deterministic lease, respawn, late-Humanoid, restoration, spectator, and destroy tests pass. Real assigned respawn and touch-control visual-conflict checks remain pending.

## Network discipline

Phase 03 authors no new gameplay remote. The permanent network surface remains:

- `ClientReadyRequest`
- `PlaceItemRequest`
- `DecisionRequest`
- `RestartRequest`
- `RoundSnapshot`
- `PlacementResponse`

Touch rays, thumbstick positions, D-pad movement, rotation, preferred input, UI geometry, camera state, focus state, and ghost movement never cross the network. Place maps to one existing placement request, Ship/One More map to one existing decision request, and Pack Again maps to one existing restart request. Phase 02 station ownership, sequence/version/round/deadline/grid validation, rate limiting, and reward authority remain unchanged.

## Test procedure and current evidence

Repository validation:

1. Run `node tools/test_studio_blueprint.mjs`.
2. Run `node tools/test_phase02_blueprint.mjs`.
3. Run `node tools/test_phase03_cross_platform.mjs` under Node 24.
4. Build and apply the Phase 01 and extended Phase 02 blueprints in that order, twice.
5. Verify managed paths, classes, duplicates, properties, and exact source parity before Play.
6. Run all three Studio development suites and inspect fresh Output.
7. Complete the required desktop, touch-emulator, gamepad, hybrid, two-player, ten-round cleanup, and cloud close/reopen checks.

Verified local Node 24 results:

```text
[StudioSyncSmoke] PASS checks=16 folders=7 scripts=10 deterministic=true
[Phase02StudioSyncSmoke] PASS criteria=24 instances=135 scripts=34 remotes=6 deterministic=true phase01=true
[Phase03LayoutMatrix] PASS viewports=13 insetProfiles=5 cases=65 desktopCompatible=true safeContainment=true
[Phase03CrossPlatformSmoke] PASS criteria=29 viewports=13 insetProfiles=5 layoutCases=65 remotes=6 deterministic=true phase01=true phase02=true
```

Verified fresh Studio Output:

```text
[ONE_MORE_ITEM][FoundationTests] RESULT suites=15 tests=69 passed=69 failed=0 duration=0.368965s fuzzCases=1000 fuzzSeed=24012026
[ONE_MORE_ITEM][FoundationTests] PASS: all 69 tests passed
[ONE_MORE_ITEM][Phase02Tests] RESULT suites=11 tests=94 passed=94 failed=0 duration=7.276670s seed=24022026
[ONE_MORE_ITEM][Phase02Tests] PASS: all 94 tests passed
[ONE_MORE_ITEM][Phase03Tests] RESULT suites=8 tests=63 passed=63 failed=0 duration=0.006260s seed=13072026
[ONE_MORE_ITEM][Phase03Tests] PASS: all 63 tests passed
```

The Phase 03 distribution is Input mode store 6, responsive classification 5, responsive geometry 9, touch tracking 7, gamepad repeat/action routing 16, prompts 4, camera targeting 5, and control cleanup/remote discipline 11.

Both canonical blueprints were applied twice with zero failures or warnings. The combined managed audit observed all `180/180` expected paths with zero missing, wrong-class, duplicate, or unexpected paths. Exact source parity passed `44/44`. Desktop Play verified timeout failure, Pack Again, placement, deliberate One More, a completed shipment, Results, and another Pack Again. The touch-emulator run verified a complete one-item shipment and Pack Again. Fresh Output contained no actionable game-owned warning or error.

## Emulator and physical-device evidence

- **Studio device emulator:** One `667 × 375` small-landscape run passed drag, invalid feedback, valid Place, Ship, Results, Pack Again, and visible containment. The other required touch profiles remain pending.
- **Studio controller emulator:** Generic Gamepad prompts and safe Pack Again focus passed visibly. Full controller-only action activation, round completion, held repeat, and reconnect behavior remain pending.
- **Physical device:** Not tested. No physical-phone or physical-controller result is claimed.

## Cloud persistence evidence

- An external recovery `.rbxl` copy was created outside the repository and verified at 181,185 bytes.
- Studio reported `Saved new changes in "ONE MORE ITEM!" to Roblox.` for the original private place.
- Every Studio process was closed. One clean Studio process then reopened the place directly from Roblox without running either synchronization path.
- The no-resynchronization reopen audit passed `180/180` unique managed paths, zero missing/wrong-class/unexpected/duplicate paths, `44/44` exact canonical sources, and the exact six-remotes surface.
- The post-reopen command audit contained reads and diagnostics only; it contained zero mutating synchronization commands.
- The safe-area properties, touch surface, focus strokes, size constraints, responsive anchors, and earlier permanent content remained present after reopen.

A later cloud reconnect attempt failed with Studio `RCC-277` after transport connected but no join snapshot arrived. That Roblox infrastructure failure interrupted additional emulator coverage; it does not invalidate the earlier successful save, full close, direct reopen, or no-resynchronization parity proof.

## Known limitations and remaining acceptance gates

- Five required touch profiles, the complete center/corner coordinate matrix, and orientation-change mapping remain pending.
- Full gamepad placement/confirmation, held repeat, deliberate One More, controller-only Pack Again activation, and disconnect/reconnect remain pending; prompts and safe focus are proven.
- Mid-round hybrid switching, assigned respawn, two-player spectator isolation, and ten mixed-input rounds remain pending.
- The final pass observed a gamepad-to-keyboard prompt switch, but the complete keyboard → gamepad → touch hybrid flow remains pending.
- A later reconnect was blocked by `RCC-277`; the earlier Phase 03 cloud persistence gate is passed and preserved.
- GitHub Actions passed on implementation head `8bc43880c48164547e6bd0e63a634f683304d078`; the later documentation head still requires its own green push and pull-request checks.

## Deferred systems

Phase 03 deliberately excludes seven additional stations, the full arena and dispatch presentation, final models/assets/audio/VFX, haptics, persistent Tape and DataStores, progression, collection, challenges, missions, cosmetics, store/monetization, analytics, social systems, trading, pets, rebirths, multiple worlds, co-op, camera orbit, the final launch map, and every Phase 04 system.
