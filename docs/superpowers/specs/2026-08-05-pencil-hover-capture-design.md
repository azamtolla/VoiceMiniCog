# Apple Pencil Hover Capture — In-Air Movement for MERIDIAN-1 (Design)

**Date:** 2026-08-05
**Status:** Draft — pending Tolla review
**Authors:** Tolla + Claude
**Priority:** Do this BEFORE the first MERIDIAN-1 capture visit (see §2)

---

## 1. Goal

Record Apple Pencil **hover** (in-air) position while the pen is near but not
touching the screen, so that in-air movement becomes a measurable *trajectory*
rather than an inferred duration.

Today `Research/UITouchCaptureView.swift` overrides only
`touchesBegan/Moved/Ended/Cancelled`. There is no `UIHoverGestureRecognizer` and
no `pencilInteraction`, so nothing is recorded between pen-up and the next
pen-down. `StrokeAnalyzer`'s `air_time_s` is therefore derived by subtraction —
a duration with no path, no velocity, and no spatial information.

## 2. Why this is urgent rather than a nice-to-have

Chan et al. 2022 (*Neuropsychol Rev* 32:566–576,
[DOI](https://doi.org/10.1007/s11065-021-09523-2)), the 90-study meta-analysis
that establishes digital CDT's advantage in MCI, states in its background:

> "Studies showed that **on-air movements can enhance the sensitivity of
> identifying patients with MCI** (Garre-Olmo et al., 2017; Müller et al., 2017).
> The **pressure applied when drawing** can be another indicator to discriminate
> elders with MCI and healthy aging (Faundez-Zanuy et al., 2013)."

Two independent studies attribute added MCI sensitivity specifically to in-air
movement — in exactly this project's target population and target condition.

The urgency is cohort integrity, not engineering. **A channel added after
enrollment begins splits the dataset**: early participants would lack hover data
and could not be pooled with later ones for any in-air feature. Adding it first
costs a small amount of work now; adding it later costs a subset of the pilot.

Supporting precedent: PaHaW records on-surface *and* in-air movement via a
button-status flag, and that corpus underpins most of the published pen-feature
taxonomy. DARWIN's public feature set reports "air time" and "paper time"
separately per task, with published AD-vs-control effect sizes.

## 3. Hardware constraint — check before committing

Apple Pencil hover requires **M2 iPad Pro or later** (and Apple Pencil Pro /
Apple Pencil 2 depending on model). It is unavailable on older iPads and
**entirely unavailable in the Simulator**.

**Action required before implementation:** confirm the exact iPad model that will
be used for MERIDIAN-1 capture visits. If it is not hover-capable, this design is
moot and the money is better spent on a hover-capable device than on the code.
Record the answer in the study's device inventory.

## 4. Design

### 4.1 Schema extension — additive only

`RawStreamRecorder.TouchSample` gains **no new fields**. Hover samples reuse the
existing schema with two conventions:

| Field | Hover value |
|---|---|
| `phase` | **`"hover"`** (new value alongside `down` / `move` / `up`) |
| `p`, `pRaw` | `0` — no contact, so no force |
| `pMax` | unchanged (device capability, not contact-dependent) |
| `alt`, `az` | populated — hover reports tilt and azimuth |
| `type` | `"stylus"` |
| `stroke` | index of the **upcoming** stroke (see §4.3) |
| `t`, `x`, `y` | as usual |

Reusing the schema means `io.py` parses hover samples with **zero changes**, and
every existing analyzer keeps working. That is the point of the design.

**Optional field, if available:** `z` — hover distance from the screen. UIKit
exposes this only indirectly; if it cannot be obtained reliably, omit it rather
than fabricate it. Do not emit a constant.

### 4.2 Capture mechanism

Add to `_TouchCapturingUIView`:

```swift
// Apple Pencil hover (M2 iPad Pro and later). Records in-air movement, which
// two studies cited in Chan et al. 2022 associate with improved MCI
// sensitivity. Unavailable in the Simulator — absence of hover samples there
// is expected, not a defect.
private lazy var hoverRecognizer = UIHoverGestureRecognizer(
    target: self, action: #selector(handleHover(_:)))
```

Register it in the same place `isMultipleTouchEnabled` is set
(`UITouchCaptureView.swift:67`). The handler mirrors the existing `makeSample`
path so that coordinate conversion, timebase, and normalization stay in one
place — do not duplicate that logic.

**Timebase:** hover samples MUST use the same `t` origin as touch samples (ms
from task start, per-sample hardware time). A second timebase would silently
corrupt every latency feature. This is the same trap the April `StrokeAnalyzer`
sketch fell into with units.

**Sampling rate:** hover fires at a lower rate than coalesced touch. Do **not**
resample or interpolate to match. Record what arrives, tagged honestly; the
analyzer measures effective rate per stream and gates spectral features on
stability, so a genuinely lower hover rate will be handled correctly rather than
disguised.

### 4.3 Stroke indexing for hover samples

Hover occurs *between* strokes, so it belongs to no completed stroke. Convention:
a hover sample carries the index of the **stroke that will begin next** — i.e.
`currentStrokeIndex + 1`. Rationale: it makes "the in-air movement preceding
stroke N" a simple filter, which is the query every planning-latency feature
wants.

**Loader consequence — must be handled before this ships.** `io.py` currently
raises `StrokeOrderError` when a stroke index is revisited non-contiguously, and
groups samples by index into `Stroke` objects. Hover samples carrying a
*forward* index would interleave with the previous stroke's touch samples and
trip that guard. Required change:

- `io.py` separates hover samples (`phase == "hover"`) into a distinct
  `Capture.hover_samples` list, **not** into `Capture.strokes`.
- The stroke-order and monotonicity guards continue to apply to touch samples only.
- `quality.retained_samples` continues to exclude `predicted`; hover is retained
  but must never enter on-surface kinematics (velocity, jerk, pressure), which
  are defined for contact only.

This is a real change to a reviewed, tested module and needs its own tests.

## 5. Features unlocked (v2 of StrokeAnalyzer, not v1)

With a genuine in-air trajectory, these become computable — none are possible today:

| Feature | Construct |
|---|---|
| `hover_path_length_mm` | distance travelled in air between strokes |
| `hover_velocity_mean_mmps` | in-air movement speed (DARWIN reports air-time GMRT and in-air jerk) |
| `hover_dwell_time_s` | time spent hovering near one location — hesitation *at a decision point* |
| `hover_excursion_count` | approaches to the surface that did not result in contact — false starts |
| `hover_to_contact_latency_s` | time from arriving above a location to touching down |
| `hover_direct_ratio` | in-air path length ÷ straight-line distance — planning directness |

`hover_dwell_time_s` and `hover_excursion_count` are the clinically interesting
pair: they distinguish *"knew where to go, moved directly"* from *"hovered over
the 7 position, retreated, came back"* — a decision-conflict signature that
elapsed pause duration alone cannot separate.

**Explicitly deferred**: none of these belong in StrokeAnalyzer v1. v1 ships on
touch data only. This design exists so the *capture* is ready before enrollment;
the features follow once real hover data exists.

## 6. Regulatory posture

Unchanged. Hover is captured only in Research mode, stored only in MERIDIAN-1
artifacts, and analyzed only by the research pipeline. Nothing reaches
`PCPReportView` or any clinical surface. Phase 1 CDS-exempt posture is unaffected.

Two additions to study documentation:
- The MERIDIAN-1 protocol and consent must state that pen position is recorded
  **while the pen is near the screen as well as while touching it**. It is not
  PHI, but participants should not be surprised by it.
- The run manifest should record hover capability and whether hover was actually
  enabled, so an artifact can never be mistaken for a hover-capable capture that
  produced no hover samples.

## 7. Testing

1. **Simulator:** hover produces zero samples; capture and analysis proceed
   normally. Absence must not error.
2. **Physical iPad + Apple Pencil (required):** hover samples appear with
   `phase == "hover"`, `p == 0`, populated `alt`/`az`, and a `t` continuous with
   surrounding touch samples.
3. **Timebase continuity:** assert no hover sample's `t` falls outside the
   enclosing pen-up→pen-down interval.
4. **Loader:** hover samples land in `hover_samples`, never in `strokes`; the
   existing stroke-order guards still fire correctly on touch data.
5. **Regression:** all 101 existing StrokeAnalyzer tests pass unchanged — the
   schema extension is additive and must break nothing.

## 8. Open questions for Tolla

1. **Which iPad model** will MERIDIAN-1 capture visits use? Everything here is
   contingent on it being M2 iPad Pro or later. If not, this design should be
   shelved and the device decision revisited.
2. **Is a hover-capable device worth purchasing** for the study if the current one
   isn't? The literature support is two studies cited in a major meta-analysis —
   suggestive, not decisive.
3. **Consent language**: do you want hover described explicitly to participants,
   or covered by a general "pen movement is recorded" statement?
