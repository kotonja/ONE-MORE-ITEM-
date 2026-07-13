import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const toolsDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(toolsDirectory, "..");
const realRepositoryRoot = fs.realpathSync(repositoryRoot);
const manifestPath = path.join(repositoryRoot, "studio", "phase01.manifest.json");
const outputDirectory = path.join(repositoryRoot, ".codex-cache");
const blueprintOutputPath = path.join(outputDirectory, "phase01-blueprint.json");
const commandBarOutputPath = path.join(outputDirectory, "phase01-command-bar.json");

const supportedServices = new Set(["ReplicatedStorage", "ServerScriptService"]);
const supportedScriptClasses = new Set(["ModuleScript", "Script"]);

function fail(message) {
  throw new Error(`[StudioSync] ${message}`);
}

function parseManagedPath(value, label) {
  if (typeof value !== "string" || value.length === 0) {
    fail(`${label} must be a non-empty string`);
  }
  const parts = value.split(".");
  if (parts.some((part) => part.length === 0)) {
    fail(`${label} contains an empty path segment: ${value}`);
  }
  if (!supportedServices.has(parts[0])) {
    fail(`${label} must begin with a supported Roblox service (${[...supportedServices].join(", ")}): ${value}`);
  }
  return parts;
}

function parentPathOf(managedPath) {
  const parts = managedPath.split(".");
  parts.pop();
  return parts.join(".");
}

function compareManagedPaths(left, right) {
  const depthDifference = left.split(".").length - right.split(".").length;
  if (depthDifference !== 0) {
    return depthDifference;
  }
  return left < right ? -1 : left > right ? 1 : 0;
}

function loadAndValidateManifest() {
  let manifest;
  try {
    manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  } catch (error) {
    fail(`Unable to parse studio/phase01.manifest.json: ${error instanceof Error ? error.message : String(error)}`);
  }

  if (!manifest || typeof manifest !== "object") {
    fail("Manifest root must be an object");
  }
  if (typeof manifest.name !== "string" || manifest.name.length === 0) {
    fail("Manifest name must be a non-empty string");
  }
  if (!Array.isArray(manifest.folders)) {
    fail("Manifest folders must be an array");
  }
  if (!Array.isArray(manifest.scripts)) {
    fail("Manifest scripts must be an array");
  }

  const folderPaths = new Set();
  for (const [index, folderPath] of manifest.folders.entries()) {
    const label = `folders[${index}]`;
    const parts = parseManagedPath(folderPath, label);
    if (parts.length < 2) {
      fail(`${label} must name a Folder below a service: ${folderPath}`);
    }
    if (folderPaths.has(folderPath)) {
      fail(`Duplicate folder path: ${folderPath}`);
    }
    folderPaths.add(folderPath);
  }

  const orderedFolderPaths = [...folderPaths].sort(compareManagedPaths);
  const guaranteedParents = new Set(supportedServices);
  for (const folderPath of orderedFolderPaths) {
    const parentPath = parentPathOf(folderPath);
    if (!guaranteedParents.has(parentPath)) {
      fail(`Folder parent is not managed before child: ${parentPath} (required by ${folderPath})`);
    }
    guaranteedParents.add(folderPath);
  }

  const scriptPaths = new Set();
  const scripts = [];
  for (const [index, entry] of manifest.scripts.entries()) {
    const label = `scripts[${index}]`;
    if (!entry || typeof entry !== "object") {
      fail(`${label} must be an object`);
    }
    const parts = parseManagedPath(entry.path, `${label}.path`);
    if (parts.length < 2) {
      fail(`${label}.path must name an instance below a service: ${entry.path}`);
    }
    if (scriptPaths.has(entry.path)) {
      fail(`Duplicate script path: ${entry.path}`);
    }
    if (folderPaths.has(entry.path)) {
      fail(`Managed path is declared as both Folder and script: ${entry.path}`);
    }
    scriptPaths.add(entry.path);

    if (!supportedScriptClasses.has(entry.className)) {
      fail(`${label}.className is unsupported: ${String(entry.className)}`);
    }
    if (entry.className === "Script" && entry.enabled !== undefined && typeof entry.enabled !== "boolean") {
      fail(`${label}.enabled must be boolean when provided`);
    }
    if (typeof entry.sourceFile !== "string" || entry.sourceFile.length === 0) {
      fail(`${label}.sourceFile must be a non-empty string`);
    }

    const parentPath = parentPathOf(entry.path);
    if (!guaranteedParents.has(parentPath)) {
      fail(`Script parent is not guaranteed by a managed Folder or service: ${parentPath} (required by ${entry.path})`);
    }

    const sourcePath = path.resolve(repositoryRoot, entry.sourceFile);
    if (!fs.existsSync(sourcePath)) {
      fail(`Source file does not exist for ${entry.path}: ${entry.sourceFile}`);
    }
    if (!fs.statSync(sourcePath).isFile()) {
      fail(`Source path is not a file for ${entry.path}: ${entry.sourceFile}`);
    }
    const realSourcePath = fs.realpathSync(sourcePath);
    const sourceRelativeToRoot = path.relative(realRepositoryRoot, realSourcePath);
    if (sourceRelativeToRoot === "" || sourceRelativeToRoot.startsWith(`..${path.sep}`) || path.isAbsolute(sourceRelativeToRoot)) {
      fail(`Source file escapes repository root for ${entry.path}: ${entry.sourceFile}`);
    }

    scripts.push({
      path: entry.path,
      className: entry.className,
      enabled: entry.className === "Script" ? entry.enabled !== false : undefined,
      sourceFile: entry.sourceFile.replaceAll("\\", "/"),
      source: fs.readFileSync(realSourcePath, "utf8").replace(/^\uFEFF/, "").replace(/\r\n?/g, "\n"),
    });
  }

  scripts.sort((left, right) => (left.path < right.path ? -1 : left.path > right.path ? 1 : 0));
  return { name: manifest.name, folders: orderedFolderPaths, scripts };
}

function appendParentResolution(commands, managedPath) {
  const parts = managedPath.split(".");
  const serviceName = parts.shift();
  parts.pop();
  commands.push(`local parent=game:GetService(${JSON.stringify(serviceName)})`);

  let currentPath = serviceName;
  for (const part of parts) {
    currentPath = `${currentPath}.${part}`;
    commands.push(`local child=parent:FindFirstChild(${JSON.stringify(part)})`);
    commands.push(`if not child then error(${JSON.stringify(`Studio sync missing managed parent Folder: ${currentPath}`)}) end`);
    commands.push(
      `if not child:IsA("Folder") then error(${JSON.stringify(`Studio sync conflict at ${currentPath}: expected Folder, found `)}..child.ClassName) end`,
    );
    commands.push("parent=child");
  }
}

function buildEnsureFolderCommand(folderPath) {
  const commands = [];
  appendParentResolution(commands, folderPath);
  const folderName = folderPath.split(".").at(-1);
  commands.push(`local existing=parent:FindFirstChild(${JSON.stringify(folderName)})`);
  commands.push(
    `if existing and not existing:IsA("Folder") then error(${JSON.stringify(`Studio sync conflict at ${folderPath}: expected Folder, found `)}..existing.ClassName) end`,
  );
  commands.push(
    `if not existing then existing=Instance.new("Folder");existing.Name=${JSON.stringify(folderName)};existing.Parent=parent end`,
  );
  return commands.join(";");
}

function buildWriteScriptCommand(scriptEntry) {
  const commands = [];
  appendParentResolution(commands, scriptEntry.path);
  const instanceName = scriptEntry.path.split(".").at(-1);
  commands.push(`local instance=parent:FindFirstChild(${JSON.stringify(instanceName)})`);
  commands.push(
    `if instance and not instance:IsA(${JSON.stringify(scriptEntry.className)}) then error(${JSON.stringify(`Studio sync conflict at ${scriptEntry.path}: expected ${scriptEntry.className}, found `)}..instance.ClassName) end`,
  );
  commands.push("local created=false");
  commands.push(
    `if not instance then instance=Instance.new(${JSON.stringify(scriptEntry.className)});instance.Name=${JSON.stringify(instanceName)};created=true end`,
  );

  if (scriptEntry.className === "Script") {
    commands.push("instance.Disabled=true");
  }
  commands.push(`local sourceOk,sourceError=pcall(function() instance.Source=${JSON.stringify(scriptEntry.source)} end)`);
  commands.push(
    `if not sourceOk then error(${JSON.stringify(`Studio sync failed to apply Source at ${scriptEntry.path}: `)}..tostring(sourceError)) end`,
  );
  commands.push("if created then instance.Parent=parent end");
  if (scriptEntry.className === "Script") {
    commands.push(`instance.Disabled=${scriptEntry.enabled ? "false" : "true"}`);
  }
  return commands.join(";");
}

function main() {
  const manifest = loadAndValidateManifest();
  const operations = [];
  const blueprintSteps = [];

  for (const folderPath of manifest.folders) {
    operations.push({ type: "ensureFolder", path: folderPath, command: buildEnsureFolderCommand(folderPath) });
    blueprintSteps.push({ type: "ensureFolder", path: folderPath });
  }

  for (const scriptEntry of manifest.scripts) {
    operations.push({
      type: "writeScript",
      path: scriptEntry.path,
      className: scriptEntry.className,
      enabled: scriptEntry.enabled,
      sourceFile: scriptEntry.sourceFile,
      command: buildWriteScriptCommand(scriptEntry),
    });
    blueprintSteps.push({
      type: "writeScript",
      path: scriptEntry.path,
      className: scriptEntry.className,
      ...(scriptEntry.className === "Script" ? { enabled: scriptEntry.enabled } : {}),
      source: scriptEntry.source,
    });
  }

  const blueprint = {
    name: manifest.name,
    mode: "supervised",
    description: "Generated from canonical repository Luau sources. Do not edit this generated file.",
    steps: blueprintSteps,
  };
  const commandBarArtifact = {
    name: manifest.name,
    description: "Run operations in order in Roblox Studio Edit mode. Generated from canonical repository sources.",
    operations,
  };

  fs.mkdirSync(outputDirectory, { recursive: true });
  fs.writeFileSync(blueprintOutputPath, `${JSON.stringify(blueprint, null, 2)}\n`, "utf8");
  fs.writeFileSync(commandBarOutputPath, `${JSON.stringify(commandBarArtifact, null, 2)}\n`, "utf8");
  console.log("[StudioBlueprint] wrote .codex-cache/phase01-blueprint.json");
  console.log("[StudioBlueprint] wrote .codex-cache/phase01-command-bar.json");
}

try {
  main();
} catch (error) {
  console.error(`[StudioBlueprint] FAIL ${error instanceof Error ? error.message : String(error)}`);
  process.exitCode = 1;
}
