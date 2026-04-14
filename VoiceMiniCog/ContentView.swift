//
//  ContentView.swift
//  VoiceMiniCog
//
//  Main routing: MA Handoff → Patient Home (Tap to Begin) → Avatar Assessment → Report.
//  Clinician Dashboard is a parallel path entered via a 5-tap chord on the
//  brain icon in Patient Home (passcode-gated).
//

import SwiftUI

enum AppScreen {
    case maHandoff
    case home
    case clinicianDashboard
    case avatarAssessment
    case caregiverAssessment
    case report
    case partialReport     // autonomous abandonment → partial PDF preview

    static func screen(for phase: Phase, state: AssessmentState? = nil) -> AppScreen {
        switch phase {
        case .intake, .qmciOrientation, .qmciRegistration, .qmciClockDrawing,
             .qmciVerbalFluency, .qmciLogicalMemory, .qmciDelayedRecall,
             .scoring:
            return .avatarAssessment
        case .report:
            return .report
        }
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    // Default to MA handoff on first launch so the nurse configures
    // patient + language BEFORE the iPad is handed to the patient. The
    // MA's "Hand iPad to Patient" tap flips to .home (Tap to Begin).
    @State private var currentScreen: AppScreen = .maHandoff
    @State private var flowType: AssessmentFlowType = .quick
    @State private var assessmentState = AssessmentState()
    @State private var showSettings = false
    @State private var sessionID = UUID()
    @State private var dailyCallManager = DailyCallManager()

    /// Observer handle for .sessionAbandoned so we can detach on disappear.
    @State private var abandonmentObserver: NSObjectProtocol?

    /// Currently-active phase (tracked so caregiver flags know which Phase
    /// to attribute). Updated by the assessment canvas via state mutations.
    private var activeClinicalPhase: Phase {
        assessmentState.currentPhase
    }

    var body: some View {
        ZStack {
            // MARK: Cognitive Assessment Canvas — ALWAYS in hierarchy.
            AvatarAssessmentCanvas(
                flowType: flowType,
                sessionID: sessionID,
                isActive: currentScreen == .avatarAssessment,
                dailyCallManager: dailyCallManager,
                assessmentState: assessmentState,
                tavusService: TavusService.shared,
                onComplete: {
                    assessmentState.currentPhase = .scoring
                    computeAllScores()
                    assessmentState.currentPhase = .report
                    AssessmentPersistence.clear()
                    dailyCallManager.leave()
                    TavusService.shared.cancelPreWarm()
                    Task { await TavusService.shared.endConversation() }
                    currentScreen = .report
                },
                onCancel: {
                    AssessmentPersistence.clear()
                    dailyCallManager.leave()
                    TavusService.shared.cancelPreWarm()
                    Task { await TavusService.shared.endConversation() }
                    currentScreen = .maHandoff
                }
            )
            .opacity(currentScreen == .avatarAssessment ? 1 : 0)
            .allowsHitTesting(currentScreen == .avatarAssessment)

            // MARK: Caregiver QDRS — separate view
            if currentScreen == .caregiverAssessment {
                CaregiverAssessmentView(
                    assessmentState: assessmentState,
                    tavusService: TavusService.shared,
                    onComplete: {
                        AssessmentPersistence.clear()
                        TavusService.shared.cancelPreWarm()
                        Task { await TavusService.shared.endConversation() }
                        currentScreen = .maHandoff
                    },
                    onCancel: {
                        AssessmentPersistence.clear()
                        TavusService.shared.cancelPreWarm()
                        Task { await TavusService.shared.endConversation() }
                        currentScreen = .maHandoff
                    }
                )
            }

            // MARK: MA Handoff (first screen each session)
            if currentScreen == .maHandoff {
                MAHandoffView(
                    flowType: $flowType,
                    onHandoffConfirmed: { patientID in
                        // Handoff timestamp already persisted by MAHandoffView.
                        // Patient-facing HomeView takes over until they tap.
                        currentScreen = .home
                    },
                    onCancel: {
                        currentScreen = .clinicianDashboard
                    }
                )
            }

            // MARK: Patient Home (single Tap to Begin)
            if currentScreen == .home {
                HomeView(
                    onSelectFlow: { selectedFlow in
                        startAssessment(flowType: selectedFlow)
                    },
                    onResume: {
                        if let restored = AssessmentPersistence.restore() {
                            assessmentState = restored
                            flowType = AssessmentPersistence.restoreFlowType()
                            sessionID = UUID()
                            if flowType == .caregiver {
                                currentScreen = .caregiverAssessment
                            } else {
                                currentScreen = AppScreen.screen(for: restored.currentPhase, state: restored)
                            }
                        }
                    },
                    onOpenClinicianDashboard: {
                        currentScreen = .clinicianDashboard
                    }
                )
                .onAppear { TavusService.shared.preWarm() }
            }

            // MARK: Clinician Dashboard (5-tap chord → PIN gate)
            if currentScreen == .clinicianDashboard {
                ClinicianDashboardView(
                    currentState: assessmentState,
                    flowType: $flowType,
                    onExit: {
                        currentScreen = .home
                    },
                    onExportPDF: { data in
                        presentSharedPDF(data: data)
                    },
                    onGoToMAHandoff: {
                        currentScreen = .maHandoff
                    }
                )
            }

            // MARK: Report (full)
            if currentScreen == .report {
                NavigationStack {
                    PCPReportView(
                        state: assessmentState,
                        onRestart: {
                            assessmentState.reset()
                            AssessmentPersistence.clear()
                            TavusService.shared.cancelPreWarm()
                            currentScreen = .maHandoff
                        },
                        onFinalize: {
                            assessmentState.qmciState.clinicianDecisionTimestamp = Date()
                            AssessmentPersistence.save(assessmentState, flowType: flowType)
                            assessmentState.reset()
                            AssessmentPersistence.clear()
                            TavusService.shared.cancelPreWarm()
                            currentScreen = .maHandoff
                        }
                    )
                }
            }

            // MARK: Partial Report (autonomous abandonment flow)
            if currentScreen == .partialReport {
                PartialReportPreview(
                    reason: AssessmentPersistence.shutdownReason ?? .unknown,
                    completed: AssessmentPersistence.completedSubtests,
                    abandonedAt: AssessmentPersistence.abandonedAt,
                    policy: AssessmentPersistence.partialScorePolicy,
                    onExport: {
                        let pdf = PartialScoreReport.generate(
                            state: assessmentState,
                            reason: AssessmentPersistence.shutdownReason ?? .unknown,
                            completed: AssessmentPersistence.completedSubtests,
                            policy: AssessmentPersistence.partialScorePolicy,
                            abandonedAt: AssessmentPersistence.abandonedAt
                        )
                        presentSharedPDF(data: pdf)
                    },
                    onDone: {
                        AssessmentPersistence.clear()
                        assessmentState.reset()
                        currentScreen = .maHandoff
                    }
                )
            }
        }
        .animation(.easeInOut(duration: 0.3), value: currentScreen)
        .onAppear(perform: registerAbandonmentObserver)
        .onDisappear {
            if let obs = abandonmentObserver {
                NotificationCenter.default.removeObserver(obs)
                abandonmentObserver = nil
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background, currentScreen != .home, currentScreen != .maHandoff {
                AssessmentPersistence.save(assessmentState, flowType: flowType)
            }
        }
    }

    // MARK: - Session abandonment listener

    private func registerAbandonmentObserver() {
        guard abandonmentObserver == nil else { return }
        abandonmentObserver = NotificationCenter.default.addObserver(
            forName: .sessionAbandoned,
            object: nil,
            queue: .main
        ) { [assessmentState] note in
            MainActor.assumeIsolated {
                let rawReason = note.userInfo?["reason"] as? String
                let reason = rawReason.flatMap(SessionShutdownReason.init(rawValue:)) ?? .unknown
                // Collect completed subtests from the current state.
                let completed = completedSubtests(from: assessmentState)
                AssessmentPersistence.recordAbandonment(
                    reason: reason,
                    completedSubtests: completed,
                    policy: .flagForClinicianReview
                )
                dailyCallManager.leave()
                TavusService.shared.cancelPreWarm()
                Task { await TavusService.shared.endConversation() }
                // Route to partial report if this was a partial session.
                if reason.isPartial {
                    currentScreen = .partialReport
                }
            }
        }
    }

    /// Which QMCI subtests have observable results in current state. Used to
    /// populate the partial-report "completed" list when the session aborts.
    private func completedSubtests(from state: AssessmentState) -> [Phase] {
        var out: [Phase] = []
        let q = state.qmciState
        if q.orientationScores.contains(where: { $0 != nil }) { out.append(.qmciOrientation) }
        if !q.registrationRecalledWords.isEmpty { out.append(.qmciRegistration) }
        if q.clockDrawingScore > 0 { out.append(.qmciClockDrawing) }
        if q.verbalFluencyScore > 0 { out.append(.qmciVerbalFluency) }
        if !q.logicalMemoryRecalledUnits.isEmpty { out.append(.qmciLogicalMemory) }
        if !q.delayedRecallWords.isEmpty { out.append(.qmciDelayedRecall) }
        return out
    }

    // MARK: - Start Assessment

    private func startAssessment(flowType selectedFlow: AssessmentFlowType) {
        AssessmentPersistence.clear()
        // Preserve MA-handoff audit fields — clear() wipes them by design.
        assessmentState = AssessmentState()
        flowType = selectedFlow
        sessionID = UUID()

        // Inject longitudinal patient context into the avatar at session
        // start (intro phase ONLY — never prior scores).
        if let patientID = AssessmentPersistence.lastHandoffPatientID,
           let header = LongitudinalPatientStore.shared.conversationContextHeader(for: patientID) {
            // Post as a pending context update; DailyCallManager will execute
            // it once the room joins.
            avatarSetContext(header)
        }

        if selectedFlow == .caregiver {
            assessmentState.qdrsState.respondentType = .informant
            currentScreen = .caregiverAssessment
        } else {
            currentScreen = .avatarAssessment
        }

        if TavusService.shared.activeConversation == nil, !TavusService.shared.isCreatingConversation {
            Task {
                do {
                    _ = try await TavusService.shared.createConversation(
                        conversationName: TavusService.defaultConversationName()
                    )
                } catch {
                    TavusService.shared.lastError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Scoring

    private func computeAllScores() {
        assessmentState.compositeRisk = computeCompositeRiskQmciQDRS(
            qmciState: assessmentState.qmciState,
            qdrsState: assessmentState.qdrsState,
            phq2Score: assessmentState.phq2State.totalScore,
            clockAnalysis: assessmentState.clockAnalysis
        )

        assessmentState.amyloidTriage = computeAmyloidTriage(
            qmciState: assessmentState.qmciState,
            qdrsState: assessmentState.qdrsState,
            medications: assessmentState.medicationFlags
        )

        assessmentState.workupOrders = generateWorkupOrders(
            qmciClassification: assessmentState.qmciState.classification,
            phq2Score: assessmentState.phq2State.totalScore,
            isFirstEvaluation: true
        )
    }

    // MARK: - PDF share

    private func presentSharedPDF(data: Data) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MercyCognitive-Report-\(Int(Date().timeIntervalSince1970)).pdf")
        try? data.write(to: url, options: .atomic)
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            activity.popoverPresentationController?.sourceView = root.view
            activity.popoverPresentationController?.sourceRect = CGRect(
                x: root.view.bounds.midX, y: root.view.bounds.midY, width: 0, height: 0
            )
            activity.popoverPresentationController?.permittedArrowDirections = []
            root.present(activity, animated: true)
        }
    }
}

// MARK: - Partial-report preview screen

private struct PartialReportPreview: View {
    let reason: SessionShutdownReason
    let completed: [Phase]
    let abandonedAt: Date?
    let policy: AssessmentPersistence.PartialScorePolicy
    let onExport: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Assessment Incomplete")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.red)

            Text("This session ended before all QMCI subtests completed. The result is NOT scorable against O'Caoimh 2012 norms. You may export a partial-session report for clinical reference only.")
                .font(.system(size: 16))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Reason: \(reason.rawValue.replacingOccurrences(of: "_", with: " "))")
                    .font(.system(size: 16, weight: .semibold))
                if let at = abandonedAt {
                    Text("Ended at: \(at.formatted(date: .abbreviated, time: .standard))")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                Text("Subtests completed: \(completed.count)")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.06)))

            HStack(spacing: 12) {
                Button {
                    onExport()
                } label: {
                    Label("Export Partial PDF", systemImage: "square.and.arrow.up")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    onDone()
                } label: {
                    Text("Done")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .padding(32)
    }
}

#Preview {
    ContentView()
}
