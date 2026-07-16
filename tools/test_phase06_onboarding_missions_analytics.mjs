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
const workflowPath = path.join(repositoryRoot, ".github", "workflows", "phase01-node-validation.yml");
const priorGates = [
  ["test_studio_blueprint.mjs", /\[StudioSyncSmoke\] PASS checks=16 folders=7 scripts=10 deterministic=true/],
  ["test_phase02_blueprint.mjs", /\[Phase02StudioSyncSmoke\] PASS criteria=\d+ instances=\d+ scripts=\d+ remotes=6 deterministic=true phase01=true/],
  ["test_phase03_cross_platform.mjs", /\[Phase03CrossPlatformSmoke\] PASS criteria=\d+ viewports=13 insetProfiles=5 layoutCases=65 remotes=6 deterministic=true phase01=true phase02=true/],
  ["test_phase04_multiplayer_arena.mjs", /\[Phase04MultiplayerArena\] PASS criteria=\d+ instances=\d+ scripts=\d+ stations=8 pathNodes=16 remotes=6 deterministic=true prior=true/],
  ["test_phase05_persistent_progression.mjs", /\[Phase05PersistentProgression\] PASS criteria=\d+ instances=\d+ scripts=\d+ gameplayRemotes=6 profileRemotes=1 shelves=8 collectionSlots=8 deterministic=true prior=true/],
];
const gameplayRemoteNames = [
  "ClientReadyRequest",
  "DecisionRequest",
  "PlaceItemRequest",
  "PlacementResponse",
  "RestartRequest",
  "RoundSnapshot",
];
const onboardingStepNames = [
  "PROFILE READY",
  "STATION ASSIGNED",
  "FIRST ITEM PLACED",
  "FIRST DECISION SHOWN",
  "FIRST SHIPMENT COMPLETED",
];
const missionContract = [
  ["first_fit", "AcceptedPlacement", 1, 10, 10],
  ["first_shipment", "SuccessfulShipment", 1, 25, 20],
  ["one_more", "OneMoreAccepted", 1, 35, 30],
  ["collector_three", "DiscoveredCount", 3, 75, 50],
  ["five_item_box", "ShipmentItemCount", 5, 150, 100],
];
const phase06Sources = [
  "src/ReplicatedStorage/ONE_MORE_ITEM/Shared/Profile/OnboardingDefinitions.luau",
  "src/ReplicatedStorage/ONE_MORE_ITEM/Shared/Profile/StarterMissionDefinitions.luau",
  "src/ServerScriptService/ONE_MORE_ITEM_Server/Services/Profile/OnboardingService.luau",
  "src/ServerScriptService/ONE_MORE_ITEM_Server/Services/Profile/StarterMissionService.luau",
  "src/ServerScriptService/ONE_MORE_ITEM_Server/Services/OnboardingRequestValidator.luau",
  "src/ServerScriptService/ONE_MORE_ITEM_Server/Services/Analytics/AnalyticsAdapter.luau",
  "src/ServerScriptService/ONE_MORE_ITEM_Server/Services/Analytics/AnalyticsEventDefinitions.luau",
  "src/ServerScriptService/ONE_MORE_ITEM_Server/Services/Analytics/MemoryAnalyticsAdapter.luau",
  "src/ServerScriptService/ONE_MORE_ITEM_Server/Services/Analytics/RobloxAnalyticsAdapter.luau",
  "src/ServerScriptService/ONE_MORE_ITEM_Server/Services/Analytics/GameAnalyticsService.luau",
  "src/StarterPlayer/StarterPlayerScripts/ONE_MORE_ITEM_Client/Controllers/OnboardingUIController.luau",
  "src/StarterPlayer/StarterPlayerScripts/ONE_MORE_ITEM_Client/Controllers/StarterMissionUIController.luau",
];
const phase06Tests = [
  "src/ServerScriptService/ONE_MORE_ITEM_Server/Dev/Phase06TestSuite.luau",
  "src/ServerScriptService/ONE_MORE_ITEM_Server/Dev/RunPhase06Tests.server.luau",
];
const uiRoot = "StarterGui.ONE_MORE_ITEM_Gameplay.Root";
const expectedUiPaths = [
  `${uiRoot}.OnboardingOverlay`,
  `${uiRoot}.OnboardingOverlay.Prompt`,
  `${uiRoot}.OnboardingOverlay.Instruction`,
  `${uiRoot}.OnboardingOverlay.InputHint`,
  `${uiRoot}.OnboardingOverlay.StepProgress`,
  `${uiRoot}.OnboardingOverlay.TutorialPointer`,
  `${uiRoot}.OnboardingOverlay.SkipButton`,
  `${uiRoot}.OnboardingOverlay.SkipHoldProgress`,
  `${uiRoot}.StarterMissionCard`,
  `${uiRoot}.StarterMissionCard.Header`,
  `${uiRoot}.StarterMissionCard.MissionName`,
  `${uiRoot}.StarterMissionCard.Description`,
  `${uiRoot}.StarterMissionCard.ProgressText`,
  `${uiRoot}.StarterMissionCard.ProgressBar`,
  `${uiRoot}.StarterMissionCard.ProgressBar.Background`,
  `${uiRoot}.StarterMissionCard.ProgressBar.Fill`,
  `${uiRoot}.StarterMissionCard.RewardText`,
  `${uiRoot}.StarterMissionCard.OpenPathButton`,
  `${uiRoot}.StarterPathPanel`,
  `${uiRoot}.StarterPathPanel.Header`,
  `${uiRoot}.StarterPathPanel.Summary`,
  `${uiRoot}.StarterPathPanel.CloseButton`,
  `${uiRoot}.StarterPathPanel.Missions`,
  `${uiRoot}.MissionCompleteBanner`,
  `${uiRoot}.MissionCompleteBanner.Header`,
  `${uiRoot}.MissionCompleteBanner.MissionName`,
  `${uiRoot}.MissionCompleteBanner.RewardText`,
  `${uiRoot}.MissionCompleteBanner.PathProgress`,
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

function listFilesRecursively(directory) {
  const result = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const child = path.join(directory, entry.name);
    if (entry.isDirectory()) result.push(...listFilesRecursively(child));
    else result.push(child);
  }
  return result;
}

function trackedFiles() {
  const result = spawnSync("git", ["ls-files", "-z"], { cwd: repositoryRoot, encoding: "buffer" });
  assert.equal(result.status, 0, `git ls-files failed: ${result.stderr.toString("utf8")}`);
  return result.stdout.toString("utf8").split("\0").filter(Boolean);
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

function escaped(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

try {
  for (const gate of priorGates) requirePriorGate(gate);

  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "one-more-item-phase06-"));
  const firstOutput = path.join(temporaryRoot, "first");
  const secondOutput = path.join(temporaryRoot, "second");
  const firstGeneration = runNode(generatorPath, [manifestPath, firstOutput]);
  assert.equal(firstGeneration.status, 0, `Phase 06 generation failed:\n${firstGeneration.stderr || firstGeneration.stdout}`);
  const secondGeneration = runNode(generatorPath, [manifestPath, secondOutput]);
  assert.equal(secondGeneration.status, 0, `Repeated Phase 06 generation failed:\n${secondGeneration.stderr || secondGeneration.stdout}`);

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

  const profileConfig = readText("src/ServerScriptService/ONE_MORE_ITEM_Server/Services/Profile/ProfileConfig.luau");
  const profileSchema = readText("src/ServerScriptService/ONE_MORE_ITEM_Server/Services/Profile/ProfileSchema.luau");
  const profileTypes = readText("src/ServerScriptService/ONE_MORE_ITEM_Server/Services/Profile/ProfileTypes.luau");
  const snapshotBuilder = readText("src/ServerScriptService/ONE_MORE_ITEM_Server/Services/Profile/ProfileSnapshotBuilder.luau");
  const profileNetworkTypes = readText("src/ReplicatedStorage/ONE_MORE_ITEM/Shared/Profile/ProfileNetworkTypes.luau");
  const onboardingDefinitions = readText("src/ReplicatedStorage/ONE_MORE_ITEM/Shared/Profile/OnboardingDefinitions.luau");
  const missionDefinitions = readText("src/ReplicatedStorage/ONE_MORE_ITEM/Shared/Profile/StarterMissionDefinitions.luau");
  const parsedMissions = [...missionDefinitions.matchAll(
    /mission\(\s*(\d+),\s*"([^"]+)",\s*"[^"]+",\s*"[^"]+",\s*"([^"]+)",\s*(\d+),\s*(\d+),\s*(\d+)\s*\)/g,
  )].map((match) => [match[2], match[3], Number(match[4]), Number(match[5]), Number(match[6])]);
  const onboardingService = readText("src/ServerScriptService/ONE_MORE_ITEM_Server/Services/Profile/OnboardingService.luau");
  const missionService = readText("src/ServerScriptService/ONE_MORE_ITEM_Server/Services/Profile/StarterMissionService.luau");
  const analyticsContract = readText("src/ServerScriptService/ONE_MORE_ITEM_Server/Services/Analytics/AnalyticsAdapter.luau");
  const analyticsEvents = readText("src/ServerScriptService/ONE_MORE_ITEM_Server/Services/Analytics/AnalyticsEventDefinitions.luau");
  const memoryAnalytics = readText("src/ServerScriptService/ONE_MORE_ITEM_Server/Services/Analytics/MemoryAnalyticsAdapter.luau");
  const robloxAnalytics = readText("src/ServerScriptService/ONE_MORE_ITEM_Server/Services/Analytics/RobloxAnalyticsAdapter.luau");
  const gameAnalytics = readText("src/ServerScriptService/ONE_MORE_ITEM_Server/Services/Analytics/GameAnalyticsService.luau");
  const roundConfig = readText("src/ReplicatedStorage/ONE_MORE_ITEM/Shared/Config/RoundConfig.luau");
  const roundService = readText("src/ServerScriptService/ONE_MORE_ITEM_Server/Services/RoundService.luau");
  const bootstrap = readText("src/ServerScriptService/ONE_MORE_ITEM_Server/ServerBootstrap.server.luau");
  const onboardingRequestValidator = readText("src/ServerScriptService/ONE_MORE_ITEM_Server/Services/OnboardingRequestValidator.luau");
  const clientProfileStore = readText("src/StarterPlayer/StarterPlayerScripts/ONE_MORE_ITEM_Client/Controllers/ClientProfileStore.luau");
  const onboardingUi = readText("src/StarterPlayer/StarterPlayerScripts/ONE_MORE_ITEM_Client/Controllers/OnboardingUIController.luau");
  const missionUi = readText("src/StarterPlayer/StarterPlayerScripts/ONE_MORE_ITEM_Client/Controllers/StarterMissionUIController.luau");
  const responsiveLayout = readText("src/StarterPlayer/StarterPlayerScripts/ONE_MORE_ITEM_Client/Controllers/ResponsiveLayout.luau");
  const phase06TestSource = readText("src/ServerScriptService/ONE_MORE_ITEM_Server/Dev/Phase06TestSuite.luau");

  criterion("profile schema version is exactly two", () => {
    assert.match(profileConfig, /SCHEMA_VERSION\s*=\s*2\b/);
    assert.match(profileSchema, /SchemaVersion\s*=\s*ProfileConfig\.SCHEMA_VERSION/);
  });

  criterion("Version 1 to Version 2 migration is explicit", () => {
    assert.match(profileSchema, /local\s+function\s+migrateV1\s*\(/);
    assert.match(
      profileSchema,
      /if\s+version\s*==\s*1\s+then\s+return\s+migrateV1\s*\(\s*raw\s*,\s*now\s*\)\s*,\s*"MIGRATED_V1_TO_V2"/,
    );
  });

  criterion("profile migration remains deterministic and non-yielding", () => {
    assert.doesNotMatch(profileSchema, /task\.wait|coroutine\.yield|WaitForChild\s*\(/);
    assert.match(profileSchema, /function ProfileSchema\.Clone/);
    assert.match(profileSchema, /function ProfileSchema\.Migrate/);
  });

  criterion("Version 0 continues through the current schema", () => {
    assert.match(profileSchema, /migrateV0/i);
    assert.match(phase06TestSource, /Version 0[^\n]*(?:Version 2|current schema)|Version 0.*migrat/is);
  });

  criterion("profile store names remain the accepted v1 namespaces", () => {
    assert.match(profileConfig, /PRODUCTION_STORE_NAME\s*=\s*"ONE_MORE_ITEM_PlayerProfiles_v1"/);
    assert.match(profileConfig, /STUDIO_STORE_NAME\s*=\s*"ONE_MORE_ITEM_PlayerProfiles_StudioTest_v1"/);
  });

  criterion("onboarding profile fields are typed and normalized", () => {
    for (const token of ["Onboarding", "NotStarted", "InProgress", "Completed", "Skipped", "HighestStep", "CompletedAt"]) {
      assert.match(`${profileTypes}\n${profileSchema}`, new RegExp(`\\b${token}\\b`));
    }
  });

  criterion("starter mission profile fields are typed and normalized", () => {
    for (const token of ["StarterMissions", "Progress", "Completed", "Rewarded", "PathCompleted", "CompletedAt"]) {
      assert.match(`${profileTypes}\n${profileSchema}`, new RegExp(`\\b${token}\\b`));
    }
  });

  criterion("new mission statistics are canonical", () => {
    assert.match(`${profileTypes}\n${profileSchema}`, /TotalMissionTapeEarned/);
    assert.match(`${profileTypes}\n${profileSchema}`, /TotalStarterMissionsCompleted/);
  });

  criterion("OnboardingDefinitions exposes the required pure APIs", () => {
    for (const name of ["GetStep", "GetStepName", "GetNextStep", "IsTerminal", "NormalizeStatus"]) {
      assert.match(onboardingDefinitions, new RegExp(`function OnboardingDefinitions\\.${name}\\b`));
    }
  });

  criterion("exactly five stable onboarding step labels exist", () => {
    for (const [index, name] of onboardingStepNames.entries()) {
      assert.match(onboardingDefinitions, new RegExp(`(?:Step|Index|Number)\\s*=\\s*${index + 1}\\b[\\s\\S]{0,180}${escaped(name)}`));
    }
    assert.match(onboardingDefinitions, /TotalCount\s*=\s*(?:5\b|#ordered)/);
    assert.match(onboardingDefinitions, /MaximumStep\s*=\s*(?:5\b|#ordered)/);
  });

  criterion("StarterMissionDefinitions exposes the required pure APIs", () => {
    for (const name of ["Get", "GetIndex", "GetGoal", "GetReward", "GetFirstIncomplete", "GetTotalCount", "IsValidMissionId"]) {
      assert.match(missionDefinitions, new RegExp(`function StarterMissionDefinitions\\.${name}\\b`));
    }
  });

  criterion("exactly five starter mission IDs exist in stable order", () => {
    assert.deepEqual(parsedMissions.map((mission) => mission[0]), missionContract.map((mission) => mission[0]));
    assert.match(missionDefinitions, /TotalCount\s*=\s*#ordered|TotalCount\s*=\s*5\b/);
  });

  criterion("mission goal types and exact goals match the approved contract", () => {
    assert.deepEqual(parsedMissions.map((mission) => mission.slice(0, 3)), missionContract.map((mission) => mission.slice(0, 3)));
  });

  criterion("mission Tape rewards match the approved contract", () => {
    assert.deepEqual(parsedMissions.map((mission) => [mission[0], mission[3]]), missionContract.map((mission) => [mission[0], mission[3]]));
  });

  criterion("mission XP rewards match the approved contract", () => {
    assert.deepEqual(parsedMissions.map((mission) => [mission[0], mission[4]]), missionContract.map((mission) => [mission[0], mission[4]]));
  });

  criterion("mission reward totals are exactly 295 Tape and 210 XP", () => {
    assert.equal(missionContract.reduce((sum, mission) => sum + mission[3], 0), 295);
    assert.equal(missionContract.reduce((sum, mission) => sum + mission[4], 0), 210);
    assert.equal(parsedMissions.reduce((sum, mission) => sum + mission[3], 0), 295);
    assert.equal(parsedMissions.reduce((sum, mission) => sum + mission[4], 0), 210);
    assert.match(missionDefinitions, /TotalTapeReward\s*=\s*totalTapeReward/);
    assert.match(missionDefinitions, /TotalXPReward\s*=\s*totalXPReward/);
  });

  criterion("OnboardingService is a focused server mutation boundary", () => {
    for (const method of ["Create", "Advance", "Skip", "IsGuided"]) {
      assert.match(onboardingService, new RegExp(`function OnboardingService\\.${method}\\b`));
    }
    assert.doesNotMatch(onboardingService, /StarterGui|PlayerGui|DataStoreService/);
  });

  criterion("StarterMissionService is a focused authoritative mutation boundary", () => {
    for (const method of ["Create", "ApplyEvent", "ApplyEventToProfile"]) {
      assert.match(missionService, new RegExp(`function StarterMissionService\\.${method}\\b`));
    }
    assert.doesNotMatch(missionService, /StarterGui|PlayerGui|DataStoreService|OnServerEvent/);
  });

  criterion("mission rewards use deterministic bounded reward IDs", () => {
    assert.match(missionService, /starter:v1:/);
    assert.match(missionService, /Rewarded/);
    assert.match(missionService, /Duplicate/);
  });

  criterion("mission analytics follow snapshot economy completion custom and next-spotlight order", () => {
    const applyEvent = missionService.indexOf("function StarterMissionService.ApplyEvent");
    const economy = missionService.indexOf("LogEconomySource", applyEvent);
    const complete = missionService.indexOf("LogProgressionComplete", economy);
    const customComplete = missionService.indexOf("\"completed\"", complete);
    const nextStart = missionService.indexOf("LogProgressionStart", customComplete);
    assert.ok(applyEvent >= 0 && economy > applyEvent && complete > economy && customComplete > complete && nextStart > customComplete);
    assert.match(missionService, /StartCurrentSpotlight/);
  });

  criterion("guided timing constants are exact", () => {
    assert.match(roundConfig, /GUIDED_PLACEMENT_DURATION\s*=\s*45\b/);
    assert.match(roundConfig, /GUIDED_DECISION_DURATION\s*=\s*12\b/);
  });

  criterion("guided timing is server-derived and presentation-safe", () => {
    assert.match(`${roundService}\n${profileNetworkTypes}`, /GuidedOnboarding/);
    assert.doesNotMatch(onboardingUi, /GuidedOnboarding\s*=/);
  });

  criterion("analytics adapter contract is server-only and focused", () => {
    for (const name of ["LogOnboardingStep", "LogCustom", "LogEconomySource", "LogProgressionStart", "LogProgressionComplete", "LogProgressionFail", "GetEnvironment"]) {
      assert.match(analyticsContract, new RegExp(`\\b${name}\\b`));
    }
    assert.doesNotMatch(analyticsContract, /DataStoreService|StarterGui|PlayerGui/);
  });

  criterion("memory analytics adapter deep copies and supports failure inspection", () => {
    assert.match(memoryAnalytics, /copyValue/);
    assert.match(memoryAnalytics, /SetFailureCount/);
    assert.match(memoryAnalytics, /GetRecords/);
    assert.doesNotMatch(memoryAnalytics, /AnalyticsService|LogOnboardingFunnelStepEvent|LogCustomEvent/);
  });

  criterion("Studio selects memory analytics", () => {
    assert.match(gameAnalytics, /RunService:IsStudio\(\)/);
    assert.match(gameAnalytics, /MemoryAnalyticsAdapter/);
  });

  criterion("published non-Studio servers select the Roblox analytics adapter", () => {
    assert.match(gameAnalytics, /RobloxAnalyticsAdapter/);
    assert.match(gameAnalytics, /if[^\n]*IsStudio|IsStudio\(\)[\s\S]{0,300}else/);
  });

  criterion("Roblox analytics uses current nondeprecated Log methods", () => {
    for (const name of [
      "LogOnboardingFunnelStepEvent",
      "LogCustomEvent",
      "LogEconomyEvent",
      "LogProgressionStartEvent",
      "LogProgressionCompleteEvent",
      "LogProgressionFailEvent",
    ]) assert.match(robloxAnalytics, new RegExp(`:${name}\\b`));
  });

  criterion("deprecated analytics APIs and ApiKey are absent", () => {
    const allAnalytics = `${analyticsContract}\n${analyticsEvents}\n${memoryAnalytics}\n${robloxAnalytics}\n${gameAnalytics}`;
    assert.doesNotMatch(allAnalytics, /\bFireCustomEvent\b|\bFireEvent\b|\bFireInGameEconomyEvent\b|\bFirePlayerProgressionEvent\b|\.ApiKey\b/);
  });

  criterion("every Roblox analytics call is protected", () => {
    assert.match(robloxAnalytics, /pcall/);
    const callCount = (robloxAnalytics.match(/AnalyticsService|_analyticsService/g) ?? []).length;
    const pcallCount = (robloxAnalytics.match(/pcall/g) ?? []).length;
    assert.ok(callCount >= 6 && pcallCount >= 1);
  });

  const clientLuauFiles = listFilesRecursively(path.join(repositoryRoot, "src", "StarterPlayer"))
    .filter((file) => file.endsWith(".luau"));
  criterion("client source never accesses AnalyticsService", () => {
    for (const file of clientLuauFiles) {
      assert.doesNotMatch(fs.readFileSync(file, "utf8"), /AnalyticsService|LogCustomEvent|LogEconomyEvent|LogOnboardingFunnelStepEvent|LogProgression/,
        `Client analytics call in ${path.relative(repositoryRoot, file)}`);
    }
  });

  criterion("analytics custom event names are fixed and bounded", () => {
    for (const name of ["CoreLoopRound", "OneMoreAccepted", "StarterMission", "OnboardingSkipped", "SessionDuration"]) {
      assert.match(analyticsEvents, new RegExp(`"${name}"`));
    }
    assert.doesNotMatch(analyticsEvents, /UserId|DisplayName|OutcomeId|RoundId|StationId/);
  });

  criterion("analytics custom fields are allowlisted and bounded", () => {
    for (const field of ["phase", "item_count_bucket", "reason", "difficulty", "mission_id", "status", "highest_step", "profile_ready", "station_assigned"]) {
      assert.match(analyticsEvents, new RegExp(`"${field}"`));
    }
    assert.match(analyticsEvents, /MaximumCustomFields\s*=\s*3\b/);
    assert.match(gameAnalytics, /GetCustomFieldOrder\s*\(\s*eventName\s*\)/);
    assert.match(gameAnalytics, /count\s*>=\s*AnalyticsEventDefinitions\.MaximumCustomFields/);
  });

  criterion("analytics has no per-frame or per-move source", () => {
    const allAnalytics = `${analyticsContract}\n${analyticsEvents}\n${memoryAnalytics}\n${robloxAnalytics}\n${gameAnalytics}`;
    assert.doesNotMatch(allAnalytics, /RenderStepped|Heartbeat:Connect|Stepped:Connect|while true do|PointerMoved|MouseMoved/);
  });

  criterion("onboarding request remote is permanently authored", () => {
    assertPath(instancesByPath, "ReplicatedStorage.ONE_MORE_ITEM.OnboardingNet", "Folder");
    assertPath(instancesByPath, "ReplicatedStorage.ONE_MORE_ITEM.OnboardingNet.OnboardingActionRequest", "RemoteEvent");
  });

  criterion("gameplay Net remains exactly six remotes", () => {
    const names = instanceSteps
      .filter((step) => step.className === "RemoteEvent" && step.path.startsWith("ReplicatedStorage.ONE_MORE_ITEM.Net."))
      .map((step) => step.path.split(".").at(-1)).sort();
    assert.deepEqual(names, [...gameplayRemoteNames].sort());
  });

  criterion("ProfileNet remains exactly one server-to-client remote", () => {
    const remotes = instanceSteps.filter((step) => step.className === "RemoteEvent" && step.path.startsWith("ReplicatedStorage.ONE_MORE_ITEM.ProfileNet."));
    assert.equal(remotes.length, 1);
    assert.equal(remotes[0].path, "ReplicatedStorage.ONE_MORE_ITEM.ProfileNet.ProfileSnapshot");
  });

  criterion("OnboardingActionRequest is the only new Phase 06 client-to-server remote", () => {
    const onboardingRemotes = instanceSteps.filter((step) => step.className === "RemoteEvent" && step.path.startsWith("ReplicatedStorage.ONE_MORE_ITEM.OnboardingNet."));
    assert.equal(onboardingRemotes.length, 1);
    assert.equal(onboardingRemotes[0].path.endsWith(".OnboardingActionRequest"), true);
  });

  criterion("no general client profile mutation remote exists", () => {
    for (const step of instanceSteps.filter((entry) => entry.className === "RemoteEvent")) {
      assert.doesNotMatch(step.path, /Profile(?:Mutation|Action|Update|Reward|Mission)(?:Request)?$/i);
    }
  });

  criterion("onboarding request source validates SKIP and monotonic sequence", () => {
    assert.match(`${bootstrap}\n${onboardingRequestValidator}`, /OnboardingActionRequest/);
    assert.match(onboardingRequestValidator, /Action[^\n]*SKIP|SKIP[^\n]*Action/);
    assert.match(onboardingRequestValidator, /ClientSequence/);
    assert.match(onboardingRequestValidator, /_lastAccepted|DUPLICATE_SEQUENCE/);
  });

  criterion("onboarding request rate and session bounds are exact", () => {
    assert.match(roundConfig, /OnboardingActionRequest\s*=\s*2\b/);
    assert.match(onboardingRequestValidator, /DEFAULT_RATE_LIMIT_PER_SECOND\s*=\s*2\b/);
    assert.match(onboardingRequestValidator, /DEFAULT_WARNING_THRESHOLD\s*=\s*10\b/);
  });

  criterion("onboarding request never trusts reward or mission fields", () => {
    assert.doesNotMatch(onboardingRequestValidator, /request\.(?:Tape|PackingXP|XP|Rank|Mission|Reward|Profile)/);
    assert.match(onboardingRequestValidator, /table\.freeze\(\{[\s\S]{0,180}Action\s*=\s*"SKIP"[\s\S]{0,180}ClientSequence/);
  });

  criterion("all permanent Phase 06 top-level UI paths are authored", () => {
    for (const instancePath of expectedUiPaths) assert.ok(instancesByPath.has(instancePath), `Missing ${instancePath}`);
  });

  criterion("exactly five mission rows are permanently authored", () => {
    const root = `${uiRoot}.StarterPathPanel.Missions`;
    const rows = instanceSteps.filter((step) => step.path.match(new RegExp(`^${escaped(root)}\\.Mission_\\d{2}$`)));
    assert.deepEqual(rows.map((row) => row.path.split(".").at(-1)).sort(), ["Mission_01", "Mission_02", "Mission_03", "Mission_04", "Mission_05"]);
  });

  criterion("every mission row has the complete authored topology", () => {
    const children = ["Status", "MissionName", "Description", "ProgressText", "RewardText", "ProgressBar", "ProgressBar.Fill", "Corner", "Stroke"];
    for (let index = 1; index <= 5; index += 1) {
      const row = `${uiRoot}.StarterPathPanel.Missions.Mission_${String(index).padStart(2, "0")}`;
      for (const child of children) assert.ok(instancesByPath.has(`${row}.${child}`), `Missing ${row}.${child}`);
    }
  });

  criterion("existing CollectionPanel remains permanently authored", () => {
    assert.ok(instancesByPath.has(`${uiRoot}.CollectionPanel`));
  });

  criterion("no runtime permanent onboarding or mission UI builder exists", () => {
    const production = listFilesRecursively(path.join(repositoryRoot, "src"))
      .filter((file) => file.endsWith(".luau") && !file.includes(`${path.sep}Dev${path.sep}`));
    for (const file of production) {
      const source = fs.readFileSync(file, "utf8");
      assert.doesNotMatch(source, /Instance\.new[\s\S]{0,220}(?:OnboardingOverlay|StarterMissionCard|StarterPathPanel|MissionCompleteBanner|Mission_0[1-5])/,
        `Runtime permanent Phase 06 UI construction in ${path.relative(repositoryRoot, file)}`);
    }
  });

  criterion("responsive layout owns onboarding and mission targets", () => {
    for (const name of ["OnboardingOverlay", "StarterMissionCard", "StarterPathPanel", "MissionCompleteBanner"]) {
      assert.match(responsiveLayout, new RegExp(`\\b${name}\\b`));
    }
    for (const profile of ["Wide", "CompactLandscape", "Portrait"]) assert.match(responsiveLayout, new RegExp(`\\b${profile}\\b`));
  });

  criterion("profile snapshot copies onboarding and mission presentation", () => {
    for (const token of ["SchemaVersion", "Onboarding", "StarterMissions", "LastMissionRewards"]) {
      assert.match(`${snapshotBuilder}\n${profileNetworkTypes}`, new RegExp(`\\b${token}\\b`));
    }
    assert.match(snapshotBuilder, /table\.freeze/);
  });

  criterion("profile snapshot contains no lock receipt or analytics payload", () => {
    assert.doesNotMatch(snapshotBuilder, /\bToken\b|ProcessedOutcomeIds|Receipts|DataStoreKey|Analytics(?:Events|Records|Payload)/);
  });

  criterion("client profile store deep copies mission batches and rejects stale revisions", () => {
    assert.match(clientProfileStore, /LastMissionRewards/);
    assert.match(clientProfileStore, /snapshot\.Revision <= previous\.Revision/);
    assert.match(clientProfileStore, /ProfileSessionId/);
  });

  criterion("client mission presentation deduplicates deterministic RewardId", () => {
    assert.match(missionUi, /RewardId/);
    assert.match(missionUi, /presented|seen|dedup/i);
    assert.match(missionUi, /SortedNewRewards|sort/i);
    assert.match(missionUi, /function StarterMissionUIController\.PathProgress/);
  });

  criterion("Phase 06 UI controllers expose no reward authority", () => {
    const clientUi = `${onboardingUi}\n${missionUi}`;
    assert.doesNotMatch(clientUi, /profile\.(?:Tape|PackingXP|Rewarded)\s*[+\-*/]?=/);
    assert.doesNotMatch(clientUi, /DataStoreService|UpdateAsync|SetAsync/);
  });

  criterion("all Phase 06 production sources begin strict", () => {
    for (const relativePath of phase06Sources) {
      assert.ok(fs.existsSync(path.join(repositoryRoot, relativePath)), `Missing Phase 06 source ${relativePath}`);
      assert.match(readText(relativePath), /^--!strict(?:\r?\n)/, `${relativePath} must begin with --!strict`);
    }
  });

  criterion("all Phase 06 tests begin strict", () => {
    for (const relativePath of phase06Tests) {
      assert.ok(fs.existsSync(path.join(repositoryRoot, relativePath)), `Missing Phase 06 test ${relativePath}`);
      assert.match(readText(relativePath), /^--!strict(?:\r?\n)/, `${relativePath} must begin with --!strict`);
    }
  });

  criterion("all Phase 06 canonical sources are mapped into Studio", () => {
    for (const relativePath of [...phase06Sources, ...phase06Tests]) {
      const mapping = manifest.scripts.find((entry) => entry.sourceFile.replaceAll("\\", "/") === relativePath);
      assert.ok(mapping, `Missing manifest mapping for ${relativePath}`);
      assert.ok(scriptsByPath.has(mapping.path), `Missing generated source ${mapping.path}`);
    }
  });

  criterion("existing eight stations and shelves remain authored", () => {
    for (let index = 1; index <= 8; index += 1) {
      const station = `Workspace.ONE_MORE_ITEM_WORLD.PlaytestArena.Stations.Station_${String(index).padStart(2, "0")}`;
      for (const relative of ["StationRoot", "Crate.GridOrigin", "PlacedItems", "RuntimePresentation", "CollectionShelf", "CollectionShelf.Runtime"]) {
        assert.ok(instancesByPath.has(`${station}.${relative}`), `Missing inherited ${station}.${relative}`);
      }
    }
  });

  criterion("generated authoring is byte deterministic", () => {
    assert.deepEqual(secondBlueprintBytes, firstBlueprintBytes);
    assert.deepEqual(secondCommandBytes, firstCommandBytes);
  });

  criterion("repeated authoring contains no duplicate managed paths", () => {
    const firstPaths = blueprint.steps.map((step) => step.path);
    const secondPaths = JSON.parse(secondBlueprintBytes.toString("utf8")).steps.map((step) => step.path);
    assert.equal(new Set(firstPaths).size, firstPaths.length);
    assert.deepEqual(secondPaths, firstPaths);
  });

  criterion("wrong-class conflicts remain non-destructive", () => {
    for (const operation of commandBar.operations) {
      assert.match(operation.command, /sync conflict/);
      const beforeSourceMutation = operation.type === "writeScript" ? operation.command.split("local sourceOk")[0] : operation.command;
      assert.doesNotMatch(beforeSourceMutation, /:Destroy\s*\(/);
    }
  });

  const gitFiles = trackedFiles();
  criterion("tracked text contains no absolute local path", () => {
    for (const relativePath of gitFiles) {
      if (!/\.(?:md|json|mjs|ya?ml|luau|txt)$/i.test(relativePath)) continue;
      assert.doesNotMatch(readText(relativePath), /C:[\\/]Users[\\/]|\/Users\/|file:\/\//i, `Absolute path in ${relativePath}`);
    }
  });

  criterion("no analytics payload DataStore payload or recovery artifact is tracked", () => {
    assert.ok(gitFiles.every((file) => !/(^|\/)(?:\.codex-cache|\.codex-studio|recovery|autosave|profile-dumps?|analytics-dumps?)(\/|$)/i.test(file)));
    assert.ok(gitFiles.every((file) => !/\.(?:rbxl|rbxlx|tmp|bak)$/i.test(file)));
  });

  criterion("phase02 manifest remains the sole Phase 02 through 06 owner", () => {
    const manifests = gitFiles.filter((file) => /^studio\/.*\.manifest\.json$/i.test(file)).sort();
    assert.deepEqual(manifests, ["studio/phase01.manifest.json", "studio/phase02.manifest.json"]);
    assert.equal(manifest.mode, "edit");
    assert.equal(manifest.stationPlacements.length, 8);
  });

  criterion("workflow uses the exact dependency-free Node 24 contract", () => {
    const workflow = fs.readFileSync(workflowPath, "utf8");
    assert.match(workflow, /^name:\s*Phase 01(?:\u2013|-)06 Node Validation/m);
    assert.match(workflow, /actions\/checkout@v7/);
    assert.match(workflow, /actions\/setup-node@v6/);
    assert.match(workflow, /node-version:\s*24/);
    assert.match(workflow, /package-manager-cache:\s*false/);
    assert.match(workflow, /permissions:\s*[\s\S]*contents:\s*read/);
    assert.doesNotMatch(workflow, /^\s*run:\s*(?:npm|npx|pnpm|yarn|bun)\b/m);
    assert.ok(!fs.existsSync(path.join(repositoryRoot, "package.json")));
  });

  criterion("workflow runs all six Node gates in order", () => {
    const workflow = fs.readFileSync(workflowPath, "utf8");
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
    const workflow = fs.readFileSync(workflowPath, "utf8");
    assert.match(workflow, /pull_request:[\s\S]*branches:[\s\S]*- main/);
    assert.match(workflow, /push:[\s\S]*branches:[\s\S]*- main[\s\S]*- ['"]codex\/\*\*['"]/);
  });

  criterion("Phase 05 merge and Phase 06 active status are documented", () => {
    const docs = `${readText("README.md")}\n${readText("docs/DEVELOPMENT_STATUS.md")}`;
    assert.match(docs, /d644411b48e20cd9bb256d3d2c55a647efc2adfd/);
    assert.match(docs, /PR #6[^\n]*merged|merged[^\n]*PR #6/i);
    assert.match(docs, /codex\/phase-06-onboarding-starter-missions/);
    assert.match(docs, /pull\/7|PR #7/);
    assert.match(docs, /draft[^\n]*(?:unmerged|not merged)|(?:unmerged|not merged)[^\n]*draft/i);
  });

  criterion("Issue #4 remains referenced and open", () => {
    const docs = `${readText("README.md")}\n${readText("docs/DEVELOPMENT_STATUS.md")}`;
    assert.match(docs, /issues\/4/);
    assert.match(docs, /Issue #4[^\n]*(?:open|remains open)|open[^\n]*Issue #4/i);
    assert.doesNotMatch(docs, /Issue #4[^\n]*(?:closed|resolved)/i);
  });

  criterion("Phase 06 Studio suite contains every required focused suite", () => {
    for (const name of [
      "Schema Version 2",
      "Onboarding definitions",
      "Onboarding service",
      "Guided timing",
      "Mission definitions",
      "Mission progress",
      "Mission rewards",
      "Profile snapshot",
      "Client mission presentation",
      "Analytics adapter",
      "Onboarding analytics",
      "Mission analytics",
      "Core loop analytics",
      "Onboarding request security",
      "Multiplayer isolation",
      "Persistence",
    ]) assert.match(phase06TestSource, new RegExp(`addSuite\\("${escaped(name)}"`));
  });

  criterion("Phase 06 test uses fixed clocks adapters and analytics sinks", () => {
    assert.match(phase06TestSource, /PHASE06_TEST_SEED/);
    assert.match(phase06TestSource, /MemoryProfileAdapter/);
    assert.match(phase06TestSource, /MemoryAnalyticsAdapter/);
    assert.match(phase06TestSource, /Clock/);
    assert.doesNotMatch(phase06TestSource, /DataStoreService|LogOnboardingFunnelStepEvent|LogCustomEvent/);
  });

  assert.ok(criterionCount >= 60, `Phase 06 validator must retain at least 60 criteria; found ${criterionCount}`);
  console.log(
    `[Phase06OnboardingMissionsAnalytics] PASS criteria=${criterionCount} instances=${instanceSteps.length} scripts=${scriptSteps.length} gameplayRemotes=6 profileRemotes=1 onboardingRemotes=1 onboardingSteps=5 starterMissions=5 missionTape=295 missionXP=210 deterministic=true prior=true`,
  );
} catch (error) {
  console.error(`[Phase06OnboardingMissionsAnalytics] FAIL criterion=${criterionCount + 1} ${error instanceof Error ? error.message : String(error)}`);
  process.exitCode = 1;
} finally {
  if (temporaryRoot) fs.rmSync(temporaryRoot, { recursive: true, force: true });
}
