/**
 * Headless calibration runner — the "image-to-model" convergence loop.
 *
 *   npx vite-node scripts/calibrate.ts -- [slug] [--write] [--year 2026] [--min-confidence 0.55]
 *
 * Loads worlds/<slug>/scene.json, projects every canonical node through the
 * fixed photo camera, applies staged SceneLayoutPatches until the layout
 * reaches a fixed point, then reports residual issues. With --write the
 * calibrated nodes/anchors are persisted back into scene.json.
 */
import { readFileSync, writeFileSync, existsSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import type { FumiraTemporalScene } from '../src/types/world'
import {
  CALIBRATION_STAGES,
  calibrateScene,
  evaluateScene,
} from '../src/modules/calibration/projection'

const appDir = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const args = process.argv.slice(2).filter((arg) => arg !== '--')
const flags = new Set(args.filter((arg) => arg.startsWith('--')))
const positional = args.filter((arg) => !arg.startsWith('--'))
const readFlagValue = (name: string, fallback: number) => {
  const index = args.indexOf(name)
  return index >= 0 && args[index + 1] ? Number(args[index + 1]) : fallback
}

const slug = positional[0] ?? 'fumira-beijing-street'
const write = flags.has('--write')
const year = readFlagValue('--year', 2026)
const minConfidence = readFlagValue('--min-confidence', 0.55)

const scenePath = resolve(appDir, '..', 'worlds', slug, 'scene.json')
const project = JSON.parse(readFileSync(scenePath, 'utf8')) as { temporalScene?: FumiraTemporalScene }
const scene = project.temporalScene
if (!scene) {
  console.error(`worlds/${slug}/scene.json has no temporalScene`)
  process.exit(1)
}

function pngAspect(path: string): number | undefined {
  if (!existsSync(path)) return undefined
  const buffer = readFileSync(path)
  if (buffer.length < 24 || buffer.readUInt32BE(12) !== 0x49484452) return undefined
  return buffer.readUInt32BE(16) / buffer.readUInt32BE(20)
}

const imagePath = scene.sourceImage ? resolve(appDir, '..', 'worlds', slug, scene.sourceImage) : undefined
const imageAspect = (imagePath && pngAspect(imagePath)) ?? 4 / 3

const stageLabel = (stage: number) => CALIBRATION_STAGES.find((entry) => entry.stage === stage)?.label ?? String(stage)
const printIssues = (title: string, issues: ReturnType<typeof evaluateScene>['issues']) => {
  console.log(`\n${title}（${issues.length}）`)
  for (const issue of issues) {
    console.log(`  [${issue.kind}] S${issue.stage} ${issue.message}`)
  }
}

console.log(`world: ${slug}`)
console.log(`image: ${scene.sourceImage ?? '(none)'}  aspect=${imageAspect.toFixed(3)}`)
console.log(`year=${year}  minConfidence=${minConfidence}  write=${write}`)

const fmtBox = (box: [number, number, number, number]) => `[${box.map((v) => v.toFixed(2)).join(', ')}]`
const printProjections = (title: string, evaluation: ReturnType<typeof evaluateScene>) => {
  console.log(`\n${title}`)
  for (const projected of evaluation.projections) {
    const node = projected.node
    const anchor = node.imageAnchor
    const cells = [
      projected.node.id.padEnd(24),
      `proj=${fmtBox(projected.box)}`,
      node.imageBox ? `decl=${fmtBox(node.imageBox)}@${(node.confidence ?? 1).toFixed(2)}` : 'decl=—',
      anchor ? `anchor=(${anchor.point[0].toFixed(2)}, ${anchor.point[1].toFixed(2)})@${anchor.confidence.toFixed(2)}` : '',
      projected.visible ? '' : 'OFFSCREEN',
    ].filter(Boolean)
    console.log(`  ${cells.join('  ')}`)
  }
}

const before = evaluateScene(scene, year, imageAspect)
printProjections('投影对照表（校正前）', before)
printIssues('校正前问题', before.issues)

const run = calibrateScene(scene, year, imageAspect, { minConfidence })

console.log(`\n迭代记录（${run.iterations.length} 次 patch，converged=${run.converged}）`)
for (const record of run.iterations) {
  console.log(`  #${record.iteration} [S${record.stage} ${stageLabel(record.stage)}] → ${record.changes.length} change(s), 剩余问题 ${record.issuesAfter}`)
  for (const change of record.changes) {
    const parts = [
      change.position ? `position=[${change.position.join(', ')}]` : '',
      change.scale ? `scale=[${change.scale.join(', ')}]` : '',
    ].filter(Boolean)
    console.log(`     · ${change.id}: ${parts.join('  ')}`)
  }
}

printIssues('校正后残留问题（低置信标注仅报告，不自动改）', run.issues)

// Fixed-point verification: a second pass over the calibrated scene must emit nothing.
const verify = calibrateScene(run.scene, year, imageAspect, { minConfidence })
console.log(`\n稳定性验证：二次运行 patch 数 = ${verify.iterations.length}（期望 0），converged=${verify.converged}`)

if (write) {
  const output = { ...project, temporalScene: run.scene }
  writeFileSync(scenePath, `${JSON.stringify(output, null, 2)}\n`)
  console.log(`\n已写回 ${scenePath}`)
} else {
  console.log('\n（dry-run：加 --write 持久化校正结果）')
}

if (verify.iterations.length > 0) process.exit(2)
