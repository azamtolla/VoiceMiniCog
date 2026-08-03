# Handoff

## State
Shipped & building (`** BUILD SUCCEEDED **` on iPad 13 inch sim): (1) Tavus persona 5-layer PATCH (LLM gemini-2.5-flash, TTS cartesia sonic-3, perception raven-1 with 3 ambient queries) in `Services/TavusService.swift`; (2) `ClockStrokeEvent` v2 biomarkers (strokeId, startTime, endTime, pauseBefore, isCorrection, pressureSamples, boundingBox, markOverlaps) + Codable backwards-compat in `Models/QmciModels.swift`; (3) optional Done button + endPhaseEarly() in legacy `ClockDrawingPhaseView.swift`; (4) Path-1 additive PencilKit module: `Views/AvatarAssessment/Phases/CDTCanvasView.swift` (CDTCanvasView + CDTCanvasCard) + `CDTBiomarkerBridge` + `CDTStroke` struct + runtime flag `voiceMiniCog.use_pencilkit_cdt`. `Services/ElevenLabsService.swift` deleted (was dead code). 4 pbxproj edits made manually.

## Next
1. Two surgical PencilKit deltas (~30 min): add `PencilStrokeSource` enum + optional `pencilSource` field to `ClockStrokeEvent`; in `CDTCanvasView` Coordinator capture `point.altitude`/`point.azimuth` and switch `drawingPolicy` to `.pencilOnly` when Pencil present; extend `CDTBiomarkerBridge` to populate `pencilSource`. Keep suffix-iteration over `drawing.strokes` (don't rebuild full array per spec — preserves wall-clock timing).
2. Test Path-1 flip on real iPad with Pencil — `UserDefaults.standard.set(true, forKey: "voiceMiniCog.use_pencilkit_cdt")` — confirm pressure≠0.5 and isCorrection flips on overlap.
3. Session 3 reduced scope: `Services/FHIRExport.swift` (LOINC 72172-0 Observation JSON, UIPasteboard) + Copy FHIR JSON button on existing `PCPReportView.swift`. Raven perception stays log-only — no UI surfacing.

## Context
- Standing rule (in CLAUDE.md): grep call sites BEFORE any service-level refactor. Three specs this session were built on wrong premises (ElevenLabs live calls, PencilKit already present, `/api/cdt/score` endpoint). Always run grep first.
- Pipecat backend is FROZEN at idea-level pending grep-first audit of `backend/avatar-gateway/gateway.py`. Memory note saved at `~/.claude/projects/-Users-azamtolla/memory/project_voiceminicog_pipecat_freeze.md`.
- Mercy navy is `MCDesign.Colors.primary700`, NOT `DesignSystem.Color.primary700` (real namespace is `MCDesign`).
- HIPAA: `ContentView.swift:274 avatarSetContext(header)` sends patient `displayName` to Tavus — needs BAA confirmation or scrubbing. Echo helpers themselves are clean.
- Replica interruptibility kept at "low" not "verylow" (per Tavus docs guidance + clinical reasoning at `TavusService.swift:404-407`).
