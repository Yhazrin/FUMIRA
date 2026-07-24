# Figma Handoff

## Source of truth

- File key: `ald6cObC6VJODKLV6MQyCk`
- Page: `108:2` — MOTION PROTOTYPE V3｜Maxima 动效融合
- Component and motion contract: `116:987`

## Core flow

| ID | Figma node | SwiftUI target |
|---|---:|---|
| A1 | 116:8 | ConnectionView |
| A2 | 116:35 | BluetoothPermissionView |
| A3 | 116:88 | ConnectionFeedbackView |
| A4 | 116:111 | CameraPermissionView |
| A5 | 116:145 | ViewfinderView |
| A6 | 116:209 | ShutterFeedbackView |
| A7 | 116:237 | GenerationView |
| A8 | 116:291 | FirstResultReadyView |
| A9 | 116:328 | ResultView / NOW reference |
| A10 | 116:419 | ResultView / future reference |

## Edge states

| ID | Figma node | SwiftUI target |
|---|---:|---|
| B1 | 116:526 | ResultView / past reference |
| B2 | 116:631 | SharePosterView |
| B3 | 116:669 | GenerationFailureView |
| B4 | 116:682 | DisconnectedView |
| B5 | 116:747 | OfflinePreviewView |

## Interpretation

Figma defines visual DNA and flow, not a literal fixed-frame implementation.
Status bars and device chrome are excluded from app UI. The original five-point
rail is replaced by the continuous ±100-year WaveTimeRail (audio-waveform bars,
leaf-green selected cursor/year, sparse −100 / NOW / +100 labels) while retaining
continuous scrubbing and nonlinear time mapping.
