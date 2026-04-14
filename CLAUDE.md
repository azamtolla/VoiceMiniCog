# CLAUDE.md — VoiceMiniCog

## Tech Stack

- iOS 16+, SwiftUI + UIKit
- Daily Client iOS SDK (https://github.com/daily-co/daily-client-ios) v0.37.0 via SPM
- Tavus CVI REST API (https://tavusapi.com/v2)
- Architecture: @Observable, async/await, NotificationCenter for avatar events

## Daily SDK Key Classes

- `CallClient` — join/leave rooms, send app messages, manage inputs (@MainActor)
- `VideoView` — render participant video tracks natively (UIView)
- `CallClientDelegate` — receive participant/track/appMessage events
- `VideoTrack` — raw video track bound to VideoView
- `sendAppMessage(json:to:)` — send Data to `.all` or `.participant(id)` for Tavus Interactions Protocol
- `appMessageAsJson` — delegate method name for receiving app messages (NOT `appMessageAsData`)
- `setInputEnabled(.microphone, Bool)` — toggle mic on/off

## Tavus Integration Rules

- POST to /v2/conversations to get conversation_url before joining Daily room
- Use `sendAppMessage` with JSON matching Tavus Interactions Protocol:
  - `conversation.echo` — make replica speak exact text (bypass LLM)
  - `conversation.respond` — inject text as LLM response (faster than echo)
  - `conversation.overwrite_llm_context` — set persona/phase context
  - `conversation.interrupt` — stop replica mid-speech
  - `conversation.sensitivity` — adjust turn-taking thresholds
- Events received via `callClient(_:appMessageAsJson:from:)` delegate:
  - `conversation.replica.started_speaking` / `stopped_speaking`
  - `conversation.user.started_speaking` / `stopped_speaking`
  - `system.replica_joined` / `system.replica_present`
- Tavus replica is always a non-local participant
- POST to /v2/conversations/{id}/end on session end
- NEVER use WKWebView for Tavus — audio session conflicts, user agent issues, Web Audio unlock hacks

## Key Architecture Files

- `Services/DailyCallManager.swift` — CallClient wrapper with echo queue, auto-interrupt, mic gating
- `Services/TavusService.swift` — REST API create/end conversation, pre-warm lifecycle
- `Views/DailyVideoView.swift` — UIViewRepresentable VideoView wrapper
- `Views/TavusHelpers.swift` — Notification names + helper functions (avatarSpeak, avatarSetContext, etc.)
- `Services/AudioSessionManager.swift` — AVAudioSession .playAndRecord/.videoChat config
- `Services/KeychainHelper.swift` — Secure API key storage

## Avatar Communication Pattern

Phase views communicate with the avatar via NotificationCenter helper functions:
- `avatarSpeak(text)` — echo exact text
- `avatarRespond(text)` — respond via LLM bypass (faster)
- `avatarSetContext(context)` — update persona context
- `avatarSetAssessmentContext(context)` — context + examiner-never-correct rule
- `avatarSetMicMuted(muted)` — toggle patient mic
- `avatarInterrupt()` — stop speech + clear echo queue
Phase views NEVER call DailyCallManager directly — always through these helpers.

## Testing Rules

- Project: plain `.xcodeproj` (no workspace). Scheme: `VoiceMiniCog`.
- Simulator: "Ipad 13 inch sim" (iPad Pro 13-inch M5, iOS 26.2). Boot once: `xcrun simctl boot "Ipad 13 inch sim"`.
- Never use iPhone 16 simulator (not installed).
- Always `cd /Users/azamtolla/Documents/MercyCognitiveApp/VoiceMiniCog` before running xcodebuild.
- Always pass `-project VoiceMiniCog.xcodeproj` explicitly (avoids "Supported platforms ... is empty" warning).
- Always use `-quiet` to reduce output noise.

### Fast incremental tests (preferred)

```
cd /Users/azamtolla/Documents/MercyCognitiveApp/VoiceMiniCog && \
xcodebuild test-without-building \
  -project VoiceMiniCog.xcodeproj \
  -scheme VoiceMiniCog \
  -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' \
  -only-testing:VoiceMiniCogTests/QmciScoringTests \
  -quiet 2>&1 | tail -120
```

If this fails with `Failed to create a bundle instance` or `no build products`, run build-for-testing first:

```
cd /Users/azamtolla/Documents/MercyCognitiveApp/VoiceMiniCog && \
xcodebuild build-for-testing \
  -project VoiceMiniCog.xcodeproj \
  -scheme VoiceMiniCog \
  -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' \
  -quiet 2>&1 | tail -40
```

Then re-run `test-without-building`. Subsequent runs reuse the cached build via Xcode's default DerivedData.

## Editing project.pbxproj

Agents may directly edit `project.pbxproj` to add or remove file references. Use raw text insertion of PBXFileReference + PBXBuildFile + PBXGroup entries with 24-character hex UUIDs matching the existing format in the file.

**DO NOT** use the Python `pbxproj` library (`from pbxproj import XcodeProject`) — it corrupts file reference IDs by wrapping them in nested quotes.

**Safe approach:** Read the pbxproj, find the correct PBXGroup and PBXBuildFile sections, generate new 24-char hex UUIDs, and insert entries following the existing format. Always build after editing to verify the project file is valid.

## Multi-agent editing (Claude Code and Cursor)

This project uses multiple AI agents (Claude Code, Cursor, and others). **Cursor and
Claude Code are both authorized to edit any file in the project**, including clinical
surfaces and Tavus bridge code. There is no utility-only allowlist; the same rules apply
to every agent.

**Shared discipline (all agents):**

- Diagnose root cause before applying fixes; do not revert clinically validated work
  without understanding the reasoning behind it.
- Do not bypass the published Qmci protocol assumptions encoded in scoring, scripts, and
  examiner copy (O'Caoimh 2012, Appendix 1). A passing build does not validate clinical
  correctness.
- When two agents work on the same file in close succession, the later agent must verify
  the earlier agent’s work is intact (e.g. grep for known markers, re-read critical paths)
  before making further changes.

**Clinical-validity surface** — Phase views (`Views/AvatarAssessment/Phases/*.swift`),
scorers (`Services/VerbalFluencyScorer.swift`, `Services/WordRecallScorer.swift`),
`Models/QmciModels.swift`, `Theme/LeftPaneSpeechCopy.swift`, Tavus/session wiring
(`Views/TavusCVIView.swift`, `ContentView.swift`), and any other code tied to administration
or scoring: **any change must include explicit reasoning about clinical impact**, not only
“build passes” validation. If a build issue appears to require touching these areas, the
correct response is to diagnose root cause, not revert to a previous version without
understanding why it was written that way.

**Policy note:** As of April 12, 2026, Cursor was promoted from a utility-only allowlist to
full project access per clinician decision (Tolla). Earlier restrictions were a response to
a specific Cowork incident; that incident’s resolution and Cursor’s subsequent behavior
demonstrated reliable adherence to diagnostic-first discipline. Both agents now share full
project access under the same rules.
