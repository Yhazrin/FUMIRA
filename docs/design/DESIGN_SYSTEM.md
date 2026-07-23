# Design System

Direction H — **公园时间海报版**：米白纸张、青蓝天空、草地分层、深松绿、
手写墨色、克制苔黄点睛。平面大色块，动态海报。禁止蓝紫 AI 渐变，禁止大面积
荧光黄作为主视觉。

## Palette

Raw hex values live only in `PosterPalette`. Features must use semantic tokens.

### Core semantic

| Token | Hex | Role |
|---|---|---|
| `paper` | `#F6F3E8` | 米白纸张 — 主画布 |
| `paperWhite` | `#FFFDF7` | 卡片与浅色控件填充 |
| `sky` | `#7BC8EB` | 天空青蓝 — 大面积背景、相机叠层、时间强调 |
| `skySoft` | `#B8E0F5` | 天空近地 / 底部渐变 |
| `skyDeep` | `#3D8BB5` | 深青蓝 — 叠层、理解页大色块 |
| `grassLight` | `#8FCB7E` | 草地浅绿 — 分层地形近层 |
| `pine` | `#2A5A3C` | 深松绿 — 地形深部、主按钮、生成页大色块 |
| `moss` | `#C9B35A` | 苔黄 — **仅 ≤5%** 选中态 / 下划线 / 游标 |
| `ink` | `#111111` | 深墨黑 — 标题与重要操作 |
| `mutedInk` | `#A5A39B` | 次要标签 |
| `waveIdle` | `ink @ 22%` | 波形时间轴非选中竖条 |
| `errorCoral` | `#E95E52` | 可恢复错误 |
| `line` | `#C9C6BC` | 分割线 |

### Scene temporal variants

Used by `TemporalParkScene` interpolation — do not hardcode in Features.

| Token | Hex | Role |
|---|---|---|
| `skyPastTop` | `#D1B894` | 过去天空顶（暖纸感） |
| `skyPastBottom` | `#E6D1B3` | 过去天空底 |
| `skyFutureTop` | `#6B8CD1` | 未来天空顶 |
| `skyFutureBottom` | `#94B3E6` | 未来天空底 |

### Compatibility aliases (legacy → Direction H)

| Legacy | Maps to | Notes |
|---|---|---|
| `timeBlue` | `sky` | Prefer `sky` in new code |
| `deepTimeBlue` | `skyDeep` | Prefer `skyDeep` |
| `parkGreen` | `pine` | Prefer `pine` |
| `growthGreen` | `pine` | Generation surfaces use deep pine blocks |
| `energyLime` | `moss` | **Deprecated / accent-only.** Never page bg or full primary fill |

### Usage rules

- `moss`（苔黄）is an accent, never a page background or solid primary button fill.
- Primary buttons prefer `pine` or `ink`; secondary is stroke + `ink` on clear.
- Photo / park scene remains the visual hero; tokens support it, not compete with it.
- No raw `Color(red:…)` product colors outside `PosterPalette`.

## Continuous time rail (`WaveTimeRail`)

- Visual: ~33 rounded vertical bars (audio-waveform); densest rhythm near NOW.
  No white card chrome — floats on `paper` / sky gradients / camera scrims.
- Selected bar + cursor use `moss` (≤5%); idle bars use `waveIdle` (paper) or
  light paperWhite tint (`.immersive` chrome on camera scrim).
- Calendar year floats above the moss cursor; sparse labels are only
  `-100` / `NOW` / `+100`.
- Drag maps rail X linearly to `TimePosition.normalized` (−1…1). Day/year mapping
  stays nonlinear via `TimePosition` (finer near NOW). Never snaps to historic
  five-point landmarks while dragging.
- On release (and VoiceOver adjust), snaps to browse granularity: day → week →
  month → year by distance from NOW — not to landmark anchors.
- Touch target ≥ 44pt; VoiceOver exposes target date / year and adjustable actions.
- `TimeRail` remains a thin compatibility wrapper → `WaveTimeRail`.

## Typography

- Poster Chinese: LXGW Marker Gothic when bundled; system rounded fallback.
- Handwritten English: Caveat Brush when bundled; system rounded italic fallback.
- Functional labels/status/buttons: system font with semantic text styles.
- Poster text may rotate by 1–4 degrees as a deliberate decoration.

## Layout

- The Figma artboards are 390×844 references.
- Runtime layout is safe-area-aware and scales to compact/large iPhones.
- Content padding baseline is 24pt; primary control height is 56pt.
- Poster/card radius: 24–30pt. Primary button radius: half its height.
- Minimum interactive target: 44×44pt.

## Scene

The supplied prototype uses a flat illustrated park. The MVP recreates this as
native shapes so it can respond continuously to time: sky tint, hill position,
tree density/scale, sun/moon, path width, grain, and overlay color interpolate
from a single time value. Sky and grass layers pull from `sky*` / `grassLight` /
`pine` tokens; active rail / NOW marker uses `moss`.

## 首屏 / 相机视觉

### Connection（纸张海报首屏）

- Composition is a **centered poster**, not a top-leading title stack.
- Keyword hero (`PosterKeywordHero`) uses ink / pine / moss segments plus a
  hand-drawn moss underline. Copy invites entry:「给时间，一张照片」/
  「把此刻，留给未来」— avoid repeating「把现在拍下来」.
- Background: paper + sky wash + layered grass ellipses + `TemporalParkScene`
  vignette. No settings gear, no「模型后台」, no developer chrome.
- Primary CTA prefers `pine`; moss stays accent-only.

### Viewfinder（沉浸相机）

- Full-bleed live / simulator preview is the subject.
- Controls sit on **top/bottom scrims only** — no large white rounded cards,
  no redundant instructional copy under the shutter.
- Top: flash (when supported) + optional simulator chip + minimal time chip
  (`NOW · 2026` or selected year). No large slogan.
- Bottom: `WaveTimeRail` (`.immersive` chrome) floating on the scrim; centered
  paper-white shutter with moss accent ring; circular chrome flip + grid.
- All colors via DesignSystem tokens; shutter must not be a solid moss/yellow fill.
