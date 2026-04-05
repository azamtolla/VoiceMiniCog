//
//  ContentView.swift
//  VoiceMiniCog
//
//  Main routing:
//  Home → QDRS → PHQ-2 → QmciIntro → Qmci Assessment (6 subtests) → Report
//

import SwiftUI

enum AppScreen {
    case home
    case qdrs            // QDRS questionnaire
    case phq2            // PHQ-2 depression gate
    case qmciIntro       // Brief intro before Qmci
    case qmciAssessment  // 6 Qmci subtests (on-device)
    case avatarAssessment // Avatar-guided assessment (Tavus CVI)
    case report          // PCP summary

    /// Maps a restored Phase + state to the correct AppScreen for navigation.
    /// During the intake phase, checks sub-state completion to determine exact screen.
    static func screen(for phase: Phase, state: AssessmentState? = nil) -> AppScreen {
        switch phase {
        case .intake:
            // Intake spans QDRS → PHQ-2 → QmciIntro. Use sub-state to pick up where left off.
            if let s = state {
                if s.phq2State.isComplete { return .qmciIntro }
                if s.qdrsState.isComplete || s.qdrsState.declined { return .phq2 }
            }
            return .qdrs
        case .qmciOrientation, .qmciRegistration, .qmciClockDrawing,
             .qmciVerbalFluency, .qmciLogicalMemory, .qmciDelayedRecall:
            return .qmciAssessment
        case .scoring:
            return .qmciAssessment
        case .report:
            return .report
        }
    }
}

struct ContentView: View {
    @AppStorage("minicog.useAvatarLiveView") var useAvatarLiveView = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var currentScreen: AppScreen = .home
    @State private var assessmentState = AssessmentState()
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            switch currentScreen {
            case .home:
                HomeView(
                    onStart: { respondentType in
                        AssessmentPersistence.clear()
                        assessmentState = AssessmentState()
                        assessmentState.qdrsState.respondentType = respondentType
                        assessmentState.qmciState.reset()
                        currentScreen = .qdrs
                    },
                    onResume: {
                        if let restored = AssessmentPersistence.restore() {
                            assessmentState = restored
                            currentScreen = AppScreen.screen(for: restored.currentPhase, state: restored)
                        }
                    }
                )

            case .qdrs:
                withCancelToolbar(
                    QDRSView(
                        qdrsState: assessmentState.qdrsState,
                        onComplete: {
                            currentScreen = .phq2
                            AssessmentPersistence.save(assessmentState)
                        },
                        onDecline: {
                            currentScreen = .phq2
                            AssessmentPersistence.save(assessmentState)
                        }
                    )
                )

            case .phq2:
                withCancelToolbar(
                    PHQ2View(
                        phq2State: $assessmentState.phq2State,
                        onComplete: {
                            currentScreen = .qmciIntro
                            AssessmentPersistence.save(assessmentState)
                        }
                    )
                )

            case .qmciIntro:
                withCancelToolbar(
                    QmciModePickerView(
                        onStandard: {
                            currentScreen = .qmciAssessment
                            AssessmentPersistence.save(assessmentState)
                        },
                        onAvatar: {
                            currentScreen = .avatarAssessment
                            AssessmentPersistence.save(assessmentState)
                        }
                    )
                )

            case .qmciAssessment:
                QmciAssessmentView(
                    state: assessmentState,
                    onComplete: {
                        // Scoring phase — compute all results
                        assessmentState.currentPhase = .scoring
                        computeAllScores()
                        assessmentState.currentPhase = .report
                        currentScreen = .report
                        AssessmentPersistence.clear()
                    },
                    onCancel: {
                        AssessmentPersistence.clear()
                        currentScreen = .home
                    }
                )

            case .avatarAssessment:
                AvatarAssessmentCanvas(
                    assessmentState: assessmentState,
                    conversationURL: TavusService.shared.activeConversation?.conversation_url,
                    onComplete: {
                        assessmentState.currentPhase = .scoring
                        computeAllScores()
                        assessmentState.currentPhase = .report
                        currentScreen = .report
                        AssessmentPersistence.clear()
                    },
                    onFallback: {
                        currentScreen = .qmciAssessment
                    },
                    onCancel: {
                        AssessmentPersistence.clear()
                        currentScreen = .home
                    }
                )

            case .report:
                PCPReportView(
                    state: assessmentState,
                    onRestart: {
                        assessmentState.reset()
                        AssessmentPersistence.clear()
                        currentScreen = .home
                    },
                    onFinalize: {
                        assessmentState.reset()
                        AssessmentPersistence.clear()
                        currentScreen = .home
                    }
                )
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background, currentScreen != .home {
                AssessmentPersistence.save(assessmentState)
            }
        }
    }

    private func computeAllScores() {
        // Composite risk
        assessmentState.compositeRisk = computeCompositeRiskQmciQDRS(
            qmciState: assessmentState.qmciState,
            qdrsState: assessmentState.qdrsState,
            phq2Score: assessmentState.phq2State.totalScore,
            clockAnalysis: assessmentState.clockAnalysis
        )

        // Anti-amyloid triage
        assessmentState.amyloidTriage = computeAmyloidTriage(
            qmciState: assessmentState.qmciState,
            qdrsState: assessmentState.qdrsState,
            medications: assessmentState.medicationFlags
        )

        // Workup orders
        assessmentState.workupOrders = generateWorkupOrders(
            qmciClassification: assessmentState.qmciState.classification,
            phq2Score: assessmentState.phq2State.totalScore,
            isFirstEvaluation: true
        )
    }

    private func withCancelToolbar<V: View>(_ view: V) -> some View {
        view
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        currentScreen = .home
                    }
                    .foregroundColor(MCDesign.Colors.error)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gear")
                            .foregroundColor(MCDesign.Colors.textSecondary)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                settingsSheet
            }
    }

    @State private var tavusAPIKey: String = UserDefaults.standard.string(forKey: "tavus_api_key") ?? ""
    @State private var tavusPersonaId: String = UserDefaults.standard.string(forKey: "tavus_persona_id") ?? "pc64945f7e08"
    @State private var tavusReplicaId: String = UserDefaults.standard.string(forKey: "tavus_replica_id") ?? "rf4e9d9790f0"

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section("Tavus Avatar") {
                    SecureField("API Key", text: $tavusAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 14, design: .monospaced))

                    TextField("Persona ID", text: $tavusPersonaId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 14, design: .monospaced))

                    TextField("Replica ID", text: $tavusReplicaId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 14, design: .monospaced))

                    Button("Save Tavus Settings") {
                        UserDefaults.standard.set(tavusAPIKey, forKey: "tavus_api_key")
                        UserDefaults.standard.set(tavusPersonaId, forKey: "tavus_persona_id")
                        UserDefaults.standard.set(tavusReplicaId, forKey: "tavus_replica_id")
                        showSettings = false
                    }
                    .foregroundColor(MCDesign.Colors.primary700)
                }

                Section("About") {
                    LabeledContent("App", value: "MercyCognitive")
                    LabeledContent("Version", value: "3.0")
                    LabeledContent("Assessment", value: "Qmci + QDRS + Tavus CVI")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showSettings = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    ContentView()
}
