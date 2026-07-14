# Development status

## Current phase and Git state

- **Phase result:** Partial. The completed six-profile touch/orientation matrix is accepted and simultaneous second-touch emulation is waived as a merge blocker. The complete controller-only A-J session, uninterrupted keyboard/mouse → gamepad → touch → keyboard round, fresh two-player regression, and prescribed ten-round mixed-input soak remain open.
- **Current phase:** Phase 03 — Cross-Platform Interaction and Responsive UI.
- **Current branch:** `codex/phase-03-cross-platform-input`.
- **Draft pull request:** [PR #3 — Phase 03: Cross-Platform Interaction and Responsive UI](https://github.com/kotonja/ONE-MORE-ITEM-/pull/3), open, draft, based on `main`, and unmerged.
- **Protected base:** `main` and `origin/main` remain at the Phase 02 merge SHA `73b3428c5ff0068f1e57f89d2150ffb8dccfdf20`.
- **Latest verified implementation SHA:** `f04a507eb7cae76a34573cf7d8ba6aaf8b4d7b68` (`fix: harden phase 03 gamepad confirmation`).
- **Acceptance starting head:** `de0583915b13f6bdb0d9b7ef3cac7be1b8789c4f`.
- **Documentation record:** This file records the final non-waived acceptance attempt truthfully as partial. The completion report records the later documentation commit and its exact-head GitHub Actions runs after they exist; no uncreated commit or run is claimed here.

## Completed Phase 03 implementation

- `studio/phase02.manifest.json` remains the sole canonical owner for the permanent vertical-slice and Phase 03 additions despite its historical filename.
- The authored ScreenGui uses `DeviceSafeInsets`, `ClipToDeviceSafeArea = true`, `SafeAreaCompatibility.None`, and `IgnoreGuiInset = true`.
- Permanent content adds `TouchDragSurface`, five `FocusStroke` objects, five `CompactMinimum` constraints, and touch-landscape/portrait camera anchors.
- Authored constraint baselines are `72 × 44` for Rotate/Place/Ship/One More and `120 × 44` for Pack Again. Runtime compact layouts enforce approximately `72 × 64` and `120 × 64` action geometry.
- Strict client modules separate preferred-input state, pure responsive layout, authored-UI application, single-touch tracking, deterministic gamepad routing/repeat, adaptive prompts, and input coordination.
- `UserInputService.PreferredInput` selects `KeyboardMouse`, `Touch`, or `Gamepad` presentation without restarting or mutating the authoritative round.
- Safe usable viewport geometry independently selects `Wide`, `CompactLandscape`, or `Portrait`.
- Gamepad repeat uses a `0.55` deadzone, immediate first step, `0.28s` initial delay, and `0.12s` interval. Decision defaults to Ship; One More requires deliberate selection and confirmation. Button B has no risky action.
- Manual testing reproduced a Decision/Results Button A ownership defect twice. The focused correction leaves placement confirmation owned by `ContextActionService`, routes Decision and Results confirmation through the exact selected authored button, and synchronizes `SelectedGamepadAction` with `GuiService.SelectedObject`.
- Responsive camera selection uses the approved desktop anchor, the authored compact-touch anchor, or the authored portrait anchor and retargets without replaying arrival.
- Assigned character controls use a reversible PlayerModule lease plus high-priority fallback sinks and restore the exact prior Humanoid `AutoRotate` value.
- The network surface remains the six Phase 02 remotes. Pointer, touch, stick, D-pad, rotation, mode, layout, focus, camera, and ghost state remain local.
- No haptics, new gameplay remotes, runtime permanent UI/world builder, external package, or Phase 04 system was added.

## CI modernization

- **Workflow/job name:** `Phase 01–03 Node Validation`.
- **Action versions:** `actions/checkout@v7` and `actions/setup-node@v6`.
- **Runtime:** Node 24.
- **Permissions/configuration:** `contents: read`, `package-manager-cache: false`, no install step, no package manifest requirement, and no third-party dependency.
- **Triggers:** Pull requests targeting `main`; pushes to `main`; pushes to `codex/**`.
- **Commands:** Phase 01, Phase 02, and Phase 03 dependency-free Node validations run in order.
- Implementation-head push run `29288248053` and PR run `29288250378` passed at `8bc43880c48164547e6bd0e63a634f683304d078` before the documentation/checkout-major correction.
- Documentation/CI record head `1c3675f36ed0a078baad526831746e50a5438a31` passed [branch-push run 29295662133](https://github.com/kotonja/ONE-MORE-ITEM-/actions/runs/29295662133) ([job 86968466310](https://github.com/kotonja/ONE-MORE-ITEM-/actions/runs/29295662133/job/86968466310)) and [draft-PR run 29295664112](https://github.com/kotonja/ONE-MORE-ITEM-/actions/runs/29295664112) ([job 86968472279](https://github.com/kotonja/ONE-MORE-ITEM-/actions/runs/29295664112/job/86968472279)). Every setup, checkout, Node, Phase 01, Phase 02, Phase 03, post, and completion step succeeded; both check annotation lists were empty.
- Corrected implementation head `f04a507eb7cae76a34573cf7d8ba6aaf8b4d7b68` passed [branch-push run 29335824552](https://github.com/kotonja/ONE-MORE-ITEM-/actions/runs/29335824552) ([job 87094675031](https://github.com/kotonja/ONE-MORE-ITEM-/actions/runs/29335824552/job/87094675031)) and [draft-PR run 29335826478](https://github.com/kotonja/ONE-MORE-ITEM-/actions/runs/29335826478) ([job 87094681186](https://github.com/kotonja/ONE-MORE-ITEM-/actions/runs/29335826478/job/87094681186)). All three Node steps and every setup/post/completion step succeeded.
- A commit cannot contain its own post-commit result. The completion report records the exact latest status-only head, local/remote/PR-head equality, and both exact-head workflow results from live GitHub state.

## Local Node 24 validation

```text
[StudioSyncSmoke] PASS checks=16 folders=7 scripts=10 deterministic=true
[Phase02StudioSyncSmoke] PASS criteria=24 instances=135 scripts=34 remotes=6 deterministic=true phase01=true
[Phase03LayoutMatrix] PASS viewports=13 insetProfiles=5 cases=65 desktopCompatible=true safeContainment=true
[Phase03CrossPlatformSmoke] PASS criteria=31 viewports=13 insetProfiles=5 layoutCases=65 remotes=6 deterministic=true phase01=true phase02=true
```

The Phase 03 gate verifies sole-manifest ownership, permanent authored content, safe-area properties, input architecture, responsive geometry, camera selection, unchanged remotes, no haptics/runtime permanent builders, and the exact CI contract.

## Studio synchronization and no-resync parity

- Phase 01 and the extended vertical-slice blueprints were applied in canonical order twice.
- Receipts: Phase 01 `Created=0 Updated=0 Skipped=17`; Phase 02 `Created=0 Updated=169 Skipped=0`; both repetitions completed with zero failures or warnings.
- Before save, the combined audit passed `180/180` managed paths with zero missing, wrong-class, duplicate, or unexpected paths.
- Exact canonical source parity passed `44/44`; all source classes matched.
- The exact approved remote surface remained six RemoteEvents.
- After full close and direct cloud reopen, the same `180/180` hierarchy, `44/44` sources, six remotes, properties, anchors, and built-in `StarterPlayerScripts` container passed again.
- The post-reopen command audit contained reads/diagnostics only and zero mutating synchronization commands.

## Fresh automated Studio tests

```text
[ONE_MORE_ITEM][FoundationTests] RESULT suites=15 tests=69 passed=69 failed=0 duration=0.356362s fuzzCases=1000 fuzzSeed=24012026
[ONE_MORE_ITEM][FoundationTests] PASS: all 69 tests passed
[ONE_MORE_ITEM][Phase02Tests] RESULT suites=11 tests=94 passed=94 failed=0 duration=6.942747s seed=24022026
[ONE_MORE_ITEM][Phase02Tests] PASS: all 94 tests passed
[ONE_MORE_ITEM][Phase03Tests] RESULT suites=8 tests=65 passed=65 failed=0 duration=0.005859s seed=13072026
[ONE_MORE_ITEM][Phase03Tests] PASS: all 65 tests passed
```

Phase 03 distribution: input mode store 6; responsive classification 5; responsive geometry 9; touch tracking 7; gamepad repeat/action routing 17; prompts 4; camera targeting 5; control cleanup/remote discipline 12.

## Responsive and permanent-property proof

- The static layout matrix covers 13 required desktop, phone, and tablet viewports across five representative safe-inset profiles, for 65 safe-containment cases.
- Exact Studio property audit after reopen:
  - ScreenGui: `DeviceSafeInsets`, `ClipToDeviceSafeArea=true`, `SafeAreaCompatibility.None`, `IgnoreGuiInset=true`.
  - Touch drag surface remained authored and full-root.
  - Rotate, Place, Ship, One More, and Pack Again remained selectable with authored disabled/transparent `Thickness=3` Border focus strokes.
  - Authored minimums remained `72 × 44` for four actions and `120 × 44` for Pack Again.
  - Both responsive camera anchors remained exact, anchored, invisible, non-colliding, non-queryable, non-touching, and script-free.

## Manual Play acceptance

All manual evidence below was recorded in Roblox Studio `0.729.0.7290838`. Desktop and automated suites used Play; touch and orientation used Play with Device Emulator; gamepad and hybrid checks used Play with Controller Emulator; two-player checks used Local Server with two players; cloud persistence used Edit mode after a direct cloud reopen.

| Gate | Result |
| --- | --- |
| Desktop round | **Passed.** Verified timeout failure, Pack Again, keyboard placement, deliberate One More, completed shipment, `+15 TAPE`, `SESSION 15 TAPE`, Results, and another Pack Again. |
| Touch six-profile matrix | **Accepted.** iPhone 7 portrait `373×666`, iPhone 16 portrait `392×758`, iPhone 7 landscape `665×374`, iPhone 13 landscape `749×368`, iPad 6 portrait `767×1022`, and iPad 6 landscape `1022×767` passed safe-area, camera, default-control, center/corner mapping, drag/release, multi-rotation Chair, Place, both Ship and One More, failure, Results, Pack Again, and cleanup checks. Physical simultaneous multi-touch: Deferred to later physical-device QA. |
| Touch coordinate mapping | **Passed in all six profiles.** Center `2,2`; rear-left `0,0`; rear-right `4,0`; front-left `0,4`; front-right `4,4`. Release returned `ActivePlacementTouch=false` and never placed. |
| Orientation | **Passed for one phone and one tablet.** RoundId, StateVersion, RoundState, item, count, bank, and logical ghost position were preserved; coordinate mapping remained correct; camera retargeted; `LayoutTweens` returned to zero. |
| Earlier focused gamepad evidence | **Partial historical evidence.** Prior acceptance checks recorded prompts, bindings, portions of D-pad/stick/placement/focus/One More/Pack Again behavior, and a pre-correction inert Button B observation. Those focused observations do not replace the required uninterrupted final A-J trace. |
| Full controller flow | **Pending.** The final Generic Gamepad trace proved connection, exactly three bindings, safe Results/Pack Again focus, one restart, disconnect cleanup, reconnect with three rather than six bindings, and mode exit. It did not complete A-J: all-direction D-pad proof, held-stick deadzone/repeat/direction/diagonal timing, Button X and outside-state negatives, exact placement/Ship/One More/Button B request traces, or Decision-state reconnect remain open. |
| Hybrid switch | **Pending.** Individual Gamepad, Touch, and KeyboardMouse transitions were observed with cleanup, but Studio automation did not complete one uninterrupted keyboard → gamepad → touch → keyboard gameplay round with the required state/reward/request trace. |
| Two-player owner/spectator | **Partial.** Earlier Local Server evidence covers portions of identity, camera/reward isolation, respawn, release, spectator continuity, and later acquisition. The required fresh final two-player regression, full owner gameplay, spectator action-denial matrix, respawn controls, release cleanup, and later-owner verification were not completed in this pass. |
| Ten mixed-input rounds | **Pending.** Exploratory rounds and timeouts did not satisfy the prescribed ten-round distribution, baseline/final metrics, or post-soak duplicate-handler checks. |
| Physical phone | **Not tested.** Studio device emulation was used. |
| Physical controller | **Not tested.** Studio controller emulation was used. |

The final attempt did not edit Controller Emulator mappings. The emulator panel was closed after the trace, and the transient acceptance probe was removed from Edit mode before the final suites.

## Cloud persistence

- An external recovery `.rbxl` copy was created outside Git and verified at 181,185 bytes.
- Studio reported `Saved new changes in "ONE MORE ITEM!" to Roblox.` for the original private place (`PlaceId 134193642444044`, `GameId 10493030248`).
- Every Studio process was closed. One clean Studio process reopened the place directly from Roblox without source synchronization.
- Because Studio-managed sources changed, both canonical synchronization paths were run twice before save. The no-resync hierarchy/source/remote audit then passed `180/180` paths, `44/44` sources, exactly six canonical remotes, and zero duplicate paths.
- The final direct-cloud reopen connected normally on the helper/plugin route in Edit mode with the authoritative PlaceId/GameId. No post-reopen synchronization was run.

A historical reconnect accepted Team Create transport but never received a join snapshot and returned `RCC-277`. The final corrected save/reopen succeeded normally, so RCC-277 is not a current persistence blocker. No divergent Studio-only script was created.

## Output and diagnostics

- The final clean Play run passed all three Studio suites and produced zero fresh game-owned warnings/errors.
- The final post-probe baseline at 2026-07-14 15:31 UTC returned zero fresh actionable Output errors or warnings. The transient probe was absent from the Edit hierarchy before this run.
- The post-correction two-client startup logged `[ONE_MORE_ITEM][Station] user=-2 is spectator reason=NO_STATION` as `MessageOutput`, not a warning. The only observed errors/warnings were unrelated Studio plugin-icon or bridge-rate noise.

## Known issues and remaining gates

- Physical simultaneous multi-touch: Deferred to later physical-device QA. The deterministic single-active-touch contract and accepted six-profile matrix are no longer Phase 03 merge blockers.
- The complete controller-only A-J session remains pending, including held-repeat timing, stick direction-change/diagonal/tie behavior, multi-rotation Button X, outside-state negatives, exact placement/Ship/One More/Button B traces, and Decision-state disconnect/reconnect.
- The uninterrupted hybrid round, fresh two-player owner/spectator regression, and prescribed ten-round cleanup/duplicate-handler soak remain pending.
- Physical phone and physical controller testing were not performed. Studio emulation was used.
- Exact status-only-head equality and checks are a handoff-time Git/GitHub observation rather than a remaining Phase 03 product gate; the completion report records them from live state.

## Deferred by design

Seven additional stations, the full launch arena/dispatch presentation, final models/assets/audio/VFX, haptics, persistent Tape/DataStores, progression, collection, challenges, missions, cosmetics, store/monetization, analytics, social systems, trading, pets, rebirths, multiple worlds, co-op, camera orbit, and every Phase 04 system remain deferred.

## Exact next phase recommendation

Finish only the outstanding controller-only A-J, uninterrupted hybrid, fresh two-player, and prescribed ten-round cleanup gates. Keep PR #3 draft and unmerged; it is not ready for final review yet. After Phase 03 is fully accepted, reviewed, and later merged by explicit authorization, **Phase 04 is the only recommended next phase**. Do not begin Phase 04 now.
