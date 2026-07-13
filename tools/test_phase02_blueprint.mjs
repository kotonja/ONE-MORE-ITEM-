import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const toolsDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(toolsDirectory, "..");
const generatorPath = path.join(toolsDirectory, "build_phase02_blueprint.mjs");
const phase01TestPath = path.join(toolsDirectory, "test_studio_blueprint.mjs");
const manifestPath = path.join(repositoryRoot, "studio", "phase02.manifest.json");
const blueprintPath = path.join(repositoryRoot, ".codex-cache", "phase02-blueprint.json");
const commandBarPath = path.join(repositoryRoot, ".codex-cache", "phase02-command-bar.json");
const serviceRoots = new Set(["ReplicatedStorage", "ServerScriptService", "StarterPlayer", "StarterGui", "Workspace"]);
const supportedTypes = new Set(["boolean", "number", "string", "EnumItem", "Color3", "Vector2", "Vector3", "UDim", "UDim2", "CFrame"]);
const expectedRemotes = ["ClientReadyRequest", "DecisionRequest", "PlaceItemRequest", "PlacementResponse", "RestartRequest", "RoundSnapshot"];
const worldRoot = "Workspace.ONE_MORE_ITEM_WORLD.PlaytestArena";
const stationRoot = `${worldRoot}.Stations.Station_01`;
const uiScreen = "StarterGui.ONE_MORE_ITEM_Gameplay";
const uiRoot = "StarterGui.ONE_MORE_ITEM_Gameplay.Root";
const requiredViewports = [
  { width: 1920, height: 1080 },
  { width: 1366, height: 768 },
  { width: 2560, height: 1440 },
  { width: 1100, height: 700 },
];
const expectedWorldPaths = [
  `${worldRoot}.ArenaFloor`,
  `${worldRoot}.ArenaBackdrop`,
  `${worldRoot}.Stations`,
  stationRoot,
  `${stationRoot}.StationRoot`,
  `${stationRoot}.PlayerStand`,
  `${stationRoot}.CameraAnchor`,
  `${stationRoot}.CameraFocus`,
  `${stationRoot}.PresentationPoint`,
  `${stationRoot}.Crate`,
  `${stationRoot}.Crate.Base`,
  `${stationRoot}.Crate.GridOrigin`,
  `${stationRoot}.Crate.GridTiles`,
  `${stationRoot}.Crate.WallFront`,
  `${stationRoot}.Crate.WallBack`,
  `${stationRoot}.Crate.WallLeft`,
  `${stationRoot}.Crate.WallRight`,
  `${stationRoot}.Crate.Lid`,
  `${stationRoot}.Crate.CrateFocus`,
  `${stationRoot}.ControlConsole`,
  `${stationRoot}.ControlConsole.RotateButton`,
  `${stationRoot}.ControlConsole.PlaceButton`,
  `${stationRoot}.ControlConsole.ShipButton`,
  `${stationRoot}.ControlConsole.OneMoreButton`,
  `${stationRoot}.PlacedItems`,
  `${stationRoot}.RuntimePresentation`,
];
const expectedUiPaths = [
  `${uiRoot}.CurrentItemCard`,
  `${uiRoot}.CurrentItemCard.ItemViewport`,
  `${uiRoot}.CurrentItemCard.ItemName`,
  `${uiRoot}.CurrentItemCard.FitState`,
  `${uiRoot}.CurrentItemCard.PlacementTimer`,
  `${uiRoot}.ShipmentCard`,
  `${uiRoot}.ShipmentCard.UnshippedLabel`,
  `${uiRoot}.ShipmentCard.ShipmentValue`,
  `${uiRoot}.ShipmentCard.ItemCount`,
  `${uiRoot}.ShipmentCard.Multiplier`,
  `${uiRoot}.ShipmentCard.SessionBank`,
  `${uiRoot}.PlacementControls`,
  `${uiRoot}.PlacementControls.RotateButton`,
  `${uiRoot}.PlacementControls.PlaceButton`,
  `${uiRoot}.PlacementControls.ControlHint`,
  `${uiRoot}.DecisionPanel`,
  `${uiRoot}.DecisionPanel.NextItemViewport`,
  `${uiRoot}.DecisionPanel.NextItemName`,
  `${uiRoot}.DecisionPanel.NextDifficulty`,
  `${uiRoot}.DecisionPanel.DecisionTimer`,
  `${uiRoot}.DecisionPanel.GuaranteedValue`,
  `${uiRoot}.DecisionPanel.PossibleValue`,
  `${uiRoot}.DecisionPanel.ShipButton`,
  `${uiRoot}.DecisionPanel.OneMoreButton`,
  `${uiRoot}.StatusBanner`,
  `${uiRoot}.ResultsPanel`,
  `${uiRoot}.ResultsPanel.ResultTitle`,
  `${uiRoot}.ResultsPanel.ResultReason`,
  `${uiRoot}.ResultsPanel.ResultValue`,
  `${uiRoot}.ResultsPanel.SessionTotal`,
  `${uiRoot}.ResultsPanel.PackAgainButton`,
  `${uiRoot}.DevelopmentDebug`,
  `${uiRoot}.DevelopmentDebug.RoundState`,
  `${uiRoot}.DevelopmentDebug.RoundId`,
  `${uiRoot}.DevelopmentDebug.StateVersion`,
  `${uiRoot}.DevelopmentDebug.GridPosition`,
  `${uiRoot}.DevelopmentDebug.ServerResponse`,
];
let criterionCount = 0;

function criterion(_name, callback) {
  callback();
  criterionCount += 1;
}

function runNode(scriptPath, args = []) {
  return spawnSync(process.execPath, [scriptPath, ...args], { cwd: repositoryRoot, encoding: "utf8" });
}

function parentPathOf(managedPath) {
  const parts = managedPath.split(".");
  parts.pop();
  return parts.join(".");
}

function calculateGuiObjectBounds(properties, parentBounds, label) {
  const position = properties?.Position;
  const size = properties?.Size;
  const anchorPoint = properties?.AnchorPoint ?? { type: "Vector2", x: 0, y: 0 };
  assert.equal(position?.type, "UDim2", `${label} requires an authored UDim2 Position`);
  assert.equal(size?.type, "UDim2", `${label} requires an authored UDim2 Size`);
  assert.equal(anchorPoint?.type, "Vector2", `${label} requires an authored Vector2 AnchorPoint`);

  const parentWidth = parentBounds.right - parentBounds.left;
  const parentHeight = parentBounds.bottom - parentBounds.top;
  const width = parentWidth * size.xScale + size.xOffset;
  const height = parentHeight * size.yScale + size.yOffset;
  const anchorX = parentBounds.left + parentWidth * position.xScale + position.xOffset;
  const anchorY = parentBounds.top + parentHeight * position.yScale + position.yOffset;
  const left = anchorX - width * anchorPoint.x;
  const top = anchorY - height * anchorPoint.y;
  return { left, top, right: left + width, bottom: top + height, width, height };
}

function authoredGuiBounds(entriesByPath, managedPath, viewport, cache = new Map()) {
  if (cache.has(managedPath)) return cache.get(managedPath);
  const entry = entriesByPath.get(managedPath);
  assert.ok(entry, `Missing authored GuiObject: ${managedPath}`);
  const parentPath = parentPathOf(managedPath);
  const parentBounds = parentPath === uiScreen
    ? { left: 0, top: 0, right: viewport.width, bottom: viewport.height, width: viewport.width, height: viewport.height }
    : authoredGuiBounds(entriesByPath, parentPath, viewport, cache);
  const bounds = calculateGuiObjectBounds(entry.properties, parentBounds, managedPath);
  cache.set(managedPath, bounds);
  return bounds;
}

function assertContained(inner, outer, label) {
  const tolerance = 1e-6;
  assert.ok(inner.left >= outer.left - tolerance, `${label} crosses the left viewport boundary`);
  assert.ok(inner.top >= outer.top - tolerance, `${label} crosses the top viewport boundary`);
  assert.ok(inner.right <= outer.right + tolerance, `${label} crosses the right viewport boundary`);
  assert.ok(inner.bottom <= outer.bottom + tolerance, `${label} crosses the bottom viewport boundary`);
}

function boundsOverlap(first, second) {
  return first.left < second.right && first.right > second.left && first.top < second.bottom && first.bottom > second.top;
}

function formatBounds(bounds) {
  return `(${bounds.left.toFixed(2)},${bounds.top.toFixed(2)})-(${bounds.right.toFixed(2)},${bounds.bottom.toFixed(2)})`;
}

function allTypedValues(manifest) {
  const values = [];
  for (const entry of manifest.instances) {
    values.push(...Object.values(entry.properties ?? {}), ...Object.values(entry.attributes ?? {}));
  }
  return values;
}

function listLuauFiles(directory) {
  const files = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...listLuauFiles(entryPath));
    else if (entry.isFile() && entry.name.endsWith(".luau")) files.push(entryPath);
  }
  return files;
}

function assertBridgePropertyValue(value, label) {
  if (value === null || ["boolean", "number", "string"].includes(typeof value)) return;
  assert.equal(typeof value, "object", `${label} must be a primitive or bridge descriptor`);
  assert.ok(!Object.hasOwn(value, "type"), `${label} leaked a manifest typed wrapper`);
  assert.ok(Object.hasOwn(value, "__type"), `${label} must use a bridge-native __type descriptor`);
  assert.ok(new Set(["EnumItem", "Color3", "Vector2", "Vector3", "UDim", "UDim2", "CFrame"]).has(value.__type), `${label} has unsupported bridge descriptor ${String(value.__type)}`);
  if (value.__type === "Color3") assert.equal(value.mode, "rgb", `${label} must preserve fromRGB color semantics`);
  if (value.__type === "CFrame") {
    assert.ok(Array.isArray(value.components), `${label}.components must be an array`);
    assert.equal(value.components.length, 12, `${label}.components must include position and rotation matrix`);
    assert.ok(value.components.every((component) => typeof component === "number" && Number.isFinite(component)));
  }
}

function expectedSourceHash(source) {
  return `sha256:${createHash("sha256").update(source, "utf8").digest("hex")}`;
}

let temporaryDirectory;
try {
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));

  criterion("manifest parses", () => {
    assert.equal(manifest.mode, "edit", "Phase 02 authoring must be Edit-mode only");
    assert.ok(Array.isArray(manifest.instances), "Manifest instances array is required");
    assert.ok(Array.isArray(manifest.scripts), "Manifest scripts array is required");
  });

  criterion("sources exist", () => {
    for (const entry of manifest.scripts) {
      assert.ok(!path.isAbsolute(entry.sourceFile), `Source must be repository-relative: ${entry.sourceFile}`);
      const sourcePath = path.resolve(repositoryRoot, entry.sourceFile);
      assert.ok(fs.existsSync(sourcePath) && fs.statSync(sourcePath).isFile(), `Missing source: ${entry.sourceFile}`);
    }
  });

  criterion("managed paths are unique", () => {
    const paths = [...manifest.instances, ...manifest.scripts].map((entry) => entry.path);
    assert.equal(new Set(paths).size, paths.length, "Managed paths must be unique");
    assert.ok(paths.every((managedPath) => serviceRoots.has(managedPath.split(".")[0])), "Every path needs a supported service root");
  });

  criterion("parents are earlier or built in", () => {
    const guaranteed = new Set(serviceRoots);
    for (const entry of manifest.builtInParents) guaranteed.add(entry.path);
    assert.deepEqual(manifest.builtInParents, [{ path: "StarterPlayer.StarterPlayerScripts", className: "StarterPlayerScripts" }]);
    for (const entry of manifest.instances) {
      assert.ok(guaranteed.has(parentPathOf(entry.path)), `Parent is not declared earlier: ${entry.path}`);
      guaranteed.add(entry.path);
    }
    for (const entry of manifest.scripts) assert.ok(guaranteed.has(parentPathOf(entry.path)), `Script parent is unavailable: ${entry.path}`);
  });

  criterion("world is authored under Workspace", () => {
    const worldEntries = manifest.instances.filter((entry) => entry.path.includes("ONE_MORE_ITEM_WORLD"));
    assert.ok(worldEntries.length > 0, "Permanent world entries are required");
    assert.ok(worldEntries.every((entry) => entry.path.startsWith("Workspace.ONE_MORE_ITEM_WORLD")));
    const station = manifest.instances.find((entry) => entry.path === stationRoot);
    assert.equal(station.className, "Model", "Station_01 must be a Model for station assignment and client binding");
    assert.deepEqual(
      Object.fromEntries(Object.entries(station.attributes).map(([key, value]) => [key, value.value])),
      { Active: true, CellSize: 2, GridDepth: 5, GridHeight: 4, GridWidth: 5, StationId: "station_01" },
    );
  });

  criterion("UI is authored under StarterGui", () => {
    const uiEntries = manifest.instances.filter((entry) => entry.path.includes("ONE_MORE_ITEM_Gameplay"));
    assert.ok(uiEntries.length > 0, "Permanent UI entries are required");
    assert.ok(uiEntries.every((entry) => entry.path.startsWith("StarterGui.ONE_MORE_ITEM_Gameplay")));
    const debug = manifest.instances.find((entry) => entry.path === `${uiRoot}.DevelopmentDebug`);
    assert.equal(debug.properties.Visible.value, false, "DevelopmentDebug must start hidden");
    assert.equal(debug.attributes.StudioOnly.value, true, "DevelopmentDebug must be Studio-only");
  });

  const entriesByPath = new Map(manifest.instances.map((entry) => [entry.path, entry]));
  criterion("DecisionPanel stores its visible target and starts hidden", () => {
    const decisionPanel = entriesByPath.get(`${uiRoot}.DecisionPanel`);
    assert.ok(decisionPanel, "DecisionPanel must be permanently authored");
    assert.deepEqual(decisionPanel.properties.AnchorPoint, { type: "Vector2", x: 0.5, y: 1 });
    assert.deepEqual(decisionPanel.properties.Position, { type: "UDim2", xScale: 0.5, xOffset: 0, yScale: 0.96, yOffset: 0 });
    assert.equal(decisionPanel.properties.Visible?.type, "boolean");
    assert.equal(decisionPanel.properties.Visible?.value, false, "Hidden state must use Visible=false");
    assert.equal(decisionPanel.properties.Position.yOffset, 0, "The authored visible target cannot contain a hidden +260 offset");
  });

  criterion("core gameplay panels fit every required desktop viewport", () => {
    const corePanels = ["CurrentItemCard", "ShipmentCard", "PlacementControls", "DecisionPanel", "ResultsPanel"];
    for (const viewport of requiredViewports) {
      const cache = new Map();
      const viewportBounds = { left: 0, top: 0, right: viewport.width, bottom: viewport.height };
      for (const panelName of corePanels) {
        const panelBounds = authoredGuiBounds(entriesByPath, `${uiRoot}.${panelName}`, viewport, cache);
        assertContained(panelBounds, viewportBounds, `${panelName} at ${viewport.width}x${viewport.height}`);
      }

      const decisionBounds = authoredGuiBounds(entriesByPath, `${uiRoot}.DecisionPanel`, viewport, cache);
      const shipBounds = authoredGuiBounds(entriesByPath, `${uiRoot}.DecisionPanel.ShipButton`, viewport, cache);
      const oneMoreBounds = authoredGuiBounds(entriesByPath, `${uiRoot}.DecisionPanel.OneMoreButton`, viewport, cache);
      console.log(
        `[Phase02Layout] viewport=${viewport.width}x${viewport.height} decision=${formatBounds(decisionBounds)} ship=${formatBounds(shipBounds)} oneMore=${formatBounds(oneMoreBounds)}`,
      );
    }
  });

  criterion("decision buttons remain contained and usable", () => {
    for (const viewport of requiredViewports) {
      const cache = new Map();
      const decisionBounds = authoredGuiBounds(entriesByPath, `${uiRoot}.DecisionPanel`, viewport, cache);
      for (const buttonName of ["ShipButton", "OneMoreButton"]) {
        const buttonBounds = authoredGuiBounds(entriesByPath, `${uiRoot}.DecisionPanel.${buttonName}`, viewport, cache);
        assertContained(buttonBounds, decisionBounds, `${buttonName} at ${viewport.width}x${viewport.height}`);
        assert.ok(buttonBounds.width > 0 && buttonBounds.height > 0, `${buttonName} must have positive pixel dimensions`);
        if (viewport.width === 1100 && viewport.height === 700) {
          assert.ok(buttonBounds.width >= 120, `${buttonName} must remain wide enough to use in the narrow desktop window`);
          assert.ok(buttonBounds.height >= 44, `${buttonName} must remain tall enough to use in the narrow desktop window`);
        }
      }
    }
  });

  criterion("top status cards do not cover decision actions", () => {
    for (const viewport of requiredViewports) {
      const cache = new Map();
      const currentItemBounds = authoredGuiBounds(entriesByPath, `${uiRoot}.CurrentItemCard`, viewport, cache);
      const shipmentBounds = authoredGuiBounds(entriesByPath, `${uiRoot}.ShipmentCard`, viewport, cache);
      for (const buttonName of ["ShipButton", "OneMoreButton"]) {
        const buttonBounds = authoredGuiBounds(entriesByPath, `${uiRoot}.DecisionPanel.${buttonName}`, viewport, cache);
        assert.equal(boundsOverlap(currentItemBounds, buttonBounds), false, `CurrentItemCard covers ${buttonName} at ${viewport.width}x${viewport.height}`);
        assert.equal(boundsOverlap(shipmentBounds, buttonBounds), false, `ShipmentCard covers ${buttonName} at ${viewport.width}x${viewport.height}`);
      }
    }
  });

  criterion("zero-value placement timeouts remain failure results", () => {
    const roundUiSource = fs.readFileSync(
      path.resolve(repositoryRoot, "src/StarterPlayer/StarterPlayerScripts/ONE_MORE_ITEM_Client/Controllers/RoundUIController.luau"),
      "utf8",
    );
    assert.match(roundUiSource, /FAILURE_RESULT_REASONS[\s\S]*PLACEMENT_TIMEOUT\s*=\s*true/);
    assert.match(roundUiSource, /local function isFailureResult\(snapshot: Snapshot\): boolean/);
    assert.match(roundUiSource, /snapshot\.State == ["']Failing["'] or snapshot\.ResultLostValue > 0/);
    assert.match(roundUiSource, /local failedResult = isFailureResult\(snapshot\)/);
    assert.doesNotMatch(roundUiSource, /local failedResult = snapshot\.ResultLostValue > 0/);
  });

  criterion("terminal placement shipping counts the authoritative result value", () => {
    const roundUiSource = fs.readFileSync(
      path.resolve(repositoryRoot, "src/StarterPlayer/StarterPlayerScripts/ONE_MORE_ITEM_Client/Controllers/RoundUIController.luau"),
      "utf8",
    );
    assert.match(
      roundUiSource,
      /local successfulShipping = state == ["']Shipping["'] and hasStation and not failedResult and snapshot\.ResultValue > 0/,
    );
    assert.match(
      roundUiSource,
      /local shipmentDisplayTarget = if successfulShipping then snapshot\.ResultValue else snapshot\.ShipmentValue/,
    );
    assert.match(roundUiSource, /["']ShipmentValue["'],\s*shipmentDisplayTarget,\s*deciding or successfulShipping/);
  });

  criterion("client scripts use StarterPlayerScripts", () => {
    const clientScripts = manifest.scripts.filter((entry) => entry.path.startsWith("StarterPlayer."));
    assert.ok(clientScripts.length >= 10, "Expected the client bootstrap and focused controllers");
    assert.ok(clientScripts.every((entry) => entry.path.startsWith("StarterPlayer.StarterPlayerScripts.ONE_MORE_ITEM_Client.")));
    assert.equal(clientScripts.find((entry) => entry.path.endsWith(".ClientBootstrap")).className, "LocalScript");
  });

  criterion("six remotes are permanent", () => {
    const remoteEntries = manifest.instances.filter((entry) => entry.className === "RemoteEvent");
    assert.deepEqual(remoteEntries.map((entry) => entry.path.split(".").at(-1)).sort(), expectedRemotes);
    assert.ok(remoteEntries.every((entry) => entry.path.startsWith("ReplicatedStorage.ONE_MORE_ITEM.Net.")));
  });

  criterion("typed properties are supported", () => {
    const typedValues = allTypedValues(manifest);
    assert.ok(typedValues.length > 0, "Managed typed values are required");
    assert.ok(typedValues.every((value) => supportedTypes.has(value.type)), "Unsupported typed value found");
    assert.deepEqual(new Set(typedValues.map((value) => value.type)), supportedTypes, "Manifest must exercise every supported typed form");
  });

  criterion("unsupported classes fail", () => {
    temporaryDirectory = fs.mkdtempSync(path.join(os.tmpdir(), "one-more-item-phase02-"));
    const invalidManifest = structuredClone(manifest);
    invalidManifest.instances[0].className = "DataStoreService";
    const invalidManifestPath = path.join(temporaryDirectory, "invalid.manifest.json");
    fs.writeFileSync(invalidManifestPath, `${JSON.stringify(invalidManifest)}\n`, "utf8");
    const result = runNode(generatorPath, [invalidManifestPath, path.join(temporaryDirectory, "output")]);
    assert.notEqual(result.status, 0, "Unsupported class generation must fail");
    assert.match(result.stderr, /className is unsupported/, "Unsupported class failure must be explicit");
  });

  const firstGeneration = runNode(generatorPath);
  assert.equal(firstGeneration.status, 0, `Phase 02 generator failed:\n${firstGeneration.stderr || firstGeneration.stdout}`);
  const firstBlueprint = fs.readFileSync(blueprintPath);
  const firstCommandBar = fs.readFileSync(commandBarPath);
  const blueprint = JSON.parse(firstBlueprint.toString("utf8"));
  const commandBar = JSON.parse(firstCommandBar.toString("utf8"));
  const operations = commandBar.operations;
  const operationPaths = new Set(operations.map((operation) => operation.path));

  criterion("conflicts never destroy content", () => {
    assert.ok(operations.length > 0, "Generated operations are required");
    for (const operation of operations) {
      const synchronizationPrefix = operation.type === "writeScript" ? operation.command.split("local sourceOk")[0] : operation.command;
      assert.match(operation.command, /Edit-mode only/, `Missing Edit-mode guard: ${operation.path}`);
      assert.match(operation.command, /sync conflict/, `Missing visible conflict handling: ${operation.path}`);
      assert.doesNotMatch(synchronizationPrefix, /:Destroy\s*\(/, `Conflict path must not destroy content: ${operation.path}`);
      assert.match(operation.command, /FindFirstChild/, `Correct existing instance must be reused: ${operation.path}`);
      assert.match(operation.command, /if not instance then instance=Instance\.new/, `Missing instance creation must be explicit: ${operation.path}`);
    }
  });

  criterion("operation order is deterministic and parent first", () => {
    const indexes = new Map(operations.map((operation, index) => [operation.path, index]));
    for (const operation of operations) {
      const parentPath = parentPathOf(operation.path);
      if (indexes.has(parentPath)) assert.ok(indexes.get(parentPath) < indexes.get(operation.path), `Parent must precede child: ${operation.path}`);
    }
    assert.equal(blueprint.mode, "edit");
    assert.equal(commandBar.mode, "edit");
    const clientBootstrapOperation = operations.find((operation) => operation.path.endsWith(".ClientBootstrap"));
    assert.match(clientBootstrapOperation.command, /StarterPlayerScripts/);
    assert.match(clientBootstrapOperation.command, /expected StarterPlayerScripts/);

    for (const step of blueprint.steps.filter((entry) => entry.type === "ensureInstance")) {
      assert.equal(step.overwrite, true, `Managed properties must update on reapply: ${step.path}`);
      for (const [propertyName, value] of Object.entries(step.properties)) {
        assertBridgePropertyValue(value, `${step.path}.${propertyName}`);
      }
      for (const [attributeName, value] of Object.entries(step.attributes)) {
        assert.ok(["boolean", "number", "string"].includes(typeof value), `${step.path} attribute ${attributeName} must be a raw SetAttribute-compatible primitive`);
      }
    }

    const arenaFloorStep = blueprint.steps.find((step) => step.path === `${worldRoot}.ArenaFloor`);
    assert.equal(arenaFloorStep.properties.Anchored, true);
    assert.deepEqual(arenaFloorStep.properties.Material, { __type: "EnumItem", enumType: "Material", name: "Concrete" });
    assert.deepEqual(arenaFloorStep.properties.Color, { __type: "Color3", mode: "rgb", r: 22, g: 33, b: 44 });
    assert.deepEqual(arenaFloorStep.properties.CFrame, { __type: "CFrame", components: [0, -0.5, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1] });
    const rootFrameStep = blueprint.steps.find((step) => step.path === uiRoot);
    assert.equal(rootFrameStep.properties.Position.__type, "UDim2");
    assert.equal(rootFrameStep.properties.AnchorPoint.__type, "Vector2");
    const cornerStep = blueprint.steps.find((step) => step.path === `${uiRoot}.CurrentItemCard.Corner`);
    assert.deepEqual(cornerStep.properties.CornerRadius, { __type: "UDim", scale: 0, offset: 12 });
    const stationStep = blueprint.steps.find((step) => step.path === stationRoot);
    assert.deepEqual(stationStep.attributes, { Active: true, CellSize: 2, GridDepth: 5, GridHeight: 4, GridWidth: 5, StationId: "station_01" });

    for (const step of blueprint.steps.filter((entry) => entry.type === "writeScript")) {
      assert.equal(step.overwrite, true, `Script reapply must be explicit: ${step.path}`);
      assert.equal(step.expectedSourceHash, expectedSourceHash(step.source), `Script overwrite hash must protect divergence: ${step.path}`);
    }
  });

  criterion("second generation is byte identical", () => {
    const secondGeneration = runNode(generatorPath);
    assert.equal(secondGeneration.status, 0, `Second generator run failed:\n${secondGeneration.stderr || secondGeneration.stdout}`);
    assert.deepEqual(fs.readFileSync(blueprintPath), firstBlueprint, "Blueprint must be byte-identical on repeat generation");
    assert.deepEqual(fs.readFileSync(commandBarPath), firstCommandBar, "Command Bar artifact must be byte-identical on repeat generation");
  });

  criterion("artifacts contain no machine paths or private data", () => {
    const output = `${firstBlueprint.toString("utf8")}\n${firstCommandBar.toString("utf8")}\n${firstGeneration.stdout}`;
    assert.ok(!output.includes(repositoryRoot), "Generated output contains repository absolute path");
    assert.doesNotMatch(output, /[A-Za-z]:[\\/](?:Users|home)[\\/]/i, "Generated output contains a user path");
    assert.doesNotMatch(output, /(?:token|password|cookie|authorization)\s*[=:]/i, "Generated output resembles private credentials");
  });

  criterion("required world hierarchy exists", () => {
    for (const requiredPath of expectedWorldPaths) assert.ok(operationPaths.has(requiredPath), `Missing world operation: ${requiredPath}`);
    const tiles = operations.filter((operation) => operation.path.startsWith(`${stationRoot}.Crate.GridTiles.Cell_`));
    assert.equal(tiles.length, 25, "The authored crate needs all 25 grid tiles");
    for (let x = 0; x < 5; x += 1) {
      for (let z = 0; z < 5; z += 1) assert.ok(operationPaths.has(`${stationRoot}.Crate.GridTiles.Cell_${x}_${z}`));
    }
    const gridOrigin = manifest.instances.find((entry) => entry.path === `${stationRoot}.Crate.GridOrigin`);
    assert.deepEqual(gridOrigin.properties.CFrame.position, [-4, 4, -4], "GridOrigin must represent logical cell 0,0,0");
    assert.ok(operationPaths.has("ReplicatedStorage.ONE_MORE_ITEM.Assets.Development.CellBlockTemplate"));
  });

  criterion("required UI hierarchy exists", () => {
    for (const requiredPath of expectedUiPaths) assert.ok(operationPaths.has(requiredPath), `Missing UI operation: ${requiredPath}`);
    assert.ok(operations.some((operation) => operation.className === "UICorner"), "Authored HUD should include rounded corners");
    assert.ok(operations.some((operation) => operation.className === "UIStroke"), "Authored HUD should include restrained strokes");
  });

  criterion("runtime architecture has no permanent builders", () => {
    const forbiddenGuiConstructor = /Instance\.new\s*\(\s*["'](?:ScreenGui|Frame|TextLabel|TextButton|ViewportFrame|RemoteEvent)["']\s*\)/;
    const permanentName = /ONE_MORE_ITEM_WORLD|ONE_MORE_ITEM_Gameplay/;
    for (const sourcePath of listLuauFiles(path.join(repositoryRoot, "src"))) {
      const relativeSourcePath = path.relative(repositoryRoot, sourcePath).replaceAll("\\", "/");
      const source = fs.readFileSync(sourcePath, "utf8");
      assert.doesNotMatch(source, forbiddenGuiConstructor, `Runtime must not construct permanent UI/remotes: ${relativeSourcePath}`);
      assert.ok(!(permanentName.test(source) && /Instance\.new\s*\(/.test(source)), `Runtime source mixes a permanent root with construction: ${relativeSourcePath}`);
    }
    const serverBootstrap = fs.readFileSync(path.resolve(repositoryRoot, "src/ServerScriptService/ONE_MORE_ITEM_Server/ServerBootstrap.server.luau"), "utf8");
    const clientBootstrap = fs.readFileSync(path.resolve(repositoryRoot, "src/StarterPlayer/StarterPlayerScripts/ONE_MORE_ITEM_Client/ClientBootstrap.luau"), "utf8");
    assert.doesNotMatch(serverBootstrap, /Instance\.new\s*\(/, "Server bootstrap must bind authored instances, not build the map");
    assert.doesNotMatch(clientBootstrap, /Instance\.new\s*\(/, "Client bootstrap must bind authored instances, not build the HUD");
    assert.match(
      clientBootstrap,
      /local function waitForAuthoredChild\s*\([\s\S]*parent:FindFirstChild\(name\)[\s\S]*parent\.ChildAdded:Wait\(\)[\s\S]*end/,
      "Client bootstrap must wait event-by-event without a deadline for authored descendants",
    );
    assert.match(
      clientBootstrap,
      /waitForAuthoredChild\s*\(\s*playerGui\s*,\s*["']ONE_MORE_ITEM_Gameplay["']\s*\)/,
      "Client bootstrap must use the warning-free authored-child wait for the permanent ScreenGui",
    );
    assert.doesNotMatch(
      clientBootstrap,
      /playerGui:WaitForChild\s*\(\s*["']ONE_MORE_ITEM_Gameplay["']/,
      "Client bootstrap must not use warning-producing or finite ScreenGui waits",
    );
    for (const clientSourcePath of listLuauFiles(path.resolve(repositoryRoot, "src/StarterPlayer/StarterPlayerScripts/ONE_MORE_ITEM_Client"))) {
      const clientSource = fs.readFileSync(clientSourcePath, "utf8");
      assert.doesNotMatch(
        clientSource,
        /local child = parent:FindFirstChild\(name\)/,
        `Required authored descendants must tolerate multiplayer replication delay: ${path.relative(repositoryRoot, clientSourcePath)}`,
      );
    }
  });

  let phase01Result;
  criterion("Phase 01 smoke remains green", () => {
    phase01Result = runNode(phase01TestPath);
    assert.equal(phase01Result.status, 0, `Phase 01 smoke failed:\n${phase01Result.stderr || phase01Result.stdout}`);
    assert.match(phase01Result.stdout, /\[StudioSyncSmoke\] PASS checks=16 folders=7 scripts=10 deterministic=true/);
  });

  const instanceCount = operations.filter((operation) => operation.type === "ensureInstance").length;
  const scriptCount = operations.filter((operation) => operation.type === "writeScript").length;
  console.log(
    `[Phase02StudioSyncSmoke] PASS criteria=${criterionCount} instances=${instanceCount} scripts=${scriptCount} remotes=${expectedRemotes.length} deterministic=true phase01=true`,
  );
} catch (error) {
  console.error(`[Phase02StudioSyncSmoke] FAIL criterion=${criterionCount + 1} ${error instanceof Error ? error.message : String(error)}`);
  process.exitCode = 1;
} finally {
  if (temporaryDirectory) fs.rmSync(temporaryDirectory, { recursive: true, force: true });
}
