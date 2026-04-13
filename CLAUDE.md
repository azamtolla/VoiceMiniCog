# CLAUDE.md — VoiceMiniCog

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

**DO NOT** use the Python `pbxproj` library (`from pbxproj import XcodeProject`) to add or remove files. It corrupts file reference IDs — it wraps them in `"'...'"` nested quotes that Xcode can't parse, silently breaking the build.

**Safe approach for removing dead files:**
```python
# Read the raw text, find PBXFileReference entries for missing .swift files,
# collect their IDs, then filter out all lines containing those IDs.
# See the remove-dead-refs pattern used in the 2026-04-12 cleanup session.
```

**Safe approach for adding files:** Use `pbxproj` library's `add_file()` ONLY (it generates valid new IDs). But do NOT call `project.save()` afterward if the project already has library-format IDs — the save mangles existing entries. Instead, add via Xcode IDE or by manually inserting PBXFileReference + PBXBuildFile entries matching the existing ID format.

**Tech debt:** The project file contains mnemonic-style IDs (e.g., `COPY0001...`, `CARD0001...`, `SESS0001...`) from prior `pbxproj` library additions. These work but are non-standard. Normalizing to 24-char hex UUIDs is tracked for a future cleanup pass.

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
