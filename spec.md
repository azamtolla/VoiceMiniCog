# spec.md — MercyCognitive (VoiceMiniCog) Product Specification

## Product Identity
- **Name**: MercyCognitive (VoiceMiniCog)
- **Version**: 3.1 (Regulatory Review Update)
- **Classification**: Software as Medical Device (SaMD), Class II, 21 CFR 882.1470, product code PKQ
- **Platform**: iOS/iPadOS ONLY (SwiftUI, Swift 5.9+, iOS 15+)
- **Developer**: Azam Tolla, DO — Attending Neurologist, Mercy Health, Toledo OH

---

## Intended Use
Digital cognitive screening tool for Mercy Health primary care (Annual Wellness Visits) and memory clinic settings. Administers PHQ-2, QDRS, and Qmci through a photorealistic AI avatar (Dr. Claire). Outputs subtest performance scores for clinician interpretation — NOT diagnostic classifications.

---

## Clinical Protocol (3 Instruments)

### 1. PHQ-2 Depression Gate (Administered First)
- 2 questions, scored 0–6
- Positive ≥3 → triggers PHQ-9 recommendation
- **Rationale**: Depression causes pseudodementia; original Qmci validation excluded depressed subjects

### 2. QDRS (Quick Dementia Rating System)
- 10-item informant questionnaire, 3–5 min
- Scored 0–30: 0–1 normal, 2–5 MCI, 6–12 mild dementia, 13–20 moderate, 20–30 severe
- Generates CDR-equivalent staging (AUC 0.911)

### 3. Qmci (Quick Mild Cognitive Impairment Screen)
- 6 subtests, 100 points total, ~4.5 min
- Outperforms MoCA for MCI: AUC 0.90 vs 0.80

| Subtest | Domain | Max Pts | Administration Method |
|---------|--------|---------|----------------------|
| Orientation | Temporal/spatial | 10 | Avatar asks via gateway LLM |
| Word Registration | Working memory | 5 | conversation.echo (verbatim) |
| Clock Drawing | Visuospatial/exec | 15 | conversation.echo + iPad canvas |
| Verbal Fluency | Semantic memory | 20 | conversation.echo + ASR capture |
| Logical Memory | Episodic memory | 30 | conversation.echo + ASR capture |
| Delayed Recall | Episodic memory | 20 | conversation.echo + ASR capture |

---

## Scoring Thresholds (SAFETY-CRITICAL)
- **Qmci**: ≥67 Normal | 54–66 MCI Probable | <54 Dementia Range
- **QDRS**: 0–1 Normal | 2–5 MCI | ≥6 Dementia staging
- **PHQ-2**: ≥3 triggers PHQ-9 recommendation
- **Composite**: Qmci + QDRS cross-tabulation → LOW / INTERMEDIATE / HIGH

---

## Assessment Flow
```
HomeView → QDRSView → PHQ2View → ModePicker → QmciAssessmentView (6 subtests) → PCPReportView
```

---

## Architecture — Tavus CVI (Option C: Gateway as Custom LLM)

### Pipeline
```
iPad (WebRTC via Daily SDK)
  ↔ Tavus CVI Cloud
      ├── ASR: Tavus STT
      ├── Perception: Raven-1 (facial affect, gaze, emotion)
      ├── Turn-taking: Sparrow (~600ms)
      ├── LLM: Gateway FastAPI on RunPod (OpenAI-compatible)
      ├── TTS: ElevenLabs (voice: Sarah)
      └── Rendering: Phoenix-4 (photorealistic avatar, 30fps)
  ↔ iPad receives WebRTC video stream
```

### Latency Budget
| Component | Time |
|-----------|------|
| ASR (Tavus STT) | ~50–100ms |
| Gateway LLM (RunPod) | ~50–100ms |
| TTS (ElevenLabs) | ~75–135ms |
| Phoenix-4 + WebRTC | ~150–200ms |
| **Total** | **~600–700ms** |
| conversation.echo path | ~225–335ms (skip ASR + LLM) |

### Key Services
| Service | Purpose |
|---------|---------|
| TavusService | WebRTC connection via Daily SDK, conversation lifecycle |
| GatewayClient | HTTP client for RunPod gateway (phase sync, scores) |
| ProtocolOrchestrator | FSM driving assessment phase transitions |
| CDTOnDeviceScorer | CoreML clock drawing scoring (Shulman 0–5) |
| ResponseCheckers | NLP validation (recall matching, fluency counting) |
| BiomarkerCollector | Aggregates CDT, ASR, Raven-1 biomarkers |

---

## Digital Biomarkers (3 Modalities)
1. **Clock Drawing**: stroke kinematics, timing, pressure, self-corrections (75+ samples/sec)
2. **Verbal Fluency**: temporal binning, inter-word intervals, clustering/switching
3. **Facial Affect** (Raven-1): emotion tracking, gaze, micro-expressions — PHASE 3 ONLY

---

## External Integrations
| Integration | Auth | Role |
|------------|------|------|
| Tavus CVI | API key | Full pipeline (ASR, TTS, avatar, perception) |
| Gateway FastAPI | API key | Phase-aware clinical router on RunPod |
| ElevenLabs | Via Tavus persona | TTS voice (Sarah) |
| CoreML CDTScorer | None | On-device clock scoring |
| Daily (WebRTC) | Via Tavus | Audio/video transport |

---

## HIPAA Requirements
- BAAs required from: Tavus (Enterprise), RunPod (Secure Cloud), ElevenLabs (Enterprise + Zero Retention)
- AES-256 at rest, TLS 1.3 in transit, Keychain with Secure Enclave
- No PHI logging in production, no unencrypted PHI storage
- 5–15 min auto-timeout with biometric re-auth
- Audit logging retained 6+ years

---

## Regulatory Pathway
- **Phase 1**: NSR Abbreviated IDE (21 CFR 812.2(b)) — clinical validation, IRB approval only
- **Phase 2**: 510(k) submission (~Month 23) — predicates: BrainCheck, Cognivue, Cogstate, Linus Health
- **Phase 3**: Raven-1 facial affect expansion (subsequent submission)
- Initial 510(k) EXCLUDES Raven-1 facial affect claims

---

## Accessibility (WCAG 2.2 AA + Elderly UX)
- 60pt minimum touch targets
- 18pt minimum text, Dynamic Type support
- 4.5:1 contrast ratio minimum
- One task per screen, hidden timers, practice rounds
- Sparrow turn_taking_patience: high (MCI patients need longer)

---

## Design System
- Primary: Mercy Health navy-teal #1a5276
- Components: MCPrimaryButton (60pt), MCSecondaryButton (52pt), MCCard, MCProgressBar
- Style: Neo-skeuomorphic, card-based, clinical aesthetic
- Prefixes: MC* = design system, Mercy* = brand
