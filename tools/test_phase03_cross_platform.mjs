import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const toolsDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(toolsDirectory, "..");
const phase01TestPath = path.join(toolsDirectory, "test_studio_blueprint.mjs");
const phase02TestPath = path.join(toolsDirectory, "test_phase02_blueprint.mjs");
const generatorPath = path.join(toolsDirectory, "build_phase02_blueprint.mjs");
const manifestPath = path.join(repositoryRoot, "studio", "phase02.manifest.json");
const workflowPath = path.join(repositoryRoot, ".github", "workflows", "phase01-node-validation.yml");
const blueprintPath = path.join(repositoryRoot, ".codex-cache", "phase02-blueprint.json");
const commandBarPath = path.join(repositoryRoot, ".codex-cache", "phase02-command-bar.json");
const clientControllersDirectory = path.join(
  repositoryRoot,
  "src",
  "StarterPlayer",
  "StarterPlayerScripts",
  "ONE_MORE_ITEM_Client",
  "Controllers",
);
const responsiveLayoutPath = path.join(clientControllersDirectory, "ResponsiveLayout.luau");
const responsiveUiControllerPath = path.join(clientControllersDirectory, "ResponsiveUIController.luau");
const inputModeStorePath = path.join(clientControllersDirectory, "InputModeStore.luau");
const inputPromptControllerPath = path.join(clientControllersDirectory, "InputPromptController.luau");
const touchInputControllerPath = path.join(clientControllersDirectory, "TouchInputController.luau");
const gamepadInputControllerPath = path.join(clientControllersDirectory, "GamepadInputController.luau");
const inputControllerPath = path.join(clientControllersDirectory, "InputController.luau");
const serverBootstrapPath = path.join(
  repositoryRoot,
  "src",
  "ServerScriptService",
  "ONE_MORE_ITEM_Server",
  "ServerBootstrap.server.luau",
);

const uiScreen = "StarterGui.ONE_MORE_ITEM_Gameplay";
const uiRoot = `${uiScreen}.Root`;
const stationRoot = "Workspace.ONE_MORE_ITEM_WORLD.PlaytestArena.Stations.Station_01";
const expectedRemotes = [
  "ClientReadyRequest",
  "DecisionRequest",
  "PlaceItemRequest",
  "PlacementResponse",
  "RestartRequest",
  "RoundSnapshot",
];
const primaryButtons = [
  { path: `${uiRoot}.PlacementControls.RotateButton`, target: "RotateButton", parent: "PlacementControls" },
  { path: `${uiRoot}.PlacementControls.PlaceButton`, target: "PlaceButton", parent: "PlacementControls" },
  { path: `${uiRoot}.DecisionPanel.ShipButton`, target: "ShipButton", parent: "DecisionPanel" },
  { path: `${uiRoot}.DecisionPanel.OneMoreButton`, target: "OneMoreButton", parent: "DecisionPanel" },
  { path: `${uiRoot}.ResultsPanel.PackAgainButton`, target: "PackAgainButton", parent: "ResultsPanel" },
];
const rootTargets = [
  "CurrentItemCard",
  "ShipmentCard",
  "PlacementControls",
  "DecisionPanel",
  "ResultsPanel",
  "StatusBanner",
];
const expectedClientModules = [
  "InputModeStore",
  "ResponsiveLayout",
  "ResponsiveUIController",
  "TouchInputController",
  "GamepadInputController",
  "InputPromptController",
  "InputController",
];
const viewportMatrix = [
  { name: "desktop-1920x1080", width: 1920, height: 1080, expectedClass: "Wide", touchLayout: false },
  { name: "desktop-1366x768", width: 1366, height: 768, expectedClass: "Wide", touchLayout: false },
  { name: "desktop-2560x1440", width: 2560, height: 1440, expectedClass: "Wide", touchLayout: false },
  { name: "desktop-1100x700", width: 1100, height: 700, expectedClass: "Wide", touchLayout: false },
  { name: "phone-portrait-360x640", width: 360, height: 640, expectedClass: "Portrait", touchLayout: true },
  { name: "phone-portrait-390x844", width: 390, height: 844, expectedClass: "Portrait", touchLayout: true },
  { name: "phone-portrait-393x852", width: 393, height: 852, expectedClass: "Portrait", touchLayout: true },
  { name: "phone-portrait-430x932", width: 430, height: 932, expectedClass: "Portrait", touchLayout: true },
  { name: "phone-landscape-640x360", width: 640, height: 360, expectedClass: "CompactLandscape", touchLayout: true },
  { name: "phone-landscape-844x390", width: 844, height: 390, expectedClass: "CompactLandscape", touchLayout: true },
  { name: "phone-landscape-932x430", width: 932, height: 430, expectedClass: "CompactLandscape", touchLayout: true },
  { name: "tablet-portrait-768x1024", width: 768, height: 1024, expectedClass: "Portrait", touchLayout: true },
  { name: "tablet-landscape-1024x768", width: 1024, height: 768, expectedClass: "CompactLandscape", touchLayout: true },
];
const insetProfiles = [
  { name: "none", left: 0, top: 0, right: 0, bottom: 0 },
  { name: "top", left: 0, top: 24, right: 0, bottom: 0 },
  { name: "left-right-notch", left: 24, top: 0, right: 24, bottom: 0 },
  { name: "bottom-home", left: 0, top: 0, right: 0, bottom: 24 },
  { name: "combined", left: 20, top: 24, right: 20, bottom: 24 },
];

let criterionCount = 0;
let activeCriterion = "startup";

function criterion(name, callback) {
  activeCriterion = name;
  callback();
  criterionCount += 1;
}

function runNode(scriptPath, args = []) {
  return spawnSync(process.execPath, [scriptPath, ...args], {
    cwd: repositoryRoot,
    encoding: "utf8",
  });
}

function readText(filePath) {
  return fs.readFileSync(filePath, "utf8");
}

function listFiles(directory, excludedNames = new Set()) {
  const files = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    if (excludedNames.has(entry.name)) continue;
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...listFiles(entryPath, excludedNames));
    else if (entry.isFile()) files.push(entryPath);
  }
  return files;
}

function listLuauFiles(directory) {
  return listFiles(directory).filter((filePath) => filePath.endsWith(".luau"));
}

function propertyValue(entry, propertyName, fallback) {
  const property = entry?.properties?.[propertyName];
  if (property === undefined) return fallback;
  if (Object.hasOwn(property, "value")) return property.value;
  return property;
}

function assertUdim2(value, expected, label) {
  assert.equal(value?.type, "UDim2", `${label} must be a UDim2`);
  assert.deepEqual(
    [value.xScale, value.xOffset, value.yScale, value.yOffset],
    [expected.xScale, expected.xOffset, expected.yScale, expected.yOffset],
    `${label} has unexpected geometry`,
  );
}

function numberConstant(source, name) {
  const match = source.match(new RegExp(`local\\s+${name}\\s*=\\s*(-?[0-9]+(?:\\.[0-9]+)?)`));
  assert.ok(match, `ResponsiveLayout is missing ${name}`);
  const value = Number(match[1]);
  assert.ok(Number.isFinite(value), `${name} must be finite`);
  return value;
}

function parseProfile(source, profileName) {
  const marker = `local ${profileName}_TARGETS`;
  const markerIndex = source.indexOf(marker);
  assert.notEqual(markerIndex, -1, `ResponsiveLayout is missing ${profileName}_TARGETS`);
  const tableStart = source.indexOf("table.freeze({", markerIndex);
  const tableEnd = source.indexOf("}) :: TargetMap", tableStart);
  assert.ok(tableStart >= 0 && tableEnd > tableStart, `Unable to parse ${profileName}_TARGETS`);
  const body = source.slice(tableStart, tableEnd);
  const targets = {};
  const pattern = /(\w+)\s*=\s*geometry\(\s*["']([^"']+)["']\s*,\s*([^)]+)\)/g;
  for (const match of body.matchAll(pattern)) {
    const values = match[3].split(",").map((component) => Number(component.trim()));
    assert.equal(values.length, 6, `${profileName}.${match[1]} must provide six scale values`);
    assert.ok(values.every(Number.isFinite), `${profileName}.${match[1]} geometry must be numeric`);
    const [positionX, positionY, sizeX, sizeY, anchorX, anchorY] = values;
    targets[match[1]] = {
      parent: match[2],
      positionX,
      positionY,
      sizeX,
      sizeY,
      anchorX,
      anchorY,
    };
  }
  assert.deepEqual(
    Object.keys(targets).sort(),
    [...rootTargets, ...primaryButtons.map((button) => button.target)].sort(),
    `${profileName}_TARGETS must define every responsive target exactly once`,
  );
  return targets;
}

function createResponsiveMirror(source) {
  const portraitRatio = numberConstant(source, "PORTRAIT_RATIO");
  const compactRatio = numberConstant(source, "COMPACT_RATIO");
  const compactMaxHeight = numberConstant(source, "COMPACT_MAX_HEIGHT");
  const profiles = {
    Wide: parseProfile(source, "WIDE"),
    CompactLandscape: parseProfile(source, "COMPACT"),
    Portrait: parseProfile(source, "PORTRAIT"),
  };

  function validate(width, height, insets) {
    assert.ok(Number.isFinite(width) && Number.isFinite(height), "Viewport dimensions must be finite");
    assert.ok(width > 0 && height > 0, "Viewport dimensions must be positive");
    for (const key of ["left", "top", "right", "bottom"]) {
      assert.ok(Number.isFinite(insets[key]) && insets[key] >= 0, `Safe inset ${key} must be finite and non-negative`);
    }
    const usableWidth = width - insets.left - insets.right;
    const usableHeight = height - insets.top - insets.bottom;
    assert.ok(usableWidth > 0 && usableHeight > 0, "Safe insets must leave positive usable bounds");
    return { usableWidth, usableHeight };
  }

  function classify(width, height, insets) {
    const { usableWidth, usableHeight } = validate(width, height, insets);
    const ratio = usableWidth / usableHeight;
    if (ratio < portraitRatio) return "Portrait";
    if (ratio < compactRatio || usableHeight <= compactMaxHeight) return "CompactLandscape";
    return "Wide";
  }

  function resolve(width, height, insets) {
    const { usableWidth, usableHeight } = validate(width, height, insets);
    const layoutClass = classify(width, height, insets);
    const widthScale = usableWidth / width;
    const heightScale = usableHeight / height;
    const targets = {};
    for (const [name, sourceTarget] of Object.entries(profiles[layoutClass])) {
      const target = { ...sourceTarget };
      if (target.parent === "Root") {
        target.positionX = (insets.left / width) + (target.positionX * widthScale);
        target.positionY = (insets.top / height) + (target.positionY * heightScale);
        target.sizeX *= widthScale;
        target.sizeY *= heightScale;
      }
      targets[name] = target;
    }
    return {
      className: layoutClass,
      width,
      height,
      safeBounds: {
        left: insets.left,
        top: insets.top,
        right: width - insets.right,
        bottom: height - insets.bottom,
        width: usableWidth,
        height: usableHeight,
      },
      targets,
    };
  }

  function boundsFor(layout, targetName, cache = new Map(), visiting = new Set()) {
    if (cache.has(targetName)) return cache.get(targetName);
    assert.ok(!visiting.has(targetName), `Responsive target parent cycle at ${targetName}`);
    const target = layout.targets[targetName];
    assert.ok(target, `Missing responsive target ${targetName}`);
    visiting.add(targetName);
    const parentBounds = target.parent === "Root"
      ? { left: 0, top: 0, right: layout.width, bottom: layout.height, width: layout.width, height: layout.height }
      : boundsFor(layout, target.parent, cache, visiting);
    const width = parentBounds.width * target.sizeX;
    const height = parentBounds.height * target.sizeY;
    const anchorX = parentBounds.left + (parentBounds.width * target.positionX);
    const anchorY = parentBounds.top + (parentBounds.height * target.positionY);
    const bounds = {
      left: anchorX - (width * target.anchorX),
      top: anchorY - (height * target.anchorY),
      right: anchorX - (width * target.anchorX) + width,
      bottom: anchorY - (height * target.anchorY) + height,
      width,
      height,
    };
    visiting.delete(targetName);
    cache.set(targetName, bounds);
    return bounds;
  }

  return { portraitRatio, compactRatio, compactMaxHeight, profiles, classify, resolve, boundsFor };
}

function assertContained(inner, outer, label) {
  const tolerance = 1e-6;
  assert.ok(inner.left >= outer.left - tolerance, `${label} crosses the left safe boundary`);
  assert.ok(inner.top >= outer.top - tolerance, `${label} crosses the top safe boundary`);
  assert.ok(inner.right <= outer.right + tolerance, `${label} crosses the right safe boundary`);
  assert.ok(inner.bottom <= outer.bottom + tolerance, `${label} crosses the bottom safe boundary`);
}

function boundsOverlap(first, second) {
  const tolerance = 1e-6;
  return first.left < second.right - tolerance
    && first.right > second.left + tolerance
    && first.top < second.bottom - tolerance
    && first.bottom > second.top + tolerance;
}

function manifestGeometry(entry, parent) {
  const position = entry?.properties?.Position;
  const size = entry?.properties?.Size;
  const anchor = entry?.properties?.AnchorPoint ?? { type: "Vector2", x: 0, y: 0 };
  assert.equal(position?.type, "UDim2", `${entry?.path ?? "missing entry"} needs authored Position`);
  assert.equal(size?.type, "UDim2", `${entry?.path ?? "missing entry"} needs authored Size`);
  assert.equal(anchor?.type, "Vector2", `${entry?.path ?? "missing entry"} needs authored AnchorPoint`);
  assert.equal(position.xOffset, 0, `${entry.path}.Position must be scale-only`);
  assert.equal(position.yOffset, 0, `${entry.path}.Position must be scale-only`);
  assert.equal(size.xOffset, 0, `${entry.path}.Size must be scale-only`);
  assert.equal(size.yOffset, 0, `${entry.path}.Size must be scale-only`);
  return {
    parent,
    positionX: position.xScale,
    positionY: position.yScale,
    sizeX: size.xScale,
    sizeY: size.yScale,
    anchorX: anchor.x,
    anchorY: anchor.y,
  };
}

function actionBindings(source, relativePath) {
  const pattern = /ContextActionService\s*:\s*BindAction(?:AtPriority)?\s*\(/g;
  for (const match of source.matchAll(pattern)) {
    const callWindow = source.slice(match.index, match.index + 1400);
    const falseIndex = callWindow.search(/(?:^|\r?\n)\s*false\s*,\s*(?:\r?\n|$)/);
    const trueIndex = callWindow.search(/(?:^|\r?\n)\s*true\s*,\s*(?:\r?\n|$)/);
    assert.ok(falseIndex >= 0, `${relativePath} binding must explicitly set createTouchButton=false`);
    assert.ok(trueIndex < 0 || falseIndex < trueIndex, `${relativePath} requests an auto-generated touch button`);
  }
}

function repositoryTextFiles() {
  const excluded = new Set([".git", ".codex-cache", ".codex-studio", "node_modules"]);
  const textExtensions = new Set([".json", ".md", ".mjs", ".js", ".luau", ".yml", ".yaml", ".gitignore"]);
  return listFiles(repositoryRoot, excluded).filter((filePath) => {
    if (path.basename(filePath) === ".gitignore") return true;
    return textExtensions.has(path.extname(filePath).toLowerCase());
  });
}

try {
  let phase01Result;
  criterion("existing Phase 01 Node smoke passes", () => {
    phase01Result = runNode(phase01TestPath);
    assert.equal(phase01Result.status, 0, `Phase 01 smoke failed:\n${phase01Result.stderr || phase01Result.stdout}`);
    assert.match(phase01Result.stdout, /\[StudioSyncSmoke\] PASS checks=16 folders=7 scripts=10 deterministic=true/);
  });

  let phase02Result;
  criterion("existing Phase 02 Node smoke passes", () => {
    phase02Result = runNode(phase02TestPath);
    assert.equal(phase02Result.status, 0, `Phase 02 smoke failed:\n${phase02Result.stderr || phase02Result.stdout}`);
    assert.match(phase02Result.stdout, /\[Phase02StudioSyncSmoke\] PASS criteria=\d+ instances=\d+ scripts=\d+ remotes=6 deterministic=true phase01=true/);
  });

  const manifest = JSON.parse(readText(manifestPath));
  const entriesByPath = new Map(manifest.instances.map((entry) => [entry.path, entry]));
  const scriptsByPath = new Map(manifest.scripts.map((entry) => [entry.path, entry]));
  const allLuauFiles = listLuauFiles(path.join(repositoryRoot, "src"));
  const productionLuauFiles = allLuauFiles.filter((filePath) => !filePath.split(path.sep).includes("Dev"));

  criterion("Phase 03 focused client modules are canonical manifest scripts", () => {
    for (const moduleName of expectedClientModules) {
      const managedPath = `StarterPlayer.StarterPlayerScripts.ONE_MORE_ITEM_Client.Controllers.${moduleName}`;
      const entry = scriptsByPath.get(managedPath);
      assert.equal(entry?.className, "ModuleScript", `Missing canonical ModuleScript ${managedPath}`);
      const sourcePath = path.resolve(repositoryRoot, entry.sourceFile);
      assert.ok(sourcePath.startsWith(`${repositoryRoot}${path.sep}`), `${managedPath} source escapes the repository`);
      assert.ok(fs.existsSync(sourcePath), `${managedPath} source is missing`);
    }
  });

  criterion("ScreenGui device-safe-area properties are authored", () => {
    const screen = entriesByPath.get(uiScreen);
    assert.equal(screen?.className, "ScreenGui", "Gameplay ScreenGui must be permanently authored");
    assert.deepEqual(screen.properties.ScreenInsets, { type: "EnumItem", enumType: "ScreenInsets", name: "DeviceSafeInsets" });
    assert.deepEqual(screen.properties.SafeAreaCompatibility, { type: "EnumItem", enumType: "SafeAreaCompatibility", name: "None" });
    assert.equal(propertyValue(screen, "ClipToDeviceSafeArea"), true);
    assert.equal(propertyValue(screen, "IgnoreGuiInset"), true);
    assert.deepEqual(screen.properties.ZIndexBehavior, { type: "EnumItem", enumType: "ZIndexBehavior", name: "Sibling" });
  });

  criterion("TouchDragSurface is a transparent authored usable-region surface", () => {
    const surface = entriesByPath.get(`${uiRoot}.TouchDragSurface`);
    assert.equal(surface?.className, "Frame", "TouchDragSurface must be a permanent Frame");
    assert.equal(propertyValue(surface, "BackgroundTransparency"), 1, "TouchDragSurface must be invisible");
    assert.equal(propertyValue(surface, "Selectable"), false, "TouchDragSurface must not take gamepad focus");
    assert.equal(typeof propertyValue(surface, "Active"), "boolean", "TouchDragSurface must author Active explicitly");
    assertUdim2(surface.properties.Position, { xScale: 0.5, xOffset: 0, yScale: 0.5, yOffset: 0 }, "TouchDragSurface.Position");
    assertUdim2(surface.properties.Size, { xScale: 1, xOffset: 0, yScale: 1, yOffset: 0 }, "TouchDragSurface.Size");
    assert.deepEqual(surface.properties.AnchorPoint, { type: "Vector2", x: 0.5, y: 0.5 });
  });

  criterion("TouchDragSurface remains behind every primary control group", () => {
    const surface = entriesByPath.get(`${uiRoot}.TouchDragSurface`);
    const surfaceZIndex = propertyValue(surface, "ZIndex", 1);
    for (const { path: buttonPath, parent } of primaryButtons) {
      const button = entriesByPath.get(buttonPath);
      const panel = entriesByPath.get(`${uiRoot}.${parent}`);
      const controlLayer = Math.max(propertyValue(button, "ZIndex", 1), propertyValue(panel, "ZIndex", 1));
      assert.ok(surfaceZIndex < controlLayer, `TouchDragSurface must render behind ${buttonPath}`);
    }
  });

  criterion("primary actions author Selectable, FocusStroke, and minimum constraints", () => {
    for (const { path: buttonPath, target } of primaryButtons) {
      const button = entriesByPath.get(buttonPath);
      const focusStroke = entriesByPath.get(`${buttonPath}.FocusStroke`);
      const minimum = entriesByPath.get(`${buttonPath}.CompactMinimum`);
      assert.equal(button?.className, "TextButton", `${buttonPath} must remain an authored TextButton`);
      assert.equal(propertyValue(button, "Selectable"), true, `${buttonPath} must support gamepad selection`);
      assert.equal(focusStroke?.className, "UIStroke", `${buttonPath}.FocusStroke must be permanently authored`);
      assert.ok(propertyValue(focusStroke, "Thickness") >= 2.5, `${buttonPath}.FocusStroke is too thin`);
      assert.ok(
        propertyValue(focusStroke, "Enabled", true) === false || propertyValue(focusStroke, "Transparency", 0) >= 0.99,
        `${buttonPath}.FocusStroke must begin visually cleared`,
      );
      assert.equal(minimum?.className, "UISizeConstraint", `${buttonPath}.CompactMinimum must be authored`);
      assert.equal(minimum.properties.MinSize?.type, "Vector2", `${buttonPath}.CompactMinimum.MinSize must be Vector2`);
      assert.ok(minimum.properties.MinSize.x >= (target === "PackAgainButton" ? 120 : 72));
      assert.ok(minimum.properties.MinSize.y >= 44, `${buttonPath} minimum height is below Roblox's baseline touch target`);
    }
  });

  criterion("responsive camera anchors are permanently authored", () => {
    for (const anchorName of ["CameraAnchor", "CameraAnchorTouchLandscape", "CameraAnchorTouchPortrait"]) {
      const entry = entriesByPath.get(`${stationRoot}.${anchorName}`);
      assert.equal(entry?.className, "Part", `${anchorName} must be a permanent Part`);
      assert.equal(propertyValue(entry, "Anchored"), true, `${anchorName} must be anchored`);
      assert.equal(propertyValue(entry, "CanCollide"), false, `${anchorName} must not collide`);
      assert.equal(propertyValue(entry, "CanQuery"), false, `${anchorName} must not affect raycasts`);
      assert.equal(propertyValue(entry, "CanTouch"), false, `${anchorName} must not receive touches`);
      assert.equal(propertyValue(entry, "Transparency"), 1, `${anchorName} must remain invisible`);
      assert.equal(entry.properties.CFrame?.type, "CFrame", `${anchorName} requires an authored CFrame`);
    }
  });

  criterion("production runtime has no permanent UI or RemoteEvent builder", () => {
    const forbiddenConstructor = /Instance\.new\s*\(\s*["'](?:ScreenGui|Frame|TextButton|TextLabel|ViewportFrame|UIStroke|UISizeConstraint|RemoteEvent)["']\s*\)/;
    for (const sourcePath of productionLuauFiles) {
      const relativePath = path.relative(repositoryRoot, sourcePath).replaceAll("\\", "/");
      assert.doesNotMatch(readText(sourcePath), forbiddenConstructor, `Permanent authored instance constructed at runtime: ${relativePath}`);
    }
  });

  criterion("ContextActionService never requests auto-generated touch buttons", () => {
    let bindingCount = 0;
    for (const sourcePath of allLuauFiles) {
      const source = readText(sourcePath);
      const relativePath = path.relative(repositoryRoot, sourcePath).replaceAll("\\", "/");
      const matches = source.match(/ContextActionService\s*:\s*BindAction(?:AtPriority)?\s*\(/g) ?? [];
      bindingCount += matches.length;
      actionBindings(source, relativePath);
      assert.doesNotMatch(source, /ContextActionService\s*:\s*Set(?:Title|Image|Position)\s*\(/, `${relativePath} configures a generated touch button`);
    }
    assert.ok(bindingCount >= 5, "Expected character sinks and gamepad bindings to be audited");
  });

  criterion("selected authored buttons exclusively own Decision and Results gamepad confirmation", () => {
    const gamepadSource = readText(gamepadInputControllerPath);
    const inputSource = readText(inputControllerPath);
    assert.match(
      inputSource,
      /local\s+GuiService\s*=\s*game:GetService\s*\(\s*["']GuiService["']\s*\)/,
      "Selected-button routing must acquire GuiService explicitly",
    );
    assert.match(
      gamepadSource,
      /UsesSelectedButtonActivation[\s\S]*CONFIRM_SHIP[\s\S]*CONFIRM_ONE_MORE[\s\S]*RESTART/,
      "Decision and Results confirmations must identify the selected-button route",
    );
    assert.match(
      gamepadSource,
      /UsesSelectedButtonActivation\s*\(\s*action\s*\)[\s\S]*Enum\.ContextActionResult\.Pass/,
      "CAS must pass selected-button confirmation to native GUI activation",
    );
    assert.match(
      inputSource,
      /gamepadSelectable\s+and\s+GuiService\.SelectedObject\s*==\s*button/,
      "Only the selected authored gamepad button may accept native activation",
    );
    assert.match(
      gamepadSource,
      /GuiService\s*:\s*GetPropertyChangedSignal\s*\(\s*["']SelectedObject["']\s*\)/,
      "Gamepad observability must follow native selected-button changes",
    );
    assert.match(
      inputSource,
      /connect\s*\(\s*buttons\.Place\s*,\s*false[\s\S]*connect\s*\(\s*buttons\.Ship\s*,\s*true[\s\S]*connect\s*\(\s*buttons\.OneMore\s*,\s*true[\s\S]*connect\s*\(\s*buttons\.PackAgain\s*,\s*true/,
      "Placement must remain CAS-owned while Decision and Results use selected authored buttons",
    );
  });

  criterion("expected spectator assignment is informational rather than a game warning", () => {
    const serverBootstrapSource = readText(serverBootstrapPath);
    assert.match(
      serverBootstrapSource,
      /print\s*\(\s*string\.format\s*\(\s*["']\[ONE_MORE_ITEM\]\[Station\] user=%d is spectator reason=%s["']/,
      "Expected no-station assignment must remain visible as informational Output",
    );
    assert.doesNotMatch(
      serverBootstrapSource,
      /warn\s*\(\s*string\.format\s*\(\s*["']\[ONE_MORE_ITEM\]\[Station\]/,
      "Expected spectator assignment must not fail the zero-game-warning acceptance gate",
    );
  });

  criterion("Phase 03 contains no haptic implementation or setting", () => {
    for (const sourcePath of allLuauFiles) {
      const relativePath = path.relative(repositoryRoot, sourcePath).replaceAll("\\", "/");
      const source = readText(sourcePath);
      assert.doesNotMatch(source, /HapticService|SetMotor|GetMotor|HapticsSetting/i, `Haptics are deferred but found in ${relativePath}`);
    }
  });

  const inputModeSource = readText(inputModeStorePath);
  criterion("InputModeStore uses PreferredInput and exactly three mapped modes", () => {
    assert.match(inputModeSource, /UserInputService\.PreferredInput/);
    assert.match(inputModeSource, /GetPropertyChangedSignal\s*\(\s*["']PreferredInput["']\s*\)/);
    assert.match(inputModeSource, /Enum\.PreferredInput\.KeyboardAndMouse[\s\S]*["']KeyboardMouse["']/);
    assert.match(inputModeSource, /Enum\.PreferredInput\.Touch[\s\S]*["']Touch["']/);
    assert.match(inputModeSource, /Enum\.PreferredInput\.Gamepad[\s\S]*["']Gamepad["']/);
    assert.match(inputModeSource, /export type (?:InputMode|Mode)\s*=\s*["']KeyboardMouse["']\s*\|\s*["']Touch["']\s*\|\s*["']Gamepad["']/);
    assert.doesNotMatch(inputModeSource, /TouchEnabled|GamepadEnabled/, "Preferred mode must not be inferred from device capability flags");
    assert.match(inputModeSource, /if mode == self\._mode then\s*return\s*end/, "Identical PreferredInput changes must be ignored");
    assert.match(inputModeSource, /connection:Disconnect\s*\(\s*\)/, "PreferredInput connection needs destroy cleanup");
  });

  const promptSource = readText(inputPromptControllerPath);
  criterion("keyboard, touch, and gamepad prompt families are explicit", () => {
    for (const text of [
      "ROTATE  [R]",
      "PLACE  [SPACE]",
      "SHIP NOW  [Q]",
      "ONE MORE  [E]",
      "PACK AGAIN  [ENTER]",
      "MOUSE / WASD / ARROWS TO MOVE",
      "DRAG TO MOVE",
      "ROTATE  [X]",
      "PLACE  [A]",
      "PACK AGAIN  [A]",
      "LEFT STICK / D-PAD TO MOVE",
      "SELECT",
      "CONFIRM  [A]",
    ]) {
      assert.ok(promptSource.includes(text), `Missing control prompt text: ${text}`);
    }
    const touchBranch = promptSource.match(/if mode == ["']Touch["'] then([\s\S]*?)elseif mode == ["']Gamepad["'] then/)?.[1];
    assert.ok(touchBranch, "Unable to identify the Touch prompt branch");
    assert.doesNotMatch(touchBranch, /\[(?:R|SPACE|Q|E|ENTER|X|A)\]/, "Touch prompts must not display key names");
    assert.match(promptSource, /ShipmentValue/);
    assert.match(promptSource, /PossibleNextShipmentValue/);
    assert.match(promptSource, /NextDifficulty/);
  });

  const responsiveSource = readText(responsiveLayoutPath);
  const responsive = createResponsiveMirror(responsiveSource);
  criterion("ResponsiveLayout remains pure, deterministic, and scale-only", () => {
    assert.doesNotMatch(responsiveSource, /game:GetService|WaitForChild|FindFirstChild|Instance\.new/, "ResponsiveLayout must not access instances or services");
    assert.match(responsiveSource, /UDim2\.fromScale\s*\(/, "ResponsiveLayout targets must use scale-only geometry");
    assert.match(responsiveSource, /function ResponsiveLayout\.Classify/);
    assert.match(responsiveSource, /function ResponsiveLayout\.Resolve/);
    assert.match(responsiveSource, /function ResponsiveLayout\.BoundsForTarget/);
    assert.match(responsiveSource, /function ResponsiveLayout\.IsContained/);
    const first = responsive.resolve(393, 852, insetProfiles[4]);
    const second = responsive.resolve(393, 852, insetProfiles[4]);
    assert.deepEqual(second, first, "Identical responsive inputs must produce identical geometry");
  });

  criterion("the complete static viewport matrix receives the intended layout class", () => {
    for (const viewport of viewportMatrix) {
      for (const insets of insetProfiles) {
        assert.equal(
          responsive.classify(viewport.width, viewport.height, insets),
          viewport.expectedClass,
          `${viewport.name}/${insets.name} selected the wrong layout class`,
        );
      }
    }
    assert.throws(() => responsive.classify(0, 640, insetProfiles[0]), /positive/);
    assert.throws(() => responsive.classify(Number.NaN, 640, insetProfiles[0]), /finite/);
  });

  criterion("all responsive core panels stay inside every simulated safe rectangle", () => {
    for (const viewport of viewportMatrix) {
      for (const insets of insetProfiles) {
        const layout = responsive.resolve(viewport.width, viewport.height, insets);
        for (const targetName of rootTargets) {
          assertContained(
            responsive.boundsFor(layout, targetName),
            layout.safeBounds,
            `${viewport.name}/${insets.name}/${targetName}`,
          );
        }
      }
    }
  });

  criterion("responsive actions stay inside parents and top cards do not cover actions", () => {
    for (const viewport of viewportMatrix) {
      for (const insets of insetProfiles) {
        const layout = responsive.resolve(viewport.width, viewport.height, insets);
        for (const { target, parent } of primaryButtons) {
          assertContained(
            responsive.boundsFor(layout, target),
            responsive.boundsFor(layout, parent),
            `${viewport.name}/${insets.name}/${target}`,
          );
        }
        for (const topCard of ["CurrentItemCard", "ShipmentCard"]) {
          for (const actionPanel of ["PlacementControls", "DecisionPanel"]) {
            assert.equal(
              boundsOverlap(responsive.boundsFor(layout, topCard), responsive.boundsFor(layout, actionPanel)),
              false,
              `${viewport.name}/${insets.name}/${topCard} overlaps ${actionPanel}`,
            );
          }
        }
      }
    }
  });

  criterion("touch layouts preserve approximately 64-pixel primary actions", () => {
    for (const viewport of viewportMatrix.filter((entry) => entry.touchLayout)) {
      for (const insets of insetProfiles) {
        const layout = responsive.resolve(viewport.width, viewport.height, insets);
        for (const target of ["RotateButton", "PlaceButton"]) {
          const bounds = responsive.boundsFor(layout, target);
          assert.ok(bounds.width >= 70, `${viewport.name}/${insets.name}/${target} is narrower than approximately 72 pixels`);
          assert.ok(bounds.height >= 60, `${viewport.name}/${insets.name}/${target} is shorter than approximately 64 pixels`);
        }
        for (const target of ["ShipButton", "OneMoreButton", "PackAgainButton"]) {
          const bounds = responsive.boundsFor(layout, target);
          assert.ok(bounds.width >= 118, `${viewport.name}/${insets.name}/${target} is narrower than approximately 120 pixels`);
          assert.ok(bounds.height >= 60, `${viewport.name}/${insets.name}/${target} is shorter than approximately 64 pixels`);
        }
      }
    }
  });

  criterion("responsive constraints enforce exact compact touch minimums", () => {
    const responsiveUiSource = readText(responsiveUiControllerPath);
    assert.match(
      responsiveUiSource,
      /targetName == ["']RotateButton["'] or targetName == ["']PlaceButton["'][\s\S]*Vector2\.new\s*\(\s*72\s*,\s*64\s*\)/,
      "Rotate and Place must enforce a 72x64 compact minimum",
    );
    assert.match(
      responsiveUiSource,
      /else[\s\S]*Vector2\.new\s*\(\s*120\s*,\s*64\s*\)/,
      "Ship, One More, and Pack Again must enforce a 120x64 compact minimum",
    );
    assert.match(
      responsiveUiSource,
      /if layoutClass == ["']Wide["'] then[\s\S]*constraint\.MinSize = Vector2\.zero/,
      "Wide must clear compact constraints to preserve exact Phase 02 desktop geometry",
    );
  });

  criterion("Wide zero-inset geometry is exactly Phase 02-authored geometry", () => {
    for (const targetName of rootTargets) {
      assert.deepEqual(
        responsive.profiles.Wide[targetName],
        manifestGeometry(entriesByPath.get(`${uiRoot}.${targetName}`), "Root"),
        `${targetName} Wide geometry regressed from the authored Phase 02 desktop layout`,
      );
    }
    for (const { path: buttonPath, target, parent } of primaryButtons) {
      assert.deepEqual(
        responsive.profiles.Wide[target],
        manifestGeometry(entriesByPath.get(buttonPath), parent),
        `${target} Wide geometry regressed from the authored Phase 02 desktop layout`,
      );
    }
  });

  criterion("exactly the six existing gameplay RemoteEvents remain authored", () => {
    const remotes = manifest.instances.filter((entry) =>
      entry.className === "RemoteEvent"
      && entry.path.startsWith("ReplicatedStorage.ONE_MORE_ITEM.Net.")
    );
    assert.deepEqual(remotes.map((entry) => entry.path.split(".").at(-1)).sort(), [...expectedRemotes].sort());
    assert.ok(remotes.every((entry) => entry.path.startsWith("ReplicatedStorage.ONE_MORE_ITEM.Net.")));
    for (const sourcePath of productionLuauFiles) {
      assert.doesNotMatch(readText(sourcePath), /Instance\.new\s*\(\s*["']RemoteEvent["']\s*\)/);
    }
  });

  criterion("touch and gamepad movement controllers do not send network requests", () => {
    const touchSource = readText(touchInputControllerPath);
    const gamepadSource = readText(gamepadInputControllerPath);
    assert.doesNotMatch(touchSource, /FireServer|InvokeServer/, "Touch drag must only update local prediction");
    assert.doesNotMatch(gamepadSource, /FireServer|InvokeServer/, "Gamepad movement must only update local prediction");
    assert.doesNotMatch(touchSource, /Place\s*\(/, "Touch release must not place automatically");
    assert.match(touchSource, /TouchEnded/);
  });

  criterion("workflow runs the five dependency-free Node gates in order", () => {
    const workflow = readText(workflowPath);
    const commands = [...workflow.matchAll(/^\s*run:\s*(.+?)\s*$/gm)].map((match) => match[1]);
    assert.deepEqual(commands, [
      "node tools/test_studio_blueprint.mjs",
      "node tools/test_phase02_blueprint.mjs",
      "node tools/test_phase03_cross_platform.mjs",
      "node tools/test_phase04_multiplayer_arena.mjs",
      "node tools/test_phase05_persistent_progression.mjs",
    ]);
    assert.match(workflow, /pull_request:[\s\S]*branches:[\s\S]*- main/);
    assert.match(workflow, /push:[\s\S]*branches:[\s\S]*- main[\s\S]*- ['"]codex\/\*\*['"]/);
    assert.match(workflow, /permissions:\s*\r?\n\s*contents:\s*read/);
    assert.doesNotMatch(workflow, /\b(?:npm|npx|pnpm|yarn|bun)\b/, "Workflow must not install packages or use a package manager");
  });

  criterion("workflow uses the verified Node 24 action runtime plan", () => {
    const workflow = readText(workflowPath);
    assert.equal((workflow.match(/actions\/checkout@v7\b/g) ?? []).length, 1, "Workflow must use verified actions/checkout@v7 exactly once");
    assert.equal((workflow.match(/actions\/setup-node@v6\b/g) ?? []).length, 1, "Workflow must use verified actions/setup-node@v6 exactly once");
    assert.match(workflow, /node-version:\s*['"]?24['"]?\s*$/m);
    assert.match(workflow, /package-manager-cache:\s*false\s*$/m);
    assert.match(workflow, /name:\s*Phase 01(?:–|-)05 Node Validation/);
    assert.ok(!fs.existsSync(path.join(repositoryRoot, "package.json")), "Phase 03 Node validation must remain package-free");
    const ownSource = readText(fileURLToPath(import.meta.url));
    const imports = [...ownSource.matchAll(/^import[\s\S]*?from\s+["']([^"']+)["'];?$/gm)].map((match) => match[1]);
    assert.ok(imports.length >= 4 && imports.every((specifier) => specifier.startsWith("node:")), "Phase 03 test imports must be Node built-ins only");
  });

  let firstBlueprint;
  let firstCommandBar;
  criterion("Phase 03 blueprint generation remains byte deterministic", () => {
    const firstRun = runNode(generatorPath);
    assert.equal(firstRun.status, 0, `First Phase 03 generator run failed:\n${firstRun.stderr || firstRun.stdout}`);
    firstBlueprint = fs.readFileSync(blueprintPath);
    firstCommandBar = fs.readFileSync(commandBarPath);
    const secondRun = runNode(generatorPath);
    assert.equal(secondRun.status, 0, `Second Phase 03 generator run failed:\n${secondRun.stderr || secondRun.stdout}`);
    assert.deepEqual(fs.readFileSync(blueprintPath), firstBlueprint, "Blueprint differs between identical runs");
    assert.deepEqual(fs.readFileSync(commandBarPath), firstCommandBar, "Command Bar artifact differs between identical runs");
  });

  criterion("generated artifacts contain every Phase 03 authored path", () => {
    const blueprint = JSON.parse(firstBlueprint.toString("utf8"));
    const operationPaths = new Set(blueprint.steps.map((step) => step.path));
    for (const managedPath of [
      `${uiRoot}.TouchDragSurface`,
      ...primaryButtons.flatMap(({ path: buttonPath }) => [`${buttonPath}.CompactMinimum`, `${buttonPath}.FocusStroke`]),
      `${stationRoot}.CameraAnchorTouchLandscape`,
      `${stationRoot}.CameraAnchorTouchPortrait`,
      ...expectedClientModules.map((moduleName) => `StarterPlayer.StarterPlayerScripts.ONE_MORE_ITEM_Client.Controllers.${moduleName}`),
    ]) {
      assert.ok(operationPaths.has(managedPath), `Generated artifact is missing ${managedPath}`);
    }
  });

  criterion("generated and canonical paths contain no absolute machine path", () => {
    const artifacts = `${firstBlueprint.toString("utf8")}\n${firstCommandBar.toString("utf8")}`;
    assert.ok(!artifacts.includes(repositoryRoot), "Generated artifact leaks the repository's absolute path");
    assert.doesNotMatch(artifacts, /[A-Za-z]:[\\/](?:Users|home)[\\/]/i, "Generated artifact contains a user-machine path");
    for (const entry of manifest.scripts) {
      assert.equal(path.isAbsolute(entry.sourceFile), false, `${entry.path} uses an absolute source path`);
      assert.doesNotMatch(entry.sourceFile, /(^|[\\/])\.\.([\\/]|$)/, `${entry.path} source escapes the repository`);
      assert.ok(!entry.sourceFile.includes("\\"), `${entry.path} source path must be portable`);
    }
  });

  criterion("repository contains no recovery artifact, lock file, or credential material", () => {
    const excluded = new Set([".git", ".codex-cache", ".codex-studio", "node_modules"]);
    const repositoryFiles = listFiles(repositoryRoot, excluded);
    const forbiddenFileName = /(?:^|[._-])(?:recovery|autosave|backup)(?:[._-]|$)|\.(?:rbxl|rbxlx|bak|tmp)$/i;
    const forbiddenLocks = /^(?:package-lock\.json|yarn\.lock|pnpm-lock\.yaml|bun\.lockb?)$/i;
    for (const filePath of repositoryFiles) {
      const relativePath = path.relative(repositoryRoot, filePath).replaceAll("\\", "/");
      assert.doesNotMatch(path.basename(filePath), forbiddenFileName, `Recovery or temporary artifact must stay outside Git: ${relativePath}`);
      assert.doesNotMatch(path.basename(filePath), forbiddenLocks, `Dependency lock file is outside the dependency-free Phase 03 plan: ${relativePath}`);
    }
    const secretMarkers = [
      ["ROBLO", "SECURITY"].join(""),
      ["gh", "p_"].join(""),
      ["github", "_pat_"].join(""),
      ["-----BEGIN ", "PRIVATE KEY-----"].join(""),
      ["AK", "IA"].join(""),
    ];
    const assignmentPattern = new RegExp(`(?:${["pass", "word"].join("")}|${["access", "_token"].join("")}|${["api", "_key"].join("")})\\s*[=:]\\s*["'][^"']{8,}["']`, "i");
    for (const filePath of repositoryTextFiles()) {
      const source = readText(filePath);
      const relativePath = path.relative(repositoryRoot, filePath).replaceAll("\\", "/");
      assert.doesNotMatch(source, /[A-Za-z]:[\\/](?:Users|home)[\\/]/i, `Absolute user-machine path found in ${relativePath}`);
      for (const marker of secretMarkers) assert.ok(!source.includes(marker), `Credential marker found in ${relativePath}`);
      assert.doesNotMatch(source, assignmentPattern, `Credential-like assignment found in ${relativePath}`);
    }
  });

  criterion("phase02 manifest is the sole vertical-slice path owner", () => {
    const studioDirectory = path.join(repositoryRoot, "studio");
    const manifestFiles = fs.readdirSync(studioDirectory).filter((name) => name.endsWith(".manifest.json")).sort();
    assert.deepEqual(manifestFiles, ["phase01.manifest.json", "phase02.manifest.json"]);
    assert.ok(!fs.existsSync(path.join(studioDirectory, `${"phase03"}.manifest.json`)), "Do not create an overlapping Phase 03 manifest");
    const verticalPrefixes = [`${uiScreen}.`, "Workspace.ONE_MORE_ITEM_WORLD.PlaytestArena."];
    for (const manifestName of manifestFiles.filter((name) => name !== "phase02.manifest.json")) {
      const candidate = JSON.parse(readText(path.join(studioDirectory, manifestName)));
      const ownedPaths = [
        ...(candidate.folders ?? []).map((entry) => typeof entry === "string" ? entry : entry.path),
        ...(candidate.instances ?? []).map((entry) => entry.path),
        ...(candidate.scripts ?? []).map((entry) => entry.path),
      ];
      for (const ownedPath of ownedPaths) {
        assert.ok(!verticalPrefixes.some((prefix) => ownedPath === prefix.slice(0, -1) || ownedPath.startsWith(prefix)), `${manifestName} overlaps ${ownedPath}`);
      }
    }
    assert.match(readText(generatorPath), /defaultManifestPath\s*=\s*path\.join\(repositoryRoot, ["']studio["'], ["']phase02\.manifest\.json["']\)/);
  });

  console.log(
    `[Phase03LayoutMatrix] PASS viewports=${viewportMatrix.length} insetProfiles=${insetProfiles.length} cases=${viewportMatrix.length * insetProfiles.length} desktopCompatible=true safeContainment=true`,
  );
  console.log(
    `[Phase03CrossPlatformSmoke] PASS criteria=${criterionCount} viewports=${viewportMatrix.length} insetProfiles=${insetProfiles.length} layoutCases=${viewportMatrix.length * insetProfiles.length} remotes=${expectedRemotes.length} deterministic=true phase01=true phase02=true`,
  );
} catch (error) {
  console.error(
    `[Phase03CrossPlatformSmoke] FAIL criterion=${criterionCount + 1} name=${JSON.stringify(activeCriterion)} ${error instanceof Error ? error.message : String(error)}`,
  );
  process.exitCode = 1;
}
