//
//  HomeView.swift
//  VoiceMiniCog
//
//  Patient-facing home: ONE big "Tap to Begin" button, nothing else.
//  Mode selection (Quick / Family Caregiver / Extended) lives behind the
//  clinician dashboard (ClinicianDashboardView), gated by long-press +
//  passcode.
//
//  Autonomous-operation design:
//    - 24pt minimum font throughout.
//    - Dynamic Type respected (.dynamicTypeSize).
//    - Tap-only — no swipes, no pinches, no gestures beyond .onTapGesture.
//    - Audio-only fallback surfaced if the device lacks a working mic/cam.
//

import SwiftUI

struct HomeView: View {
    /// Called when the patient taps the begin button. Host decides which
    /// flow to launch based on the clinician's pre-selected mode.
    let onSelectFlow: (AssessmentFlowType) -> Void
    /// Called when the clinician triggers the hidden dashboard gesture
    /// (5-tap chord on the brain icon).
    var onOpenClinicianDashboard: (() -> Void)? = nil

    @State private var appeared = false
    @State private var dashboardTapCount = 0
    @State private var dashboardTapResetTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The mode the clinician pre-selected via the dashboard. Persisted
    /// across launches so the nurse sets it once at start-of-day.
    @AppStorage("voiceMiniCog.preselectedFlow") private var preselectedFlowRaw: String = AssessmentFlowType.quick.rawValue

    private var preselectedFlow: AssessmentFlowType {
        AssessmentFlowType(rawValue: preselectedFlowRaw) ?? .quick
    }

    var body: some View {
        ZStack {
            homeCanvasBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Brain icon — completely static, hidden 5-tap chord trigger.
                staticBrainIcon
                    .onTapGesture { handleHiddenDashboardTap() }
                    .accessibilityLabel("Brain Health Screening")
                    .padding(.bottom, 28)

                Text("Brain Health Check")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(Self.heroBlue)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 14)

                Text("A quick check-in with your thinking")
                    .font(.title3.weight(.regular))
                    .foregroundStyle(Color.secondary)
                    .padding(.top, 10)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 14)

                Spacer()

                Button {
                    let haptic = UIImpactFeedbackGenerator(style: .medium)
                    haptic.prepare(); haptic.impactOccurred()
                    onSelectFlow(preselectedFlow)
                } label: {
                    beginButtonLabel
                }
                .buttonStyle(HomeBeginButtonStyle())
                .accessibilityLabel("Tap to begin the brain health check")
                .accessibilityHint("Starts the assessment")
                .padding(.bottom, 40)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 18)

                Spacer()
            }
        }
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.easeOut(duration: 0.4).delay(0.1)) { appeared = true }
            }
        }
    }

    // MARK: - Palette

    /// Fresh, modern iOS blue — between SF Symbol blue and a deeper tech
    /// accent. Used for the title, icon, and the Begin button fill.
    fileprivate static let heroBlue = Color(red: 0.22, green: 0.49, blue: 0.97)

    /// Slightly deeper variant for the button gradient's trailing stop —
    /// gives the pill a subtle depth without heavy shading.
    fileprivate static let heroBlueDeep = Color(red: 0.14, green: 0.38, blue: 0.87)

    // MARK: - Canvas background

    /// Warm off-white base with a very soft blue breath behind the hero —
    /// keeps the page calm and modern without gradients competing with text.
    @ViewBuilder
    private var homeCanvasBackground: some View {
        ZStack {
            Color(red: 0.976, green: 0.980, blue: 0.988)
            RadialGradient(
                colors: [Self.heroBlue.opacity(0.07), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 620
            )
        }
    }

    // MARK: - Static brain icon (no animation)

    @ViewBuilder
    private var staticBrainIcon: some View {
        Image(systemName: "brain.head.profile")
            .resizable()
            .scaledToFit()
            .frame(width: 112, height: 112)
            .foregroundStyle(Self.heroBlue)
            .symbolRenderingMode(.hierarchical)
    }

    // MARK: - Begin button label

    /// iOS-flavored Begin pill — rounded rect with a gentle gradient fill,
    /// soft accent glow, scale-on-press feedback. No shimmer / no idle
    /// animation so the page stays calm.
    @ViewBuilder
    private var beginButtonLabel: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        HStack(spacing: 10) {
            Image(systemName: "play.fill")
                .font(.system(size: 22, weight: .bold))
            Text("Tap to Begin")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 56)
        .padding(.vertical, 24)
        .frame(minHeight: 76)
        .background(
            shape
                .fill(
                    LinearGradient(
                        colors: [Self.heroBlue, Self.heroBlueDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            shape
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: Self.heroBlue.opacity(0.35), radius: 16, x: 0, y: 8)
    }

    /// 5-tap chord on the brain icon within 3s opens the clinician
    /// dashboard. Tap-only (no long-press / no swipe) per autonomous
    /// accessibility rules.
    private func handleHiddenDashboardTap() {
        dashboardTapCount += 1
        dashboardTapResetTask?.cancel()
        if dashboardTapCount >= 5 {
            dashboardTapCount = 0
            onOpenClinicianDashboard?()
            return
        }
        dashboardTapResetTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled {
                await MainActor.run { dashboardTapCount = 0 }
            }
        }
    }
}

// MARK: - HomeBeginButtonStyle

/// Press feedback for the primary Home CTA: scale 0.96, raised shadow
/// bloom, spring release. Gated on reduce-motion.
struct HomeBeginButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? 0.96 : 1.0))
            .animation(AssessmentTheme.Motion.microFeedback, value: configuration.isPressed)
    }
}

#Preview {
    HomeView(onSelectFlow: { _ in }, onOpenClinicianDashboard: {})
}
