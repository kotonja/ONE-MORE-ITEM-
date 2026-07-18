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
  {
    path: path.join(toolsDirectory, "test_studio_blueprint.mjs"),
    pass: /\[StudioSyncSmoke\] PASS checks=16 folders=7 scripts=10 deterministic=true/,
  },
  {
    path: path.join(toolsDirectory, "test_phase02_blueprint.mjs"),
    pass: /\[Phase02StudioSyncSmoke\] PASS criteria=\d+ instances=\d+ scripts=\d+ remotes=6 deterministic=true phase01=true/,
  },
  {
    path: path.join(toolsDirectory, "test_phase03_cross_platform.mjs"),
    pass: /\[Phase03CrossPlatformSmoke\] PASS criteria=\d+ viewports=13 insetProfiles=5 layoutCases=65 remotes=6 deterministic=true phase01=true phase02=true/,
  },
];
const expectedRemotes = [
  "ClientReadyRequest",
  "DecisionRequest",
  "PlaceItemRequest",
  "PlacementResponse",
  "RestartRequest",
  "RoundSnapshot",
];
const stationRelativePaths = [
  "StationRoot",
  "PlayerStand",
  "CameraAnchor",
  "CameraAnchorTouchLandscape",
  "CameraAnchorTouchPortrait",
  "CameraFocus",
  "PresentationPoint",
  "DispatchPort",
  "Crate",
  "Crate.Base",
  "Crate.GridOrigin",
  "Crate.GridTiles",
  "Crate.WallFront",
  "Crate.WallBack",
  "Crate.WallLeft",
  "Crate.WallRight",
  "Crate.Lid",
  "Crate.CrateFocus",
  "ControlConsole",
  "ControlConsole.RotateButton",
  "ControlConsole.PlaceButton",
  "ControlConsole.ShipButton",
  "ControlConsole.OneMoreButton",
  "OwnerDisplay",
  "OwnerDisplay.BillboardGui",
  "OwnerDisplay.BillboardGui.PlayerName",
  "OwnerDisplay.BillboardGui.RoundStatus",
  "OwnerDisplay.BillboardGui.RiskValue",
  "OwnerDisplay.BillboardGui.StationNumber",
  "RiskIndicator",
  "RiskIndicator.IndicatorPart",
  "RiskIndicator.IndicatorPart.Light",
  "PlacedItems",
  "RuntimePresentation",
];
const centerDispatchPaths = [
  "Base",
  "Lift",
  "LiftTop",
  "ShowcaseEntry",
  "ArenaAnnouncement",
  "ArenaAnnouncement.BillboardGui",
  "ArenaAnnouncement.BillboardGui.Headline",
  "ArenaAnnouncement.BillboardGui.Detail",
  "ServerBest",
  "ServerBest.BillboardGui",
  "ServerBest.BillboardGui.PlayerName",
  "ServerBest.BillboardGui.ShipmentValue",
  "ServerBest.BillboardGui.ItemCount",
];

let criterionCount = 0;

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

function requireSuccessfulNodeGate(gate) {
  const result = runNode(gate.path);
  assert.equal(result.status, 0, `${path.basename(gate.path)} failed:\n${result.stderr || result.stdout}`);
  assert.match(result.stdout, gate.pass, `${path.basename(gate.path)} did not emit its required PASS summary`);
}

function readText(relativePath) {
  return fs.readFileSync(path.join(repositoryRoot, relativePath), "utf8");
}

function trackedFiles() {
  const result = spawnSync("git", ["ls-files", "-z"], { cwd: repositoryRoot, encoding: "buffer" });
  assert.equal(result.status, 0, `git ls-files failed: ${result.stderr.toString("utf8")}`);
  return result.stdout.toString("utf8").split("\0").filter(Boolean);
}

function listFilesRecursively(directory) {
  const files = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const child = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...listFilesRecursively(child));
    else if (entry.isFile()) files.push(child);
  }
  return files;
}

function cframePosition(step, label) {
  const value = step?.properties?.CFrame;
  assert.equal(value?.__type, "CFrame", `${label} requires an authored CFrame`);
  assert.equal(value.components?.length, 12, `${label} CFrame must contain 12 components`);
  return value.components.slice(0, 3);
}

function cframeLookVector(step, label) {
  const components = step?.properties?.CFrame?.components;
  assert.equal(components?.length, 12, `${label} requires a 12-component CFrame`);
  return [-components[5], -components[8], -components[11]];
}

function horizontalDistance(a, b) {
  return Math.hypot(a[0] - b[0], a[2] - b[2]);
}

function normalizedHorizontal(vector) {
  const magnitude = Math.hypot(vector[0], vector[2]);
  assert.ok(magnitude > 0, "Horizontal vector cannot be zero");
  return [vector[0] / magnitude, vector[2] / magnitude];
}

function dot2(a, b) {
  return a[0] * b[0] + a[1] * b[1];
}

function stationObb(step) {
  const c = step.properties.CFrame.components;
  const size = step.properties.Size;
  assert.equal(size?.__type, "Vector3", `${step.path} requires authored Size`);
  return {
    center: [c[0], c[2]],
    axes: [normalizedHorizontal([c[3], 0, c[9]]), normalizedHorizontal([c[5], 0, c[11]])],
    extents: [size.x / 2, size.z / 2],
  };
}

function obbsOverlap(first, second) {
  const delta = [second.center[0] - first.center[0], second.center[1] - first.center[1]];
  const axes = [...first.axes, ...second.axes];
  for (const axis of axes) {
    const firstRadius = first.extents[0] * Math.abs(dot2(first.axes[0], axis))
      + first.extents[1] * Math.abs(dot2(first.axes[1], axis));
    const secondRadius = second.extents[0] * Math.abs(dot2(second.axes[0], axis))
      + second.extents[1] * Math.abs(dot2(second.axes[1], axis));
    if (Math.abs(dot2(delta, axis)) >= firstRadius + secondRadius - 1e-6) return false;
  }
  return true;
}

function assertNoScriptDescendants(scriptSteps, rootPath) {
  assert.ok(
    scriptSteps.every((step) => !step.path.startsWith(`${rootPath}.`)),
    `${rootPath} must contain no scripts`,
  );
}

let temporaryRoot;
try {
  // The Phase 04 gate deliberately proves all inherited gates before reading
  // or validating any Phase 04 artifact.
  for (const gate of priorGates) requireSuccessfulNodeGate(gate);

  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "one-more-item-phase04-"));
  const firstOutput = path.join(temporaryRoot, "first");
  const secondOutput = path.join(temporaryRoot, "second");
  const firstGeneration = runNode(generatorPath, [manifestPath, firstOutput]);
  assert.equal(firstGeneration.status, 0, `Phase 04 generation failed:\n${firstGeneration.stderr || firstGeneration.stdout}`);
  const secondGeneration = runNode(generatorPath, [manifestPath, secondOutput]);
  assert.equal(secondGeneration.status, 0, `Repeated Phase 04 generation failed:\n${secondGeneration.stderr || secondGeneration.stdout}`);

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
  const worldRoot = "Workspace.ONE_MORE_ITEM_WORLD.PlaytestArena";
  const stationsRoot = `${worldRoot}.Stations`;
  const stationRoots = Array.from({ length: 8 }, (_, index) => `${stationsRoot}.Station_${String(index + 1).padStart(2, "0")}`);

  criterion("exactly eight final station models", () => {
    const models = instanceSteps.filter((step) => /^Workspace\.ONE_MORE_ITEM_WORLD\.PlaytestArena\.Stations\.Station_\d{2}$/.test(step.path));
    assert.equal(models.length, 8);
    assert.ok(models.every((step) => step.className === "Model"));
  });

  criterion("station IDs are station_01 through station_08", () => {
    assert.deepEqual(stationRoots.map((root) => instancesByPath.get(root)?.attributes?.StationId),
      Array.from({ length: 8 }, (_, index) => `station_${String(index + 1).padStart(2, "0")}`));
  });

  criterion("station indexes are unique one through eight", () => {
    const indexes = stationRoots.map((root) => instancesByPath.get(root)?.attributes?.StationIndex);
    assert.deepEqual(indexes, [1, 2, 3, 4, 5, 6, 7, 8]);
    assert.equal(new Set(indexes).size, 8);
  });

  criterion("station gameplay attributes remain uniform", () => {
    for (const root of stationRoots) {
      const attrs = instancesByPath.get(root)?.attributes;
      assert.equal(attrs.Active, true);
      assert.equal(attrs.GridWidth, 5);
      assert.equal(attrs.GridHeight, 4);
      assert.equal(attrs.GridDepth, 5);
      assert.equal(attrs.CellSize, 2);
    }
  });

  criterion("every station has the required permanent hierarchy", () => {
    for (const root of stationRoots) {
      for (const relativePath of stationRelativePaths) {
        assert.ok(instancesByPath.has(`${root}.${relativePath}`), `Missing ${root}.${relativePath}`);
      }
    }
  });

  criterion("every station has exactly 25 authored grid tiles", () => {
    for (const root of stationRoots) {
      const prefix = `${root}.Crate.GridTiles.Cell_`;
      const tiles = instanceSteps.filter((step) => step.path.startsWith(prefix));
      assert.equal(tiles.length, 25, `${root} must own 25 grid tiles`);
      for (let x = 0; x < 5; x += 1) {
        for (let z = 0; z < 5; z += 1) assert.ok(instancesByPath.has(`${prefix}${x}_${z}`));
      }
    }
  });

  criterion("every station has all responsive camera anchors", () => {
    for (const root of stationRoots) {
      for (const name of ["CameraAnchor", "CameraAnchorTouchLandscape", "CameraAnchorTouchPortrait"]) {
        const anchor = instancesByPath.get(`${root}.${name}`);
        assert.equal(anchor?.className, "Part");
        assert.equal(anchor.properties.Anchored, true);
        assert.equal(anchor.properties.Transparency, 1);
      }
    }
  });

  criterion("every station has an authored owner display", () => {
    for (const root of stationRoots) assert.equal(instancesByPath.get(`${root}.OwnerDisplay.BillboardGui`)?.className, "BillboardGui");
  });

  criterion("every station has an authored risk indicator", () => {
    for (const root of stationRoots) {
      const light = instancesByPath.get(`${root}.RiskIndicator.IndicatorPart.Light`);
      assert.equal(light?.className, "PointLight");
      assert.equal(light.properties.Enabled, false, `${root} risk light must start disabled`);
      assert.equal(light.properties.Brightness, 0, `${root} risk light must start dark`);
      assert.equal(light.properties.Shadows, false, `${root} risk light may not cast shadows`);
    }
  });

  criterion("every station has an authored dispatch port", () => {
    for (const root of stationRoots) assert.equal(instancesByPath.get(`${root}.DispatchPort`)?.className, "Part");
  });

  const stationRootParts = stationRoots.map((root) => instancesByPath.get(`${root}.StationRoot`));
  criterion("station transforms form one deterministic ring", () => {
    const radii = stationRootParts.map((step, index) => {
      const position = cframePosition(step, `Station_${index + 1}.StationRoot`);
      return Math.hypot(position[0], position[2]);
    });
    assert.ok(radii.every((radius) => Math.abs(radius - 50) < 0.001));
    assert.ok(Math.max(...radii) - Math.min(...radii) < 0.001);
  });

  criterion("stations face the arena center with local negative Z", () => {
    for (const step of stationRootParts) {
      const position = cframePosition(step, step.path);
      const towardCenter = normalizedHorizontal([-position[0], 0, -position[2]]);
      const look = normalizedHorizontal(cframeLookVector(step, step.path));
      assert.ok(dot2(towardCenter, look) > 0.999, `${step.path} does not face center`);
    }
  });

  criterion("station authored footprints do not overlap", () => {
    const obbs = stationRootParts.map(stationObb);
    for (let first = 0; first < obbs.length; first += 1) {
      for (let second = first + 1; second < obbs.length; second += 1) {
        assert.equal(obbsOverlap(obbs[first], obbs[second]), false, `Station ${first + 1} overlaps Station ${second + 1}`);
      }
    }
  });

  criterion("opposite stations have opposite grid transforms", () => {
    const first = cframePosition(instancesByPath.get(`${stationRoots[0]}.Crate.GridOrigin`), "Station_01 GridOrigin");
    const fifth = cframePosition(instancesByPath.get(`${stationRoots[4]}.Crate.GridOrigin`), "Station_05 GridOrigin");
    assert.ok(Math.abs(first[0] + fifth[0]) < 0.001);
    assert.ok(Math.abs(first[2] + fifth[2]) < 0.001);
    const firstLook = normalizedHorizontal(cframeLookVector(instancesByPath.get(`${stationRoots[0]}.Crate.GridOrigin`), "Station_01 GridOrigin"));
    const fifthLook = normalizedHorizontal(cframeLookVector(instancesByPath.get(`${stationRoots[4]}.Crate.GridOrigin`), "Station_05 GridOrigin"));
    assert.ok(dot2(firstLook, fifthLook) < -0.999);
  });

  criterion("center dispatch hierarchy is permanent", () => {
    const root = `${worldRoot}.CenterDispatch`;
    assert.ok(instancesByPath.has(root));
    for (const relativePath of centerDispatchPaths) assert.ok(instancesByPath.has(`${root}.${relativePath}`), `Missing ${root}.${relativePath}`);
  });

  criterion("arena announcement is world-authored", () => {
    assert.equal(instancesByPath.get(`${worldRoot}.CenterDispatch.ArenaAnnouncement.BillboardGui`)?.className, "BillboardGui");
  });

  criterion("server-best board is world-authored", () => {
    assert.equal(instancesByPath.get(`${worldRoot}.CenterDispatch.ServerBest.BillboardGui`)?.className, "BillboardGui");
  });

  const showcaseTemplate = "ReplicatedStorage.ONE_MORE_ITEM.Assets.Development.ShowcaseCrateTemplate";
  criterion("showcase crate template is permanent and script-free", () => {
    assert.equal(instancesByPath.get(showcaseTemplate)?.className, "Model");
    assert.ok(instancesByPath.has(`${showcaseTemplate}.Base`));
    assert.ok(instancesByPath.has(`${showcaseTemplate}.Lid`));
    for (const wallName of ["WallFront", "WallBack", "WallLeft", "WallRight"]) {
      assert.ok(instancesByPath.has(`${showcaseTemplate}.${wallName}`));
    }
    const displayRoot = `${showcaseTemplate}.DisplayAnchor.BillboardGui`;
    assert.ok(instancesByPath.has(`${displayRoot}.PlayerName`));
    assert.ok(instancesByPath.has(`${displayRoot}.ShipmentValue`));
    assert.ok(instancesByPath.has(`${displayRoot}.ItemCount`));
    for (const step of instanceSteps.filter((candidate) => candidate.path.startsWith(`${showcaseTemplate}.`) && candidate.className === "Part")) {
      assert.equal(step.properties.Anchored, true, `${step.path} must be anchored`);
      assert.equal(step.properties.CanCollide, false, `${step.path} must not collide`);
      assert.equal(step.properties.CanTouch, false, `${step.path} must not touch`);
      assert.equal(step.properties.CanQuery, false, `${step.path} must not be queryable`);
    }
    assertNoScriptDescendants(scriptSteps, showcaseTemplate);
  });

  const pathRoot = `${worldRoot}.ShowcaseLoop.PathNodes`;
  const pathNodes = Array.from({ length: 16 }, (_, index) => instancesByPath.get(`${pathRoot}.Node_${String(index + 1).padStart(2, "0")}`));
  criterion("sixteen authored showcase path nodes exist", () => {
    assert.ok(pathNodes.every((step) => step?.className === "Part"));
  });

  criterion("path-node names are deterministic", () => {
    assert.deepEqual(pathNodes.map((step) => step.path.split(".").at(-1)),
      Array.from({ length: 16 }, (_, index) => `Node_${String(index + 1).padStart(2, "0")}`));
  });

  criterion("path-node positions are unique", () => {
    const keys = pathNodes.map((step) => cframePosition(step, step.path).map((value) => value.toFixed(6)).join(","));
    assert.equal(new Set(keys).size, 16);
  });

  criterion("path nodes are invisible, inert, and above players", () => {
    for (const step of pathNodes) {
      assert.equal(step.properties.Anchored, true);
      assert.equal(step.properties.CanCollide, false);
      assert.equal(step.properties.CanQuery, false);
      assert.equal(step.properties.CanTouch, false);
      assert.equal(step.properties.Transparency, 1);
      assert.ok(cframePosition(step, step.path)[1] >= 15);
    }
  });

  criterion("showcase runtime folder exists", () => {
    assert.equal(instancesByPath.get(`${worldRoot}.ShowcaseLoop.Runtime`)?.className, "Folder");
  });

  criterion("exactly six gameplay remotes remain", () => {
    const remotes = instanceSteps.filter((step) =>
      step.className === "RemoteEvent"
      && step.path.startsWith("ReplicatedStorage.ONE_MORE_ITEM.Net.")
    );
    assert.equal(remotes.length, 6);
    assert.deepEqual(remotes.map((step) => step.path.split(".").at(-1)).sort(), expectedRemotes);
  });

  const productionLuauFiles = listFilesRecursively(path.join(repositoryRoot, "src"))
    .filter((file) => file.endsWith(".luau") && !file.includes(`${path.sep}Dev${path.sep}`));
  criterion("production runtime has no permanent station or UI builder", () => {
    for (const file of productionLuauFiles) {
      const source = fs.readFileSync(file, "utf8");
      assert.doesNotMatch(source, /Instance\.new\s*\(\s*["'](?:ScreenGui|RemoteEvent|BillboardGui)["']\s*\)/,
        `Permanent UI/network construction is forbidden: ${path.relative(repositoryRoot, file)}`);
      assert.doesNotMatch(source, /Instance\.new[\s\S]{0,240}Station_0[1-8]/,
        `Permanent station construction is forbidden: ${path.relative(repositoryRoot, file)}`);
    }
  });

  criterion("production has no Station_01-only assignment behavior", () => {
    for (const file of productionLuauFiles) {
      if (file.endsWith(`${path.sep}StationDefinitions.luau`)) continue;
      const source = fs.readFileSync(file, "utf8");
      assert.doesNotMatch(source, /["']station_01["']|["']Station_01["']/,
        `Station_01-only production reference: ${path.relative(repositoryRoot, file)}`);
      assert.doesNotMatch(source, /snapshot\.StationId\s*==\s*["']station_01["']/);
    }
  });

  criterion("Phase 04 production scripts are strict", () => {
    const requiredNames = [
      "StationDefinitions.luau",
      "DisplayNameSanitizer.luau",
      "ShipmentTypes.luau",
      "StationContextController.luau",
      "StationService.luau",
      "RoundService.luau",
      "WorldItemService.luau",
      "ShipmentRecordService.luau",
      "ShowcaseService.luau",
      "ServerBestService.luau",
      "StationDisplayService.luau",
      "ArenaAnnouncementService.luau",
    ];
    for (const name of requiredNames) {
      const matches = productionLuauFiles.filter((file) => path.basename(file) === name);
      assert.equal(matches.length, 1, `Missing unique Phase 04 source ${name}`);
      assert.match(fs.readFileSync(matches[0], "utf8"), /^--!strict(?:\r?\n)/, `${name} must begin with --!strict`);
    }
  });

  criterion("Phase 04 Studio suite and runner are strict", () => {
    for (const relativePath of [
      "src/ServerScriptService/ONE_MORE_ITEM_Server/Dev/Phase04TestSuite.luau",
      "src/ServerScriptService/ONE_MORE_ITEM_Server/Dev/RunPhase04Tests.server.luau",
    ]) {
      assert.match(readText(relativePath), /^--!strict(?:\r?\n)/);
    }
  });

  criterion("generated output is byte-deterministic", () => {
    assert.deepEqual(secondBlueprintBytes, firstBlueprintBytes);
    assert.deepEqual(secondCommandBytes, firstCommandBytes);
  });

  criterion("authoring reapply cannot create duplicate managed paths", () => {
    const paths = blueprint.steps.map((step) => step.path);
    assert.equal(new Set(paths).size, paths.length);
    assert.deepEqual(JSON.parse(secondBlueprintBytes.toString("utf8")).steps.map((step) => step.path), paths);
  });

  criterion("wrong-class conflicts remain visible and non-destructive", () => {
    for (const operation of commandBar.operations) {
      if (operation.type === "setLighting") {
        assert.equal(operation.path, "Lighting");
        assert.match(operation.command, /Edit-mode only/);
        assert.match(operation.command, /game:GetService\("Lighting"\)/);
        assert.match(operation.command, /pcall/);
        assert.doesNotMatch(operation.command, /:Destroy\s*\(|Instance\.new\s*\(/);
        continue;
      }
      assert.match(operation.command, /sync conflict/);
      const preMutation = operation.type === "writeScript" ? operation.command.split("local sourceOk")[0] : operation.command;
      assert.doesNotMatch(preMutation, /:Destroy\s*\(/);
      assert.match(operation.command, /duplicate managed child|same-name managed children|FindFirstChild/);
    }
  });

  const gitFiles = trackedFiles();
  criterion("tracked project text contains no absolute personal path", () => {
    for (const relativePath of gitFiles) {
      if (!/\.(?:md|json|mjs|ya?ml|luau|txt)$/i.test(relativePath)) continue;
      const source = readText(relativePath);
      assert.doesNotMatch(source, /C:[\\/]Users[\\/]|\/Users\/|file:\/\//i, `Absolute path in ${relativePath}`);
    }
  });

  criterion("no generated cache or recovery file is tracked", () => {
    assert.ok(gitFiles.every((file) => !/(^|\/)(?:\.codex-cache|\.codex-studio|recovery|autosave)(\/|$)/i.test(file)));
    assert.ok(gitFiles.every((file) => !/\.(?:rbxl|rbxlx|tmp|bak)$/i.test(file)));
  });

  criterion("workflow runs the seven Node 24 gates", () => {
    const workflow = readText(".github/workflows/phase01-node-validation.yml");
    assert.match(workflow, /^name:\s*Phase 01(?:–|-)07 Node Validation/m);
    assert.match(workflow, /actions\/checkout@v7/);
    assert.match(workflow, /actions\/setup-node@v6/);
    assert.match(workflow, /node-version:\s*24/);
    assert.match(workflow, /package-manager-cache:\s*false/);
    for (const command of [
      "node tools/test_studio_blueprint.mjs",
      "node tools/test_phase02_blueprint.mjs",
      "node tools/test_phase03_cross_platform.mjs",
      "node tools/test_phase04_multiplayer_arena.mjs",
      "node tools/test_phase05_persistent_progression.mjs",
      "node tools/test_phase06_onboarding_missions_analytics.mjs",
      "node tools/test_phase07_visual_readability.mjs",
    ]) assert.match(workflow, new RegExp(command.replaceAll("/", "\\/")));
  });

  criterion("issue four remains open pre-release QA in documentation", () => {
    const docs = `${readText("README.md")}\n${readText("docs/DEVELOPMENT_STATUS.md")}`;
    assert.match(docs, /issues\/4/);
    assert.match(docs, /Issue #4[^\n]*(?:open|Open)|open[^\n]*Issue #4/i);
    assert.doesNotMatch(docs, /Issue #4[^\n]*(?:closed|resolved|complete)/i);
  });

  criterion("Phase 03 merge SHA is recorded", () => {
    const docs = `${readText("README.md")}\n${readText("docs/DEVELOPMENT_STATUS.md")}`;
    assert.match(docs, /014ff3964eb63f22f8527894067cddb1b4f98070/);
    assert.match(docs, /PR #3[^\n]*merged|merged[^\n]*PR #3/i);
  });

  criterion("Phase 04 through Phase 06 merged baselines plus the Phase 07 draft branch are recorded", () => {
    const docs = `${readText("README.md")}\n${readText("docs/DEVELOPMENT_STATUS.md")}`;
    assert.match(docs, /213f3581bd242523e34601cfefa5b5a74770ddee/);
    assert.match(docs, /PR #5[^\n]*merged|merged[^\n]*PR #5/i);
    assert.match(docs, /d644411b48e20cd9bb256d3d2c55a647efc2adfd/);
    assert.match(docs, /PR #6[^\n]*merged|merged[^\n]*PR #6/i);
    assert.match(docs, /4c606ae4f5e7a5e3d5fa431775c94469ecea1b67/);
    assert.match(docs, /PR #7[^\n]*merged|merged[^\n]*PR #7/i);
    assert.match(docs, /codex\/phase-07-visual-readability-arena-rebuild/);
    assert.match(docs, /pull\/8|PR #8/);
    assert.match(docs, /draft[^\n]*(?:unmerged|not merged)|(?:unmerged|not merged)[^\n]*draft/i);
  });

  criterion("phase02 manifest remains the sole Phase 02 through 07 owner", () => {
    const manifests = gitFiles.filter((file) => /^studio\/.*\.manifest\.json$/i.test(file));
    assert.deepEqual(manifests.sort(), ["studio/phase01.manifest.json", "studio/phase02.manifest.json"]);
    assert.equal(manifest.mode, "edit");
    assert.ok(Array.isArray(manifest.stationPlacements));
    assert.equal(manifest.stationPlacements.length, 8);
  });

  criterion("all managed sources remain repository-relative", () => {
    for (const script of manifest.scripts) {
      assert.equal(path.isAbsolute(script.sourceFile), false);
      assert.ok(!script.sourceFile.includes(".."));
      assert.ok(scriptsByPath.has(script.path));
    }
  });

  criterion("Phase 04 canonical modules are mapped into Studio", () => {
    for (const suffix of [
      ".Shared.World.StationDefinitions",
      ".Shared.World.DisplayNameSanitizer",
      ".Shared.World.ShipmentTypes",
      ".Services.ShipmentRecordService",
      ".Services.ShowcaseService",
      ".Services.ServerBestService",
      ".Services.StationDisplayService",
      ".Services.ArenaAnnouncementService",
      ".Controllers.StationContextController",
      ".Dev.Phase04TestSuite",
      ".Dev.RunPhase04Tests",
    ]) assert.ok(scriptSteps.some((step) => step.path.endsWith(suffix)), `Missing Studio script mapping ${suffix}`);
  });

  criterion("arena rails and spectator spawn are permanent", () => {
    assert.ok(instancesByPath.has(`${worldRoot}.ArenaRails`));
    assert.equal(instancesByPath.get(`${worldRoot}.SpectatorSpawn`)?.className, "Part");
  });

  criterion("permanent instance count stays explicit and auditable", () => {
    assert.equal(instanceSteps.length, 1355, `Phase 07 permanent authored path count drifted: ${instanceSteps.length}`);
  });

  console.log(
    `[Phase04MultiplayerArena] PASS criteria=${criterionCount} instances=${instanceSteps.length} scripts=${scriptSteps.length} stations=8 pathNodes=16 remotes=6 deterministic=true prior=true`,
  );
} catch (error) {
  console.error(`[Phase04MultiplayerArena] FAIL criterion=${criterionCount + 1} ${error instanceof Error ? error.message : String(error)}`);
  process.exitCode = 1;
} finally {
  if (temporaryRoot) fs.rmSync(temporaryRoot, { recursive: true, force: true });
}
