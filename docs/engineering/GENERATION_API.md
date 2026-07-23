# Story-Aware Generation Contract

`GenerationProvider` accepts `ImageGenerationRequest`: the captured photo,
structured scene understanding, approved temporal story, continuous target time,
model route, and session UUID. It emits progress and a `GeneratedFrame` through an
async throwing stream.

The UI never knows endpoint URLs or transport models. Cancellation and session
identity are mandatory so stale scrubs cannot overwrite the current result.

The frame records the story beat ID, generation prompt, route ID, and optional
rendered image bytes. The prompt explicitly contains original-subject and
composition continuity rules. See `AI_PIPELINE_API.md` for the hosted transport.
