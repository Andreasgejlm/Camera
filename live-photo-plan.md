# Live Photo Integration Plan (Backwards Compatible)

Last updated: 2026-02-07
Status: In Progress

## Goal
Add Live Photo capture as an opt-in enhancement while preserving existing behavior for all current adopters.

## Backward Compatibility Contract
- `CameraOutputType` remains unchanged (`photo`, `video`).
- Existing apps continue to get a single still image when using photo mode by default.
- Existing callbacks (`onImageCaptured`, `onVideoCaptured`) continue to work without code changes.
- Any Live Photo functionality must be additive and optional.

## Scope
- Additive public API for enabling Live Photo in photo mode.
- Live Photo capture pipeline in `CameraManagerPhotoOutput`.
- Graceful fallback to still photo when unsupported or failing.
- File lifecycle and cleanup for paired Live Photo movie assets.
- Tests and docs updates.

## Milestones
1. Planning and progress tracking
- [x] Create this plan document
- [x] Keep this file updated after every implementation milestone

2. Public additive API
- [x] Add `PhotoCaptureMode` (`still`, `livePhoto`)
- [x] Add `setPhotoCaptureMode(_:)` to `MCamera` settings API
- [x] Add optional `onLivePhotoCaptured` callback
- [x] Add public Live Photo model (`MCameraLivePhoto`)
- [x] Extend `MCameraMedia` additively (no breaking changes)

3. Internal state/config plumbing
- [x] Add photo capture mode + support flags to `CameraManagerAttributes`
- [x] Add live-photo callback storage in `MCamera.Config`
- [x] Keep default path unchanged (still photo only)

4. Capture pipeline implementation
- [x] Enable and configure Live Photo capture in `CameraManagerPhotoOutput`
- [x] Track in-flight capture parts and assemble final paired result
- [x] Fallback to still photo on unsupported devices/errors
- [x] Preserve current photo animation and screen transitions

5. Callback and UI integration
- [x] Keep `onImageCaptured` behavior unchanged
- [x] Call `onLivePhotoCaptured` only for successful live captures
- [x] Keep default camera UI unchanged unless explicitly opted in

6. Asset lifecycle and cleanup
- [x] Add helper for Live Photo movie temp URLs
- [x] Remove stale temp files on cancel/retake/failure
- [x] Keep accepted capture files available to consumers

7. Testing and docs
- [ ] Keep all existing tests passing
- [ ] Add tests for opt-in mode, fallback, callbacks, and cleanup
- [ ] Update README/examples with no-migration path + opt-in sample

## Risks and Guardrails
- Risk: Breaking exhaustive `switch`es in adopter apps.
  - Guardrail: Do not add new `CameraOutputType` cases.
- Risk: Unsupported-device crashes.
  - Guardrail: Capability checks + automatic still fallback.
- Risk: Temp-file leaks.
  - Guardrail: Centralized file management and cleanup hooks.

## Progress Log
- 2026-02-07: Created `live-photo-plan.md` with milestone checklist and compatibility contract.
- 2026-02-07: Implemented additive Live Photo API (`PhotoCaptureMode`, `setPhotoCaptureMode`, `onLivePhotoCaptured`, `MCameraLivePhoto`, additive `MCameraMedia` getters/data).
- 2026-02-07: Implemented Live Photo capture path in `CameraManagerPhotoOutput` with capability checks, in-flight pairing, and still-photo fallback.
- 2026-02-07: Wired callback integration so existing `onImageCaptured` remains unchanged and Live Photo callback is additive-only.
- 2026-02-07: Added temp-file lifecycle helpers and cleanup hooks for cancel/retake/replacement flows.
- 2026-02-07: Added initial tests for `PhotoCaptureMode` state and temp-file cleanup behavior.
- 2026-02-07: Validation blockers encountered: local `swift build`/`swift test` are not currently runnable in this environment due SwiftPM platform/cache/toolchain constraints.

## Next Step
Finish Milestone 7 by validating in a working iOS build/test environment and updating README/examples with migration-free and opt-in usage docs.
