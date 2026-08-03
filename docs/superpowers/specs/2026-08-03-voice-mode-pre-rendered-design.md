# Voice Mode — Pre-Rendered Realistic Voice (Design)

**Date:** 2026-08-03
**Status:** Draft — pending Tolla review
**Authors:** Tolla + Claude
**Supersedes:** nothing (additive mode; Tavus avatar path untouched)

## 1. Goal

Replace the Tavus video avatar with a **realistic voice guide** that speaks every
assessment script and listens to patient answers, with:

- **Maximum voice realism** — rendered offline with a top-quality ElevenLabs model,
  unconstrained by real-time latency budgets
- **Minimal latency** — <50 ms local clip playback vs the avatar pipeline's 600–700 ms
- **Zero runtime cloud dependency** — no Tavus, no Daily, no RunPod GPU, no network
- **Perfect standardization** — every patient hears bit-identical audio for every
  script, stronger psychometrically than any live TTS

### Non-goals

- No change to any scoring surface, threshold, or clinical display (CDS posture unchanged)
- No generative speech at runtime (echo-vessel discipline is retained: the voice can
  only play clips whose text was authored in `LeftPaneSpeechCopy` / the behavioral guide)
- No removal of the Tavus path — it remains selectable when configured

## 2. Why this is architecturally cheap (verified 2026-08-03)

| Fact | Evidence |
|---|---|
| All clinical speech is static, PHI-free script text | `Theme/LeftPaneSpeechCopy.swift` (47 constants/functions); CLAUDE.md HIPAA table — echo call sites pass only static constants / canonical stimuli |
| The avatar never generates speech | tavus-persona-configuration.md: "pure text-to-speech vessel", echo-only system prompt v2 |
| Listening is ALREADY on-device | `VerbalFluencyPhaseView:44`, `WordRecallPhaseView:50`, `WordRegistrationPhaseView:68` each use `SpeechService` (SFSpeechRecognizer + AVAudioEngine); Tavus `conversation.utterance` events are logged and ignored (`DailyCallManager.swift:1217`) |
| Phase views are transport-agnostic | They speak via NotificationCenter helpers (`avatarSpeak` → `.tavusEchoRequest`), never call DailyCallManager directly (CLAUDE.md rule) |
| Only dynamic scripts are finite compositions | `wordRegistrationEcho(words:trial:)` interpolates fixed word sets (post-Plan-1: Set 1 only) with SSML `<break>` tags — enumerable variants |

Runtime deltas vs today: **swap the mouth; keep everything else.**

## 3. Architecture

```
Phase views (UNCHANGED)
   │  avatarSpeak(text) ──► .tavusEchoRequest notification
   ▼
VoiceGuideService  (NEW, ~200 LOC)          DailyCallManager (UNCHANGED)
   │  active when mode == .voice               active when mode == .avatar
   │
   ├─► VoiceClipLibrary (NEW): text → SHA-256 → bundled clip
   │      └─ hit:  AVAudioPlayer plays clip (<50 ms)
   │      └─ miss: AVSpeechSynthesizer fallback + os_log (dev-visible, no PHI)
   │
   ├─► avatarInterrupt() → stop playback, clear queue
   ├─► avatarSetMicMuted() → SpeechService gating (existing)
   └─► Off-script handling: OffScriptIntentMatcher (NEW) → refusal clip
Listening (UNCHANGED): SpeechService → ResponseCheckers/scorers
```

### 3.1 VoiceClipLibrary

- Bundled audio clips (`.m4a`, 44.1 kHz mono) + `VoiceClipManifest.json`
- Manifest entry: `{ id, scriptSHA256, file, durationMs, voiceId, modelId, renderedAt }`
- Lookup: normalize echo text (strip SSML breaks, collapse whitespace) → SHA-256 → clip.
  SSML `<break time="600ms">` markers are honored at **render time** (real silence baked
  into the clip), mirroring the stimulus-fingerprint discipline from the six-module spec.
- Clip inventory (~60–80 clips):
  - All `LeftPaneSpeechCopy` static constants (welcome, per-phase instructions,
    orientation questions, clock instruction, fluency prompt, story, recall prompt, closing)
  - `wordRegistrationEcho` composed variants: per word set × {initial, retry}
  - The 8 refusal templates + emergency response + "use the button on the screen"
    responses from tavus-avatar-behavioral-guide.md
- **Drift guard (test):** `VoiceClipManifestTests` fails if any `LeftPaneSpeechCopy`
  surface lacks a manifest entry — same pattern as `BatteryEnumSyncTests`.

### 3.2 VoiceGuideService

- Subscribes to the same notifications DailyCallManager handles today
  (`.tavusEchoRequest`, context updates no-op, interrupt, mic gating)
- Serial playback queue with the existing echo-queue semantics (one clip at a time,
  interruptible); publishes `replicaStartedSpeaking/StoppedSpeaking`-equivalent state so
  existing UI affordances (speaking indicator, auto-interrupt guards) keep working
- Audio session: `.playback` + `.duckOthers` handoff with SpeechService's
  `.playAndRecord` capture (reuse `AudioSessionManager`); explicit half-duplex — never
  play while capturing a scored answer, matching the avatar's mic-gating pattern

### 3.3 OffScriptIntentMatcher (v1: rules, not ML)

Maps patient utterances that arrive *outside* answer-capture windows to the scripted
refusal categories (performance question, repeat request, medical question, off-topic,
distress, wants-to-stop, emergency, manipulation) via keyword/phrase tables taken
verbatim from the behavioral guide. Emergency table (chest pain, breathing, weakness,
vision loss, severe headache, self-harm, falling) additionally raises the existing
staff-alert path. Anything unmatched → **stay silent** (the guide's own default).
Apple FoundationModels on-device classification is a possible v2 — explicitly deferred.

### 3.4 Mode selection

- `Settings`: Guide mode picker — **Voice (recommended)** / Video avatar (requires Tavus)
- Default: Voice when no Tavus API key configured (upgrades today's silent
  "Continue without avatar" fallback into a full guided experience)
- `GuideMode` enum drives which service subscribes at session start; both are never
  active simultaneously

## 4. Render pipeline (one-time, offline)

- Script `scripts/render_voice_clips.py` (or Swift CLI): reads script inventory from a
  generated JSON dump of `LeftPaneSpeechCopy`, calls ElevenLabs TTS REST once per clip,
  writes clips + manifest
- Voice: audition 2–3 ElevenLabs voices (warm, mature, clear; ~130–140 wpm via voice
  speed setting) — candidate list produced via ElevenLabs voice search; final pick is
  Tolla's call (clinical tone matters)
- Model: highest-quality tier (no real-time constraint) — e.g. `eleven_multilingual_v2`
  or v3; stability high / style low for neutral clinical delivery
- Inputs contain **zero PHI** (static scripts only) → no BAA required for rendering
- API key: use the existing ElevenLabs key already provisioned in `mercy-backend/.env`
  (never committed, never logged); estimated cost: a few dollars of credits, one time
- Re-render policy: any script text change → new SHA-256 → drift-guard test fails →
  re-render that clip. Manifest records voice/model for provenance.

## 5. Error handling

| Failure | Behavior |
|---|---|
| Clip missing for echo text | AVSpeechSynthesizer fallback (assessment never blocks) + `os_log` fault (no PHI) |
| Audio session interrupted (call, Siri) | Pause queue, resume current clip from start (never mid-word for stimuli) |
| Speech recognition unavailable/denied | Existing SpeechService paths unchanged; phase views already handle this |
| Emergency phrase detected | Play emergency clip + raise existing staff-alert path |

## 6. Regulatory / HIPAA impact

- **Improves PHI posture:** in Voice mode, nothing crosses the device boundary — the
  `ContentView.swift:274` displayName-to-Tavus issue and the
  `wordRegistrationWithTrial` derived-score leak are moot in this mode (they remain
  open items for the avatar mode)
- **CDS posture unchanged:** no scoring surface, threshold, or clinical display is
  touched; ASR remains exactly as wired today
- **Echo-vessel discipline retained:** runtime speech is restricted to a closed,
  pre-authored, hash-verified clip set — a *stronger* guarantee than prompt-guarding a
  cloud LLM
- Phase-3 avatar aspirations are unaffected; this is a Phase-1-friendly mode

## 7. Testing

1. `VoiceClipManifestTests` — every speech surface has a clip (drift guard)
2. `VoiceGuideServiceTests` — queue ordering, interrupt clears queue, half-duplex
   invariant (never plays while a scored capture window is open)
3. `OffScriptIntentMatcherTests` — table-driven: guide's example utterances → expected
   refusal category; emergency phrases → alert
4. Simulator smoke: full 7-phase run in Voice mode, no Tavus key present
5. Existing suites (ScoringLogicTests, ResponseCheckersTests) must stay green — they
   are untouched by design

## 8. Build order (summary for the implementation plan)

1. `GuideMode` + Settings picker + service selection seam
2. `VoiceClipLibrary` + manifest + drift-guard test (with temporary AVSpeech-rendered
   placeholder clips so the pipeline is testable before ElevenLabs render)
3. `VoiceGuideService` + queue/interrupt + tests
4. `OffScriptIntentMatcher` + tests
5. Voice audition → one-time ElevenLabs render → swap real clips in
6. End-to-end simulator verification

## 9. Open questions (for Tolla)

1. Voice audition: pick the final voice from 2–3 rendered samples (I'll prepare them)
2. OK to spend a few dollars of the existing ElevenLabs credits for the one-time render?
3. Should Voice mode become the *default* even when a Tavus key exists? (This spec
   defaults to Voice only when Tavus is unconfigured)
