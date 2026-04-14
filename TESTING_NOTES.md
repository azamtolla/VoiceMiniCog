# TESTING_NOTES.md — v1-pilot Fix Verification

Physical iPad testing guide for all 15 fixes in PR "Fix: QMCI assessment flow, scoring, and Tavus pipeline".

---

## Fix 1: Clock Drawing PNG Lost on Early "Done Drawing"

**File:** `ClockDrawingPhaseView.swift`

1. Start an assessment and reach the clock drawing phase.
2. Draw a few strokes on the canvas.
3. Tap **Done Drawing** before the 180-second timer expires.
4. Complete the assessment and open the PCP report.
5. **Verify:** The clock drawing image appears in the report (not blank/missing).

---

## Fix 2: Tavus Conversation Never Explicitly Ended

**File:** `ContentView.swift`

1. Start an assessment with a live Tavus conversation.
2. Complete the assessment normally (tap "Return to Home" on the completion screen).
3. Check the Tavus dashboard — the conversation should show as **ended**, not still active.
4. Repeat: start an assessment and tap **End Session** mid-flow.
5. **Verify:** The conversation is ended on the Tavus dashboard in both cases.

---

## Fix 3: Clock Timer 180s vs QMCI Model 60s

**Files:** `ClockDrawingPhaseView.swift`, `QmciModels.swift`, `QMCIAvatarContext.swift`

1. Reach the clock drawing phase.
2. Observe the timer runs for **180 seconds** (3 minutes, per Shulman CDT protocol).
3. Check the avatar's spoken instruction includes "up to three minutes".
4. **Verify:** No references to "60 seconds" remain in the clock drawing flow. The `durationSeconds` model field is now 180.

---

## Fix 4: Orientation Scoring — Wire SpeechService

**Files:** `QAPhaseView.swift`, `ResponseCheckers.swift`

1. Reach the orientation phase.
2. Answer orientation questions verbally (date, month, year, day of week, place).
3. **Verify:** The app auto-scores answers via ASR transcript matching (green checkmark for correct, red X for incorrect) rather than requiring manual clinician scoring for every question.
4. Also verify manual override still works — tap the score to change it.

---

## Fix 5: Story Recall — Add Ceiling Timer

**File:** `StoryRecallPhaseView.swift`

1. Reach the story recall phase.
2. After the avatar finishes reading the story, a 60-second recall timer should start.
3. Wait the full 60 seconds without speaking.
4. **Verify:** The phase auto-advances when the timer expires (does not hang indefinitely waiting for the patient to finish).

---

## Fix 6: Word Registration Substring Matching

**File:** `ResponseCheckers.swift`

1. Reach word registration (the 5-word recall list).
2. Say a word that is a substring of a target word (e.g., say "arm" when the target is "army").
3. **Verify:** "arm" does NOT match "army" — the scorer uses token-level word boundary matching, not substring `contains()`.
4. Say the correct word "army".
5. **Verify:** "army" matches correctly.

---

## Fix 7: API Key — Migrate to Keychain

**Files:** `KeychainHelper.swift` (new), `TavusService.swift`, `ContentView.swift`

1. If upgrading from a prior build: open Settings and verify your Tavus API key is still present (migrated from UserDefaults to Keychain automatically).
2. Change the API key in Settings, close and reopen the app.
3. **Verify:** The key persists across app restarts.
4. On a fresh install: enter an API key in Settings, force-quit, reopen.
5. **Verify:** The key is retained (stored in Keychain, not UserDefaults).

---

## Fix 8: Verbal Fluency Scorer — Handle ASR Revisions

**File:** `VerbalFluencyScorer.swift`

1. Reach the verbal fluency phase ("name as many animals as possible").
2. Speak quickly — ASR may revise earlier words as it receives more audio context.
3. **Verify:** The animal count does not decrease when ASR revises a transcript segment. Already-credited animals stay credited even if the transcript temporarily shrinks.

---

## Fix 9: Simulator Debug Fixture Mode

**File:** `SpeechService.swift`

1. In Xcode, add launch argument `-speechFixtures YES` to the scheme.
2. Run in the simulator.
3. Reach any ASR-dependent phase (orientation, verbal fluency, word recall).
4. **Verify:** A sample transcript is injected after ~1.5 seconds, allowing the phase to progress without a physical microphone.
5. Remove the launch argument and run on a real device.
6. **Verify:** Fixture mode is disabled — real microphone input is used.

---

## Fix 10: CompletionPhaseView Notification Race

**File:** `CompletionPhaseView.swift`

1. Complete an assessment and reach the completion screen.
2. **Verify:** The "Return to Home" and "View Report" buttons appear only after the avatar finishes speaking the completion message.
3. The buttons should NOT appear prematurely due to a stale `avatarDoneSpeaking` notification from a prior phase (e.g., story recall's closing utterance).

---

## Fix 11: Dual Phase Enum Documentation

**Files:** `Phase.swift`, `AvatarLayoutManager.swift`

1. **Code review only** — no runtime behavior change.
2. Open both files and verify the doc comments explain:
   - `Phase` = persistence/routing enum (includes `.intake`, `.scoring`, `.report`)
   - `AssessmentPhaseID` = avatar layout state machine (includes `.welcome`, `.qdrs`, `.phq2`)
   - The two intentionally diverge; mapping happens in `AvatarAssessmentCanvas` and `ContentView`.

---

## Fix 12: Echo Watchdog — Tighten + UI Indicator

**File:** `TavusBridge.html`

1. This is difficult to test without simulating a dropped `stopped_speaking` event.
2. If you can intercept/block Tavus events in Safari Web Inspector:
   - Queue a long-form echo (e.g., welcome SSML block).
   - Block the `stopped_speaking` event from firing.
   - **Verify:** After ~45 seconds (not 120), the watchdog fires, releases the echo slot, and a `echoWatchdogFired` event is sent to Swift.
3. Normal operation: verify that welcome and instruction echoes complete normally without the watchdog firing (check console logs for absence of "Echo watchdog" messages).

---

## Fix 13: Pre-warm Orphaned Conversations

**File:** `TavusService.swift`

1. Start the app, let it pre-warm a Tavus conversation (Home screen).
2. Force-quit the app (swipe up from app switcher) before starting the assessment.
3. Reopen the app.
4. **Verify:** Console logs show `[Tavus] Ending orphaned pre-warm conversation: <id>` — the stale conversation is cleaned up before a new one is created.
5. Check the Tavus dashboard — the orphaned conversation should be ended.

---

## Fix 14: No Stroke Count Minimum — Confirmation Dialog

**File:** `AvatarAssessmentCanvas.swift`

1. Reach the clock drawing phase.
2. **Without drawing anything**, tap **Done Drawing**.
3. **Verify:** An alert appears: "No Drawing Detected — The patient hasn't drawn anything yet. Are you sure you want to skip the clock drawing test?"
4. Tap "Continue Drawing" — verify you return to the canvas.
5. Tap "Done Drawing" again (still no strokes) and tap "Skip Clock Drawing" — verify the phase advances.
6. Now restart: draw at least one stroke, then tap "Done Drawing".
7. **Verify:** No alert appears — the phase advances immediately.

---

## Fix 15: Caregiver TavusCVIView Instance Documentation

**File:** `CaregiverAssessmentView.swift`

1. **Code review only** — no runtime behavior change.
2. Open the file and verify the header comment explains:
   - CaregiverAssessmentView creates its own TavusCVIView instance.
   - Both instances must not be in the hierarchy simultaneously.
   - `warmTavusWebViewOnHome` is set to false while caregiver is active.
3. Optionally: start a caregiver assessment, then go back and start a cognitive assessment — verify no WebView conflicts or crashes.
