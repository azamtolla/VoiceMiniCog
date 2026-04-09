//
//  ContentView.swift
//  VoiceMiniCog
//
//  Main routing: Home (three cards) → Avatar Assessment / Caregiver / Extended → Report
//

import SwiftUI

enum AppScreen {
    case home
    case avatarAssessment
    case caregiverAssessment
    case report

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
    @AppStorage("minicog.useAvatarLiveView") var useAvatarLiveView = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var currentScreen: AppScreen = .home
    @State private var flowType: AssessmentFlowType = .quick
    @State private var assessmentState = AssessmentState()
    @State private var showSettings = false
    @State private var sessionID = UUID()

    var body: some View {
        ZStack {
            // MARK: Cognitive Assessment Canvas — in hierarchy when not in caregiver mode
            // Only one TavusCVIView can hold the Daily WebRTC connection at a time.
            if currentScreen != .caregiverAssessment {
            AvatarAssessmentCanvas(
                flowType: flowType,
                assessmentState: assessmentState,
                tavusService: TavusService.shared,
                onComplete: {
                    assessmentState.currentPhase = .scoring
                    computeAllScores()
                    assessmentState.currentPhase = .report
                    currentScreen = .report
                    AssessmentPersistence.clear()
                },
                onCancel: {
                    AssessmentPersistence.clear()
                    TavusService.shared.cancelPreWarm()
                    currentScreen = .home
                }
            )
            .opacity(currentScreen == .avatarAssessment ? 1 : 0)
            .allowsHitTesting(currentScreen == .avatarAssessment)
            .id(sessionID) // Forces full recreation on new assessment start
            } // end if not caregiver

            // MARK: Caregiver QDRS — created on demand, shares pre-warmed conversation
            if currentScreen == .caregiverAssessment {
                CaregiverAssessmentView(
                    assessmentState: assessmentState,
                    tavusService: TavusService.shared,
                    onComplete: {
                        AssessmentPersistence.clear()
                        TavusService.shared.cancelPreWarm()
                        currentScreen = .home
                    },
                    onCancel: {
                        AssessmentPersistence.clear()
                        TavusService.shared.cancelPreWarm()
                        currentScreen = .home
                    }
                )
            }

            // MARK: Home
            if currentScreen == .home {
                NavigationStack {
                    HomeView(
                        onSelectFlow: { selectedFlow in
                            startAssessment(flowType: selectedFlow)
                        },
                        onResume: {
                            if let restored = AssessmentPersistence.restore() {
                                assessmentState = restored
                                flowType = AssessmentPersistence.restoreFlowType()
                                if flowType == .caregiver {
                                    currentScreen = .caregiverAssessment
                                } else {
                                    currentScreen = AppScreen.screen(for: restored.currentPhase, state: restored)
                                }
                            }
                        }
                    )
                }
                .onAppear {
                    TavusService.shared.preWarm()
                }
            }

            // MARK: Report
            if currentScreen == .report {
                NavigationStack {
                    PCPReportView(
                        state: assessmentState,
                        onRestart: {
                            assessmentState.reset()
                            AssessmentPersistence.clear()
                            TavusService.shared.cancelPreWarm()
                            currentScreen = .home
                        },
                        onFinalize: {
                            assessmentState.reset()
                            AssessmentPersistence.clear()
                            TavusService.shared.cancelPreWarm()
                            currentScreen = .home
                        }
                    )
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: currentScreen)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background, currentScreen != .home {
                AssessmentPersistence.save(assessmentState, flowType: flowType)
            }
        }
    }

    // MARK: - Start Assessment

    private func startAssessment(flowType selectedFlow: AssessmentFlowType) {
        AssessmentPersistence.clear()
        assessmentState = AssessmentState()
        assessmentState.qmciState.reset()
        flowType = selectedFlow
        sessionID = UUID()

        if selectedFlow == .caregiver {
            // Caregiver → dedicated QDRS view (no cognitive subtest shell)
            assessmentState.qdrsState.respondentType = .informant
            currentScreen = .caregiverAssessment
        } else {
            // Quick / Extended → shared cognitive assessment canvas
            currentScreen = .avatarAssessment
        }

        // Fallback: if pre-warm never ran or failed, start fresh conversation
        if TavusService.shared.activeConversation == nil && !TavusService.shared.isCreatingConversation {
            Task {
                do {
                    _ = try await TavusService.shared.createConversation(
                        conversationName: "MercyCog Assessment \(Date().formatted(date: .abbreviated, time: .shortened))"
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

    // MARK: - Settings

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
