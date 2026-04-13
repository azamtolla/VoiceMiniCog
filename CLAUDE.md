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

## Multi-Agent File Ownership

This project uses multiple AI agents (Claude Code, Cowork, Cursor). Clinical-critical
files require explicit clinical-impact reasoning before modification — a passing build
does not validate clinical correctness.

### Cowork / other agents may freely edit

- `VoiceMiniCogTests/` — test files
- `docs/` — documentation, handoffs, specs
- `scripts/`, `*.py`, `*.sh` — build and utility scripts
- `README.md`, `CLAUDE.md` (non-ownership sections only)
- `Assets.xcassets/` — design assets
- Build configuration files other than `project.pbxproj`

### Claude Code exclusive — do not modify without clinical reasoning

Files in this list contain clinically-validated implementations anchored to the
published Qmci protocol (O'Caoimh 2012, Appendix 1). Reverting changes here without
understanding the clinical reasoning produces silently-incorrect patient scores.
Changes to these files require explicit clinical-impact reasoning, not just
build-passes-and-looks-OK validation. If a build issue appears to require touching
these files, the correct response is to diagnose root cause, not revert to a
previous version.

- `Views/AvatarAssessment/Phases/*.swift` — all phase views (clock drawing, verbal fluency, word registration, word recall, story recall, welcome, QA)
- `Models/QmciModels.swift` — scoring formulas, subscale weights, normative cutoffs, Codable persistence
- `Theme/LeftPaneSpeechCopy.swift` — verbatim examiner scripts validated against Qmci protocol
- `Services/VerbalFluencyScorer.swift` — animal lexicon, compound-name dedup, repetition tracking
- `Services/WordRecallScorer.swift` — delayed recall scoring with semantic substitution detection
- `Views/TavusCVIView.swift` — WebRTC lifecycle, avatar speech bridge, mic mute control
- `ContentView.swift` — routing entry point, PHI persistence trigger, Tavus session lifecycle
