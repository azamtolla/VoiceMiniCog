# Avatar-Guided Assessment UI — Design Spec

**Date:** 2026-04-02
**Status:** Pending approval
**Author:** Azam Tolla, DO

---

## Core Philosophy

This is ONE canvas, not two panels. The avatar and content zone share a single
unified space that breathes and reshapes around context. The content zone is
always the primary focus. The avatar is ambient — present, alive, never competing.
No dividers. No borders. No hard edges. One living UI.

---

## Phases

1. Welcome / Intro
2. QDRS (10 questions)
3. PHQ-2 (2 questions)
4. Orientation (5 questions)
5. Word Registration
6. Clock Drawing — EXPANDED
7. Verbal Fluency — EXPANDED
8. Story Recall
9. Word Recall

---

## 1. FLUID LAYOUT — No Fixed Split

Avatar width is not fixed. It is a `@Published var` owned by `AvatarStateManager`.
Content width always fills the remainder: `contentWidth = screenWidth - avatarWidth`

```swift
let avatarWidths: [Int: CGFloat] = [
    1: screenWidth * 0.65, // Welcome — large, full presence
    2: screenWidth * 0.50, // QDRS — medium
    3: screenWidth * 0.50, // PHQ-2 — medium
    4: screenWidth * 0.50, // Orientation — medium
    5: screenWidth * 0.50, // Word Registration — medium
    6: screenWidth * 0.30, // Clock Drawing — small, content takes over
    7: screenWidth * 0.30, // Verbal Fluency — small, content takes over
    8: screenWidth * 0.55, // Story Recall — medium-large, narrator
    9: screenWidth * 0.45  // Word Recall — medium, attentive
]
```

Width changes animate via spring — not linear resize, a living contraction/expansion.
Content layout reflows on width change via Auto Layout — no hardcoded frames.

---

## 2. UNIFIED BACKGROUND — One Layer, No Hard Edges

Single `CAGradientLayer` behind the entire screen. No panel backgrounds.
The dark avatar zone bleeds into the content zone organically via smooth gradient.
Gradient locations animate in sync with avatar width changes.

Colors:
- Far right (deep behind avatar): `#080808`
- Transition zone (no hard line): `#141416`
- Content zone (slightly lighter): `#1C1C1E`

Gradient is horizontal (right to left). Locations animate to match avatar width ratio.

Subtle radial accent tint (5% opacity) bleeds from avatar center on each phase change — reinforces phase color without feeling heavy.

---

## 3. PHASE TRANSITIONS — 3-Act Choreography

Total duration: 0.55s.

**ACT 1 — Content breathes out (0.0s to 0.20s)**
- Left content: opacity 1 to 0, scale 1.0 to 0.97
- Avatar: begins scaling to new width (spring starts)
- Background gradient: begins cross-dissolving

**ACT 2 — Space reshapes (0.15s to 0.40s)**
- Avatar width spring-animates to new value (stiffness 280, damping 0.75 — slight overshoot)
- Content zone expands/contracts inversely
- Phase accent tint radiates from avatar center
- Phase label clips out

**ACT 3 — New content arrives (0.30s to 0.55s)**
- Left content fades in: opacity 0 to 1
- Content elements stagger in, 40ms delay between each item
- Avatar settles with subtle bounce at new size
- New phase label clips in from top
- Avatar opacity cross-fades to new value (large=1.0, small=0.4)

---

## 4. AVATAR STATE MACHINE

```swift
enum AvatarState {
    case idle          // Welcome, between phases
    case speaking      // Delivering question or instruction
    case listening     // Waiting for patient verbal response (mic open)
    case waiting       // Patient on independent task — phases 6 & 7
    case narrating     // Story recall — sustained speech
    case acknowledging // 1.2s post answer-tap, then → .speaking
    case completing    // End of assessment
}
```

### State to Behavior

| Phase | AvatarState | Opacity | Animation | Ring | Label |
|---|---|---|---|---|---|
| 1 — Welcome | idle | 1.0 | Low, gentle | Accent 40% slow pulse | — |
| 2–4 — Q&A asking | speaking | 1.0 | High, lip sync | Accent 100%, audio-driven | "Speaking" |
| 2–4 — Q&A waiting | idle | 1.0 | Low | Accent 40% | — |
| 5 — Word Reg | speaking | 1.0 | High, slow paced | Accent 100%, audio-driven | "Speaking" |
| 6 — Clock | waiting | 0.4 | Minimal breathing | None | — |
| 7 — Verbal | listening | 0.4 | Subtle nods | Accent 100%, mic-driven | "Listening" |
| 8 — Story | narrating | 1.0 | Highest fidelity | Accent 100%, audio-driven | "Reading story" |
| 9 — Recall | listening | 0.85 | Slow patient nods | Accent 100%, mic-driven | "Listening" |
| Any — answer tapped | acknowledging | 1.0 | Medium | Green flash 1.2s | — |
| End | completing | 1.0 | Celebratory | Accent pulse | — |

### Special Rule — Phases 6 & 7
Avatar is forced to waiting or listening. It becomes a ghost in the corner.
If avatar needs to deliver a mid-task instruction:
- Scales up briefly from 30% to 45% width
- Opacity 0.4 to 1.0
- Delivers spoken line
- Springs back to 30%, fades to 0.4
- Duration of intrusion: exactly as long as the speech, +0.3s

### Ring
- 2pt stroke around avatar
- Color always = phaseAccentColor, animates on phase change (0.3s ease)
- Speaking/narrating: scale driven by TTS audio level (range 1.0–1.06)
- Listening: scale driven by AVAudioRecorder.averagePower (range 1.0–1.08)
- Waiting: no ring
- Idle pulse: opacity 1.0 to 0.5, duration 1.8s, autoreverse, repeat

---

## 5. PHASE ACCENT COLORS

```swift
let phaseAccentColors: [Int: UIColor] = [
    1: UIColor(hex: "#2563EB"), // Welcome — blue
    2: UIColor(hex: "#D97706"), // QDRS — amber
    3: UIColor(hex: "#7C3AED"), // PHQ-2 — violet
    4: UIColor(hex: "#059669"), // Orientation — emerald
    5: UIColor(hex: "#DB2777"), // Word Registration — pink
    6: UIColor(hex: "#DC2626"), // Clock Drawing — red
    7: UIColor(hex: "#0891B2"), // Verbal Fluency — cyan
    8: UIColor(hex: "#4F46E5"), // Story Recall — indigo
    9: UIColor(hex: "#16A34A")  // Word Recall — green
]
```

On every phase change, three animate simultaneously:
1. Background gradient accent tint to new color
2. Avatar ring to new color
3. Active progress segment to new color

---

## 6. PROGRESS INDICATOR

Weighted segmented track at top of content zone:

- Segment weights: [1, 4, 1, 2, 1, 3, 3, 2, 1] (18 units total)
- Track: 4pt height, full content-zone width, cornerRadius 2pt
- Completed: phaseAccentColor, full opacity
- Active: phaseAccentColor + pulse (opacity 1.0 to 0.6, 1.2s, autoreverse)
- Upcoming: white 15% opacity
- Below track: current phase name, SF Pro Text 11pt, white 60%, centered
- Track width reflows as content zone width changes between phases

---

## 7. TYPOGRAPHY

| Role | Font | Size | Color |
|------|------|------|-------|
| Phase label | SF Pro Rounded | 11pt, uppercase, 0.08em tracking | phaseAccentColor 80% |
| Question/instruction | SF Pro Display Semibold | 19pt, lineHeight 1.35 | white |
| Helper text | SF Pro Text Regular | 14pt | white 55% |
| Answer button labels | SF Pro Text Medium | 16pt | white |
| Timers + counters | SF Pro Mono | 13pt, tabular | white |
| Large counters | SF Pro Mono Bold | 48pt | phaseAccentColor |
| Score display | SF Pro Mono Bold | 28pt | white |

All fonts via UIFontMetrics for Dynamic Type.

---

## 8. CONTENT ZONE SURFACES

No hard panel container. Content lives directly on the unified background.

- Answer buttons: systemMaterialDark visual effect, cornerRadius 14
  - Normal: white text, 8% white fill
  - Selected: phaseAccentColor fill 90%, white text, shadow (0 4px 16px accent/40%)
- Content cards (question container): NO background — text floats on gradient
- Clock canvas only: white background (drawing surface), cornerRadius 12
- No colored side borders anywhere — state communicated via fill + shadow

---

## 9. ANSWER BUTTONS

- Minimum height: 56pt (clinical — motor-impaired patients)
- Full content-zone width minus 16pt horizontal padding
- Haptic: UIImpactFeedbackGenerator(.medium) on tap
- Yes/No pairs: side-by-side, 12pt gap, 50% width each
- Multi-option: vertical stack, 56pt each, 8pt gaps
- Press: scale(0.97) touchDown, spring back (stiffness 400, damping 25)
- Correct: #34C759 fill + checkmark.circle.fill
- Incorrect: #FF3B30 fill + xmark.circle.fill
- Buttons reflow width automatically as content zone resizes

---

## 10. EXPANDED PHASE 6 — Clock Drawing

Content zone layout (top to bottom):
- Phase label + progress track pinned at top
- Instruction text: SF Pro Display Semibold 19pt, white
- Drawing canvas: white bg, cornerRadius 12, inset shadow
  — expands to fill ALL available space between instruction and bottom bar
  — canvas width = full content zone width minus 24pt padding
- Bottom bar: timer (SF Mono Bold 32pt) left + "Done Drawing" button right
  - Done Drawing: 56pt tall, phaseAccentColor fill, checkmark SF Symbol

Avatar: waiting state — 30% width, 0.4 opacity, breathing only, no ring

---

## 11. EXPANDED PHASE 7 — Verbal Fluency

Content zone layout:
- Phase label + progress track at top
- Counter: SF Mono Bold 48pt, phaseAccentColor (cyan), countUp on each word
- Progress bar: 4pt, fills left to right (target ~12 words = full), below counter
- Word chips: horizontal wrapping flow
  - Background: white 12% opacity, cornerRadius 8, 8pt H / 6pt V padding
  - Text: SF Pro Text Medium 13pt, white
  - Appear: scale(0.6 to 1.0) + opacity(0 to 1), spring on insert

Avatar: listening — 30% width, 0.4 opacity, subtle nods, ring pulses with mic level

---

## 12. PHASE 9 — Word Recall

- Reference row at top: small gray chips of the 5 registered words, labeled "Registered:"
- Recalled word chips:
  - Correct: #34C759 background, white text
  - Missing: #FF3B30 background, strikethrough text
- Score: SF Mono Bold 28pt, centered below chips, countUp animation on reveal

---

## 13. PAUSE BUTTON

- Always pinned: bottom of content zone, 16pt above safe area
- Style: systemUltraThinMaterialDark, pill shape, 44pt tall, 120pt wide
- Content: pause.fill SF Symbol + "Pause" label, SF Pro Medium 14pt, 8pt gap
- Normal: white 70% opacity. Pressed: white 100%
- Haptic: UIImpactFeedbackGenerator(.light)

---

## 14. ACCESSIBILITY

- All answer buttons: accessibilityLabel = full question + option text
- Avatar speech: UIAccessibility.post(.announcement, argument: spokenText)
- Timer: accessibilityValue updates every 10s
- Reduce Motion:
  - Disable all spring/scale animations
  - Avatar width changes: instant
  - Phase transitions: opacity-only cross-dissolve, 0.2s
  - Word chip inserts: opacity-only
- Touch targets: 56pt minimum height throughout
- Dynamic Type: all fonts via UIFontMetrics, test at Accessibility XL
- VoiceOver: avatar ring state announced
