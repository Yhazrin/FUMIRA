# Design System

Direction H — **公园时间海报版**：纯白画布、青蓝天空、草地分层、深松绿、
手写墨色、清新叶绿点睛。平面大色块，动态海报。禁止蓝紫 AI 渐变，禁止大面积
荧光黄作为主视觉。**不以米色作 App 主背景**；米色纸感仅保留在海报合成 /
公园装饰形局部。

视觉基准屏：**Connection「时间光圈」** — 哆啦蓝 + 纯白门户 + 玩具红细节 +
铃铛黄点睛。其余 chrome / 设置 / 结果留白对齐纯白画布。

## Palette

Raw hex values live only in `PosterPalette`. Features must use semantic tokens.

### Core semantic

| Token | Hex | Role |
|---|---|---|
| `canvas` / `pageBackground` | `#FFFFFF` | **纯白画布** — App chrome、设置、结果留白、默认页背景 |
| `paper` | `#F6F3E8` | 米白纸张 — **仅**海报合成区 / 公园装饰形 / 场景叠色 |
| `paperWhite` | `#FFFFFF` | 浅色控件填充（同 `canvas`）；白底靠描边建立层级 |
| `cardLight` | `#FFFFFF` | 完全不透明的浅色信息卡 |
| `cardDark` | `#111111` | 完全不透明的深色信息卡 |
| `cardActive` | `#B8E0F5` | 完全不透明的浅蓝选中态信息卡 |
| `sky` | `#7BC8EB` | 天空青蓝 — Connection 基准、相机叠层、时间强调 |
| `skySoft` | `#B8E0F5` | 天空近地 / 底部渐变 |
| `skyDeep` | `#3D8BB5` | 深青蓝 — 叠层、理解页大色块 |
| `actionBlue` | `#1E9CE0` | 哆啦 A 梦蓝 — 主按钮、进度、时间选中态 |
| `actionBlueDeep` | `#1269A8` | 按压暗面、描边与高对比蓝色文字 |
| `actionBlueShadow` | `#075999` | 时间光圈暗面、光学阴影与外描边 |
| `toyRed` | `#E82A34` | 首屏镜头与入口按钮的小面积红色点睛 |
| `bellYellow` | `#FFD33A` | 首屏状态点与镜头标记的小面积黄色点睛 |
| `grassLight` | `#8FCB7E` | 草地浅绿 — 分层地形近层 |
| `pine` | `#2A5A3C` | 深松绿 — 仅地形深部与自然场景 |
| `leafGreen` | `#5FA868` | 清新叶绿 — **仅**自然场景与海报下划线 |
| `ink` | `#111111` | 深墨黑 — 标题与重要操作 |
| `mutedInk` | `#6E6C64` | 次要标签（白底约 4.6:1 AA） |
| `waveIdle` | `ink @ 22%` | 波形时间轴非选中竖条 |
| `errorCoral` | `#E95E52` | 可恢复错误 |
| `line` | `#D2D0C8` | 分割线 / 白底卡片细描边 |

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

### Usage rules

- Page / chrome backgrounds use `canvas` (or `pageBackground`). Do **not** use
  `paper` as a full-screen App background.
- `paper` is allowed only for poster synthesis caption blocks, park decorative
  shapes (`ParkPosterBackdrop`), and temporal scene overlays.
- `leafGreen` is a natural illustration accent, never an interactive fill.
- Primary buttons prefer `pine` or `ink`; secondary is stroke + `ink` on `canvas`.
- White-on-white cards need `line` stroke (or shadow) for edge definition.
- Information cards, clue tags, evidence pills, and result consoles use
  `cardLight`, `cardDark`, or `cardActive` at full opacity. Do not use Material or
  translucent color fills for these reading surfaces.
- Transparency is reserved for spatial media effects that must reveal the scene:
  viewfinder surrounds, exposure masks, comparison boundaries, and the micro
  time-slice slit. These are not cards.
- Photo / park scene remains the visual hero; tokens support it, not compete with it.
- No raw `Color(red:…)` product colors outside `PosterPalette`.

## Continuous time rail (`WaveTimeRail`)

- Visual: ~33 rounded vertical bars (audio-waveform); deterministic envelope +
  rhythm morph continuously with drag. No white card chrome — floats on `canvas` /
  sky gradients / camera scrims.
- Selected thumb capsule + cursor use `actionBlue` at full height as the
  unique tallest peak; ordinary bars stay below 78% of peak and are centered on
  the rail midline (symmetric ±Y).
- Calendar year floats above the action-blue cursor; sparse labels are only
  `-100` / `NOW` / `+100`.
- Drag maps rail X linearly to `TimePosition.normalized` (−1…1). Day/year mapping
  stays nonlinear via `TimePosition` (finer near NOW). Never snaps to historic
  five-point landmarks while dragging.
- On release (and VoiceOver adjust), snaps to browse granularity: day → week →
  month → year by distance from NOW — not to landmark anchors.
- Touch target ≥ 44pt; VoiceOver exposes target date / year and adjustable actions.
- `TimeRail` remains a thin compatibility wrapper → `WaveTimeRail`.

## Typography

- All in-app type uses Apple system fonts.
- Functional titles, labels, status and buttons use the normal SF family via
  semantic text styles. Rounded SF is reserved for the wordmark and occasional
  poster metric, so functional UI stays calm and recognisably native.
- Expressive poster character comes from weight, spacing, color, and restrained
  1–2 degree rotation — never from oversized novelty type.

## Visible copy hierarchy

- Each stage has one primary sentence and one primary action. Do not expose
  implementation notes, reliability disclaimers, or a second paraphrase of the
  same gesture in the visible interface.
- Prefer a large, direct verb phrase (`拖动，看时间差`) over an eyebrow, title,
  subtitle, helper paragraph, and footer that all explain the same operation.
- A value already communicated by the photo, time rail, or progress number does
  not need another status badge.
- Keep precise behavior and recovery detail in VoiceOver labels and hints so
  visual simplicity never removes accessible instructions.
- Opaque rounded cards group one decision or one status. Fewer, larger cards are
  preferred to several translucent pills.

## Layout

- The Figma artboards are 390×844 references.
- Runtime layout is safe-area-aware and scales to compact/large iPhones.
- Content padding baseline is 24pt; primary control height is 56pt.
- Card radius: 26pt; photo-paper radius: 20pt; compact controls: 18pt. Primary
  button radius is half its height. Use continuous corners and one subtle
  1pt border or soft shadow — never both heavily.
- Minimum interactive target: 44×44pt.

## Scene

The supplied prototype uses a flat illustrated park. The MVP recreates this as
native shapes so it can respond continuously to time: sky tint, hill position,
tree density/scale, sun/moon, path width, grain, and overlay color interpolate
from a single time value. Sky and grass layers pull from `sky*` / `grassLight` /
`pine` tokens; active rail / NOW marker uses `actionBlue`.

## 首屏 / 相机视觉

### Connection（时间光圈 · 视觉基准）

- Full-screen supplied blue-and-white line-art background with a static blue
  wordmark; no portal rings, ornamental lens stack, particles, or parallax.
- A single centered action-blue aperture button is the hero and entry control.
  It keeps a 44pt+ target with no visible CTA sentence and no settings gear.
- The wordmark and button are present immediately and remain geometrically stable.
- Raw color values remain in `PosterPalette`; Connection uses semantic tokens.

### Viewfinder（沉浸相机）

- The screen is a two-layer camera object. `cameraBody` fills the permanent
  lower layer; the live / simulator preview is a separate upper card.
- The preview begins behind the system status region, spans the exact screen
  width, and uses only continuous bottom corners. It has no side gutter, border,
  bottom shadow, frosted surround, or artificial Dynamic Island.
- 16:9, 3:4, and 1:1 keep the card's top and width fixed while only the bottom
  edge moves upward. Native/full framing is a distinct, taller final stop.
- Two 44pt Doraemon-blue / white-symbol controls sit inside the upper card with
  16pt side insets. Their icon contrast is 3.05:1; compact textual feedback uses
  `actionBlueDeep` instead (5.81:1 against white). iOS owns status-bar and
  Dynamic Island geometry.
- The wave-shutter stays visually centered in the exposed blue camera body for
  every card height. Ratio feedback appears briefly inside the card near its
  lower edge; there is no persistent instruction paragraph.

### Chrome screens（权限 / 生成 / 理解 / 故事 / 结果 / 设置 / 失败）

- Default `PosterScreenContainer` background is `canvas` (`#FFFFFF`).
- Primary actions, progress, and time-selection chrome use `actionBlue`; green
  remains part of landscape illustration only and is not an action color.
- Generation, generated-image understanding, story writing, and result all use
  a white page stage so the sealed/revealed photo remains the visual hero.
- Narrative / status cards on white use `canvas` fill + `line` stroke.
- Share poster **caption block** may use local `paper` for mild paper feel;
  the page chrome around it stays white.
