# Game direction

ONE MORE ITEM! — PACK THE BOX is a premium, mobile-first Roblox packing game. The core promise is: **Fit it. Ship it. Or risk one more.**

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

- Permanent UI is authored as actual `StarterGui` instances, never generated wholesale at runtime.
- The permanent arena and stations are authored as actual `Workspace` instances, never generated at runtime.
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

Studio and production profile data remain strictly separated. Normal Studio persistence uses the Studio-test store; controlled Unavailable, SaveDelayed, and Conflict acceptance fixtures use only an injected in-memory adapter and must be cleared before normal persistence or saving. Deterministic coverage, both real Studio-test persistence sessions, and the last normal pre-queue-correction cloud save/close with fresh Output passed. The later monotonic waiting-snapshot correction passed all five suites in an offline recovery copy but has not reached the cloud place. Final apply/save/close/direct-reopen parity is blocked by the local Studio/network path: protocol opens failed TLS verification, while signed-in Home retries reached Team Create and then stalled without a join snapshot. Manual phone/gamepad collection opening also remains incomplete. Phase 05 is therefore not accepted, and Phase 06 must not begin during Phase 05.
