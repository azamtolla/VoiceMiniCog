# todo.md — MercyCognitive Development Tracker
> Last updated: March 28, 2026

## Legend
- 🔴 BLOCKER — Cannot proceed to clinical use without this
- 🟡 HIGH — Required for demo / prototype quality
- 🟢 MEDIUM — Needed before 510(k) but not for demo
- ⚪ LOW — Future enhancement / Phase 3

---

## 🔴 BLOCKERS (Resolve Before Any Patient Data)

- [ ] **Tavus CVI integration** — WebRTC via Daily SDK not yet implemented in Swift. Replica and Persona not created. PRIMARY DEV BLOCKER.
- [ ] **Gateway FastAPI endpoint** — Phase-aware clinical router on RunPod not yet built. OpenAI-compatible /v1/chat/completions.
- [ ] **Enterprise BAAs (all 3 vendors)** — Tavus (Enterprise, exclude AI training on PHI), RunPod (Secure Cloud ONLY), ElevenLabs (Enterprise + Zero Retention Mode, verify TTS API coverage). ALL required before PHI enters pipeline.
- [ ] **Schedule FDA Pre-Submission (Q-Sub)** — Free CDRH consultation. Confirm NSR determination, predicate strategy, evidence requirements BEFORE enrollment.
- [ ] **Medicare Coverage Analysis** — Formal legal opinion on AWV billing during investigational device study. False Claims Act risk. Coordinate with Mercy Health compliance.

---

## 🟡 HIGH PRIORITY (Required for Demo / Pre-Clinical)

- [ ] **PDF/CSV report export** — PCPReportView needs print/export via PDFKit. Required before any PCP clinic use.
- [ ] **State persistence** — SwiftData serialization so interrupted assessments can resume.
- [ ] **Unit tests for scoring logic** — ResponseCheckers, risk matrix, all Qmci subtest scorers. IEC 62304 compliance.
- [ ] **IRB protocol writing** — Full board review application to Mercy Health IRB. NSR IDE documentation, informed consent per 21 CFR Part 50. Target submission within 30 days.
- [ ] **Identify second enrollment site** — At least 1 site beyond Mercy Health Toledo for demographic diversity.
- [ ] **Raven-1 affect data pipeline** — Define storage schema, capture framework. Research only (excluded from initial 510(k)).

---

## 🟢 MEDIUM PRIORITY (Pre-510(k) Submission)

- [ ] **CDT digital biomarker extraction** — Canvas captures strokes but temporal/graphomotor feature extraction not implemented.
- [ ] **Verbal fluency NLP** — Basic word counting exists. Clustering/switching (Troyer framework) not implemented.
- [ ] **QMSR/ISO 13485 compliance** — Engage contract QMS consultant + external auditor. Solo dev cannot self-audit.
- [ ] **SBOM documentation** — Software Bill of Materials for all cloud dependencies. Required by FDA cybersecurity guidance.
- [ ] **RunPod endpoint stability** — Gateway FastAPI needs stable URL.
- [ ] **Formative usability study** — 5–10 clinicians, iterative.
- [ ] **Summative usability study** — 15–25 users, PCP + memory clinic.
- [ ] **Clinical knowledge RAG** — LightRAG microservice powering PCPReportView recommendations.
- [ ] **Epic EHR integration** — SMART-on-FHIR R4 (requires Epic App Orchard approval).

---

## ⚪ LOW / PHASE 3 (Post-Clearance)

- [ ] **Raven-1 facial affect 510(k) claims** — Subsequent submission or De Novo after core platform clears.
- [ ] **Speech prosody extraction** — openSMILE eGeMAPSv02 or Praat integration. Jitter/shimmer/rate.
- [ ] **Advanced CDT biomarker claims** — 700+ digital features beyond Shulman scoring.
- [ ] **Referral automation** — n8n workflow for auto-generating memory clinic referrals.
- [ ] **Offline mode** — Tavus requires internet. AVSpeech text-only fallback exists but no avatar fallback.
- [ ] **Monitor Ohio HB 525** — AI emotional state detection prohibition. Could impact Raven-1 if enacted.

---

## 510(k) SUBMISSION MILESTONES

| Milestone | Target Month | Status |
|-----------|-------------|--------|
| Q-Sub FDA meeting | 0–1 | ❌ Not scheduled |
| Medicare Coverage Analysis | 0–1 | ❌ Not started |
| Enterprise BAAs executed | 1 | ❌ Not started |
| Gateway FastAPI stable | 1 | ❌ Not built |
| PDF report export | 1 | ❌ Not built |
| SBOM initiated | 1 | ❌ Not started |
| IRB submission (NSR IDE) | 1–2 | ❌ In preparation |
| QMS consultant engaged | 2 | ❌ Not started |
| IRB approval | 2–4 | ⏳ Pending submission |
| Second site identified | 2–3 | ❌ Not started |
| PCP enrollment begins | 4 | ⏳ Pending IRB |
| Formative usability | 4–5 | ⏳ Pending |
| Enrollment complete (300–400 pts) | 10–18 | ⏳ Pending |
| Summative usability | 16–18 | ⏳ Pending |
| Data lock + analysis | 18–20 | ⏳ Pending |
| 510(k) submission | 23 | ⏳ Pending |
| FDA clearance (core) | 29–32 | ⏳ Pending |
| Phase 3: Affect biomarkers | Post-clearance | ⏳ Future |

---

## COMPLETED ✅
- [x] CLAUDE.md comprehensive project spec (v3.1 regulatory update)
- [x] SwiftUI app scaffold with all views
- [x] Assessment flow architecture (Home → QDRS → PHQ-2 → Qmci → Report)
- [x] @Observable state management pattern
- [x] Design system (MCDesign, MercyColors, MCComponents)
- [x] CDTScorer CoreML model (on-device, Shulman 0–5)
- [x] Basic ResponseCheckers (word matching, fluency counting)
- [x] Regulatory strategy defined (NSR IDE → 510(k) → Phase 3)
- [x] Predicate device analysis (BrainCheck, Cognivue, Cogstate, Linus Health)
- [x] Tavus CVI architecture design (Option C: Gateway as Custom LLM)
- [x] Moshi/PersonaPlex evaluation and rejection (documented rationale)
- [x] HIPAA data flow analysis completed
- [x] Validation study protocol designed (300–400 patients, multi-site)
