//
//  ProgressTrackView.swift
//  VoiceMiniCog
//
//  "Chevron Phase Track" — a horizontal pipeline of connected phase boxes
//  whose right edges are chevron points. Each box's chevron slots into the
//  next box's matching V-notch on the left, creating a clean → → → flow
//  with no gaps between boxes.
//
//  States:
//    • upcoming   — low opacity (22%) accent fill + 60% accent text
//    • active     — full accent fill, white text, cardResting shadow,
//                   scaleEffect y=1.08 (lifted)
//    • completed  — 75% accent fill, white text, checkmark replaces icon
//
//  All state transitions use a spring(.4, .7). Reduce-motion degrades to
//  an easeInOut crossfade.
//

import SwiftUI

// MARK: - ProgressTrackView (public API preserved)

struct ProgressTrackView: View {
    let layoutManager: AvatarLayoutManager

    var body: some View {
        PhaseProgressTrack(layoutManager: layoutManager)
    }
}

// MARK: - PhaseProgressTrack

struct PhaseProgressTrack: View {
    let layoutManager: AvatarLayoutManager

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Displayed phases — `.completion` is excluded from the track
    /// (it's an end-state screen, not part of the pipeline).
    private var phases: [AssessmentPhaseID] {
        layoutManager.phaseSequence.filter { $0 != .completion }
    }

    private var currentIndex: Int {
        phases.firstIndex(of: layoutManager.currentPhase) ?? 0
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(phases.enumerated()), id: \.element) { i, phase in
                PhaseChevronCell(
                    phase: phase,
                    state: cellState(for: i),
                    accent: AssessmentTheme.accent(for: phase.rawValue),
                    isFirst: i == 0
                )
            }
        }
        .frame(height: 38)
        .animation(
            reduceMotion
                ? .easeInOut(duration: 0.2)
                : .spring(response: 0.4, dampingFraction: 0.7),
            value: currentIndex
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Phase \(currentIndex + 1) of \(phases.count): \(layoutManager.currentPhase.displayName)"
        )
    }

    private func cellState(for index: Int) -> PhaseCellState {
        if index < currentIndex { return .completed }
        if index == currentIndex { return .active }
        return .upcoming
    }
}

// MARK: - Cell state

enum PhaseCellState { case upcoming, active, completed }

// MARK: - PhaseChevronCell

private struct PhaseChevronCell: View {
    let phase: AssessmentPhaseID
    let state: PhaseCellState
    let accent: Color
    let isFirst: Bool

    private let chevronDepth: CGFloat = 10

    var body: some View {
        ZStack {
            shape
                .fill(fillColor)
                .overlay(
                    shape.stroke(
                        state == .upcoming ? accent.opacity(0.35) : .clear,
                        lineWidth: 0.5
                    )
                )
                .shadow(
                    color: state == .active ? Color.black.opacity(0.18) : .clear,
                    radius: state == .active ? 6 : 0,
                    y: state == .active ? 2 : 0
                )

            // Icons removed per brief — labels only, 11pt medium, zero
            // truncation. Full text centered inside the box.
            Text(shortName)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .fixedSize(horizontal: false, vertical: false)
                .foregroundStyle(foregroundColor)
                // First box has no left notch, so less leading inset.
                .padding(.leading, isFirst ? 10 : 10 + chevronDepth)
                .padding(.trailing, 10 + chevronDepth)
                .frame(maxWidth: .infinity, alignment: .center)
                .overlay(alignment: .leading) {
                    // Small completed-state checkmark before the label so
                    // completed phases still read as "done" without an icon.
                    if state == .completed {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(foregroundColor)
                            .padding(.leading, isFirst ? 8 : 8 + chevronDepth)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
        }
        .frame(maxWidth: .infinity)
        .scaleEffect(x: 1.0, y: state == .active ? 1.08 : 1.0, anchor: .center)
    }

    private var shape: ChevronBoxShape {
        ChevronBoxShape(chevronDepth: chevronDepth, hasLeftNotch: !isFirst)
    }

    private var fillColor: Color {
        switch state {
        case .upcoming:  return accent.opacity(0.22)
        case .active:    return accent
        case .completed: return accent.opacity(0.75)
        }
    }

    private var foregroundColor: Color {
        switch state {
        case .upcoming:          return accent.opacity(0.75)
        case .active, .completed: return .white
        }
    }

    // MARK: - Content mapping

    private var shortName: String {
        switch phase {
        case .welcome:          return "Welcome"
        case .qdrs:             return "Caregiver"
        case .phq2:             return "Mood"
        case .orientation:      return "Orient"
        case .wordRegistration: return "Words"
        case .clockDrawing:     return "Clock"
        case .verbalFluency:    return "Fluency"
        case .storyRecall:      return "Story"
        case .wordRecall:       return "Recall"
        case .completion:       return "Done"
        }
    }
}

// MARK: - ChevronBoxShape

/// Pentagon with:
///   • right edge → chevron point (always)
///   • left edge  → matching V-notch (inward) for all but the first box,
///                   so the previous box's chevron slots into it cleanly.
///
/// Not animatable — shape geometry is constant per cell; state animations
/// live on fill / shadow / scale at the wrapper level.
struct ChevronBoxShape: Shape {
    var chevronDepth: CGFloat = 10
    var hasLeftNotch: Bool = true

    func path(in rect: CGRect) -> Path {
        var p = Path()
        // top-left
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // top edge
        p.addLine(to: CGPoint(x: rect.maxX - chevronDepth, y: rect.minY))
        // right chevron tip
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX - chevronDepth, y: rect.maxY))
        // bottom edge
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        if hasLeftNotch {
            // V-notch inward so the previous cell's chevron fits cleanly
            p.addLine(to: CGPoint(x: rect.minX + chevronDepth, y: rect.midY))
        }
        p.closeSubpath()
        return p
    }
}
