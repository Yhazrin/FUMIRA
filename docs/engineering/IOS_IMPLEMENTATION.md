# iOS Implementation

## Platform

- Swift 6 language mode
- iOS 17 minimum
- SwiftUI + Observation + Swift Concurrency
- UIKit image rendering is used only by the deterministic Simulator capture service
- AVFoundation powers real rear-camera permission, preview lifecycle and JPEG capture
- CoreBluetooth and hosted-AI implementations remain protocol-backed

## Organization

`App` owns composition and the state machine. `Domain` owns pure value types.
`Services` owns protocols and implementations. `Features` owns SwiftUI screens.
`DesignSystem` owns all product styling and motion. `PreviewSupport` owns fixtures.

## State ownership

`FUMIRAApp` owns one `@State AppModel`. Root and feature views receive the model
explicitly. Feature-local press/drag state stays local. Dependencies are injected
once through `AppDependencies`.

## Narrative pipeline semantics

On physical devices, `LiveCameraService` configures `AVCaptureSession` on a
dedicated serial queue and retains each photo delegate through completion. The
session stops after capture and restarts on retake. Simulator builds inject the
mock camera and preview factory at compile time.

Capture creates valid JPEG data and a session UUID. Understanding produces a
`SceneUnderstanding`; story writing turns that into a `TemporalStory`; the user
must review it before `ImageGenerationRequest` can be created. Every stream carries
the session identity. Late events for another session are discarded.

Continuous scrubbing changes the nearest story beat and local mock visualization
at display refresh speed. A production generator should debounce or render only
after explicit approval, never submit a request for every drag event.

## Runtime modes

The shipped configuration uses deterministic local providers. Route options for
major providers are visible but disabled until a backend catalog marks them ready.
Feature views never construct a provider client.

When `FUMIRA_API_BASE_URL` is set (process environment or Info.plist),
`AppDependencies.runtime` injects `RemoteGenerationProvider` for image generation
while understanding and story stay on mocks. Empty / missing URL keeps
`MockGenerationProvider`. Vendor API keys never appear in the iOS target.
