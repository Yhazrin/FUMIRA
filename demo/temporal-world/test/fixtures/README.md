# Test Fixtures

These fixture files are **test-only**. They are never imported by production code.

## campus-gate.json

A valid SceneFixture for the campus-gate diorama. Used by tests to verify:
- Scene loading and entity building
- Temporal interpolation across anchor years
- Palette and style application

**This fixture is NOT loaded by the desktop client.** The desktop fetches
scene data dynamically from `/api/scene/:sessionId`, which is populated by
the GenerationService (SceneCompiler) when a photo is processed.
