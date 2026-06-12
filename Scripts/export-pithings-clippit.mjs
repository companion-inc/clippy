#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";

const repoRoot = path.resolve(import.meta.dirname, "..");
const defaultSourceRoot =
  "/Users/advaitpaliwal/Projects/clawd/research/clippy-sources/repos/pithings-clippy/src/agents/clippy";
const sourceRoot = process.argv[2] ? path.resolve(process.argv[2]) : defaultSourceRoot;
const outputRoot = process.argv[3]
  ? path.resolve(process.argv[3])
  : path.join(repoRoot, "Resources/Characters/Clippit");

function evaluateDefaultObject(filePath) {
  const source = fs.readFileSync(filePath, "utf8");
  const script = source.replace(/^export default\s+/, "module.exports = ");
  const sandbox = { module: { exports: undefined } };
  vm.createContext(sandbox);
  vm.runInContext(script, sandbox, { filename: filePath });
  return sandbox.module.exports;
}

fs.mkdirSync(outputRoot, { recursive: true });

const character = evaluateDefaultObject(path.join(sourceRoot, "agent.ts"));
const sounds = evaluateDefaultObject(path.join(sourceRoot, "sounds-mp3.ts"));

fs.writeFileSync(
  path.join(outputRoot, "character.json"),
  JSON.stringify(character, null, 2) + "\n",
);
fs.writeFileSync(
  path.join(outputRoot, "sounds-mp3.json"),
  JSON.stringify(sounds, null, 2) + "\n",
);
fs.copyFileSync(path.join(sourceRoot, "map.png"), path.join(outputRoot, "map.png"));

const summary = {
  sourceRoot,
  outputRoot,
  generatedAt: new Date().toISOString(),
  frameSize: character.framesize,
  overlayCount: character.overlayCount,
  soundCount: character.sounds.length,
  animationCount: Object.keys(character.animations).length,
  animations: Object.keys(character.animations).sort(),
};

fs.writeFileSync(
  path.join(outputRoot, "manifest.json"),
  JSON.stringify(summary, null, 2) + "\n",
);

console.log(JSON.stringify(summary, null, 2));
