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
