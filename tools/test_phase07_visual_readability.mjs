import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const toolsDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(toolsDirectory, "..");
const manifestPath = path.join(repositoryRoot, "studio", "phase02.manifest.json");
const generatorPath = path.join(toolsDirectory, "build_phase02_blueprint.mjs");
const workflowRelativePath = ".github/workflows/phase01-node-validation.yml";
const phase06MergeSha = "4c606ae4f5e7a5e3d5fa431775c94469ecea1b67";
const worldRoot = "Workspace.ONE_MORE_ITEM_WORLD.PlaytestArena";
const stationsRoot = `${worldRoot}.Stations`;
const uiScreen = "StarterGui.ONE_MORE_ITEM_Gameplay";
const uiRoot = `${uiScreen}.Root`;
const phase07Sources = [
  "src/ReplicatedStorage/ONE_MORE_ITEM/Shared/Presentation/VisualThemeDefinitions.luau",
  "src/ReplicatedStorage/ONE_MORE_ITEM/Shared/Presentation/VisualFraming.luau",
  "src/StarterPlayer/StarterPlayerScripts/ONE_MORE_ITEM_Client/Controllers/ArrivalCurtainController.luau",
  "src/StarterPlayer/StarterPlayerScripts/ONE_MORE_ITEM_Client/Controllers/WorldLabelController.luau",
  "src/ReplicatedFirst/ONE_MORE_ITEM_FirstFrame/FirstFrameBootstrap.client.luau",
  "src/ReplicatedStorage/ONE_MORE_ITEM/Shared/Presentation/FirstFrameHandoffPolicy.luau",
];
const phase07Tests = [
  "src/ServerScriptService/ONE_MORE_ITEM_Server/Dev/Phase07TestSuite.luau",
  "src/ServerScriptService/ONE_MORE_ITEM_Server/Dev/RunPhase07Tests.server.luau",
];
const protectedContentHashes = new Map([
  ["src/ReplicatedStorage/ONE_MORE_ITEM/Shared/Content/DevelopmentItemDefinitions.luau", "2dad20fe48cbfaab7af8d1d23e400f769acfc5d42128a8c6870746c5817098a4"],
  ["src/ReplicatedStorage/ONE_MORE_ITEM/Shared/Content/ShapeDefinitions.luau", "88b327b15ec2b09cfde73e41b1bbf848b5d133d677ddceaf2624ab335cc39874"],
  ["src/ReplicatedStorage/ONE_MORE_ITEM/Shared/Profile/CollectionDefinitions.luau", "aab60d2848f50b3991c95783f1570a5feddc00e3bd0b4c327bd4ba6d5d5cb414"],
  ["src/ReplicatedStorage/ONE_MORE_ITEM/Shared/Profile/MasteryDefinitions.luau", "9e452adb305634fc35f502e1680a47a82f76cb5809bbc9c24e4b0d4c5465a32a"],
  ["src/ReplicatedStorage/ONE_MORE_ITEM/Shared/Profile/PackingRankDefinitions.luau", "5eb5e2ad5e86c0a84ca22e5833bd17eaef55a6496742c673f6e9c26b365fc3a7"],
  ["src/ReplicatedStorage/ONE_MORE_ITEM/Shared/Profile/StarterMissionDefinitions.luau", "6f0dc84ad6361ef9ab66c0c6c1ecdc69dc8b7d1a52693acb2c3e4b713d6ce4bb"],
  ["src/ReplicatedStorage/ONE_MORE_ITEM/Shared/Profile/OnboardingDefinitions.luau", "6a141561cef44b61c256c543781cc675bc787879ee09edf553919a815e228374"],
]);
const gameplayRemoteNames = [
  "ClientReadyRequest",
  "DecisionRequest",
  "PlaceItemRequest",
  "PlacementResponse",
  "RestartRequest",
  "RoundSnapshot",
];
const priorGates = [
  ["test_studio_blueprint.mjs", /\[StudioSyncSmoke\] PASS checks=16 folders=7 scripts=10 deterministic=true/],
  ["test_phase02_blueprint.mjs", /\[Phase02StudioSyncSmoke\] PASS criteria=\d+ instances=\d+ scripts=\d+ remotes=6 deterministic=true phase01=true/],
  ["test_phase03_cross_platform.mjs", /\[Phase03CrossPlatformSmoke\] PASS criteria=\d+ viewports=13 insetProfiles=5 layoutCases=65 remotes=6 deterministic=true phase01=true phase02=true/],
  ["test_phase04_multiplayer_arena.mjs", /\[Phase04MultiplayerArena\] PASS criteria=\d+ instances=\d+ scripts=\d+ stations=8 pathNodes=16 remotes=6 deterministic=true prior=true/],
  ["test_phase05_persistent_progression.mjs", /\[Phase05PersistentProgression\] PASS criteria=\d+ instances=\d+ scripts=\d+ gameplayRemotes=6 profileRemotes=1 shelves=8 collectionSlots=8 deterministic=true prior=true/],
  ["test_phase06_onboarding_missions_analytics.mjs", /\[Phase06OnboardingMissionsAnalytics\] PASS criteria=\d+ instances=\d+ scripts=\d+ gameplayRemotes=6 profileRemotes=1 onboardingRemotes=1 onboardingSteps=5 starterMissions=5 missionTape=295 missionXP=210 deterministic=true prior=true/],
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
    maxBuffer: 32 * 1024 * 1024,
  });
}

function requirePriorGate([name, passPattern]) {
  const result = runNode(path.join(toolsDirectory, name));
  assert.equal(result.status, 0, `${name} failed:\n${result.stderr || result.stdout}`);
  assert.match(result.stdout, passPattern, `${name} did not emit its required PASS summary`);
}

function readText(relativePath) {
  return fs.readFileSync(path.join(repositoryRoot, relativePath), "utf8");
}

function digest(relativePath) {
  const normalizedSource = fs.readFileSync(path.join(repositoryRoot, relativePath), "utf8").replaceAll("\r\n", "\n");
  return createHash("sha256").update(normalizedSource).digest("hex");
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

function stationRoot(index) {
  return `${stationsRoot}.Station_${String(index).padStart(2, "0")}`;
}

function assertPath(map, managedPath, className) {
  const entry = map.get(managedPath);
  assert.ok(entry, `Missing authored path ${managedPath}`);
  if (className !== undefined) assert.equal(entry.className, className, `${managedPath} must be ${className}`);
  return entry;
}

function enumName(value) {
  return value?.name;
}

function colorTuple(value) {
  assert.equal(value?.mode, "rgb", "Expected RGB Color3 encoding");
  return [value.r, value.g, value.b];
}

function cframe(entry) {
  const components = entry?.properties?.CFrame?.components;
  assert.ok(Array.isArray(components) && components.length === 12, `${entry?.path} requires a 12-component CFrame`);
  return components;
}

function vector(value) {
  return [value.x, value.y, value.z];
}

function add(first, second) {
  return [first[0] + second[0], first[1] + second[1], first[2] + second[2]];
}

function subtract(first, second) {
  return [first[0] - second[0], first[1] - second[1], first[2] - second[2]];
}

function scale(value, amount) {
  return [value[0] * amount, value[1] * amount, value[2] * amount];
}

function dot(first, second) {
  return first[0] * second[0] + first[1] * second[1] + first[2] * second[2];
}

function cross(first, second) {
  return [
    first[1] * second[2] - first[2] * second[1],
    first[2] * second[0] - first[0] * second[2],
    first[0] * second[1] - first[1] * second[0],
  ];
}

function magnitude(value) {
  return Math.sqrt(dot(value, value));
}

function normalize(value) {
  const length = magnitude(value);
  assert.ok(length > 1e-9, "Cannot normalize a zero vector");
  return scale(value, 1 / length);
}

function cframeTransform(entry) {
  const value = cframe(entry);
  return {
    position: value.slice(0, 3),
    right: [value[3], value[6], value[9]],
    up: [value[4], value[7], value[10]],
    back: [value[5], value[8], value[11]],
  };
}

function transformPoint(transform, localPoint) {
  return add(
    transform.position,
    add(scale(transform.right, localPoint[0]), add(scale(transform.up, localPoint[1]), scale(transform.back, localPoint[2]))),
  );
}

function lookAtCamera(anchorEntry, focusEntry) {
  const anchor = cframeTransform(anchorEntry);
  const target = cframeTransform(focusEntry).position;
  const forward = normalize(subtract(target, anchor.position));
  let upHint = normalize(anchor.up);
  if (Math.abs(dot(forward, upHint)) >= 0.999) upHint = [0, 1, 0];
  const right = normalize(cross(forward, upHint));
  const up = normalize(cross(right, forward));
  return { position: anchor.position, target, forward, right, up };
}

function downwardPitchDegrees(camera) {
  return Math.atan2(-camera.forward[1], Math.hypot(camera.forward[0], camera.forward[2])) * 180 / Math.PI;
}

function obbCorners(transform, size) {
  const half = scale(size, 0.5);
  const result = [];
  for (const signY of [-1, 1]) {
    for (const signZ of [-1, 1]) {
      for (const signX of [-1, 1]) {
        result.push(transformPoint(transform, [signX * half[0], signY * half[1], signZ * half[2]]));
      }
    }
  }
  return result;
}

function projectPoints(camera, worldPoints, viewport, fieldOfView) {
  const focalLength = viewport.height * 0.5 / Math.tan(fieldOfView * Math.PI / 360);
  const projected = worldPoints.map((point) => {
    const relative = subtract(point, camera.position);
    const depth = dot(relative, camera.forward);
    assert.ok(depth > 0.01, "Projected point must remain in front of the camera");
    return {
      x: viewport.width * 0.5 + dot(relative, camera.right) * focalLength / depth,
      y: viewport.height * 0.5 - dot(relative, camera.up) * focalLength / depth,
    };
  });
  const left = Math.min(...projected.map((point) => point.x));
  const right = Math.max(...projected.map((point) => point.x));
  const top = Math.min(...projected.map((point) => point.y));
  const bottom = Math.max(...projected.map((point) => point.y));
  return {
    left,
    right,
    top,
    bottom,
    width: right - left,
    height: bottom - top,
    centerX: (left + right) * 0.5,
    centerY: (top + bottom) * 0.5,
  };
}

function occupancy(bounds, viewport) {
  return {
    width: bounds.width / viewport.width,
    height: bounds.height / viewport.height,
    centerX: bounds.centerX / viewport.width,
    centerY: bounds.centerY / viewport.height,
    contained: bounds.left >= 0 && bounds.right <= viewport.width && bounds.top >= 0 && bounds.bottom <= viewport.height,
  };
}

function overlap(first, second) {
  const width = Math.max(0, Math.min(first.right, second.right) - Math.max(first.left, second.left));
  const height = Math.max(0, Math.min(first.bottom, second.bottom) - Math.max(first.top, second.top));
  return { width, height, area: width * height };
}

function logicalInterior(instancesByPath, stationPath) {
  const grid = cframeTransform(assertPath(instancesByPath, `${stationPath}.Crate.GridOrigin`, "Part"));
  return {
    transform: {
      position: transformPoint(grid, [4, 0, 4]),
      right: grid.right,
      up: grid.up,
      back: grid.back,
    },
    // The projection rectangle is the readable 5x5 layer-zero interior. Four-cell
    // vertical capacity is validated separately by the required upper-corner rays.
    size: [10, 0.1, 10],
  };
}

function partCorners(entry) {
  return obbCorners(cframeTransform(entry), vector(entry.properties.Size));
}

function pointInsidePart(point, entry, padding = 0.03) {
  const transform = cframeTransform(entry);
  const relative = subtract(point, transform.position);
  const local = [dot(relative, transform.right), dot(relative, transform.up), dot(relative, transform.back)];
  const half = vector(entry.properties.Size).map((component) => component * 0.5 + padding);
  return local.every((component, index) => Math.abs(component) <= half[index]);
}

function segmentIntersectsPart(origin, target, entry) {
  const transform = cframeTransform(entry);
  const toLocal = (point) => {
    const relative = subtract(point, transform.position);
    return [dot(relative, transform.right), dot(relative, transform.up), dot(relative, transform.back)];
  };
  const localOrigin = toLocal(origin);
  const localTarget = toLocal(target);
  const direction = subtract(localTarget, localOrigin);
  const half = vector(entry.properties.Size).map((component) => component * 0.5);
  let minimumT = 0;
  let maximumT = 0.995;
  for (let axis = 0; axis < 3; axis += 1) {
    if (Math.abs(direction[axis]) < 1e-8) {
      if (Math.abs(localOrigin[axis]) > half[axis]) return false;
      continue;
    }
    let first = (-half[axis] - localOrigin[axis]) / direction[axis];
    let second = (half[axis] - localOrigin[axis]) / direction[axis];
    if (first > second) [first, second] = [second, first];
    minimumT = Math.max(minimumT, first);
    maximumT = Math.min(maximumT, second);
    if (minimumT > maximumT) return false;
  }
  return maximumT >= 0 && minimumT <= 0.995;
}

function lineOfSightSamples(instancesByPath, stationPath) {
  const grid = cframeTransform(assertPath(instancesByPath, `${stationPath}.Crate.GridOrigin`, "Part"));
  const focus = cframeTransform(assertPath(instancesByPath, `${stationPath}.CameraFocus`, "Part")).position;
  const samples = [];
  for (let z = 0; z < 5; z += 1) {
    for (let x = 0; x < 5; x += 1) samples.push({ name: `LayerZero_${x}_${z}`, point: transformPoint(grid, [x * 2, 0, z * 2]) });
  }
  for (const [x, z] of [[0, 0], [4, 0], [0, 4], [4, 4]]) {
    samples.push({ name: `UpperCorner_${x}_${z}`, point: transformPoint(grid, [x * 2, 6, z * 2]) });
  }
  samples.push({ name: "CrateFocus", point: focus });
  samples.push({ name: "GridOrigin", point: grid.position });
  samples.push({ name: "GhostFixture", point: transformPoint(grid, [4, 2, 4]) });
  assert.equal(samples.length, 32);
  return samples;
}

function isApprovedPane(entry, stationPath) {
  return ["WallBack", "WallLeft", "WallRight"].some((name) => entry.path === `${stationPath}.Crate.${name}`);
}

function assertFraming(occ, profile, label) {
  assert.ok(occ.contained, `${label} must remain inside the safe viewport`);
  if (profile === "Desktop") {
    assert.ok(occ.width >= 0.42 && occ.width <= 0.58, `${label} width ratio ${occ.width}`);
    assert.ok(occ.height >= 0.36 && occ.height <= 0.56, `${label} height ratio ${occ.height}`);
    assert.ok(occ.centerX >= 0.46 && occ.centerX <= 0.54, `${label} centerX ${occ.centerX}`);
    assert.ok(occ.centerY >= 0.43 && occ.centerY <= 0.61, `${label} centerY ${occ.centerY}`);
  } else if (profile === "TouchPortrait") {
    assert.ok(occ.width >= 0.72 && occ.width <= 0.88, `${label} portrait width ratio ${occ.width}`);
  } else if (profile === "TouchLandscape") {
    assert.ok(occ.width >= 0.44 && occ.width <= 0.62, `${label} landscape width ratio ${occ.width}`);
    assert.ok(occ.height >= 0.50 && occ.height <= 0.72, `${label} landscape height ratio ${occ.height}`);
  }
}

try {
  for (const gate of priorGates) requirePriorGate(gate);

  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "one-more-item-phase07-"));
  const firstOutput = path.join(temporaryRoot, "first");
  const secondOutput = path.join(temporaryRoot, "second");
  const firstGeneration = runNode(generatorPath, [manifestPath, firstOutput]);
  const secondGeneration = runNode(generatorPath, [manifestPath, secondOutput]);
  assert.equal(firstGeneration.status, 0, `Phase 07 generation failed:\n${firstGeneration.stderr || firstGeneration.stdout}`);
  assert.equal(secondGeneration.status, 0, `Repeated Phase 07 generation failed:\n${secondGeneration.stderr || secondGeneration.stdout}`);

  const firstBlueprintBytes = fs.readFileSync(path.join(firstOutput, "phase02-blueprint.json"));
  const secondBlueprintBytes = fs.readFileSync(path.join(secondOutput, "phase02-blueprint.json"));
  const firstCommandBytes = fs.readFileSync(path.join(firstOutput, "phase02-command-bar.json"));
  const secondCommandBytes = fs.readFileSync(path.join(secondOutput, "phase02-command-bar.json"));
  const blueprint = JSON.parse(firstBlueprintBytes.toString("utf8"));
  const commandBar = JSON.parse(firstCommandBytes.toString("utf8"));
  const instanceSteps = blueprint.steps.filter((step) => step.type === "ensureInstance");
  const scriptSteps = blueprint.steps.filter((step) => step.type === "writeScript");
  const lightingSteps = blueprint.steps.filter((step) => step.type === "setLighting");
  const instancesByPath = new Map(instanceSteps.map((step) => [step.path, step]));
  const scriptsByPath = new Map(scriptSteps.map((step) => [step.path, step]));
  const fieldOfView = Number(readText("src/StarterPlayer/StarterPlayerScripts/ONE_MORE_ITEM_Client/Controllers/PresentationTokens.luau")
    .match(/FieldOfView\s*=\s*(\d+(?:\.\d+)?)/)?.[1]);

  criterion("manifest owns one explicit Lighting service descriptor", () => {
    assert.equal(manifest.managedServices.length, 1);
    assert.equal(manifest.managedServices[0].path, "Lighting");
    assert.equal(manifest.managedServices[0].className, "Lighting");
    assert.ok(manifest.managedServices[0].properties, "Lighting service descriptor must own its authored properties");
    assert.equal(lightingSteps.length, 1);
  });

  criterion("Phase 07 generation is byte deterministic", () => {
    assert.deepEqual(secondBlueprintBytes, firstBlueprintBytes);
    assert.deepEqual(secondCommandBytes, firstCommandBytes);
  });

  criterion("all generated managed paths remain unique", () => {
    const paths = [...instanceSteps, ...scriptSteps].map((step) => step.path);
    assert.equal(new Set(paths).size, paths.length);
  });

  criterion("wrong-class and duplicate conflicts remain non-destructive", () => {
    const operations = commandBar.operations.filter((operation) => operation.type === "ensureInstance");
    assert.ok(operations.length > 0);
    for (const operation of operations) {
      assert.match(operation.command, /duplicate managed child|same-name managed children|FindFirstChild/);
      assert.doesNotMatch(operation.command, /Destroy\s*\(/);
    }
  });

  criterion("VisualThemeDefinitions is source-controlled and mapped", () => {
    assertPath(scriptsByPath, "ReplicatedStorage.ONE_MORE_ITEM.Shared.Presentation.VisualThemeDefinitions", "ModuleScript");
  });

  criterion("VisualFraming is source-controlled and mapped", () => {
    assertPath(scriptsByPath, "ReplicatedStorage.ONE_MORE_ITEM.Shared.Presentation.VisualFraming", "ModuleScript");
  });

  criterion("ArrivalCurtainController is source-controlled and mapped", () => {
    assertPath(scriptsByPath, "StarterPlayer.StarterPlayerScripts.ONE_MORE_ITEM_Client.Controllers.ArrivalCurtainController", "ModuleScript");
  });

  criterion("WorldLabelController is source-controlled and mapped", () => {
    assertPath(scriptsByPath, "StarterPlayer.StarterPlayerScripts.ONE_MORE_ITEM_Client.Controllers.WorldLabelController", "ModuleScript");
  });

  criterion("first-frame bootstrap is source-controlled and mapped under ReplicatedFirst", () => {
    assertPath(scriptsByPath, "ReplicatedFirst.ONE_MORE_ITEM_FirstFrame.FirstFrameBootstrap", "LocalScript");
    assertPath(scriptsByPath, "ReplicatedStorage.ONE_MORE_ITEM.Shared.Presentation.FirstFrameHandoffPolicy", "ModuleScript");
  });

  criterion("Phase 07 Studio suite and runner are source-controlled and mapped", () => {
    assertPath(scriptsByPath, "ServerScriptService.ONE_MORE_ITEM_Server.Dev.Phase07TestSuite", "ModuleScript");
    assertPath(scriptsByPath, "ServerScriptService.ONE_MORE_ITEM_Server.Dev.RunPhase07Tests", "Script");
  });

  const themeSource = readText(phase07Sources[0]);
  const framingSource = readText(phase07Sources[1]);
  const arrivalSource = readText(phase07Sources[2]);
  const worldLabelSource = readText(phase07Sources[3]);
  const firstFrameSource = readText(phase07Sources[4]);
  const firstFramePolicySource = readText(phase07Sources[5]);
  const cameraSource = readText("src/StarterPlayer/StarterPlayerScripts/ONE_MORE_ITEM_Client/Controllers/CameraController.luau");
  const clientBootstrap = readText("src/StarterPlayer/StarterPlayerScripts/ONE_MORE_ITEM_Client/ClientBootstrap.luau");
  const roundConfig = readText("src/ReplicatedStorage/ONE_MORE_ITEM/Shared/Config/RoundConfig.luau");

  criterion("semantic visual colors are exact", () => {
    const colors = [...themeSource.matchAll(/(\w+)\s*=\s*Color3\.fromRGB\((\d+),\s*(\d+),\s*(\d+)\)/g)]
      .map((match) => [match[1], Number(match[2]), Number(match[3]), Number(match[4])]);
    assert.deepEqual(colors.slice(0, 14), [
      ["Background", 10, 15, 22], ["StructuralGraphite", 21, 30, 40], ["SecondarySteel", 34, 48, 61],
      ["Concrete", 42, 48, 56], ["RubberDark", 16, 22, 29], ["CrateWarm", 139, 106, 66],
      ["CrateFloor", 110, 92, 70], ["TextPrimary", 245, 247, 250], ["TextSecondary", 167, 181, 196],
      ["Cyan", 34, 211, 230], ["Amber", 255, 178, 26], ["Green", 99, 232, 92],
      ["Red", 255, 75, 62], ["Purple", 155, 108, 255],
    ]);
  });

  criterion("visual theme definitions are recursively frozen", () => {
    assert.match(themeSource, /local color[^\n]*= table\.freeze\s*\(/);
    assert.match(themeSource, /local material[^\n]*= table\.freeze\s*\(/);
    assert.match(themeSource, /local timing[^\n]*= table\.freeze\s*\(/);
    assert.match(themeSource, /return table\.freeze\(VisualThemeDefinitions\)/);
  });

  criterion("semantic environment materials reject Glass and ordinary green or red", () => {
    assert.match(themeSource, /Pane\s*=\s*Enum\.Material\.SmoothPlastic/);
    const materialBlock = themeSource.match(/local material[\s\S]*?\n\}\)/)?.[0] ?? "";
    assert.doesNotMatch(materialBlock, /Glass|Green|Red/);
  });

  criterion("ArrivalCurtain fade stays inside 0.22 through 0.28 seconds", () => {
    const fade = Number(themeSource.match(/ArrivalCurtainFade\s*=\s*(\d+(?:\.\d+)?)/)?.[1]);
    assert.ok(fade >= 0.22 && fade <= 0.28);
  });

  criterion("VisualFraming owns deterministic projection and 32 LOS samples", () => {
    for (const api of ["GetSafeRect", "ProjectPoint", "ProjectWorldBounds", "ProjectObb", "GetOccupancy", "GetOverlap", "EvaluateCamera", "EvaluateFraming", "GenerateLineOfSightSamples"]) {
      assert.match(framingSource, new RegExp(`function\\s+VisualFraming\\.${api}\\s*\\(`));
    }
    assert.match(framingSource, /LineOfSightSampleCount\s*=\s*32\b/);
    assert.match(framingSource, /for gridZ = 0, 4 do[\s\S]*for gridX = 0, 4 do/);
  });

  criterion("camera constants and responsive thresholds retain the accepted visual ranges", () => {
    assert.match(framingSource, /MinimumFieldOfView\s*=\s*48\b/);
    assert.match(framingSource, /MaximumFieldOfView\s*=\s*52\b/);
    assert.match(framingSource, /MinimumDownwardPitchDegrees\s*=\s*50\b/);
    assert.match(framingSource, /MaximumDownwardPitchDegrees\s*=\s*58\b/);
    assert.match(framingSource, /MaximumFrontRimOverlapRatio\s*=\s*0\.08\b/);
  });

  const curtainPath = `${uiScreen}.ArrivalCurtain`;
  criterion("ArrivalCurtain is permanently authored and visible before Play", () => {
    const curtain = assertPath(instancesByPath, curtainPath, "Frame");
    assert.equal(curtain.properties.Visible, true);
    assert.equal(curtain.properties.BackgroundTransparency, 1);
    const background = assertPath(instancesByPath, `${curtainPath}.Background`, "Frame");
    assert.equal(background.properties.BackgroundTransparency, 0);
    assert.deepEqual(colorTuple(background.properties.BackgroundColor3), [10, 15, 22]);
    assert.equal(background.properties.Size.xScale, 1);
    assert.equal(background.properties.Size.yScale, 1);
    assert.ok(curtain.properties.Size.xScale >= 1 && curtain.properties.Size.yScale >= 1);
    assert.ok(curtain.properties.ZIndex >= 100);
  });

  const firstFrameRoot = "ReplicatedFirst.ONE_MORE_ITEM_FirstFrame";
  const firstFrameCurtain = `${firstFrameRoot}.FirstFrameCurtain`;
  criterion("ReplicatedFirst owns the authored opaque first-frame curtain", () => {
    const packageRoot = assertPath(instancesByPath, firstFrameRoot, "Folder");
    assert.equal(packageRoot.attributes.OverlayMounted, false);
    assert.equal(packageRoot.attributes.HandoffComplete, false);
    const screen = assertPath(instancesByPath, firstFrameCurtain, "ScreenGui");
    assert.equal(screen.properties.DisplayOrder, 10000);
    assert.equal(screen.properties.Enabled, true);
    assert.equal(screen.properties.IgnoreGuiInset, true);
    assert.equal(screen.properties.ResetOnSpawn, false);
    assert.equal(enumName(screen.properties.ZIndexBehavior), "Global");
    const background = assertPath(instancesByPath, `${firstFrameCurtain}.Background`, "Frame");
    assert.equal(background.properties.BackgroundTransparency, 0);
    assert.deepEqual(colorTuple(background.properties.BackgroundColor3), [10, 15, 22]);
  });

  criterion("first-frame curtain carries the exact authored presentation copy without images", () => {
    assert.equal(assertPath(instancesByPath, `${firstFrameCurtain}.GameTitle`, "TextLabel").properties.Text, "ONE MORE ITEM!");
    assert.equal(assertPath(instancesByPath, `${firstFrameCurtain}.Subtitle`, "TextLabel").properties.Text, "PACK THE BOX");
    assert.equal(assertPath(instancesByPath, `${firstFrameCurtain}.LoadingStatus`, "TextLabel").properties.Text, "PREPARING STATION");
    assertPath(instancesByPath, `${firstFrameCurtain}.AccentLine`, "Frame");
    for (const entry of instanceSteps.filter((step) => step.path === firstFrameCurtain || step.path.startsWith(`${firstFrameCurtain}.`))) {
      assert.notEqual(entry.className, "ImageLabel");
      assert.notEqual(entry.className, "ImageButton");
    }
  });

  criterion("first-frame bootstrap mounts before loader removal and performs covered handoff", () => {
    const mountIndex = firstFrameSource.indexOf("overlay.Parent = playerGui");
    const removeIndex = firstFrameSource.indexOf("ReplicatedFirst:RemoveDefaultLoadingScreen()")
    const destroyIndex = firstFrameSource.indexOf("overlay:Destroy()")
    const handoffIndex = firstFrameSource.indexOf('packageRoot:SetAttribute("HandoffComplete", true)')
    assert.ok(mountIndex >= 0 && removeIndex > mountIndex);
    assert.ok(destroyIndex >= 0 && handoffIndex > destroyIndex);
    assert.match(firstFrameSource, /FirstFrameHandoffPolicy\.ShouldHandoff\s*\(/);
    assert.match(firstFrameSource, /MINIMUM_FIRST_FRAME_HOLD\s*=\s*0\.65/);
    assert.match(firstFrameSource, /MINIMUM_FIRST_FRAME_HOLD\s*-\s*\(os\.clock\(\)\s*-\s*overlayMountedAt\)/);
    assert.match(firstFrameSource, /task\.delay\(remainingHold/);
    assert.ok(firstFrameSource.indexOf("remainingHold > 0") < destroyIndex, "minimum first-frame hold must gate overlay destruction");
    assert.doesNotMatch(firstFrameSource, /FireServer|InvokeServer|RenderStepped|Heartbeat/);
  });

  criterion("first-frame handoff policy covers visible and already-revealed canonical states", () => {
    assert.match(firstFramePolicySource, /return cameraSafe and \(canonicalVisible or presentationState == "REVEALED"\)/);
    const shouldHandoff = (visible, safe, state) => safe && (visible || state === "REVEALED");
    assert.equal(shouldHandoff(true, true, "WAITING FOR STATION"), true);
    assert.equal(shouldHandoff(false, true, "REVEALED"), true);
    assert.equal(shouldHandoff(false, true, "WAITING FOR STATION"), false);
    assert.equal(shouldHandoff(true, false, "WAITING FOR STATION"), false);
    assert.equal(shouldHandoff(false, false, "REVEALED"), false);
  });

  criterion("ArrivalCurtain required hierarchy and exact text are authored", () => {
    assertPath(instancesByPath, `${curtainPath}.Background`);
    assert.equal(assertPath(instancesByPath, `${curtainPath}.GameTitle`, "TextLabel").properties.Text, "ONE MORE ITEM!");
    assert.equal(assertPath(instancesByPath, `${curtainPath}.Subtitle`, "TextLabel").properties.Text, "PACK THE BOX");
    assert.equal(assertPath(instancesByPath, `${curtainPath}.LoadingStatus`, "TextLabel").properties.Text, "LOADING PROFILE");
    assertPath(instancesByPath, `${curtainPath}.AccentLine`);
  });

  criterion("ArrivalCurtain controller gates reveal on profile and camera readiness without a remote", () => {
    for (const api of ["StatusForProfile", "ShouldReveal", "new", "ApplyProfileSnapshot", "SetAssignment", "IsRevealed", "Destroy"]) {
      assert.match(arrivalSource, new RegExp(`(?:function\\s+ArrivalCurtainController\\.${api}|function\\s+ControllerMethods\\.${api})`));
    }
    assert.match(arrivalSource, /GetReadiness\s*\(/);
    assert.match(arrivalSource, /SubscribeReadiness\s*\(/);
    assert.doesNotMatch(arrivalSource, /FireServer|InvokeServer|RenderStepped/);
    assert.match(arrivalSource, /Cancel\s*\(/);
  });

  criterion("ArrivalCurtain waits for the authored camera pair before validating replication", () => {
    const helperStart = arrivalSource.indexOf("local function optionalPart");
    const helperEnd = arrivalSource.indexOf("\nlocal function fallbackCenter", helperStart);
    assert.ok(helperStart >= 0 && helperEnd > helperStart, "optionalPart helper is missing");
    const helperSource = arrivalSource.slice(helperStart, helperEnd);
    assert.match(helperSource, /WaitForChild\(name,\s*10\)/);
    assert.doesNotMatch(helperSource, /FindFirstChild\(name\)/);
  });

  criterion("camera becomes Scriptable before ArrivalCurtain reveal and exposes readiness", () => {
    assert.match(cameraSource, /CameraType\s*=\s*Enum\.CameraType\.Scriptable/);
    for (const api of ["PrepareWaitingView", "GetReadiness", "SubscribeReadiness"]) {
      assert.match(cameraSource, new RegExp(`function\\s+(?:CameraController|ControllerMethods)\\.${api}`));
    }
    assert.match(clientBootstrap, /ArrivalCurtainController/);
  });

  criterion("WorldLabelController owns local adjacent and distant policy without a frame loop or remote", () => {
    for (const api of ["ClassifyStation", "ShouldShowForView", "IsMeaningfulCameraChange", "new", "SetAssignedStation", "Refresh", "Destroy"]) {
      assert.match(worldLabelSource, new RegExp(`(?:function\\s+WorldLabelController\\.${api}|function\\s+ControllerMethods\\.${api})`));
    }
    assert.doesNotMatch(worldLabelSource, /RenderStepped|Heartbeat|FireServer|InvokeServer/);
    assert.match(worldLabelSource, /Disconnect\s*\(/);
  });

  criterion("safe waiting camera anchors are permanently authored and noninteractive", () => {
    for (const name of ["ArrivalCameraAnchor", "ArrivalCameraFocus"]) {
      const anchor = assertPath(instancesByPath, `${worldRoot}.${name}`, "Part");
      assert.equal(anchor.properties.Transparency, 1);
      assert.equal(anchor.properties.CanCollide, false);
      assert.equal(anchor.properties.CanQuery, false);
      assert.equal(anchor.properties.CanTouch, false);
    }
  });

  criterion("arena shell owns the complete warehouse hierarchy", () => {
    for (const relativePath of [
      "ArenaShell", "ArenaShell.OuterFloor", "ArenaShell.WallSegments", "ArenaShell.SupportPillars",
      "ArenaShell.CeilingRing", "ArenaShell.LightRig", "ArenaShell.Entry", "ArenaShell.Branding",
    ]) assert.ok(instancesByPath.has(`${worldRoot}.${relativePath}`), `Missing ${relativePath}`);
  });

  criterion("arena floor is a 134-stud cylindrical replacement and Baseplate is hidden", () => {
    const arenaFloor = assertPath(instancesByPath, `${worldRoot}.ArenaFloor`, "Part");
    assert.equal(enumName(arenaFloor.properties.Shape), "Cylinder");
    assert.deepEqual(vector(arenaFloor.properties.Size).sort((a, b) => a - b), [0.5, 134, 134]);
    const baseplate = assertPath(instancesByPath, "Workspace.Baseplate", "Part");
    assert.equal(baseplate.properties.Transparency, 1);
    assert.equal(baseplate.properties.CanCollide, false);
  });

  criterion("arena floor markings are radial and no square cyan boundary remains", () => {
    const seams = instanceSteps.filter((step) => /^Workspace\.ONE_MORE_ITEM_WORLD\.PlaytestArena\.ArenaFloorMarkings\.RadialSeams\.Seam_\d\d$/.test(step.path));
    const ring = instanceSteps.filter((step) => /^Workspace\.ONE_MORE_ITEM_WORLD\.PlaytestArena\.ArenaFloorMarkings\.InnerRing\.Segment_\d\d$/.test(step.path));
    assert.equal(seams.length, 8);
    assert.equal(ring.length, 16);
    const rails = instanceSteps.filter((step) => step.className === "Part" && step.path.startsWith(`${worldRoot}.ArenaRails.`));
    assert.equal(rails.length, 16);
    for (const rail of rails) {
      assert.equal(enumName(rail.properties.Material), "Metal");
      assert.notEqual(enumName(rail.properties.Material), "Neon");
    }
  });

  criterion("warehouse shell has bounded segment, pillar, ceiling, rafter, fixture, and entry counts", () => {
    const count = (pattern, className = "Part") => instanceSteps.filter((step) => step.className === className && pattern.test(step.path)).length;
    assert.equal(count(/ArenaShell\.WallSegments\.Wall_\d\d$/), 15);
    assert.equal(count(/ArenaShell\.SupportPillars\.Pillar_\d\d$/), 8);
    assert.equal(count(/ArenaShell\.CeilingRing\.Segment_\d\d$/), 16);
    assert.equal(count(/ArenaShell\.LightRig\.Rafters\.Rafter_\d\d$/), 8);
    assert.equal(count(/ArenaShell\.LightRig\.Fixtures\.Fixture_\d\d$/), 4);
    for (const name of ["LeftJamb", "RightJamb", "Header", "BackWall"]) assertPath(instancesByPath, `${worldRoot}.ArenaShell.Entry.${name}`, "Part");
  });

  criterion("center dispatch retains the landmark and extends it with route structure", () => {
    for (const relativePath of [
      "Base", "Lift", "LiftTop", "ShowcaseEntry", "ArenaAnnouncement", "ServerBest", "DispatchPit", "CentralColumn",
    ]) assertPath(instancesByPath, `${worldRoot}.CenterDispatch.${relativePath}`);
    assert.equal(instanceSteps.filter((step) => /CenterDispatch\.RouteStrips\.Route_\d\d$/.test(step.path)).length, 8);
    assert.equal(instanceSteps.filter((step) => /CenterDispatch\.ShowcaseSupports\.Support_\d\d$/.test(step.path)).length, 8);
  });

  criterion("showcase path remains exactly 16 nodes at radius 28.5 and height 20", () => {
    const positions = [];
    for (let index = 1; index <= 16; index += 1) {
      const node = assertPath(instancesByPath, `${worldRoot}.ShowcaseLoop.PathNodes.Node_${String(index).padStart(2, "0")}`, "Part");
      const [x, y, z] = cframeTransform(node).position;
      assert.ok(Math.abs(Math.hypot(x, z) - 28.5) < 1e-6);
      assert.ok(Math.abs(y - 20) < 1e-6);
      positions.push(`${x},${y},${z}`);
    }
    assert.equal(new Set(positions).size, 16);
  });

  criterion("showcase rail stays 16-segment and clear of every camera anchor", () => {
    assert.equal(instanceSteps.filter((step) => /ShowcaseLoop\.Rail\.Segment_\d\d$/.test(step.path)).length, 16);
    const nodes = instanceSteps.filter((step) => /ShowcaseLoop\.PathNodes\.Node_\d\d$/.test(step.path));
    for (let stationIndex = 1; stationIndex <= 8; stationIndex += 1) {
      for (const anchorName of ["CameraAnchor", "CameraAnchorTouchLandscape", "CameraAnchorTouchPortrait"]) {
        const anchor = cframeTransform(assertPath(instancesByPath, `${stationRoot(stationIndex)}.${anchorName}`, "Part")).position;
        for (const node of nodes) assert.ok(magnitude(subtract(cframeTransform(node).position, anchor)) >= 4);
      }
    }
  });

  criterion("station ring is exactly eight deterministic placements at radius 50", () => {
    assert.equal(manifest.stationPlacements.length, 8);
    for (let index = 0; index < 8; index += 1) {
      const placement = manifest.stationPlacements[index];
      assert.equal(placement.radius, 50);
      assert.equal(placement.stationIndex, index + 1);
      assert.equal(placement.stationId, `station_${String(index + 1).padStart(2, "0")}`);
      assert.equal(placement.angleDegrees, -90 + index * 45 > 180 ? -135 : -90 + index * 45);
    }
  });

  criterion("expanded station bays do not overlap and retain at least four studs of clear separation", () => {
    const roots = Array.from({ length: 8 }, (_, index) => assertPath(instancesByPath, `${stationRoot(index + 1)}.StationRoot`, "Part"));
    for (let index = 0; index < 8; index += 1) {
      const first = roots[index];
      const second = roots[(index + 1) % 8];
      const firstPosition = cframeTransform(first).position;
      const secondPosition = cframeTransform(second).position;
      const firstRadius = Math.hypot(first.properties.Size.x, first.properties.Size.z) * 0.5;
      const secondRadius = Math.hypot(second.properties.Size.x, second.properties.Size.z) * 0.5;
      const clearance = magnitude(subtract(firstPosition, secondPosition)) - firstRadius - secondRadius;
      assert.ok(clearance >= 4, `${first.path}/${second.path} clearance ${clearance}`);
    }
  });

  const frameRelativePaths = [
    "Crate.Frame", "Crate.Frame.FrontLeftPost", "Crate.Frame.FrontRightPost", "Crate.Frame.BackLeftPost",
    "Crate.Frame.BackRightPost", "Crate.Frame.UpperRails", "Crate.Frame.LowerRails",
  ];
  for (let stationIndex = 1; stationIndex <= 8; stationIndex += 1) {
    const root = stationRoot(stationIndex);
    criterion(`Station_${stationIndex} owns the approved crate frame`, () => {
      for (const relativePath of frameRelativePaths) assert.ok(instancesByPath.has(`${root}.${relativePath}`), `Missing ${root}.${relativePath}`);
    });

    criterion(`Station_${stationIndex} owns exactly 25 readable floor tiles`, () => {
      const tiles = instanceSteps.filter((step) => step.path.startsWith(`${root}.Crate.GridTiles.Cell_`) && step.className === "Part");
      assert.equal(tiles.length, 25);
      for (const tile of tiles) {
        assert.ok(tile.properties.Size.x >= 1.82 && tile.properties.Size.x <= 1.86);
        assert.ok(tile.properties.Size.z >= 1.82 && tile.properties.Size.z <= 1.86);
        assert.equal(tile.properties.Transparency, 0);
        assert.notEqual(enumName(tile.properties.Material), "Neon");
      }
    });

    criterion(`Station_${stationIndex} crate descendants contain no Glass`, () => {
      const crateParts = instanceSteps.filter((step) => step.path.startsWith(`${root}.Crate.`) && step.className === "Part");
      assert.ok(crateParts.length > 25);
      for (const part of crateParts) assert.notEqual(enumName(part.properties.Material), "Glass", `Glass rejected at ${part.path}`);
    });

    criterion(`Station_${stationIndex} front rim and panes satisfy the physical visibility contract`, () => {
      const front = assertPath(instancesByPath, `${root}.Crate.WallFront`, "Part");
      assert.ok(front.properties.Size.y <= 0.55);
      assert.ok(Math.min(front.properties.Size.x, front.properties.Size.z) <= 0.24);
      for (const paneName of ["WallBack", "WallLeft", "WallRight"]) {
        const pane = assertPath(instancesByPath, `${root}.Crate.${paneName}`, "Part");
        assert.equal(enumName(pane.properties.Material), "SmoothPlastic");
        assert.ok(pane.properties.Transparency >= 0.55 && pane.properties.Transparency <= 0.72);
        assert.equal(pane.properties.CastShadow, false);
        assert.equal(pane.properties.CanCollide, false);
        assert.equal(pane.properties.CanTouch, false);
        assert.equal(pane.properties.CanQuery, false);
      }
    });

    criterion(`Station_${stationIndex} console remains compact and below the visible crate floor`, () => {
      const consolePaths = ["ConsoleBase", "ConsoleDeck", "ConsoleFace"].map((name) => `${root}.ControlConsole.${name}`);
      const consoleParts = consolePaths.map((managedPath) => assertPath(instancesByPath, managedPath, "Part"));
      for (const part of consoleParts) {
        assert.ok(part.properties.Size.x <= 8.5);
        assert.ok(part.properties.Size.z <= 3.2);
        assert.notEqual(enumName(part.properties.Material), "Neon");
      }
      const floor = assertPath(instancesByPath, `${root}.Crate.InteriorFloor`, "Part");
      const consoleTop = Math.max(...consoleParts.map((part) => cframeTransform(part).position[1] + part.properties.Size.y * 0.5));
      const floorBottom = cframeTransform(floor).position[1] - floor.properties.Size.y * 0.5;
      assert.ok(consoleTop <= floorBottom - 0.35, `${root} console top ${consoleTop} floor bottom ${floorBottom}`);
      for (const controlName of ["RotateButton", "PlaceButton", "ShipButton", "OneMoreButton"]) {
        assertPath(instancesByPath, `${root}.ControlConsole.${controlName}`, "Part");
      }
    });

    criterion(`Station_${stationIndex} owns one restrained task light`, () => {
      const taskLights = instanceSteps.filter((step) => step.className === "PointLight" && step.path.startsWith(`${root}.Crate.`));
      assert.equal(taskLights.length, 1);
      const light = assertPath(instancesByPath, `${root}.Crate.TaskLight.Light`, "PointLight");
      assert.equal(light.properties.Enabled, true);
      assert.deepEqual(colorTuple(light.properties.Color), [255, 231, 194]);
      assert.ok(light.properties.Brightness >= 1.3 && light.properties.Brightness <= 1.7);
      assert.ok(light.properties.Range >= 16 && light.properties.Range <= 20);
      assert.equal(light.properties.Shadows, false);
    });

    criterion(`Station_${stationIndex} risk indicator and collection shelf reject debug geometry`, () => {
      const indicator = assertPath(instancesByPath, `${root}.RiskIndicator.IndicatorPart`, "Part");
      assert.equal(enumName(indicator.properties.Shape), "Block");
      assert.ok(Math.max(...vector(indicator.properties.Size)) <= 2.2);
      const riskLight = assertPath(instancesByPath, `${root}.RiskIndicator.IndicatorPart.Light`, "PointLight");
      assert.equal(riskLight.properties.Enabled, false);
      assert.equal(riskLight.properties.Range, 6);
      for (const name of ["Back", "FrontRail", "LeftSide", "RightSide", "Top"]) {
        assertPath(instancesByPath, `${root}.CollectionShelf.Frame.${name}`, "Part");
      }
    });
  }

  criterion("camera field of view is inside the accepted range", () => {
    assert.ok(Number.isFinite(fieldOfView) && fieldOfView >= 48 && fieldOfView <= 52);
  });

  criterion("Station_01 and Station_05 camera pitches remain between 50 and 58 degrees", () => {
    for (const stationIndex of [1, 5]) {
      for (const anchorName of ["CameraAnchor", "CameraAnchorTouchLandscape", "CameraAnchorTouchPortrait"]) {
        const camera = lookAtCamera(
          assertPath(instancesByPath, `${stationRoot(stationIndex)}.${anchorName}`, "Part"),
          assertPath(instancesByPath, `${stationRoot(stationIndex)}.CameraFocus`, "Part"),
        );
        const pitch = downwardPitchDegrees(camera);
        assert.ok(pitch >= 50 && pitch <= 58, `${stationRoot(stationIndex)}.${anchorName} pitch ${pitch}`);
      }
    }
  });

  const viewportProfiles = [
    { name: "desktop-1920x1080", width: 1920, height: 1080, anchor: "CameraAnchor", profile: "Desktop" },
    { name: "desktop-1366x768", width: 1366, height: 768, anchor: "CameraAnchor", profile: "Desktop" },
    { name: "compact-1100x700", width: 1100, height: 700, anchor: "CameraAnchor", profile: "Compact" },
    { name: "portrait-360x640", width: 360, height: 640, anchor: "CameraAnchorTouchPortrait", profile: "TouchPortrait" },
    { name: "portrait-430x932", width: 430, height: 932, anchor: "CameraAnchorTouchPortrait", profile: "TouchPortrait" },
    { name: "landscape-640x360", width: 640, height: 360, anchor: "CameraAnchorTouchLandscape", profile: "TouchLandscape" },
    { name: "landscape-932x430", width: 932, height: 430, anchor: "CameraAnchorTouchLandscape", profile: "TouchLandscape" },
  ];
  for (const stationIndex of [1, 5]) {
    for (const profile of viewportProfiles) {
      criterion(`Station_${stationIndex} ${profile.name} framing passes`, () => {
        const root = stationRoot(stationIndex);
        const camera = lookAtCamera(
          assertPath(instancesByPath, `${root}.${profile.anchor}`, "Part"),
          assertPath(instancesByPath, `${root}.CameraFocus`, "Part"),
        );
        const interior = logicalInterior(instancesByPath, root);
        const viewport = { width: profile.width, height: profile.height };
        const bounds = projectPoints(camera, obbCorners(interior.transform, interior.size), viewport, fieldOfView);
        assertFraming(occupancy(bounds, viewport), profile.profile, `${root}/${profile.name}`);
      });
    }
  }

  for (const stationIndex of [1, 5]) {
    for (const profile of viewportProfiles) {
      criterion(`Station_${stationIndex} ${profile.name} upper capacity remains onscreen`, () => {
        const root = stationRoot(stationIndex);
        const camera = lookAtCamera(
          assertPath(instancesByPath, `${root}.${profile.anchor}`, "Part"),
          assertPath(instancesByPath, `${root}.CameraFocus`, "Part"),
        );
        const grid = cframeTransform(assertPath(instancesByPath, `${root}.Crate.GridOrigin`, "Part"));
        const viewport = { width: profile.width, height: profile.height };
        const upperBounds = projectPoints(
          camera,
          [[0, 6, 0], [8, 6, 0], [0, 6, 8], [8, 6, 8]].map((point) => transformPoint(grid, point)),
          viewport,
          fieldOfView,
        );
        assert.ok(
          upperBounds.left >= 0
            && upperBounds.right <= viewport.width
            && upperBounds.top >= 0
            && upperBounds.bottom <= viewport.height,
          `${root}/${profile.name} upper bounds escape viewport: ${JSON.stringify(upperBounds)}`,
        );
      });
    }
  }

  criterion("projected consoles do not overlap crate interiors and front-rim overlap stays below eight percent", () => {
    const viewport = { width: 1920, height: 1080 };
    for (let stationIndex = 1; stationIndex <= 8; stationIndex += 1) {
      const root = stationRoot(stationIndex);
      const camera = lookAtCamera(
        assertPath(instancesByPath, `${root}.CameraAnchor`, "Part"),
        assertPath(instancesByPath, `${root}.CameraFocus`, "Part"),
      );
      const interior = logicalInterior(instancesByPath, root);
      const crateBounds = projectPoints(camera, obbCorners(interior.transform, interior.size), viewport, fieldOfView);
      const consoleParts = ["ConsoleBase", "ConsoleDeck", "ConsoleFace"].map((name) => assertPath(instancesByPath, `${root}.ControlConsole.${name}`, "Part"));
      const consoleBounds = projectPoints(camera, consoleParts.flatMap(partCorners), viewport, fieldOfView);
      assert.equal(overlap(crateBounds, consoleBounds).area, 0, `${root} console overlaps crate`);
      const floor = assertPath(instancesByPath, `${root}.Crate.InteriorFloor`, "Part");
      const front = assertPath(instancesByPath, `${root}.Crate.WallFront`, "Part");
      const floorBounds = projectPoints(camera, partCorners(floor), viewport, fieldOfView);
      const frontBounds = projectPoints(camera, partCorners(front), viewport, fieldOfView);
      assert.ok(overlap(floorBounds, frontBounds).height / floorBounds.height < 0.08, `${root} front rim overlaps floor`);
    }
  });

  let lineOfSightRayCount = 0;
  criterion("all 25 floor cells and seven additional samples pass 768 deterministic line-of-sight checks", () => {
    const permanentParts = instanceSteps.filter((step) => step.className === "Part" && step.path.startsWith(`${worldRoot}.`));
    const failures = [];
    for (let stationIndex = 1; stationIndex <= 8; stationIndex += 1) {
      const root = stationRoot(stationIndex);
      const samples = lineOfSightSamples(instancesByPath, root);
      for (const anchorName of ["CameraAnchor", "CameraAnchorTouchLandscape", "CameraAnchorTouchPortrait"]) {
        const origin = cframeTransform(assertPath(instancesByPath, `${root}.${anchorName}`, "Part")).position;
        for (const sample of samples) {
          lineOfSightRayCount += 1;
          for (const part of permanentParts) {
            if ((part.properties.Transparency ?? 0) >= 0.99) continue;
            if (isApprovedPane(part, root)) continue;
            if (pointInsidePart(sample.point, part)) continue;
            if (segmentIntersectsPart(origin, sample.point, part)) {
              failures.push(`${root}/${anchorName}/${sample.name} blocked by ${part.path}`);
              break;
            }
          }
        }
      }
    }
    assert.equal(lineOfSightRayCount, 32 * 8 * 3);
    assert.deepEqual(failures, [], failures.slice(0, 20).join("\n"));
  });

  criterion("Lighting service properties are authored exactly", () => {
    const properties = lightingSteps[0].properties;
    assert.equal(enumName(properties.Technology), "Future");
    assert.equal(properties.Brightness, 2);
    assert.equal(properties.ExposureCompensation, -0.25);
    assert.deepEqual(colorTuple(properties.Ambient), [28, 35, 45]);
    assert.deepEqual(colorTuple(properties.OutdoorAmbient), [20, 25, 32]);
    assert.equal(properties.EnvironmentDiffuseScale, 0.35);
    assert.equal(properties.EnvironmentSpecularScale, 0.55);
    assert.equal(properties.GlobalShadows, true);
    assert.equal(properties.ShadowSoftness, 0.35);
    assert.equal(properties.ClockTime, 14.5);
  });

  criterion("BloomEffect is singular and restrained", () => {
    const blooms = instanceSteps.filter((step) => step.className === "BloomEffect");
    assert.equal(blooms.length, 1);
    const bloom = assertPath(instancesByPath, "Lighting.Bloom", "BloomEffect");
    assert.equal(bloom.properties.Enabled, true);
    assert.ok(bloom.properties.Intensity >= 0.10 && bloom.properties.Intensity <= 0.18);
    assert.ok(bloom.properties.Size >= 12 && bloom.properties.Size <= 18);
    assert.ok(bloom.properties.Threshold >= 1.35 && bloom.properties.Threshold <= 1.55);
  });

  criterion("ColorCorrectionEffect is singular and restrained", () => {
    const corrections = instanceSteps.filter((step) => step.className === "ColorCorrectionEffect");
    assert.equal(corrections.length, 1);
    const correction = assertPath(instancesByPath, "Lighting.ONE_MORE_ITEM_ColorCorrection", "ColorCorrectionEffect");
    assert.equal(correction.properties.Enabled, true);
    assert.ok(correction.properties.Contrast >= 0.06 && correction.properties.Contrast <= 0.12);
    assert.ok(correction.properties.Saturation >= -0.10 && correction.properties.Saturation <= -0.04);
    assert.ok(correction.properties.Brightness >= -0.03 && correction.properties.Brightness <= 0);
  });

  criterion("no enabled DepthOfFieldEffect or uncontrolled gameplay blur is authored", () => {
    for (const effect of instanceSteps.filter((step) => step.className === "DepthOfFieldEffect")) assert.equal(effect.properties.Enabled, false);
    for (const source of phase07Sources.map(readText)) assert.doesNotMatch(source, /DepthOfFieldEffect|MotionBlur/i);
  });

  criterion("dynamic lights are bounded at 20 and exactly eight task lights exist", () => {
    const dynamicLights = instanceSteps.filter((step) => ["PointLight", "SpotLight", "SurfaceLight"].includes(step.className));
    assert.ok(dynamicLights.length <= 20, `Dynamic light count ${dynamicLights.length}`);
    assert.equal(dynamicLights.filter((step) => /\.Crate\.TaskLight\.Light$/.test(step.path)).length, 8);
    assert.ok(dynamicLights.filter((step) => step.properties.Shadows === true).length <= 4);
  });

  criterion("giant Neon surfaces are rejected unless explicitly allowlisted", () => {
    for (const part of instanceSteps.filter((step) => step.className === "Part" && enumName(step.properties.Material) === "Neon")) {
      const sorted = vector(part.properties.Size).sort((a, b) => a - b);
      assert.ok(sorted[1] <= 1.25 || part.attributes.Phase07NeonAllowlisted === true, `Oversized Neon surface ${part.path}`);
    }
  });

  criterion("giant glowing spheres are rejected under station paths", () => {
    for (const part of instanceSteps.filter((step) => step.className === "Part" && step.path.startsWith(`${stationsRoot}.`) && enumName(step.properties.Shape) === "Ball")) {
      assert.ok(Math.max(...vector(part.properties.Size)) <= 1.2, `Giant station sphere ${part.path}`);
    }
  });

  criterion("owner displays are finite distance and never AlwaysOnTop", () => {
    for (let index = 1; index <= 8; index += 1) {
      const gui = assertPath(instancesByPath, `${stationRoot(index)}.OwnerDisplay.BillboardGui`, "BillboardGui");
      assert.ok(gui.properties.MaxDistance > 0 && gui.properties.MaxDistance <= 70);
      assert.equal(gui.properties.AlwaysOnTop, false);
    }
  });

  criterion("collection shelf labels are distance limited and world occluded", () => {
    for (let index = 1; index <= 8; index += 1) {
      const gui = assertPath(instancesByPath, `${stationRoot(index)}.CollectionShelf.ShelfLabel.BillboardGui`, "BillboardGui");
      assert.ok(gui.properties.MaxDistance > 0 && gui.properties.MaxDistance <= 60);
      assert.equal(gui.properties.AlwaysOnTop, false);
    }
  });

  criterion("central announcement and server-best surfaces remain singular", () => {
    assert.equal(instanceSteps.filter((step) => step.path === `${worldRoot}.CenterDispatch.ArenaAnnouncement`).length, 1);
    assert.equal(instanceSteps.filter((step) => step.path === `${worldRoot}.CenterDispatch.ServerBest`).length, 1);
  });

  criterion("MetaBar layouts satisfy desktop density targets", () => {
    const source = readText("src/StarterPlayer/StarterPlayerScripts/ONE_MORE_ITEM_Client/Controllers/ProfileResponsiveLayout.luau");
    const wide = source.match(/Wide\s*=\s*table\.freeze\(\{[\s\S]*?MetaBar\s*=\s*geometry\([^,]+,[^,]+,[^,]+,\s*([\d.]+)\)/)?.[1];
    const compact = source.match(/CompactLandscape\s*=\s*table\.freeze\(\{[\s\S]*?MetaBar\s*=\s*geometry\([^,]+,[^,]+,[^,]+,\s*([\d.]+)\)/)?.[1];
    const portrait = source.match(/Portrait\s*=\s*table\.freeze\(\{[\s\S]*?MetaBar\s*=\s*geometry\([^,]+,[^,]+,[^,]+,\s*([\d.]+)\)/)?.[1];
    assert.ok(Number(wide) * 1080 <= 64);
    assert.ok(Number(wide) * 768 <= 58);
    assert.ok(Number(compact) * 430 <= 58);
    assert.ok(Number(portrait) * 640 <= 58);
  });

  criterion("StarterMissionCard stays below twelve percent of safe viewport area", () => {
    const source = readText("src/StarterPlayer/StarterPlayerScripts/ONE_MORE_ITEM_Client/Controllers/ResponsiveLayout.luau");
    const dimensions = [...source.matchAll(/StarterMissionCard\s*=\s*geometry\("Root",\s*[^,]+,\s*[^,]+,\s*([\d.]+),\s*([\d.]+)/g)]
      .map((match) => [Number(match[1]), Number(match[2])]);
    assert.equal(dimensions.length, 3);
    for (const [width, height] of dimensions) assert.ok(width * height < 0.12, `StarterMissionCard area ${width * height}`);
  });

  criterion("current item shipment decision and results surfaces remain authored", () => {
    for (const name of ["CurrentItemCard", "ShipmentCard", "PlacementControls", "DecisionPanel", "ResultsPanel"]) {
      assert.ok(instancesByPath.has(`${uiRoot}.${name}`), `Missing ${uiRoot}.${name}`);
    }
  });

  criterion("ZIndex is authored only on GUI object classes that support it", () => {
    const zIndexClasses = new Set(["Frame", "TextButton", "TextLabel", "ViewportFrame"]);
    for (const entry of instanceSteps.filter((step) => step.path.startsWith(`${uiScreen}.`))) {
      if (entry.properties.ZIndex !== undefined) {
        assert.ok(zIndexClasses.has(entry.className), `${entry.path} cannot own ZIndex as ${entry.className}`);
      }
    }
  });

  criterion("CollectionPanel and its accepted eight-slot layout remain present", () => {
    assertPath(instancesByPath, `${uiRoot}.CollectionPanel`, "Frame");
    assert.equal(instanceSteps.filter((step) => new RegExp(`^${uiRoot.replaceAll(".", "\\.")}\\.CollectionPanel\\.Slots\\.Slot_\\d\\d$`).test(step.path)).length, 8);
  });

  criterion("onboarding and mission UI remain permanently authored", () => {
    for (const name of ["OnboardingOverlay", "StarterMissionCard", "StarterPathPanel", "MissionCompleteBanner"]) {
      assert.ok(instancesByPath.has(`${uiRoot}.${name}`), `Missing ${uiRoot}.${name}`);
    }
  });

  criterion("existing gameplay Net remains exactly six remotes", () => {
    const remotes = instanceSteps.filter((step) => step.className === "RemoteEvent" && step.path.startsWith("ReplicatedStorage.ONE_MORE_ITEM.Net."));
    assert.deepEqual(remotes.map((step) => step.path.split(".").at(-1)).sort(), gameplayRemoteNames);
  });

  criterion("ProfileNet remains exactly one server-to-client remote", () => {
    const remotes = instanceSteps.filter((step) => step.className === "RemoteEvent" && step.path.startsWith("ReplicatedStorage.ONE_MORE_ITEM.ProfileNet."));
    assert.deepEqual(remotes.map((step) => step.path.split(".").at(-1)), ["ProfileSnapshot"]);
  });

  criterion("OnboardingNet remains exactly one narrowly scoped request remote", () => {
    const remotes = instanceSteps.filter((step) => step.className === "RemoteEvent" && step.path.startsWith("ReplicatedStorage.ONE_MORE_ITEM.OnboardingNet."));
    assert.deepEqual(remotes.map((step) => step.path.split(".").at(-1)), ["OnboardingActionRequest"]);
  });

  criterion("no new gameplay or profile mutation remote exists", () => {
    const expected = new Set([
      ...gameplayRemoteNames.map((name) => `ReplicatedStorage.ONE_MORE_ITEM.Net.${name}`),
      "ReplicatedStorage.ONE_MORE_ITEM.ProfileNet.ProfileSnapshot",
      "ReplicatedStorage.ONE_MORE_ITEM.OnboardingNet.OnboardingActionRequest",
    ]);
    const actual = instanceSteps.filter((step) => step.className === "RemoteEvent").map((step) => step.path);
    assert.deepEqual(new Set(actual), expected);
  });

  criterion("profile schema remains Version 2 in the accepted stores", () => {
    const profileConfig = readText("src/ServerScriptService/ONE_MORE_ITEM_Server/Services/Profile/ProfileConfig.luau");
    assert.match(profileConfig, /SCHEMA_VERSION\s*=\s*2\b/);
    assert.match(profileConfig, /ONE_MORE_ITEM_PlayerProfiles_v1/);
    assert.match(profileConfig, /ONE_MORE_ITEM_PlayerProfiles_StudioTest_v1/);
    assert.doesNotMatch(profileConfig, /PlayerProfiles_v2|StudioTest_v2/);
  });

  criterion("progression rewards and item-shape definitions are byte-identical to the accepted Phase 06 baseline", () => {
    for (const [relativePath, expectedHash] of protectedContentHashes) {
      assert.equal(digest(relativePath), expectedHash, `${relativePath} changed outside Phase 07 scope`);
    }
  });

  criterion("accepted gameplay timers and maximum-item values remain unchanged", () => {
    const expected = new Map([
      ["INITIAL_PREPARING_DURATION", "0.12"], ["RESTART_PREPARING_DURATION", "0.72"], ["PRESENTATION_DURATION", "0.45"],
      ["PLACEMENT_DURATION", "30"], ["DECISION_DURATION", "8"], ["GUIDED_PLACEMENT_DURATION", "45"],
      ["GUIDED_DECISION_DURATION", "12"], ["SHIPPING_PRESENTATION_DURATION", "1.35"], ["FAILURE_PRESENTATION_DURATION", "1.0"],
      ["MAXIMUM_ITEMS", "10"], ["GRID_CELL_SIZE", "2"],
    ]);
    for (const [name, value] of expected) assert.match(roundConfig, new RegExp(`${name}\\s*=\\s*${value.replace(".", "\\.")}\\b`));
  });

  criterion("accepted multiplier values remain unchanged", () => {
    const multipliers = [...roundConfig.matchAll(/\[(\d+)\]\s*=\s*(\d+(?:\.\d+)?)/g)].slice(0, 10)
      .map((match) => [Number(match[1]), Number(match[2])]);
    assert.deepEqual(multipliers, [[1, 1], [2, 1.15], [3, 1.35], [4, 1.6], [5, 1.9], [6, 2.25], [7, 2.65], [8, 3.2], [9, 3.9], [10, 5]]);
  });

  criterion("Phase 07 development test flag and fixed seed are explicit", () => {
    assert.match(roundConfig, /RUN_PHASE07_TESTS\s*=\s*true/);
    assert.match(roundConfig, /PHASE07_TEST_SEED\s*=\s*17072026\b/);
  });

  criterion("runtime production sources do not build permanent UI or world roots", () => {
    const runtimeSources = listFilesRecursively(path.join(repositoryRoot, "src")).filter((file) => file.endsWith(".luau") && !/[\\/]Dev[\\/]Phase\d+TestSuite\.luau$/.test(file));
    for (const file of runtimeSources) {
      const source = fs.readFileSync(file, "utf8");
      const relative = path.relative(repositoryRoot, file).replaceAll("\\", "/");
      assert.ok(!(/ONE_MORE_ITEM_WORLD|ONE_MORE_ITEM_Gameplay/.test(source) && /Instance\.new\s*\(/.test(source)), `Runtime permanent builder rejected: ${relative}`);
      assert.doesNotMatch(source, /Instance\.new\s*\(\s*["'](?:ScreenGui|RemoteEvent)["']\s*\)/, `Runtime UI/remote builder rejected: ${relative}`);
    }
  });

  criterion("Phase 07 adds no external image sound texture mesh or package asset ID", () => {
    const relevantText = [JSON.stringify(manifest), ...listFilesRecursively(path.join(repositoryRoot, "src")).filter((file) => file.endsWith(".luau")).map((file) => fs.readFileSync(file, "utf8"))].join("\n");
    assert.doesNotMatch(relevantText, /rbxassetid:\/\/|https?:\/\/www\.roblox\.com\/asset|(?:Image|Sound|Texture|Mesh|Package)Id\s*[=:]\s*["']?\d+/i);
  });

  criterion("all Phase 07 production sources begin with strict mode", () => {
    for (const relativePath of phase07Sources) assert.match(readText(relativePath), /^--!strict(?:\r?\n|$)/, `${relativePath} is not strict`);
  });

  criterion("all Phase 07 Studio tests begin with strict mode and cover the 768-ray matrix", () => {
    for (const relativePath of phase07Tests) assert.match(readText(relativePath), /^--!strict(?:\r?\n|$)/, `${relativePath} is not strict`);
    const suite = readText(phase07Tests[0]);
    assert.match(suite, /32\s*\*\s*8\s*\*\s*3/);
    assert.match(suite, /LineOfSightRays/);
  });

  criterion("generated authoring has no absolute local paths or private data", () => {
    const generated = `${firstBlueprintBytes.toString("utf8")}\n${firstCommandBytes.toString("utf8")}`;
    assert.ok(!generated.includes(repositoryRoot));
    assert.doesNotMatch(generated, /[A-Za-z]:[\\/](?:Users|home)[\\/]/i);
    assert.doesNotMatch(generated, /(?:api[_-]?key|password|cookie|authorization|access[_-]?token|refresh[_-]?token)\s*[=:]\s*["'][^"']{4,}/i);
  });

  criterion("no screenshot video recovery autosave or cache artifact is tracked", () => {
    const forbidden = /(?:^|\/)(?:\.codex-cache|recovery|autosave|screenshots?|evidence|recordings?|videos?)(?:\/|$)|\.(?:png|jpe?g|gif|webp|mp4|mov|avi|rbxlx?|rbxl\.lock)$/i;
    for (const tracked of trackedFiles()) assert.doesNotMatch(tracked.replaceAll("\\", "/"), forbidden, `Forbidden tracked artifact ${tracked}`);
  });

  criterion("workflow uses the exact Phase 01 through 07 Node 24 contract", () => {
    const workflow = readText(workflowRelativePath);
    assert.match(workflow, /^name:\s*Phase 01(?:\u2013|-)07 Node Validation/m);
    assert.match(workflow, /actions\/checkout@v7/);
    assert.match(workflow, /actions\/setup-node@v6/);
    assert.match(workflow, /node-version:\s*24/);
    assert.match(workflow, /package-manager-cache:\s*false/);
    assert.match(workflow, /permissions:\s*\r?\n\s+contents:\s*read/);
    for (const [gate] of priorGates) assert.match(workflow, new RegExp(`node tools/${gate.replaceAll(".", "\\.")}`));
    assert.match(workflow, /node tools\/test_phase07_visual_readability\.mjs/);
    assert.doesNotMatch(workflow, /npm (?:install|ci)|pnpm|yarn/);
  });

  criterion("workflow triggers remain main pull requests main pushes and codex pushes", () => {
    const workflow = readText(workflowRelativePath);
    assert.match(workflow, /pull_request:[\s\S]*branches:[\s\S]*- main/);
    assert.match(workflow, /push:[\s\S]*branches:[\s\S]*- main[\s\S]*- ['"]codex\/\*\*['"]/);
  });

  criterion("Phase 06 exact squash merge SHA is documented", () => {
    for (const relativePath of ["README.md", "docs/DEVELOPMENT_STATUS.md", "CHANGELOG.md"]) {
      assert.match(readText(relativePath), new RegExp(phase06MergeSha));
    }
  });

  criterion("Issue 4 remains referenced as open with Phase 07 deferred QA", () => {
    const status = readText("docs/DEVELOPMENT_STATUS.md");
    assert.match(status, /Issue #4[^\n]*remains open/i);
    assert.match(status, /github\.com\/kotonja\/ONE-MORE-ITEM-\/issues\/4/);
    assert.match(status, /Phase 07 visual and arena QA additions/i);
    for (const deferredCheck of [
      "Physical-phone crate readability",
      "Physical-controller visual flow",
      "Low-end-device lighting and transparency performance",
      "Color-vision-deficiency review",
      "Eight-player long-session world-label clutter",
      "Eight-player simultaneous showcase visibility",
      "Long-session camera and label cleanup",
      "Production screenshot and thumbnail review",
      "Final object-model replacement",
      "Final sound/music/VFX integration",
      "Final art consistency review",
      "Public-beta visual feedback",
      "Production-device bloom/exposure review",
    ]) {
      assert.match(status, new RegExp(deferredCheck.replaceAll("/", "\\/"), "i"));
    }
  });

  criterion("Phase 07 branch and active-unaccepted status are documented without Phase 08 work", () => {
    const developmentStatus = readText("docs/DEVELOPMENT_STATUS.md");
    const phase07 = readText("docs/PHASE07_VISUAL_READABILITY_ARENA_REBUILD.md");
    const readme = readText("README.md");
    const status = `${readme}\n${developmentStatus}`;
    assert.match(status, /codex\/phase-07-visual-readability-arena-rebuild/);
    assert.match(status, /Phase 07[^\n]*(?:active|Current phase)/i);
    assert.match(status, /Phase 07[^\n]*unaccepted/i);
    assert.match(status, /No Phase 08|Do not begin Phase 08/i);
    assert.match(developmentStatus, /\*\*Phase result:\*\*\s+\*\*In progress and unaccepted\.\*\*/i);
    assert.match(developmentStatus, /PR #8[^\n]*open, draft, and unmerged/i);
    assert.match(developmentStatus, /Issue #4[^\n]*remains open/i);
    assert.match(developmentStatus, /acceptance-time comment[^\n]*(?:has not been posted|unposted)/i);
    assert.match(developmentStatus, /\| Cloud save \|[^\n]*Passed normal publish/i);
    assert.match(developmentStatus, /\| Direct no-sync reopen \|[^\n]*Passed[^\n]*without synchronization/i);
    assert.match(readme, /15\/15[^\n]*required screenshots[^\n]*accepted/i);
    assert.match(developmentStatus, /15\/15[^\n]*screenshot frames accepted/i);
    assert.match(developmentStatus, /frame 12[^\n]*(?:genuine|same-session)[^\n]*four-client/i);
    assert.match(developmentStatus, /frame 15[^\n]*physical authored collection shelf/i);
    assert.doesNotMatch(developmentStatus, /(?:clearer\s+)?screenshot frames? 12 and 15[^\n]*(?:remain|pending|must|need)/i);
    assert.match(developmentStatus, /unedited continuous recording remains pending/i);
    assert.match(developmentStatus, /replacement unedited continuous recording[^\n]*(?:3-6|3\u20136) minutes/i);
    assert.match(phase07, /\*\*Active and unaccepted\.\*\*/i);
    assert.match(phase07, /does \*\*not\*\* claim[^\n]*accepted continuous recording/i);
    assert.match(phase07, /replacement unedited continuous recording is the sole remaining visual-acceptance blocker/i);
  });

  assert.ok(criterionCount >= 160, `Phase 07 Node gate requires at least 160 criteria, got ${criterionCount}`);
  console.log(
    `[Phase07VisualReadability] PASS criteria=${criterionCount} instances=${instanceSteps.length} scripts=${scriptSteps.length} stations=8 losRays=${lineOfSightRayCount} pointLights=${instanceSteps.filter((step) => step.className === "PointLight").length} deterministic=true prior=true`,
  );
} catch (error) {
  console.error(`[Phase07VisualReadability] FAIL criterion=${criterionCount + 1} ${error instanceof Error ? error.message : String(error)}`);
  process.exitCode = 1;
} finally {
  if (temporaryRoot) fs.rmSync(temporaryRoot, { recursive: true, force: true });
}
