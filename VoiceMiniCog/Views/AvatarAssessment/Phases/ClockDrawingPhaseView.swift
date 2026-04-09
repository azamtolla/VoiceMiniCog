//
//  ClockDrawingPhaseView.swift
//  VoiceMiniCog
//
//  Phase 6 — Clock Drawing (EXPANDED layout).
//  The avatar shrinks to 30% width and dims to 0.4 opacity (handled by
//  AvatarLayoutManager); the content zone fills the remaining space with
//  a full-screen drawing canvas and a countdown timer.
//
//  CDT scoring rule (15 pts, Shulman 0–5): see CDTOnDeviceScorer.
//  This view captures strokes only; scoring happens at review time.
//
//  MARK: CLINICAL-UI — Clock drawing is a validated Qmci subtest (15 pts).
//  Design rationale: No undo button, no drawing guides beyond the dashed
//  circle, timer hidden from patient, every stroke captured for
//  biomarker extraction. See CLAUDE.md §Digital Biomarker Capture.
//

import SwiftUI

// MARK: - ClockDrawingPhaseView

struct ClockDrawingPhaseView: View {

    // MARK: Properties

    let layoutManager: AvatarLayoutManager
    @Bindable var assessmentState: AssessmentState

    @State private var lines: [[CGPoint]] = []
    @State private var currentLine: [CGPoint] = []
    @State private var timeRemaining = 180 // 3 minutes
    @State private var timer: Timer?
    @State private var contentVisible = false

    // MARK: Body

    var body: some View {
        VStack(spacing: 12) {

            // 1. Instruction text
            Text(LeftPaneSpeechCopy.clockDrawingOnScreen)
                .font(AssessmentTheme.Fonts.question)
                .foregroundStyle(AssessmentTheme.Content.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .assessmentContentEnter(isVisible: contentVisible, yOffset: 14)
                .animation(AssessmentTheme.Anim.contentEnter.delay(0.06), value: contentVisible)

            // 2. Drawing canvas — fills all available space
            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                let guideSize = size * 0.75

                ZStack {
                    // White card surface
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white)
                        .shadow(
                            color: AssessmentTheme.Content.shadowColor.opacity(0.08),
                            radius: 8,
                            y: 4
                        )

                    // Dashed circle guide
                    Circle()
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 1.5, dash: [8, 4])
                        )
                        .foregroundColor(Color.gray.opacity(0.25))
                        .frame(width: guideSize, height: guideSize)

                    // SwiftUI Canvas — renders completed lines + current stroke
                    Canvas { context, _ in
                        for stroke in lines {
                            drawStroke(stroke, in: context)
                        }
                        drawStroke(currentLine, in: context)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                currentLine.append(value.location)
                            }
                            .onEnded { _ in
                                if !currentLine.isEmpty {
                                    lines.append(currentLine)
                                    currentLine = []
                                }
                            }
                    )
                }
                .frame(width: size, height: size)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .assessmentContentEnter(isVisible: contentVisible, yOffset: 18)
            .animation(AssessmentTheme.Anim.contentEnter.delay(0.12), value: contentVisible)

            // 3. Bottom bar: timer only (Done Drawing moved to right-side status panel)
            HStack {
                Spacer()
                Text(formatTime(timeRemaining))
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(timeRemaining <= 30 ? Color.red : AssessmentTheme.Content.textSecondary)
                Spacer()
            }
            .padding(.bottom, 4)
        }
        .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
        .onAppear {
            withAnimation(AssessmentTheme.Anim.contentEnter.delay(0.05)) {
                contentVisible = true
            }
            avatarSetContext("You are on the Clock Drawing phase. The patient is drawing a clock. Stay quiet and wait. Do NOT give hints, do NOT comment on their drawing, do NOT advance to the next phase. Only speak when sent echo commands. If the patient asks for help, say 'Just do your best.'")
            avatarSpeak(LeftPaneSpeechCopy.clockDrawingInstruction)
            startTimer()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if timeRemaining > 0 {
                timeRemaining -= 1
            } else {
                timer?.invalidate()
                layoutManager.advanceToNextPhase()
            }
        }
    }

    // MARK: - Drawing Helpers

    private func drawStroke(_ points: [CGPoint], in context: GraphicsContext) {
        var path = Path()
        guard let first = points.first else { return }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        context.stroke(path, with: .color(.black), lineWidth: 2.5)
    }

    // MARK: - Formatting

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Preview

#Preview("Clock Drawing Phase") {
    ClockDrawingPhaseView(
        layoutManager: AvatarLayoutManager(),
        assessmentState: AssessmentState()
    )
    .background(AssessmentTheme.Content.background)
}
