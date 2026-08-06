# Literature Synthesis — four papers, 2026-08-05

Sources reviewed in full:

1. **Raksasat et al. 2023**, *Sci Rep* 13:18113 — API-Net for Shulman CDT scoring.
   [DOI](https://doi.org/10.1038/s41598-023-44723-1) · CC BY 4.0
2. **Chan et al. 2022**, *Neuropsychol Rev* 32:566–576 — systematic review and
   meta-analysis of digital vs paper drawing tests.
   [DOI](https://doi.org/10.1007/s11065-021-09523-2) · PROSPERO CRD42020166750
3. **Unger et al. 2024**, *Stud Health Technol Inform* (GMDS) 317:251 — scoping
   review of digital drawing tools. [DOI](https://doi.org/10.3233/SHTI240864) · CC BY-NC 4.0
4. **Altuna 2026**, *Front Neurol* 17:1870463 — from cognitive screening to
   digital phenotyping in primary care.
   [DOI](https://doi.org/10.3389/fneur.2026.1870463) · CC BY

---

## 1. The headline: the meta-analysis validates the product thesis, with numbers

Chan et al. pooled 90 studies / 22,567 participants. For **MCI screening**:

| Instrument | Sensitivity | Specificity | AUC |
|---|---|---|---|
| **Digital CDT** | **0.86** (0.75–0.92) | **0.92** (0.69–0.98) | **87%** (84–90) |
| Paper CDT, brief scoring (≤9 pts) | 0.63 (0.49–0.75) | 0.77 (0.68–0.84) | 77% (74–81) |
| Paper CDT, detailed scoring (>9 pts) | 0.63 (0.56–0.71) | 0.72 (0.65–0.78) | 74% (69–77) |

Digital CDT significantly outperformed both paper methods for MCI
(**P = 0.02** vs brief, **P < 0.001** vs detailed).

**The crucial asymmetry.** For *dementia* screening there was **no significant
difference** — digital AUC 92%, paper brief 88%, paper detailed 87%
(P = 0.33 and P = 0.35).

> Digital clock drawing's advantage is **specific to MCI**. For established
> dementia, paper is just as good.

That is the single strongest evidence-based justification for this product:
MercyCognitive targets MCI detection in primary care, which is precisely and
only where the digital modality earns its keep. It should be quoted in the
pilot protocol, the IRB submission, and the business case.

### Action: the pilot's AUC target is set too low

`mercy-pilot-protocol.md` states a primary endpoint of **AUC ≥ 0.80**. The
pooled digital-CDT AUC for MCI is already **0.87**. A target of 0.80 is below
the published state of the field and would be hard to defend as a success
criterion. Either raise the target to ≥0.85 or state explicitly why a lower
threshold is acceptable for a primary-care (rather than memory-clinic)
population — spectrum effects are a legitimate argument, but they must be made,
not assumed.

---

## 2. The image-only ceiling this project exists to break

Raksasat et al. is state of the art for automated Shulman scoring on 3,108
clocks (majority vote of three neuropsychologists/neurologists). On the
**score 4 vs score 5** task — minor visuospatial deficit vs normal, the early-MCI
boundary:

| Model | Accuracy | F1 |
|---|---|---|
| ResNet-152 | 0.7877 | 0.7855 |
| **API-Net (best)** | **0.8033** | **0.8013** |

Roughly **1 in 5 misclassified** at the boundary that decides investigation.
Their stated cause: residual errors are on *visually similar* images.

This is a data limitation, not a modelling one. Two clocks can be near-identical
as images and cognitively opposite — one drawn fluently in 25 s, the other in
90 s with 12 s of hesitation before the hands and three corrections. The scanned
image cannot represent the difference. The process record can.

Their own discussion invites the extension ("other modalities such as speech
sounds, fluid biomarkers, and brain imaging") and their reference list cites both
Davoudi 2021 and Souillard-Mandar's THink work — they knew the kinematic
literature existed but had only paper-based MoCA scans.

**Use 0.8033 / F1 0.8013 as the published comparison target for the 4-vs-5 task.**
Not as an equivalence: their cohort is Thai, hospital-recruited, ages 29–90,
F:M 3:1, which differs from Mercy primary care.

**Licensing note.** The GitHub repo carries no license file, but the paper is
CC BY 4.0 and states: "To foster such a direction and enable a direct
benchmarking for interested researchers, we have made our dataset and
implementation publicly available." Ethics: Chulalongkorn no. 383/2022,
de-identified. Published intent for research benchmarking is documented — cite
it when requesting explicit permission.

---

## 3. On-air movement: a capture gap now backed by literature

Chan et al., background section:

> "Studies showed that **on-air movements can enhance the sensitivity of
> identifying patients with MCI** (Garre-Olmo et al., 2017; Müller et al., 2017).
> The **pressure applied when drawing** can be another indicator to discriminate
> elders with MCI and healthy aging (Faundez-Zanuy et al., 2013)."

`UITouchCaptureView` handles only `touchesBegan/Moved/Ended/Cancelled`. There is
no `UIHoverGestureRecognizer` or `pencilInteraction` hover capture, so **in-air
movement is not recorded** — `air_time_s` is an inferred duration, never a
trajectory.

This was previously logged as a "nice to have." It is now a substantive gap with
direct literature support, in the exact population of interest. Apple Pencil
hover is available on M2 iPad Pro and later. **Recommendation: add hover capture
to `UITouchCaptureView` before the MERIDIAN-1 capture visits begin** — retrofitting
it later means the early cohort lacks the channel and cannot be pooled.

---

## 4. Altuna 2026: a ready-made readiness framework and the right positioning

### 4.1 Positioning language that matches the Phase 1 regulatory posture

Altuna argues digital cognitive screening should be understood as

> "a **governed triage and phenotyping layer** rather than a stand-alone
> diagnostic label"

and that "digital tools should not independently assign an etiological
diagnosis." That is the CDS-exemption argument expressed in clinical-literature
terms, from a 2026 peer-reviewed review. It is stronger framing than the
regulatory strategy currently uses, and it is citable.

### 4.2 The staged pathway matches the existing assessment flow

Altuna's Figure 1: clinical entry points → brief clinical assessment (incl.
informant tools AD8/IQCODE) → **digital phenotyping** (incl. digital clock
drawing, graphomotor metrics) → biological anchoring (p-tau217, MRI, amyloid PET)
→ clinical action (referral, treatment-readiness, monitoring).

MercyCognitive's QDRS (informant) → PHQ-2 (mood confound) → Qmci (brief
performance) → PCP report → anti-amyloid triage maps onto stages 1–2 and 5.
The **digital phenotyping layer (stage 3) is what StrokeAnalyzer adds**, and the
anti-amyloid triage already anticipates stage 4.

### 4.3 Table 2 as a validation audit checklist

Altuna proposes 12 domains for appraising whether a digital screening tool is
ready for clinical use. Assessed against MercyCognitive today:

| Domain | Status | Gap |
|---|---|---|
| Intended use and target condition | 🟡 partial | Prespecified use case exists; decision threshold and expected downstream action need documenting |
| Analytical validity | 🔴 gap | No device-equivalence or missing-data-rate evidence; single iPad model tested |
| Measurement properties | 🔴 gap | No test–retest, ICC, or practice-effect data |
| Construct validity | 🟡 partial | Qmci/QDRS validated; StrokeAnalyzer features not yet mapped to neuropsych domains |
| Diagnostic validity | 🔴 gap | The n=40 pilot is designed to produce this |
| Biomarker/etiological validity | 🔴 gap | No p-tau217 or amyloid correlation planned |
| Longitudinal validity | 🔴 gap | Cross-sectional only; no within-person change data |
| Clinical actionability | 🟢 strong | PCP report + anti-amyloid triage define concrete downstream action |
| **Equity and measurement invariance** | 🔴 **gap** | No subgroup calibration by education, language, or digital literacy — see warning below |
| Interpretability and uncertainty | 🟡 partial | Scoring is transparent; no uncertainty estimates surfaced |
| Workflow/implementation validity | 🟡 partial | iPad-first design; no completion-rate or staff-burden data |
| Regulatory and governance readiness | 🟡 partial | CDS-exemption posture documented; BAAs and IRB still outstanding |

### 4.4 The equity warning is specific and applies here

> "A digital version of a biased measure may preserve the same educational,
> cultural, sensory, or motor biases as its analog predecessor."

Two concrete instances for this project:

- **Education bias is documented in clock drawing.** Davoudi 2021 found digit
  misplacement differed by education (<13 yrs: 77.88° vs >16 yrs: 63.27°) and
  anchoring prevalence ranged 34.09% (≤high school) to >50% (college). Any
  StrokeAnalyzer feature will inherit this. Stratified reporting is required,
  not optional.
- **Motor confounds.** Tremor, arthritis, and neuropathy all alter graphomotor
  features without cognitive change. The spectral features are especially
  exposed. Exclusion criteria and a motor-confound covariate are needed in the
  pilot protocol.

---

## 5. Unger et al. 2024 — field context

Scoping review of 37 unique digital drawing tools, selected specifically for
tools that "not only evaluate the final drawing, but also **process data**."
Two dominant application areas: tremor detection and cognitive-state assessment.
Roughly 75% published after 2014; 86.5% target adults.

Useful mainly as a landscape citation and a source of comparator tools
(their Table 2 lists hardware, task, and condition for all 37). Notably, most
listed cognitive-state tools use digitizer tablets or touch screens; very few
use a stylus-on-tablet consumer device in a clinical workflow, which is where
MercyCognitive sits.

---

## 6. Recommended actions, in priority order

1. **Raise the pilot AUC target** from ≥0.80 to ≥0.85, or document why lower is
   acceptable for primary care. Cite Chan et al. pooled AUC 0.87.
2. **Add Apple Pencil hover capture** to `UITouchCaptureView` before MERIDIAN-1
   capture begins. On-air movement enhances MCI sensitivity (2 citations) and
   retrofitting splits the cohort.
3. **Quote the MCI-specific advantage** (digital AUC 87% vs paper 74–77%,
   P<0.001; no advantage for dementia) in the pilot protocol, IRB submission, and
   business case. It is the strongest single justification available.
4. **Adopt Altuna's Table 2 as a standing audit** — the four red domains
   (analytical validity, measurement properties, longitudinal validity, equity)
   are the roadmap beyond the pilot.
5. **Re-frame the regulatory posture** using Altuna's "governed triage and
   phenotyping layer" language.
6. **Add education stratification and motor-confound exclusion** to the pilot
   protocol.
7. **Use 0.8033 / F1 0.8013** as the published image-only benchmark for the
   4-vs-5 task, and cite Raksasat's data-availability statement when requesting
   dataset permission.
