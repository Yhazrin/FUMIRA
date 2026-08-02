/**
 * Pixel-evidence extractor — replaces "visual impression" annotation with
 * measurable image anchors that any run can reproduce:
 *
 *   npx vite-node scripts/extract-evidence.ts -- [slug]
 *
 * Outputs connected-component boxes for high-salience masks (red vehicles,
 * vegetation, dark vehicles) plus a vertical color profile, and writes
 * worlds/<slug>/source/evidence.json for reconciliation with scene.json.
 */
import { readFileSync, writeFileSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { decodePng } from './png'

const appDir = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const args = process.argv.slice(2).filter((arg) => arg !== '--')
const slug = args.find((arg) => !arg.startsWith('--')) ?? 'fumira-beijing-street'

const worldDir = resolve(appDir, '..', 'worlds', slug)
const project = JSON.parse(readFileSync(resolve(worldDir, 'scene.json'), 'utf8'))
const sourceRel: string = project.temporalScene?.sourceImage ?? 'source/0-beijing-street.png'
const png = decodePng(readFileSync(resolve(worldDir, sourceRel)))
const { width, height, pixels } = png

type MaskFn = (r: number, g: number, b: number, x: number, y: number) => boolean

interface Region {
  box: [number, number, number, number]
  areaFraction: number
  centroid: [number, number]
  meanColor: [number, number, number]
}

function componentsFor(mask: MaskFn, minAreaFraction: number, maxRegions: number): Region[] {
  const flags = new Uint8Array(width * height)
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const i = (y * width + x) * 4
      if (mask(pixels[i], pixels[i + 1], pixels[i + 2], x, y)) flags[y * width + x] = 1
    }
  }
  const seen = new Uint8Array(width * height)
  const regions: Region[] = []
  const stack: number[] = []
  for (let start = 0; start < flags.length; start += 1) {
    if (!flags[start] || seen[start]) continue
    let minX = width
    let minY = height
    let maxX = 0
    let maxY = 0
    let count = 0
    let sumX = 0
    let sumY = 0
    let sumR = 0
    let sumG = 0
    let sumB = 0
    stack.push(start)
    seen[start] = 1
    while (stack.length) {
      const index = stack.pop()!
      const x = index % width
      const y = (index / width) | 0
      count += 1
      sumX += x
      sumY += y
      const p = index * 4
      sumR += pixels[p]
      sumG += pixels[p + 1]
      sumB += pixels[p + 2]
      if (x < minX) minX = x
      if (x > maxX) maxX = x
      if (y < minY) minY = y
      if (y > maxY) maxY = y
      const neighbors = [index - 1, index + 1, index - width, index + width]
      for (const next of neighbors) {
        if (next < 0 || next >= flags.length || seen[next] || !flags[next]) continue
        if ((next === index - 1 && x === 0) || (next === index + 1 && x === width - 1)) continue
        seen[next] = 1
        stack.push(next)
      }
    }
    const areaFraction = count / (width * height)
    if (areaFraction < minAreaFraction) continue
    regions.push({
      box: [minX / width, minY / height, (maxX - minX + 1) / width, (maxY - minY + 1) / height],
      areaFraction,
      centroid: [sumX / count / width, sumY / count / height],
      meanColor: [Math.round(sumR / count), Math.round(sumG / count), Math.round(sumB / count)],
    })
  }
  return regions.sort((a, b) => b.areaFraction - a.areaFraction).slice(0, maxRegions)
}

const masks: Record<string, { fn: MaskFn; minArea: number; max: number }> = {
  redVehicle: {
    fn: (r, g, b) => r > 80 && r - g > 45 && r - b > 35,
    minArea: 0.001,
    max: 5,
  },
  vegetation: {
    fn: (r, g, b) => g > 50 && g - r > 12 && g - b > 12,
    minArea: 0.004,
    max: 5,
  },
  darkVehicle: {
    // lower 55% of the frame only, to avoid shadows in canopy
    fn: (r, g, b, _x, y) => y > height * 0.45 && r < 70 && g < 70 && b < 75 && Math.max(r, g, b) - Math.min(r, g, b) < 25,
    minArea: 0.002,
    max: 6,
  },
}

const evidence: Record<string, Region[]> = {}
for (const [name, config] of Object.entries(masks)) {
  evidence[name] = componentsFor(config.fn, config.minArea, config.max)
}

const rows: { y: number; mean: [number, number, number] }[] = []
for (let step = 0; step <= 20; step += 1) {
  const y = Math.min(height - 1, Math.round((step / 20) * (height - 1)))
  let sumR = 0
  let sumG = 0
  let sumB = 0
  for (let x = 0; x < width; x += 1) {
    const i = (y * width + x) * 4
    sumR += pixels[i]
    sumG += pixels[i + 1]
    sumB += pixels[i + 2]
  }
  rows.push({ y: y / height, mean: [Math.round(sumR / width), Math.round(sumG / width), Math.round(sumB / width)] })
}

const round = (value: number) => Math.round(value * 1000) / 1000
console.log(`image ${width}x${height} aspect=${round(width / height)}`)
for (const [name, regions] of Object.entries(evidence)) {
  console.log(`\n${name} (${regions.length} region${regions.length === 1 ? '' : 's'})`)
  for (const region of regions) {
    console.log(
      `  box=[${region.box.map(round).join(', ')}] area=${round(region.areaFraction * 100)}% centroid=[${region.centroid.map(round).join(', ')}] rgb=(${region.meanColor.join(',')})`,
    )
  }
}
console.log('\nrow color profile (y → mean rgb)')
for (const row of rows) {
  console.log(`  y=${round(row.y).toFixed(2)}  rgb=(${row.mean.join(',')})`)
}

const outPath = resolve(worldDir, 'source', 'evidence.json')
writeFileSync(outPath, `${JSON.stringify({ width, height, evidence, rows }, null, 2)}\n`)
console.log(`\nwritten ${outPath}`)
