import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const toolsDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(toolsDirectory, "..");
const manifestPath = path.join(repositoryRoot, "studio", "phase02.manifest.json");
const generatorPath = path.join(toolsDirectory, "build_phase02_blueprint.mjs");
const priorGates = [
  ["test_studio_blueprint.mjs", /\[StudioSyncSmoke\] PASS checks=16 folders=7 scripts=10 deterministic=true/],
  ["test_phase02_blueprint.mjs", /\[Phase02StudioSyncSmoke\] PASS criteria=\d+ instances=\d+ scripts=\d+ remotes=6 deterministic=true phase01=true/],
  ["test_phase03_cross_platform.mjs", /\[Phase03CrossPlatformSmoke\] PASS criteria=\d+ viewports=13 insetProfiles=5 layoutCases=65 remotes=6 deterministic=true phase01=true phase02=true/],
  ["test_phase04_multiplayer_arena.mjs", /\[Phase04MultiplayerArena\] PASS criteria=\d+ instances=\d+ scripts=\d+ stations=8 pathNodes=16 remotes=6 deterministic=true prior=true/],
];
const expectedGameplayRemotes = [
  "ClientReadyRequest",
  "DecisionRequest",
  "PlaceItemRequest",
  "PlacementResponse",
  "RestartRequest",
  "RoundSnapshot",
];
const phase05Sources = [
  "src/ReplicatedStorage/ONE_MORE_ITEM/Shared/Profile/CollectionDefinitions.luau",
  "src/ReplicatedStorage/ONE_MORE_ITEM/Shared/Profile/MasteryDefinitions.luau",
  "src/ReplicatedStorage/ONE_MORE_ITEM/Shared/Profile/PackingRankDefinitions.luau",
  "src/ReplicatedStorage/ONE_MORE_ITEM/Shared/Profile/ProfileNetworkTypes.luau",
  "src/ReplicatedStorage/ONE_MORE_ITEM/Shared/Profile/ProgressionTypes.luau",
  "src/ServerScriptService/ONE_MORE_ITEM_Server/Services/Profile/DataStoreProfileAdapter.luau",
  "src/ServerScriptService/ONE_MORE_ITEM_Server/Services/Profile/MemoryProfileAdapter.luau",
  "src/ServerScriptService/ONE_MORE_ITEM_Server/Services/Profile/ProfileConfig.luau",
  "src/ServerScriptService/ONE_MORE_ITEM_Server/Services/Profile/ProfileSchema.luau",
  "src/ServerScriptService/ONE_MORE_ITEM_Server/Services/Profile/ProfileService.luau",
  "src/ServerScriptService/ONE_MORE_ITEM_Server/Services/Profile/ProfileSnapshotBuilder.luau",
  "src/ServerScriptService/ONE_MORE_ITEM_Server/Services/Profile/ProfileStoreAdapter.luau",
  "src/ServerScriptService/ONE_MORE_ITEM_Server/Services/Profile/ProfileTypes.luau",
  "src/ServerScriptService/ONE_MORE_ITEM_Server/Services/Profile/ProgressionService.luau",
  "src/ServerScriptService/ONE_MORE_ITEM_Server/Services/CollectionShelfService.luau",
  "src/StarterPlayer/StarterPlayerScripts/ONE_MORE_ITEM_Client/Controllers/ClientProfileStore.luau",
  "src/StarterPlayer/StarterPlayerScripts/ONE_MORE_ITEM_Client/Controllers/ProfileResponsiveLayout.luau",
];
const phase05TestSources = [
  "src/ServerScriptService/ONE_MORE_ITEM_Server/Dev/Phase05TestSuite.luau",
  "src/ServerScriptService/ONE_MORE_ITEM_Server/Dev/RunPhase05Tests.server.luau",
];

let criterionCount = 0;
let temporaryRoot;

function criterion(_name, callback) {
  callback();
  criterionCount += 1;
}

function runNode(scriptPath, args = []) {
  return spawnSync(process.execPath, [scriptPath, ...args], {
    cwd: repositoryRoot,
    encoding: "utf8",
  });
}

function readText(relativePath) {
  return fs.readFileSync(path.join(repositoryRoot, relativePath), "utf8");
}

function trackedFiles() {
  const result = spawnSync("git", ["ls-files", "-z"], {
    cwd: repositoryRoot,
    encoding: "buffer",
  });
  assert.equal(result.status, 0, `git ls-files failed: ${result.stderr.toString("utf8")}`);
  return result.stdout.toString("utf8").split("\0").filter(Boolean);
}

function listFilesRecursively(directory) {
  const result = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const child = path.join(directory, entry.name);
    if (entry.isDirectory()) result.push(...listFilesRecursively(child));
    else result.push(child);
  }
  return result;
}

function requirePriorGate([name, passPattern]) {
  const result = runNode(path.join(toolsDirectory, name));
  assert.equal(result.status, 0, `${name} failed:\n${result.stderr || result.stdout}`);
  assert.match(result.stdout, passPattern, `${name} did not emit its required PASS summary`);
}

function assertPath(map, instancePath, className) {
  const entry = map.get(instancePath);
  assert.ok(entry, `Missing authored path ${instancePath}`);
  assert.equal(entry.className, className, `${instancePath} must be ${className}`);
  return entry;
}

function assertNoScriptDescendants(scriptSteps, rootPath) {
  assert.equal(
    scriptSteps.some((step) => step.path === rootPath || step.path.startsWith(`${rootPath}.`)),
    false,
    `${rootPath} must remain script-free`,
  );
}

try {
  for (const gate of priorGates) requirePriorGate(gate);

  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "one-more-item-phase05-"));
  const firstOutput = path.join(temporaryRoot, "first");
  const secondOutput = path.join(temporaryRoot, "second");
  const firstGeneration = runNode(generatorPath, [manifestPath, firstOutput]);
  assert.equal(firstGeneration.status, 0, `Phase 05 generation failed:\n${firstGeneration.stderr || firstGeneration.stdout}`);
  const secondGeneration = runNode(generatorPath, [manifestPath, secondOutput]);
  assert.equal(secondGeneration.status, 0, `Repeated Phase 05 generation failed:\n${secondGeneration.stderr || secondGeneration.stdout}`);

  const firstBlueprintBytes = fs.readFileSync(path.join(firstOutput, "phase02-blueprint.json"));
  const secondBlueprintBytes = fs.readFileSync(path.join(secondOutput, "phase02-blueprint.json"));
  const firstCommandBytes = fs.readFileSync(path.join(firstOutput, "phase02-command-bar.json"));
  const secondCommandBytes = fs.readFileSync(path.join(secondOutput, "phase02-command-bar.json"));
  const blueprint = JSON.parse(firstBlueprintBytes.toString("utf8"));
  const commandBar = JSON.parse(firstCommandBytes.toString("utf8"));
  const instanceSteps = blueprint.steps.filter((step) => step.type === "ensureInstance");
  const scriptSteps = blueprint.steps.filter((step) => step.type === "writeScript");
  const instancesByPath = new Map(instanceSteps.map((step) => [step.path, step]));
  const scriptsByPath = new Map(scriptSteps.map((step) => [step.path, step]));

  const configSource = readText("src/ServerScriptService/ONE_MORE_ITEM_Server/Services/Profile/ProfileConfig.luau");
  const schemaSource = readText("src/ServerScriptService/ONE_MORE_ITEM_Server/Services/Profile/ProfileSchema.luau");
  const dataStoreSource = readText("src/ServerScriptService/ONE_MORE_ITEM_Server/Services/Profile/DataStoreProfileAdapter.luau");
  const memorySource = readText("src/ServerScriptService/ONE_MORE_ITEM_Server/Services/Profile/MemoryProfileAdapter.luau");
  const rankSource = readText("src/ReplicatedStorage/ONE_MORE_ITEM/Shared/Profile/PackingRankDefinitions.luau");
  const masterySource = readText("src/ReplicatedStorage/ONE_MORE_ITEM/Shared/Profile/MasteryDefinitions.luau");
  const collectionSource = readText("src/ReplicatedStorage/ONE_MORE_ITEM/Shared/Profile/CollectionDefinitions.luau");
  const itemSource = readText("src/ReplicatedStorage/ONE_MORE_ITEM/Shared/Content/DevelopmentItemDefinitions.luau");
  const snapshotBuilderSource = readText("src/ServerScriptService/ONE_MORE_ITEM_Server/Services/Profile/ProfileSnapshotBuilder.luau");
  const profileServiceSource = readText("src/ServerScriptService/ONE_MORE_ITEM_Server/Services/Profile/ProfileService.luau");
  const progressionSource = readText("src/ServerScriptService/ONE_MORE_ITEM_Server/Services/Profile/ProgressionService.luau");
  const roundSource = readText("src/ServerScriptService/ONE_MORE_ITEM_Server/Services/RoundService.luau");
  const bootstrapSource = readText("src/ServerScriptService/ONE_MORE_ITEM_Server/ServerBootstrap.server.luau");
  const roundUiSource = readText("src/StarterPlayer/StarterPlayerScripts/ONE_MORE_ITEM_Client/Controllers/RoundUIController.luau");
  const shelfSource = readText("src/ServerScriptService/ONE_MORE_ITEM_Server/Services/CollectionShelfService.luau");
  const profileUiSource = readText("src/StarterPlayer/StarterPlayerScripts/ONE_MORE_ITEM_Client/Controllers/ProfileUIController.luau");
  const phase05TestSource = readText("src/ServerScriptService/ONE_MORE_ITEM_Server/Dev/Phase05TestSuite.luau");
  const networkTypesSource = readText("src/ReplicatedStorage/ONE_MORE_ITEM/Shared/Net/NetworkTypes.luau");

  criterion("profile schema module exists", () => {
    assert.ok(fs.existsSync(path.join(repositoryRoot, "src/ServerScriptService/ONE_MORE_ITEM_Server/Services/Profile/ProfileSchema.luau")));
    assert.match(schemaSource, /function ProfileSchema\.CreateDefault/);
    assert.match(schemaSource, /function ProfileSchema\.Migrate/);
  });

  criterion("current schema is Version 2 with explicit Version 1 preservation", () => {
    assert.match(configSource, /SCHEMA_VERSION\s*=\s*2\b/);
    assert.match(schemaSource, /SchemaVersion\s*=\s*ProfileConfig\.SCHEMA_VERSION/);
    assert.match(schemaSource, /function migrateV1\b/);
    assert.match(schemaSource, /MIGRATED_V1_TO_V2/);
    assert.match(phase05TestSource, /Version 1[^\n]*Version 2|MIGRATED_V1_TO_V2/);
  });

  criterion("production and Studio-test stores are exact and distinct", () => {
    const production = configSource.match(/PRODUCTION_STORE_NAME\s*=\s*"([^"]+)"/)?.[1];
    const studio = configSource.match(/STUDIO_STORE_NAME\s*=\s*"([^"]+)"/)?.[1];
    assert.equal(production, "ONE_MORE_ITEM_PlayerProfiles_v1");
    assert.equal(studio, "ONE_MORE_ITEM_PlayerProfiles_StudioTest_v1");
    assert.notEqual(production, studio);
    assert.match(dataStoreSource, /RunService:IsStudio\(\)/);
  });

  const clientSources = listFilesRecursively(path.join(repositoryRoot, "src", "StarterPlayer"))
    .filter((file) => file.endsWith(".luau"));
  criterion("client sources cannot access DataStoreService", () => {
    for (const file of clientSources) {
      assert.doesNotMatch(fs.readFileSync(file, "utf8"), /DataStoreService|GetDataStore|UpdateAsync|SetAsync/,
        `Client persistence access in ${path.relative(repositoryRoot, file)}`);
    }
  });

  criterion("DataStore adapter is server-only", () => {
    const mapping = manifest.scripts.find((entry) => entry.sourceFile.endsWith("DataStoreProfileAdapter.luau"));
    assert.ok(mapping);
    assert.ok(mapping.path.startsWith("ServerScriptService.ONE_MORE_ITEM_Server."));
    assert.ok(!mapping.path.startsWith("ReplicatedStorage."));
  });

  criterion("normal profile writes use UpdateAsync", () => {
    assert.match(dataStoreSource, /store:UpdateAsync\(key, transform\)/);
    assert.ok((dataStoreSource.match(/protectedUpdate\(/g) ?? []).length >= 5);
  });

  criterion("normal profile writes never use SetAsync", () => {
    const serverProfileSources = listFilesRecursively(path.join(repositoryRoot, "src", "ServerScriptService", "ONE_MORE_ITEM_Server", "Services", "Profile"));
    for (const file of serverProfileSources) assert.doesNotMatch(fs.readFileSync(file, "utf8"), /:SetAsync\s*\(/);
  });

  criterion("UpdateAsync transform source contains no yielding operation", () => {
    assert.doesNotMatch(dataStoreSource, /task\.(?:wait|delay|spawn)|WaitForChild|Heartbeat:Wait|RenderStepped:Wait|coroutine\.yield/);
    assert.doesNotMatch(schemaSource, /task\.(?:wait|delay|spawn)|coroutine\.yield/);
  });

  criterion("all DataStore access is protected", () => {
    assert.match(dataStoreSource, /local function protectedUpdate[\s\S]*return pcall/);
    assert.match(dataStoreSource, /pcall\(function\(\)[\s\S]*GetDataStore/);
    assert.match(dataStoreSource, /pcall\(function\(\)[\s\S]*GetRequestBudgetForRequestType/);
  });

  criterion("memory adapter exists with deterministic fixtures", () => {
    assert.match(memorySource, /function MemoryProfileAdapter\.Create/);
    assert.match(memorySource, /SetLoadFailure/);
    assert.match(memorySource, /SetSaveFailure/);
    assert.match(memorySource, /SimulateServerCrash/);
    assert.match(memorySource, /GetRequestCountForUser/);
    assert.doesNotMatch(memorySource, /DataStoreService|task\.wait/);
    assert.match(bootstrapSource, /if not RunService:IsStudio\(\) then\s*return nil\s*end/);
    assert.match(bootstrapSource, /ONE_MORE_ITEM_Phase05AcceptanceMode/);
    assert.match(bootstrapSource, /ONE_MORE_ITEM_Phase05AcceptanceTargetUserId/);
    assert.match(bootstrapSource, /ONE_MORE_ITEM_Phase05AcceptanceExpiresAt/);
    assert.match(bootstrapSource, /INVALID_OR_EXPIRED_ARMING/);
    assert.match(bootstrapSource, /local acceptanceAttributeHost = script\.Parent/);
    assert.doesNotMatch(bootstrapSource, /game:GetAttribute\(ACCEPTANCE_/);
    assert.match(bootstrapSource, /rawMode ~= "Unavailable"[\s\S]*rawMode ~= "SaveDelayed"[\s\S]*rawMode ~= "Conflict"/);
    assert.match(bootstrapSource, /SetLoadFailure\(userId, ProfileConfig\.MAXIMUM_LOAD_ATTEMPTS\)/);
    assert.match(bootstrapSource,
      /snapshot\.State == "Saving"[\s\S]*snapshot\.LastReward\.TapeDelta > 0[\s\S]*SetSaveFailure\(userId, ACCEPTANCE_SAVE_FAILURE_COUNT\)/);
    assert.match(bootstrapSource, /ForceSession\(player\.UserId,[\s\S]*ProcessDueSaves\(math\.huge\)/);
    assert.match(bootstrapSource, /GetRequestCountForUser\("Load", userId\)/);
    assert.match(bootstrapSource, /GetRequestCountForUser\("Save", userId\)/);
    assert.match(bootstrapSource, /ReadStored\(userId\)/);
    assert.match(bootstrapSource, /storedProgressionMatches=%s outcomeStable=%s receiptCount=%d/);
    assert.match(bootstrapSource,
      /if previousRound ~= nil then previousRound\.StateVersion \+ 1 else 1/);
    assert.match(bootstrapSource, /local waitingStateVersions:\s*\{ \[Player\]: number \} = \{\}/);
    assert.match(bootstrapSource, /local function nextWaitingStateVersion/);
    assert.match(bootstrapSource, /nextVersion = math\.max\(nextVersion, minimumStateVersion\)/);
    assert.match(bootstrapSource, /StateVersion = nextWaitingStateVersion\(player, stateVersion\)/);
    assert.match(bootstrapSource, /waitingStateVersions\[player\] = nil/);
    assert.match(roundUiSource, /function RoundUIController\.ResolveWaitingCopy/);
    assert.match(roundUiSource, /"DATA UNAVAILABLE", "REJOIN TO RETRY"/);
    assert.match(roundUiSource, /"PROFILE OPEN ELSEWHERE", "CLOSE THE OTHER SESSION AND REJOIN"/);
    assert.match(bootstrapSource,
      /local profileAdapter = if acceptanceFixture ~= nil then acceptanceFixture\.Adapter else DataStoreProfileAdapter\.Create\(\)/);
  });

  criterion("session-lock fields are persisted", () => {
    for (const field of ["Token", "JobId", "PlaceId", "AcquiredAt", "HeartbeatAt"]) {
      assert.match(schemaSource, new RegExp(`\\b${field}\\b`));
    }
  });

  criterion("lock heartbeat and timeout are finite positive bounds", () => {
    assert.match(configSource, /SESSION_HEARTBEAT_SECONDS\s*=\s*60\b/);
    assert.match(configSource, /STALE_LOCK_SECONDS\s*=\s*180\b/);
    assert.match(configSource, /MAXIMUM_LOAD_ATTEMPTS\s*=\s*5\b/);
    assert.match(configSource, /MAXIMUM_SAVE_ATTEMPTS\s*=\s*5\b/);
  });

  criterion("processed outcome receipt bound is 128", () => {
    assert.match(configSource, /MAXIMUM_RECEIPT_COUNT\s*=\s*128\b/);
    assert.match(schemaSource, /while #receipts > ProfileConfig\.MAXIMUM_RECEIPT_COUNT/);
    assert.match(progressionSource, /while #updated > ProfileConfig\.MAXIMUM_RECEIPT_COUNT/);
  });

  criterion("OutcomeId includes user, server session, and round", () => {
    assert.match(roundSource, /OutcomeId\s*=\s*string\.format\("%d:%s:%d",\s*player\.UserId,\s*self\._serverSessionId,\s*roundId\)/);
    assert.match(roundSource, /ServerSessionId/);
  });

  criterion("OutcomeId authority is bounded and server generated", () => {
    assert.match(configSource, /MAXIMUM_OUTCOME_ID_LENGTH\s*=\s*(?:256|[1-9][0-9]+)/);
    assert.match(roundSource, /#options\.ServerSessionId\s*>\s*120/);
    assert.doesNotMatch(networkTypesSource, /(?:PlaceItemRequest|DecisionRequest|RestartRequest)[\s\S]{0,220}OutcomeId/);
  });

  criterion("seven rank definitions use stable unique names", () => {
    const definitions = [...rankSource.matchAll(/definition\((\d+),\s*"([^"]+)",\s*([\d_]+)\)/g)];
    assert.equal(definitions.length, 7);
    assert.deepEqual(definitions.map((match) => Number(match[1])), [1, 2, 3, 4, 5, 6, 7]);
    assert.equal(new Set(definitions.map((match) => match[2])).size, 7);
  });

  criterion("rank thresholds match the contract", () => {
    const thresholds = [...rankSource.matchAll(/definition\(\d+,\s*"[^"]+",\s*([\d_]+)\)/g)]
      .map((match) => Number(match[1].replaceAll("_", "")));
    assert.deepEqual(thresholds, [0, 300, 1000, 2500, 5000, 9000, 15000]);
    assert.match(rankSource, /GetProgress/);
  });

  criterion("mastery thresholds match five twenty and fifty", () => {
    assert.match(masterySource, /Bronze\s*=\s*5\b/);
    assert.match(masterySource, /Silver\s*=\s*20\b/);
    assert.match(masterySource, /Gold\s*=\s*50\b/);
    for (const tier of ["Locked", "Discovered", "Bronze", "Silver", "Gold"]) assert.match(masterySource, new RegExp(`"${tier}"`));
  });

  criterion("collection catalog resolves all eight current items", () => {
    assert.match(collectionSource, /DevelopmentItemDefinitions\.Ordered/);
    assert.match(collectionSource, /IsValidItemId/);
    const itemIds = [...itemSource.matchAll(/\bitem\("([a-z0-9_]+)"/g)].map((match) => match[1]);
    assert.equal(itemIds.length, 8);
    assert.equal(new Set(itemIds).size, 8);
  });

  criterion("ProfileSnapshot is a separately authored server-to-client remote", () => {
    assertPath(instancesByPath, "ReplicatedStorage.ONE_MORE_ITEM.ProfileNet", "Folder");
    assertPath(instancesByPath, "ReplicatedStorage.ONE_MORE_ITEM.ProfileNet.ProfileSnapshot", "RemoteEvent");
    assert.match(bootstrapSource, /ProfileSnapshot:FireClient|profileSnapshot:FireClient/);
    assert.doesNotMatch(bootstrapSource, /ProfileSnapshot\.OnServerEvent|profileSnapshot\.OnServerEvent/);
  });

  criterion("gameplay Net still contains exactly six remotes", () => {
    const remotes = instanceSteps.filter((step) => step.className === "RemoteEvent"
      && step.path.startsWith("ReplicatedStorage.ONE_MORE_ITEM.Net."));
    assert.equal(remotes.length, 6);
    assert.deepEqual(remotes.map((step) => step.path.split(".").at(-1)).sort(), expectedGameplayRemotes);
  });

  criterion("no client-to-server profile mutation remote exists", () => {
    const profileRemotes = instanceSteps.filter((step) => step.className === "RemoteEvent"
      && step.path.startsWith("ReplicatedStorage.ONE_MORE_ITEM.ProfileNet."));
    assert.deepEqual(profileRemotes.map((step) => step.path.split(".").at(-1)), ["ProfileSnapshot"]);
    for (const step of instanceSteps.filter((candidate) => candidate.className === "RemoteEvent")) {
      assert.doesNotMatch(step.path, /(?:Set|Add|Grant|Mutate|Save|Tape|XP|Rank|Mastery|Discovery)/i);
    }
  });

  const uiRoot = "StarterGui.ONE_MORE_ITEM_Gameplay.Root";
  criterion("MetaBar is permanently authored with exact core children", () => {
    assertPath(instancesByPath, `${uiRoot}.MetaBar`, "Frame");
    for (const [name, className] of [
      ["TapeLabel", "TextLabel"], ["TapeValue", "TextLabel"], ["RankName", "TextLabel"],
      ["RankProgressBar", "Frame"], ["RankProgressText", "TextLabel"],
      ["CollectionButton", "TextButton"], ["DataStatus", "TextLabel"],
    ]) assertPath(instancesByPath, `${uiRoot}.MetaBar.${name}`, className);
    assertPath(instancesByPath, `${uiRoot}.MetaBar.RankProgressBar.Background`, "Frame");
    assertPath(instancesByPath, `${uiRoot}.MetaBar.RankProgressBar.Fill`, "Frame");
  });

  criterion("CollectionPanel is permanently authored", () => {
    assertPath(instancesByPath, `${uiRoot}.CollectionPanel`, "Frame");
    for (const [name, className] of [
      ["Header", "TextLabel"], ["CloseButton", "TextButton"], ["CollectionSummary", "TextLabel"],
      ["RankSummary", "TextLabel"], ["StatsSummary", "TextLabel"], ["Slots", "Frame"],
    ]) assertPath(instancesByPath, `${uiRoot}.CollectionPanel.${name}`, className);
  });

  criterion("eight collection slots have the exact authored topology", () => {
    const slotsRoot = `${uiRoot}.CollectionPanel.Slots`;
    for (let index = 1; index <= 8; index += 1) {
      const slot = `${slotsRoot}.Slot_${String(index).padStart(2, "0")}`;
      assertPath(instancesByPath, slot, "TextButton");
      for (const [name, className] of [
        ["ItemViewport", "ViewportFrame"], ["ItemName", "TextLabel"], ["LockOverlay", "TextLabel"],
        ["MasteryTier", "TextLabel"], ["MasteryCount", "TextLabel"], ["MasteryProgress", "Frame"],
        ["Corner", "UICorner"], ["Stroke", "UIStroke"],
      ]) assertPath(instancesByPath, `${slot}.${name}`, className);
    }
  });

  criterion("DiscoveryReveal is permanently authored", () => {
    assertPath(instancesByPath, `${uiRoot}.DiscoveryReveal`, "Frame");
    assertPath(instancesByPath, `${uiRoot}.DiscoveryReveal.ItemViewport`, "ViewportFrame");
    for (const name of ["ItemName", "DiscoveryLabel", "MasteryLabel"]) {
      assertPath(instancesByPath, `${uiRoot}.DiscoveryReveal.${name}`, "TextLabel");
    }
  });

  criterion("RankUpBanner is permanently authored", () => {
    assertPath(instancesByPath, `${uiRoot}.RankUpBanner`, "Frame");
    assertPath(instancesByPath, `${uiRoot}.RankUpBanner.RankLabel`, "TextLabel");
    assertPath(instancesByPath, `${uiRoot}.RankUpBanner.RankName`, "TextLabel");
  });

  criterion("ResultsPanel includes all Phase 05 reward presentation fields", () => {
    for (const name of ["XPReward", "RankProgress", "DiscoverySummary"]) {
      assertPath(instancesByPath, `${uiRoot}.ResultsPanel.${name}`, "TextLabel");
    }
  });

  criterion("all eight stations have a permanently authored collection shelf", () => {
    for (let index = 1; index <= 8; index += 1) {
      const shelf = `Workspace.ONE_MORE_ITEM_WORLD.PlaytestArena.Stations.Station_${String(index).padStart(2, "0")}.CollectionShelf`;
      assertPath(instancesByPath, shelf, "Model");
      assertPath(instancesByPath, `${shelf}.ShelfBase`, "Part");
      assertPath(instancesByPath, `${shelf}.ShelfLabel`, "Part");
      assertPath(instancesByPath, `${shelf}.ShelfLabel.BillboardGui.RankName`, "TextLabel");
      assertPath(instancesByPath, `${shelf}.ShelfLabel.BillboardGui.CollectionCount`, "TextLabel");
    }
  });

  criterion("every shelf has six slots and exactly one Runtime folder", () => {
    for (let station = 1; station <= 8; station += 1) {
      const shelf = `Workspace.ONE_MORE_ITEM_WORLD.PlaytestArena.Stations.Station_${String(station).padStart(2, "0")}.CollectionShelf`;
      for (let slot = 1; slot <= 6; slot += 1) assertPath(instancesByPath, `${shelf}.Slot_${String(slot).padStart(2, "0")}`, "Part");
      assertPath(instancesByPath, `${shelf}.Runtime`, "Folder");
      const directRuntime = instanceSteps.filter((step) => step.path === `${shelf}.Runtime`);
      assert.equal(directRuntime.length, 1);
    }
  });

  criterion("CollectionShelfItemTemplate exists and is inert", () => {
    const templatePath = "ReplicatedStorage.ONE_MORE_ITEM.Assets.Development.CollectionShelfItemTemplate";
    const template = assertPath(instancesByPath, templatePath, "Part");
    assert.equal(template.properties.Anchored, true);
    assert.equal(template.properties.CanCollide, false);
    assert.equal(template.properties.CanTouch, false);
    assert.equal(template.properties.CanQuery, false);
    assertNoScriptDescendants(scriptSteps, templatePath);
  });

  criterion("collection shelf uses the canonical catalog and mastery definitions", () => {
    assert.match(shelfSource, /require\(Root\.Shared\.Profile\.CollectionDefinitions\)/);
    assert.match(shelfSource, /require\(Root\.Shared\.Profile\.MasteryDefinitions\)/);
    for (const member of ["OrderedItemIds", "TotalCount", "GetCatalogIndex", "GetDiscoveredCount"]) {
      assert.match(shelfSource, new RegExp(`CollectionDefinitions\\.${member}\\b`));
    }
    assert.match(shelfSource, /MasteryDefinitions\.GetMasteryTier\(count, true\)/);
    assert.match(shelfSource, /validateCanonicalCatalog\(\)/);
  });

  criterion("profile UI maps authored slots from the canonical catalog", () => {
    assert.match(profileUiSource, /require\(profile:WaitForChild\("CollectionDefinitions"\)\)/);
    assert.match(profileUiSource, /require\(profile:WaitForChild\("MasteryDefinitions"\)\)/);
    assert.match(profileUiSource, /validateCollectionAuthoring\(slotsContainer\)/);
    assert.match(profileUiSource, /for index, itemId in ipairs\(CollectionDefinitions\.OrderedItemIds\)/);
    assert.match(profileUiSource, /CollectionDefinitions\.GetCatalogIndex\(itemId\)/);
    assert.match(profileUiSource, /MasteryDefinitions\.GetMasteryProgress\(count, true\)/);
    assert.match(profileUiSource, /MasteryDefinitions\.Thresholds\.Gold/);
  });

  criterion("presentation sources contain no duplicated collection total or mastery thresholds", () => {
    for (const [name, source] of [["CollectionShelfService", shelfSource], ["ProfileUIController", profileUiSource]]) {
      assert.doesNotMatch(source, /\/\s*8\b|8\s*DISCOVERED/i, `${name} duplicates the canonical collection total`);
      assert.doesNotMatch(source, /\b(?:5|20|50)\+?\s+SHIPMENTS\b/i, `${name} duplicates a canonical mastery threshold in copy`);
      assert.doesNotMatch(source, /\bcount\s*(?:>=|>|==)\s*(?:5|20|50)\b/, `${name} duplicates mastery threshold logic`);
      assert.doesNotMatch(source, /\b(?:Bronze|Silver|Gold)(?:Threshold)?\s*=\s*(?:5|20|50)\b/i,
        `${name} defines a duplicate mastery threshold`);
    }
  });

  criterion("collection shelf render has deterministic idempotence and structural validation", () => {
    assert.match(shelfSource, /local function presentationFingerprint\(/);
    assert.match(shelfSource, /local function renderedStructureMatches\(/);
    assert.match(shelfSource, /cached\.Fingerprint == expected\.Fingerprint/);
    assert.match(shelfSource, /cached\.OwnerUserId == currentOwnerUserId/);
    assert.match(shelfSource, /and renderedStructureMatches\(record, expected, self\._template\)/);
    assert.match(shelfSource, /or not proxy\.Massless/);
    assert.equal((shelfSource.match(/return true, "UNCHANGED"/g) ?? []).length, 1);
    assert.equal((shelfSource.match(/return true, "RENDERED"/g) ?? []).length, 1);
    assert.match(shelfSource, /self\._rebuildCounts\[stationId\][\s\S]{0,120}\+ 1[\s\S]{0,120}return true, "RENDERED"/);
  });

  criterion("Studio regressions prove identical render is unchanged without rebuilding", () => {
    assert.match(phase05TestSource, /Name = "identical render preserves proxy identities without rebuilding"/);
    assert.match(phase05TestSource,
      /local secondOk, secondResult = service:Render\("station_01", profile\)[\s\S]{0,260}expectEqual\(secondResult, "UNCHANGED"\)/);
    assert.match(phase05TestSource,
      /Name = "identical render preserves proxy identities without rebuilding"[\s\S]{0,1400}expectEqual\(service:GetRebuildCount\("station_01"\), 1\)/);
  });

  criterion("Studio regression runs the memory adapter reward saving and saved shelf flow", () => {
    assert.match(phase05TestSource, /Name = "memory adapter reward saving and saved snapshots rebuild once"/);
    assert.match(phase05TestSource,
      /local adapter = MemoryProfileAdapter\.Create\(\)[\s\S]{0,260}local progression = ProgressionService\.Create\(harness\.Service\)/);
    assert.match(phase05TestSource,
      /expectEqual\(rewardResult, "RENDERED"\)[\s\S]{0,1800}expectEqual\(savingResult, "UNCHANGED"\)[\s\S]{0,240}expectEqual\(savedResult, "UNCHANGED"\)/);
    assert.match(phase05TestSource,
      /MEMORY_SHELF adapter=memory reward=%s saving=%s saved=%s rebuildDelta=1 identitiesStable=true childCountStable=true cleanup=%d/);
  });

  criterion("Studio regressions prove profile and structural changes rebuild", () => {
    assert.match(phase05TestSource, /Name = "mastery ordering is tier count then catalog"/);
    assert.match(phase05TestSource,
      /profile\.Collection\.MasteryCounts\.parcel = thresholds\.Gold \+ 1[\s\S]{0,240}expectEqual\(result, "RENDERED"\)/);
    assert.match(phase05TestSource, /Name = "malformed runtime is rebuilt instead of treated as unchanged"/);
    assert.match(phase05TestSource,
      /corruptProxy:SetAttribute\("ItemId", "not_a_catalog_item"\)[\s\S]{0,240}expectEqual\(result, "RENDERED"\)/);
  });

  criterion("Studio regressions prove clear owner isolation and the six-proxy bound", () => {
    assert.match(phase05TestSource, /Name = "release clears one shelf only and reassignment starts clean"/);
    assert.match(phase05TestSource, /Name = "station owner reassignment rebuilds only the reassigned shelf"/);
    assert.match(phase05TestSource,
      /stationOne:SetAttribute\("OwnerUserId", 303\)[\s\S]{0,260}expectEqual\(result, "RENDERED"\)/);
    assert.match(phase05TestSource,
      /expectEqual\(service:GetRebuildCount\("station_02"\), 1\)[\s\S]{0,180}expectEqual\(featuredInstances\(shelfRuntime\(stations, 2\)\)\[1\], stationTwoProxy\)/);
    assert.match(shelfSource, /local MAX_FEATURED_ITEMS = 6\b/);
    assert.match(phase05TestSource, /Name = "maximum six runtime proxies and cleanup returns to baseline"/);
    assert.match(phase05TestSource, /expectEqual\(service:GetRuntimeCount\("station_01"\), 6\)/);
  });

  const productionLuauFiles = listFilesRecursively(path.join(repositoryRoot, "src"))
    .filter((file) => file.endsWith(".luau") && !file.includes(`${path.sep}Dev${path.sep}`));
  criterion("no runtime permanent profile UI builder exists", () => {
    for (const file of productionLuauFiles) {
      const source = fs.readFileSync(file, "utf8");
      assert.doesNotMatch(source, /Instance\.new\s*\(\s*["'](?:ScreenGui|TextButton|TextLabel|ViewportFrame|UIStroke|UICorner)["']\s*\)/,
        `Runtime UI construction in ${path.relative(repositoryRoot, file)}`);
    }
  });

  criterion("no runtime permanent shelf builder exists", () => {
    for (const file of productionLuauFiles) {
      const source = fs.readFileSync(file, "utf8");
      assert.doesNotMatch(source, /Instance\.new[\s\S]{0,220}(?:CollectionShelf|ShelfBase|ShelfLabel|Slot_0[1-6])/,
        `Runtime shelf construction in ${path.relative(repositoryRoot, file)}`);
    }
  });

  criterion("all Phase 05 production sources begin strict", () => {
    for (const relativePath of phase05Sources) {
      assert.ok(fs.existsSync(path.join(repositoryRoot, relativePath)), `Missing Phase 05 source ${relativePath}`);
      assert.match(readText(relativePath), /^--!strict(?:\r?\n)/, `${relativePath} must begin with --!strict`);
    }
  });

  criterion("Phase 05 tests begin strict", () => {
    for (const relativePath of phase05TestSources) {
      assert.ok(fs.existsSync(path.join(repositoryRoot, relativePath)), `Missing Phase 05 test ${relativePath}`);
      assert.match(readText(relativePath), /^--!strict(?:\r?\n)/, `${relativePath} must begin with --!strict`);
    }
  });

  criterion("all Phase 05 canonical sources are mapped into Studio", () => {
    for (const relativePath of [...phase05Sources, ...phase05TestSources]) {
      const mapping = manifest.scripts.find((entry) => entry.sourceFile.replaceAll("\\", "/") === relativePath);
      assert.ok(mapping, `Missing manifest mapping for ${relativePath}`);
      assert.ok(scriptsByPath.has(mapping.path), `Missing generated script for ${mapping.path}`);
    }
  });

  criterion("existing station and arena paths remain unchanged", () => {
    for (let index = 1; index <= 8; index += 1) {
      const station = `Workspace.ONE_MORE_ITEM_WORLD.PlaytestArena.Stations.Station_${String(index).padStart(2, "0")}`;
      for (const relativePath of ["StationRoot", "PlayerStand", "CameraAnchor", "Crate.GridOrigin", "PlacedItems", "RuntimePresentation"]) {
        assert.ok(instancesByPath.has(`${station}.${relativePath}`), `Missing inherited path ${station}.${relativePath}`);
      }
    }
    for (const relativePath of ["ArenaFloor", "ArenaBackdrop", "CenterDispatch", "ShowcaseLoop.PathNodes.Node_01", "ShowcaseLoop.PathNodes.Node_16"]) {
      assert.ok(instancesByPath.has(`Workspace.ONE_MORE_ITEM_WORLD.PlaytestArena.${relativePath}`));
    }
  });

  criterion("generated authoring remains byte deterministic", () => {
    assert.deepEqual(secondBlueprintBytes, firstBlueprintBytes);
    assert.deepEqual(secondCommandBytes, firstCommandBytes);
  });

  criterion("repeating authoring creates no duplicate managed paths", () => {
    const paths = blueprint.steps.map((step) => step.path);
    assert.equal(new Set(paths).size, paths.length);
    const repeated = JSON.parse(secondBlueprintBytes.toString("utf8")).steps.map((step) => step.path);
    assert.deepEqual(repeated, paths);
  });

  criterion("wrong-class conflicts remain visible and non-destructive", () => {
    for (const operation of commandBar.operations) {
      assert.match(operation.command, /sync conflict/);
      const beforeSourceMutation = operation.type === "writeScript"
        ? operation.command.split("local sourceOk")[0]
        : operation.command;
      assert.doesNotMatch(beforeSourceMutation, /:Destroy\s*\(/);
      assert.match(operation.command, /duplicate managed child|same-name managed children|FindFirstChild/);
    }
  });

  const gitFiles = trackedFiles();
  criterion("tracked text contains no absolute local path", () => {
    for (const relativePath of gitFiles) {
      if (!/\.(?:md|json|mjs|ya?ml|luau|txt)$/i.test(relativePath)) continue;
      const source = readText(relativePath);
      assert.doesNotMatch(source, /C:[\\/]Users[\\/]|\/Users\/|file:\/\//i, `Absolute path in ${relativePath}`);
    }
  });

  criterion("no recovery file profile dump or cache is tracked", () => {
    assert.ok(gitFiles.every((file) => !/(^|\/)(?:\.codex-cache|\.codex-studio|recovery|autosave|profile-dumps?)(\/|$)/i.test(file)));
    assert.ok(gitFiles.every((file) => !/\.(?:rbxl|rbxlx|tmp|bak)$/i.test(file)));
  });

  criterion("workflow uses the exact Phase 01 through 06 Node 24 contract", () => {
    const workflow = readText(".github/workflows/phase01-node-validation.yml");
    assert.match(workflow, /^name:\s*Phase 01(?:\u2013|-)06 Node Validation/m);
    assert.match(workflow, /actions\/checkout@v7/);
    assert.match(workflow, /actions\/setup-node@v6/);
    assert.match(workflow, /node-version:\s*24/);
    assert.match(workflow, /package-manager-cache:\s*false/);
    assert.match(workflow, /permissions:\s*[\s\S]*contents:\s*read/);
    assert.doesNotMatch(workflow, /^\s*run:\s*(?:npm (?:install|ci)|pnpm\b|yarn\b|bun\b)/m);
  });

  criterion("workflow runs all six Node gates in order", () => {
    const workflow = readText(".github/workflows/phase01-node-validation.yml");
    const commands = [...workflow.matchAll(/^\s*run:\s*(node tools\/test_[^\s]+\.mjs)\s*$/gm)].map((match) => match[1]);
    assert.deepEqual(commands, [
      "node tools/test_studio_blueprint.mjs",
      "node tools/test_phase02_blueprint.mjs",
      "node tools/test_phase03_cross_platform.mjs",
      "node tools/test_phase04_multiplayer_arena.mjs",
      "node tools/test_phase05_persistent_progression.mjs",
      "node tools/test_phase06_onboarding_missions_analytics.mjs",
    ]);
  });

  criterion("workflow triggers remain exact", () => {
    const workflow = readText(".github/workflows/phase01-node-validation.yml");
    assert.match(workflow, /pull_request:[\s\S]*branches:[\s\S]*- main/);
    assert.match(workflow, /push:[\s\S]*branches:[\s\S]*- main[\s\S]*- ['"]codex\/\*\*['"]/);
  });

  criterion("Phase 04 merge SHA is documented correctly", () => {
    const docs = `${readText("README.md")}\n${readText("docs/DEVELOPMENT_STATUS.md")}`;
    assert.match(docs, /213f3581bd242523e34601cfefa5b5a74770ddee/);
    assert.match(docs, /PR #5[^\n]*merged|merged[^\n]*PR #5/i);
  });

  criterion("issue four remains referenced and open", () => {
    const docs = `${readText("README.md")}\n${readText("docs/DEVELOPMENT_STATUS.md")}`;
    assert.match(docs, /issues\/4/);
    assert.match(docs, /Issue #4[^\n]*(?:open|remains open)|open[^\n]*Issue #4/i);
    assert.doesNotMatch(docs, /Issue #4[^\n]*(?:closed|resolved)/i);
  });

  criterion("Phase 05 merged baseline and honest Phase 06 closeout status are documented", () => {
    const docs = `${readText("README.md")}\n${readText("docs/DEVELOPMENT_STATUS.md")}`;
    assert.match(docs, /d644411b48e20cd9bb256d3d2c55a647efc2adfd/);
    assert.match(docs, /PR #6[^\n]*merged|merged[^\n]*PR #6/i);
    assert.match(docs, /codex\/phase-06-onboarding-starter-missions/);
    assert.match(docs, /pull\/7|PR #7/);
    assert.match(docs, /draft[^\n]*(?:unmerged|not merged)|(?:unmerged|not merged)[^\n]*draft/i);
    assert.match(docs, /Phase 06[^\n]*(?:implementation complete and accepted|complete and accepted)/i);
    assert.doesNotMatch(docs, /Phase 06[^\n]*(?:not yet accepted|unaccepted|acceptance (?:is )?partial|acceptance partial)/i);
  });

  criterion("phase02 manifest remains the sole Phase 02 through 06 owner", () => {
    const manifests = gitFiles.filter((file) => /^studio\/.*\.manifest\.json$/i.test(file)).sort();
    assert.deepEqual(manifests, ["studio/phase01.manifest.json", "studio/phase02.manifest.json"]);
    assert.equal(manifest.mode, "edit");
    assert.equal(manifest.stationPlacements.length, 8);
  });

  criterion("profile snapshots exclude secrets and receipts", () => {
    assert.doesNotMatch(snapshotBuilderSource, /\bToken\b|ProcessedOutcomeIds|Receipts|DataStoreKey/);
    assert.match(snapshotBuilderSource, /ProfileSessionId/);
    assert.match(snapshotBuilderSource, /Revision/);
    assert.match(snapshotBuilderSource, /table\.freeze/);
  });

  criterion("snapshot revisions are monotonic and client rejects stale duplicates", () => {
    const clientStore = readText("src/StarterPlayer/StarterPlayerScripts/ONE_MORE_ITEM_Client/Controllers/ClientProfileStore.luau");
    assert.match(profileServiceSource, /entry\.SnapshotRevision \+= 1/);
    assert.match(clientStore, /snapshot\.Revision <= previous\.Revision/);
    assert.match(clientStore, /previous\.ProfileSessionId == snapshot\.ProfileSessionId/);
  });

  criterion("profile autosave uses one shared bounded scheduler", () => {
    assert.match(configSource, /DIRTY_SAVE_DEBOUNCE_SECONDS\s*=\s*5\b/);
    assert.match(configSource, /AUTOSAVE_INTERVAL_SECONDS\s*=\s*60\b/);
    assert.match(configSource, /MAXIMUM_SIMULTANEOUS_SAVES\s*=\s*8\b/);
    assert.match(configSource, /SHUTDOWN_DEADLINE_SECONDS\s*=\s*25\b/);
    assert.match(profileServiceSource, /_scheduledHandle/);
    assert.doesNotMatch(profileServiceSource, /while true do|RunService\.(?:Heartbeat|Stepped|RenderStepped):Connect/);
  });

  criterion("load save and release transforms enforce lock ownership", () => {
    assert.ok((dataStoreSource.match(/stored\.Session\.Token ~= token/g) ?? []).length >= 3);
    assert.match(dataStoreSource, /currentSession\.Token ~= claim\.Token/);
    assert.ok((dataStoreSource.match(/return nil/g) ?? []).length >= 4);
  });

  criterion("progression formulas and duplicate receipts are authoritative", () => {
    assert.match(progressionSource, /10 \+ \(4 \* itemCount\) \+ math\.floor\(shipmentValue \/ 100\) \+ perfectBonus/);
    assert.match(progressionSource, /math\.min\(itemCount \* 2, 10\)/);
    assert.match(progressionSource, /if hasReceipt\(profile, outcomeId\) then/);
    assert.match(progressionSource, /UNKNOWN_ITEM_ID/);
  });

  criterion("round progression precedes cosmetic callbacks", () => {
    const shipmentProgression = roundSource.indexOf(":ApplyShipment(");
    const shipmentCosmetic = roundSource.indexOf("OnShipmentCompleted", Math.max(0, shipmentProgression));
    const failureProgression = roundSource.indexOf(":ApplyFailure(");
    const failureCosmetic = roundSource.indexOf("OnRoundFailed", Math.max(0, failureProgression));
    assert.ok(shipmentProgression >= 0 && shipmentCosmetic > shipmentProgression);
    assert.ok(failureProgression >= 0 && failureCosmetic > failureProgression);
    assert.match(roundSource, /GetTape/);
  });

  criterion("client request contracts contain no profile authority fields", () => {
    const forbidden = ["Tape", "PackingXP", "Rank", "Discovery", "Mastery", "ProfileRevision", "SessionLock"];
    const requestSection = networkTypesSource.split("export type RoundSnapshot")[0];
    for (const field of forbidden) assert.doesNotMatch(requestSection, new RegExp(`\\b${field}\\b`));
  });

  assert.ok(criterionCount >= 63, `Phase 05 validator must retain at least 63 criteria; found ${criterionCount}`);
  console.log(
    `[Phase05PersistentProgression] PASS criteria=${criterionCount} instances=${instanceSteps.length} scripts=${scriptSteps.length} gameplayRemotes=6 profileRemotes=1 shelves=8 collectionSlots=8 deterministic=true prior=true`,
  );
} catch (error) {
  console.error(`[Phase05PersistentProgression] FAIL criterion=${criterionCount + 1} ${error instanceof Error ? error.message : String(error)}`);
  process.exitCode = 1;
} finally {
  if (temporaryRoot) fs.rmSync(temporaryRoot, { recursive: true, force: true });
}
