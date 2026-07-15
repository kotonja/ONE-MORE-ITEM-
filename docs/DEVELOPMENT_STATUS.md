# Development status

## Current phase and Git state

- **Phase result:** **Implemented and substantially verified; not yet accepted.** Phase 05 code, deterministic tests, normal Play, controlled failure fixtures, and two-session Studio-test persistence passed. The final queue `StateVersion` correction passed all five suites in an offline recovery copy but is not yet synchronized or saved to the cloud place. Cloud apply/save/close/direct-reopen parity and manual phone/gamepad collection-panel gates remain incomplete.
- **Current phase:** Phase 05 - Persistent Player Profiles, Tape, Collection, and Packing Rank.
- **Current branch:** `codex/phase-05-persistent-progression`.
- **Protected base:** `main` and `origin/main` remain at the accepted Phase 04 squash merge `213f3581bd242523e34601cfefa5b5a74770ddee`.
- **Current pull request:** [Draft PR #6 - Phase 05: Persistent Profiles, Collection, and Packing Rank](https://github.com/kotonja/ONE-MORE-ITEM-/pull/6), draft and unmerged.
- **Latest implementation SHA:** `bf144fc3cb478823a80ceadaafc28cb78298bf12` (`test: harden Phase 05 acceptance verification`), pushed to the Phase 05 branch. Its green code-head runs are recorded below; the containing documentation commit and exact-head runs are recorded externally in PR #6 and the final handoff to avoid a self-referential tracked status.
- **Pre-release QA:** [Issue #4 - Pre-release cross-platform and multiplayer integration QA](https://github.com/kotonja/ONE-MORE-ITEM-/issues/4) remains open. No Phase 05 acceptance comment has been added.
- **Main protection:** Phase 05 remains isolated to its feature branch. Keep PR #6 open as a draft during this task; Phase 06 has not begun.

## Phase 04 protected baseline

Phase 04 is complete and merged at `213f3581bd242523e34601cfefa5b5a74770ddee`. Its accepted cloud proof remains historical evidence: `672/672` managed paths, 617 non-script instances, `55/55` exact canonical sources, eight authored stations, 16 showcase path nodes, exactly six gameplay remotes, zero duplicate/wrong-class managed paths, Foundation `69/69`, Phase 02 `94/94`, Phase 03 `65/65`, Phase 04 `119/119`, a verified five-client Station_05 integration, final showcase cleanup, and zero fresh game-owned warnings/errors after direct no-sync reopen.

Phase 05 extends but does not weaken that baseline. It adds no gameplay remote, client-authoritative progression, monetization, later-phase system, or final asset dependency.

## Phase 05 implementation result

The working implementation now includes:

- strict shared catalog, rank, mastery, progression, and profile-network types;
- server-only Version 1 migration/schema, adapter contract, guarded DataStore adapter, deterministic memory adapter, profile lifecycle/scheduler, snapshot builder, and progression service;
- load-before-assignment, per-player monotonic waiting-snapshot versions across Loading/queued Ready/Unavailable at `RoundId=0`, canonical persistent Tape, server-created OutcomeIds, reward-before-cosmetic ordering, bounded receipts, lock-aware release, and shutdown integration;
- one permanent server-to-client `ReplicatedStorage.ONE_MORE_ITEM.ProfileNet.ProfileSnapshot` event while retaining exactly six gameplay remotes;
- independent client profile storage/presentation, permanent MetaBar/DataStatus/CollectionPanel/eight slots/discovery/rank/results UI, and responsive collection controls;
- eight permanent station collection shelves plus one script-free development proxy template; and
- `studio/phase02.manifest.json` as the sole permanent-instance owner for Phase 02-05.

The full canonical Phase 01 plus Phase 02-05 target contains 909 unique managed paths: 834 non-script instances and 75 Luau sources. The Phase 02-05 blueprint itself contains 898 operations and 65 sources.

## Profile storage and safety

| Contract | Verified result |
| --- | --- |
| Schema version | Version `1`; defaults, normalization, Version 0 migration, Version 1 copy, and future-version rejection passed deterministic tests. |
| Production configuration | `ONE_MORE_ITEM_PlayerProfiles_v1` for non-Studio servers. **No production-store access, test, rollout, or result is claimed.** |
| Normal Studio persistence | `ONE_MORE_ITEM_PlayerProfiles_StudioTest_v1` only; Session A/B and the last normal pre-queue-correction cloud Studio run used this isolated store. |
| Deterministic/failure storage | Injected `MemoryProfileAdapter`; network-free and not persistence evidence. |
| Normal writes | Guarded `UpdateAsync` with synchronous non-yielding transforms; retries/budget waits occur outside transforms. |
| Bounds | 128 OutcomeIds, 12 recent discoveries, 60-second heartbeat/autosave, 180-second stale lock, at most 8 concurrent saves, 25-second shutdown deadline. |

The Studio-only failure acceptance fixture is disabled by default. It reads these attributes from `ServerScriptService.ONE_MORE_ITEM_Server`:

```text
ONE_MORE_ITEM_Phase05AcceptanceMode
ONE_MORE_ITEM_Phase05AcceptanceTargetUserId
ONE_MORE_ITEM_Phase05AcceptanceExpiresAt
```

Allowed modes are `Unavailable`, `SaveDelayed`, and `Conflict`. Expiry must be an integer in the future and no more than 600 seconds ahead; target is optional and otherwise selects the first joining player. A valid fixture selects one `MemoryProfileAdapter` for the **entire test server**, while the target controls which player receives the injected condition. Invalid/expired arming is rejected.

All three attributes were cleared before the last normal pre-queue-correction Studio-test run and save. They must remain absent before every normal Studio-test persistence run, cloud save, or cloud reopen. Never save or publish the place while a fixture is armed, and never cite memory-fixture evidence as a substitute for Session A/B.

## Persistent progression result

- A successful shipment grants `ShipmentValue` Tape exactly once, XP from the documented formula, discovery/mastery per valid shipped occurrence, and shipment statistics.
- Failure grants only bounded consolation XP and the failed-round statistic; it grants no Tape, discovery, or mastery.
- Rank thresholds and mastery tiers are derived, deterministic status with no gameplay power.
- Outcome IDs use `{UserId}:{ServerSessionId}:{RoundId}` and are server created. Bounded receipt deduplication prevents reward replay.
- The profile snapshot copies presentation-safe values only and exposes no store key, lock token, heartbeat, receipt list, or internal profile table.

Session A/B and controlled SaveDelayed recovery both demonstrated exact-once reward behavior. No client-authoritative result or profile-mutation remote was added.

## Local Node 24 validation

Fresh local output passed all five gates:

```text
[StudioSyncSmoke] PASS checks=16 folders=7 scripts=10 deterministic=true
[Phase02StudioSyncSmoke] PASS criteria=28 instances=833 scripts=65 remotes=6 deterministic=true phase01=true
[Phase03LayoutMatrix] PASS viewports=13 insetProfiles=5 cases=65 desktopCompatible=true safeContainment=true
[Phase03CrossPlatformSmoke] PASS criteria=31 viewports=13 insetProfiles=5 layoutCases=65 remotes=6 deterministic=true phase01=true phase02=true
[Phase04MultiplayerArena] PASS criteria=42 instances=833 scripts=65 stations=8 pathNodes=16 remotes=6 deterministic=true prior=true
[Phase05PersistentProgression] PASS criteria=56 instances=833 scripts=65 gameplayRemotes=6 profileRemotes=1 shelves=8 collectionSlots=8 deterministic=true prior=true
```

`git diff --check` passes for the corrected documentation tree.

## Automated Studio suites

Studio evidence is split honestly between the last normal cloud run and the post-correction offline recovery-copy run. Both passed these deterministic suite totals:

| Suite | Result | Determinism evidence |
| --- | ---: | --- |
| Foundation | `69/69` | fuzz seed `24012026`, 1,000 cases |
| Phase 02 | `94/94` | seed `24022026` |
| Phase 03 | `65/65` | seed `13072026` |
| Phase 04 | `119/119` | seed `14072026` |
| Phase 05 | `123/123` | seed `15072026`, adapter `memory` for the deterministic suite |

The last normal cloud server, before the queue correction, reported `profileStore=StudioTest`, not memory. It loaded the same Studio user into Station_01 with profile `Ready`, save state `Saved`, Tape `30`, XP `30`, and profile revision `5`. Normal stop logged profile shutdown `successes=1 failures=0 skipped=0`, followed by zero actionable game-owned errors or warnings. After commit `bf144fc3cb478823a80ceadaafc28cb78298bf12` added the monotonic waiting-snapshot contract, a fresh offline recovery-copy Play run again passed Foundation `69/69`, Phase 02 `94/94`, Phase 03 `65/65`, Phase 04 `119/119`, and Phase 05 `123/123`. That local file is not attached to the cloud experience, so its server emitted the expected `Profile store unavailable for StudioTest` error; the run proves the corrected suites only and is not new persistence or zero-Output evidence.

## Play and multiplayer evidence

| Gate | Verified result |
| --- | --- |
| Loading before station | Play Solo showed `LOADING YOUR PROFILE` before Station_01 and did not assign reward-bearing gameplay early. |
| Successful shipment | A one-Parcel shipment granted exactly `+15` Tape and `+14` XP, discovered Parcel, and incremented mastery/statistics once. |
| Failure consolation | A deliberate one-item failure granted `+2` XP with no Tape/discovery/mastery; incidental zero-item failures granted zero XP. |
| Persistent presentation | Tape, XP, collection count, mastery, Rookie rank, Results, DataStatus, and the owner shelf reflected authoritative state. Desktop collection presentation was exercised. |
| Two-player isolation | In the controlled memory run, Player1/Station_01 and Player2/Station_02 had distinct user/session/revision state. The target reached Tape `30`/XP `28` from two shipments while the unaffected player remained Tape `0`/XP `0`; no cross-player reward contamination was observed. |
| Player leave | One test client was forcibly terminated to simulate abrupt departure. Automated suites cover release/isolation, but no explicit manual shelf-release log was captured from that termination, so that visual/manual detail is not claimed. |
| Manual device collection | **Incomplete.** Desktop passed; a gamepad prompt displayed `C/Y`, but opening/closing Collection with ButtonY/ButtonB was not completed, and phone/touch collection opening was not manually exercised. Deterministic 65-case layout/input coverage remains green but does not replace these manual checks. |

## Controlled data-failure evidence

The following runs used the explicitly armed Studio-only `MemoryProfileAdapter` fixture, never a real DataStore outage:

| Fixture | Verified result |
| --- | --- |
| `Unavailable` | Bounded load ended after 5 attempts; the target retained normal movement, had no station/round, and visibly saw `DATA UNAVAILABLE` / `REJOIN TO RETRY`. |
| `SaveDelayed` | The target outcome first reached SaveDelayed, preserved its in-memory progression fingerprint, then recovered to Ready/Saved after save attempt 4. Stored progression matched memory, OutcomeId stayed stable, and the adapter contained exactly one receipt for the checked outcome. The transient amber `SAVE DELAYED` visual was not captured, so only hook logs and final Saved presentation are claimed. |
| `Conflict` | Target progression stopped; hook evidence reported `roundCleared=true`, `stationReleased=true`, `shelfRuntime=0`, and final state Conflict. The target visibly saw `PROFILE OPEN ELSEWHERE` / `CLOSE THE OTHER SESSION AND REJOIN`; the unaffected Player2 remained Saved at Station_02. |
| Eight-profile deterministic coverage | Independent defaults/locks, eight mutations/saves, isolated failure/conflict, and bounded shutdown passed in the Phase 05 suite. |

These fixtures validate behavior only. Because arming replaces the adapter for the entire test server, none of their wallets or saves are evidence about `ONE_MORE_ITEM_PlayerProfiles_StudioTest_v1`.

## Two-session Studio-test profile persistence

Only `ONE_MORE_ITEM_PlayerProfiles_StudioTest_v1` was used. Sanitized evidence:

| Evidence | Result |
| --- | --- |
| Session A baseline | Tape `0`, XP `0`, Parcel mastery `0`, discovered `0`, successful shipments `0`. |
| Session A post-play | Tape `15`, XP `16`, Parcel mastery `1`, discovered `1/8`, successful shipments `1`, failed rounds `7`, total Tape earned `15`. The extra `2` XP came from the deliberate one-item failure. |
| Session A stop | Saved/clean result; shutdown `successes=1 failures=0 skipped=0`. Every Studio process then closed. |
| Session B direct no-sync reopen | The same private cloud place reopened without repository synchronization and loaded exactly Tape `15`, XP `16`, Parcel mastery `1`, discovered `1`, successful shipments `1`. |
| Session B second shipment | Applied exactly `+15` Tape and `+14` XP, incremented Parcel mastery to `2`, kept discovery at `1`, and incremented successful shipments to `2`; no Session A reward replay occurred. |
| Session B final state | Tape `30`, XP `30`, Parcel mastery `2`, discovered `1/8`, successful shipments `2`, failed rounds `10`, total Tape earned `30`, Saved; shutdown `successes=1 failures=0 skipped=0`. |

This completes the required real two-session Studio-test profile persistence proof. It predates the acceptance-hook/UI synchronization and queue correction, so it does **not** complete the later final-place cloud apply/save/reopen/parity gate.

## GitHub Actions

- **Workflow name:** `Phase 01–05 Node Validation`.
- **Runtime/actions:** Node 24, `actions/checkout@v7`, `actions/setup-node@v6`.
- **Permissions/configuration:** `contents: read`, package-manager cache disabled, no package install, no third-party dependency.
- **Triggers:** pull requests targeting `main`, pushes to `main`, and pushes to `codex/**`.
- **Pushed implementation head:** `bf144fc3cb478823a80ceadaafc28cb78298bf12`.
- **Branch-push run:** `29398524215`, job `87297461413`, success; every Phase 01-05 step succeeded.
- **Draft-PR run:** `29398526422`, job `87297468905`, success; every Phase 01-05 step succeeded.
- **Documentation head:** the containing commit and its exact-head branch/PR runs are recorded in PR #6 and the final handoff rather than self-referenced by this tracked document.

## Cloud place persistence

| Gate | Current Phase 05 result |
| --- | --- |
| Recovery copy | Saved outside Git; 261,264 bytes; SHA-256 `18C06C0874C256A58E30E33882812A77D9FACB3A26A4A283514A1EC673BBAFF2`. The personal filesystem path is intentionally omitted. |
| Canonical synchronization | Rebuilt the Phase 02-05 blueprint and applied all 898 operations twice at the then-current pre-queue-correction source state. Both passes reported `Created=0 Updated=898 Failed=0`; 65 script backups were taken. |
| Fixture cleanup | Acceptance attributes printed as cleared (`nil nil nil`) before the last normal pre-queue-correction Studio-test run and save. |
| Normal pre-save proof | At that pre-queue-correction state, all five Studio suites passed; the normal StudioTest profile loaded Tape `30`/XP `30`; shutdown succeeded; zero fresh actionable game-owned Output remained. |
| Cloud save | Completed normally after cleanup for the pre-queue-correction state; the Studio tab had no unsaved marker. Commit `bf144fc3cb478823a80ceadaafc28cb78298bf12` is not yet synchronized or saved there. |
| Complete close | Passed; Roblox Studio process count reached zero. |
| Final direct reopen | **Blocked, not passed.** Two direct protocol opens returned `Studio is unable to connect. Check your network connection and try again.` Two later signed-in Studio Home opens reached the correct PlaceId, universe, and Team Create server but stalled before the editor received a join snapshot. |
| Blocker evidence | The protocol-attempt log reports `HttpError: TlsVerificationFail` and OpenSSL `unable to get local issuer certificate (20)` while Roblox API requests pass through Avast HTTPS interception. The latest Home-route log has zero TLS-verification failures and records the correct Team Create endpoint, but no completed join/editor. This is an external Studio/network failure, not a game-owned Output failure. |
| Post-reopen managed/source parity | **Not run because the cloud place cannot reopen.** No `909/909`, `75/75`, duplicate/wrong-class, UI/shelf/remote, or post-reopen suite claim is made. |

The earlier successful Session B no-sync reopen proves the Studio-test profile persisted between Sessions A and B. It does not prove that the last pre-queue-correction cloud synchronization survived its later close, and it does not prove that the repository queue correction reached the cloud place.

## Performance and cleanup accounting

- Observed loaded profiles: one in Play Solo, two in controlled Local Server, eight in deterministic capacity coverage.
- One shared due-save scheduler handles debounce, autosave, and heartbeat; there is no per-profile frame loop.
- Save concurrency is bounded at 8; receipts at 128; recent discoveries at 12.
- Shelf runtime is bounded at six simplified proxies per occupied station, 48 total. Conflict evidence returned the target shelf runtime to `0`.
- Existing showcase bounds remain three active clones, sixteen pending records, and one conditional shared 30 Hz loop.
- The last normal pre-queue-correction cloud shutdown reported one successful release and zero failures/skips; fresh actionable game-owned Output was zero. The post-correction offline recovery run is suite-only evidence and emitted the expected unavailable Studio-test-store error.

## Known issues and deferred pre-release QA

- **Acceptance blocker:** repair the local Roblox Studio/Avast network path so PlaceId `134193642444044` completes an editor join; synchronize the repository queue correction; save normally; close every Studio process; reopen directly without synchronization; then prove all 909 managed paths, all 75 sources, zero duplicates/wrong classes, permanent profile UI/eight shelves, exactly six gameplay remotes plus one ProfileSnapshot remote, all five Studio suites, and zero fresh actionable game-owned Output.
- **Manual input gap:** phone/touch and gamepad collection open/close were not completed. No physical phone or controller result is claimed.
- **SaveDelayed visual gap:** exact hook logs and recovery passed, but the transient amber Save Delayed state was not visually captured.
- [Issue #4](https://github.com/kotonja/ONE-MORE-ITEM-/issues/4) remains open for extended controller, hybrid, Station_07, multiplayer-soak, physical-device, and integration QA. Do not add the Phase 05 acceptance comment until Phase 05 is fully accepted.
- No production DataStore, production rollout, current published `MaxPlayers`, or lower-end-device result is claimed.
- Development geometry and text-only iconography remain non-final.

## Deferred by design

Daily challenges, starter missions, offline income, cosmetics/ownership/store, Robux products, monetization, trading, pets, rebirths, multiple worlds, co-op packing, cheer reactions, persistent/global/OrderedDataStore leaderboards, analytics, quests, final object models, external assets, sound/music, final VFX, haptics, final Tape wrap, item power, functional mastery bonuses, rank power bonuses, and every Phase 06 system remain deferred.

## Exact next phase recommendation

Do not begin Phase 06. First resolve the local Roblox Studio/Avast network blocker so the private place editor opens; synchronize the repository queue correction; save; close every Studio process; reopen directly without synchronization; complete managed/source/UI/shelf/remote parity, all five post-reopen Studio suites, and fresh Output; manually open/close Collection on phone/touch and gamepad; and confirm the final branch/PR CI recorded in PR #6. Only after every remaining gate is documented may Phase 05 be accepted, issue #4 receive its concise Phase 05 follow-up, and Phase 06 be recommended.
