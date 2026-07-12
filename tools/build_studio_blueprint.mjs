import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const toolsDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(toolsDirectory, "..");
const manifestPath = path.join(repositoryRoot, "studio", "phase01.manifest.json");
const outputDirectory = path.join(repositoryRoot, ".codex-cache");
const outputPath = path.join(outputDirectory, "phase01-blueprint.json");

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

const blueprint = {
  name: manifest.name,
  mode: "supervised",
  description: "Generated from canonical repository Luau sources. Do not edit this generated file.",
  steps,
};

fs.mkdirSync(outputDirectory, { recursive: true });
fs.writeFileSync(outputPath, `${JSON.stringify(blueprint, null, 2)}\n`, "utf8");
console.log(outputPath);
