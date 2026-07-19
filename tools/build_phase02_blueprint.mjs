import fs from "node:fs";
import path from "node:path";
import { createHash } from "node:crypto";
import { fileURLToPath } from "node:url";

const toolsDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(toolsDirectory, "..");
const realRepositoryRoot = fs.realpathSync(repositoryRoot);
const defaultManifestPath = path.join(repositoryRoot, "studio", "phase02.manifest.json");
const defaultOutputDirectory = path.join(repositoryRoot, ".codex-cache");

const supportedServices = new Map([
  ["Lighting", "Lighting"],
  ["ReplicatedFirst", "ReplicatedFirst"],
  ["ReplicatedStorage", "ReplicatedStorage"],
  ["ServerScriptService", "ServerScriptService"],
  ["StarterPlayer", "StarterPlayer"],
  ["StarterGui", "StarterGui"],
  ["Workspace", "Workspace"],
]);
const supportedClasses = new Set([
  "BillboardGui",
  "BloomEffect",
  "ColorCorrectionEffect",
  "Folder",
  "Frame",
  "LocalScript",
  "Model",
  "ModuleScript",
  "Part",
  "PointLight",
  "RemoteEvent",
  "ScreenGui",
  "Script",
  "TextButton",
  "TextLabel",
  "SurfaceGui",
  "UICorner",
  "UIPadding",
  "UISizeConstraint",
  "UIStroke",
  "ViewportFrame",
]);
const supportedScriptClasses = new Set(["ModuleScript", "Script", "LocalScript"]);
const supportedValueTypes = new Set([
  "boolean",
  "number",
  "string",
  "EnumItem",
  "Color3",
  "Vector2",
  "Vector3",
  "UDim",
  "UDim2",
  "CFrame",
]);
const builtInParents = new Map([["StarterPlayer.StarterPlayerScripts", "StarterPlayerScripts"]]);
const stationTemplateRoot = "Workspace.ONE_MORE_ITEM_WORLD.PlaytestArena.Stations.Station_01";
const expectedStationPlacements = [
  { direction: "North", angleDegrees: -90, yawDegrees: 180 },
  { direction: "NE", angleDegrees: -45, yawDegrees: 135 },
  { direction: "East", angleDegrees: 0, yawDegrees: 90 },
  { direction: "SE", angleDegrees: 45, yawDegrees: 45 },
  { direction: "South", angleDegrees: 90, yawDegrees: 0 },
  { direction: "SW", angleDegrees: 135, yawDegrees: -45 },
  { direction: "West", angleDegrees: 180, yawDegrees: -90 },
  { direction: "NW", angleDegrees: -135, yawDegrees: -135 },
];

function fail(message) {
  throw new Error(`[Phase02StudioSync] ${message}`);
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function assertFiniteNumber(value, label) {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    fail(`${label} must be a finite number`);
  }
}

function assertKeys(value, allowedKeys, label) {
  for (const key of Object.keys(value)) {
    if (!allowedKeys.has(key)) {
      fail(`${label} contains unsupported field ${key}`);
    }
  }
}

function validateTypedValue(value, label) {
  if (!isObject(value) || !supportedValueTypes.has(value.type)) {
    fail(`${label} must use a supported typed value (${[...supportedValueTypes].join(", ")})`);
  }

  switch (value.type) {
    case "boolean":
      assertKeys(value, new Set(["type", "value"]), label);
      if (typeof value.value !== "boolean") fail(`${label}.value must be boolean`);
      break;
    case "number":
      assertKeys(value, new Set(["type", "value"]), label);
      assertFiniteNumber(value.value, `${label}.value`);
      break;
    case "string":
      assertKeys(value, new Set(["type", "value"]), label);
      if (typeof value.value !== "string") fail(`${label}.value must be string`);
      break;
    case "EnumItem":
      assertKeys(value, new Set(["type", "enumType", "name"]), label);
      if (!/^[A-Za-z][A-Za-z0-9_]*$/.test(value.enumType ?? "")) fail(`${label}.enumType is invalid`);
      if (!/^[A-Za-z][A-Za-z0-9_]*$/.test(value.name ?? "")) fail(`${label}.name is invalid`);
      break;
    case "Color3":
      assertKeys(value, new Set(["type", "r", "g", "b"]), label);
      for (const component of ["r", "g", "b"]) {
        assertFiniteNumber(value[component], `${label}.${component}`);
        if (!Number.isInteger(value[component]) || value[component] < 0 || value[component] > 255) {
          fail(`${label}.${component} must be an integer from 0 through 255`);
        }
      }
      break;
    case "Vector2":
    case "Vector3": {
      const components = value.type === "Vector2" ? ["x", "y"] : ["x", "y", "z"];
      assertKeys(value, new Set(["type", ...components]), label);
      for (const component of components) assertFiniteNumber(value[component], `${label}.${component}`);
      break;
    }
    case "UDim":
      assertKeys(value, new Set(["type", "scale", "offset"]), label);
      assertFiniteNumber(value.scale, `${label}.scale`);
      assertFiniteNumber(value.offset, `${label}.offset`);
      break;
    case "UDim2":
      assertKeys(value, new Set(["type", "xScale", "xOffset", "yScale", "yOffset"]), label);
      for (const component of ["xScale", "xOffset", "yScale", "yOffset"]) {
        assertFiniteNumber(value[component], `${label}.${component}`);
      }
      break;
    case "CFrame":
      if (Object.hasOwn(value, "components")) {
        assertKeys(value, new Set(["type", "components"]), label);
        if (!Array.isArray(value.components) || value.components.length !== 12) {
          fail(`${label}.components must contain exactly 12 numbers`);
        }
        value.components.forEach((component, index) => assertFiniteNumber(component, `${label}.components[${index}]`));
      } else {
        assertKeys(value, new Set(["type", "position", "rotationDegrees"]), label);
        for (const [field, expectedLength] of [["position", 3], ["rotationDegrees", 3]]) {
          if (!Array.isArray(value[field]) || value[field].length !== expectedLength) {
            fail(`${label}.${field} must contain exactly ${expectedLength} numbers`);
          }
          value[field].forEach((component, index) => assertFiniteNumber(component, `${label}.${field}[${index}]`));
        }
      }
      break;
    default:
      fail(`${label} has unsupported type ${String(value.type)}`);
  }
}

function typedValueToLuau(value) {
  switch (value.type) {
    case "boolean":
    case "number":
    case "string":
      return JSON.stringify(value.value);
    case "EnumItem":
      return `Enum.${value.enumType}.${value.name}`;
    case "Color3":
      return `Color3.fromRGB(${value.r},${value.g},${value.b})`;
    case "Vector2":
      return `Vector2.new(${value.x},${value.y})`;
    case "Vector3":
      return `Vector3.new(${value.x},${value.y},${value.z})`;
    case "UDim":
      return `UDim.new(${value.scale},${value.offset})`;
    case "UDim2":
      return `UDim2.new(${value.xScale},${value.xOffset},${value.yScale},${value.yOffset})`;
    case "CFrame": {
      if (Array.isArray(value.components)) return `CFrame.new(${value.components.join(",")})`;
      const [x, y, z] = value.position;
      const [rx, ry, rz] = value.rotationDegrees;
      return `CFrame.new(${x},${y},${z})*CFrame.Angles(math.rad(${rx}),math.rad(${ry}),math.rad(${rz}))`;
    }
    default:
      fail(`Cannot serialize unsupported typed value ${String(value.type)}`);
  }
}

function cleanRotationComponent(value) {
  if (Math.abs(value) < 1e-12) return 0;
  if (Math.abs(value - 1) < 1e-12) return 1;
  if (Math.abs(value + 1) < 1e-12) return -1;
  return Number(value.toFixed(12));
}

function cframeComponents(value) {
  if (Array.isArray(value.components)) return value.components.map(cleanRotationComponent);
  const [x, y, z] = value.position;
  const [rxDegrees, ryDegrees, rzDegrees] = value.rotationDegrees;
  const rx = (rxDegrees * Math.PI) / 180;
  const ry = (ryDegrees * Math.PI) / 180;
  const rz = (rzDegrees * Math.PI) / 180;
  const cx = Math.cos(rx);
  const sx = Math.sin(rx);
  const cy = Math.cos(ry);
  const sy = Math.sin(ry);
  const cz = Math.cos(rz);
  const sz = Math.sin(rz);
  return [
    x,
    y,
    z,
    cy * cz,
    -cy * sz,
    sy,
    (cx * sz) + (sx * sy * cz),
    (cx * cz) - (sx * sy * sz),
    -sx * cy,
    (sx * sz) - (cx * sy * cz),
    (sx * cz) + (cx * sy * sz),
    cx * cy,
  ].map(cleanRotationComponent);
}

function multiplyCFrameComponents(left, right) {
  const result = new Array(12);
  for (let row = 0; row < 3; row += 1) {
    for (let column = 0; column < 3; column += 1) {
      let component = 0;
      for (let inner = 0; inner < 3; inner += 1) {
        component += left[3 + (row * 3) + inner] * right[3 + (inner * 3) + column];
      }
      result[3 + (row * 3) + column] = cleanRotationComponent(component);
    }
  }
  for (let row = 0; row < 3; row += 1) {
    let component = left[row];
    for (let inner = 0; inner < 3; inner += 1) {
      component += left[3 + (row * 3) + inner] * right[inner];
    }
    result[row] = cleanRotationComponent(component);
  }
  return result;
}

function placementCFrameComponents(placement) {
  const angleRadians = (placement.angleDegrees * Math.PI) / 180;
  const position = [
    cleanRotationComponent(placement.radius * Math.cos(angleRadians)),
    0,
    cleanRotationComponent(placement.radius * Math.sin(angleRadians)),
  ];
  return cframeComponents({ type: "CFrame", position, rotationDegrees: [0, placement.yawDegrees, 0] });
}

function transformCFrameValue(value, placement) {
  return {
    type: "CFrame",
    components: multiplyCFrameComponents(placementCFrameComponents(placement), cframeComponents(value)),
  };
}

function typedValueToBridge(value) {
  switch (value.type) {
    case "boolean":
    case "number":
    case "string":
      return value.value;
    case "EnumItem":
      return { __type: "EnumItem", enumType: value.enumType, name: value.name };
    case "Color3":
      return { __type: "Color3", mode: "rgb", r: value.r, g: value.g, b: value.b };
    case "Vector2":
      return { __type: "Vector2", x: value.x, y: value.y };
    case "Vector3":
      return { __type: "Vector3", x: value.x, y: value.y, z: value.z };
    case "UDim":
      return { __type: "UDim", scale: value.scale, offset: value.offset };
    case "UDim2":
      return {
        __type: "UDim2",
        xScale: value.xScale,
        xOffset: value.xOffset,
        yScale: value.yScale,
        yOffset: value.yOffset,
      };
    case "CFrame":
      return { __type: "CFrame", components: cframeComponents(value) };
    default:
      fail(`Cannot encode unsupported bridge value ${String(value.type)}`);
  }
}

function valueMapToBridge(values) {
  return Object.fromEntries(Object.entries(values).map(([name, value]) => [name, typedValueToBridge(value)]));
}

function sourceHash(source) {
  return `sha256:${createHash("sha256").update(source, "utf8").digest("hex")}`;
}

function parseManagedPath(value, label) {
  if (typeof value !== "string" || value.length === 0) fail(`${label} must be a non-empty string`);
  const parts = value.split(".");
  if (parts.some((part) => part.length === 0)) fail(`${label} contains an empty path segment: ${value}`);
  if (!supportedServices.has(parts[0])) {
    fail(`${label} must begin with a supported Roblox service (${[...supportedServices.keys()].join(", ")}): ${value}`);
  }
  if (parts.length < 2) fail(`${label} must name an instance below a service: ${value}`);
  return parts;
}

function parentPathOf(managedPath) {
  const parts = managedPath.split(".");
  parts.pop();
  return parts.join(".");
}

function compareManagedEntries(left, right) {
  const depthDifference = left.path.split(".").length - right.path.split(".").length;
  if (depthDifference !== 0) return depthDifference;
  return left.path < right.path ? -1 : left.path > right.path ? 1 : 0;
}

function validatePropertyMap(propertyMap, label, attributes = false) {
  if (propertyMap === undefined) return {};
  if (!isObject(propertyMap)) fail(`${label} must be an object`);
  const normalized = {};
  for (const key of Object.keys(propertyMap).sort()) {
    if (!/^[A-Za-z][A-Za-z0-9_]*$/.test(key)) fail(`${label} contains invalid Roblox member name ${key}`);
    validateTypedValue(propertyMap[key], `${label}.${key}`);
    if (attributes && !new Set(["boolean", "number", "string"]).has(propertyMap[key].type)) {
      fail(`${label}.${key} uses ${propertyMap[key].type}; Phase 02 attributes must be boolean, number, or string`);
    }
    normalized[key] = propertyMap[key];
  }
  return normalized;
}

function validateBuiltInParents(entries) {
  if (!Array.isArray(entries)) fail("Manifest builtInParents must be an array");
  const declared = new Map();
  for (const [index, entry] of entries.entries()) {
    if (!isObject(entry)) fail(`builtInParents[${index}] must be an object`);
    assertKeys(entry, new Set(["path", "className"]), `builtInParents[${index}]`);
    const expectedClass = builtInParents.get(entry.path);
    if (expectedClass === undefined || entry.className !== expectedClass) {
      fail(`builtInParents[${index}] is not an approved built-in parent: ${String(entry.path)}`);
    }
    if (declared.has(entry.path)) fail(`Duplicate built-in parent: ${entry.path}`);
    declared.set(entry.path, entry.className);
  }
  for (const [requiredPath, requiredClass] of builtInParents) {
    if (declared.get(requiredPath) !== requiredClass) fail(`Missing required built-in parent declaration: ${requiredPath}`);
  }
  return declared;
}

function validateStationPlacements(entries) {
  if (!Array.isArray(entries) || entries.length !== expectedStationPlacements.length) {
    fail(`Manifest stationPlacements must contain exactly ${expectedStationPlacements.length} descriptors`);
  }
  const names = new Set();
  const stationIds = new Set();
  const stationIndexes = new Set();
  const normalized = [];
  for (const [index, entry] of entries.entries()) {
    const label = `stationPlacements[${index}]`;
    if (!isObject(entry)) fail(`${label} must be an object`);
    assertKeys(entry, new Set(["name", "stationId", "stationIndex", "direction", "radius", "angleDegrees", "yawDegrees"]), label);
    const expected = expectedStationPlacements[index];
    const expectedIndex = index + 1;
    const suffix = String(expectedIndex).padStart(2, "0");
    if (entry.name !== `Station_${suffix}`) fail(`${label}.name must be Station_${suffix}`);
    if (entry.stationId !== `station_${suffix}`) fail(`${label}.stationId must be station_${suffix}`);
    if (entry.stationIndex !== expectedIndex) fail(`${label}.stationIndex must be ${expectedIndex}`);
    if (entry.direction !== expected.direction) fail(`${label}.direction must be ${expected.direction}`);
    if (entry.radius !== 50) fail(`${label}.radius must be 50`);
    if (entry.angleDegrees !== expected.angleDegrees) fail(`${label}.angleDegrees must be ${expected.angleDegrees}`);
    if (entry.yawDegrees !== expected.yawDegrees) fail(`${label}.yawDegrees must be ${expected.yawDegrees}`);
    for (const [field, value] of [["radius", entry.radius], ["angleDegrees", entry.angleDegrees], ["yawDegrees", entry.yawDegrees]]) {
      assertFiniteNumber(value, `${label}.${field}`);
    }
    if (names.has(entry.name)) fail(`Duplicate station placement name: ${entry.name}`);
    if (stationIds.has(entry.stationId)) fail(`Duplicate station placement id: ${entry.stationId}`);
    if (stationIndexes.has(entry.stationIndex)) fail(`Duplicate station placement index: ${entry.stationIndex}`);
    names.add(entry.name);
    stationIds.add(entry.stationId);
    stationIndexes.add(entry.stationIndex);
    normalized.push({ ...entry });
  }
  return normalized;
}

function validateManagedServices(entries) {
  if (!Array.isArray(entries) || entries.length !== 1) {
    fail("Manifest managedServices must contain exactly one Lighting descriptor");
  }
  const entry = entries[0];
  if (!isObject(entry)) fail("managedServices[0] must be an object");
  assertKeys(entry, new Set(["path", "className", "properties"]), "managedServices[0]");
  if (entry.path !== "Lighting" || entry.className !== "Lighting") {
    fail("managedServices[0] must describe the Lighting service");
  }
  return [{
    path: entry.path,
    className: entry.className,
    properties: validatePropertyMap(entry.properties, "managedServices[0].properties"),
  }];
}

function validateRawInstanceShapes(entries) {
  if (!Array.isArray(entries)) fail("Manifest instances must be an array");
  for (const [index, entry] of entries.entries()) {
    const label = `instances[${index}]`;
    if (!isObject(entry)) fail(`${label} must be an object`);
    assertKeys(entry, new Set(["path", "className", "properties", "attributes"]), label);
    parseManagedPath(entry.path, `${label}.path`);
    if (typeof entry.className !== "string") fail(`${label}.className must be a string`);
  }
}

function expandStationInstances(rawInstances, placements) {
  const templateEntries = rawInstances.filter((entry) => entry.path === stationTemplateRoot || entry.path.startsWith(`${stationTemplateRoot}.`));
  if (templateEntries.length === 0 || templateEntries[0].path !== stationTemplateRoot || templateEntries[0].className !== "Model") {
    fail(`Station source template must begin with a Model at ${stationTemplateRoot}`);
  }
  const concreteEntries = rawInstances.filter((entry) => entry.path !== stationTemplateRoot && !entry.path.startsWith(`${stationTemplateRoot}.`));
  const stationsParent = parentPathOf(stationTemplateRoot);
  for (const placement of placements) {
    const targetRoot = `${stationsParent}.${placement.name}`;
    for (const templateEntry of templateEntries) {
      const entry = structuredClone(templateEntry);
      const suffix = templateEntry.path.slice(stationTemplateRoot.length);
      entry.path = `${targetRoot}${suffix}`;
      if (entry.properties?.CFrame !== undefined) {
        entry.properties.CFrame = transformCFrameValue(entry.properties.CFrame, placement);
      }
      if (suffix === "") {
        entry.attributes = {
          ...(entry.attributes ?? {}),
          StationId: { type: "string", value: placement.stationId },
          StationIndex: { type: "number", value: placement.stationIndex },
        };
      }
      if (suffix === ".OwnerDisplay.BillboardGui.StationNumber") {
        entry.properties = {
          ...(entry.properties ?? {}),
          Text: { type: "string", value: `STATION ${String(placement.stationIndex).padStart(2, "0")}` },
        };
      }
      concreteEntries.push(entry);
    }
  }
  concreteEntries.sort(compareManagedEntries);
  return concreteEntries;
}

function loadAndValidateManifest(manifestPath) {
  let manifest;
  try {
    manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  } catch (error) {
    fail(`Unable to parse manifest: ${error instanceof Error ? error.message : String(error)}`);
  }
  if (!isObject(manifest)) fail("Manifest root must be an object");
  assertKeys(manifest, new Set(["name", "mode", "builtInParents", "managedServices", "stationPlacements", "instances", "scripts"]), "Manifest root");
  if (typeof manifest.name !== "string" || manifest.name.length === 0) fail("Manifest name must be a non-empty string");
  if (manifest.mode !== "edit") fail("Manifest mode must be edit");
  if (!Array.isArray(manifest.scripts)) fail("Manifest scripts must be an array");

  const declaredBuiltIns = validateBuiltInParents(manifest.builtInParents);
  const managedServices = validateManagedServices(manifest.managedServices);
  const stationPlacements = validateStationPlacements(manifest.stationPlacements);
  validateRawInstanceShapes(manifest.instances);
  const concreteInstanceEntries = expandStationInstances(manifest.instances, stationPlacements);
  const guaranteedClasses = new Map([...supportedServices, ...declaredBuiltIns]);
  const managedPaths = new Set();
  const instances = [];
  for (const [index, entry] of concreteInstanceEntries.entries()) {
    const label = `expandedInstances[${index}]`;
    parseManagedPath(entry.path, `${label}.path`);
    if (!supportedClasses.has(entry.className) || supportedScriptClasses.has(entry.className)) {
      fail(`${label}.className is unsupported for an authored instance: ${String(entry.className)}`);
    }
    if (managedPaths.has(entry.path) || guaranteedClasses.has(entry.path)) fail(`Duplicate managed path: ${entry.path}`);
    const parentPath = parentPathOf(entry.path);
    if (!guaranteedClasses.has(parentPath)) {
      fail(`Instance parent must be declared earlier or be built-in: ${parentPath} (required by ${entry.path})`);
    }
    const properties = validatePropertyMap(entry.properties, `${label}.properties`);
    const attributes = validatePropertyMap(entry.attributes, `${label}.attributes`, true);
    instances.push({ path: entry.path, className: entry.className, properties, attributes });
    managedPaths.add(entry.path);
    guaranteedClasses.set(entry.path, entry.className);
  }

  const scripts = [];
  for (const [index, entry] of manifest.scripts.entries()) {
    const label = `scripts[${index}]`;
    if (!isObject(entry)) fail(`${label} must be an object`);
    assertKeys(entry, new Set(["path", "className", "enabled", "sourceFile"]), label);
    parseManagedPath(entry.path, `${label}.path`);
    if (!supportedScriptClasses.has(entry.className)) fail(`${label}.className is unsupported: ${String(entry.className)}`);
    if (managedPaths.has(entry.path) || guaranteedClasses.has(entry.path)) fail(`Duplicate managed path: ${entry.path}`);
    const parentPath = parentPathOf(entry.path);
    if (!guaranteedClasses.has(parentPath)) fail(`Script parent is not declared: ${parentPath} (required by ${entry.path})`);
    if ((entry.className === "Script" || entry.className === "LocalScript") && entry.enabled !== undefined && typeof entry.enabled !== "boolean") {
      fail(`${label}.enabled must be boolean when provided`);
    }
    if (typeof entry.sourceFile !== "string" || entry.sourceFile.length === 0 || path.isAbsolute(entry.sourceFile)) {
      fail(`${label}.sourceFile must be a non-empty repository-relative path`);
    }
    const sourcePath = path.resolve(repositoryRoot, entry.sourceFile);
    if (!fs.existsSync(sourcePath) || !fs.statSync(sourcePath).isFile()) fail(`Source file does not exist for ${entry.path}: ${entry.sourceFile}`);
    const realSourcePath = fs.realpathSync(sourcePath);
    const sourceRelativeToRoot = path.relative(realRepositoryRoot, realSourcePath);
    if (sourceRelativeToRoot === "" || sourceRelativeToRoot.startsWith(`..${path.sep}`) || path.isAbsolute(sourceRelativeToRoot)) {
      fail(`Source file escapes repository root for ${entry.path}: ${entry.sourceFile}`);
    }
    scripts.push({
      path: entry.path,
      className: entry.className,
      enabled: entry.className === "ModuleScript" ? undefined : entry.enabled !== false,
      sourceFile: entry.sourceFile.replaceAll("\\", "/"),
      source: fs.readFileSync(realSourcePath, "utf8").replace(/^\uFEFF/, "").replace(/\r\n?/g, "\n"),
    });
    managedPaths.add(entry.path);
    guaranteedClasses.set(entry.path, entry.className);
  }

  instances.sort(compareManagedEntries);
  scripts.sort(compareManagedEntries);
  return { name: manifest.name, mode: manifest.mode, builtInParents: declaredBuiltIns, managedServices, instances, scripts, classByPath: guaranteedClasses };
}

function editModeGuard() {
  return 'if game:GetService("RunService"):IsRunning() then error("Phase 02 Studio sync is Edit-mode only") end';
}

function appendParentResolution(commands, managedPath, classByPath) {
  const parts = managedPath.split(".");
  const serviceName = parts.shift();
  parts.pop();
  commands.push(`local parent=game:GetService(${JSON.stringify(serviceName)})`);
  let currentPath = serviceName;
  for (const part of parts) {
    currentPath = `${currentPath}.${part}`;
    const expectedClass = classByPath.get(currentPath);
    if (expectedClass === undefined) fail(`Generator has no expected class for parent ${currentPath}`);
    commands.push(`local child=parent:FindFirstChild(${JSON.stringify(part)})`);
    commands.push(`local childCount=0;for _,candidate in ipairs(parent:GetChildren()) do if candidate.Name==${JSON.stringify(part)} then childCount+=1 end end`);
    commands.push(`if childCount>1 then error(${JSON.stringify(`Phase 02 Studio sync duplicate managed child at ${currentPath}`)}) end`);
    commands.push(`if not child then error(${JSON.stringify(`Phase 02 Studio sync missing managed parent: ${currentPath}`)}) end`);
    commands.push(`if not child:IsA(${JSON.stringify(expectedClass)}) then error(${JSON.stringify(`Phase 02 Studio sync conflict at ${currentPath}: expected ${expectedClass}, found `)}..child.ClassName) end`);
    commands.push("parent=child");
  }
}

function appendManagedValues(commands, instanceVariable, values, attributes, managedPath) {
  for (const [propertyName, typedValue] of Object.entries(values)) {
    commands.push(`local propertyOk,propertyError=pcall(function() ${instanceVariable}.${propertyName}=${typedValueToLuau(typedValue)} end)`);
    commands.push(`if not propertyOk then error(${JSON.stringify(`Phase 02 Studio sync failed property ${propertyName} at ${managedPath}: `)}..tostring(propertyError)) end`);
  }
  for (const [attributeName, typedValue] of Object.entries(attributes)) {
    commands.push(`local attributeOk,attributeError=pcall(function() ${instanceVariable}:SetAttribute(${JSON.stringify(attributeName)},${typedValueToLuau(typedValue)}) end)`);
    commands.push(`if not attributeOk then error(${JSON.stringify(`Phase 02 Studio sync failed attribute ${attributeName} at ${managedPath}: `)}..tostring(attributeError)) end`);
  }
}

function buildEnsureInstanceCommand(entry, classByPath) {
  const commands = [editModeGuard()];
  appendParentResolution(commands, entry.path, classByPath);
  const instanceName = entry.path.split(".").at(-1);
  commands.push(`local instance=parent:FindFirstChild(${JSON.stringify(instanceName)})`);
  commands.push(`local instanceCount=0;for _,candidate in ipairs(parent:GetChildren()) do if candidate.Name==${JSON.stringify(instanceName)} then instanceCount+=1 end end`);
  commands.push(`if instanceCount>1 then error(${JSON.stringify(`Phase 02 Studio sync duplicate managed child at ${entry.path}`)}) end`);
  commands.push(`if instance and not instance:IsA(${JSON.stringify(entry.className)}) then error(${JSON.stringify(`Phase 02 Studio sync conflict at ${entry.path}: expected ${entry.className}, found `)}..instance.ClassName) end`);
  commands.push("local created=false");
  commands.push(`if not instance then instance=Instance.new(${JSON.stringify(entry.className)});instance.Name=${JSON.stringify(instanceName)};created=true end`);
  appendManagedValues(commands, "instance", entry.properties, entry.attributes, entry.path);
  commands.push("if created then instance.Parent=parent end");
  return commands.join(";");
}

function buildWriteScriptCommand(entry, classByPath) {
  const commands = [editModeGuard()];
  appendParentResolution(commands, entry.path, classByPath);
  const instanceName = entry.path.split(".").at(-1);
  commands.push(`local instance=parent:FindFirstChild(${JSON.stringify(instanceName)})`);
  commands.push(`local instanceCount=0;for _,candidate in ipairs(parent:GetChildren()) do if candidate.Name==${JSON.stringify(instanceName)} then instanceCount+=1 end end`);
  commands.push(`if instanceCount>1 then error(${JSON.stringify(`Phase 02 Studio sync duplicate managed child at ${entry.path}`)}) end`);
  commands.push(`if instance and not instance:IsA(${JSON.stringify(entry.className)}) then error(${JSON.stringify(`Phase 02 Studio sync conflict at ${entry.path}: expected ${entry.className}, found `)}..instance.ClassName) end`);
  commands.push("local created=false");
  commands.push(`if not instance then instance=Instance.new(${JSON.stringify(entry.className)});instance.Name=${JSON.stringify(instanceName)};created=true end`);
  if (entry.className !== "ModuleScript") commands.push("instance.Disabled=true");
  commands.push(`local sourceOk,sourceError=pcall(function() instance.Source=${JSON.stringify(entry.source)} end)`);
  commands.push(`if not sourceOk then error(${JSON.stringify(`Phase 02 Studio sync failed to apply Source at ${entry.path}: `)}..tostring(sourceError)) end`);
  commands.push("if created then instance.Parent=parent end");
  if (entry.className !== "ModuleScript") commands.push(`instance.Disabled=${entry.enabled ? "false" : "true"}`);
  return commands.join(";");
}

function buildArtifacts(manifest) {
  const operations = [];
  const blueprintSteps = [];
  for (const entry of manifest.managedServices) {
    const bridgeProperties = valueMapToBridge(entry.properties);
    const command = [editModeGuard()];
    command.push(`local service=game:GetService(${JSON.stringify(entry.path)})`);
    appendManagedValues(command, "service", entry.properties, {}, entry.path);
    operations.push({
      type: "setLighting",
      path: entry.path,
      className: entry.className,
      overwrite: true,
      properties: bridgeProperties,
      command: command.join(";"),
    });
    blueprintSteps.push({
      type: "setLighting",
      properties: bridgeProperties,
    });
  }
  for (const entry of manifest.instances) {
    const bridgeProperties = valueMapToBridge(entry.properties);
    const bridgeAttributes = valueMapToBridge(entry.attributes);
    operations.push({
      type: "ensureInstance",
      path: entry.path,
      className: entry.className,
      overwrite: true,
      properties: bridgeProperties,
      attributes: bridgeAttributes,
      command: buildEnsureInstanceCommand(entry, manifest.classByPath),
    });
    blueprintSteps.push({
      type: "ensureInstance",
      path: entry.path,
      className: entry.className,
      overwrite: true,
      properties: bridgeProperties,
      attributes: bridgeAttributes,
    });
  }
  for (const entry of manifest.scripts) {
    const expectedSourceHash = sourceHash(entry.source);
    operations.push({
      type: "writeScript",
      path: entry.path,
      className: entry.className,
      ...(entry.className === "ModuleScript" ? {} : { enabled: entry.enabled }),
      overwrite: true,
      expectedSourceHash,
      sourceFile: entry.sourceFile,
      command: buildWriteScriptCommand(entry, manifest.classByPath),
    });
    blueprintSteps.push({
      type: "writeScript",
      path: entry.path,
      className: entry.className,
      ...(entry.className === "ModuleScript" ? {} : { enabled: entry.enabled }),
      overwrite: true,
      expectedSourceHash,
      source: entry.source,
    });
  }
  return {
    blueprint: {
      name: manifest.name,
      mode: "edit",
      description: "Generated from source-controlled Phase 02 typed authoring data. Apply only in Roblox Studio Edit mode.",
      steps: blueprintSteps,
    },
    commandBar: {
      name: manifest.name,
      mode: "edit",
      description: "Run operations in order in Roblox Studio Edit mode. Existing correct instances are reused; conflicts fail without deletion.",
      operations,
    },
  };
}

function main() {
  const manifestPath = process.argv[2] ? path.resolve(process.argv[2]) : defaultManifestPath;
  const outputDirectory = process.argv[3] ? path.resolve(process.argv[3]) : defaultOutputDirectory;
  const manifest = loadAndValidateManifest(manifestPath);
  const { blueprint, commandBar } = buildArtifacts(manifest);
  fs.mkdirSync(outputDirectory, { recursive: true });
  fs.writeFileSync(path.join(outputDirectory, "phase02-blueprint.json"), `${JSON.stringify(blueprint, null, 2)}\n`, "utf8");
  fs.writeFileSync(path.join(outputDirectory, "phase02-command-bar.json"), `${JSON.stringify(commandBar, null, 2)}\n`, "utf8");
  console.log("[Phase02StudioBlueprint] wrote phase02-blueprint.json");
  console.log("[Phase02StudioBlueprint] wrote phase02-command-bar.json");
}

try {
  main();
} catch (error) {
  console.error(`[Phase02StudioBlueprint] FAIL ${error instanceof Error ? error.message : String(error)}`);
  process.exitCode = 1;
}
