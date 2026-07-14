# Phase 03 — Cross-Platform Interaction and Responsive UI

Phase 03 adapts the existing single-station, server-authoritative packing round for keyboard/mouse, touch, gamepad, and hybrid input. It does not change the round authority model, add gameplay remotes, or begin the eight-station launch arena.

The implementation is present on `codex/phase-03-cross-platform-input` and is accepted. PR #3 remains draft and unmerged pending final merge review; Phase 04 has not started.

## Acceptance disposition

**Phase 03 implementation acceptance: Complete.**

The production code, permanent authored content, responsive safe-area matrix, automated Phase 01–03 suites, cloud persistence and source parity, and completed six-profile touch/orientation matrix passed. The deterministic simultaneous second-touch rejection contract is accepted for Phase 03. No known production defect remains.

The full physical-style controller session, uninterrupted KeyboardMouse → Gamepad → Touch → KeyboardMouse round, expanded two-player action matrix, ten-round mixed-input soak, physical phone, physical simultaneous multi-touch, and physical controller checks remain unpassed and are tracked in [pre-release QA issue #4](https://github.com/kotonja/ONE-MORE-ITEM-/issues/4). They are intentionally deferred until the complete multiplayer game and later launch-critical systems exist, and they are not Phase 03 implementation blockers. Physical simultaneous multi-touch remains deferred; a physical phone and physical controller were not tested.

The incomplete manual observations below are retained as historical evidence. This acceptance decision does not rewrite any attempted manual gate as passed.

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

The authored property contract and 65-case simulated safe-inset matrix pass. Six real Studio device-emulator profiles also kept the core panels, actions, Roblox top bar, crate interaction area, and responsive cameras contained.

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

The automated touch tracker contracts pass. The final emulator matrix recorded:

| Category | Studio profile | Actual viewport | Layout class | Mapping result |
| --- | --- | --- | --- | --- |
| Small phone portrait | iPhone 7 | `373×666` | `Portrait` | center `2,2`; corners `0,0`, `4,0`, `0,4`, `4,4` |
| Tall phone portrait | iPhone 16 | `392×758` | `Portrait` | center `2,2`; corners `0,0`, `4,0`, `0,4`, `4,4` |
| Small phone landscape | iPhone 7 | `665×374` | `CompactLandscape` | center `2,2`; corners `0,0`, `4,0`, `0,4`, `4,4` |
| Large phone landscape | iPhone 13 | `749×368` | `CompactLandscape` | center `2,2`; corners `0,0`, `4,0`, `0,4`, `4,4` |
| Tablet portrait | iPad 6 | `767×1022` | `Portrait` | center `2,2`; corners `0,0`, `4,0`, `0,4`, `4,4` |
| Tablet landscape | iPad 6 | `1022×767` | `CompactLandscape` | center `2,2`; corners `0,0`, `4,0`, `0,4`, `4,4` |

Every profile used `PreferredInput=Touch` and passed the safe-area, camera-priority, assigned default-control, coordinate, drag/release, multi-rotation Chair, Place, both Ship and One More, failure, Results, Pack Again, and cleanup checks. Release returned `ActivePlacementTouch=false` and never placed. The six-profile matrix and deterministic simultaneous second-touch rejection contract are accepted for Phase 03. Physical simultaneous multi-touch was not proven by this emulator matrix.

Physical simultaneous multi-touch: Deferred to later physical-device QA

Orientation changed during `AwaitingPlacement` on a phone at round 14/state version 2 and on a tablet at round 4/state version 2. Both transitions preserved RoundId, StateVersion, RoundState, current item, ItemCount, SessionBank, and logical ghost position; post-change mapping remained correct, the camera retargeted without replaying arrival, and `LayoutTweens` returned to zero.

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

The pure gamepad routing, safe-default, and fixed-clock repeat tests pass. Earlier manual Generic Gamepad checks recorded portions of D-pad, deadzone, placement, selection, One More, and Pack Again behavior, and reproduced the two confirmation defects corrected at `f04a507`. In the final live pass, Studio Controller Emulator confirmed Gamepad connection/reconnection, exactly three bindings rather than duplicated bindings, safe Results/Pack Again focus, one restart, and cleanup on exit to a non-Gamepad mode. Those observations do not constitute a complete controller-only A-J session; that unpassed session is tracked as pre-release QA in issue #4.

The correction keeps placement Button A owned by `ContextActionService`, passes Decision/Results Button A to the exact selected authored button, rejects non-selected gamepad button activation, and synchronizes the logical action with `GuiService.SelectedObject`. Focused deterministic tests cover selected-action resolution and authored-button routing. A complete uninterrupted controller-only A-J session, all-direction D-pad proof, held repeat delay/interval, stick direction-change/diagonal/tie behavior, multi-rotation Button X, all outside-state negatives, exact placement/Ship/One More/Button B request traces, and Decision-state disconnect/reconnect remain unpassed and are tracked in issue #4. No production source correction was required in the final pass; the transient acceptance probe was removed, and no manifest property, permanent instance, synchronization, or Studio save changed.

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

Static selection/retarget/impulse tests and authored-anchor parity pass. All six profile cameras and the phone/tablet orientation retargets also passed; the unpassed ten-round obsolete-tween cleanup check is tracked as pre-release QA in issue #4.

## Character-control behavior

While the local player owns Station 01, `CharacterController` leases the existing PlayerModule controls, disables them when they were previously enabled, and applies high-priority movement/jump sinks as a defensive fallback. It suppresses the current Humanoid's `AutoRotate` and records the exact prior value.

Unassignment or destruction removes the fallback bindings and restores only controls changed by this controller. Respawn reapplies the lease while assigned, including a late Humanoid, and restores the previous AutoRotate value when the tracked Humanoid changes. Spectators are not modified. The controller does not destroy `TouchGui` or permanently modify CoreGui.

The deterministic lease, respawn, late-Humanoid, restoration, spectator, and destroy tests pass. Assigned-owner respawn recovered station assignment, camera, active input, and movement suppression; exact PlayerStand placement/default-mobile-control behavior and previous-owner restoration after station release remain incomplete and are tracked in the expanded pre-release multiplayer QA.

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
7. Review the preserved manual evidence below. Extended controller, hybrid, two-player, ten-round cleanup, and physical-device checks are tracked as pre-release QA in issue #4 rather than Phase 03 implementation blockers.

Verified local Node 24 results:

```text
[StudioSyncSmoke] PASS checks=16 folders=7 scripts=10 deterministic=true
[Phase02StudioSyncSmoke] PASS criteria=24 instances=135 scripts=34 remotes=6 deterministic=true phase01=true
[Phase03LayoutMatrix] PASS viewports=13 insetProfiles=5 cases=65 desktopCompatible=true safeContainment=true
[Phase03CrossPlatformSmoke] PASS criteria=31 viewports=13 insetProfiles=5 layoutCases=65 remotes=6 deterministic=true phase01=true phase02=true
```

Verified fresh Studio Output:

```text
[ONE_MORE_ITEM][FoundationTests] RESULT suites=15 tests=69 passed=69 failed=0 duration=0.356362s fuzzCases=1000 fuzzSeed=24012026
[ONE_MORE_ITEM][FoundationTests] PASS: all 69 tests passed
[ONE_MORE_ITEM][Phase02Tests] RESULT suites=11 tests=94 passed=94 failed=0 duration=6.942747s seed=24022026
[ONE_MORE_ITEM][Phase02Tests] PASS: all 94 tests passed
[ONE_MORE_ITEM][Phase03Tests] RESULT suites=8 tests=65 passed=65 failed=0 duration=0.005859s seed=13072026
[ONE_MORE_ITEM][Phase03Tests] PASS: all 65 tests passed
```

The Phase 03 distribution is Input mode store 6, responsive classification 5, responsive geometry 9, touch tracking 7, gamepad repeat/action routing 17, prompts 4, camera targeting 5, and control cleanup/remote discipline 12.

Both canonical blueprints were applied twice with zero failures or warnings after the earlier source correction. The combined managed audit observed all `180/180` expected paths with zero missing, wrong-class, duplicate, or unexpected paths. Exact source parity passed `44/44`, and the six approved remotes were exact. The existing persistence proof remains valid because this final pass changed no Studio-managed source, manifest property, or permanent instance. Fresh post-probe Play passed all three suites with zero fresh actionable warnings or errors after baseline; no synchronization or save was performed.

## Emulator and physical-device evidence

- **Evidence environment:** Roblox Studio `0.729.0.7290838`. Desktop and automated suites used Play; touch/orientation used Play with Device Emulator; gamepad and mode-switch observations used Play with Controller Emulator; earlier two-player checks used Local Server; persistence used Edit mode after a direct cloud reopen.
- **Studio device emulator:** All six required categories were exercised at `373×666`, `392×758`, `665×374`, `749×368`, `767×1022`, and `1022×767`; the completed matrix is accepted under the revised policy.
- **Studio controller emulator:** The final Generic Gamepad trace confirmed connection/reconnection, exactly three bindings, safe Results restart, and mode-exit cleanup. The complete controller-only A-J session and uninterrupted hybrid round were not passed and are deferred to issue #4.
- **Fresh two-player final session:** Not completed. Earlier evidence does not satisfy the expanded pre-release action matrix tracked in issue #4.
- **Physical phone:** Not tested. Studio device emulation was used.
- **Physical controller:** Not tested. Studio controller emulation was used.

## Cloud persistence evidence

- An external recovery `.rbxl` copy was created outside the repository and verified at 181,185 bytes.
- Studio reported `Saved new changes in "ONE MORE ITEM!" to Roblox.` for the original private place.
- Every Studio process was closed. One clean Studio process then reopened the place directly from Roblox without running either synchronization path.
- Because Studio-managed sources changed during acceptance, both canonical synchronization paths were rebuilt and applied twice before saving. The no-resynchronization reopen audit passed `180/180` unique managed paths, zero missing/wrong-class/unexpected/duplicate paths, `44/44` exact canonical sources, and the exact six-remotes surface.
- The post-reopen command audit contained reads and diagnostics only; it contained zero mutating synchronization commands.
- The safe-area properties, touch surface, focus strokes, size constraints, responsive anchors, and earlier permanent content remained present after reopen.
- No Studio-managed source, manifest property, or permanent instance changed in the final pass, so this proof was reused without synchronization, save, or reopen.

A historical cloud reconnect attempt failed with Studio `RCC-277` after transport connected but no join snapshot arrived. The final corrected place later saved and reopened normally from cloud; RCC-277 was not a current persistence blocker and did not invalidate either proof.

## Known limitations and deferred pre-release QA

- [Issue #4](https://github.com/kotonja/ONE-MORE-ITEM-/issues/4) is the single open tracker for the deferred checks below. They remain unpassed and are not Phase 03 implementation blockers.
- Physical simultaneous multi-touch is deferred to later physical-device QA.
- The complete controller-only A-J session remains unpassed; emulator connection/reconnection, three bindings, safe restart, and mode-exit cleanup were confirmed but do not constitute a full pass.
- The uninterrupted keyboard → gamepad → touch → keyboard round remains unpassed.
- The expanded two-player owner/spectator action matrix remains unpassed; earlier observations do not satisfy it.
- The prescribed ten-round mixed-input soak and final duplicate-handler checks remain unpassed.
- Physical phone and physical controller testing were not performed.
- No known Phase 03 production defect remains.
- Corrected implementation head `f04a507eb7cae76a34573cf7d8ba6aaf8b4d7b68` passed branch-push run `29335824552` and draft-PR run `29335826478`; both `Phase 01–03 Node Validation` jobs passed every step.
- The exact latest documentation head and its post-commit checks are reported from live GitHub state in the completion report because a commit cannot contain its own post-commit result.

## Deferred systems

Phase 03 deliberately excludes seven additional stations, the full arena and dispatch presentation, final models/assets/audio/VFX, haptics, persistent Tape and DataStores, progression, collection, challenges, missions, cosmetics, store/monetization, analytics, social systems, trading, pets, rebirths, multiple worlds, co-op, camera orbit, the final launch map, and every Phase 04 system.
