# Design System

FUMIRA — **Clay OS** 温暖粘土风格。Paper 米白纸感、Time Blue 时间蓝、Park Green 公园绿、
Energy Lime 能量黄绿、Ink 墨黑为品牌核心。Orange 是重要强调色，但不作为全局主色。
平面大色块 + Clay 3D 材质层。禁止蓝紫 AI 渐变，禁止大面积荧光黄作为主视觉。

跨端 token 源文件：`tokens.json`（设计稿）、`tokens.css`（桌面端 CSS）。

## Core Palette

Raw hex values live only in `ClayPalette` / `PosterPalette`. Features must use semantic tokens.

| Token | Hex | Clay Source | Role |
|---|---|---|---|
| Paper | `#F2EEE5` | `warmWhite` | **米白纸张** — 布白纸感背景、海报合成区 |
| Time Blue | `#4A90D9` | `timeBlue` | **时间蓝** — 主操作色、时间强调、相机 UI |
| Time Blue Rim | `#3570A8` | `timeBlueRim` | 时间蓝暗面 — 按压态、阴影、深色描边 |
| Park Green | `#8FCB7E` | `parkGreen` | **公园绿** — 草地、自然场景、植物 |
| Park Green Rim | `#5FA04E` | `parkGreenRim` | 公园绿暗面 — 深层地形、松绿 |
| Energy Lime | `#B7D83D` | `lime` | **能量黄绿** — 成功、激活、进度指示 |
| Ink | `#202425` | `charcoal` | **墨黑** — 文字、深色背景、主 chrome |
| Orange | `#FF672A` | `orange` | **活力橙** — 强调色、玩具红系、温暖点缀 |
| Yellow | `#FFC52A` | `yellow` | **铃铛黄** — 进度条、警告、小面积点睛 |
| Warm White Rim | `#CEC7B8` | `warmWhiteRim` | 暖白边缘 — 分割线、细描边 |
| Error | `#E95E52` | `error` | 错误红 — 可恢复错误 |

### Extended tones

| Token | Hex | Role |
|---|---|---|
| `charcoalLight` | `#3A3E3F` | 暗面二级 — hover、disabled |
| `orangeRim` | `#C9441D` | 橙暗面 — 按压态 |
| `yellowRim` | `#C18B14` | 黄暗面 |

## Clay 3D Style

Clay OS 三维风格是 FUMIRA 的视觉核心。组件使用以下材质系统：

### 四级材质分级

| Level | Roughness | Metalness | Clearcoat | 用途 |
|---|---|---|---|---|
| 0 — 光滑 | 0.0 | 0.0 | 0.0 | 玻璃、高光面、纯净背景 |
| 1 — 微磨 | 0.25 | 0.3 | 0.3 | 哑光塑料、卡片、按钮 |
| 2 — 中磨 | 0.55 | 0.7 | 0.6 | 纸张、布料、海报材质 |
| 3 — 粗磨 | 0.85 | 1.0 | 1.0 | 石材、木材、地面 |

### 几何参数

- `cornerRadiusRatio` = 0.067（Card 26pt / 390pt 短边）
- `bevelSegments` = 8（倒角分段数）
- Card 圆角：26pt
- 照片纸圆角：20pt
- 紧凑控件圆角：18pt

### 使用规则

- 卡片和面板使用 Level 1 材质（微磨 + 薄涂层）
- 海报合成区使用 Level 2 材质（中磨 + 标准涂层）
- 按钮使用 Level 1 + Level 2 混合（微磨底座 + 中磨表面）
- 地面 / 场景元素使用 Level 3 材质（粗磨 + 全金属）
- 所有 3D 元素保持 8 段倒角，确保边缘圆润

## 跨端适配

### Token 来源

- `tokens.json` — 设计稿源文件（Figma 插件、原型工具）
- `tokens.css` — 桌面端 CSS custom properties
- `ClayPalette.swift` — iOS 原始色值源
- `PosterPalette.swift` — iOS 语义 token 桥接层

### 适配规则

- 所有平台从同一 token 源取色，不允许硬编码 hex
- iOS 使用 `ClayPalette` / `PosterPalette` 枚举
- Web/Desktop 使用 `tokens.css` custom properties
- 3D 参数（roughness/metalness/clearcoat）通过 `tokens.json` 同步
- 间距单位统一使用 pt，CSS 端转为 px（1:1）

## Usage Rules

- Page / chrome backgrounds use `charcoal` (dark mode) or `warmWhite` (light mode).
- Paper is allowed only for poster synthesis caption blocks and temporal scene overlays.
- Time Blue is the primary interactive color — buttons, time rail, active states.
- Park Green is reserved for landscape illustration and nature scene elements.
- Energy Lime is a success/activation accent, not a full-screen background.
- Orange is an emphasis color for toys, warmth, and small highlights — not a global primary.
- Primary actions prefer Time Blue; secondary is stroke + ink on canvas.
- White-on-white cards need `warmWhiteRim` stroke for edge definition.
- Photo / scene content remains the visual hero; tokens support it, not compete with it.
- No raw `Color(red:…)` product colors outside `ClayPalette` / `PosterPalette`.

## Continuous time rail (`WaveTimeRail`)

- Visual: ~33 rounded vertical bars (audio-waveform); deterministic envelope +
  rhythm morph continuously with drag.
- Selected thumb capsule + cursor use `timeBlue` at full height as the unique tallest peak.
- Calendar year floats above the cursor; sparse labels are only `-100` / `NOW` / `+100`.
- Drag maps rail X linearly to `TimePosition.normalized` (−1…1). Day/year mapping
  stays nonlinear via `TimePosition` (finer near NOW).
- Horizontal drag stays continuous and bounded. Pulling vertically changes precision.
- On release (and VoiceOver adjust), snaps to the active precision — never to landmarks.
- Touch target ≥ 44pt; VoiceOver exposes target date / year and adjustable actions.

## Typography

- All in-app type uses Apple system fonts (SF Pro / SF Rounded).
- Functional titles, labels, status and buttons use the normal SF family.
- Rounded SF is reserved for the wordmark and occasional poster metric.
- Expressive poster character comes from weight, spacing, color, and restrained rotation.

## Layout

- The Figma artboards are 390×844 references.
- Runtime layout is safe-area-aware and scales to compact/large iPhones.
- Content padding baseline is 24pt; primary control height is 56pt.
- Minimum interactive target: 44×44pt.
