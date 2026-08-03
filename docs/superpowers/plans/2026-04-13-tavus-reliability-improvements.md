# Tavus Reliability Improvements

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve Tavus CVI reliability for clinical cognitive assessments by adding interrupt-on-phase-transition, mid-session disconnect resilience, and missing context coverage.

**Architecture:** Four independent changes to the existing Tavus bridge pipeline: (1) expose `avatarInterrupt()` and call it on every phase entry to prevent stale echo overlap, (2) add connection-state notifications and a mid-session disconnect overlay in AvatarZoneView, (3) add missing context overwrite to CompletionPhaseView, (4) forward nonfatal-error events from JS to Swift for diagnostics.

**Tech Stack:** Swift/SwiftUI, WKWebView, Daily.js, NotificationCenter

---

### Task 1: Add `avatarInterrupt()` Global Helper

**Files:**
- Modify: `VoiceMiniCog/Views/TavusCVIView.swift`

- [ ] **Step 1: Add notification name and global helper**

In `TavusCVIView.swift`, add the interrupt notification name alongside the existing ones (after `tavusMicMuteRequest`):

```swift
static let tavusInterruptRequest = Notification.Name("tavusInterruptRequest")
```

Add the global helper function after `avatarSetMicMuted` (around line 625):

```swift
/// Interrupt the avatar — stops current speech and clears the echo queue.
/// Call this at the start of every phase `onAppear` to prevent stale echoes
/// from the previous phase overlapping with the new phase's first instruction.
func avatarInterrupt() {
    NotificationCenter.default.post(
        name: .tavusInterruptRequest,
        object: nil
    )
}
```

- [ ] **Step 2: Add interrupt observer in Coordinator**

In the Coordinator class, add a property alongside the existing observers:

```swift
private var interruptObserver: NSObjectProtocol?
```

In `init()`, add the observer after the `muteObserver` block:

```swift
interruptObserver = NotificationCenter.default.addObserver(
    forName: .tavusInterruptRequest,
    object: nil,
    queue: .main
) { [weak self] _ in
    self?.sendInterrupt()
}
```

In `deinit`, add cleanup:

```swift
if let observer = interruptObserver {
    NotificationCenter.default.removeObserver(observer)
}
```

- [ ] **Step 3: Build and verify**

Run: `cd /Users/azamtolla/Documents/MercyCognitiveApp/VoiceMiniCog && xcodebuild build -project VoiceMiniCog.xcodeproj -scheme VoiceMiniCog -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' -quiet 2>&1 ; echo "EXIT=$?"`

Expected: `EXIT=0`

---

### Task 2: Add Interrupt-Before-Echo on All Phase Entries

**Files:**
- Modify: `VoiceMiniCog/Views/AvatarAssessment/Phases/WelcomePhaseView.swift`
- Modify: `VoiceMiniCog/Views/AvatarAssessment/Phases/QAPhaseView.swift`
- Modify: `VoiceMiniCog/Views/AvatarAssessment/Phases/WordRegistrationPhaseView.swift`
- Modify: `VoiceMiniCog/Views/AvatarAssessment/Phases/ClockDrawingPhaseView.swift`
- Modify: `VoiceMiniCog/Views/AvatarAssessment/Phases/VerbalFluencyPhaseView.swift`
- Modify: `VoiceMiniCog/Views/AvatarAssessment/Phases/StoryRecallPhaseView.swift`
- Modify: `VoiceMiniCog/Views/AvatarAssessment/Phases/WordRecallPhaseView.swift`
- Modify: `VoiceMiniCog/Views/AvatarAssessment/Phases/CompletionPhaseView.swift`

- [ ] **Step 1: Add `avatarInterrupt()` as first action in each phase's onAppear**

For each file, add `avatarInterrupt()` as the FIRST line inside the `.onAppear` block (or the `onPhaseAppear()` method for WordRecallPhaseView), BEFORE `avatarSetAssessmentContext` / `avatarSetContext` / `avatarSpeak`. This ensures any stale echo from the previous phase is cut off before the new phase starts.

Pattern for most phases (example: ClockDrawingPhaseView):
```swift
.onAppear {
    avatarInterrupt()  // ← ADD THIS LINE
    avatarSetAssessmentContext(clockDrawingTavusBehaviorContext)
    avatarSpeak(LeftPaneSpeechCopy.clockDrawingInstruction)
    // ... rest of onAppear
}
```

**EXCEPTION: WelcomePhaseView** — do NOT add `avatarInterrupt()` here. Welcome is the first phase; there is no prior speech to interrupt. An interrupt on welcome entry would fight with the first-echo unmute logic in TavusBridge.

Phases to modify (7 total, NOT welcome):
1. QAPhaseView — first line of `.onAppear`
2. WordRegistrationPhaseView — first line of `.onAppear`
3. ClockDrawingPhaseView — first line of `.onAppear`
4. VerbalFluencyPhaseView — first line of `.onAppear`
5. StoryRecallPhaseView — first line of `.onAppear`
6. WordRecallPhaseView — first line of `onPhaseAppear()` method
7. CompletionPhaseView — first line of `.onAppear`

- [ ] **Step 2: Build and verify**

Run: `cd /Users/azamtolla/Documents/MercyCognitiveApp/VoiceMiniCog && xcodebuild build -project VoiceMiniCog.xcodeproj -scheme VoiceMiniCog -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' -quiet 2>&1 ; echo "EXIT=$?"`

Expected: `EXIT=0`

---

### Task 3: Add Missing Context to CompletionPhaseView

**Files:**
- Modify: `VoiceMiniCog/Views/AvatarAssessment/Phases/CompletionPhaseView.swift`

- [ ] **Step 1: Add context overwrite before avatarSpeak**

In `CompletionPhaseView.swift`, in the `.onAppear` block (around line 58), add context AFTER `avatarInterrupt()` (from Task 2) and BEFORE `avatarSpeak`:

```swift
.onAppear {
    avatarInterrupt()
    withAnimation(AssessmentTheme.Anim.contentEnter.delay(0.05)) {
        contentVisible = true
    }
    avatarSetAssessmentContext("The cognitive assessment is now complete. You are delivering a brief closing thank-you. Do not ask any questions or provide any feedback about performance. Simply thank the patient for their participation.")
    avatarSpeak(LeftPaneSpeechCopy.closingThankYou)
}
```

- [ ] **Step 2: Build and verify**

Run: same build command. Expected: `EXIT=0`

---

### Task 4: Forward `nonfatal-error` Events to Swift

**Files:**
- Modify: `VoiceMiniCog/Resources/TavusBridge.html`

- [ ] **Step 1: Forward nonfatal-error to Swift**

In `TavusBridge.html`, find the `nonfatal-error` handler (around line 286-288):

```javascript
callObject.on('nonfatal-error', (evt) => {
    log('Non-fatal error: ' + JSON.stringify(evt).substring(0, 200));
});
```

Change to:

```javascript
callObject.on('nonfatal-error', (evt) => {
    log('Non-fatal error: ' + JSON.stringify(evt).substring(0, 200));
    notifySwift('error', {message: 'nonfatal-error: ' + JSON.stringify(evt).substring(0, 200)});
});
```

- [ ] **Step 2: Build and verify**

Run: same build command. Expected: `EXIT=0`

---

### Task 5: Add Mid-Session Connection State Notifications

**Files:**
- Modify: `VoiceMiniCog/Views/TavusCVIView.swift`

- [ ] **Step 1: Add connection-lost notification name**

In the `Notification.Name` extension (around line 19), add:

```swift
/// Fired when the Daily WebRTC connection drops mid-session (left-meeting or fatal error)
static let tavusConnectionLost = Notification.Name("tavusConnectionLost")
```

- [ ] **Step 2: Post connection-lost from Coordinator**

In the Coordinator's `userContentController` message handler, update the `"left"` case:

```swift
case "left":
    print("[TavusCVI] Left Daily room")
    cviLog.info("Left Daily room")
    onAvatarEvent?(.left)
    NotificationCenter.default.post(name: .tavusConnectionLost, object: nil)
```

Update the `"error"` case — after the benign filter, before `onAvatarEvent`:

```swift
case "error":
    let msg = json["message"] as? String ?? "Unknown"
    if msg.hasPrefix("network-connection:"), msg.contains("\"event\":\"connected\"") {
        cviLog.debug("Bridge (network ok): \(msg, privacy: .public)")
        return
    }
    print("[TavusCVI] Bridge error: \(msg)")
    cviLog.error("Bridge error: \(msg, privacy: .public)")
    // Fatal errors and network interruptions signal potential connection loss
    if !msg.hasPrefix("nonfatal-error:") {
        NotificationCenter.default.post(
            name: .tavusConnectionLost,
            object: nil,
            userInfo: ["message": msg]
        )
    }
    onAvatarEvent?(.error(msg))
```

- [ ] **Step 3: Build and verify**

Run: same build command. Expected: `EXIT=0`

---

### Task 6: Add Mid-Session Disconnect Overlay to AvatarZoneView

**Files:**
- Modify: `VoiceMiniCog/Views/AvatarAssessment/AvatarZoneView.swift`

- [ ] **Step 1: Add connection-lost state tracking**

Add a `@State` property to AvatarZoneView:

```swift
@State private var isConnectionLost = false
```

Add a notification observer in `.onAppear` of the AvatarZoneView body (or use `.onReceive`):

```swift
.onReceive(NotificationCenter.default.publisher(for: .tavusConnectionLost)) { _ in
    isConnectionLost = true
}
```

- [ ] **Step 2: Add disconnect overlay in the ZStack**

Inside AvatarZoneView's body `ZStack`, add a new layer after the existing content (after the state label, before the closing brace). Use the same visual style as `avatarRecoveryView`:

```swift
// 6. Mid-session connection lost overlay
if isConnectionLost {
    VStack(spacing: 12) {
        Image(systemName: "wifi.slash")
            .font(.system(size: 32))
            .foregroundStyle(isClockDrawing ? Color(hex: "#6B7280") : Color.white.opacity(0.6))
        Text("Avatar connection lost")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(isClockDrawing ? Color(hex: "#374151") : Color.white.opacity(0.7))
        Text("The assessment can continue without the avatar.")
            .font(.system(size: 13))
            .foregroundStyle(isClockDrawing ? Color(hex: "#6B7280") : Color.white.opacity(0.5))
            .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background((isClockDrawing ? Color.white : Color.black).opacity(0.85))
    .transition(.opacity)
    .animation(.easeInOut(duration: 0.3), value: isConnectionLost)
}
```

- [ ] **Step 3: Build and verify**

Run: same build command. Expected: `EXIT=0`

---

### Task 7: Final Build Verification

- [ ] **Step 1: Clean build**

Run: `cd /Users/azamtolla/Documents/MercyCognitiveApp/VoiceMiniCog && xcodebuild build -project VoiceMiniCog.xcodeproj -scheme VoiceMiniCog -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' -quiet 2>&1 ; echo "EXIT=$?"`

Expected: `EXIT=0`
