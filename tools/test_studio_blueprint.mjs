import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const toolsDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(toolsDirectory, "..");
const generatorPath = path.join(toolsDirectory, "build_studio_blueprint.mjs");
const manifestPath = path.join(repositoryRoot, "studio", "phase01.manifest.json");
const blueprintPath = path.join(repositoryRoot, ".codex-cache", "phase01-blueprint.json");
const commandBarPath = path.join(repositoryRoot, ".codex-cache", "phase01-command-bar.json");
let checkCount = 0;

function check(callback) {
  callback();
  checkCount += 1;
}

function runGenerator() {
  const result = spawnSync(process.execPath, [generatorPath], {
    cwd: repositoryRoot,
    encoding: "utf8",
  });
  check(() => assert.equal(result.status, 0, `Generator failed:\n${result.stderr || result.stdout}`));
  return result;
}

try {
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  check(() => assert.ok(Array.isArray(manifest.folders) && Array.isArray(manifest.scripts), "Manifest arrays are required"));

  check(() => {
    for (const scriptEntry of manifest.scripts) {
      assert.ok(fs.existsSync(path.resolve(repositoryRoot, scriptEntry.sourceFile)), `Missing source: ${scriptEntry.sourceFile}`);
    }
  });

  const firstRun = runGenerator();
  const firstBlueprint = fs.readFileSync(blueprintPath);
  const firstCommandBar = fs.readFileSync(commandBarPath);
  let artifact;
  check(() => {
    artifact = JSON.parse(firstCommandBar.toString("utf8"));
    assert.ok(Array.isArray(artifact.operations), "Command Bar operations array is required");
  });
  const operations = artifact.operations;
  const folderOperations = operations.filter((operation) => operation.type === "ensureFolder");
  const scriptOperations = operations.filter((operation) => operation.type === "writeScript");

  check(() => assert.ok(folderOperations.length > 0, "Command Bar artifact must contain folder operations"));
  check(() => {
    const firstScriptIndex = operations.findIndex((operation) => operation.type === "writeScript");
    const lastFolderIndex = operations.findLastIndex((operation) => operation.type === "ensureFolder");
    assert.ok(lastFolderIndex < firstScriptIndex, "All folder operations must precede scripts");
  });
  check(() => {
    const indexes = new Map(operations.map((operation, index) => [operation.path, index]));
    for (const folder of folderOperations) {
      const parts = folder.path.split(".");
      parts.pop();
      const parentPath = parts.join(".");
      if (parentPath.includes(".")) {
        assert.ok(indexes.has(parentPath), `Missing folder parent operation: ${parentPath}`);
        assert.ok(indexes.get(parentPath) < indexes.get(folder.path), `Parent must precede child: ${parentPath}`);
      }
    }
  });
  check(() => {
    const guaranteed = new Set(["ReplicatedStorage", "ServerScriptService", ...folderOperations.map((operation) => operation.path)]);
    for (const script of scriptOperations) {
      const parts = script.path.split(".");
      parts.pop();
      assert.ok(guaranteed.has(parts.join(".")), `Script parent is not guaranteed: ${script.path}`);
    }
  });
  check(() => {
    const paths = operations.map((operation) => operation.path);
    assert.equal(new Set(paths).size, paths.length, "Managed paths must be unique");
  });
  check(() => assert.equal(scriptOperations.length, manifest.scripts.length, "Script count must match manifest"));
  check(() => assert.equal(folderOperations.length, manifest.folders.length, "Folder count must match manifest"));
  check(() => {
    for (const operation of operations) {
      assert.ok(!operation.command.includes(":Destroy("), `Operation must not destroy conflicts: ${operation.path}`);
      assert.match(operation.command, /Studio sync conflict/, `Operation needs a clear conflict error: ${operation.path}`);
    }
  });
  check(() => {
    const outputs = `${firstBlueprint.toString("utf8")}\n${firstCommandBar.toString("utf8")}\n${firstRun.stdout}`;
    assert.ok(!outputs.includes(repositoryRoot), "Generated output must not contain the repository's absolute path");
    assert.doesNotMatch(outputs, /[A-Za-z]:\\Users\\/i, "Generated output must not contain a Windows user path");
  });

  runGenerator();
  check(() => assert.deepEqual(fs.readFileSync(blueprintPath), firstBlueprint, "Blueprint output must be deterministic"));
  check(() => assert.deepEqual(fs.readFileSync(commandBarPath), firstCommandBar, "Command Bar output must be deterministic"));

  console.log(
    `[StudioSyncSmoke] PASS checks=${checkCount} folders=${folderOperations.length} scripts=${scriptOperations.length} deterministic=true`,
  );
} catch (error) {
  console.error(`[StudioSyncSmoke] FAIL ${error instanceof Error ? error.message : String(error)}`);
  process.exitCode = 1;
}
