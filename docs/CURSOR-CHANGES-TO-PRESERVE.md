# Critical: Cursor Changes That Must Be Preserved

## Problem
The app is currently running a stale build. Several phase views were updated by Cursor with epoch-gated speech synchronization, but the running app shows the OLD behavior (e.g., Word Registration chips revealing before avatar finishes speaking, listening state activating too early).

**You MUST NOT overwrite these changes during the clock drawing redesign.**

## Commits containing the Cursor fixes (already on v1-pilot)

### Commit `7d30199` — epoch-gated speech sync across 4 phase views:
- `QAPhaseView.swift` — Added `questionSpeechEpoch` counter + `finishQuestionSpeechIfNeeded(epoch:)` so late `avatarDoneSpeaking` events from a previous question can't unlock the wrong question's listening state. Old hardcoded `0.08s/word + 1.5s` fallback replaced with `0.38s/word + 6.0s`.
- `StoryRecallPhaseView.swift` — Added `recallPromptSpeechEpoch` + `unlockStoryRecallListeningIfNeeded(epoch:)`. Fixed bug where `setAvatarListening()` was called when transitioning to recalling phase even though avatar was about to speak the recall prompt (now correctly calls `setAvatarSpeaking()` first).
- `WordRecallPhaseView.swift` — Added `recallPromptSpeechEpoch` + `unlockRecallListeningIfNeeded(epoch:)`. Old fixed 3.5s delay replaced with actual `avatarDoneSpeaking` notification.
- `WordRegistrationPhaseView.swift` — Added **dual gate** (`chipsRevealCompleteForGate` AND `avatarPlaybackCompleteForGate`) via `maybeBeginListeningPauseForCurrentTrial()`. Listening pause now requires BOTH chip animation completion AND avatar audio completion. Fallback: `0.32s/word + 12.0s`.

### Commit `546caf0` — same files plus metadata (`.claude/`, `.remember/` etc were accidentally staged)

### Commits `9038d11`, `c29f53e`, `7971cc2` — Claude Code enhancements:
- `WelcomePhaseView.swift` — Dynamic `SpeechTimingModel` that computes reveal delays from script text (0.47s/word, per-boundary pauses). SSML `introScriptForEcho` for Tavus-friendly pacing. `.tavusDailyRoomJoined` listener to replay echo if first one fired before Tavus was ready.
- `c29f53e` — Mute patient mic before echo to prevent pre-speech noise.

## What to do
1. Before modifying ANY of the 4 phase views above, verify the epoch-gate pattern is still intact.
2. The clock drawing redesign (AvatarZoneView refactor) should NOT touch phase view internals.
3. After the redesign is complete, rebuild and verify all phases still work:
   - Welcome: rows reveal in sync with avatar speech
   - Word Registration: chips reveal one-by-one, listening only after BOTH chips done AND avatar done
   - Orientation (QA): listening indicator only after avatar finishes question
   - Story Recall: avatar speaks recall prompt before switching to listening
   - Word Recall: listening unlocks after avatar finishes delayed recall prompt
