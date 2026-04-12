//
//  AvatarAssessmentCanvas.swift
//  VoiceMiniCog
//
//  Root view for the avatar-guided assessment.
//  ONE unified canvas: content zone (left) + avatar zone (right).
//  Layout ratios are driven by AvatarLayoutManager per phase.
//

import SwiftUI

// MARK: - AvatarAssessmentCanvas

struct AvatarAssessmentCanvas: View {

    @Bindable var assessmentState: AssessmentState
    var conversationURL: String?
    let onComplete: () -> Void
    let onFallback: () -> Void
    let onCancel: () -> Void

    @State private var layoutManager = AvatarLayoutManager()
    @State private var showPauseSheet = false
    @State private var tavusService = TavusService.shared
    @State private var activeConversationURL: String?
    @State private var isLoadingAvatar = true
    @State private var avatarError: String?
    @State private var avatarCoordinator: TavusCVIView.Coordinator?

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            let avatarWidth  = geo.size.width * layoutManager.avatarWidthRatio
            let contentWidth = geo.size.width - avatarWidth

            ZStack {
                // MARK: Layer 1 — Unified background gradient
                // Light #F8F9FA on left → dark #080808 on right,
                // gradient stop animated with avatarWidthRatio.
                LinearGradient(
                    stops: layoutManager.currentPhase == .clockDrawing
                        ? [
                            .init(color: Color(hex: "#F8F9FA"), location: 0.0),
                            .init(color: Color(hex: "#F8F9FA"), location: 1.0)
                        ]
                        : [
                            .init(color: Color(hex: "#F8F9FA"), location: 0.0),
                            .init(
                                color: Color(hex: "#F8F9FA"),
                                location: 1.0 - layoutManager.avatarWidthRatio
                            ),
                            .init(color: Color(hex: "#080808"), location: 1.0)
                        ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .ignoresSafeArea()
                .animation(AssessmentTheme.Anim.phaseTransition, value: layoutManager.avatarWidthRatio)
                .animation(AssessmentTheme.Anim.phaseTransition, value: layoutManager.currentPhase)

                // MARK: Layer 2 — Content + Avatar HStack
                HStack(spacing: 0) {

                    // MARK: Content Zone (left)
                    contentZone
                        .frame(width: contentWidth)

                    // MARK: Avatar Zone (right)
                    avatarZone(width: avatarWidth, height: geo.size.height)
                }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .animation(AssessmentTheme.Anim.phaseTransition, value: layoutManager.currentPhase)
        .pauseSheet(
            isPresented: $showPauseSheet,
            accentColor: layoutManager.accentColor,
            onCancel: onCancel
        )
    }

    // MARK: - Content Zone

    @ViewBuilder
    private var contentZone: some View {
        VStack(spacing: 0) {
            // Progress track — 60pt top padding for safe area
            progressTrackPlaceholder
                .padding(.top, 60)

            // Phase-specific content
            Group {
                phaseContent
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    .id(layoutManager.currentPhase)
                    .animation(AssessmentTheme.Anim.phaseTransition, value: layoutManager.currentPhase)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Pause button
            pauseButton
        }
        .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
        .padding(.bottom, 24)
    }

    // MARK: - Phase Content Switch

    @ViewBuilder
    private var phaseContent: some View {
        switch layoutManager.currentPhase {
        case .welcome:
            WelcomePhaseView(layoutManager: layoutManager, onGoToMainMenu: onFallback)
        case .qdrs:
            QAPhaseView(layoutManager: layoutManager, assessmentState: assessmentState, phaseID: .qdrs)
        case .phq2:
            QAPhaseView(layoutManager: layoutManager, assessmentState: assessmentState, phaseID: .phq2)
        case .orientation:
            QAPhaseView(layoutManager: layoutManager, assessmentState: assessmentState, phaseID: .orientation)
        case .wordRegistration:
            WordRegistrationPhaseView(layoutManager: layoutManager, qmciState: assessmentState.qmciState)
        case .clockDrawing:
            ClockDrawingPhaseView(layoutManager: layoutManager, assessmentState: assessmentState)
        case .verbalFluency:
            VerbalFluencyPhaseView(layoutManager: layoutManager, qmciState: assessmentState.qmciState)
        case .storyRecall:
            StoryRecallPhaseView(layoutManager: layoutManager, qmciState: assessmentState.qmciState)
        case .wordRecall:
            WordRecallPhaseView(layoutManager: layoutManager, qmciState: assessmentState.qmciState)
        }
    }

    // MARK: - Progress Track

    private var progressTrackPlaceholder: some View {
        ProgressTrackView(layoutManager: layoutManager)
    }

    // MARK: - Pause Button

    private var pauseButton: some View {
        PauseButtonView {
            showPauseSheet = true
        }
    }

    // MARK: - Avatar Zone

    @ViewBuilder
    private func avatarZone(width: CGFloat, height: CGFloat) -> some View {
        AvatarZoneView(
            layoutManager: layoutManager,
            conversationURL: activeConversationURL ?? conversationURL,
            isLoading: isLoadingAvatar,
            errorMessage: avatarError,
            onAvatarEvent: handleAvatarEvent,
            width: width,
            height: height,
            onDoneDrawing: {
                layoutManager.advanceToNextPhase()
            },
            onEndSession: onCancel
        )
        .frame(width: width, height: height)
        .onAppear {
            if activeConversationURL == nil && conversationURL == nil {
                createConversation()
            } else if let url = conversationURL {
                activeConversationURL = url
                isLoadingAvatar = false
            }
        }
        .onDisappear {
            Task { await tavusService.endConversation() }
        }
        .onChange(of: layoutManager.currentPhase) { _, newPhase in
            sendPhaseContext(newPhase)
        }
    }

    // MARK: - Tavus Conversation

    private func createConversation() {
        isLoadingAvatar = true
        avatarError = nil
        print("[AvatarCanvas] Creating Tavus conversation...")

        Task {
            do {
                let session = try await tavusService.createConversation(
                    conversationName: "MercyCognitive — \(Date().formatted(date: .abbreviated, time: .shortened))"
                )
                print("[AvatarCanvas] Conversation created: \(session.conversation_url)")
                await MainActor.run {
                    activeConversationURL = session.conversation_url
                    isLoadingAvatar = false
                }
            } catch {
                print("[AvatarCanvas] Failed to create conversation: \(error)")
                await MainActor.run {
                    avatarError = error.localizedDescription
                    isLoadingAvatar = false
                }
            }
        }
    }

    // MARK: - Avatar Event Handling

    private func handleAvatarEvent(_ event: TavusAvatarEvent) {
        switch event {
        case .joined:
            print("[AvatarCanvas] Avatar joined — sending welcome context")
            layoutManager.avatarBehavior = .speaking
            sendPhaseContext(layoutManager.currentPhase)

        case .replicaStartedSpeaking:
            layoutManager.avatarBehavior = .speaking

        case .replicaStoppedSpeaking:
            layoutManager.avatarBehavior = .listening

        case .userStartedSpeaking:
            layoutManager.avatarBehavior = .listening

        case .userStoppedSpeaking:
            layoutManager.avatarBehavior = .idle

        case .left:
            layoutManager.avatarBehavior = .idle

        case .error(let msg):
            print("[AvatarCanvas] Avatar error: \(msg)")
            avatarError = msg
        }
    }

    // MARK: - Phase Context Updates

    /// Sends context to the avatar describing what phase is active and what it should do
    private func sendPhaseContext(_ phase: AssessmentPhaseID) {
        // Find the TavusCVIView coordinator to send JS messages
        // We post via notification since we can't hold a direct reference to UIViewRepresentable coordinator
        let context = phaseContextString(for: phase)
        print("[AvatarCanvas] Sending phase context: \(phase)")
        NotificationCenter.default.post(
            name: .tavusContextUpdate,
            object: nil,
            userInfo: ["context": context]
        )
    }


    private func phaseContextString(for phase: AssessmentPhaseID) -> String {
        switch phase {
        case .welcome:
            return "PHASE: WELCOME. The patient sees an overview of the 6 activities on the left side of the screen. There is a 'Begin Assessment' button. Wait for them to press it or say they are ready. Do NOT start the assessment yet."

        case .qdrs:
            return "PHASE: QDRS. The left pane now shows the Quick Dementia Rating System questionnaire. The patient/informant will select answers on the iPad. You should read each QDRS question aloud and wait for them to tap their answer. After they select, say 'Got it, thank you' and move to the next question. There are 10 questions total."

        case .phq2:
            return "PHASE: PHQ-2. Transition: 'Now I have two quick questions about how you have been feeling lately.' Read each PHQ-2 question and wait for the patient to select their answer on the iPad."

        case .orientation:
            return "PHASE: ORIENTATION. Transition: 'Great, let us start with some simple questions.' Ask these 5 questions ONE at a time, waiting for a verbal response: 1) What year is it? 2) What month are we in? 3) What day of the week? 4) What is today's date? 5) What country are we in? Say 'Thank you' after each. NEVER say correct or incorrect."

        case .wordRegistration:
            return "PHASE: WORD REGISTRATION. Say: 'Now I am going to say five words. Listen carefully and repeat them back.' Then say clearly with pauses: 'butter... arm... shore... letter... queen.' Ask them to repeat. If they miss words, repeat ONCE more. Then say: 'Try to remember those five words, I will ask again later.'"

        case .clockDrawing:
            return "PHASE: CLOCK DRAWING. The left pane shows a drawing canvas. Say: 'Now I would like you to draw a clock on the iPad screen. Please draw a large circle for a clock face, put in all the numbers, then set the hands to show ten minutes after eleven — 11:10.' Then WAIT QUIETLY while they draw. Do not rush or comment. When they finish, say 'Thank you, that looks great.'"

        case .verbalFluency:
            return "PHASE: VERBAL FLUENCY. Say: 'For this next exercise, name as many animals as you can think of. Any kind — pets, farm animals, birds, fish — anything counts. You will have one minute. Ready? Go ahead.' Then stay QUIET for 60 seconds. Only if they stop for more than 10 seconds say 'Keep going, any animal you can think of.' At the end: 'Time is up. You did well, thank you.'"

        case .storyRecall:
            return "PHASE: STORY RECALL. Say: 'Now I am going to read you a short story. Listen carefully because I will ask you to tell me what you remember.' Then read this story EXACTLY: 'Anna Thompson of South Boston, employed as a cook in a school cafeteria, reported at the police station that she had been held up on State Street the night before and robbed of fifty-six dollars. She had four small children, the rent was due, and they had not eaten for two days. The police, touched by the woman's story, took up a collection for her.' Then say: 'Now tell me everything you remember from that story.' Listen. Ask 'Anything else?' once. Then: 'Thank you.'"

        case .wordRecall:
            return "PHASE: WORD RECALL. Say: 'Earlier I asked you to remember five words. Can you tell me those words now?' Wait for them to recall. Do NOT give hints, first letters, or categories. If they say they cannot remember more: 'That is perfectly fine. Thank you. That completes our brain health check. Thank you for your time and effort. Your doctor will review the results.'"
        }
    }

}

// MARK: - Notification for context updates
// Notification.Name extensions for tavusContextUpdate and tavusEchoRequest
// are defined in TavusCVIView.swift — no duplicate declaration here.

// MARK: - Pause Sheet View Modifier

private struct PauseSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    let accentColor: Color
    let onCancel: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                VStack(spacing: 24) {
                    Text("Assessment Paused")
                        .font(.system(size: 22, weight: .bold))
                    Text("The patient can take a break.")
                        .font(.system(size: 16))
                        .foregroundColor(AssessmentTheme.Content.textSecondary)
                    Button("Resume Assessment") { isPresented = false }
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(accentColor)
                        .cornerRadius(14)
                    Button("End Session") {
                        isPresented = false
                        onCancel()
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color(hex: "#DC2626"))
                }
                .padding(32)
                .presentationDetents([.medium])
            }
    }
}

private extension View {
    func pauseSheet(
        isPresented: Binding<Bool>,
        accentColor: Color,
        onCancel: @escaping () -> Void
    ) -> some View {
        modifier(PauseSheetModifier(
            isPresented: isPresented,
            accentColor: accentColor,
            onCancel: onCancel
        ))
    }
}

// MARK: - Preview

#Preview {
    AvatarAssessmentCanvas(
        assessmentState: AssessmentState(),
        conversationURL: nil,
        onComplete: {},
        onFallback: {},
        onCancel: {}
    )
}
