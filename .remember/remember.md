# Handoff

## State
I fixed the avatar crash (missing NSCameraUsageDescription in project.pbxproj), resolved Tavus 402 credits issue (user upgraded plan), updated persona `pc64945f7e08` to be reactive (waits for phase cues instead of running autonomously), built a custom Daily JS bridge (`VoiceMiniCog/Resources/TavusBridge.html`) replacing the prebuilt Daily URL for full `sendAppMessage` control, wired phase transitions in `AvatarAssessmentCanvas.swift` to send context updates via NotificationCenter → TavusCVIView coordinator → JS, and rewrote `AvatarZoneView.swift` with council-informed premium clinical design (glass frame, breathing animation, waveform bars, status dot, Mercy badge, phase-colored accent ring).

## Next
1. **Test on physical iPad** — user has a presentation. Verify: avatar loads, greeting plays, phase context updates reach avatar, new AvatarZoneView renders correctly.
2. **Auto-join may need tuning** — the new TavusBridge.html uses `Daily.createCallObject()` directly (no prebuilt lobby), so the old JS auto-join hack is gone. Verify the avatar video actually renders in the custom HTML page.
3. **Council API keys expired** — OPENAI_API_KEY, GEMINI_API_KEY, OPENROUTER_API_KEY are in ~/.zshrc but not loaded in Claude's env. Run `source ~/.zshrc` before council calls.

## Context
- Tavus API key: `ad59dab220804a8f81f07e21e78b5ba6`, persona: `pc64945f7e08`, replica: `rf4e9d9790f0` (Anna - Professional)
- Simulator name is `Ipad 13 inch sim` (custom), physical iPad ID: `00008122-0001650E1E6B801C`
- TavusBridge.html was added to Xcode project via `pbxproj` Python library — verify it stays in Copy Bundle Resources if project file is regenerated
