import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const toolsDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(toolsDirectory, "..");
const manifestPath = path.join(repositoryRoot, "studio", "phase01.manifest.json");
const outputDirectory = path.join(repositoryRoot, ".codex-cache");
const outputPath = path.join(outputDirectory, "phase01-blueprint.json");
const commandBarOutputPath = path.join(outputDirectory, "phase01-command-bar.json");

const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
const steps = [];

for (const folderPath of manifest.folders) {
  steps.push({ type: "ensureFolder", path: folderPath });
}

for (const scriptEntry of manifest.scripts) {
  const sourcePath = path.join(repositoryRoot, scriptEntry.sourceFile);
  const source = fs.readFileSync(sourcePath, "utf8").replace(/^\uFEFF/, "");
  steps.push({
    type: "writeScript",
    path: scriptEntry.path,
    className: scriptEntry.className,
    source,
  });
}

const commandBarCommands = manifest.scripts.map((scriptEntry) => {
  const pathParts = scriptEntry.path.split(".");
  const serviceName = pathParts.shift();
  const instanceName = pathParts.pop();
  const parentExpression = `game:GetService(${JSON.stringify(serviceName)})${pathParts
    .map((part) => `[${JSON.stringify(part)}]`)
    .join("")}`;
  const sourcePath = path.join(repositoryRoot, scriptEntry.sourceFile);
  const source = fs.readFileSync(sourcePath, "utf8").replace(/^\uFEFF/, "");
  const enableScript = scriptEntry.className === "Script" ? ";instance.Disabled=false" : "";
  const command = [
    `local parent=${parentExpression}`,
    `local instance=parent:FindFirstChild(${JSON.stringify(instanceName)})`,
    `if instance and not instance:IsA(${JSON.stringify(scriptEntry.className)}) then instance:Destroy();instance=nil end`,
    `if not instance then instance=Instance.new(${JSON.stringify(scriptEntry.className)});instance.Name=${JSON.stringify(instanceName)};instance.Parent=parent end`,
    `instance.Source=${JSON.stringify(source)}${enableScript}`,
  ].join(";");
  return { path: scriptEntry.path, command };
});

const blueprint = {
  name: manifest.name,
  mode: "supervised",
  description: "Generated from canonical repository Luau sources. Do not edit this generated file.",
  steps,
};

fs.mkdirSync(outputDirectory, { recursive: true });
fs.writeFileSync(outputPath, `${JSON.stringify(blueprint, null, 2)}\n`, "utf8");
fs.writeFileSync(
  commandBarOutputPath,
  `${JSON.stringify({ name: manifest.name, commands: commandBarCommands }, null, 2)}\n`,
  "utf8",
);
console.log(outputPath);
console.log(commandBarOutputPath);
