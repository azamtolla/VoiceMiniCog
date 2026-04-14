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
    @Environment(\.scenePhase) private var scenePhase
    @State private var currentScreen: AppScreen = .home
    @State private var flowType: AssessmentFlowType = .quick
    @State private var assessmentState = AssessmentState()
    @State private var showSettings = false
    @State private var sessionID = UUID()

    var body: some View {
        ZStack {
            // MARK: Cognitive Assessment Canvas — ALWAYS in hierarchy so WebView stays connected.
            AvatarAssessmentCanvas(
                flowType: flowType,
                sessionID: sessionID,
                isActive: currentScreen == .avatarAssessment,
                warmTavusWebViewOnHome: currentScreen == .home,
                assessmentState: assessmentState,
                tavusService: TavusService.shared,
                onComplete: {
                    assessmentState.currentPhase = .scoring
                    computeAllScores()
                    assessmentState.currentPhase = .report
                    AssessmentPersistence.clear()
                    TavusService.shared.cancelPreWarm()
                    currentScreen = .report
                },
                onCancel: {
                    AssessmentPersistence.clear()
                    TavusService.shared.cancelPreWarm()
                    currentScreen = .home
                }
            )
            .opacity(currentScreen == .avatarAssessment ? 1 : 0)
            .allowsHitTesting(currentScreen == .avatarAssessment)

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
                                sessionID = UUID() // Fix #5: fresh session key for Daily
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
                            assessmentState.qmciState.clinicianDecisionTimestamp = Date()
                            AssessmentPersistence.save(assessmentState, flowType: flowType)
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
            // Fix #15: save only on .background (true "user left the app" signal).
            // .inactive fires on Control Center, incoming calls, Face ID — saving
            // mid-render could overwrite valid state with a partially-mutated copy.
            if newPhase == .background, currentScreen != .home {
                AssessmentPersistence.save(assessmentState, flowType: flowType)
            }
        }
    }

    // MARK: - Start Assessment

    private func startAssessment(flowType selectedFlow: AssessmentFlowType) {
        AssessmentPersistence.clear()
        assessmentState = AssessmentState()
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

        // Fallback: if pre-warm never ran or failed, start fresh conversation.
        // Guard also checks isCreatingConversation to avoid racing with an
        // in-flight preWarm Task.
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

    // MARK: - Settings

    @State private var tavusAPIKey: String = UserDefaults.standard.string(forKey: "tavus_api_key") ?? ""
    @State private var tavusPersonaId: String = UserDefaults.standard.string(forKey: "tavus_persona_id") ?? "pc64945f7e08"
    @State private var tavusReplicaId: String = UserDefaults.standard.string(forKey: "tavus_replica_id") ?? "rf4e9d9790f0"
    @State private var tavusVoiceIsolation: TavusVoiceIsolation =
        TavusVoiceIsolation(rawValue: UserDefaults.standard.string(forKey: "tavus_voice_isolation") ?? "near") ?? .near

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

                    Picker("Participant voice isolation", selection: $tavusVoiceIsolation) {
                        ForEach(TavusVoiceIsolation.allCases) { mode in
                            Text(mode.settingsLabel).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Button("Save Tavus Settings") {
                        UserDefaults.standard.set(tavusAPIKey, forKey: "tavus_api_key")
                        UserDefaults.standard.set(tavusPersonaId, forKey: "tavus_persona_id")
                        UserDefaults.standard.set(tavusReplicaId, forKey: "tavus_replica_id")
                        UserDefaults.standard.set(tavusVoiceIsolation.rawValue, forKey: "tavus_voice_isolation")
                        TavusService.shared.invalidateVoiceIsolationSyncCache()
                        // Cancel any pre-warmed conversation — it snapshotted the
                        // old persona settings. A fresh preWarm will run on the
                        // next home screen .onAppear with the updated persona.
                        TavusService.shared.cancelPreWarm()
                        Task {
                            await TavusService.shared.syncVoiceIsolationToPersonaIfNeeded(personaId: tavusPersonaId)
                        }
                        showSettings = false
                    }
                    .foregroundColor(MCDesign.Colors.primary700)
                }

                if TavusService.shared.voiceIsolationSyncFailed {
                    Section {
                        Label("Voice isolation failed to sync — background noise may interrupt the avatar. Try saving again or check the API key.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.footnote)
                    }
                }

                Section("About") {
                    LabeledContent("App", value: "MercyCognitive")
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
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
            .onAppear {
                // Fix #8: re-read ALL settings on sheet open, not just voice isolation.
                tavusAPIKey = UserDefaults.standard.string(forKey: "tavus_api_key") ?? ""
                tavusPersonaId = UserDefaults.standard.string(forKey: "tavus_persona_id") ?? "pc64945f7e08"
                tavusReplicaId = UserDefaults.standard.string(forKey: "tavus_replica_id") ?? "rf4e9d9790f0"
                let raw = UserDefaults.standard.string(forKey: "tavus_voice_isolation") ?? "near"
                tavusVoiceIsolation = TavusVoiceIsolation(rawValue: raw) ?? .near
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    ContentView()
}
