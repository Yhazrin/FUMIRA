/**
 * Compile the canonical scene spec into a scene.json
 * that the display app can render.
 */
import { SceneCompiler } from '../../../server/scene-compiler.js';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const specPath = path.join(__dirname, 'scene.canon.json');
const outPath = path.join(__dirname, 'scene.json');

const spec = JSON.parse(fs.readFileSync(specPath, 'utf-8'));

const compiler = new SceneCompiler();
compiler.loadSceneSpec(spec);
const manifest = compiler.getSceneManifest();

fs.writeFileSync(outPath, JSON.stringify(manifest, null, 2));
console.log('✅ Compiled scene.json');
console.log(`   Entities: ${manifest.sceneGraph.length}`);
console.log(`   Scene graph nodes: ${manifest.sceneGraph.map(n => n.id).join(', ')}`);
