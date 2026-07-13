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
