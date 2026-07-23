# Design System

## Palette

| Token | Value | Role |
|---|---|---|
| Paper | `#F6F3E8` | primary canvas |
| Paper White | `#FFFDF7` | cards and light control fills |
| Time Blue | `#3657D6` | temporal emphasis |
| Deep Time Blue | `#243899` | generation typography |
| Park Green | `#2C7A44` | nature and past/future accents |
| Growth Green | `#68C86D` | generation surface |
| Energy Lime | `#DFFF45` | active energy and underline |
| Ink | `#111111` | primary content/control |
| Muted Ink | `#A5A39B` | secondary labels |
| Error Coral | `#E95E52` | recoverable failure |

Energy Lime is never a page background. Raw values live only in DesignSystem tokens.

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
from a single time value.
