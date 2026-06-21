#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";

const repoRoot = path.resolve(import.meta.dirname, "..");
const defaultAgentsRoot =
  path.join(repoRoot, "Research/sources/repos/pithings-clippy/src/agents");
const sourceRoot = process.argv[2]
  ? path.resolve(process.argv[2])
  : process.env.CLIPPY_SOURCE_ROOT
    ? path.resolve(process.env.CLIPPY_SOURCE_ROOT)
    : defaultAgentsRoot;
const outputRoot = process.argv[3]
  ? path.resolve(process.argv[3])
  : path.join(repoRoot, "Resources/Characters");

const displayNamesByID = {
  bonzi: "Bonzi",
  clippy: "Clippy",
  f1: "F1",
  genie: "Genie",
  genius: "Genius",
  links: "Links",
  merlin: "Merlin",
  peedy: "Peedy",
  rocky: "Rocky",
  rover: "Rover",
};

function evaluateDefaultObject(filePath) {
  const source = fs.readFileSync(filePath, "utf8");
  const script = source.replace(/^export default\s+/, "module.exports = ");
  const sandbox = { module: { exports: undefined } };
  vm.createContext(sandbox);
  vm.runInContext(script, sandbox, { filename: filePath });
  return sandbox.module.exports;
}

function exportedAgents(root) {
  if (fs.existsSync(path.join(root, "agent.ts"))) {
    const id = path.basename(root);
    return [{ id, sourceRoot: root, outputRoot }];
  }
  return fs.readdirSync(root, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => ({
      id: entry.name,
      sourceRoot: path.join(root, entry.name),
      outputRoot: path.join(outputRoot, displayNamesByID[entry.name] ?? entry.name),
    }))
    .filter((agent) => fs.existsSync(path.join(agent.sourceRoot, "agent.ts")))
    .sort((a, b) => a.id.localeCompare(b.id));
}

function exportAgent(agent) {
  fs.mkdirSync(agent.outputRoot, { recursive: true });

  const character = evaluateDefaultObject(path.join(agent.sourceRoot, "agent.ts"));
  const sounds = evaluateDefaultObject(path.join(agent.sourceRoot, "sounds-mp3.ts"));

  fs.writeFileSync(
    path.join(agent.outputRoot, "character.json"),
    JSON.stringify(character, null, 2) + "\n",
  );
  fs.writeFileSync(
    path.join(agent.outputRoot, "sounds-mp3.json"),
    JSON.stringify(sounds, null, 2) + "\n",
  );
  fs.copyFileSync(path.join(agent.sourceRoot, "map.png"), path.join(agent.outputRoot, "map.png"));

  const summary = {
    id: agent.id,
    displayName: displayNamesByID[agent.id] ?? agent.id,
    sourceRoot: agent.sourceRoot,
    outputRoot: agent.outputRoot,
    generatedAt: new Date().toISOString(),
    frameSize: character.framesize,
    overlayCount: character.overlayCount,
    soundCount: character.sounds.length,
    animationCount: Object.keys(character.animations).length,
    animations: Object.keys(character.animations).sort(),
  };

  fs.writeFileSync(
    path.join(agent.outputRoot, "manifest.json"),
    JSON.stringify(summary, null, 2) + "\n",
  );
  return summary;
}

const summaries = exportedAgents(sourceRoot).map(exportAgent);
console.log(JSON.stringify(summaries.length === 1 ? summaries[0] : summaries, null, 2));
