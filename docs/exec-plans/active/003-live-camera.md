# Execution Plan 003 — Live Immersive Camera

Status: completed on 2026-07-23.

## Goal

Replace the app-runtime mock camera on physical iPhone with a real, immersive
rear-camera experience while keeping Simulator development deterministic.

## Delivered

1. AVFoundation permission handling with localized denial and unavailable-camera errors.
2. Serial-queue `AVCaptureSession` configuration and high-quality photo output.
3. Full-screen `AVCaptureVideoPreviewLayer` hidden behind an opaque preview factory.
4. Real JPEG bytes and pixel dimensions passed unchanged into the existing AI pipeline.
5. Session stop after capture, restart on retake, portrait-only orientation, and
   stage-specific camera failure recovery.
6. Simulator-only scene fallback selected by runtime dependency composition.
7. Immersive poster-styled controls plus a short tap-through guard after navigation.

## Verification

- Generic iOS Simulator build succeeded.
- Generic physical iOS device build succeeded with camera code compiled.
- Thirteen unit tests passed with zero failures.
- iPhone 17 Pro Simulator reached viewfinder, capture, understanding and story approval.

## Remaining physical check

The repository environment has no connected iPhone camera feed. A signed build
must still be installed on one physical iPhone to visually confirm lens framing,
flash behavior and the first system permission prompt.
