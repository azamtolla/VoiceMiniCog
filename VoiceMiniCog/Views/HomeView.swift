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
    var onResume: (() -> Void)? = nil
    /// Called when the clinician triggers the hidden dashboard gesture
    /// (5-tap chord on the brain icon).
    var onOpenClinicianDashboard: (() -> Void)? = nil

    @State private var hasInProgress: Bool = false
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
            MCDesign.Colors.background.ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                // Brain icon — hidden 5-tap clinician chord trigger.
                Image(systemName: "brain.head.profile")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .foregroundStyle(MCDesign.Colors.primary700)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : -12)
                    .onTapGesture {
                        handleHiddenDashboardTap()
                    }
                    .accessibilityLabel("Brain Health Screening")

                Text("Brain Health Check")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(MCDesign.Colors.primary700)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                Spacer()

                // The one and only control the patient ever sees here.
                Button {
                    onSelectFlow(preselectedFlow)
                } label: {
                    Text("Tap to Begin")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 64)
                        .padding(.vertical, 28)
                        .frame(minHeight: 88)
                        .background(
                            RoundedRectangle(cornerRadius: 22)
                                .fill(MCDesign.Colors.primary700)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Tap to begin the brain health check")
                .accessibilityHint("Starts the assessment")
                .padding(.bottom, 28)

                if hasInProgress {
                    Button {
                        onResume?()
                    } label: {
                        Label("Resume previous session", systemImage: "arrow.counterclockwise.circle.fill")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(MCDesign.Colors.primary700)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 16)
                            .frame(minHeight: 64)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Resume previous session")
                }

                Spacer()
            }
        }
        .onAppear {
            hasInProgress = AssessmentPersistence.hasInProgressAssessment()
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.easeOut(duration: 0.4).delay(0.1)) { appeared = true }
            }
        }
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

#Preview {
    HomeView(onSelectFlow: { _ in }, onResume: {}, onOpenClinicianDashboard: {})
}
