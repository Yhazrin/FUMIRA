import { describe, it, expect } from 'vitest'
import dotenv from 'dotenv'
import path from 'path'

dotenv.config({ path: path.resolve(__dirname, '../../.env') })

describe('env vars', () => {
  it('allows a local-only scene sandbox without World Labs credentials', () => {
    const key = process.env.WORLD_LABS_API_KEY
    expect(key === undefined || key.length > 0).toBe(true)
  })

  it('allows a local-only scene sandbox without FAL credentials', () => {
    const key = process.env.FAL_KEY
    expect(key === undefined || key.length > 0).toBe(true)
  })
})
