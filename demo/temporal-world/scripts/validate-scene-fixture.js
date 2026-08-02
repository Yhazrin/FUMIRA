#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';

const fixturePath = process.argv[2] ?? path.resolve('fixtures/street-scene/scene.json');
const fixture = JSON.parse(fs.readFileSync(fixturePath, 'utf8'));
const fail = (message) => {
  console.error(`Scene fixture invalid: ${message}`);
  process.exitCode = 1;
};

if (!fixture.sceneGraph) fail('sceneGraph is required for scene reconstruction');
if (!fixture.sceneGraph?.bounds?.width || !fixture.sceneGraph?.bounds?.depth) {
  fail('sceneGraph.bounds must define width and depth');
}

const entityIds = new Set((fixture.entities ?? []).map(entity => entity.id));
const nodes = fixture.sceneGraph?.nodes ?? [];
const nodeIds = new Set(nodes.map(node => node.id));
for (const node of nodes) {
  if (!entityIds.has(node.id)) fail(`node ${node.id} has no matching entity`);
  if (!Array.isArray(node.footprint) || node.footprint.length !== 2) fail(`node ${node.id} has no 2D footprint`);
  if (!node.layer) fail(`node ${node.id} has no depth layer`);
}
for (const relation of fixture.sceneGraph?.relations ?? []) {
  if (!entityIds.has(relation.from) && !nodeIds.has(relation.from)) fail(`relation.from ${relation.from} is unknown`);
  if (!entityIds.has(relation.to) && !nodeIds.has(relation.to)) fail(`relation.to ${relation.to} is unknown`);
  if (relation.strength < 0 || relation.strength > 1) fail(`relation ${relation.type} strength must be 0..1`);
}

const uniqueEntityIds = new Set(fixture.entities?.map(entity => entity.id));
if (uniqueEntityIds.size !== fixture.entities?.length) fail('entity ids must be unique');
if (fixture.sceneGraph?.evaluation?.target !== 'overall-recognizability') {
  fail('evaluation.target must be overall-recognizability');
}

if (!process.exitCode) {
  console.log(JSON.stringify({
    ok: true,
    fixture: fixture.id,
    entities: fixture.entities.length,
    graphNodes: nodes.length,
    relations: fixture.sceneGraph.relations.length,
    evaluation: fixture.sceneGraph.evaluation.target,
  }, null, 2));
}
