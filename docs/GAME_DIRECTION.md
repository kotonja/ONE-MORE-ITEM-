# Game direction

ONE MORE ITEM! — PACK THE BOX is a mobile-first Roblox packing game targeting a premium visual bar. The core promise is: **Fit it. Ship it. Or risk one more.**

## Frozen foundation

- The crate is exactly 5 cells wide, 5 cells deep, and 4 cells high: 100 integer cells.
- Packing uses a zero-based snap grid. World-space physics and floating-point transforms are not gameplay authority.
- Items are irregular sets of unique integer cells.
- Rotation is allowed only around the vertical Y axis in 90-degree increments.
- The player does not move an item vertically. A rigid item enters from above and auto-drops one integer layer at a time to its lowest reachable position.
- Rigid bridging and overhang are valid, but an item may never teleport through an upper obstruction into a cavity.
- A future “One More” offer is fair only when the item has at least one enumerated legal placement. Zero-placement candidates are never offerable.
- Future placement decisions remain server-authoritative.

## Permanent authoring direction

- Permanent gameplay UI is authored as actual `StarterGui` instances. The permanent pre-game first-frame curtain is authored under `ReplicatedFirst`; neither surface is generated wholesale at runtime.
- The permanent arena and stations are authored as actual `Workspace` instances, never generated at runtime.
- Permanent environment lighting and post-processing are authored under `Lighting`, never synthesized by gameplay scripts.
- Temporary ghosts, cloned active items, particles, debris, beams, tokens, and showcase copies may be created at runtime from prepared templates.

Phase 01 contains only the mathematical grid foundation, its development shapes, automated tests, and documentation.

## Phase 02 controlled vertical slice

Phase 02 adds exactly one authored packing station and the minimum permanent HUD, networking, desktop controls, server-authoritative round loop, session-only Tape, and temporary blockout presentation needed to prove the core promise. It does not expand into the eight-player launch arena, persistent progression/economy, mobile/gamepad support, final assets, audio, monetization, or later-phase systems.

## Phase 03 cross-platform interaction

Phase 03 keeps the same one-station round and adapts only its local interaction and presentation for keyboard/mouse, touch phones and tablets, gamepads, and hybrid devices. Responsive classes follow viewport geometry, while `PreferredInput` controls local routing, prompts, and safe focus. Authored safe-area UI and responsive camera anchors preserve the crate as the focal point without creating permanent content at runtime.

Touch drag, gamepad cell movement, rotation, layout, prompts, focus, and camera state remain local prediction. Place, decision, and restart continue through the existing server-authoritative requests; Phase 03 adds no gameplay remote and does not weaken station ownership, grid validation, timing, or Tape authority.

At Phase 03 acceptance, the eight-player arena, persistent progression, final assets, social systems, and monetization remained deferred. Phase 04 subsequently completed the permanent multiplayer arena without weakening this authority boundary.

## Phase 04 multiplayer arena

Phase 04 expands the authored world to eight independent packing stations around one shared presentation arena. Station ownership, rounds, placement, cleanup, shipment capture, and the FIFO waiting queue remain server authoritative. The shared showcase is cosmetic: queue overflow or rendering failure cannot remove a valid shipment reward. Phase 04 preserves the same six gameplay remotes and adds no persistence or monetization.

## Phase 05 persistent player ownership

Phase 05 gives each player a safe server-owned profile whose canonical values are Tape, Packing XP, collection discovery/mastery, bounded processed-outcome receipts, and honest statistics. Rank and mastery tiers are deterministic status, not power. Nothing in persistent progression changes item value, placement fit, round fairness, or the decision to risk one more.

Profile availability is part of gameplay integrity. A profile must load and own its server lock before station assignment; unavailable or conflicting data cannot enter a reward-bearing round. Successful and failed outcomes use globally unique server-created IDs so rewards cannot apply twice. Save delay is shown honestly and never converted into a sales prompt.

Collection presentation reinforces the packing fantasy without obscuring the crate: a compact authored MetaBar, an optional safe-area collection panel, focused discovery/rank reveals, and one small deterministic shelf per owned station. Phase 05 uses the eight development items and geometric proxies only. It introduces no final object models, external assets, functional bonuses, store, Robux product, leaderboard, social system, or Phase 06 feature.

Studio and production profile data remain strictly separated. Normal Studio persistence uses the Studio-test store; controlled Unavailable, SaveDelayed, and Conflict acceptance fixtures use only an injected in-memory adapter and must be cleared before normal persistence or saving. Phase 05 ultimately passed its deterministic coverage, real Studio-test persistence sessions, cloud save, complete close, direct no-sync reopen, source parity, and focused Studio-emulator Collection checks, then squash-merged through PR #6 at `d644411b48e20cd9bb256d3d2c55a647efc2adfd`. Physical-device and production-store checks remain visible in issue #4 and are not represented as passed.

## Phase 06 first-session retention foundation

Phase 06 adds a compact contextual first-time-player experience, five fixed starter missions, and a server-only analytics boundary without changing the deterministic packing rules. Durable onboarding advances from profile readiness, station assignment, accepted placement, the first decision, and a successful first shipment. Incomplete onboarding receives only longer first-round decision windows; completion or deliberate skip is persistent, terminal, and reward-free.

Starter missions observe authoritative placement, decision, shipment, discovery, and shipment-size state. Their fixed Tape and Packing XP rewards apply atomically and exactly once through the existing profile mutation boundary. The client can request only tutorial skip through one narrowly validated remote; it cannot submit progress, mission completion, rewards, balances, rank, or profile values.

Permanent onboarding and mission surfaces remain authored under `StarterGui`, adapt to keyboard/mouse, touch, and gamepad, and leave the crate and core controls unobstructed. Studio uses a deterministic memory analytics adapter that makes no Roblox analytics call; published non-Studio servers use current Roblox `AnalyticsService` log methods behind a best-effort server boundary. Analytics failure cannot change gameplay, progression, station assignment, saving, or presentation truth.

Phase 06 introduces no daily system, store, monetization, final art, external asset, audio, functional bonus, or Phase 07 system.

## Phase 07 crate-first visual reconstruction

Phase 07 changes presentation, not the game contract. The crate becomes the dominant readable object in every active view: all 25 floor cells, the four-cell vertical capacity, placed items, ghost validity, and resting height must remain legible. A low matte console and low front rim frame the crate without hiding it; thin non-refractive side/rear panes, a warm opaque floor, restrained task light, and controlled camera replace the obstructed recording baseline.

The first rendered frame is authored and controlled. A dark curtain hides the world until profile/waiting state and a safe Scriptable camera are ready, so players do not see raw sky, a default avatar camera, uninitialized geometry, or an uncontrolled snap. Responsive station framing remains local presentation; it adds no orbit and sends no remote.

The eight deterministic stations become separate bays on a wider ring inside one coherent circular/octagonal toy-industrial warehouse. The center dispatch is the landmark and the existing showcase route explains where successful crates travel. Lighting, bloom, Neon, world labels, and screen UI all support the packing volume rather than compete with it. Semantic green/red remain state-only, amber remains shipping/reward, purple remains collection/mastery, and cyan remains navigation/station identity.

Shipping must visibly close around the player's arrangement, failure must visibly break containment, and reset must return a clean open crate. These are local visual refinements around the accepted server-authoritative state machine, rewards, progression, profile, mission, and analytics boundaries.

Final item models, external assets, textures, images, audio, music, final particles/VFX, haptics, monetization, new systems, and Phase 08 remain deferred. Phase 07 is active and unaccepted on `codex/phase-07-visual-readability-arena-rebuild`; [PR #8](https://github.com/kotonja/ONE-MORE-ITEM-/pull/8) remains open, draft, and unmerged. Automated, manual, cloud, complete-close, direct-reopen, and parity checks are green, but they cannot substitute for the accepted complete recording and final screenshot set. See `docs/PHASE07_VISUAL_READABILITY_ARENA_REBUILD.md` for the remaining evidence gate.
