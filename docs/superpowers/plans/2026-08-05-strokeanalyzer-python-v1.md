# StrokeAnalyzer v1 (Python) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A deterministic, label-free Python package that extracts process features (timing, kinematics, spectral, sequence) from Apple Pencil stroke data, validated against real clinical pen data and published norms, with golden fixtures that make the later Swift port verifiable.

**Architecture:** Pure functions over a normalized `Stroke`/`Sample` representation. `io.py` loads MERIDIAN-1 JSON Lines; adapters convert PaHaW `.svc` and Quick, Draw! `.ndjson` into the same representation so all three drive identical code paths. `features.py` orchestrates into one flat dict per task, stamped with `FEATURE_SCHEMA_VERSION`. Spec: `docs/superpowers/specs/2026-08-04-strokeanalyzer-design.md`.

**Tech Stack:** Python 3.12, numpy 2.5.1, scipy 1.18.0, pandas 3.0.5, pytest (to be added). All already installed in `stroke-research/.venv` except pytest.

**Working directory:** `/Users/azamtolla/Documents/MercyCognitiveApp/stroke-research`. Every command below assumes `cd` there and `source .venv/bin/activate` first. Paths are relative to that directory.

**Critical context — no real input data exists yet.** `RawStreamRecorder` has never run, so there are zero `.jsonl` artifacts on disk. Task 1 therefore builds a schema-accurate synthetic generator, and Task 11 captures a real artifact from the simulator to prove the reader handles genuine recorder output. Do not skip Task 11 — a reader validated only against its own synthetic data proves nothing.

**Numpy 2.x gotcha, already encountered:** `float(np.array([x]))` raises `TypeError: only 0-dimensional arrays can be converted to Python scalars`. Use `arr.item()` for size-1 or an explicit reduction. This broke an earlier script; do not reintroduce it.

---

### Task 0: Package scaffold and pytest

**Files:**
- Create: `strokeanalyzer/__init__.py`
- Create: `pytest.ini`
- Create: `strokeanalyzer/tests/__init__.py`

- [ ] **Step 1: Install pytest**

```bash
cd /Users/azamtolla/Documents/MercyCognitiveApp/stroke-research && source .venv/bin/activate && uv pip install pytest
```

Expected: `Installed 1 package ... + pytest==<version>`

- [ ] **Step 2: Create the package init**

`strokeanalyzer/__init__.py`:

```python
"""Process-feature extraction for Apple Pencil stroke data.

Spec: VoiceMiniCog/docs/superpowers/specs/2026-08-04-strokeanalyzer-design.md
Research-only. No output from this package may reach a clinical surface.
"""

FEATURE_SCHEMA_VERSION = "1.0.0"
```

- [ ] **Step 3: Create `pytest.ini`**

```ini
[pytest]
testpaths = strokeanalyzer/tests
python_files = test_*.py
addopts = -q
```

- [ ] **Step 4: Create empty `strokeanalyzer/tests/__init__.py`** (empty file).

- [ ] **Step 5: Verify collection**

```bash
cd /Users/azamtolla/Documents/MercyCognitiveApp/stroke-research && source .venv/bin/activate && python -m pytest --collect-only
```

Expected: `no tests ran` (exit code 5) — the scaffold is valid, there is just nothing to collect yet.

- [ ] **Step 6: Commit** — note `stroke-research/` is NOT inside a git repo (the repo root has no `.git`). Skip committing; state this in your report. Do not `git init` anything.

---

### Task 1: Core types + MERIDIAN-1 reader + synthetic generator

**Files:**
- Create: `strokeanalyzer/types.py`
- Create: `strokeanalyzer/io.py`
- Create: `strokeanalyzer/synth.py`
- Test: `strokeanalyzer/tests/test_io.py`

**Schema being implemented** — verified from `VoiceMiniCog/Research/RawStreamRecorder.swift`:

`TouchSample` fields: `t` (ms from task start), `x`, `y` (UIKit points), `p` (normalized 0–1), `pRaw`, `pMax` (0 ⇒ no force sensor), `alt` (radians), `az` (radians), `type` (`stylus`|`direct`|`predicted`|`other`), `phase` (`down`|`move`|`up`), `stroke` (0-based index).

Manifest sidecar `<base>.manifest.json` carries `pointsPerMillimeter`, `calibrationSource`, `azimuthConvention`, build identity. Integrity sidecar `<base>.sha256`.

- [ ] **Step 1: Write the failing test**

`strokeanalyzer/tests/test_io.py`:

```python
import json
import math
from pathlib import Path

import pytest

from strokeanalyzer.io import load_meridian, IntegrityError, ManifestError
from strokeanalyzer.synth import write_synthetic_capture


def test_loads_synthetic_capture(tmp_path):
    base = write_synthetic_capture(tmp_path, n_strokes=3, points_per_stroke=50)
    cap = load_meridian(base)
    assert len(cap.strokes) == 3
    assert all(len(s.samples) == 50 for s in cap.strokes)
    assert cap.points_per_mm > 0


def test_samples_carry_all_channels(tmp_path):
    base = write_synthetic_capture(tmp_path, n_strokes=1, points_per_stroke=10)
    cap = load_meridian(base)
    s = cap.strokes[0].samples[0]
    for attr in ("t", "x", "y", "p", "p_raw", "p_max", "alt", "az", "type", "phase"):
        assert hasattr(s, attr)


def test_strokes_split_on_stroke_index(tmp_path):
    base = write_synthetic_capture(tmp_path, n_strokes=4, points_per_stroke=5)
    cap = load_meridian(base)
    assert [st.index for st in cap.strokes] == [0, 1, 2, 3]


def test_missing_manifest_refuses(tmp_path):
    base = write_synthetic_capture(tmp_path, n_strokes=1, points_per_stroke=5)
    Path(str(base) + ".manifest.json").unlink()
    with pytest.raises(ManifestError):
        load_meridian(base)


def test_sha256_mismatch_refuses(tmp_path):
    base = write_synthetic_capture(tmp_path, n_strokes=1, points_per_stroke=5)
    sha_path = Path(str(base) + ".sha256")
    sha_path.write_text("0" * 64)
    with pytest.raises(IntegrityError):
        load_meridian(base)


def test_missing_sha_sidecar_is_allowed_but_flagged(tmp_path):
    base = write_synthetic_capture(tmp_path, n_strokes=1, points_per_stroke=5)
    Path(str(base) + ".sha256").unlink()
    cap = load_meridian(base)
    assert cap.integrity_verified is False


def test_mm_conversion_uses_manifest(tmp_path):
    base = write_synthetic_capture(tmp_path, n_strokes=1, points_per_stroke=5,
                                   points_per_mm=2.0)
    cap = load_meridian(base)
    assert math.isclose(cap.points_per_mm, 2.0)
```

- [ ] **Step 2: Run to verify failure**

```bash
cd /Users/azamtolla/Documents/MercyCognitiveApp/stroke-research && source .venv/bin/activate && python -m pytest strokeanalyzer/tests/test_io.py
```

Expected: `ModuleNotFoundError: No module named 'strokeanalyzer.io'`

- [ ] **Step 3: Implement `strokeanalyzer/types.py`**

```python
"""Normalized stroke representation shared by all input adapters."""

from dataclasses import dataclass, field
from typing import List, Optional


@dataclass(frozen=True)
class Sample:
    t: float            # milliseconds from task start
    x: float            # UIKit points
    y: float
    p: float = 0.0      # normalized force 0-1
    p_raw: float = 0.0
    p_max: float = 0.0  # 0 => device has no force sensor
    alt: float = 0.0    # radians
    az: float = 0.0     # radians
    type: str = "stylus"
    phase: str = "move"


@dataclass
class Stroke:
    index: int
    samples: List[Sample] = field(default_factory=list)

    @property
    def t_start(self) -> float:
        return self.samples[0].t

    @property
    def t_end(self) -> float:
        return self.samples[-1].t

    @property
    def duration_ms(self) -> float:
        return self.t_end - self.t_start


@dataclass
class Capture:
    strokes: List[Stroke]
    points_per_mm: float
    source: str                       # meridian1 | pahaw_svc | quickdraw
    integrity_verified: bool = False
    manifest: Optional[dict] = None
    artifact_id: Optional[str] = None

    @property
    def all_samples(self) -> List[Sample]:
        return [s for st in self.strokes for s in st.samples]
```

- [ ] **Step 4: Implement `strokeanalyzer/io.py`**

```python
"""MERIDIAN-1 JSON Lines reader with manifest and integrity enforcement."""

import hashlib
import json
from pathlib import Path
from typing import Union

from strokeanalyzer.types import Capture, Sample, Stroke


class ManifestError(Exception):
    """Manifest missing or unusable — mm conversion would be wrong."""


class IntegrityError(Exception):
    """SHA-256 sidecar does not match the data file."""


class SampleSchemaError(Exception):
    """A JSONL line is unparseable or missing a required field.

    Carries file path and 1-based line number. RawStreamRecorder flushes
    incrementally and only writes the .sha256 sidecar in endTask(), so a
    crash mid-capture genuinely can leave a truncated final line with a
    manifest present and no sidecar. Batch analysis needs to know WHICH
    file and WHICH line.
    """


class StrokeOrderError(Exception):
    """Sample timestamps regress within a stroke, or a stroke index is reused.

    Deliberately raises rather than silently sorting: re-sorting would hide a
    genuine recorder bug behind clean-looking numbers, which in a research
    instrument is the worse failure.
    """


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load_meridian(base: Union[str, Path]) -> Capture:
    """Load a MERIDIAN-1 capture given its base path (no extension).

    Expects <base>.jsonl, <base>.manifest.json, optionally <base>.sha256.
    Refuses to load without a manifest (points_per_mm is not guessable) or
    on a SHA mismatch (integrity is the entire point of the sidecar).
    """
    base = Path(base)
    data_path = Path(str(base) + ".jsonl")
    manifest_path = Path(str(base) + ".manifest.json")
    sha_path = Path(str(base) + ".sha256")

    if not data_path.exists():
        raise FileNotFoundError(f"no data file: {data_path}")
    if not manifest_path.exists():
        raise ManifestError(
            f"no manifest at {manifest_path}; refusing to analyze because "
            "pointsPerMillimeter would have to be guessed")

    manifest = json.loads(manifest_path.read_text())
    ppm = manifest.get("pointsPerMillimeter")
    if not ppm or ppm <= 0:
        raise ManifestError(f"manifest has no usable pointsPerMillimeter: {ppm!r}")

    integrity_verified = False
    if sha_path.exists():
        expected = sha_path.read_text().strip().split()[0]
        actual = _sha256(data_path)
        if expected != actual:
            raise IntegrityError(
                f"sha256 mismatch for {data_path.name}: "
                f"expected {expected[:12]}..., got {actual[:12]}...")
        integrity_verified = True

    by_stroke: dict = {}
    last_index = None
    with open(data_path) as fh:
        for line_no, raw_line in enumerate(fh, start=1):
            line = raw_line.strip()
            if not line:
                continue
            try:
                d = json.loads(line)
            except json.JSONDecodeError as e:
                raise SampleSchemaError(
                    f"{data_path}:{line_no}: invalid JSON ({e})") from e

            try:
                # "stroke" is required, same as t/x/y: a missing key means
                # corrupt data, not "stroke 0" — silently defaulting it would
                # fold the sample into the wrong stroke and corrupt every
                # downstream timing/sequence feature.
                stroke_idx = int(d["stroke"])
                sample = Sample(
                    t=float(d["t"]), x=float(d["x"]), y=float(d["y"]),
                    p=float(d.get("p", 0.0)), p_raw=float(d.get("pRaw", 0.0)),
                    p_max=float(d.get("pMax", 0.0)),
                    alt=float(d.get("alt", 0.0)), az=float(d.get("az", 0.0)),
                    type=str(d.get("type", "stylus")),
                    phase=str(d.get("phase", "move")),
                )
            except (KeyError, ValueError, TypeError) as e:
                # ValueError/TypeError catch non-numeric values (e.g. "t": "abc"
                # from a bit-flip or schema-version mismatch) — same failure
                # category as a missing key, so it gets the same file:line
                # treatment rather than a bare context-free exception.
                raise SampleSchemaError(
                    f"{data_path}:{line_no}: invalid or missing required field ({e})") from e

            if stroke_idx in by_stroke and stroke_idx != last_index:
                raise StrokeOrderError(
                    f"{data_path}:{line_no}: stroke index {stroke_idx} reused "
                    f"after stroke index {last_index}; a capture must visit "
                    "each stroke index exactly once, contiguously")

            samples = by_stroke.setdefault(stroke_idx, [])
            # Validate, never silently sort: re-sorting would hide a recorder
            # bug behind clean-looking numbers.
            if samples and sample.t < samples[-1].t:
                raise StrokeOrderError(
                    f"{data_path}:{line_no}: stroke {stroke_idx} timestamp "
                    f"moved backward ({samples[-1].t} -> {sample.t})")

            samples.append(sample)
            last_index = stroke_idx

    strokes = [Stroke(index=i, samples=by_stroke[i]) for i in sorted(by_stroke)]
    return Capture(strokes=strokes, points_per_mm=float(ppm), source="meridian1",
                   integrity_verified=integrity_verified, manifest=manifest,
                   artifact_id=manifest.get("runID") or base.name)
```

- [ ] **Step 5: Implement `strokeanalyzer/synth.py`**

```python
"""Schema-accurate synthetic MERIDIAN-1 captures.

Used because RawStreamRecorder has never run on a device, so no genuine
artifacts exist yet. Also the source of analytically-known ground truth for
feature tests (see generate_circle).
"""

import hashlib
import json
import math
from pathlib import Path
from typing import List, Optional


def _sha256_of(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_synthetic_capture(directory, n_strokes=3, points_per_stroke=50,
                            points_per_mm=2.834646, sample_rate_hz=240.0,
                            gap_ms=500.0, base_name="synthetic",
                            samples: Optional[List[dict]] = None) -> Path:
    """Write <base>.jsonl + .manifest.json + .sha256; return the base path."""
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    base = directory / base_name
    dt = 1000.0 / sample_rate_hz

    if samples is None:
        samples = []
        t = 0.0
        for s in range(n_strokes):
            for i in range(points_per_stroke):
                ang = 2 * math.pi * i / max(points_per_stroke, 1)
                samples.append({
                    "t": t, "x": 100.0 + 50.0 * math.cos(ang),
                    "y": 100.0 + 50.0 * math.sin(ang),
                    "p": 0.5, "pRaw": 2.0, "pMax": 4.0,
                    "alt": 1.0, "az": 0.5, "type": "stylus",
                    "phase": "down" if i == 0 else ("up" if i == points_per_stroke - 1 else "move"),
                    "stroke": s,
                })
                t += dt
            t += gap_ms

    data_path = Path(str(base) + ".jsonl")
    with open(data_path, "w") as fh:
        for s in samples:
            fh.write(json.dumps(s) + "\n")

    manifest = {
        "pointsPerMillimeter": points_per_mm,
        "calibrationSource": "synthetic",
        "azimuthConvention": "UIKit_view_x_axis_y_down",
        "runID": base_name,
        "note": "SYNTHETIC — not from a device",
    }
    Path(str(base) + ".manifest.json").write_text(json.dumps(manifest, indent=2))
    Path(str(base) + ".sha256").write_text(_sha256_of(data_path))
    return base


def generate_circle(radius_mm=20.0, velocity_mmps=30.0, points_per_mm=2.834646,
                    sample_rate_hz=240.0, centre=(100.0, 100.0)) -> List[dict]:
    """A circle traced at EXACTLY constant speed.

    Analytic ground truth: velocity_mean == velocity_mmps, velocity_cv == 0,
    jerk == 0 (constant-magnitude tangential velocity).
    """
    circumference_mm = 2 * math.pi * radius_mm
    duration_s = circumference_mm / velocity_mmps
    n = max(int(duration_s * sample_rate_hz), 8)
    dt_ms = 1000.0 / sample_rate_hz
    r_pts = radius_mm * points_per_mm

    out = []
    for i in range(n):
        frac = i / n
        ang = 2 * math.pi * frac
        out.append({
            "t": i * dt_ms,
            "x": centre[0] + r_pts * math.cos(ang),
            "y": centre[1] + r_pts * math.sin(ang),
            "p": 0.5, "pRaw": 2.0, "pMax": 4.0, "alt": 1.0, "az": 0.0,
            "type": "stylus",
            "phase": "down" if i == 0 else ("up" if i == n - 1 else "move"),
            "stroke": 0,
        })
    return out
```

- [ ] **Step 6: Add the robustness tests** — the happy path is not enough for a
loader whose output every later module trusts. Add to `test_io.py`:
`test_missing_stroke_key_raises` (SampleSchemaError), `test_malformed_json_line_raises`
(SampleSchemaError with file:line in the message), `test_out_of_order_timestamps_within_stroke_raises`
(StrokeOrderError — assert it RAISES, not that it sorts), `test_reused_stroke_index_raises`
(StrokeOrderError), `test_empty_capture_has_no_strokes`. Also strengthen
`test_samples_carry_all_channels` to assert actual VALUES against the synthetic
generator's constants (p=0.5, p_raw=2.0, p_max=4.0, alt=1.0, az=0.5) — a
`hasattr`-only check would pass with `pRaw`/`pMax` transposed.

- [ ] **Step 7: Run tests to verify pass**

```bash
cd /Users/azamtolla/Documents/MercyCognitiveApp/stroke-research && source .venv/bin/activate && python -m pytest strokeanalyzer/tests/test_io.py -v
```

Expected: 13 passed.

**Assert message content, not just exception type.** The file:line context must be
regression-protected — use `pytest.raises(...) as excinfo` and assert the expected
1-based line number appears in the message. Type-only assertions would let a
refactor silently break the line-number computation.

**Known scope boundary (deliberate, documented in the `StrokeOrderError` docstring):**
ordering is validated *within* a stroke only. A capture where stroke 1's timestamps
entirely precede stroke 0's would not raise, since both checks look only at a stroke's
own prior samples. The recorder's monotonic stroke counter makes this unlikely; Task 3
should not assume cross-stroke ordering is guaranteed by the loader.

---

### Task 2: Data-quality module

**Files:**
- Create: `strokeanalyzer/quality.py`
- Test: `strokeanalyzer/tests/test_quality.py`

- [ ] **Step 1: Write the failing test**

```python
import math

from strokeanalyzer.quality import quality_features, retained_samples
from strokeanalyzer.types import Capture, Sample, Stroke


def _cap(samples, ppm=2.834646):
    return Capture(strokes=[Stroke(index=0, samples=samples)],
                   points_per_mm=ppm, source="test")


def test_predicted_samples_are_excluded():
    samples = [Sample(t=i * 4.0, x=float(i), y=0.0,
                      type="predicted" if i % 2 else "stylus")
               for i in range(10)]
    kept = retained_samples(_cap(samples))
    assert len(kept) == 5
    assert all(s.type != "predicted" for s in kept)


def test_predicted_fraction_reported():
    samples = [Sample(t=i * 4.0, x=float(i), y=0.0,
                      type="predicted" if i < 2 else "stylus")
               for i in range(10)]
    q = quality_features(_cap(samples))
    assert math.isclose(q["predicted_sample_fraction"], 0.2)


def test_effective_sample_rate_measured_not_assumed():
    # 4 ms spacing => 250 Hz, deliberately NOT 240
    samples = [Sample(t=i * 4.0, x=float(i), y=0.0) for i in range(50)]
    q = quality_features(_cap(samples))
    assert math.isclose(q["sample_rate_hz_effective"], 250.0, rel_tol=1e-6)


def test_stability_low_for_regular_sampling():
    samples = [Sample(t=i * 4.0, x=float(i), y=0.0) for i in range(50)]
    q = quality_features(_cap(samples))
    assert q["sample_rate_stability"] < 0.01
    assert q["sample_rate_is_stable"] is True


def test_stability_high_for_jittered_sampling():
    ts = [0.0]
    for i in range(1, 50):
        ts.append(ts[-1] + (4.0 if i % 2 else 40.0))
    samples = [Sample(t=t, x=float(i), y=0.0) for i, t in enumerate(ts)]
    q = quality_features(_cap(samples))
    assert q["sample_rate_stability"] > 0.5
    assert q["sample_rate_is_stable"] is False


def test_no_force_sensor_detected():
    samples = [Sample(t=i * 4.0, x=float(i), y=0.0, p_max=0.0) for i in range(10)]
    q = quality_features(_cap(samples))
    assert q["has_force_sensor"] is False


def test_stylus_fraction():
    samples = [Sample(t=i * 4.0, x=float(i), y=0.0,
                      type="stylus" if i < 8 else "direct")
               for i in range(10)]
    q = quality_features(_cap(samples))
    assert math.isclose(q["stylus_fraction"], 0.8)
```

- [ ] **Step 2: Run to verify failure.** Expected: `ModuleNotFoundError: No module named 'strokeanalyzer.quality'`

- [ ] **Step 3: Implement `strokeanalyzer/quality.py`**

```python
"""Data-quality features. First-class output, not diagnostics.

Every feature row carries these. A result without them cannot be interpreted:
a spectral feature computed on an unstable sample rate is a wrong number that
looks right.
"""

from typing import List

import numpy as np

from strokeanalyzer.types import Capture, Sample

# Above this IQR/median ratio of inter-sample intervals, the rate is too
# irregular for frequency-domain work. Catches CONTINUOUS jitter well
# (gaussian sd=5% -> 0.067 pass, sd=10% -> 0.131 fail).
STABILITY_THRESHOLD = 0.10
# Above this fraction of intervals outside [0.5, 1.5] x median, discrete frame
# drops are present even when the IQR ratio looks clean. IQR is a quartile
# statistic: a dropped frame (interval ~2x median) moves neither quartile until
# roughly a quarter of intervals are affected, so a capture missing 1 in 5
# samples scores a perfect 0.0 IQR ratio. Measured: at 5/10/20% drop rates IQR
# reports 0.0000 while this metric reports 0.05/0.10/0.20. Conversely at 40%
# the median itself shifts and this metric goes blind while IQR catches it.
# The two are complementary — each covers the other's failure mode. Keep both.
OUTLIER_FRACTION_THRESHOLD = 0.02
# Below this stylus fraction, force/tilt/azimuth are not meaningful.
MIN_STYLUS_FRACTION = 0.5
# Minimum surviving intervals before a spread statistic means anything. Below
# this, IQR of a 1-element array is trivially 0 — zero evidence rendering as
# confidence (measured: t=[0,0,10] reported is_stable=True).
MIN_INTERVALS_FOR_STABILITY = 3


def retained_samples(capture: Capture) -> List[Sample]:
    """All samples except UIKit's forward-estimated 'predicted' ones.

    Predicted samples are synthetic look-ahead for rendering latency. They are
    tagged at capture time and must never enter a feature.
    """
    return [s for s in capture.all_samples if s.type != "predicted"]


def quality_features(capture: Capture) -> dict:
    all_s = capture.all_samples
    kept = retained_samples(capture)
    n_all, n_kept = len(all_s), len(kept)

    out = {
        "predicted_sample_fraction": (n_all - n_kept) / n_all if n_all else None,
        "sample_count_total": n_all,
        "sample_count_retained": n_kept,
        "stylus_fraction": (
            sum(1 for s in kept if s.type == "stylus") / n_kept if n_kept else None),
        "has_force_sensor": any(s.p_max > 0 for s in kept) if kept else False,
    }

    if n_kept < 3:
        out.update({"sample_rate_hz_effective": None, "sample_rate_stability": None,
                    "sample_rate_is_stable": False, "dropped_sample_count": None})
        return out

    t = np.array([s.t for s in kept], dtype=float)
    dt = np.diff(t)
    dt = dt[dt > 0]
    if dt.size == 0:
        out.update({"sample_rate_hz_effective": None, "sample_rate_stability": None,
                    "sample_rate_is_stable": False, "dropped_sample_count": None})
        return out

    median_dt = float(np.median(dt))
    out["sample_rate_hz_effective"] = 1000.0 / median_dt
    # A dropped frame is ~2x the median interval, not 3x: >=1.5x catches it
    # without false-tripping on ordinary sampling noise.
    out["dropped_sample_count"] = int(np.sum(dt >= 1.5 * median_dt))

    if dt.size < MIN_INTERVALS_FOR_STABILITY:
        out["sample_rate_stability"] = None
        out["interval_outlier_fraction"] = None
        out["sample_rate_is_stable"] = False
        return out

    iqr = float(np.percentile(dt, 75) - np.percentile(dt, 25))
    stability = iqr / median_dt if median_dt else float("inf")
    outlier_frac = float(np.mean((dt < 0.5 * median_dt) | (dt > 1.5 * median_dt)))

    out["sample_rate_stability"] = stability
    out["interval_outlier_fraction"] = outlier_frac
    # BOTH must hold — see the constants above for why either alone is blind.
    out["sample_rate_is_stable"] = bool(
        stability <= STABILITY_THRESHOLD
        and outlier_frac <= OUTLIER_FRACTION_THRESHOLD)
    return out
```

- [ ] **Step 4: Run tests.** Expected: 7 passed.

---

### Task 3: Timing features

**Files:**
- Create: `strokeanalyzer/timing.py`
- Test: `strokeanalyzer/tests/test_timing.py`

- [ ] **Step 1: Write the failing test**

```python
import math

from strokeanalyzer.timing import timing_features
from strokeanalyzer.types import Capture, Sample, Stroke


def _cap(strokes):
    return Capture(strokes=strokes, points_per_mm=2.834646, source="test")


def _stroke(index, t0, t1, n=10):
    step = (t1 - t0) / (n - 1)
    return Stroke(index=index,
                  samples=[Sample(t=t0 + i * step, x=float(i), y=0.0) for i in range(n)])


def test_ink_and_air_split():
    # stroke 0: 0-1000ms, gap 500ms, stroke 1: 1500-2500ms
    cap = _cap([_stroke(0, 0, 1000), _stroke(1, 1500, 2500)])
    f = timing_features(cap)
    assert math.isclose(f["ink_time_s"], 2.0)
    assert math.isclose(f["air_time_s"], 0.5)
    assert math.isclose(f["total_time_s"], 2.5)
    assert math.isclose(f["air_ink_ratio"], 0.25)


def test_pause_distribution():
    cap = _cap([_stroke(0, 0, 100), _stroke(1, 300, 400), _stroke(2, 900, 1000)])
    f = timing_features(cap)
    assert f["pause_count"] == 2
    assert math.isclose(f["pause_median_ms"], 350.0)   # gaps: 200, 500
    assert math.isclose(f["pause_max_ms"], 500.0)
    assert f["longest_pause_before_stroke_index"] == 2


def test_single_stroke_has_no_pauses():
    cap = _cap([_stroke(0, 0, 1000)])
    f = timing_features(cap)
    assert f["pause_count"] == 0
    assert f["pause_median_ms"] is None
    assert math.isclose(f["air_time_s"], 0.0)


def test_zero_ink_gives_none_ratio_not_zero():
    # A degenerate capture: all samples share one timestamp.
    s = Stroke(index=0, samples=[Sample(t=5.0, x=0.0, y=0.0),
                                 Sample(t=5.0, x=1.0, y=0.0)])
    f = timing_features(_cap([s]))
    assert f["air_ink_ratio"] is None       # NOT 0.0 — absent is not zero


def test_pre_first_stroke_latency():
    cap = _cap([_stroke(0, 800, 1800)])
    f = timing_features(cap)
    assert math.isclose(f["pre_first_stroke_latency_s"], 0.8)


def test_empty_capture():
    f = timing_features(_cap([]))
    assert f["total_time_s"] is None
    assert f["reason"] == "insufficient_samples"
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement `strokeanalyzer/timing.py`**

```python
"""Timing features — the think-vs-ink decomposition.

NOTE ON air_time_s: MERIDIAN-1 captures only touch phases; there is no hover
trajectory. air_time_s is the summed interval between pen-up and the next
pen-down. It is a DURATION, not a path. Do not describe it as in-air movement.

Naming follows DARWIN ('paper time' / 'air time') and Davoudi 2021 latency
vocabulary where constructs overlap.
"""

from typing import List, Optional

import numpy as np

from strokeanalyzer.types import Capture


def _median_or_none(values: List[float]) -> Optional[float]:
    return float(np.median(values)) if values else None


def _retained_strokes(capture: Capture):
    """Strokes with predicted samples removed.

    quality.py's contract is that predicted samples never enter a feature, and
    kinematics honours it — timing must too. Measured: two trailing predicted
    samples inflated ink_time_s by 22%, because predicted samples cluster at
    stroke ends and so shift every stroke boundary.
    """
    out = []
    for st in capture.strokes:
        kept = [s for s in st.samples if s.type != "predicted"]
        if len(kept) >= 2:
            out.append(Stroke(index=st.index, samples=kept))
    return out


def timing_features(capture: Capture) -> dict:
    strokes = _retained_strokes(capture)
    if not strokes:
        return {"total_time_s": None, "ink_time_s": None, "air_time_s": None,
                "air_ink_ratio": None, "pause_count": 0, "pause_median_ms": None,
                "pause_p90_ms": None, "pause_max_ms": None,
                "longest_pause_before_stroke_index": None,
                "pre_first_stroke_latency_s": None,
                "reason": "insufficient_samples"}

    t_first = strokes[0].t_start
    t_last = strokes[-1].t_end
    total_ms = t_last - t_first
    ink_ms = sum(s.duration_ms for s in strokes)

    gaps, gap_after = [], []
    for prev, cur in zip(strokes, strokes[1:]):
        gap = cur.t_start - prev.t_end
        if gap >= 0:
            gaps.append(gap)
            gap_after.append(cur.index)

    # Out-of-order strokes produce PLAUSIBLE wrong numbers, which is worse than
    # obvious breakage. Measured: a full reversal gave total_time_s = -0.5 with
    # reason=null; a partial reorder gave ink 3.0 > total 2.5 — physically
    # impossible — silently absorbed by max(0.0, ...). The loader validates
    # ordering only WITHIN a stroke, so nothing upstream prevents this, and the
    # Task 8 adapters offer no ordering guarantee at all.
    # ink > total is impossible for well-ordered strokes: use it as the detector.
    EPS = 1e-6
    if ink_ms > total_ms + EPS or total_ms < -EPS:
        return {"total_time_s": None, "ink_time_s": None, "air_time_s": None,
                "air_ink_ratio": None, "pause_count": None,
                "pause_median_ms": None, "pause_p90_ms": None,
                "pause_max_ms": None, "longest_pause_before_stroke_index": None,
                "pre_first_stroke_latency_s": None,
                "reason": "strokes_out_of_order"}

    air_ms = max(0.0, total_ms - ink_ms)

    out = {
        "total_time_s": total_ms / 1000.0,
        "ink_time_s": ink_ms / 1000.0,
        "air_time_s": air_ms / 1000.0,
        # Absent is not zero: with no ink there is no ratio to report.
        "air_ink_ratio": (air_ms / ink_ms) if ink_ms > 0 else None,
        "pause_count": len(gaps),
        "pause_median_ms": _median_or_none(gaps),
        "pause_p90_ms": float(np.percentile(gaps, 90)) if gaps else None,
        "pause_max_ms": float(max(gaps)) if gaps else None,
        "longest_pause_before_stroke_index": (
            gap_after[int(np.argmax(gaps))] if gaps else None),
        # Task start is t=0 by MERIDIAN-1 definition.
        "pre_first_stroke_latency_s": t_first / 1000.0,
        "reason": None,
    }
    return out
```

- [ ] **Step 4: Run tests.** Expected: 6 passed.

---

### Task 4: Kinematics (time domain)

**Files:**
- Create: `strokeanalyzer/kinematics.py`
- Test: `strokeanalyzer/tests/test_kinematics.py`

- [ ] **Step 1: Write the failing test** — uses the analytic circle from Task 1

```python
import math

import pytest

from strokeanalyzer.io import load_meridian
from strokeanalyzer.kinematics import kinematic_features
from strokeanalyzer.synth import generate_circle, write_synthetic_capture
from strokeanalyzer.types import Capture, Sample, Stroke


def _circle_capture(tmp_path, velocity_mmps=30.0):
    samples = generate_circle(radius_mm=20.0, velocity_mmps=velocity_mmps)
    base = write_synthetic_capture(tmp_path, samples=samples, base_name="circle")
    return load_meridian(base)


def test_constant_speed_circle_recovers_velocity(tmp_path):
    cap = _circle_capture(tmp_path, velocity_mmps=30.0)
    f = kinematic_features(cap)
    assert f["velocity_mean_mmps"] == pytest.approx(30.0, rel=0.02)


def test_constant_speed_circle_has_near_zero_cv(tmp_path):
    cap = _circle_capture(tmp_path)
    f = kinematic_features(cap)
    assert f["velocity_cv"] < 0.01


def test_path_length_matches_circumference(tmp_path):
    cap = _circle_capture(tmp_path)
    f = kinematic_features(cap)
    assert f["path_length_mm"] == pytest.approx(2 * math.pi * 20.0, rel=0.02)


def test_pressure_none_without_sensor():
    s = Stroke(index=0, samples=[Sample(t=i * 4.0, x=float(i), y=0.0, p=0.0, p_max=0.0)
                                 for i in range(20)])
    cap = Capture(strokes=[s], points_per_mm=2.834646, source="test")
    f = kinematic_features(cap)
    assert f["pressure_mean"] is None       # not 0.0


def test_azimuth_uses_circular_variance():
    # Azimuth split either side of the 0/2pi wrap: ordinary variance would be
    # huge, circular variance must be small.
    vals = [0.05, 6.23, 0.02, 6.28, 0.01]
    s = Stroke(index=0, samples=[Sample(t=i * 4.0, x=float(i), y=0.0, az=a)
                                 for i, a in enumerate(vals)])
    cap = Capture(strokes=[s], points_per_mm=2.834646, source="test")
    f = kinematic_features(cap)
    assert f["azimuth_circular_variance"] < 0.05
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement `strokeanalyzer/kinematics.py`**

```python
"""Time-domain kinematics.

UNITS: coordinates arrive in UIKit points. Millimetres come from the capture's
points_per_mm, which is read from the manifest per file. Never hardcode a
conversion constant.
"""

from typing import Optional

import numpy as np

from strokeanalyzer.quality import retained_samples
from strokeanalyzer.types import Capture


def _circular_variance(angles_rad: np.ndarray) -> float:
    """1 - |mean resultant vector|. 0 = perfectly concentrated, 1 = uniform.

    Required because azimuth wraps at 2*pi: values near 0 and near 2*pi are
    adjacent, so ordinary sigma/mu is meaningless.
    """
    if angles_rad.size == 0:
        return float("nan")
    return float(1.0 - np.abs(np.mean(np.exp(1j * angles_rad))))


def _series(capture: Capture):
    """Per-stroke (t_seconds, x_mm, y_mm) arrays, predicted samples removed."""
    ppm = capture.points_per_mm
    out = []
    for stroke in capture.strokes:
        kept = [s for s in stroke.samples if s.type != "predicted"]
        if len(kept) < 2:
            continue
        t = np.array([s.t for s in kept], dtype=float) / 1000.0
        x = np.array([s.x for s in kept], dtype=float) / ppm
        y = np.array([s.y for s in kept], dtype=float) / ppm
        out.append((t, x, y))
    return out


def speed_series(capture: Capture):
    """Concatenated per-segment speed (mm/s) across strokes, plus dt."""
    speeds, dts = [], []
    for t, x, y in _series(capture):
        dt = np.diff(t)
        good = dt > 0
        if not np.any(good):
            continue
        dist = np.hypot(np.diff(x), np.diff(y))
        speeds.append(dist[good] / dt[good])
        dts.append(dt[good])
    if not speeds:
        return np.array([]), np.array([])
    return np.concatenate(speeds), np.concatenate(dts)


def kinematic_features(capture: Capture) -> dict:
    kept = retained_samples(capture)
    speeds, dts = speed_series(capture)

    out: dict = {}

    if speeds.size == 0:
        out.update({"velocity_mean_mmps": None, "velocity_cv": None,
                    "jerk_mean_mmps3": None, "ncv": None, "path_length_mm": None})
    else:
        mean_v = float(np.mean(speeds))
        out["velocity_mean_mmps"] = mean_v
        out["velocity_cv"] = float(np.std(speeds) / mean_v) if mean_v > 0 else None
        out["path_length_mm"] = float(np.sum(speeds * dts))

        # jerk = d(acceleration)/dt ; acceleration = d(speed)/dt
        if speeds.size >= 3:
            acc = np.diff(speeds) / dts[1:]
            jerk = np.diff(acc) / dts[2:]
            out["jerk_mean_mmps3"] = float(np.mean(np.abs(jerk)))
            # NCV: sign changes of acceleration = velocity-profile inversions
            signs = np.sign(acc)
            signs = signs[signs != 0]
            out["ncv"] = int(np.sum(np.diff(signs) != 0)) if signs.size > 1 else 0
        else:
            out["jerk_mean_mmps3"] = None
            out["ncv"] = None

    # Pressure — absent when the device reports no force sensor.
    has_force = any(s.p_max > 0 for s in kept)
    if has_force:
        p = np.array([s.p for s in kept], dtype=float)
        mean_p = float(np.mean(p))
        out["pressure_mean"] = mean_p
        out["pressure_cv"] = float(np.std(p) / mean_p) if mean_p > 0 else None
    else:
        out["pressure_mean"] = None
        out["pressure_cv"] = None

    if kept:
        out["tilt_mean"] = float(np.mean([s.alt for s in kept]))
        out["azimuth_circular_variance"] = _circular_variance(
            np.array([s.az for s in kept], dtype=float))
    else:
        out["tilt_mean"] = None
        out["azimuth_circular_variance"] = None

    return out
```

- [ ] **Step 4: Run tests.** Expected: 5 passed.

---

### Task 5: Spectral features (Toffoli 2023 bands)

**Files:**
- Create: `strokeanalyzer/spectral.py`
- Test: `strokeanalyzer/tests/test_spectral.py`

**Method being implemented** — per Toffoli et al. 2023, *Front Neurol* 14:1093690, doi 10.3389/fneur.2023.1093690, as recorded in spec §10.1: band-pass 2–12 Hz zero-phase 4th-order Butterworth, Welch PSD, **relative** power in bands 0–2, 2–4, 4–7, 8–12 Hz, computed on velocity and acceleration (not position). 4–7 Hz is the parkinsonian tremor band.

- [ ] **Step 1: Write the failing test**

```python
import numpy as np
import pytest

from strokeanalyzer.spectral import BANDS, relative_band_powers, spectral_features
from strokeanalyzer.types import Capture, Sample, Stroke


def _tone_capture(freq_hz, fs=240.0, seconds=4.0, ppm=1.0):
    """A pure sinusoidal wobble in x at a known frequency."""
    n = int(fs * seconds)
    samples = []
    for i in range(n):
        t_s = i / fs
        samples.append(Sample(t=t_s * 1000.0,
                              x=10.0 * np.sin(2 * np.pi * freq_hz * t_s),
                              y=0.0, p_max=4.0))
    return Capture(strokes=[Stroke(index=0, samples=samples)],
                   points_per_mm=ppm, source="test")


def test_bands_match_published_edges():
    assert BANDS == [(0.0, 2.0), (2.0, 4.0), (4.0, 7.0), (8.0, 12.0)]


def test_five_hz_tone_lands_in_4_7_band():
    cap = _tone_capture(5.0)
    f = spectral_features(cap, sample_rate_hz=240.0)
    assert f["relpow_vel_4_7hz"] > f["relpow_vel_2_4hz"]
    assert f["relpow_vel_4_7hz"] > f["relpow_vel_8_12hz"]
    assert f["relpow_vel_4_7hz"] > 0.5


def test_ten_hz_tone_lands_in_8_12_band():
    cap = _tone_capture(10.0)
    f = spectral_features(cap, sample_rate_hz=240.0)
    assert f["relpow_vel_8_12hz"] > f["relpow_vel_4_7hz"]


def test_relative_powers_sum_to_at_most_one():
    cap = _tone_capture(5.0)
    f = spectral_features(cap, sample_rate_hz=240.0)
    total = sum(f[f"relpow_vel_{lo:g}_{hi:g}hz".replace(".0", "")]
                for lo, hi in BANDS)
    assert 0.0 <= total <= 1.0 + 1e-9


def test_unstable_rate_returns_none_with_reason():
    cap = _tone_capture(5.0)
    f = spectral_features(cap, sample_rate_hz=240.0, rate_is_stable=False)
    assert f["relpow_vel_4_7hz"] is None
    assert f["spectral_reason"] == "unstable_sample_rate"


def test_too_short_signal_returns_none():
    cap = _tone_capture(5.0, seconds=0.05)
    f = spectral_features(cap, sample_rate_hz=240.0)
    assert f["relpow_vel_4_7hz"] is None
    assert f["spectral_reason"] == "insufficient_samples"
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement `strokeanalyzer/spectral.py`**

```python
"""Spectral / tremor features.

Method and band edges follow Toffoli et al. 2023 (Front Neurol 14:1093690,
doi 10.3389/fneur.2023.1093690): band-pass 2-12 Hz zero-phase 4th-order
Butterworth, Welch PSD, RELATIVE power per band, computed on velocity and
acceleration - never on position. 4-7 Hz is the parkinsonian tremor band and
the discriminative one in that study (rho = 0.50 with UPDRS-III resting tremor).

Their capture was 50 Hz IMU angular velocity; ours is ~240 Hz position, so we
differentiate first and band-pass AFTER differentiation, because
differentiation amplifies high-frequency noise.
"""

from typing import Optional

import numpy as np
from scipy import signal

BANDS = [(0.0, 2.0), (2.0, 4.0), (4.0, 7.0), (8.0, 12.0)]
BANDPASS_LO, BANDPASS_HI = 2.0, 12.0
BUTTER_ORDER = 4
MIN_SAMPLES = 64


def _band_key(prefix: str, lo: float, hi: float) -> str:
    return f"relpow_{prefix}_{lo:g}_{hi:g}hz"


def relative_band_powers(sig: np.ndarray, fs: float) -> Optional[dict]:
    """Welch PSD then fractional power per band. None if the signal is too short."""
    if sig.size < MIN_SAMPLES:
        return None
    nperseg = min(500, sig.size)
    freqs, psd = signal.welch(sig, fs=fs, nperseg=nperseg,
                              noverlap=nperseg // 2)
    total = float(np.trapezoid(psd, freqs))
    if total <= 0:
        return None
    out = {}
    for lo, hi in BANDS:
        mask = (freqs >= lo) & (freqs < hi)
        out[(lo, hi)] = float(np.trapezoid(psd[mask], freqs[mask]) / total) if np.any(mask) else 0.0
    return out


def _bandpassed(sig: np.ndarray, fs: float) -> np.ndarray:
    """Zero-phase 4th-order Butterworth 2-12 Hz. Returns sig unchanged if fs is too low."""
    nyq = fs / 2.0
    hi = min(BANDPASS_HI, nyq * 0.99)
    if hi <= BANDPASS_LO:
        return sig
    sos = signal.butter(BUTTER_ORDER, [BANDPASS_LO / nyq, hi / nyq],
                        btype="bandpass", output="sos")
    return signal.sosfiltfilt(sos, sig)


def spectral_features(capture, sample_rate_hz: Optional[float],
                      rate_is_stable: bool = True) -> dict:
    """Relative band powers for velocity and acceleration magnitude series."""
    keys = [_band_key(p, lo, hi) for p in ("vel", "acc") for lo, hi in BANDS]
    none_result = {k: None for k in keys}
    none_result["tremor_stability_index"] = None

    if not sample_rate_hz or sample_rate_hz <= 0:
        return {**none_result, "spectral_reason": "no_sample_rate"}
    if not rate_is_stable:
        return {**none_result, "spectral_reason": "unstable_sample_rate"}

    from strokeanalyzer.kinematics import speed_series
    speeds, dts = speed_series(capture)
    if speeds.size < MIN_SAMPLES:
        return {**none_result, "spectral_reason": "insufficient_samples"}

    fs = float(sample_rate_hz)
    vel = _bandpassed(speeds - float(np.mean(speeds)), fs)
    acc_raw = np.diff(speeds) / dts[1:]
    acc = _bandpassed(acc_raw - float(np.mean(acc_raw)), fs) if acc_raw.size >= MIN_SAMPLES else None

    out: dict = {"spectral_reason": None}

    vel_powers = relative_band_powers(vel, fs)
    for lo, hi in BANDS:
        out[_band_key("vel", lo, hi)] = vel_powers[(lo, hi)] if vel_powers else None

    acc_powers = relative_band_powers(acc, fs) if acc is not None else None
    for lo, hi in BANDS:
        out[_band_key("acc", lo, hi)] = acc_powers[(lo, hi)] if acc_powers else None

    # Tremor stability index: dispersion of the dominant frequency across
    # windows. Toffoli reported PD 4.84 +/- 1.37 Hz vs control 6.00 +/- 1.76 Hz.
    out["tremor_stability_index"] = _tremor_stability(vel, fs)
    return out


def _tremor_stability(sig: np.ndarray, fs: float) -> Optional[float]:
    win = int(fs * 1.0)
    if sig.size < win * 3:
        return None
    peaks = []
    for start in range(0, sig.size - win, win):
        seg = sig[start:start + win]
        freqs, psd = signal.welch(seg, fs=fs, nperseg=min(win, seg.size))
        band = (freqs >= BANDPASS_LO) & (freqs <= BANDPASS_HI)
        if np.any(band):
            peaks.append(float(freqs[band][int(np.argmax(psd[band]))]))
    return float(np.std(peaks)) if len(peaks) >= 2 else None
```

- [ ] **Step 4: Run tests.** Expected: 6 passed. If `np.trapezoid` is unavailable, this numpy is older than 2.0 — verify with `python -c "import numpy; print(numpy.__version__)"` (expected 2.5.1) before substituting `np.trapz`.

---

### Task 6: Sequence and planning strategy

**Files:**
- Create: `strokeanalyzer/sequence.py`
- Test: `strokeanalyzer/tests/test_sequence.py`

**Naming discipline (spec §10.3):** the v1 feature is `anchoring_positional`, a positional approximation. Davoudi's published definition depends on digit identity and is v2. Do not name anything `anchoring` unqualified.

- [ ] **Step 1: Write the failing test**

```python
import math

from strokeanalyzer.sequence import clock_position, sequence_features
from strokeanalyzer.types import Capture, Sample, Stroke


def _mark(index, cx, cy, t0):
    """A small stroke centred at (cx, cy)."""
    return Stroke(index=index, samples=[
        Sample(t=t0 + i * 4.0, x=cx + (i % 2), y=cy) for i in range(6)])


def _contour(index=0, t0=0.0, cx=100.0, cy=100.0, r=50.0, n=60):
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        pts.append(Sample(t=t0 + i * 4.0, x=cx + r * math.cos(a), y=cy + r * math.sin(a)))
    return Stroke(index=index, samples=pts)


def _cap(strokes):
    return Capture(strokes=strokes, points_per_mm=2.834646, source="test")


def test_clock_position_screen_coords():
    # y is DOWN, so 12 o'clock is -y
    assert clock_position(100, 50, 100, 100) == 12
    assert clock_position(150, 100, 100, 100) == 3
    assert clock_position(100, 150, 100, 100) == 6
    assert clock_position(50, 100, 100, 100) == 9


def test_contour_detected_and_first():
    cap = _cap([_contour(0), _mark(1, 100, 55, 300)])
    f = sequence_features(cap)
    assert f["contour_detected"] is True
    assert f["contour_first"] is True


def test_contour_not_first_when_drawn_later():
    cap = _cap([_mark(0, 100, 55, 0), _contour(1, t0=300)])
    f = sequence_features(cap)
    assert f["contour_detected"] is True
    assert f["contour_first"] is False


def test_anchoring_positional_detected():
    # contour then marks at 12, 3, 6, 9 in that order
    strokes = [_contour(0)]
    for i, (x, y) in enumerate([(100, 55), (145, 100), (100, 145), (55, 100)]):
        strokes.append(_mark(i + 1, x, y, 300 + i * 100))
    f = sequence_features(_cap(strokes))
    assert f["anchoring_positional"] is True
    assert f["planning_strategy"] == "anchoring_positional"


def test_sequential_detected():
    # marks at 1,2,3,4 o'clock in order
    strokes = [_contour(0)]
    for i, hour in enumerate([1, 2, 3, 4]):
        ang = math.radians(hour * 30)
        x = 100 + 45 * math.sin(ang)
        y = 100 - 45 * math.cos(ang)
        strokes.append(_mark(i + 1, x, y, 300 + i * 100))
    f = sequence_features(_cap(strokes))
    assert f["planning_strategy"] == "sequential"
    assert f["anchoring_positional"] is False


def test_too_few_rim_marks_is_unclassifiable():
    cap = _cap([_contour(0), _mark(1, 100, 55, 300)])
    f = sequence_features(cap)
    assert f["planning_strategy"] == "unclassifiable"


def test_post_contour_latency():
    cap = _cap([_contour(0), _mark(1, 100, 55, 1000)])
    f = sequence_features(cap)
    # contour ends at 59*4 = 236ms, next starts at 1000ms
    assert f["post_contour_latency_s"] == 0.764
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement `strokeanalyzer/sequence.py`**

```python
"""Stroke sequence and planning strategy.

v1 is GEOMETRY ONLY: no digit identification. `anchoring_positional` marks
rim positions at 12/3/6/9 clock ANGLES; Davoudi 2021's published definition
depends on knowing which DIGIT each mark is and is deferred to v2. The names
keep that distinction visible - see spec section 10.3.

Reference values (Davoudi 2021, n=430 cognitively-well adults 55+):
  anchoring prevalence 51.16% command / 42.09% copy
  total pen strokes 24.92 +/- 5.22 (command)
  clockface in a single stroke: median 1
"""

import math
from typing import List, Optional, Tuple

import numpy as np

from strokeanalyzer.types import Capture, Stroke

MIN_ASPECT = 0.6            # contour must be roughly square in bbox
CLOSURE_TOL = 0.25          # start-end gap as fraction of bbox diagonal
CONTOUR_AREA_FRAC = 0.8     # contour must be >= this fraction of largest bbox area
RIM_MIN_RADIUS_FRAC = 0.45  # rim marks lie outside this fraction of radius
MIN_MARKS_TO_CLASSIFY = 4
ANCHOR_HOURS = {12, 3, 6, 9}
ANCHOR_MIN_HITS = 3         # >=3 of the first 4 rim marks at anchor positions
REVISIT_RADIUS_MM = 5.0


def _bbox(stroke: Stroke) -> Tuple[float, float, float, float]:
    xs = [s.x for s in stroke.samples]
    ys = [s.y for s in stroke.samples]
    return min(xs), min(ys), max(xs), max(ys)


def _centroid(stroke: Stroke) -> Tuple[float, float]:
    xs = [s.x for s in stroke.samples]
    ys = [s.y for s in stroke.samples]
    return sum(xs) / len(xs), sum(ys) / len(ys)


def _is_closed(stroke: Stroke) -> bool:
    x0, y0, x1, y1 = _bbox(stroke)
    diag = math.hypot(x1 - x0, y1 - y0) or 1.0
    a, b = stroke.samples[0], stroke.samples[-1]
    return math.hypot(a.x - b.x, a.y - b.y) / diag < CLOSURE_TOL


def clock_position(px: float, py: float, ox: float, oy: float) -> Optional[int]:
    """Map a point to clock hour 1..12 about origin (ox, oy).

    Screen coordinates: +y is DOWN, so 12 o'clock is -y. Angle is measured
    clockwise from 12.
    """
    dx, dy = px - ox, py - oy
    if abs(dx) < 1e-9 and abs(dy) < 1e-9:
        return None
    ang = math.degrees(math.atan2(dx, -dy)) % 360.0
    hour = int(round(ang / 30.0)) % 12
    return 12 if hour == 0 else hour


def _find_contour(strokes: List[Stroke]) -> Optional[int]:
    areas = []
    for st in strokes:
        x0, y0, x1, y1 = _bbox(st)
        areas.append((x1 - x0) * (y1 - y0))
    if not areas:
        return None
    biggest = max(areas)
    if biggest <= 0:
        return None
    for i, st in enumerate(strokes):
        x0, y0, x1, y1 = _bbox(st)
        w, h = x1 - x0, y1 - y0
        if w < 5 or h < 5:
            continue
        if min(w, h) / max(w, h) < MIN_ASPECT:
            continue
        if areas[i] < CONTOUR_AREA_FRAC * biggest:
            continue
        if not _is_closed(st):
            continue
        return i
    return None


def sequence_features(capture: Capture) -> dict:
    strokes = [s for s in capture.strokes if len(s.samples) >= 2]
    out: dict = {
        "stroke_count": len(strokes),
        "contour_detected": False,
        "contour_first": False,
        "contour_index": None,
        "rim_mark_count": 0,
        "angular_sequence": [],
        "anchoring_positional": False,
        "planning_strategy": "unclassifiable",
        "direction": None,
        "revisit_count": None,
        "post_contour_latency_s": None,
    }
    if not strokes:
        return out

    ci = _find_contour(strokes)
    if ci is None:
        return out

    contour = strokes[ci]
    out["contour_detected"] = True
    out["contour_index"] = contour.index
    out["contour_first"] = ci == 0

    x0, y0, x1, y1 = _bbox(contour)
    ox, oy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
    radius = max(x1 - x0, y1 - y0) / 2.0 or 1.0

    # Davoudi 'post-clockface latency' analogue (norm 1.51 +/- 1.81 s command)
    later = [s for s in strokes if s.t_start >= contour.t_end]
    if later:
        out["post_contour_latency_s"] = round(
            (min(s.t_start for s in later) - contour.t_end) / 1000.0, 6)

    # Contour drawing direction (Davoudi: 94.23% of right-handers counterclockwise)
    out["direction"] = _contour_direction(contour, ox, oy)

    rim: List[Tuple[int, float, float]] = []
    for st in strokes:
        if st is contour:
            continue
        gx, gy = _centroid(st)
        if math.hypot(gx - ox, gy - oy) < RIM_MIN_RADIUS_FRAC * radius:
            continue
        pos = clock_position(gx, gy, ox, oy)
        if pos is not None:
            rim.append((pos, gx, gy))

    out["rim_mark_count"] = len(rim)
    out["angular_sequence"] = [p for p, _, _ in rim]

    ppm = capture.points_per_mm
    revisits = 0
    for i in range(len(rim)):
        for j in range(i):
            if math.hypot(rim[i][1] - rim[j][1], rim[i][2] - rim[j][2]) / ppm < REVISIT_RADIUS_MM:
                revisits += 1
                break
    out["revisit_count"] = revisits

    if len(rim) >= MIN_MARKS_TO_CLASSIFY:
        seq = out["angular_sequence"]
        hits = len(set(seq[:4]) & ANCHOR_HOURS)
        anchoring = hits >= ANCHOR_MIN_HITS
        deltas = [(seq[i + 1] - seq[i]) % 12 for i in range(min(5, len(seq)) - 1)]
        sequential = bool(deltas) and all(d == 1 for d in deltas)

        out["anchoring_positional"] = anchoring
        if anchoring:
            out["planning_strategy"] = "anchoring_positional"
        elif sequential:
            out["planning_strategy"] = "sequential"
        else:
            out["planning_strategy"] = "mixed"
    return out


def _contour_direction(contour: Stroke, ox: float, oy: float) -> Optional[str]:
    """Sign of cumulative swept angle. Screen y is down, so positive cross
    product corresponds to clockwise on screen."""
    pts = contour.samples
    if len(pts) < 3:
        return None
    total = 0.0
    for a, b in zip(pts, pts[1:]):
        ax, ay = a.x - ox, a.y - oy
        bx, by = b.x - ox, b.y - oy
        total += ax * by - ay * bx
    if abs(total) < 1e-9:
        return "mixed"
    return "clockwise" if total > 0 else "counterclockwise"
```

- [ ] **Step 4: Run tests.** Expected: 7 passed. If `test_post_contour_latency` fails on float rounding, verify the expected value by hand from the fixture timings before changing the assertion — do not loosen a test to make it pass.

---

### Task 7: Orchestrator

**Files:**
- Create: `strokeanalyzer/features.py`
- Test: `strokeanalyzer/tests/test_features.py`

- [ ] **Step 1: Write the failing test**

```python
from strokeanalyzer import FEATURE_SCHEMA_VERSION
from strokeanalyzer.features import analyze
from strokeanalyzer.io import load_meridian
from strokeanalyzer.synth import write_synthetic_capture


def test_analyze_returns_flat_dict(tmp_path):
    base = write_synthetic_capture(tmp_path, n_strokes=5, points_per_stroke=80)
    result = analyze(load_meridian(base))
    assert isinstance(result, dict)
    assert all(not isinstance(v, dict) for v in result.values())


def test_result_carries_provenance(tmp_path):
    base = write_synthetic_capture(tmp_path, n_strokes=2, points_per_stroke=20)
    result = analyze(load_meridian(base))
    assert result["feature_schema_version"] == FEATURE_SCHEMA_VERSION
    assert result["source"] == "meridian1"
    assert result["integrity_verified"] is True


def test_result_always_carries_quality_block(tmp_path):
    base = write_synthetic_capture(tmp_path, n_strokes=2, points_per_stroke=20)
    result = analyze(load_meridian(base))
    for k in ("predicted_sample_fraction", "sample_rate_hz_effective",
              "stylus_fraction", "has_force_sensor"):
        assert k in result


def test_spectral_gated_on_stability(tmp_path):
    # jittered timestamps -> unstable rate -> spectral features None
    samples, t = [], 0.0
    for i in range(400):
        samples.append({"t": t, "x": 100.0 + i % 7, "y": 100.0, "p": 0.5,
                        "pRaw": 2.0, "pMax": 4.0, "alt": 1.0, "az": 0.0,
                        "type": "stylus", "phase": "move", "stroke": 0})
        t += 4.0 if i % 2 else 40.0
    base = write_synthetic_capture(tmp_path, samples=samples, base_name="jitter")
    result = analyze(load_meridian(base))
    assert result["sample_rate_is_stable"] is False
    assert result["relpow_vel_4_7hz"] is None
    assert result["spectral_reason"] == "unstable_sample_rate"
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement `strokeanalyzer/features.py`**

```python
"""Orchestrator: one flat dict per capture, stamped with schema version.

Flat because results tabulate straight into a DataFrame for the study and
diff cleanly across versions.
"""

from strokeanalyzer import FEATURE_SCHEMA_VERSION
from strokeanalyzer.kinematics import kinematic_features
from strokeanalyzer.quality import quality_features
from strokeanalyzer.sequence import sequence_features
from strokeanalyzer.spectral import spectral_features
from strokeanalyzer.timing import timing_features
from strokeanalyzer.types import Capture


def analyze(capture: Capture) -> dict:
    q = quality_features(capture)
    result: dict = {
        "feature_schema_version": FEATURE_SCHEMA_VERSION,
        "source": capture.source,
        "artifact_id": capture.artifact_id,
        "integrity_verified": capture.integrity_verified,
        "points_per_mm": capture.points_per_mm,
    }
    result.update(q)
    result.update(timing_features(capture))
    result.update(kinematic_features(capture))
    result.update(spectral_features(
        capture,
        sample_rate_hz=q.get("sample_rate_hz_effective"),
        rate_is_stable=bool(q.get("sample_rate_is_stable"))))
    result.update(sequence_features(capture))
    return result
```

- [ ] **Step 4: Run the full suite**

```bash
cd /Users/azamtolla/Documents/MercyCognitiveApp/stroke-research && source .venv/bin/activate && python -m pytest -v
```

Expected: all tests pass (about 38 by this point).

---

### Task 8: Adapters — PaHaW SVC and Quick, Draw!

**Files:**
- Create: `strokeanalyzer/adapters.py`
- Test: `strokeanalyzer/tests/test_adapters.py`

**SVC format** (from `repo/examples/data/info.json`, verbatim): line 1 = number of samples; line n = `Y X timestamp button_state azimuth altitude pressure`. Button state 0 = pen-up (in-air), 1 = pen-down. Wacom Intuos 4M, **200 Hz**.

Note the column order: **Y before X**. Getting this backwards silently mirrors every drawing.

**Quick, Draw! raw format:** `drawing` = list of strokes, each `[[x...], [y...], [t_ms...]]`.

- [ ] **Step 1: Write the failing test**

```python
from pathlib import Path

import pytest

from strokeanalyzer.adapters import load_pahaw_svc, load_quickdraw_line

PAHAW = Path("repo/examples/data/PD-male/00009_w.cz.fnusa.1_1.svc")


@pytest.mark.skipif(not PAHAW.exists(), reason="PaHaW sample not present")
def test_pahaw_loads_with_strokes():
    cap = load_pahaw_svc(PAHAW)
    assert cap.source == "pahaw_svc"
    assert len(cap.strokes) >= 1
    assert len(cap.all_samples) > 100


@pytest.mark.skipif(not PAHAW.exists(), reason="PaHaW sample not present")
def test_pahaw_button_state_splits_strokes():
    """Pen-up samples must not be inside strokes; they define the gaps."""
    cap = load_pahaw_svc(PAHAW)
    for st in cap.strokes:
        assert all(s.phase != "up_inair" for s in st.samples)


def test_quickdraw_line_parses():
    line = ('{"word":"clock","recognized":true,"key_id":"1",'
            '"drawing":[[[0,10,20],[0,0,0],[0,50,100]],'
            '[[30,40],[5,5],[200,250]]]}')
    cap = load_quickdraw_line(line)
    assert cap.source == "quickdraw"
    assert len(cap.strokes) == 2
    assert cap.strokes[0].samples[1].t == 50.0
    assert cap.strokes[1].samples[0].x == 30.0
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement `strokeanalyzer/adapters.py`**

```python
"""Adapters turning other corpora into the same Capture representation.

PaHaW SVC (info.json, verbatim): "1st line: number of samples; n-th line:
Y coordinate, X coordinate, time stamp, button state, azimuth, altitude,
pressure". Button state 0 = pen-up (in-air), 1 = pen-down. 200 Hz.
NOTE Y COMES FIRST - reversing it silently mirrors every drawing.

Quick, Draw! raw: drawing = [[[x...],[y...],[t_ms...]], ...] per stroke.
CC BY 4.0. Healthy doodles on mouse/touch: ENGINEERING DATA ONLY. Median
stroke count is 4 vs 24.92 +/- 5.22 for real clocks (Davoudi 2021), so these
must not calibrate stroke-count, anchoring prevalence, or digit features.
"""

import json
from pathlib import Path
from typing import Union

from strokeanalyzer.types import Capture, Sample, Stroke

# Wacom Intuos 4M reports 0.02 mm per unit => 50 units/mm. The Capture field is
# points_per_mm; for SVC we express coordinates directly in device units.
PAHAW_UNITS_PER_MM = 50.0
PAHAW_SAMPLE_RATE_HZ = 200.0
PAHAW_PRESSURE_MAX = 32767.0


def load_pahaw_svc(path: Union[str, Path]) -> Capture:
    path = Path(path)
    lines = path.read_text().strip().splitlines()
    strokes, current, idx = [], [], 0
    prev_down = False

    for raw in lines[1:]:
        parts = raw.split()
        if len(parts) < 7:
            continue
        y, x, t, button, az, alt, pressure = (float(v) for v in parts[:7])
        is_down = button == 1.0
        if is_down:
            current.append(Sample(
                t=t, x=x, y=y,
                p=pressure / PAHAW_PRESSURE_MAX, p_raw=pressure,
                p_max=PAHAW_PRESSURE_MAX,
                alt=alt, az=az, type="stylus",
                phase="down" if not prev_down else "move"))
        elif current:
            strokes.append(Stroke(index=idx, samples=current))
            idx += 1
            current = []
        prev_down = is_down

    if current:
        strokes.append(Stroke(index=idx, samples=current))

    return Capture(strokes=strokes, points_per_mm=PAHAW_UNITS_PER_MM,
                   source="pahaw_svc", integrity_verified=False,
                   artifact_id=path.stem)


def load_quickdraw_line(line: str) -> Capture:
    d = json.loads(line)
    strokes = []
    for i, st in enumerate(d["drawing"]):
        xs, ys = st[0], st[1]
        ts = st[2] if len(st) > 2 else list(range(len(xs)))
        strokes.append(Stroke(index=i, samples=[
            Sample(t=float(t), x=float(x), y=float(y), type="stylus",
                   phase="down" if j == 0 else "move")
            for j, (x, y, t) in enumerate(zip(xs, ys, ts))]))
    return Capture(strokes=strokes, points_per_mm=1.0, source="quickdraw",
                   artifact_id=str(d.get("key_id", "")))
```

- [ ] **Step 4: Run tests.** Expected: 3 passed.

---

### Task 9: Validation suite

**Files:**
- Create: `strokeanalyzer/tests/test_validation.py`

This is the task that decides whether the implementation is trustworthy. Each check has a published or independently-measured reference.

- [ ] **Step 1: Write the validation tests**

```python
"""Validation against real data and published references.

References:
  Davoudi et al. 2021, J Alzheimers Dis 82:59-70, doi 10.3233/JAD-201249
    n=430 cognitively-well adults 55+, digital CDT at 75 Hz.
  BDALab handwriting-features (MIT), measured on the same PaHaW files:
    median air:ink ratio 0.21.
  Measured in this project on 6,982 Quick, Draw! clocks:
    air:ink 0.66, contour_first 94%, median inter-stroke gap 479 ms.
"""

import json
import statistics
from pathlib import Path

import pytest

from strokeanalyzer.adapters import load_pahaw_svc, load_quickdraw_line
from strokeanalyzer.features import analyze

PAHAW_DIR = Path("repo/examples/data")
QUICKDRAW = Path("quickdraw/clock_raw.ndjson")


@pytest.mark.skipif(not PAHAW_DIR.exists(), reason="PaHaW data absent")
def test_pahaw_air_ink_matches_bdalab_reference():
    """Independent cross-check: our air:ink on PaHaW must land near the value
    the MIT-licensed BDALab library produced on the same files (0.21).
    A large divergence means WE are wrong."""
    ratios = []
    for svc in sorted(PAHAW_DIR.rglob("*.svc")):
        r = analyze(load_pahaw_svc(svc)).get("air_ink_ratio")
        if r is not None:
            ratios.append(r)
    assert len(ratios) >= 20, f"only {len(ratios)} files produced a ratio"
    median = statistics.median(ratios)
    assert 0.10 <= median <= 0.40, f"median air:ink {median:.3f} far from 0.21 reference"


@pytest.mark.skipif(not QUICKDRAW.exists(), reason="Quick Draw data absent")
def test_quickdraw_scale_sanity():
    """Geometry and sequencing behave sanely at scale.
    ENGINEERING CHECK ONLY - no clinical inference from these doodles."""
    ratios, contour_first, gaps, n = [], 0, [], 0
    with open(QUICKDRAW) as fh:
        for line in fh:
            if n >= 2000:
                break
            d = json.loads(line)
            if not d.get("recognized") or len(d["drawing"]) < 3:
                continue
            n += 1
            f = analyze(load_quickdraw_line(line))
            if f.get("air_ink_ratio") is not None:
                ratios.append(f["air_ink_ratio"])
            if f.get("contour_first"):
                contour_first += 1
            if f.get("pause_median_ms") is not None:
                gaps.append(f["pause_median_ms"])

    assert n >= 500
    assert 0.3 <= statistics.median(ratios) <= 1.2, "air:ink far from measured 0.66"
    assert contour_first / n > 0.7, "contour-first rate far below measured 94%"
    assert 200 <= statistics.median(gaps) <= 900, "gap far from measured 479 ms"


@pytest.mark.skipif(not QUICKDRAW.exists(), reason="Quick Draw data absent")
def test_quickdraw_is_not_used_for_stroke_count_calibration():
    """Documents the limitation: real clocks average 24.92 +/- 5.22 strokes
    (Davoudi 2021); these doodles are far simpler. This test asserts the
    DIFFERENCE so nobody later mistakes Quick Draw for a clock-count norm."""
    counts = []
    with open(QUICKDRAW) as fh:
        for i, line in enumerate(fh):
            if i >= 1000:
                break
            d = json.loads(line)
            if d.get("recognized"):
                counts.append(len(d["drawing"]))
    assert statistics.median(counts) < 10, (
        "Quick Draw median stroke count unexpectedly high; if it approaches "
        "25 the corpus assumption in the spec needs revisiting")
```

- [ ] **Step 2: Run the validation suite**

```bash
cd /Users/azamtolla/Documents/MercyCognitiveApp/stroke-research && source .venv/bin/activate && python -m pytest strokeanalyzer/tests/test_validation.py -v
```

Expected: 3 passed. **If `test_pahaw_air_ink_matches_bdalab_reference` fails, stop and debug the implementation — do not widen the bounds.** An independent implementation disagreeing is the single most informative signal available here.

- [ ] **Step 3: Record the measured values** in a new file `strokeanalyzer/VALIDATION.md`: the actual median air:ink on PaHaW, the Quick, Draw! medians, and the date. Future changes diff against these.

---

### Task 10: Golden fixtures for the Swift port

**Files:**
- Create: `strokeanalyzer/fixtures/generate_fixtures.py`
- Create: `strokeanalyzer/fixtures/*.jsonl`, `*.manifest.json`, `*.expected.json`
- Test: `strokeanalyzer/tests/test_fixtures.py`

- [ ] **Step 1: Write the fixture generator**

```python
"""Generate golden input/expected pairs — the Python<->Swift parity contract.

Swift's StrokeAnalyzer test suite loads these same .jsonl files and asserts
the same .expected.json values within tolerance. A divergence is a test
failure in whichever implementation changed.
"""

import json
import math
from pathlib import Path

from strokeanalyzer.features import analyze
from strokeanalyzer.io import load_meridian
from strokeanalyzer.synth import generate_circle, write_synthetic_capture

HERE = Path(__file__).parent

CASES = {
    "circle_constant_speed": lambda: generate_circle(radius_mm=20.0, velocity_mmps=30.0),
    "circle_slow": lambda: generate_circle(radius_mm=15.0, velocity_mmps=10.0),
}


def _clock_with_anchoring():
    """Contour, then marks at 12, 3, 6, 9, then four more."""
    samples, t, stroke = [], 0.0, 0
    for i in range(120):
        a = 2 * math.pi * i / 120
        samples.append({"t": t, "x": 100 + 50 * math.cos(a), "y": 100 + 50 * math.sin(a),
                        "p": 0.5, "pRaw": 2.0, "pMax": 4.0, "alt": 1.0, "az": 0.0,
                        "type": "stylus",
                        "phase": "down" if i == 0 else ("up" if i == 119 else "move"),
                        "stroke": stroke})
        t += 4.0
    for cx, cy in [(100, 55), (145, 100), (100, 145), (55, 100),
                   (122, 65), (135, 122), (78, 135), (65, 78)]:
        t += 400.0
        stroke += 1
        for j in range(8):
            samples.append({"t": t, "x": cx + j * 0.5, "y": cy, "p": 0.5,
                            "pRaw": 2.0, "pMax": 4.0, "alt": 1.0, "az": 0.0,
                            "type": "stylus",
                            "phase": "down" if j == 0 else ("up" if j == 7 else "move"),
                            "stroke": stroke})
            t += 4.0
    return samples


CASES["clock_anchoring"] = _clock_with_anchoring


def main():
    HERE.mkdir(parents=True, exist_ok=True)
    for name, make in CASES.items():
        base = write_synthetic_capture(HERE, samples=make(), base_name=name)
        result = analyze(load_meridian(base))
        Path(str(base) + ".expected.json").write_text(
            json.dumps(result, indent=2, sort_keys=True, default=str))
        print(f"wrote fixture {name}: {len(result)} features")


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Generate the fixtures**

```bash
cd /Users/azamtolla/Documents/MercyCognitiveApp/stroke-research && source .venv/bin/activate && python -m strokeanalyzer.fixtures.generate_fixtures
```

Expected: three lines reporting fixtures written.

- [ ] **Step 3: Write the regression test**

```python
import json
from pathlib import Path

import pytest

from strokeanalyzer.features import analyze
from strokeanalyzer.io import load_meridian

FIX = Path(__file__).parent.parent / "fixtures"
TOL_EXACT = 1e-6      # pure arithmetic
TOL_SPECTRAL = 1e-3   # FFT: library differences are legitimate
SPECTRAL_PREFIXES = ("relpow_", "tremor_stability")


@pytest.mark.parametrize("expected_path", sorted(FIX.glob("*.expected.json")))
def test_fixture_roundtrip(expected_path):
    base = str(expected_path).replace(".expected.json", "")
    expected = json.loads(expected_path.read_text())
    actual = analyze(load_meridian(base))

    assert set(actual) == set(expected), "feature key set drifted"
    for key, exp in expected.items():
        act = actual[key]
        if isinstance(exp, (int, float)) and not isinstance(exp, bool) and act is not None:
            tol = TOL_SPECTRAL if key.startswith(SPECTRAL_PREFIXES) else TOL_EXACT
            assert abs(act - exp) <= tol * max(1.0, abs(exp)), f"{key}: {act} != {exp}"
        else:
            assert act == exp or str(act) == str(exp), f"{key}: {act} != {exp}"
```

- [ ] **Step 4: Run the full suite.** Expected: everything passes, including 3 fixture cases.

---

### Task 11: Capture a REAL MERIDIAN-1 artifact and verify the reader

**Files:** none created — verification only.

**Why this is mandatory:** every test so far reads data this package generated itself. A reader validated only against its own synthetic output proves nothing about the real recorder's field names, units, or edge cases.

- [ ] **Step 1: Build and run the app in Research mode**

```bash
cd /Users/azamtolla/Documents/MercyCognitiveApp/VoiceMiniCog && xcodebuild build -project VoiceMiniCog.xcodeproj -scheme VoiceMiniCog -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' -quiet
```

Then launch on the `Ipad 13 inch sim` simulator, enter Research mode (hidden 5-tap staff entry per `ResearchModeSettings.swift`), and complete one capture by drawing with the mouse.

- [ ] **Step 2: Locate the artifact**

```bash
find ~/Library/Developer/CoreSimulator/Devices -name "*.jsonl" -newermt "-1 hour" 2>/dev/null | head -5
```

Expected: at least one `.jsonl` with sibling `.manifest.json` and `.sha256`.

- [ ] **Step 3: Load it and report**

```bash
cd /Users/azamtolla/Documents/MercyCognitiveApp/stroke-research && source .venv/bin/activate && python -c "
import sys, json
from strokeanalyzer.io import load_meridian
from strokeanalyzer.features import analyze
base = sys.argv[1].replace('.jsonl','')
cap = load_meridian(base)
r = analyze(cap)
print('strokes', len(cap.strokes), '| samples', len(cap.all_samples))
print('effective Hz', r['sample_rate_hz_effective'], '| stable', r['sample_rate_is_stable'])
print('stylus_fraction', r['stylus_fraction'], '| force sensor', r['has_force_sensor'])
print('air:ink', r['air_ink_ratio'], '| contour_first', r['contour_first'])
" <PATH_TO_JSONL>
```

- [ ] **Step 4: Reconcile.** Simulator input is mouse, so expect `stylus_fraction` near 0 and `has_force_sensor` False — that is correct behaviour, not a bug, and it proves the quality gating works. Record any field-name or unit mismatch between the real manifest and `io.py`, fix `io.py`, and re-run the suite.

- [ ] **Step 5: Report** the real capture's quality block, any mismatches found and fixed, and whether a physical iPad + Apple Pencil run is still needed to exercise force/tilt/azimuth paths (it is — note it as the follow-up).

---

## Self-Review Notes

- **Spec coverage:** §2 input → Tasks 1, 11; §3 architecture → Tasks 0–7; §4.1 timing → Task 3; §4.2 kinematics → Tasks 4, 5; §4.3 sequence → Task 6; §4.4 quality → Task 2; §5 validation → Task 9; §6 error handling → Tasks 1 (manifest/integrity refusal), 2 (gating), 3 (None-not-zero); §7 regulatory → no clinical surface is touched by any task; §10.1 bands → Task 5; §10.2 latencies → Task 3 + Task 6 `post_contour_latency_s`; §10.3 naming → Task 6.
- **Deliberately deferred:** the Swift port (fixtures exist to make it verifiable), `pre_first_hand_latency_s` and all semantic parsing (v2, needs labelled data), and the clinical-view import guard (belongs with the Swift port, since there are no Swift imports to guard yet).
- **Type consistency:** `Capture`/`Stroke`/`Sample` field names are identical across Tasks 1, 2, 3, 4, 5, 6, 8. `points_per_mm` is the single units source everywhere. `speed_series` is defined in Task 4 and consumed in Task 5.
- **Known risk:** Task 9's PaHaW cross-check may fail on the SVC stroke-splitting rule (pen-up handling) rather than on the timing maths. If it fails, debug the adapter before the timing module — the adapter is newer and less tested.
