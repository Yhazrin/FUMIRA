/** Minimal PNG decoder (bit depth 8, color type 2/6, no interlace) — enough for evidence extraction. */
import { inflateSync } from 'node:zlib'

export interface DecodedPng {
  width: number
  height: number
  /** RGBA, 4 bytes per pixel. */
  pixels: Uint8Array
}

export function decodePng(buffer: Buffer): DecodedPng {
  if (buffer.readUInt32BE(0) !== 0x89504e47) throw new Error('not a PNG')
  let offset = 8
  let width = 0
  let height = 0
  let colorType = -1
  const idat: Buffer[] = []

  while (offset < buffer.length) {
    const length = buffer.readUInt32BE(offset)
    const type = buffer.toString('ascii', offset + 4, offset + 8)
    const data = buffer.subarray(offset + 8, offset + 8 + length)
    if (type === 'IHDR') {
      width = data.readUInt32BE(0)
      height = data.readUInt32BE(4)
      const bitDepth = data.readUInt8(8)
      colorType = data.readUInt8(9)
      const interlace = data.readUInt8(12)
      if (bitDepth !== 8) throw new Error(`unsupported bit depth ${bitDepth}`)
      if (colorType !== 2 && colorType !== 6) throw new Error(`unsupported color type ${colorType}`)
      if (interlace !== 0) throw new Error('interlaced PNG unsupported')
    } else if (type === 'IDAT') {
      idat.push(data)
    } else if (type === 'IEND') {
      break
    }
    offset += 12 + length
  }

  const channels = colorType === 6 ? 4 : 3
  const raw = inflateSync(Buffer.concat(idat))
  const stride = width * channels
  const pixels = new Uint8Array(width * height * 4)
  const prior = new Uint8Array(stride)
  const current = new Uint8Array(stride)

  for (let y = 0; y < height; y += 1) {
    const rowStart = y * (stride + 1)
    const filter = raw[rowStart]
    for (let i = 0; i < stride; i += 1) {
      const x = raw[rowStart + 1 + i]
      const left = i >= channels ? current[i - channels] : 0
      const up = prior[i]
      const upLeft = i >= channels ? prior[i - channels] : 0
      let value = x
      if (filter === 1) value = x + left
      else if (filter === 2) value = x + up
      else if (filter === 3) value = x + ((left + up) >> 1)
      else if (filter === 4) {
        const p = left + up - upLeft
        const pa = Math.abs(p - left)
        const pb = Math.abs(p - up)
        const pc = Math.abs(p - upLeft)
        value = x + (pa <= pb && pa <= pc ? left : pb <= pc ? up : upLeft)
      }
      current[i] = value & 0xff
    }
    for (let px = 0; px < width; px += 1) {
      const src = px * channels
      const dst = (y * width + px) * 4
      pixels[dst] = current[src]
      pixels[dst + 1] = current[src + 1]
      pixels[dst + 2] = current[src + 2]
      pixels[dst + 3] = channels === 4 ? current[src + 3] : 255
    }
    prior.set(current)
  }

  return { width, height, pixels }
}
