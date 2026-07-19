# Phase 07 - Visual Readability and Arena Art-Direction Rebuild

## Status and acceptance boundary

**Active and unaccepted.** Phase 07 is isolated on `codex/phase-07-visual-readability-arena-rebuild`, based on the accepted Phase 06 squash merge `4c606ae4f5e7a5e3d5fa431775c94469ecea1b67`. [PR #8](https://github.com/kotonja/ONE-MORE-ITEM-/pull/8) remains open, draft, and unmerged. The latest committed Phase 07 implementation head observed while this document was prepared is `a057cbb7fd23cb16f387142dec3e988efa213247`; later documentation commits must be recorded in `docs/DEVELOPMENT_STATUS.md` and the PR because a commit cannot contain its own SHA.

This document records the reconstruction contract and the current evidence boundary. The implementation head has fresh seven-gate Node, seven-suite synchronized-Studio, deterministic camera/line-of-sight, double-authoring, targeted manual visual checks, exact-head Actions, normal cloud publish, complete Studio close, direct no-sync cloud reopen, and final parity. It does **not** claim final live visual acceptance, a complete accepted screenshot set, or an accepted continuous recording. Phase 07 remains unaccepted until those remaining evidence gates pass together on the final candidate. Passing configuration, deterministic tests, or persistence parity cannot substitute for visibly readable gameplay.

[Issue #4](https://github.com/kotonja/ONE-MORE-ITEM-/issues/4) remains open. Its Phase 07 QA comment is not due until Phase 07 acceptance and has not been represented as posted.

## Scope and protected behavior

Phase 07 is a presentation reconstruction only. It may recompose permanent world geometry, UI geometry, station cameras, lighting, post-processing, labels, and local visual motion. It preserves:

- the exact `5 x 5 x 4` integer crate and two-stud cells;
- all item shapes, offer fairness, timer values, rewards, multipliers, progression, profile Schema Version 2, and existing DataStore names;
- eight deterministic stations at 45-degree intervals and the existing server-authoritative allocation and round boundaries;
- the six gameplay remotes, one server-to-client profile remote, and one narrowly validated onboarding request remote;
- the deterministic 16-node showcase path, queue limits, reward behavior, and cleanup ownership;
- the accepted onboarding, starter-mission, collection, input, persistence, and analytics semantics from Phases 01-06.

No new gameplay system, progression, currency, mission, catalog object, final model, external asset, image, sound, music, particle system, monetization, store, leaderboard, experiment, or Phase 08 system belongs in this phase.

## Recording-derived defects and correction contract

The authoritative recording exposed defects that static validation could not waive. The table below records the correction target; every row still needs final visual evidence.

| Recording-derived defect | Required correction | Current acceptance state |
| --- | --- | --- |
| The opening view exposed an overexposed yellow surface, empty sky, and an uncontrolled avatar camera before settling. | An authored opaque first-frame curtain and immediate Scriptable camera handoff must hide the world until a safe profile/waiting state and camera target exist. | Pending final opening-sequence evidence. |
| A large black console/front structure occupied roughly the lower half of the view. | Lower and shrink the matte console, replace the front sheet with a low rim, and prove neither overlaps the projected interior or camera-to-cell rays. | Pending final projection and live evidence. |
| The low camera, dark/reflective panes, floor treatment, frame, and lighting made cell depth and occupied layers difficult to read. | Use the approved high downward framing, an open front, non-refractive panes, warm opaque floor, individual grid seams, thin frame, and restrained task light. | Pending final desktop, touch, and Station_05 evidence. |
| Placement, resting height, valid/invalid feedback, and the four-cell vertical capacity were unclear. | Keep the full floor and layer-three capacity visible; preserve the outlined local ghost and readable contact/grounding cues. | Pending final packing matrix. |
| Shipping read as a green slab over a dark slab. | Keep packed contents visible while the authored lid closes, delay green confirmation until closure, and retain the physical result during early Results. | Pending final shipping evidence. |
| Failure read mostly as a red panel because the impact and burst were hidden. | Show the closure attempt and impact, keep the open front, expose the burst, then apply one restrained red edge treatment and Results. | Pending final failure evidence. |
| Giant yellow Neon station surfaces clipped into featureless brightness. | Use the semantic palette and restrict Neon to small meaningful accents under restrained exposure and bloom. | Pending final arena/exposure evidence. |
| The arena read as a square Baseplate test rig with repeated debug bays, weak dispatch, and no shell. | Rebuild a circular/octagonal toy-industrial warehouse, separate eight bays on a wider ring, enclose normal views, and make dispatch the landmark. | Pending final Edit-mode and multiplayer evidence. |
| World-space text competed with the HUD. | Apply local/adjacent/distant label tiers, finite distances, `AlwaysOnTop = false`, and one central announcement plus one server-best board. | Pending final four-client evidence. |
| The top HUD was dense and the mission/profile surfaces competed with gameplay. | Reduce persistent chrome, rebalance existing authored panels, preserve safe areas, and keep the crate rectangle free. | Pending the full viewport/non-overlap matrix and live review. |
| Collection shelves read as debug geometry. | Retain deterministic featured-item logic while presenting compact authored display cases with integrated nearby labels and at most six geometric proxies. | Pending final shelf evidence. |

## Visual hierarchy and semantic palette

The crate is the dominant object in every active gameplay view. The station frames the crate; the arena supplies context; dispatch is the shared landmark; labels and HUD communicate only information that cannot be read directly from the world. Negative space is intentional. No avatar, console, panel, label, shelf, neighbor station, shell piece, or dispatch element may cover the active packing volume.

`VisualThemeDefinitions` centralizes the following semantic targets for world and screen presentation:

| Role | Color | Use |
| --- | --- | --- |
| Background | `#0A0F16` | Upper void and low-detail backdrop |
| StructuralGraphite | `#151E28` | Primary structure |
| SecondarySteel | `#22303D` | Secondary structure |
| Concrete | `#2A3038` | Sealed arena surfaces |
| RubberDark | `#10161D` | Recesses and quiet controls |
| CrateWarm | `#8B6A42` | Crate structure |
| CrateFloor | `#6E5C46` | Warm matte interior floor |
| TextPrimary | `#F5F7FA` | Primary copy |
| TextSecondary | `#A7B5C4` | Supporting copy |
| Cyan | `#22D3E6` | Navigation and station identity |
| Amber | `#FFB21A` | Shipping and reward |
| Green | `#63E85C` | Valid and successful state only |
| Red | `#FF4B3E` | Invalid, risk, and failure state only |
| Purple | `#9B6CFF` | Collection and mastery |

Semantic colors are not general decoration. Green and red remain reserved for state, amber for shipping/reward, purple for collection/mastery, and cyan for navigation/station identity. Uncontrolled rainbow styling is rejected.

## Canonical ownership and permanent hierarchy

Canonical Luau remains under `src/`. The historically named `studio/phase02.manifest.json` remains the sole canonical owner for permanent Phase 02-07 UI, remotes, templates, arena content, station content, lighting, post-processing, and mapped scripts. Phase 07 safely extends managed roots to `ReplicatedFirst` and `Lighting`; it does not introduce a competing manifest.

Permanent content exists before Play, including the first-frame curtain, gameplay arrival curtain, camera anchors, crate/frame/grid, console, bay structures, shell, dispatch, showcase supports, world signs, UI, lighting, bloom, and color correction. Runtime code may bind and animate those authored instances and may create only already-authorized temporary gameplay/cosmetic objects. Wrong-class conflicts remain visible and non-destructive, and repeated authoring must remain deterministic and duplicate-free.

The focused presentation sources are:

- `VisualThemeDefinitions`: immutable semantic colors and presentation values;
- `VisualFraming`: pure projection, safe-viewport, bounds, pitch, occupancy, and line-of-sight calculations with no instance lookup;
- `FirstFrameHandoffPolicy`: pure state for the ReplicatedFirst-to-gameplay curtain transfer;
- `FirstFrameBootstrap`: immediate pre-game curtain and covered minimum-hold handoff;
- `ArrivalCurtainController`: profile/waiting state copy, camera-readiness gating, fade, and cleanup;
- `CameraController`: authored responsive station targets and bounded local impulses;
- `WorldLabelController`: station-relative visibility tiers without a permanent per-frame loop;
- `ResponsiveLayout` and `ProfileResponsiveLayout`: scale-based safe-area geometry;
- `WorldMotionController`: temporary shipping, failure, and reset presentation around the accepted state machine.

These presentation modules add no server authority and send no new gameplay request.

## Controlled first visible frame

The authored curtain starts opaque with a charcoal background, `ONE MORE ITEM!`, `PACK THE BOX`, `LOADING PROFILE`, and one restrained cyan accent. No external image, spinner, tutorial, monetization, or permanent idle animation is used.

Before revealing the world, the camera must already be Scriptable at a safe arrival CFrame, the known profile/waiting state must be valid, and an assigned station's selected anchor and focus must be resolved. The curtain reports `LOADING PROFILE`, `DATA UNAVAILABLE`, or `PROFILE OPEN ELSEWHERE` honestly. Ready assigned players reveal only after camera readiness; Ready waiting players transition to the waiting presentation without an invalid station camera. The target fade is `0.22-0.28` seconds. Respawn must not replay the complete join sequence unless a short local safety fade is required. Cleanup cancels every tween and connection, sends no server request, and owns no permanent render-step loop.

## Camera and projection contract

`VisualFraming` supplies deterministic fixtures; authored anchors supply the actual transforms. The final camera must satisfy:

- FOV `48-52` degrees and downward angle approximately `50-58` degrees;
- horizontal crate-interior center within `46-54%` of the safe viewport and generally within `+/-4%` of its usable center;
- vertical crate-interior center within `43-61%` of the safe viewport;
- at 1920 x 1080 and 1366 x 768, interior width `42-58%` and height `36-56%` of the safe viewport;
- at touch portrait, crate width generally `72-88%` of safe width;
- at touch landscape, crate width generally `44-62%` and height `50-72%` of safe dimensions;
- front-rim projected overlap below `8%` of interior height;
- complete crate visibility at 1100 x 700, with top cards above and actions below it;
- stable framing during ordinary grid movement, no orbit, and no uncontrolled snap.

Station_01, Station_03, Station_05, and Station_07 require explicit projection checks, with Station_05 treated as the opposite-side proof. Desktop, phone portrait, phone landscape, and tablet safe-area profiles must all keep primary cells and actions unobstructed.

For every gameplay anchor, deterministic rays target all 25 layer-zero centers, four upper-layer corner centers, `CrateFocus`, `GridOrigin`, and the current ghost center. Only compliant transparent side/back panes may intersect those rays. The console, front rim, stand, sign, shelf, labels, light support, neighboring station, shell, and center dispatch may not.

The current authored candidate uses FOV `48`. Relative to each rotated station frame, its desktop camera is at approximately `(0, 19.2659, 9.2203)` with `55.6` degrees downward pitch; touch landscape is at `(0, 16.2375, 8.7548)` with approximately `50.0` degrees pitch; touch portrait is at `(0, 28.4608, 18.9810)` with approximately `50.0` degrees pitch. The Phase 07 Studio suite passed the deterministic projection fixtures and all `768/768` line-of-sight rays (`32` samples x eight stations x three anchor profiles). Exact 1100x700, touch portrait, touch landscape, legitimate Station_05 pointer/Place/Ship, and Station_03/07 clearance spot checks passed. The accepted 1920x1080 evidence replacement, documented 1366x768 final review, and complete avatar/UI obstruction evidence remain pending.

## Crate, panes, grid, and item presentation

The logical interior stays exactly `10 x 10 x 8` studs, `5 x 5 x 4` cells, with two-stud cells and unchanged `GridOrigin` semantics.

- `WallFront` is a low solid rim, no more than about `0.55` studs above the floor and `0.24` studs thick. There is no full front sheet during packing.
- Side and rear panes use thin `SmoothPlastic`, light desaturated cyan-gray, transparency `0.55-0.72`, `CastShadow = false`, and no collision/touch/query unless a documented local query is required. `Enum.Material.Glass`, refractive duplication, and stacked surfaces are rejected.
- The warm matte opaque interior floor has no Neon. All 25 tiles are individually legible; tile size is approximately `1.82-1.86` studs inside each two-stud cell, with a restrained seam and no continuous full-floor glow.
- The graphite frame uses thin posts and rails, generally `0.18-0.28` studs thick, and places no member through the active viewing angle.
- One restrained warm task light per station targets approximately RGB `255,231,194`, brightness `1.3-1.7`, and range `16-20` studs without per-frame updates or a camera-blocking fixture.
- The raised lid remains thin, mechanical, and camera-clear. It provides state feedback without becoming a luminous plane.
- Development cell proxies stay opaque, non-reflective, slightly smaller than a cell, and separated by clean seams. No final object model is introduced.
- Placed items preserve exact occupied cells and station isolation. The local ghost retains a readable outline, transparent body, green/red validity, and clear resting-height treatment without per-cell highlights or constant pulsing.

## Console and station bays

The matte graphite console frames the box rather than dominating it. It remains approximately no wider than `8.5` studs or deeper than `3.2` studs; its top reads roughly `0.35-0.55` studs below the visible floor plane and intersects no approved camera ray. Physical Rotate, Place, Ship, and One More buttons remain recognizable with small semantic accents and unchanged actions.

Eight visually equal bays remain at 45-degree intervals on an approximately 50-stud ring, each facing center. Target bay width is about 20 studs, depth `17-19` studs, and elevation `0.35-0.55` studs above the arena floor, with at least about four studs of clear separation between adjacent footprints. Each bay contains its station platform, crate, low console, stand, compact collection shelf, integrated owner/status sign, small risk indicator, task-light support, restrained station number, and clear boundary. Presentation may differ only by orientation and identity; gameplay does not.

The risk indicator is a compact strip or stack: off below six items, amber at six/seven, red at eight/nine, and gold at ten. It has no sphere larger than about `1.2` studs, bloom halo, rapid flashing, or camera obstruction. Shelves remain compact authored cases with three to six pedestal positions, integrated nearby rank/count labels, and at most six temporary geometric proxies.

## Arena shell, dispatch, and showcase route

The target is a circular/octagonal toy-industrial game-show warehouse, not a square Baseplate composition:

- raised arena floor diameter approximately `128-136` studs;
- station ring radius approximately `50` studs;
- outer shell radius approximately `70-76` studs and height `28-34` studs;
- center dispatch diameter approximately `18-20` studs;
- showcase loop radius approximately `27-30` studs and height `18-21` studs.

The authored shell uses a circular or 16-sided sealed-concrete floor, inner metal ring, radial bay seams, 16 wall segments, eight major supports, a ceiling ring, partial rafters/light rig, controlled entrance, dark upper treatment, and restrained text-only branding. Normal station views must not expose open blue sky or a default Baseplate horizon. Shell pieces may not intersect camera paths.

Center dispatch is the arena landmark: a circular/octagonal base, lift, lift top, mechanical column, amber inset routes, showcase entry, supports, one integrated announcement, and one server-best board. It remains visible from every station while staying camera-clear and independent of gameplay collision. The existing deterministic 16-node showcase path and service limits remain unchanged; only its authored composition may move to fit the arena. It stays above players, clear of anchors and shell supports, visually linked to dispatch, and secondary during packing.

## Lighting, bloom, and Neon policy

The current source-controlled Lighting configuration is Future technology, brightness `2.0`, clock time `14.5`, exposure `-0.25`, ambient RGB `28,35,45`, outdoor ambient RGB `20,25,32`, diffuse scale `0.35`, specular scale `0.55`, global shadows enabled, and shadow softness `0.35`.

The single authored BloomEffect uses intensity `0.14`, size `16`, and threshold `1.45`. The single authored ColorCorrectionEffect uses contrast `0.09`, saturation `-0.07`, brightness `-0.02`, and tint RGB `255,249,242`. Gameplay uses no enabled depth-of-field blur, motion blur, per-frame lighting change, or global strobe. Deterministic configuration checks pass, but final visible exposure/contrast review on the required device profiles and direct cloud reopen remains pending.

Neon is an accent, not construction material. Small station edges, buttons, risk indicators, dispatch routes, branding accents, and state lights are allowed. Entire floors, console decks, crate surfaces, walls, yellow rectangles, giant spheres, and arena-wide borders are rejected unless a specifically documented allowlist proves safe area and exposure.

## World-label policy

The local station may show player name, station number, one short status, relevant risk, and compact shelf rank/count. Adjacent stations may show station number plus a short owner/status. Distant stations show only station number or nothing. Distant risk, full rank, collection count, long status, rewards, and detailed owner data remain hidden.

World Billboards use finite `MaxDistance`, restrained `LightInfluence`, and `AlwaysOnTop = false` unless a documented exception exists. They cannot render through walls, cover the crate, or compete with screen UI. `WorldLabelController` reacts to assignment and meaningful camera/responsive changes, cleans every connection, creates no permanent UI, sends no remote, and does not own a full per-frame loop. A meaningful-change throttle may run no faster than roughly 2 Hz.

## Screen UI hierarchy

Phase 07 recomposes the existing authored HUD; it does not create a new UI system or change behavior.

- Top left: compact Tape.
- Top center: rank and thin XP progress.
- Top right: Collection plus quiet healthy save state; Loading, SaveDelayed, Unavailable, and Conflict may expand honestly.
- Upper left/right: balanced Current Item/timer and Shipment value/count/multiplier cards.
- Lower left or left-middle: compact current Starter Mission card, generally below `12%` of safe viewport area.
- Bottom center: PlacementControls or DecisionPanel.
- Center: Results only while active.
- Upper middle: compact onboarding guidance, never over crate center.

MetaBar density targets a `25-35%` reduction, generally no more than about 64 pixels at 1920 x 1080 and 54-58 pixels at 1366 x 768. Collection retains all eight slots. Decision/Results behavior and semantic Ship amber, One More controlled red, and Pack Again priority remain intact.

The documented Z-order is world labels below screen UI; gameplay `10-19`; profile/meta `20-29`; decision/results `30-39`; onboarding/mission completion `40-49`; arrival curtain `100`. Modal Collection and Starter Path panels continue to suppress underlying gameplay inputs. The full desktop, phone, landscape, portrait, and tablet matrix must prove safe containment, readable text, active-panel separation, and no primary-cell or action obstruction.

## Shipping, failure, and reset presentation

Shipping preserves the accepted authority and timing. Visible contents remain during lid descent; the open front stays readable; amber input acknowledgement precedes green success after closure; the camera may ease back slightly; the physical shipment remains during early Results; and the temporary showcase transfer follows the dispatch direction.

Failure likewise preserves authority. The contents and attempted lid contact remain visible, followed by a short pause, the existing burst through the open front, one restrained red edge flash, `TOO MUCH!`, readable Results, prompt Pack Again, and exact cleanup.

Reset raises the lid visibly, immediately restores the readable interior, uses only a restrained cyan sweep, clears stale success/failure/debris state, avoids a camera snap, and begins with a visibly clean crate.

## Performance budget

The final accepted candidate must record exact permanent counts. New environment geometry should generally stay below about 350 additional permanent BaseParts unless justified. Dynamic lights target about 20 or fewer, with shadow-casting lights used sparingly. Phase 07 adds no particles, scripts inside decorative Parts, physics-driven environment, per-station frame loop, per-label frame loop, per-frame full-Workspace scan, or one-connection-per-decoration system. Transparent panes and Neon accents generally do not cast shadows.

The current generated candidate contains 1,453 combined managed paths, 97 managed sources, and 824 permanent BaseParts, a `+346` visual-Part delta from the accepted Phase 06 generated tree. It contains 20 PointLights, including eight station task lights, and zero shadow-casting dynamic lights. The deterministic material scan finds zero `Enum.Material.Glass` descendants under any gameplay station `Crate`; four Glass walls remain only in the off-world development `ShowcaseCrateTemplate` and are not gameplay panes. Eighty managed Neon Parts remain as small accents, with a maximum second-largest dimension of `0.9` studs and no giant-surface allowlist. These counts are not by themselves a low-end-device performance claim.

## Automated and manual evidence ledger

The current implementation head passed all seven dependency-free Node 24 gates:

```text
[StudioSyncSmoke] PASS checks=16 folders=7 scripts=10 deterministic=true
[Phase02StudioSyncSmoke] PASS criteria=28 instances=1355 scripts=87 remotes=6 deterministic=true phase01=true
[Phase03CrossPlatformSmoke] PASS criteria=31 viewports=13 insetProfiles=5 layoutCases=65 remotes=6 deterministic=true phase01=true phase02=true
[Phase04MultiplayerArena] PASS criteria=42 instances=1355 scripts=87 stations=8 pathNodes=16 remotes=6 deterministic=true prior=true
[Phase05PersistentProgression] PASS criteria=64 instances=1355 scripts=87 gameplayRemotes=6 profileRemotes=1 shelves=8 collectionSlots=8 deterministic=true prior=true
[Phase06OnboardingMissionsAnalytics] PASS criteria=76 instances=1355 scripts=87 gameplayRemotes=6 profileRemotes=1 onboardingRemotes=1 onboardingSteps=5 starterMissions=5 missionTape=295 missionXP=210 deterministic=true prior=true
[Phase07VisualReadability] PASS criteria=160 instances=1355 scripts=87 stations=8 losRays=768 pointLights=20 deterministic=true prior=true
```

The final directly reopened place produced this fresh seven-suite run without post-reopen synchronization:

| Suite | Current result | Deterministic detail |
| --- | ---: | --- |
| Foundation | `69/69` | 15 suites; seed `24012026`; 1,000 fuzz cases; `0.333691s` |
| Phase 02 | `94/94` | 11 suites; seed `24022026`; `6.775828s` |
| Phase 03 | `65/65` | 8 suites; seed `13072026`; `0.007074s` |
| Phase 04 | `119/119` | 13 suites; seed `14072026`; `3.483551s` |
| Phase 05 | `130/130` | 16 suites; seed `15072026`; memory adapter; `0.553133s` |
| Phase 06 | `75/75` | 18 suites; seed `16072026`; profile/analytics memory adapters; `0.036370s` |
| Phase 07 | `64/64` | 12 suites; seed `17072026`; 768 LOS rays; `1.654351s` |

Implementation-head GitHub Actions also passed: push run `29662807404` / job `88128209680` and draft-PR run `29662808244` / job `88128211869`, with all seven Node steps successful. A later documentation head requires fresh exact-head Actions evidence.

The direct-reopen Studio run reported no fresh game-owned warning or error. The remaining visual ledger is:

| Gate | Current Phase 07 state |
| --- | --- |
| Opening sequence | First-frame curtain and controlled arrival passed; the accepted recording must retain the sequence. |
| Desktop 1920 x 1080 and 1366 x 768 | Both final visual checks passed. |
| Narrow desktop 1100 x 700 | Exact-size visual spot check passed. |
| Touch portrait and landscape | Both required Phase 07 emulator spot checks passed; no physical-phone result is claimed. |
| Station_05 opposite-side view | Legitimate assignment, opposite-side camera, pointer, Place, and Ship passed; Station_03/07 clearance also passed. |
| Four-client arena and label tiers | Exact four-client cold-start assignment and four distinct occupied bays passed; the final evidence image must show that state more clearly. |
| Shipping, failure, reset, Collection, and Starter Path | Individual live checks passed; one complete accepted continuous flow remains required. |
| Edit-mode top-down, entrance, ring, dispatch, loop, and shelf inspection | All required inspection angles passed; the accepted recording must retain the flyover and Station_05 view. |
| Post-publish seven suites and clean Output | Passed after normal publish, verified zero-process close, and direct no-sync reopen. |

The required 15 screenshots and one unedited continuous recording of approximately 3-6 minutes must remain outside Git. No complete accepted set is claimed by this document. Thirteen screenshot frames are usable; frame 12 must clearly prove the four-client arena and frame 15 must show the physical authored collection shelf. Existing recordings are explicitly rejected because none contains all 13 required moments. The user is supplying the replacement continuous recording. Rejected material remains recovery-only and may not be counted toward acceptance.

## Canonical synchronization and cloud persistence

With all three Phase 05 acceptance-fixture attributes absent, the current candidate applied Phase 01 and the extended Phase 02-07 authoring twice in one Studio session. Phase 01 reused all 17 operations on both passes with zero creation, update, warning, backup, or failure. Each extended pass updated 1,443 operations, preserved 87 script backups, created nothing, failed nothing, and emitted one expected protected-property warning because the authoring context lacks `RobloxScript` capability for `Lighting.Technology`; the manifest remains the source of the Future intent.

The synchronized audit and one later direct no-sync read-only reopen audit each matched 1,453 expected managed paths against 1,454 unique live paths, with only the allowlisted unmanaged `Workspace.Baseplate.Texture` extra and zero missing, duplicate, or wrong-class paths. All 97 sources matched exactly. Of 9,512 declared managed properties, the bridge exposed and matched 7,813; 1,699 were not exposed and are not claimed as independently read back. All 94 authored-attribute targets and 152 keys matched with zero mismatch. The no-sync audit targeted the original PlaceId `134193642444044` and GameId `10493030248`.

The final persistence sequence passed: Studio published normally to the original private cloud place with all Phase 05 fixture attributes absent, every Studio process closed to a verified zero count, and the correct original place reopened directly from Roblox. No synchronization occurred after reopen. The reopened place passed one successful round, one failure, all seven suites, clean Output, and the parity counts above.

Canonical double synchronization, normal cloud publish, full close, post-publish direct reopen, and final post-reopen parity are green. These persistence results do not waive the remaining external visual-evidence gates.

## Known limitations and deferred pre-release QA

Final object models, external assets, textures, images, sounds, music, final particles/VFX, and haptics remain deferred by design. Geometric development proxies remain intentional Phase 07 placeholders.

After Phase 07 acceptance, issue #4 should receive one concise `Phase 07 visual and arena QA additions` comment retaining physical-phone readability, physical-controller flow, low-end lighting/transparency, color-vision review, eight-player label/showcase observation, long-session camera/label cleanup, production screenshot/thumbnail review, final model/audio/VFX integration, final art consistency, public-beta feedback, and production-device bloom/exposure as explicitly unpassed pre-release QA. The issue must remain open. Those future checks are not implementation substitutes and are not claimed as passed.

## Exact next step

Complete and verify Phase 07 only on `codex/phase-07-visual-readability-arena-rebuild`, keep PR #8 draft and unmerged, preserve issue #4, and do not begin Phase 08.
