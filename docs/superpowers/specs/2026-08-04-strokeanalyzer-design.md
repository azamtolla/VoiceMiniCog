# StrokeAnalyzer — Process-Feature Extraction for Pencil Tasks (Design)

**Date:** 2026-08-04
**Status:** Draft — pending Tolla review
**Authors:** Tolla + Claude
**Supersedes:** the `StrokeAnalyzer` sketch in Plan 3 Task 1
(`docs/superpowers/plans/2026-04-29-plan-3-tmtb-strokeanalyzer-clinical-docs.md`) —
see §9 for exactly what changes and why.

---

## 1. Goal

Extract **process-based** features from Apple Pencil stroke data captured during
Clock Drawing (and later TMT-B): the *how* of drawing rather than the finished
picture — timing, kinematics, stroke sequence, and planning strategy — as
research-only measures supporting the MERIDIAN-1 study and eventual clinical
validation.

Clinical motivation: 92% of MCI at Mercy Health is undiagnosed. Process measures
of clock drawing (think:ink ratio, planning strategy, pause structure) discriminate
early impairment that a scored image misses, because the executive load of clock
drawing is expressed in *when and in what order* the pen moves, not in the ink.

### 1.1 The published ceiling this work exists to break

Raksasat et al. 2023, *Sci Rep* 13:18113
([DOI](https://doi.org/10.1038/s41598-023-44723-1), CC BY 4.0) is the current
state of the art for automated Shulman scoring, on a corpus of 3,108 clocks
scored by majority vote of three experienced neuropsychologists/neurologists.
Their headline result is the **score 4 vs score 5** task — minor visuospatial
deficit versus normal, i.e. exactly the early-MCI boundary:

| Model | Accuracy | F1 |
|---|---|---|
| ResNet-152 baseline | 0.7877 | 0.7855 |
| **API-Net (best reported)** | **0.8033** | **0.8013** |

So the best image-only method misclassifies roughly **1 in 5** cases at the
boundary that determines whether a patient is investigated. Their stated cause:
the residual errors are on images that are *visually similar*.

That is a data limitation, not a modelling one, and it is the premise of this
spec. Two clocks can be near-identical as images and cognitively opposite — one
drawn fluently in 25 s, the other in 90 s with 12 s of hesitation before the
hands and three corrections. A scanned image cannot represent the difference;
the process record is where it lives. Raksasat et al. could not access it
because their data was paper-based MoCA scans, though their reference list cites
both Davoudi 2021 and Souillard-Mandar's THink work, and their discussion
explicitly invites extension to "other modalities."

**Use as a benchmark, with care.** 0.8033 / F1 0.8013 is the number to compare
against on the 4-vs-5 task. It is *not* directly comparable to a Qmci threshold
or to overall accuracy across all Shulman classes, and their cohort
(Thai, hospital-recruited, ages 29–90, F:M 3:1) differs from a Mercy primary-care
population. Cite it as the published image-only ceiling, not as an equivalence.

**Consequence for pilot design.** Their corpus had only ~3% of clocks scoring
≤3, forcing them to collapse scores 0–3 into a single class — their model is
effectively 3-class. A Mercy pilot of n=40 (30 normal, 10 MCI) will be more
skewed still, so power should target the **4-vs-5 discrimination specifically**
rather than overall accuracy. For context on the status quo: the paper cites a
Shulman cutoff at score 4 as sensitivity 90% / **specificity 39%**.

### Non-goals (v1)

- **No semantic parsing.** No identification of which stroke is a digit, a hand,
  or the contour beyond a single geometric contour heuristic. Digit-placement
  error, hand-angle correctness, and quadrant crowding are **v2**, gated on
  labelled stroke data that MERIDIAN-1 itself will produce (§8).
- **No clinical output.** Nothing computed here may reach `PCPReportView`,
  `ResultsView`, or any clinician-facing surface (§7).
- **No ML.** v1 is fully deterministic. No model, no weights, no training data,
  therefore no provenance burden.
- **No real-time computation.** Features are computed after a task completes.

---

## 2. Input: MERIDIAN-1 raw streams (decision)

`StrokeAnalyzer` consumes the artifacts already written by
`VoiceMiniCog/Research/RawStreamRecorder.swift`: JSON Lines of `TouchSample`
plus a `.manifest.json` sidecar and a `.sha256` integrity sidecar.

**Verified schema** (`RawStreamRecorder.TouchSample`):

| Field | Meaning |
|---|---|
| `t` | ms from task start, per-sample hardware time (single timebase) |
| `x`, `y` | UIKit points (mm = value / `pointsPerMillimeter` from the manifest) |
| `p` | normalized force 0–1 (0 when no force sensor) |
| `pRaw`, `pMax` | raw force and `maximumPossibleForce` at capture |
| `alt` | altitude, radians |
| `az` | azimuth, radians (UIKit view frame, y-down) |
| `type` | `stylus` \| `direct` \| `predicted` \| `other` |
| `phase` | `down` \| `move` \| `up` |
| `stroke` | 0-based stroke index within the task |

### Why this input, not the alternatives

- **Highest fidelity available:** ~240 Hz coalesced samples with force, tilt, and
  azimuth. `ClockStrokeEvent v3` carries PencilKit-rate data only.
- **Ships independently:** does not block on Plan 1 Tasks 10–24
  (`RawStroke`/`KinematicCapture` do not exist yet, which is why the April
  `StrokeAnalyzer` sketch cannot be implemented as written).
- **Shadow-mode by construction:** Research mode is structurally isolated from the
  clinical tree, so the regulatory guarantee is architectural rather than a policy
  promise (§7).
- **Provenance already solved:** the manifest records `pointsPerMillimeter`,
  `calibrationSource`, `azimuthConvention`, and build identity; the SHA-256
  sidecar makes every analysis traceable to an exact byte stream.

### Known input limitation — no hover trajectory

`UITouchCaptureView` handles `touchesBegan/Moved/Ended/Cancelled` only. There is
**no** `UIHoverGestureRecognizer` or `pencilInteraction` hover capture. Therefore:

> `air_time_s` is **inferred** from the interval between pen-up and the next
> pen-down. It is a duration, not a trajectory. No feature in v1 may describe
> in-air *path*, and no document may imply one is recorded.

This matches PaHaW's button-status semantics, so the measure is field-standard.
Adding hover capture is a separate, additive change to the capture layer (§8).

---

## 3. Architecture

Python package first (research velocity), Swift port second (device capability),
with a **golden-fixture parity harness** that makes equivalence verifiable rather
than assumed.

```
stroke-research/strokeanalyzer/
  io.py           MERIDIAN-1 JSONL + manifest loading, schema validation
  quality.py      predicted-sample filtering, effective sample rate, gap detection
  timing.py       timing features            ┐
  kinematics.py   velocity/jerk/pressure/FFT ├ pure functions: no I/O, no state
  sequence.py     stroke order and strategy  ┘
  features.py     orchestrator → one flat dict per task
  fixtures/       golden input + expected-output pairs (the parity contract)
  tests/
```

Design rules, each with a reason:

- **Pure functions over a loaded sample list.** No file access below `io.py`, no
  global state, no wall-clock reads. Every feature is replayable from a fixture.
- **One flat dict per task**, keys stable and snake_case, so results tabulate
  directly into a DataFrame for the study and diff cleanly across versions.
- **`FEATURE_SCHEMA_VERSION` constant**, emitted with every result. A feature
  definition change bumps it; analyses record which version produced them.
- **No feature silently returns 0 for "missing".** Absent (e.g. no force sensor)
  is `None`, distinct from a genuine zero. A 0 that means "unknown" is how a
  false effect gets published.

### Swift parity contract

`VoiceMiniCog/Services/StrokeAnalyzer.swift` (v2) consumes the **same
`fixtures/`** in its own XCTest suite. Both implementations must produce values
within tolerance (`1e-6` relative for pure arithmetic; `1e-3` for FFT-derived
values, where library differences are legitimate). Fixtures are the contract; a
divergence is a test failure in whichever implementation changed.

---

## 4. Feature surface (v1)

Names match DARWIN / Davoudi 2021 / BDALab vocabulary where the construct
overlaps, so results benchmark against published effect sizes and norms.

### 4.1 Timing

| Feature | Definition | Parity |
|---|---|---|
| `total_time_s` | last sample t − first sample t | — |
| `ink_time_s` | Σ per-stroke (last t − first t) | DARWIN *paper time* |
| `air_time_s` | `total − ink` (inferred; see §2) | DARWIN *air time* |
| `air_ink_ratio` | `air_time_s / ink_time_s` | DARWIN air/paper |
| `pre_first_stroke_latency_s` | task start → first pen-down | Davoudi latency |
| `pause_count` | count of inter-stroke gaps | — |
| `pause_median_ms`, `pause_p90_ms`, `pause_max_ms` | gap distribution | Davoudi |
| `longest_pause_before_stroke_index` | which element was hardest | novel |

`air_ink_ratio` is `None` when `ink_time_s == 0`, never 0.

### 4.2 Kinematics

| Feature | Definition |
|---|---|
| `velocity_mean_mmps`, `velocity_cv` | per-segment speed in mm/s; CV = σ/μ |
| `jerk_mean_mmps3` | mean \|third derivative of position\| on-surface |
| `ncv` | number of changes in velocity profile (sign changes of acceleration) |
| `pressure_mean`, `pressure_cv` | from `p`; `None` when `pMax == 0` |
| `tilt_mean` | mean `alt` (altitude does not wrap; ordinary mean is valid) |
| `azimuth_circular_variance` | **circular** variance of `az` — azimuth wraps at 2π, so σ/μ is invalid; use `1 − |mean resultant vector|` |
| `relpow_0_2hz`, `relpow_2_4hz`, `relpow_4_7hz`, `relpow_8_12hz` | **relative** (fractional) spectral power per band, computed separately on velocity and acceleration. Bands and method per Toffoli 2023 — see §10.1. `relpow_4_7hz` is the parkinsonian tremor band and the discriminative one. |
| `tremor_stability_index` | variability of the dominant tremor frequency across cycles (PD 4.84 ± 1.37 Hz vs control 6.00 ± 1.76 Hz) |
| `path_length_mm` | total on-surface distance travelled |

**Units.** Coordinates are UIKit **points**; millimetres come from the manifest's
`pointsPerMillimeter`. That value is read per-file, never hardcoded. (The April
sketch computed a constant `1/0.3528` *and* carried a contradictory comment
claiming coordinates were already mm — see §9.)

**Sample rate.** `tremor_power_4_12hz` and `ncv` require a rate. It is **measured**
from timestamp deltas (`quality.py`), never assumed, and the measured value is
reported alongside the feature. If the effective rate is unstable beyond a
threshold, spectral features return `None` with a recorded reason.

### 4.3 Sequence and planning strategy (the novel contribution)

| Feature | Definition |
|---|---|
| `stroke_count` | number of distinct strokes |
| `contour_detected` | a stroke is largest, near-square aspect, near-closed |
| `contour_first` | the contour is stroke index 0 |
| `rim_mark_count` | non-contour strokes with centroid > 0.45 × radius from centre |
| `angular_sequence` | clock positions 1–12 of rim marks, in draw order |
| `anchoring_positional` | positional approximation of Davoudi anchoring — see §10.3. **Not** the same measure as digit-identity anchoring; named to keep that distinction visible. |
| `planning_strategy` | `anchoring_positional` \| `sequential` \| `mixed` \| `unclassifiable` |
| `post_contour_latency_s` | gap from contour completion to next stroke — Davoudi *post-clockface latency*, norm 1.51 ± 1.81 s (command) |
| `direction` | `clockwise` \| `counterclockwise` \| `mixed` |
| `revisit_count` | non-contour strokes whose centroid falls within `revisitRadiusMm` of an earlier non-contour stroke's centroid |

Three definitions were corrected during spec self-review, each because the obvious
formulation is silently wrong for clock geometry — recorded here so the Swift port
does not reintroduce them:

- **`azimuth_cv` → `azimuth_circular_variance`.** Azimuth is an angle that wraps at
  2π; ordinary σ/μ is meaningless (values near 0 and near 2π are adjacent, not
  opposite). Circular statistics required.
- **`path_efficiency` removed.** Defined as path length ÷ straight-line
  start-to-end distance, it is degenerate for a closed contour, where the
  denominator approaches zero and the ratio explodes. The construct is meaningful
  for TMT-B node-to-node segments; it returns there in v2, not here.
- **`revisit_count` redefined.** Bounding-box overlap would count *every* digit as
  a revisit, since digits sit inside the contour's bounding box by construction.
  Now defined over non-contour strokes by centroid proximity.

Classification rules (deterministic, tunable constants named in one place):
- **anchoring:** ≥3 of the first 4 rim marks fall at 12/3/6/9
- **sequential:** first ≥4 rim marks advance by exactly +1 hour
- **unclassifiable:** fewer than 4 rim marks — reported honestly, never forced

`clock_position` maps a point to an hour with y-down screen convention
(12 o'clock = −y), measured clockwise from 12.

### 4.4 Data quality (first-class output, not a footnote)

| Feature | Purpose |
|---|---|
| `predicted_sample_fraction` | share of samples tagged `predicted` (all excluded from features) |
| `sample_rate_hz_effective` | median 1/Δt over retained samples |
| `sample_rate_stability` | IQR/median of Δt — gates spectral features |
| `stylus_fraction` | share of `type == "stylus"`; low ⇒ finger input, force/tilt meaningless |
| `has_force_sensor` | `pMax > 0` |
| `dropped_sample_count` | Δt outliers indicating capture gaps |

Every feature row carries these. A result without them cannot be interpreted.

---

## 5. Validation strategy

Four independent checks, weakest assumptions first:

1. **Synthetic ground truth.** Generated strokes with analytically known answers:
   a perfect circle traced at constant velocity has exact expected
   `velocity_mean_mmps`, zero `velocity_cv`, zero `jerk`; a square wave in the
   velocity series has known `tremor_power_4_12hz`. Catches sign, unit, and
   off-by-one errors that clinical data hides.
2. **Clinical regression.** The 129 PaHaW `.svc` files
   (`stroke-research/repo/examples/data/`, 2 HC + 2 PD, Wacom Intuos 4M,
   **200 Hz per `info.json`**, 7 channels including button status). An SVC adapter
   lets the same code path run on them.
3. **External cross-check.** On identical PaHaW files, our `air_ink_ratio` must
   agree with the MIT-licensed BDALab `handwriting-features` output
   (measured: **median 0.21**). Divergence beyond tolerance means our
   implementation is wrong, not theirs. This is the single most valuable test:
   an independent implementation of the same construct.
4. **Scale sanity.** The 120,536 Quick, Draw! raw clock drawings
   (`stroke-research/quickdraw/clock_raw.ndjson`, x/y/t, CC BY 4.0) against
   measured baselines from 6,982 analysed drawings: `air_ink_ratio` ≈ **0.66**,
   `contour_first` ≈ **94%**, `pause_median_ms` ≈ **479**.
   **Engineering data only** — healthy internet users, mouse/touch input, no
   clinical inference is permitted from these numbers. They test that the
   geometry and sequencing code behaves sanely at scale.

Note the informative contrast between (2) and (4): handwriting air:ink ≈ 0.21 vs
clock air:ink ≈ 0.66. Clock drawing is a think-dominated task; that ratio gap is
the empirical justification for prioritising timing features.

---

## 6. Error handling

| Condition | Behavior |
|---|---|
| Empty or single-sample stream | all features `None`, `reason: "insufficient_samples"` |
| Manifest missing or unparseable | **refuse to analyze** — without `pointsPerMillimeter` every mm value would be wrong |
| SHA-256 mismatch | **refuse to analyze**, report the mismatch (integrity is the point of the sidecar) |
| `pMax == 0` (no force sensor) | pressure features `None`, `has_force_sensor: false` |
| `stylus_fraction` below threshold | force/tilt/azimuth features `None` with reason |
| Unstable sample rate | spectral features `None` with reason; time-domain features still computed |
| Zero rim marks | `planning_strategy: "unclassifiable"` |

Principle: **fail loudly or return `None` with a reason — never a plausible wrong
number.** A silently wrong feature in a validation study is worse than a missing
one.

---

## 7. Regulatory posture

- **Phase 1 CDS-exempt maintained.** All output is research-only. Nothing here is
  displayed, scored clinically, or included in the PCP report.
- **Structural, not procedural, isolation.** Analyzer input is Research-mode
  artifacts, which are already isolated from the clinical tree by design.
- **Mechanical guard (required test).** A test asserts that no import path exists
  from any clinical view (`PCPReportView`, `ResultsView`, `ClinicianDashboardView`)
  to analyzer output — the same posture as the six-module spec's contamination
  guard. Restoring the shadow-mode language removed from `VoiceMiniCog/CLAUDE.md`
  on 2026-04-12 is a prerequisite for the Swift port.
- **No PHI.** Analyzer consumes coordinates and timestamps; participant identity
  lives in MERIDIAN-1's Keychain-gated site/participant mapping, never in feature
  rows. Feature output is keyed by artifact UUID.
- **Provenance.** Every feature row records `FEATURE_SCHEMA_VERSION`, the source
  artifact UUID, and its SHA-256.
- **Phase 2 note.** If any process feature is later promoted to clinical output,
  that is an SaMD transition requiring 510(k) — an explicit, separate decision,
  not a consequence of this work.

---

## 8. Deferred to v2 (with the reason each is deferred)

| Item | Why deferred |
|---|---|
| Semantic stroke parsing (digit / hand / contour classification) | Needs labelled stroke data. MERIDIAN-1 sessions *become* that data, with documented provenance. Doing it first inverts the dependency. |
| Digit angular-placement error, quadrant crowding, hand-angle correctness | Depend on the above. |
| Hover / in-air trajectory | Requires an additive capture-layer change (`UIHoverGestureRecognizer`); would make in-air *path* features possible. |
| HMM search-vs-move segmentation (Du et al. 2022 method) | More defensible than threshold-based pause detection, but needs the time-domain baseline first. |
| TMT-B feature set | Same engine, different geometry. Plan 3 scope; the layout is gated on clinical review of `TMTBLayout.json`. |
| Normative comparison | Davoudi 2021 supplementary tables give latency norms stratified by age/education/handedness/anchoring strategy — usable once features are frozen. |
| Swift on-device port | Deliberately after the Python feature set stops changing; fixtures make it verifiable. |

---

## 9. Relationship to the April Plan 3 sketch

The Plan 3 Task 1 sketch is superseded, not discarded. Retained: the stateless
pure-function design, the DARWIN-parity intent, and the eventual Clock+TMT-B
unification. Changed:

1. **Input.** `RawStroke`/`KinematicCapture` do not exist (Plan 1 Tasks 10–24
   unstarted), so that sketch is unimplementable today. v1 reads MERIDIAN-1
   artifacts instead and ships independently.
2. **Units bug fixed.** The sketch's `pixelsPerMillimeter()` returns *points* per
   mm (`1/0.3528`) while an adjacent comment asserts coordinates are "already
   physical mm in our spec" — then divides by it anyway. v1 reads
   `pointsPerMillimeter` from the manifest, single source of truth.
3. **Sample rate measured, not assumed.** The sketch had no rate handling; v1
   measures it and gates spectral features on stability.
4. **Sequence features added.** The sketch had no stroke-order or planning-strategy
   features — the executive-function signal that most distinguishes process-based
   CDT from image scoring.
5. **Data-quality features added** as first-class outputs.
6. **Language first, Swift second**, with fixtures as the parity contract.

---

## 10. Resolved questions — evidence review 2026-08-05

Literature retrieved via PubMed. Each decision states whether it is
evidence-based or a judgement call.

### 10.1 Tremor bands — RESOLVED, my original proposal was wrong

**Decision: four relative-power bands — 0–2, 2–4, 4–7, 8–12 Hz — computed on
velocity and acceleration, not position.** Not a single 4–12 Hz band, and not the
4–6 / 6–12 split I proposed.

Toffoli et al. 2023 (*Front Neurol* 14:1093690,
[DOI](https://doi.org/10.3389/fneur.2023.1093690)) is the closest published
method: 29 Parkinson's patients vs 29 age-matched controls drawing spirals with a
sensorised pen. Their pipeline, adopted here:

- band-pass **2–12 Hz**, zero-phase 4th-order Butterworth, before spectral estimation
- PSD by **Welch's method** (500-sample window, 50% overlap, 0.1 Hz resolution)
- **relative** power per band (fraction of total), not absolute
- computed on **acceleration and angular velocity** — explicitly not on position

Findings that make the band choice non-arbitrary: PD showed significantly higher
relative power in **4–7 Hz** (the parkinsonian tremor band) and *lower* power in
0–2 Hz (acceleration) and 2–4 Hz (angular velocity). The 4–7 Hz relative power
correlated with UPDRS-III resting tremor (ρ = 0.50, p = 0.007). A separate
Tremor Stability Index differed between groups (PD 4.84 ± 1.37 Hz vs control
6.00 ± 1.76 Hz, p = 0.007). Classification reached 94.83% accuracy with
fluency and power-distribution indicators dominating.

Corroborating: Phillips et al. 2009 (*Hum Mov Sci* 28:619-32,
[DOI](https://doi.org/10.1016/j.humov.2009.01.006)) found alcohol-induced
cerebellar dysfunction raised handwriting spectral power **around 4 Hz** on a
Wacom tablet. Elble & Ellenbogen 2017 (*Tremor Other Hyperkinet Mov* 7:481,
[DOI](https://doi.org/10.7916/D89S20H7)) established that tablet spectral
analysis of Archimedes spirals detects essential-tremor change with ICC 0.97 —
i.e. the method is sound, but its minimum detectable change is limited by natural
tremor variability, not by the instrument.

**Adaptation required.** Toffoli sampled at 50 Hz from an IMU (gyroscope angular
velocity); we sample position at ~240 Hz and must differentiate to velocity and
acceleration. Differentiation amplifies high-frequency noise, so the 2–12 Hz
band-pass must be applied *after* differentiation and before PSD. Report the band
edges as named constants.

**Signed components, never speed magnitude (corrected 2026-08-05).** The PSD is
computed on the **signed** velocity components `vx` and `vy` separately, with
band powers summed — not on speed magnitude `hypot(dx,dy)/dt`. Speed magnitude
is always ≥ 0, so when the pen's drawing speed is lower than the tremor's
velocity amplitude the signal full-wave rectifies and the tremor appears at
**double** its true frequency. Measured, 5 Hz tremor of 10 mm/s amplitude:

| baseline drawing speed | recovered from speed magnitude | from signed velocity |
|---|---|---|
| 0 mm/s | **10.08 Hz** | 4.80 Hz |
| 2 mm/s | **10.08 Hz** | 4.80 Hz |
| ≥5 mm/s | 4.80 Hz | 4.80 Hz |

This is not a cosmetic concern. Rectification occurs at *low drawing speed* —
precisely what bradykinetic patients produce — so a 5 Hz parkinsonian tremor
would land in the 8–12 Hz band instead of 4–7 Hz, causing `relpow_4_7hz` (the
band correlating with UPDRS-III resting tremor) to miss it and misread it as
physiological tremor. The method would fail on the most impaired subjects while
working correctly on controls. Toffoli's gyroscope angular velocity is a signed
quantity; substituting a magnitude silently changes the signal. A regression
test asserts that a 5 Hz tremor at **zero** baseline drawing speed reports peak
energy in 4–7 Hz.

**Differentiate within strokes only.** Acceleration and jerk must never be
differentiated across a stroke boundary. Measured: two strokes each internally
constant-speed (1 mm/s then 50 mm/s across a real 2 s pen-lift) produced
`jerk_mean_mmps3 ≈ 170,139` and `ncv = 16` when both true values are 0 — a
single boundary sample fabricated a ~12,250 mm/s² acceleration that never
occurred.

**Judgement call:** whether an 8–12 Hz band is worth computing for clock drawing.
It is physiological/essential tremor territory and Toffoli included it, so v1
computes it — but no clock-drawing study validates it, and it may prove uninformative.

**Would change if:** a clock-specific (not spiral) tremor study establishes
different discriminative bands. None exists today.

### 10.2 Pause threshold — RESOLVED: use named component latencies, not a threshold

**Decision: apply no generic pause threshold. Report the full inter-stroke gap
distribution, plus named component latencies aligned to Davoudi 2021 as parsing
capability allows.**

Davoudi et al. 2021 (*J Alzheimers Dis* 82:59-70,
[DOI](https://doi.org/10.3233/JAD-201249)), n = 430 cognitively-well adults 55+,
does not use a pause threshold at all. It defines **named inter-component
latencies**, which is a materially better construct: each measures a specific
planning decision rather than an arbitrary gap.

Their normative values (command condition, mean ± SD):

| Latency | Command | Copy |
|---|---|---|
| Total completion time | 35.02 ± 12.52 s | 27.40 ± 8.93 s |
| Post-clockface latency | 1.51 ± 1.81 s | 1.33 ± 1.13 s |
| **Pre-first-hand latency** | **2.54 ± 2.36 s** | 1.15 ± 0.95 s |
| Pre-centre-dot latency | 1.98 ± 2.12 s | 1.21 ± 0.87 s |
| Pre-second-hand latency | 1.57 s | 1.06 s |

Pre-first-hand latency is the longest — consistent with hand placement being the
most cognitively demanding step (working memory and inhibition).

**Consequence for v1 scope.** `post_contour_latency_s` is computable now, since
contour detection exists. `pre_first_hand_latency_s` requires hand identification
and therefore lands in **v2** with semantic parsing. This is a partial revision of
§8: pre-first-hand latency is now a *named, normed* v2 target rather than a
vaguely deferred idea.

**Judgement call, now better grounded:** reporting the raw distribution remains
correct for v1, because a threshold imported from handwriting research would be
measuring a different cognitive event. Our measured healthy median inter-stroke
gap of ~479 ms sits well below every published component latency (1.15–2.54 s),
which is expected — most gaps are ordinary element transitions, while the
clinically meaningful ones are the long tail before hands and centre dot. That
gap between the median and the named latencies is itself the argument against a
single cut-point.

**Would change if:** MERIDIAN-1 pilot data shows a bimodal gap distribution with a
natural separation point, which would justify a data-driven threshold.

### 10.3 Anchoring — RESOLVED, with an important scope correction

**Decision: adopt Davoudi's published definition — anchoring is placing digits
12, 3, 6, 9 *prior to* the other numbers — and rename the v1 feature to
`anchoring_positional` to state honestly that v1 approximates it by angular
position rather than digit identity.**

Davoudi 2021 defines it verbatim as "the act of anchoring numbers (placing 12, 3,
6, 9 prior to other numbers)" and stratifies its normative tables by it. Reference
values from n = 430 cognitively-well adults 55+:

| | Value |
|---|---|
| Anchoring prevalence, command | **51.16%** |
| Anchoring prevalence, copy | 42.09% |
| By age | 54.35% (55–64) → 44.44% (75–84) |
| By education | >50% (college+) vs 34.09% (≤high school) |
| Digit misplacement, anchorers vs not (command) | 64.56° vs 76.78° |
| Extra time taken by anchorers (command) | ~1.5 s longer |
| Handedness effect | none |

Anchoring is a **positive** marker: anchorers place digits more accurately, and
Davoudi cites prior work showing anchorers outperform non-anchorers on executive
function and learning/memory, with more modular ventral-stream connectomics. The
trade-off is ~1.5 s of extra planning time — strategy costing time and buying
accuracy, which is exactly the executive-function signal of interest.

**Scope correction (important).** Davoudi's definition depends on knowing *which
digit* each mark is — that is semantic parsing, i.e. v2. My proposed rule (≥3 of
the first 4 rim marks at the 12/3/6/9 clock *positions*) is a positional
approximation that does not require digit identity. It is therefore a distinct
measure and must not be reported as if it were Davoudi's. v1 emits
`anchoring_positional` (boolean) plus `anchoring_positional_confidence`;
`anchoring_davoudi` arrives in v2 and its agreement with the positional proxy
must be measured, not assumed.

**Judgement call:** the ≥3-of-4 relaxation is mine and is unvalidated. Davoudi's
51.16% prevalence gives a calibration target — if `anchoring_positional` fires at
a wildly different rate in a comparable cohort, the rule is miscalibrated.

**Would change if:** v2 parsing shows poor agreement between positional and
digit-identity anchoring, in which case the positional proxy should be dropped
rather than reported.

### 10.4 Bonus normative anchors for validation (Davoudi 2021)

Directly usable as sanity checks for our pipeline:

| Measure | Cognitively-well 55+ |
|---|---|
| Total pen strokes (command) | **24.92 ± 5.22** |
| Clockface drawn in a single stroke | median 1.00 (mean 1.12) |
| Incomplete clockface | 3% |
| Right-handers drawing clockface counterclockwise | **94.23%** (left-handers 45.83%) |
| Digit misplacement per digit | ~6° |
| Self-correction (scratch-out) | 13.72% command, 7.44% copy |
| Digit omission | 1.16% |
| Perseverated digits | 0% |
| dCDT capture rate (Anoto pen) | 75 Hz |

**This invalidates one of my earlier validation assumptions.** Real clocks average
~25 pen strokes; the Quick, Draw! corpus had a *median of 4*. Those doodles are
circles-plus-hands, not clocks with digits. Quick, Draw! therefore remains valid
for geometry and sequencing code paths but must **not** be used to calibrate
stroke-count, anchoring prevalence, or any digit-related feature. §5 item 4 is
narrowed accordingly.

Our ~240 Hz capture is **3.2× the dCDT reference rate of 75 Hz**, so temporal
resolution is not a limiting factor when comparing against these norms.
