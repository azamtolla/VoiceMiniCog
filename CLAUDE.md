# CLAUDE.md — MercyCognitive (VoiceMiniCog)

## Project Overview

MercyCognitive is an iOS/iPadOS cognitive screening app for Mercy Health primary care and memory clinic screening of mild cognitive impairment (MCI) and dementia. It delivers a three-instrument clinical protocol (PHQ-2, QDRS, Qmci) through an MA-administered iPad interface with automated scoring, composite risk classification, and PCP reporting with recommended labs, billing codes, and referral guidance.

**Version**: 5.0
**Stack**: SwiftUI, Swift 5.9+ (@Observable), iOS 15+
**Platform**: iOS/iPadOS ONLY — no React, no web, no Android
**State**: Active development — building most advanced product
**Developer**: Azam Tolla, DO — Attending Neurologist, Mercy Health Neurology Specialists, Toledo OH
**Strategic context**: Internal clinical tool to increase MCI capture rate in Mercy Health primary care, finding eligible patients for anti-amyloid therapy (Leqembi, Kisunla). 92% of MCI cases are undiagnosed; 99% of PCPs underdiagnose MCI. Each diagnosed patient entering anti-amyloid therapy generates ~$82,500/year in downstream clinical revenue (infusions, ARIA monitoring MRIs, amyloid PET, specialist visits) for Mercy Health. With 46 hospitals system-wide, building in-house is significantly cheaper than purchasing per-site SaaS licenses from BrainCheck/Linus Health ($30K-50K/site/year = $1.4M-2.3M annually).
**Innovation team**: Working with Mercy Health Innovation Team for pilot deployment and system-wide scaling.

---

## Regulatory Context

### SaMD Classification
MercyCognitive with AI scoring is Software as a Medical Device (SaMD):
- **Regulation**: 21 CFR 882.1470 ("Computerized Cognitive Assessment Aid"), product code PKQ
- **Class**: II (non-exempt), special controls
- **Pathway**: 510(k) using predicates (Cognivue, Cogstate Cognigram, BrainCheck Assess, Linus Health)
- **IMDRF SaMD Category**: I or II (informs clinical management of serious condition)
- **IEC 62304 Software Safety Class**: B (non-serious injury from delayed/missed screening)

### Coding Standards for Clinical Software
- No silent failures in any clinical pathway — every failure must surface to the user.
- All scoring algorithms must be deterministic and auditable.
- Every UI component displaying clinical data must be marked with `// MARK: CLINICAL-UI`.
- Display subtest performance scores in the PCP report (e.g., "Delayed Recall: 8/20"). Clinician interprets — the app does not diagnose.

---

## Validation Study Protocol (NSR Abbreviated IDE — ACTIVE)

### Regulatory Framework
- **Pathway**: Nonsignificant Risk (NSR) Abbreviated IDE under 21 CFR 812.2(b)
- **IDE requirements**: Investigational device labeling, informed consent per 21 CFR Part 50, no device promotion during study, study records per 21 CFR 812.140
- **IRB type**: Full board review (recommended due to vulnerable elderly population, cognitive impairment stigmatization risk, and dual-purpose study design)
- **Pre-Submission (Q-Sub)**: Schedule with FDA CDRH BEFORE enrollment begins to confirm NSR determination and evidence requirements. Free consultation.

### Study Design
- **Type**: Prospective cohort with delayed reference standard
- **Design rationale**: Mirrors published predicate device validation methodology (Cognivue, BrainCheck); avoids same-day verification bias
- **IRB status**: Protocol in preparation — target submission Q2 2026

### Enrollment
- **Target N**: 300-400 patients across cognitive strata (normal cognition, MCI, dementia). Prior target of 150-200 was insufficient — cleared comparators used larger samples (Cognivue 401, BrainCheck 414, Cognivue FOCUS 452). With ~15-20% expected cognitive impairment prevalence in AWV population, n=200 yields only 30-40 positive cases, insufficient for precise sensitivity estimation.
- **Sites**: 2-3 Mercy Health PCP clinics + Memory Clinic (reference standard site) + at least 1 additional external site. Single-site study threatens generalizability for FDA. Cognivue FOCUS used 6 sites with 31.2% African American and 9.2% Hispanic enrollment. Toledo demographics alone may not reflect intended national use population.
- **Population**: Adults presenting for Annual Wellness Visits (AWV) at PCP, plus memory clinic referrals
- **Informed consent**: Written informed consent per 21 CFR Part 50 required for all participants. Consent must clearly disclose: investigational status of device, nature of cognitive screening, data collection and storage practices, cloud processing of speech/facial data, voluntary participation.

### Medicare Billing Considerations (⚠️ LEGAL RISK)
- **Action required**: Formal Medicare Coverage Analysis before enrollment begins.
- **Risk**: Billing Medicare for AWV while simultaneously using an investigational device for research creates potential False Claims Act exposure. Multiple academic centers have paid seven-figure settlements for clinical trial billing errors.
- **Options**: (a) Sponsor-fund the cognitive screening component entirely (cleanest legally), (b) Bill only for the AWV clinical encounter and clearly segregate research costs, (c) Obtain formal Mercy Health compliance opinion on permissible billing structure.
- **Coordinate with**: Mercy Health billing/compliance, legal counsel familiar with Medicare research billing rules.

### Data Collection by Timepoint

| Timepoint | Setting | Data Collected | Collector |
|-----------|---------|----------------|-----------|
| Visit 1 | PCP (AWV) | MercyCognitive digital Qmci scores (all 6 subtests + digital biomarkers), PCP referral decision (refer / reassure / recheck) | App + PCP |
| Visit 2 (referred cases) | Memory Clinic | Full neuropsych battery, CDR, MoCA, clinical MCI/dementia diagnosis | Dr. Tolla |
| Visit 2 (random non-referred sample) | Memory Clinic | Same battery — required to correct verification bias | Dr. Tolla |

### Primary Endpoints
- Sensitivity and specificity of digital Qmci for MCI detection vs. neuropsychologist gold standard
- AUC comparison: digital Qmci vs. MoCA (administered at memory clinic)
- Correlation of digital Qmci subtest scores with neuropsychological battery subscores

### Secondary Endpoints
- Time to administer (digital Qmci vs. paper MoCA)
- PCP workflow satisfaction (Likert scale survey)
- Prediction of PCP referral decision from digital Qmci score
- Test-retest reliability (subset of patients, 2-week interval)

### Statistical Considerations
- Verification bias correction: Begg-Greenes method applied to non-referred sample. **⚠️ Caveat**: FDA's 2007 Statistical Guidance cites Begg (1987) but explicitly recommends consulting a CDRH statistician before using this approach. A 2008 BMC study found the method produces unstable estimates when false negatives are few (common in cognitive screening). Request CDRH statistical consultation during Q-Sub.
- Published Qmci AUC 0.90 vs. MoCA 0.80 — power calculation targets detecting this difference at 80% power, alpha 0.05 → ~120 patients with MCI/dementia confirmation. At updated n=300-400 with ~15-20% prevalence, expect 45-80 positive cases — adequate but not generous. Consider enriched enrollment at memory clinic to ensure sufficient positive cases.
- Three alternative word sets / story versions available — counterbalance across subjects to reduce practice effects

### Study = 510(k) Evidence
**This study is the primary clinical evidence for the 510(k) submission.** Data collected here directly supports:
- Clinical performance section of 510(k)
- Substantial equivalence argument to predicates
- Digital vs. paper Qmci equivalence claim (required per German eQmci validation precedent)

---

## Clinical Validation Foundation

### Qmci (Quick Mild Cognitive Impairment Screen)
Developed by O'Caoimh & Molloy (2012), validated across four memory clinics in Ontario, Canada. Administered in median 4.24 to 4.5 minutes. Outperforms MoCA for MCI detection: AUC 0.90 vs 0.80 (p=0.009). At cutoff <62: sensitivity 90%, specificity 87% vs MoCA's 96%/58%.

Six subtests, 100 points total:

| Subtest | Domain | Max | Scoring detail |
|---------|--------|-----|----------------|
| Orientation | Temporal/spatial | 10 | 5 questions (country, year, month, day, date), 2 pts each |
| Word Registration | Working memory | 5 | 5 words read aloud, score trial 1 only, up to 3 trials |
| Clock Drawing | Visuospatial/executive | 15 | Blank template, patient sets specified time |
| Verbal Fluency | Semantic memory | 20 | Animals in 60 sec, 1 pt/word, max 20 |
| Logical Memory | Episodic memory | 30 | Immediate recall of short story (4 sentences), highest weight — most sensitive subtest for MCI (AUC 0.80) |
| Delayed Recall | Episodic memory | 20 | Recall of 5 registration words, 4 pts/word |

**Critical note**: Any digital adaptation of the Qmci constitutes a different test requiring independent validation (per German eQmci study). The IRB validation study above directly addresses this requirement. Document all deviations from paper administration.

### QDRS (Quick Dementia Rating System)
Developed by James E. Galvin (2015). 10-item informant-based questionnaire, 3 to 5 minutes. Generates valid CDR-equivalent staging. AUC 0.911. Cronbach alpha 0.86 to 0.93. ICC with clinician CDR = 0.90.

Scoring: 0 to 30 total. 0 to 1 normal, 2 to 5 MCI, 6 to 12 mild dementia, 13 to 20 moderate, 20 to 30 severe.

Complements Qmci: captures informant-observed functional decline and behavioral changes vs Qmci's objective patient performance.

### PHQ-2 Depression Gate
Kroenke et al. (2003). Two questions on anhedonia and depressed mood, scored 0 to 6. At threshold >=3: sensitivity 83%, specificity 92% for major depression.

Clinical rationale: Depression causes pseudodementia (0.9 to 4.5% of cognitive decline presentations, up to 13% under age 65), producing false-positive cognitive screening results. The original Qmci validation explicitly excluded subjects with depression (GDS >7). PHQ-2 must be administered before cognitive testing to preserve Qmci validity.

---

## Scoring Thresholds

### SAFETY-CRITICAL — Never change without clinical review by Dr. Tolla

- **Qmci**: >=67 Normal | 54 to 66 MCI Probable | <54 Dementia Range
- **QDRS**: 0 to 1 Normal | 2 to 5 MCI | >=6 Dementia staging (see QDRS scale above)
- **PHQ-2**: >=3 triggers PHQ-9 recommendation; cognitive results interpreted with caution
- **Composite Risk Matrix**: Qmci + QDRS cross-tabulation => LOW / INTERMEDIATE / HIGH

**PCP Report display rule**: Show raw subtest scores + total score. The composite risk matrix (LOW/INTERMEDIATE/HIGH) may be displayed as a *clinical prompt to consider* (consistent with 2026 FDA CDS guidance enforcement discretion for treatment planning support), but must NOT be labeled as a diagnosis. Include explicit disclosure: *"These results reflect patient performance on a standardized cognitive assessment. Clinical diagnosis of MCI or dementia requires physician evaluation."*

Published Qmci cutoffs vary by age, education, and population. The thresholds above are the working clinical cutoffs for this implementation. Document any future adjustments with clinical justification and date.

---

## Architecture — Tavus CVI Option C (Gateway as Custom LLM)

### Why This Architecture

The entire assessment is structured prompts followed by patient responses. There is no open-ended free dialogue anywhere in the protocol. QDRS is caregiver Q&A. PHQ-2 is two scripted questions. Qmci is six scripted subtests. This means:
- 600ms utterance-to-utterance latency is imperceptible for structured clinical assessment
- Full-duplex speech-to-speech models (Moshi, PersonaPlex) are unnecessary — they solve a problem this app does not have
- A photorealistic avatar with emotional intelligence (Raven-1 affect reading, Sparrow turn-taking) adds far more clinical value than 200ms raw audio latency ever could

### Why Moshi/PersonaPlex Were Dropped

PersonaPlex (NVIDIA) and Moshi (Kyutai) are monolithic audio-to-audio models. They cannot plug into Tavus's modular layer system because Tavus expects text at each layer boundary (ASR outputs text, LLM processes text, TTS consumes text), while PersonaPlex eliminates the text layer entirely. The only way to combine them would be server-to-server audio piping, which adds 200-600ms latency and defeats the purpose.

PersonaPlex achieves ~200ms precisely because it has no avatar rendering pipeline. Tavus achieves a photorealistic avatar because it has a rendering pipeline that costs ~400ms minimum. These are mutually exclusive with current technology. For structured clinical assessment where no phase is latency-sensitive, the avatar is the right call.

Additionally: Moshi was labeled "research only" by Kyutai, had issues with excessive output and interruptions in SOVA-Bench evaluations, could not deliver verbatim clinical prompts (it paraphrases everything), and had a ~5 minute context window limit.

### The Pipeline

Tavus CVI runs the complete pipeline. The iPad connects directly via WebRTC to Tavus's Daily room. Tavus handles ASR, TTS, avatar rendering, and turn-taking. Your custom clinical logic lives in a lightweight FastAPI endpoint on RunPod that Tavus calls as its "LLM" layer via OpenAI-compatible API.

```
iPad (WebRTC via Daily SDK)
  <-> Tavus CVI Cloud
        |-- ASR: Tavus STT (speech to text)
        |-- Perception: Raven-1 (facial affect, gaze, emotion, sub-100ms audio perception)
        |-- Turn-taking: Sparrow (natural pauses, interruption handling, ~600ms)
        |-- LLM: YOUR Gateway FastAPI on RunPod (OpenAI-compatible /v1/chat/completions)
        |-- TTS: ElevenLabs (voice: Sarah) configured as Tavus TTS layer
        |-- Rendering: Phoenix-4 (photorealistic avatar, 30fps, full-face animation + micro-expressions)
  <-> iPad receives WebRTC video stream
```

### Gateway "LLM" — Phase-Aware Clinical Router

Your FastAPI endpoint on RunPod exposes an OpenAI-compatible `/v1/chat/completions` endpoint. Tavus sends it the ASR transcription as user messages. Your endpoint manages assessment phase state and returns the appropriate response:

| Phase Type | Gateway Behavior | Tavus Action |
|-----------|-----------------|--------------|
| **Greeting** | Return warm conversational greeting from persona prompt | Tavus TTS speaks it, Phoenix-4 renders |
| **QDRS questions** | Return next QDRS question based on phase state, score previous response | Tavus TTS speaks, Sparrow manages turn-taking |
| **PHQ-2 questions** | Return next PHQ-2 question, score previous response | Same as QDRS |
| **Scripted Qmci prompts** | Use `conversation.echo` via Interactions Protocol to inject exact clinical text verbatim | Bypasses LLM entirely, Tavus TTS speaks exact text, no paraphrasing possible |
| **Listen phases** | Return brief acknowledgment or empty, configure high `turn_taking_patience` | Avatar waits silently with attentive expression while patient responds |
| **Transitions** | Return encouraging transition text between subtests | Natural avatar speech with emotional expression |
| **Scoring/Report** | Compute scores, return summary | Transition to PCPReportView on iPad |

### Critical: Verbatim Clinical Prompt Delivery

For Qmci subtests requiring exact wording (word lists, clock instructions, logical memory story, recall prompts, fluency instructions), use the Tavus Interactions Protocol `conversation.echo` to make the replica speak supplied text verbatim. This bypasses the LLM entirely, so the exact clinical text goes directly to TTS then to Phoenix-4 rendering. This guarantees psychometric validity — no paraphrasing, no hallucination, no variation between administrations.

### Latency Budget (Realistic)

| Component | Time |
|-----------|------|
| ASR (Tavus STT) | ~50-100ms |
| Gateway "LLM" (RunPod FastAPI) | ~50-100ms |
| TTS (ElevenLabs Flash or Cartesia Sonic) | ~75-135ms |
| Phoenix-4 rendering + WebRTC | ~150-200ms |
| **Total end-to-end** | **~600-700ms** |

For scripted prompts via `conversation.echo`: skip the ASR and LLM steps, so TTS + rendering only = ~225-335ms.

Note: Demo latency vs real-world latency can differ due to network congestion and geographic distance between iPad, Tavus edge, and RunPod. The ~50-100ms gateway hop assumes RunPod is low-latency and co-located or nearby.

### Tavus Configuration

```python
# Persona creation (POST https://tavusapi.com/v2/personas)
{
    "persona_name": "Dr. Claire",
    "system_prompt": "You are Dr. Claire, a warm and professional clinical assistant...",
    "context": "Assessment protocol context, phase state, scoring rules...",
    "default_replica_id": "your_dr_claire_replica_id",
    "layers": {
        "llm": {
            "model": "mercy-cognitive-gateway",
            "base_url": "https://your-runpod-endpoint/v1",
            "api_key": "your-api-key",
            "speculative_inference": true
        },
        "tts": {
            "tts_engine": "elevenlabs",
            "api_key": "your-elevenlabs-key",
            "external_voice_id": "sarah-voice-id",
            "voice_settings": {
                "speed": "normal",
                "emotion": ["positivity:medium"]
            }
        },
        "perception": {
            "perception_model": "raven-1",
            "ambient_awareness": true
        }
    }
}
```

### Raven-1 Affect Perception (Key Differentiator)

Tavus Raven-1 (GA February 11, 2026) provides real-time audio-visual fusion of facial expression, gaze direction, tone, and prosody into natural-language descriptions for the LLM, with sub-100ms audio perception latency:
- Reads facial expressions, emotional states, gaze direction, and confusion/distress signals
- Outputs structured perception events sent to the gateway "LLM" as additional context
- Configure `turn_taking_patience: high` — patients with MCI need longer response windows and must not be interrupted
- Clinical applications: detecting patient distress during recall failure, confusion during orientation questions, engagement/attention level throughout assessment, affect flattening patterns
- This is a completely new biomarker modality no competing cognitive screening platform captures

### Avatar System — Tavus Phoenix-4

The avatar is a **photorealistic digital human** ("Dr. Claire") rendered by Tavus Phoenix-4:
- Gaussian-diffusion rendering model producing full-face animation at 30fps
- Lip-sync, micro-expressions, eyebrow movement, and cheek muscle dynamics — not just mouth movement
- Emotional intelligence: avatar adapts expression based on Raven-1 perception of patient state
- Requires only 2 minutes of source video to train a custom Replica
- 100+ pre-built Replicas available for initial development/testing
- WebRTC delivery via Daily — no local rendering compute required on iPad

Avatar behavior during assessment:
- Maintains warm, attentive expression during patient response/drawing windows
- Adapts emotional tone based on Raven-1 perception (e.g., more encouraging if patient shows frustration)
- Practice rounds before scored subtests where clinically appropriate
- Assessment framed positively to reduce anxiety — research shows this improves completion rates

### State Management
- `AssessmentState` (@Observable) is the **single source of truth** — never create parallel state
- Sub-states: `QmciState`, `QDRSState`, `PHQ2State` (nested @Observable)
- Views use `@Bindable` for reactive binding
- Local-only transient state uses `@State`
- No Redux, no Combine, no external state libraries — pure @Observable

### Navigation
Enum-based routing via `AppScreen` in `ContentView.swift`:
```
Home -> QDRS -> PHQ-2 -> ModePicker -> QmciAssessment (6 subtests) -> Report
```

### Project Structure
```
VoiceMiniCog/
├── Models/               # Data models, scoring, enums (AssessmentState, Phase, QmciModels, etc.)
├── Views/                # SwiftUI screens (18 files, one per screen/subtest)
├── Services/             # API, speech, TTS, avatar, audio, ML scoring (16 files)
├── Theme/                # Design system (MCDesign, MercyColors, MCComponents)
├── Resources/            # JSON manifests (ClipManifest.json)
└── CDTScorer.mlpackage/  # CoreML clock drawing model (on-device)
```

---

## Assessment Flow

1. **HomeView** — Select respondent type (Patient / Informant)
2. **QDRSView** — 10-question informant functional decline survey (0 to 30 pts, see QDRS staging)
3. **PHQ2View** — 2-question depression gate (0 to 6 pts, positive >=3)
4. **QmciAssessmentView** — 6 subtests (0 to 100 pts total):
   - Orientation (5 Qs, 10 pts) — Avatar asks via gateway LLM, gateway scores ASR transcription
   - Word Registration (5 words, 5 pts) — `conversation.echo` for exact word list, Tavus ASR captures recall
   - Clock Drawing (canvas, 15 pts) — `conversation.echo` for instructions, avatar waits silently, iPad captures drawing
   - Verbal Fluency (animals in 1 min, 20 pts) — `conversation.echo` for instructions, Tavus ASR transcribes with timestamps
   - Logical Memory (story recall, 30 pts) — `conversation.echo` for story, Tavus ASR captures recall
   - Delayed Recall (5 words, 20 pts) — `conversation.echo` for prompt, Tavus ASR captures recall
5. **PCPReportView** — Subtest performance scores, composite risk prompt, recommended labs, billing codes, specialist referral recommendations. **Displays patient performance — clinician diagnoses.**

### Latency Sensitivity by Assessment Phase
- **QDRS** (caregiver Q&A): Structured questions with yes/no or scale responses. 600ms is imperceptible between prompt and response wait.
- **PHQ-2**: Two scripted questions expecting 0-3 frequency responses. Latency irrelevant.
- **Orientation**: Scripted questions, structured responses. Latency irrelevant.
- **Word Registration/Recall**: Timing of word presentation matters (inter-stimulus interval). `conversation.echo` bypasses LLM, so delivery is TTS + rendering only (~225-335ms).
- **Clock Drawing**: Avatar is silent. Zero latency sensitivity. iPad-only interaction.
- **Verbal Fluency**: Avatar is silent during 60-second generation. Zero latency sensitivity during capture.
- **Logical Memory**: Story delivery via `conversation.echo` (~225-335ms), then silent listening. Zero latency sensitivity.
- **Conclusion**: No phase in the assessment is latency-sensitive for open-ended conversational exchange. The 600ms floor is a non-issue.

---

## Key Services

| Service | File | Purpose |
|---------|------|---------|
| `TavusService` | Services/TavusService.swift | WebRTC connection via Daily SDK to Tavus CVI. Manages conversation lifecycle, sends interactions (`conversation.echo`, `conversation.respond`), receives perception events and ASR transcriptions. |
| `GatewayClient` | Services/GatewayClient.swift | HTTP client for direct communication with RunPod gateway when needed outside Tavus pipeline (e.g., phase sync, score retrieval, biomarker aggregation) |
| `ProtocolOrchestrator` | Services/ProtocolOrchestrator.swift | FSM driving assessment phase transitions on iPad side, coordinates with gateway phase state via conversation context |
| `CDTOnDeviceScorer` | Services/CDTOnDeviceScorer.swift | CoreML clock drawing scoring (Shulman 0 to 5), fully on-device |
| `ResponseCheckers` | Services/ResponseCheckers.swift | NLP validation (word recall matching, fluency word counting, orientation answer validation) — may run on-device or in gateway |
| `BiomarkerCollector` | Services/BiomarkerCollector.swift | Aggregates digital biomarkers from CDT canvas, Tavus ASR timestamps, and Raven-1 affect perception events |

### Deprecated Services (From Prior Moshi/PersonaPlex Architecture)
- `PersonaPlexService` — REMOVED. PersonaPlex cannot integrate with Tavus layer system (monolithic audio-to-audio model vs Tavus text-boundary layers).
- `AudioArbitrator` — REMOVED. No more 16kHz/24kHz sample rate conflict. Tavus handles all audio internally.
- `ElevenLabsService` — REMOVED as runtime service. ElevenLabs is configured as Tavus TTS layer via persona config.
- `SpeechService` — REMOVED as primary ASR. Tavus ASR handles all speech recognition. On-device SFSpeechRecognizer retained as offline fallback only.

---

## Digital Biomarker Capture

MercyCognitive's key differentiator vs competitors (Linus Health, BrainCheck, Cogstate): combining Qmci administration with real-time digital biomarker extraction across three modalities (drawing kinematics, speech temporal patterns, and facial affect). No current platform does this.

**Regulatory note**: Digital biomarker claims in the 510(k) submission require analytical validation evidence. Raven-1 facial affect biomarkers have no PKQ predicate precedent and may require separate De Novo classification.

### Clock Drawing Biomarkers (CDT Canvas)
Capture at minimum **75 samples/second** via Apple Pencil or finger drawing:
- **Temporal**: Total completion time, pre-first-stroke latency (decision-making), think-time vs ink-time ratio, inter-stroke pauses
- **Graphomotor**: Drawing velocity, pen pressure (Apple Pencil), stroke count, in-air pen distance, stroke length variability
- **Behavioral**: Self-correction frequency and timing, stroke ordering sequence, number placement strategy (anchor numbers first vs sequential)
- **Clinical significance**: DCTclock research shows these features outperform 30-minute PACC battery for detecting pre-symptomatic amyloid pathology

CDT Canvas Rules (unchanged):
- No undo button
- No drawing guides or overlays
- No pen style options
- Every stroke, pause, and self-correction captured
- Timer is hidden from patient view
- On-device CoreML scoring via CDTScorer.mlpackage (Shulman 0 to 5)

### Verbal Fluency Biomarkers
Captured via Tavus ASR transcription events with timestamps during 60-second animal naming:
- **Temporal binning**: Word counts in 15-second intervals (front-loading pattern is normal; flat or accelerating is atypical)
- **Inter-word intervals**: Millisecond-precision timestamps from Tavus ASR utterance events
- **Clustering and switching**: Troyer framework — count semantic subcategory clusters (farm animals, pets, zoo animals) and switches between them. MCI patients show impaired switching more than reduced total count
- **Semantic distance**: Compute word embedding distances between consecutive words (requires NLP model, future enhancement)
- **Clinical significance**: Phonemic fluency cluster count has AUC 0.80 for predicting MCI-to-dementia conversion

### Facial Affect Biomarkers (via Tavus Raven-1)

Note: Ohio HB 525 (introduced November 2025, in committee) would prohibit AI from "detecting emotional or mental states." Monitor this legislation.

Captured passively throughout the entire assessment via Raven-1 perception model (no additional hardware, uses iPad front camera already active for WebRTC):
- **Emotional state tracking**: Confusion, distress, frustration, engagement levels during each subtest, logged with timestamps
- **Gaze direction**: Sustained attention vs. visual wandering during avatar instructions
- **Micro-expression analysis**: Subtle emotional responses to questions (e.g., distress during memory recall failure, frustration during clock drawing)
- **Tone and prosody fusion**: Raven-1 combines audio perception (sub-100ms latency) with visual facial cues for richer affect signal than either modality alone
- **Clinical significance**: Affect flattening, inappropriate emotional responses, and apathy are documented early markers of frontotemporal and Alzheimer's pathology. No existing cognitive screening app captures this data. This is a novel research biomarker category enabled by the Tavus architecture.

### Speech Prosody Biomarkers (Future Enhancement)
Audio captured at 16 kHz supports extraction of:
- **Jitter** (pitch instability) and **shimmer** (amplitude instability) — Framingham Heart Study found these predict dementia 7 years before diagnosis
- **Speech rate**, pause frequency, filled pauses ("um", "uh")
- Feature extraction via openSMILE eGeMAPSv02 parameter set (88 features) or Praat
- **Clinical significance**: Meta-analysis of 54 studies shows 80% accuracy, 78% AUC for speech-based MCI detection

---

## External Integrations

| Integration | Location | Auth | Runtime Role |
|------------|----------|------|-------------|
| **Tavus CVI** | Tavus cloud | API key | Full pipeline: ASR, TTS (ElevenLabs Sarah), Phoenix-4 rendering, Sparrow turn-taking, Raven-1 perception. iPad connects via WebRTC (Daily SDK). |
| **Gateway FastAPI** | RunPod | API key (OpenAI-compatible) | Phase-aware clinical router. Tavus calls as its "LLM" layer via `/v1/chat/completions`. Manages assessment state, scoring, `conversation.echo` triggers. |
| **ElevenLabs** | Tavus TTS layer | API key (configured in Tavus persona) | Voice: Sarah. Configured as Tavus TTS engine via `layers.tts`. No direct runtime calls from iPad. |
| **Raven-1** | Tavus perception layer | Configured in persona | Real-time facial affect, gaze, emotion analysis. Sub-100ms audio perception. Outputs to gateway as context. |
| **Daily (WebRTC)** | Tavus infrastructure | Via Tavus conversation API | Real-time video/audio transport. iPad embeds Daily call client. Stable room URLs per conversation. |
| **CoreML CDTScorer** | On-device (iPad) | None | Clock drawing scoring. No network call, fully offline. |
| **AVSpeech** | On-device | None | Fallback TTS if Tavus/network unavailable — text-only, no avatar |

**No SPM / CocoaPods** — all networking via URLSession + native frameworks + Daily SDK only.

ElevenLabs is configured as the Tavus TTS layer. It receives only clinical prompt text and LLM-generated response text — never patient audio or PHI. No direct ElevenLabs API calls from the iPad.

---

## HIPAA / PHI Compliance (MANDATORY)

### PHI Classification in This App
- Patient speech audio processed by Tavus ASR = PHI (voice prints are HIPAA Safe Harbor identifiers)
- Cognitive test scores linked to identifiable patients = PHI
- Digital biomarker data (drawing strokes, timing) = potential quasi-biometric identifiers
- Raven-1 facial perception data (facial geometry, emotional state, gaze) = PHI (biometric + health information)
- Tavus avatar video output = NOT PHI (generated content, no patient data)
- Clinical prompt text sent to TTS = NOT PHI (standardized scripts)

### Hard Rules
- NEVER log patient name, DOB, MRN, or assessment scores to console in production
- NEVER store audio recordings to disk — Tavus processes audio ephemerally
- NEVER send identifiable PHI to any service without a signed BAA
- NEVER transmit PHI over unencrypted connections in production (HTTPS required, TLS 1.3 with certificate pinning)
- Wrap any test/demo patient data in `#if DEBUG` guards
- NEVER store PHI in local state without encryption (HIPAA §164.312)

### BAA Requirements (ALL REQUIRED BEFORE ANY PATIENT DATA)
- **Tavus**: Requires Enterprise-tier agreement with BAA. Must cover ASR audio processing, Raven-1 facial perception data, conversation transcripts, and any stored session data. **⚠️ Critical**: Verify that Tavus's standard policy of creating "anonymized data to train AI models" is explicitly excluded for PHI under the BAA. **BLOCKER — verify before any patient data touches the pipeline.**
- **ElevenLabs**: Offers HIPAA-eligible services with BAA on Enterprise tier, but **only for the Agents Platform with Zero Retention Mode enabled**. If MercyCognitive uses standard TTS API rather than the Agents Platform, coverage may not apply. Must verify with ElevenLabs sales that the BAA covers the specific TTS integration path used via Tavus. In this architecture, ElevenLabs receives only TTS text (clinical prompts and LLM-generated responses, not patient data), but verify if any patient-generated text is ever spoken back.
- **RunPod**: Announced HIPAA compliance on February 6, 2026 — very recent, limited healthcare track record. BAA required. **Must use only Secure Cloud with HIPAA-compliant Tier III+ data centers; Community Cloud is PROHIBITED for PHI workloads.** Gateway endpoint processes ASR transcriptions (patient speech as text) and Raven-1 perception events.
- **Daily (WebRTC)**: Audio/video transport layer — covered under Tavus infrastructure agreement. Verify independently that Daily's DTLS-SRTP encryption meets BAA requirements.

### Encryption Requirements
- **At rest**: AES-256 via iOS Data Protection Class A (`NSFileProtectionComplete`)
- **In transit**: TLS 1.3 with certificate pinning to Tavus and RunPod endpoints
- **Key storage**: Keychain with Secure Enclave (`kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly`)
- **Structured PHI storage**: Encrypted database (Realm AES-256 or SQLCipher)
- **Rationale**: January 2025 NPRM proposes making all HIPAA security specifications required (not addressable). NIST-compliant encryption provides breach notification safe harbor.

### Session Security
- 5 to 15 minute auto-timeout with Face ID/Touch ID re-authentication
- Audit logging: user ID, timestamp, action type, data accessed (retain 6 years minimum)
- Minimum necessary standard (§164.502(b)): gateway receives only transcribed text needed for scoring, not raw audio

### Data Flow HIPAA Analysis
- iPad camera + mic -> Tavus (WebRTC via Daily): Video/audio in transit over encrypted WebRTC (DTLS-SRTP). Tavus processes ASR and Raven-1 perception in their cloud. **BAA required.**
- Tavus -> Gateway (RunPod): ASR transcription text + Raven-1 perception events sent as LLM context. In transit over TLS. **BAA required for RunPod.**
- Gateway -> Tavus: Response text (clinical prompts, conversational responses). Not PHI.
- `conversation.echo` text: Standardized clinical scripts. Not PHI.
- iPad CDT canvas: On-device drawing capture. No network call for scoring.
- CoreML CDT scoring: On-device, no network call.

---

## Accessibility Requirements (WCAG 2.2 AA + Elderly UX)

Target users are primarily adults age 65+. Design every interaction for this population.

### Touch Targets
- 60pt minimum for all interactive elements (exceeds WCAG 2.2 AAA 44x44 and Apple HIG 44x44)
- MCPrimaryButton: 60pt height
- MCSecondaryButton: 52pt height (acceptable for secondary actions)

### Typography
- 18pt minimum for all primary text (body text)
- Support Dynamic Type for system accessibility scaling
- Type scale: heroTitle(34) > screenTitle(28) > sectionTitle(24) > body(20) > caption(18)

### Contrast
- 4.5:1 minimum contrast ratio for normal text
- 3:1 minimum for large text (>=18pt or >=14pt bold)
- Primary color Mercy Health navy-teal `#1a5276` on white exceeds 4.5:1

### Interaction Design
- One task per screen to minimize cognitive load
- Practice rounds before scored subtests
- Clear progress indicators (MCProgressBar) showing assessment position
- No time pressure communicated to patient (timers hidden from view during timed subtests)
- Face ID/Touch ID for authentication (WCAG 2.2 SC 3.3.7 — no cognitive function test for login)
- Reframe assessment positively to reduce anxiety — research shows this improves completion rates and data quality
- Tavus Sparrow configured with `turn_taking_patience: high` — patients with MCI need longer response windows and must not be interrupted by the avatar
- Avatar maintains warm, attentive expression during all patient response windows (Raven-1 adapts if patient shows distress)

### VoiceOver / Assistive Technology
- All interactive elements must have meaningful accessibility labels
- Assessment phases that require visual interaction (clock drawing) need documented alternative pathways or clinical override

---

## Design System (Theme/)

- **Primary Color**: Mercy Health navy-teal `#1a5276`
- **Typography**: heroTitle(34) > screenTitle(28) > sectionTitle(24) > body(20) > caption(18)
- **Components**: MCPrimaryButton (60pt), MCSecondaryButton (52pt), MCCard, MCIconCircle, MCProgressBar
- **Spacing**: xs(4) sm(8) md(16) lg(24) xl(32) xxl(48)
- **Style**: Neo-skeuomorphic, card-based, clinical aesthetic
- **Prefix conventions**: `MC*` = design system components, `Mercy*` = brand items

---

## Coding Conventions

### Naming
- **PascalCase**: Types (Views, States, Services, Enums)
- **camelCase**: Properties, functions
- **MC* prefix**: Design system components
- **Mercy* prefix**: Brand items
- **is/has prefix**: Booleans (`isListening`, `hasContent`)
- **UPPERCASE**: Constants (`LISTEN_TIMEOUTS`, `QDRS_QUESTIONS`)

### Patterns
- One primary type per file
- `// MARK:` pragmas to section all files
- `async/await` for ALL async work — no DispatchQueue, no callbacks
- `@MainActor` on all UI-bound services
- `Task { }` for fire-and-forget async
- Graceful fallbacks over thrown errors (never crash on API failure)
- Structs for data models, classes for stateful services
- Never hardcode patient data, PHI, or API keys in source

### SaMD-Specific Coding Rules
- All scoring algorithms must be deterministic — no randomness, no floating-point ambiguity
- Every function that affects clinical decision-making must be flagged with `// MARK: CLINICAL` and have a corresponding unit test
- Every UI component displaying clinical data must have a `// MARK: CLINICAL-UI` comment with design rationale
- No third-party dependency changes without documenting as potential 510(k)-impacting change
- Version-track all scoring logic changes with SRS requirement IDs in commit messages

---

## Competitive Landscape Context

When making design decisions, understand MercyCognitive's position relative to these platforms:

| Competitor | FDA Status | Key Feature | MercyCognitive Differentiator |
|-----------|-----------|-------------|------------------------------|
| **Linus Health** | Class I + Class II (DCTclock) | 700+ CDT digital biomarkers, Apple Pencil | We add voice-guided Qmci + photorealistic AI avatar + Raven-1 facial affect biomarkers |
| **BrainCheck** | Class II cleared | 500+ practices, 400K+ assessments | We use Qmci (superior AUC for MCI) not proprietary battery + avatar + affect biomarkers |
| **Cognivue** | Class II (first FDA-cleared, de novo 2013) | Self-calibrating to patient visual/motor | We add informant assessment (QDRS) + depression gate (PHQ-2) + affect biomarkers |
| **Cogstate (Cognigram)** | Class II (510k) | Playing-card paradigm, language-independent | We capture richer biomarkers (CDT + fluency + affect) + PCP report with billing codes |
| **CognICA (Cognetivity)** | Class II cleared March 2026 | 5-min AI-assisted iPad assessment | We use validated Qmci + photorealistic avatar + multi-modal biomarkers vs proprietary battery |

No current competitor combines: Qmci administration + photorealistic AI avatar (Tavus Phoenix-4) + CDT digital biomarkers + informant assessment + depression gating + facial affect biomarkers (Raven-1) + automated PCP reporting with billing codes.

---

## Immediate Priorities

1. **Tavus CVI avatar integration** — Persistent WebRTC video, Phoenix-4 rendering, Raven-1 perception, Sparrow turn-taking. Core differentiator.
2. **AI scoring enabled** — CoreML CDT scoring, ASR-based word recall, all ML-derived classifications displayed to clinicians with confidence disclosures.
3. **Digital biomarker extraction** — CDT drawing kinematics (pressure, velocity, pauses), verbal fluency clustering/switching, facial affect via Raven-1, speech prosody.
4. **PDF/CSV report export** — PCPReportView printable output with subtest scores, composite risk, recommended labs, billing codes (CPT 99483), referral recommendation.
5. **State persistence** — SwiftData serialization so interrupted assessments can resume.
6. **Gateway FastAPI on RunPod** — Clinical router, scoring, `conversation.echo` triggers.
7. **Enterprise BAAs** — Tavus, RunPod, ElevenLabs. Required before PHI enters pipeline.

---

## Known Limitations

1. **No PDF/CSV export** — PCPReportView has no printable output yet.
2. **No state persistence** — interrupted assessments are lost.
3. **No Epic EHR integration** — planned. PDF report is the workaround for now.
4. **Deprecated services in codebase** — PersonaPlexService, AudioArbitrator, ElevenLabsService, SpeechService from prior architecture. Clean up when convenient.
5. **CDT biomarker extraction pipeline not built** — Canvas captures strokes but feature extraction not implemented.
6. **Verbal fluency clustering/switching not implemented** — Troyer framework analysis pending.
7. **Speech prosody extraction not implemented** — openSMILE/CoreML pipeline pending.

---

## Installed Claude Code Tools

### claude-mem (thedotmack/claude-mem)
Persistent memory across sessions. Auto-injects context on SessionStart. Key memories: scoring thresholds, Tavus CVI architecture, assessment phase routing, avatar configuration, Raven-1 perception pipeline.

### obra/superpowers
Enforces brainstorm -> plan -> test -> build workflow. Use for any new module or complex feature. Do NOT start coding without a design phase.

### affaan-m/everything-claude-code (ECC)
Full agent harness. Key agents:
- `@tdd-guide` — for all scoring, risk matrix, and NLP validation logic
- `@security-reviewer` — run before any commit touching Services/ or Models/
- `@architect` — for Tavus CVI integration, Epic FHIR, and RunPod gateway design decisions

### mcp-voice-hooks (johnmatthewtennant)
Voice interface for development. Speak clinical requirements directly during coding sessions.

---

## Build & Run

```bash
# Open in Xcode
open VoiceMiniCog.xcodeproj

# Build via CLI
xcodebuild -scheme VoiceMiniCog -destination 'platform=iOS Simulator,name=iPhone 16'

# Run tests
xcodebuild test -scheme VoiceMiniCog -destination 'platform=iOS Simulator,name=iPhone 16'
```

### Requirements
- Xcode 15+ (Swift 5.9 for @Observable)
- iOS 15+ deployment target
- Microphone + Camera permissions (Info.plist: NSMicrophoneUsageDescription + NSCameraUsageDescription — camera required for Raven-1 perception via WebRTC)
- Tavus API key + configured Persona (Dr. Claire) + trained Replica
- RunPod instance running gateway FastAPI endpoint (OpenAI-compatible `/v1/chat/completions`)
- Daily SDK for WebRTC (Tavus provides room URL per conversation via Create Conversation API)
- AVSpeech fallback works offline for text-only TTS without Tavus (no avatar)

### Gateway Setup (RunPod)
```bash
# FastAPI endpoint exposing OpenAI-compatible /v1/chat/completions
# Receives: ASR transcription from Tavus as user messages + Raven-1 perception context
# Returns: Clinical response text (or triggers conversation.echo for verbatim prompts)
# Manages: Assessment phase state, scoring, biomarker aggregation

pip install fastapi uvicorn
uvicorn gateway:app --host 0.0.0.0 --port 8080

# Tavus calls this endpoint as its LLM layer via:
# layers.llm.base_url = "https://your-runpod-endpoint/v1"
```

---

## Companion Skill File

A separate `.claude/skills/samd-docs/skill.md` exists for on-demand FDA documentation generation. It is NOT loaded every session (token efficiency). Invoke explicitly when generating 510(k) SDS documents, risk analyses, or traceability matrices. The skill covers:
- Intended use, inputs, outputs, failure modes per module
- Risk classification per IMDRF SaMD framework (I to IV)
- IEC 62304 software safety class mapping (A/B/C)
- Traceability from SRS -> design -> test

Human verification is mandatory for all AI-generated regulatory documentation.
