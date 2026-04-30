# Reference Dataset Review

## Overview

This document reviews each dataset and normative source listed for `data/reference/`.
For each item it records: access status, implementation target, key limitations, and
any action required before the source is used in a clinical report or scoring algorithm.

---

## Free / Immediate Downloads

### 1. Davoudi 2021 — Digital Clock Drawing Kinematic Norms

| | |
|---|---|
| **Source** | PMC8379638 — *J Alzheimers Dis* 2021;82(1):59–70 |
| **Population** | n=430, cognitively well US adults 55+, Apple Pencil on iPad |
| **Data** | Supplemental Tables 2–19; age-stratified means and SDs for stroke count, completion time, think-time %, latencies, graphomotor speed/jerk/pressure |
| **Access** | Free; PMC open access |
| **Target file** | `Sources/MercyCognitive/Norms/KinematicNormsDavoudi2021.swift` |
| **Status** | ✅ Download and implement |

**Implementation notes:** Tables are stratified by age decade (55–64, 65–74, 75–84, 85+),
education, and handedness. Also stratified by number-anchor condition (command vs. copy).
Implement as a Swift struct with a `lookup(age:education:handedness:condition:) -> KinematicNormsBand`
method returning `(mean: Double, sd: Double)` per feature. The Apple Pencil hardware
matches this study's instrument exactly — this is the primary kinematic norm source for
cognitively healthy older US adults.

**Limitation:** Single US Northeast/Florida recruitment site; predominantly White; n
becomes small in the 85+ band. Cross-validate against Piers 2017.

---

### 2. Piers 2017 — Framingham Heart Study Digital Clock Drawing Norms

| | |
|---|---|
| **Source** | PMC7286350 — *J Alzheimers Dis* 2017;60(4):1611–1620 |
| **Population** | Framingham Heart Study Offspring Cohort, age 43–91, community-based |
| **Data** | Age-band means for graphomotor and latency parameters from the digital CDT |
| **Access** | Free; PMC open access |
| **Target file** | `Sources/MercyCognitive/Norms/KinematicNormsPiers2017.swift` |
| **Status** | ✅ Download and implement; use as cross-validation against Davoudi 2021 |

**Implementation notes:** Piers 2017 uses the same dCDT platform (Randall Davis/MIT
system, same pipeline as Davoudi). Age-band granularity is coarser than Davoudi (decadal
bins only). Implement identically to `KinematicNormsDavoudi2021.swift`. Where Davoudi and
Piers means diverge by more than 0.5 SD, log a warning in `KinematicScoringEngine` and
flag the feature for MERIDIAN-1 sensitivity analysis.

**Limitation:** Framingham cohort is predominantly White, New England-based. Does not
stratify by handedness. Primary use is cross-validation; Davoudi 2021 is the first-line
norm for Apple Pencil kinematic features.

---

### 3. Mayo Normative Studies 2024 — TMT-B and Animal Fluency

| | |
|---|---|
| **Source** | PMC11014770 — *J Int Neuropsychol Soc* 2024;30(4):389–401 |
| **Population** | n=4,428, cognitively unimpaired, Olmsted County MN, ages 30–91 |
| **Data** | Regression-based normative equations for TMT-B completion time, Boston Naming Test, and Category Fluency (animals); adjusts for age, age², sex, education |
| **Access** | Free; PMC open access |
| **Target file** | `Sources/MercyCognitive/Norms/MayoNorms2024.swift` |
| **Status** | ✅ Extract regression equations; implement as z-score calculator |
| **Primary use** | White/English-speaking patients |

**Implementation notes:** Equations produce a predicted mean score; z-score =
`(rawScore − predictedMean) / RMSE`. Implement as
`MayoNorms2024.zScore(measure:rawScore:age:sex:education:) -> Double`.
Measures: `tmtBSeconds`, `animalFluencyCount`, `bostonNamingTest`.

**Limitation:** Olmsted County sample is 97% White and highly educated relative to national
averages. Do not apply to Hispanic or African American patients — use TMAANS or
Heaton 2004 respectively for those populations. Midwest geography is a genuine advantage
for the Mercy Toledo patient population.

---

### 4. TMAANS — Texas Mexican American Adult Normative Studies

| | |
|---|---|
| **Source** | PMC5875704 — *Dev Neuropsychol* 2018;43(1):1–26 |
| **Population** | n=797 Mexican American adults 40+, Texas; ~52% Spanish-speaking |
| **Data** | Education-stratified scaled score tables (education bins: 0–6, 3–9, 6–12, 12+; age bins: 40–60, 61+) for TMT-A, TMT-B, animal naming, and memory measures |
| **Access** | Free; PMC open access |
| **Target file** | `Sources/MercyCognitive/Norms/TMAANSNorms.swift` |
| **Status** | ✅ Extract Tables 11–18 (executive/language) and 19–26 (memory); implement as scaled-score lookup |
| **Primary use** | Hispanic/Mexican American patients |

**Implementation notes:** Education is the primary stratification variable (dominant
predictor, R²=0.30–0.32 for TMT measures). Implement as a two-dimensional lookup:
`TMAANSNorms.scaledScore(measure:rawScore:educationBin:ageBin:) -> Int`.
`EducationBin` enum: `.e0_6`, `.e3_9`, `.e6_12`, `.e12plus`.
`AgeBin` enum: `.a40_60`, `.a61plus`.

**Limitation:** Sample is Texas-based; caution applying to Toledo-area Hispanic patients
whose origin countries may differ. Cell sizes are small in some bins (n < 30) — flag
these in code with a `lowNWarning` field. Do not use for non-Mexican-American Hispanic
patients (Puerto Rican, Cuban, Dominican).

---

### 5. NP-NUMBRS — Spanish-Speaker TMT Norms

| | |
|---|---|
| **Source** | PMC8240160 — *Clin Neuropsychol* 2021;35(2):308–323 |
| **Population** | n=252 native Spanish-speakers, ages 19–60, San Diego/Tucson US-Mexico border |
| **Data** | Demographically adjusted T-score equations for TMT-A and TMT-B time; fractional polynomial regression adjusting for age, sex, education |
| **Access** | Free; PMC open access |
| **Target file** | `Sources/MercyCognitive/Norms/NPNUMBRSNorms.swift` |
| **Status** | ✅ Implement T-score equations from Table 8 directly in Swift |
| **Primary use** | Secondary reference for native Spanish-speaking patients; supplement TMAANS |

**Implementation notes:** T-score equations (Table 8) take scaled score, age (years),
education (years), and sex (Male=1, Female=0) as inputs. Age range 19–60 only — do not
extrapolate above 60; log a range-exceeded warning and fall back to TMAANS for patients
over 60. The study used a Spanish-language TMT-B with a "Ch" variant for patients whose
alphabet includes Ch between C and D; note this in `NPNUMBRSNorms` documentation.

**Limitation:** Southwest US-Mexico border sample; younger age ceiling (60) than clinical
need. Bilingualism affects TMT-B performance in this sample — patients with higher English
fluency performed better. For bilingual patients, document language dominance in session
metadata.

---

### 6. NACC UDS Normative Calculator — Word List Recall

| | |
|---|---|
| **Source** | https://www.alz.washington.edu/WEB/npsych_means.html; Shirk et al. 2011 (*Alzheimer's Research & Therapy* 3:32); Weintraub et al. 2018 (PMC6193830) |
| **Population** | n=3,268 cognitively normal UDS participants; Shirk et al. (2011) |
| **Data** | Interactive web calculator; z-scores adjusted for sex, age, education for all UDS3 neuropsychological tests including word list learning and recall |
| **Access** | Free online calculator |
| **Target file** | `Sources/MercyCognitive/Norms/NACCWordListNorms.swift` |
| **Status** | ✅ Extract regression coefficients by querying calculator systematically; implement offline |

**Implementation notes:** Do not call the web calculator at runtime — extract the underlying
regression coefficients by sampling the calculator across the age × sex × education space
and fitting the equations. Implement as
`NACCWordListNorms.zScore(measure:rawScore:age:sex:educationYears:) -> Double`.
Measures: `wordListLearning` (trials 1–3 sum), `wordListRecall` (delayed), `wordListRecognition`.
The UDS3 battery uses a 10-word list; note that the Qmci uses a 5-word list — norms are
not directly interchangeable. Document this in the norm file header.

**Limitation:** Norms derived from UDS convenience sample (Alzheimer's Disease Center
patients and volunteers); may over-represent high-education White participants. Updated
UDS3 norms (Weintraub et al. 2018) are the current standard and supersede earlier versions.

---

### 7. DARWIN Dataset (Cilia et al. 2022)

| | |
|---|---|
| **Source** | https://archive.ics.uci.edu/dataset/732/darwin; DOI: 10.24432/C55D0K |
| **Population** | 174 participants (Alzheimer's disease vs. healthy controls); 25 handwriting tasks × 18 kinematic features |
| **Access** | Free; CC BY 4.0; direct CSV download |
| **Storage** | `data/reference/darwin/data.csv` |
| **Status** | ✅ Download immediately; use for StrokeAnalyzer feature validation |

**Implementation notes:** DARWIN features include: air_time, paper_time, total_time,
gmrt_in_air, gmrt_on_paper, mean_speed_in_air, mean_speed_on_paper, mean_acc_in_air,
mean_acc_on_paper, mean_jerk_in_air, mean_jerk_on_paper, num_of_pendown, pressure_mean,
pressure_var, max_x_extension, max_y_extension, disp_index — 18 features × 25 tasks
= 451 columns plus ID. These map directly to `StrokeAnalyzer` output fields.

Run `tests/StrokeAnalyzerDARWINValidationTests.swift` to verify that feature values
reproduced by `StrokeAnalyzer` on the DARWIN tasks fall within ±5% of published values
on overlapping tasks. This is a regression test, not a clinical norm.

**Limitation:** DARWIN uses a Wacom digitizing tablet, not Apple Pencil. Pressure
calibration and sampling rate differ. Geometric features (speed, jerk, air time) should
reproduce within tolerance; pressure-dependent features may diverge and should be flagged
rather than failed in validation tests.

---

## Free with Registration / DUA

### 8. NACC UDS v3 Full Dataset

| | |
|---|---|
| **Source** | https://naccdata.org/requesting-data/data-request-process |
| **Population** | 52,000+ participants; includes Cleveland ADRC (Ohio site) |
| **Data** | TMT-B, animal fluency, word list learning/recall/recognition, Benson figure; longitudinal |
| **Access** | Data use agreement; ~2 business days; free for research |
| **Status** | ⚠️ Submit DUA now — do not wait for MERIDIAN-1 IRB |

**Action:** Submit data use agreement at https://naccdata.org/requesting-data/data-request-process.
Specify: Forms C2 (neuropsychological data), age 50+, cognitively normal at baseline
(`NORMCOG == 1`), English-speaking (`PRIMLANG == 1`). Request longitudinal follow-up
visits to enable conversion analysis.

**Use:** (a) Calibrate composite cutoffs for TMT-B + animal fluency; (b) build and
validate scoring algorithm for word list recognition; (c) generate Ohio-site reference
distributions using Cleveland ADRC subset as a geographically proximate comparator for
the Mercy Toledo population.

**Limitation:** NACC UDS data are observational and convenience-sampled; not population-
representative. MCI exclusion at baseline is based on clinical consensus, not biomarker
confirmation. Use for algorithm calibration, not as ground truth for sensitivity claims.

---

### 9. HRS Public Data — Health and Retirement Study

| | |
|---|---|
| **Source** | https://hrs.isr.umich.edu/data-products/access-to-public-data; cognition module at https://hrs.isr.umich.edu/data-products/cognition-data |
| **Population** | Nationally representative; Midwest oversampled; biennial waves from 1992 |
| **Data** | Immediate and delayed word recall (10-word list), serial 7s, TICS, proxy cognition measures |
| **Access** | Free download after registration; no DUA required for public files |
| **Status** | ⚠️ Register and download public cognition files |

**Use:** Population-representative word recall reference distributions for Midwest adults
50+. HRS uses a 10-word list rather than Qmci's 5-word list, but age-normed performance
distributions are useful for contextualizing delayed recall z-scores. The Midwest
representativeness is a genuine advantage for the Mercy patient population.

**Limitation:** HRS word recall is phone-administered; examiner-administered norms
(NACC, Mayo) are more appropriate for in-person digital administration. Use HRS for
population prevalence context, not as the primary norm source.

---

## Requires Purchase

### 10. Heaton et al. 2004 — Race-Adjusted TMT-B Norms

| | |
|---|---|
| **Source** | *Revised Comprehensive Norms for an Expanded Halstead-Reitan Battery: Demographically Adjusted Neuropsychological Norms for African American and Caucasian Adults* — Heaton, Miller, Taylor & Grant (2004), PAR Inc. |
| **Purchase** | https://www.parinc.com/Products/Pkey/85; approximately $200 for manual + scoring software |
| **Population** | Ages 20–85; African American and Caucasian adults; native English speakers educated in the US |
| **Status** | ⚠️ Purchase before MERIDIAN-1 enrollment opens |

**Rationale:** No free equivalent provides race-adjusted TMT-B T-scores for African American
patients. Applying White norms to African American patients in a clinical tool that will
be used in a racially diverse population inflates apparent impairment rates and creates a
disparate false-positive burden — exactly the pattern documented in NP-NUMBRS when
non-Hispanic White norms were applied to Spanish speakers (Suarez et al., 2021). Mercy
Health Neurology Specialists serves a significant Black patient population; this is a
clinical necessity, not a supplementary reference.

**Implementation:** Implement as `HeatonNorms2004.swift`. Software outputs T-scores;
extract T-score equations from manual. The PAR scoring program uses proprietary software
but the manual contains the underlying regression tables. Confirm with PAR that
extraction for internal clinical software use is covered under the purchase license.

---

## Skipped

### IEEE DataPort Apple Pencil PD Spirals
Institutional subscription required (~$4,500/year). Replaced by local healthy-control
collection at Mercy (Item 11). No action required.

### UCI Parkinson Spiral Drawings
Wacom-based; disease model is Parkinson's disease, not MCI. Synthetic ground truth testing
covers the validation use case. No action required.

---

## Local Data Collection (Highest Priority)

### 11. Mercy Health Apple Pencil Healthy Control Reference Collection

| | |
|---|---|
| **IRB path** | Mercy Health IRB; expedited or exempt review (healthy volunteer normative data) |
| **Target n** | 30–50 participants |
| **Eligibility** | Age 50–85; no diagnosed cognitive or movement disorder; able to use iPad; English or Spanish speaking |
| **Recruitment** | Clinic staff, residents, NPs, family members of patients in waiting areas, community volunteers at Mercy Health Neurology Specialists Toledo |
| **Protocol** | Full 6-module battery on iPad with Apple Pencil; single session, ~15 minutes including consent |
| **Storage** | `data/reference/mercy-controls/` (de-identified; IRB-compliant) |
| **Status** | 🔴 Submit IRB application before MERIDIAN-1 IRB — local norms are a prerequisite for the MERIDIAN-1 feasibility argument |

**Outputs:**
- (a) Toledo-specific reference distributions for all Apple Pencil kinematic features
- (b) Apple Pencil pressure/velocity/acceleration calibration ranges for adults 50–85
- (c) Feasibility evidence for MERIDIAN-1 IRB submission
- (d) Publishable normative paper (target: *Archives of Clinical Neuropsychology* or
  *Journal of Alzheimer's Disease*)
- (e) Preliminary 510(k) supporting evidence

**Why this cannot wait:** Published norms (Davoudi, Piers) were collected on iPad +
Apple Pencil but at different clinical sites with different patient populations.
Pressure and velocity ranges vary by device generation and user motor characteristics.
Without a local reference collection, kinematic z-scores will be estimated against
geographically and institutionally mismatched norms. The Mercy collection is the
data substrate that transforms the published norms from approximations into calibrated
site-specific benchmarks.

---

## Norm Selection by Patient Demographics

The following matrix summarizes which norm source to apply by patient demographic profile.
All selections are subject to revision after MERIDIAN-1 data analysis.

| Measure | White / English | Hispanic / Mexican American | Hispanic / Spanish-speaking | African American |
|---|---|---|---|---|
| TMT-B (completion time) | MayoNorms2024 | TMAANSNorms | NPNUMBRSNorms (age ≤60) / TMAANSNorms (age >60) | Heaton2004 |
| Animal fluency (count) | MayoNorms2024 | TMAANSNorms | TMAANSNorms | MayoNorms2024 (flagged) |
| Word list delayed recall | NACCWordListNorms | TMAANSNorms (CERAD subset) | TMAANSNorms (CERAD subset) | NACCWordListNorms (flagged) |
| Clock kinematics | KinematicNormsDavoudi2021 | Mercy local (pending) | Mercy local (pending) | Mercy local (pending) |

Cells marked *(flagged)* indicate that a norm mismatch may inflate apparent impairment;
the report renderer should append: *"Norm source not validated for this demographic group.
Interpret with caution."*
