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
    case avatarAssessment // Avatar-guided assessment (PersonaPlex)
    case report          // PCP summary
}

struct ContentView: View {
    @State private var currentScreen: AppScreen = .home
    @State private var assessmentState = AssessmentState()
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            switch currentScreen {
            case .home:
                HomeView(onStart: { respondentType in
                    assessmentState = AssessmentState()
                    assessmentState.qdrsState.respondentType = respondentType
                    assessmentState.qmciState.reset()
                    currentScreen = .qdrs
                })

            case .qdrs:
                withCancelToolbar(
                    QDRSView(
                        qdrsState: assessmentState.qdrsState,
                        onComplete: {
                            currentScreen = .phq2
                        },
                        onDecline: {
                            currentScreen = .phq2
                        }
                    )
                )

            case .phq2:
                withCancelToolbar(
                    PHQ2View(
                        phq2State: $assessmentState.phq2State,
                        onComplete: {
                            currentScreen = .qmciIntro
                        }
                    )
                )

            case .qmciIntro:
                withCancelToolbar(
                    QmciModePickerView(
                        onStandard: { currentScreen = .qmciAssessment },
                        onAvatar: { currentScreen = .avatarAssessment }
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
                    },
                    onCancel: {
                        currentScreen = .home
                    }
                )

            case .avatarAssessment:
                // Avatar path — requires Tavus files (added on avatar-tavus branch)
                Text("Avatar mode not available on this branch")
                    .onAppear { currentScreen = .qmciAssessment }

            case .report:
                PCPReportView(
                    state: assessmentState,
                    onRestart: {
                        assessmentState.reset()
                        currentScreen = .home
                    },
                    onFinalize: {
                        assessmentState.reset()
                        currentScreen = .home
                    }
                )
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

    @State private var avatarURLText: String = UserDefaults.standard.string(forKey: "avatar_gateway_url") ?? "wss://3fy931d4vpried-8080.proxy.runpod.net/avatar"

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section("Avatar Gateway") {
                    TextField("wss://pod.proxy.runpod.net/avatar", text: $avatarURLText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 14, design: .monospaced))

                    Button("Save & Apply") {
                        UserDefaults.standard.set(avatarURLText, forKey: "avatar_gateway_url")
                        showSettings = false
                    }
                    .foregroundColor(MCDesign.Colors.primary700)
                }

                Section("About") {
                    LabeledContent("App", value: "MercyCognitive")
                    LabeledContent("Version", value: "2.0")
                    LabeledContent("Assessment", value: "Qmci + QDRS")
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
