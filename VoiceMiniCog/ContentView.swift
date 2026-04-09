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
    case avatarAssessment // Avatar-guided assessment (Tavus CVI)
    case report          // PCP summary

    /// Maps a restored Phase + state to the correct AppScreen for navigation.
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
    @State private var assessmentState = AssessmentState()
    @State private var showSettings = false

    var body: some View {
        ZStack {
            // MARK: Avatar Canvas — ALWAYS in hierarchy so WebView stays connected.
            // While on Home, this is hidden (opacity 0) but the WKWebView is live:
            // bridge loaded, room joined, avatar streaming. When Start is pressed
            // we just flip visibility — instant avatar.
            AvatarAssessmentCanvas(
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

            // MARK: Home / Report — created and destroyed normally
            if currentScreen == .home {
                NavigationStack {
                    HomeView(
                        onStart: { respondentType in
                            AssessmentPersistence.clear()
                            assessmentState = AssessmentState()
                            assessmentState.qdrsState.respondentType = respondentType
                            assessmentState.qmciState.reset()
                            startAvatarAssessment()
                        },
                        onResume: {
                            if let restored = AssessmentPersistence.restore() {
                                assessmentState = restored
                                currentScreen = AppScreen.screen(for: restored.currentPhase, state: restored)
                            }
                        }
                    )
                }
                .onAppear {
                    TavusService.shared.preWarm()
                }
            }

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
                AssessmentPersistence.save(assessmentState)
            }
        }
    }

    private func startAvatarAssessment() {
        // Just reveal the canvas — the avatar is already streaming behind the Home screen.
        // If pre-warm failed or hasn't finished, the canvas shows its connecting/error UI.
        currentScreen = .avatarAssessment
        // Fallback: if pre-warm never ran or failed, start a fresh conversation
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
