//
//  AssessmentView.swift
//  VoiceMiniCog
//
//  Main assessment flow with OpenAI Realtime integration
//

import SwiftUI

struct AssessmentView: View {
    @Binding var isActive: Bool

    @State private var state = AssessmentState()
    @State private var speechService = SpeechService()
    @State private var tts = ElevenLabsService()
    @State private var realtimeManager = RealtimeManager()
    @State private var showingCancelAlert = false
    @State private var showingSettings = false
    @State private var isProcessing = false
    @State private var detailedStage: String = "idle"

    // Realtime mode toggle - set to true to use OpenAI Realtime
    @State private var useRealtimeMode: Bool = true

    // Realtime transcript accumulator
    @State private var realtimeTranscript: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Phase stepper
            PhaseStepper(currentStage: detailedStage)
                .padding(.top, 8)

            // Main content based on stage
            Group {
                switch detailedStage {
                case "idle":
                    startView

                case "greeting", "register_words", "register_retry", "recall_prompt", "recall_followup", "ad8_intro", "ad8_questions":
                    conversationView

                case "words_complete":
                    wordsCompleteView

                case "clock_intro", "clock_drawing":
                    clockDrawingStage

                case "clock_scoring":
                    clockScoringView

                case "ad8_offer":
                    ad8OfferView

                case "physician_ready":
                    physicianReadyView

                case "complete":
                    ResultsView(state: state, onRestart: handleRestart, onFinalize: handleFinalize)

                default:
                    conversationView
                }
            }
        }
        .background(MercyColors.gray50)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    showingCancelAlert = true
                }
                .foregroundColor(.red)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gear")
                        .foregroundColor(MercyColors.gray600)
                }
            }
        }
        .alert("Cancel Assessment?", isPresented: $showingCancelAlert) {
            Button("Continue", role: .cancel) {}
            Button("Cancel", role: .destructive) {
                cleanup()
                isActive = false
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsSheet(tts: tts, useRealtime: $useRealtimeMode)
        }
    }

    // MARK: - Start View

    private var startView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Brain icon
            ZStack {
                Circle()
                    .fill(MercyColors.mercyBlue.opacity(0.15))
                    .frame(width: 100, height: 100)

                Image(systemName: "brain.head.profile")
                    .font(.system(size: 44))
                    .foregroundColor(MercyColors.mercyBlue)
            }

            Text("Mini-Cog Assessment")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(MercyColors.gray800)

            Text("Voice-guided cognitive screening")
                .font(.system(size: 16))
                .foregroundColor(MercyColors.gray500)

            // Realtime mode indicator
            if useRealtimeMode {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 12))
                    Text("OpenAI Realtime")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(Color(hex: "#10B981"))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(hex: "#10B981").opacity(0.1))
                .cornerRadius(16)
            }

            // AD8 Respondent toggle
            VStack(spacing: 8) {
                Text("Is an informant (family/caregiver) available?")
                    .font(.system(size: 13))
                    .foregroundColor(MercyColors.gray500)

                HStack(spacing: 12) {
                    Button(action: { state.ad8State.respondentType = .informant }) {
                        Text("Yes — Informant")
                            .font(.system(size: 14, weight: .medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(state.ad8State.respondentType == .informant ? MercyColors.mercyBlue : Color.white)
                            .foregroundColor(state.ad8State.respondentType == .informant ? .white : MercyColors.gray600)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(MercyColors.gray300, lineWidth: state.ad8State.respondentType == .informant ? 0 : 1)
                            )
                    }

                    Button(action: { state.ad8State.respondentType = .selfReport }) {
                        Text("No — Self Report")
                            .font(.system(size: 14, weight: .medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(state.ad8State.respondentType == .selfReport ? MercyColors.mercyBlue : Color.white)
                            .foregroundColor(state.ad8State.respondentType == .selfReport ? .white : MercyColors.gray600)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(MercyColors.gray300, lineWidth: state.ad8State.respondentType == .selfReport ? 0 : 1)
                            )
                    }
                }

                Text(state.ad8State.respondentType == .informant
                     ? "AD8 will be completed separately. Mini-Cog only (~3-5 min)."
                     : "Includes AD8 voice questions after Mini-Cog (~5-8 min).")
                    .font(.system(size: 12))
                    .foregroundColor(MercyColors.gray400)
            }
            .padding(.top, 8)

            Spacer()

            // Start Button
            Button(action: startAssessment) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 16))
                    Text("Start Assessment")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(MercyColors.mercyBlue)
                .cornerRadius(12)
            }
            .padding(.horizontal, 40)

            Spacer().frame(height: 60)
        }
        .background(Color.white)
    }

    // MARK: - Conversation View (matching React layout)

    private var conversationView: some View {
        VStack(spacing: 0) {
            // Status bar
            statusBar

            // Content
            ScrollView {
                VStack(spacing: 16) {
                    statusCard

                    // Show transcript based on mode
                    if useRealtimeMode {
                        if !realtimeTranscript.isEmpty || realtimeManager.isUserSpeaking {
                            realtimeTranscriptCard
                        }
                    } else {
                        if !speechService.transcript.isEmpty || speechService.isListening {
                            legacyTranscriptCard
                        }
                    }
                }
                .padding(16)
            }
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 12) {
            WaveformView(
                isActive: isVoiceActive,
                color: isListeningState ? Color(hex: "#22c55e") : MercyColors.mercyBlue
            )
            .frame(width: 40, height: 28)

            Text(statusLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(MercyColors.mercyBlue)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(MercyColors.mercyBlue.opacity(0.15))
                .cornerRadius(12)

            // Connection indicator for realtime mode
            if useRealtimeMode {
                connectionIndicator
            }

            if isProcessing {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(MercyColors.mercyBlue)
            }

            Spacer()

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(MercyColors.mercyBlue.opacity(0.15))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(MercyColors.mercyBlue)
                        .frame(width: geo.size.width * (progress / 100))
                }
            }
            .frame(width: 100, height: 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(MercyColors.mercyBlue.opacity(0.08))
        .overlay(
            Rectangle()
                .fill(MercyColors.mercyBlue)
                .frame(width: 3),
            alignment: .leading
        )
        .cornerRadius(8)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var connectionIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(connectionColor)
                .frame(width: 6, height: 6)
            Text(connectionLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(connectionColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(connectionColor.opacity(0.1))
        .cornerRadius(8)
    }

    private var connectionColor: Color {
        switch realtimeManager.connectionState {
        case .connected: return Color(hex: "#10B981")
        case .connecting, .reconnecting: return Color(hex: "#F59E0B")
        case .disconnected: return MercyColors.gray400
        case .failed: return Color(hex: "#EF4444")
        }
    }

    private var connectionLabel: String {
        switch realtimeManager.connectionState {
        case .connected: return "Live"
        case .connecting: return "Connecting..."
        case .reconnecting: return "Reconnecting..."
        case .disconnected: return "Offline"
        case .failed: return "Failed"
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        VStack(spacing: 0) {
            // Card content
            VStack(alignment: .leading, spacing: 16) {
                // Assistant speech bubble
                if !state.currentPrompt.isEmpty {
                    HStack(alignment: .top, spacing: 0) {
                        Text(state.currentPrompt)
                            .font(.system(size: 15))
                            .foregroundColor(MercyColors.gray800)
                            .lineSpacing(4)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(MercyColors.gray50)
                            .cornerRadius(4, corners: [.topLeft])
                            .cornerRadius(16, corners: [.topRight, .bottomLeft, .bottomRight])
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(MercyColors.gray200, lineWidth: 1)
                            )

                        Spacer()
                    }
                }
            }
            .padding(16)

            // Controls at bottom
            HStack(spacing: 16) {
                // Tap to Speak button (legacy mode)
                if !useRealtimeMode && state.waitingForTapToSpeak {
                    Button(action: handleTapToSpeak) {
                        HStack(spacing: 8) {
                            Image(systemName: "mic.fill")
                            Text("Tap to Speak")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color(hex: "#22c55e"))
                        .cornerRadius(8)
                    }
                }

                // Listening indicator
                if isListeningState {
                    HStack(spacing: 6) {
                        Image(systemName: "mic.fill")
                            .foregroundColor(Color(hex: "#22c55e"))
                        Text(useRealtimeMode ? "Listening (Realtime)..." : "Listening...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(hex: "#22c55e"))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(hex: "#22c55e").opacity(0.1))
                    .cornerRadius(16)
                }

                // Speaking indicator (realtime mode)
                if useRealtimeMode && realtimeManager.isAssistantSpeaking {
                    HStack(spacing: 6) {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundColor(MercyColors.mercyBlue)
                        Text("Speaking...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(MercyColors.mercyBlue)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(MercyColors.mercyBlue.opacity(0.1))
                    .cornerRadius(16)
                }
            }
            .padding(16)
        }
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(MercyColors.gray200, lineWidth: 1)
        )
    }

    // MARK: - Transcript Cards

    private var realtimeTranscriptCard: some View {
        HStack {
            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(realtimeTranscript.isEmpty ? "..." : realtimeTranscript)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(MercyColors.gray800)
                    .lineSpacing(4)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(MercyColors.mercyBlue.opacity(0.12))
                    .cornerRadius(16, corners: [.topLeft, .topRight, .bottomLeft])
                    .cornerRadius(4, corners: [.bottomRight])
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(MercyColors.mercyBlue.opacity(0.3), lineWidth: 1)
                    )

                Text(Date().formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundColor(MercyColors.gray400)
            }
        }
    }

    private var legacyTranscriptCard: some View {
        HStack {
            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(speechService.transcript.isEmpty ? "..." : speechService.transcript)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(MercyColors.gray800)
                    .lineSpacing(4)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(MercyColors.mercyBlue.opacity(0.12))
                    .cornerRadius(16, corners: [.topLeft, .topRight, .bottomLeft])
                    .cornerRadius(4, corners: [.bottomRight])
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(MercyColors.mercyBlue.opacity(0.3), lineWidth: 1)
                    )

                Text(Date().formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundColor(MercyColors.gray400)
            }
        }
    }

    // MARK: - Words Complete View

    private var wordsCompleteView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(MercyColors.success)

            Text("Ready for Clock Drawing")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(MercyColors.gray800)

            Text("The patient will be asked to draw a clock face with all numbers and set the hands to ten past eleven.")
                .font(.system(size: 16))
                .foregroundColor(MercyColors.gray600)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            Button(action: startClockDrawing) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("Continue to Clock Drawing")
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(MercyColors.mercyBlue)
                .cornerRadius(12)
            }
            .padding(.horizontal, 40)
            .disabled(tts.isSpeaking || realtimeManager.isAssistantSpeaking)

            Spacer().frame(height: 60)
        }
        .background(Color.white)
    }

    // MARK: - Clock Drawing Stage

    private var clockDrawingStage: some View {
        VStack(spacing: 0) {
            statusBar

            ClockDrawingView(state: state, onComplete: handleClockComplete)
                .padding()
        }
    }

    // MARK: - Clock Scoring View

    private var clockScoringView: some View {
        ClockScoringView(
            state: state,
            onScore: handleClockScore
        )
    }

    // MARK: - AD8 Offer View

    private var ad8OfferView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "list.clipboard.fill")
                .font(.system(size: 64))
                .foregroundColor(Color(hex: "#ea580c"))

            Text("Optional Memory Questions")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(MercyColors.gray800)

            Text("Would you like to answer 8 brief questions about everyday memory and thinking? This is optional and helps provide a more complete picture.")
                .font(.system(size: 16))
                .foregroundColor(MercyColors.gray600)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            HStack(spacing: 16) {
                Button(action: handleAD8Skip) {
                    Text("Skip")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(MercyColors.gray600)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.white)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(MercyColors.gray300, lineWidth: 1)
                        )
                }

                Button(action: handleAD8Continue) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                        Text("Continue")
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(MercyColors.mercyBlue)
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal, 40)
            .disabled(tts.isSpeaking || realtimeManager.isAssistantSpeaking)

            Spacer().frame(height: 60)
        }
        .background(Color.white)
    }

    // MARK: - Physician Ready View

    private var physicianReadyView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(MercyColors.success)

            Text("Assessment Complete")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(MercyColors.gray800)

            Text("Thank you for completing the Mini-Cog assessment. The results are ready for physician review.")
                .font(.system(size: 16))
                .foregroundColor(MercyColors.gray600)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            Button(action: { detailedStage = "complete" }) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.fill")
                    Text("For Physician Evaluation")
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(MercyColors.mercyBlue)
                .cornerRadius(12)
            }
            .padding(.horizontal, 40)

            Spacer().frame(height: 60)
        }
        .background(Color.white)
    }

    // MARK: - Computed Properties

    private var isVoiceActive: Bool {
        if useRealtimeMode {
            return realtimeManager.isAssistantSpeaking || realtimeManager.isUserSpeaking
        } else {
            return tts.isSpeaking || speechService.isListening
        }
    }

    private var isListeningState: Bool {
        if useRealtimeMode {
            return realtimeManager.isUserSpeaking || (realtimeManager.connectionState == .connected && !realtimeManager.isAssistantSpeaking)
        } else {
            return speechService.isListening && !state.waitingForTapToSpeak
        }
    }

    private var statusLabel: String {
        if useRealtimeMode {
            if realtimeManager.isAssistantSpeaking {
                return "Speaking..."
            } else if realtimeManager.isUserSpeaking {
                return "Listening..."
            } else if realtimeManager.connectionState == .connecting {
                return "Connecting..."
            } else if realtimeManager.connectionState == .connected {
                return phaseLabel
            } else {
                return phaseLabel
            }
        } else {
            switch state.assistantState {
            case .speaking: return "Speaking..."
            case .listening: return "Listening..."
            case .processing: return "Processing..."
            case .thinking: return "Thinking..."
            case .complete: return "Complete"
            default: return phaseLabel
            }
        }
    }

    private var phaseLabel: String {
        switch detailedStage {
        case "greeting": return "Introduction"
        case "register_words", "register_retry": return "Word Registration"
        case "words_complete": return "Ready"
        case "clock_intro", "clock_drawing": return "Clock Drawing"
        case "clock_scoring": return "Clock Evaluation"
        case "recall_prompt", "recall_followup": return "Word Recall"
        case "ad8_intro": return "AD8 Intro"
        case "ad8_questions": return "AD8 Q\(state.ad8State.currentQuestion + 1)/8"
        case "ad8_offer": return "AD8 Offer"
        case "physician_ready", "complete": return "Complete"
        default: return "Ready"
        }
    }

    private var progress: Double {
        let stages = ["idle", "greeting", "register_words", "words_complete", "clock_drawing", "recall_prompt", "ad8_questions", "complete"]
        if let idx = stages.firstIndex(of: detailedStage) {
            return Double(idx + 1) / Double(stages.count) * 100
        }
        return 0
    }

    // MARK: - Actions

    private func startAssessment() {
        Task {
            if useRealtimeMode {
                await runRealtimeAssessment()
            } else {
                await runLegacyAssessment()
            }
        }
    }

    // MARK: - Realtime Assessment Flow

    private func runRealtimeAssessment() async {
        // Start realtime session
        await realtimeManager.startSession()

        guard realtimeManager.connectionState == .connected else {
            // Fall back to legacy mode if realtime fails
            state.errorMessage = realtimeManager.errorMessage
            print("[Assessment] Realtime connection failed, falling back to legacy mode")
            useRealtimeMode = false
            await runLegacyAssessment()
            return
        }

        // Configure session with Mini-Cog instructions
        let instructions = """
        You are conducting a Mini-Cog cognitive assessment. Your role is to:
        1. Greet the patient warmly and explain you'll do a short memory exercise
        2. Say three words clearly and slowly: \(state.words.joined(separator: ", "))
        3. Ask the patient to repeat the words
        4. After they repeat, tell them you'll ask for the words again later
        5. Say "Great, now we're going to do something different" to transition to clock drawing

        Be patient, speak slowly, and be encouraging. Keep responses brief.
        When the patient is ready to continue, just proceed naturally.
        """
        realtimeManager.updateSessionConfig(instructions: instructions)

        // Start greeting phase
        detailedStage = "greeting"
        state.currentPhase = .intro
        state.currentPrompt = "Hello! I'm going to walk you through a short memory exercise."

        // Send initial instruction to start conversation
        realtimeManager.sendInstructionText("Please greet the patient and begin the Mini-Cog assessment. Introduce yourself and say you'll do a short memory exercise.")

        // Wait for greeting phase to complete
        // In full implementation, this would be event-driven based on RealtimeManager delegate
        try? await Task.sleep(nanoseconds: 8_000_000_000) // 8 seconds for greeting

        // Transition to word registration
        detailedStage = "register_words"
        state.currentPhase = .wordRegistration
        state.currentPrompt = "I'm going to say three words. Please remember them."

        realtimeManager.sendInstructionText("Now say the three words clearly and slowly, then ask the patient to repeat them.")

        // Wait for registration
        try? await Task.sleep(nanoseconds: 15_000_000_000) // 15 seconds

        // Transition to clock drawing
        detailedStage = "words_complete"
    }

    // MARK: - Legacy Assessment Flow

    private func runLegacyAssessment() async {
        // Request speech authorization
        _ = await speechService.requestAuthorization()

        // Run greeting phase
        await runGreeting()

        // Run word registration
        if detailedStage != "idle" {
            await runWordRegistration()
        }
    }

    private func runGreeting() async {
        detailedStage = "greeting"
        state.assistantState = .speaking

        let prompt = state.getPromptForPhase(.intro)
        state.currentPrompt = prompt
        state.addMessage(role: .assistant, content: prompt)

        await tts.speak(prompt)

        // Listen for response
        state.assistantState = .listening
        await listenWithTimeout(timeoutKey: "greeting", checker: isGreetingComplete)

        state.assistantState = .idle
    }

    private func runWordRegistration() async {
        detailedStage = "register_words"
        state.currentPhase = .wordRegistration
        state.registrationAttempt = 1
        state.addMessage(role: .system, content: "Word Registration Phase")

        // Speak word intro
        let intro = state.getWordIntroPrompt()
        state.currentPrompt = intro
        state.addMessage(role: .assistant, content: intro)
        state.assistantState = .speaking
        await tts.speak(intro)

        // Ask for repetition
        let repeatPrompt = state.getRepeatPrompt()
        state.currentPrompt = repeatPrompt
        state.addMessage(role: .assistant, content: repeatPrompt)
        await tts.speak(repeatPrompt)

        // Listen
        state.assistantState = .listening
        let wordChecker = makeWordRegistrationChecker(wordList: state.words)
        let transcript = await listenWithTimeout(timeoutKey: "register_words", checker: wordChecker)

        // Score
        let result = scoreWordRecall(transcript: transcript, wordList: state.words)
        state.registrationResults.append(result.count)
        state.wordRegistrationScore = result.count

        // Retry loop
        var attempt = 1
        var currentScore = result.count

        while attempt < 3 && currentScore < 3 {
            attempt += 1
            state.registrationAttempt = attempt
            detailedStage = "register_retry"

            let retryPrompt = state.getRetryPrompt(attempt: attempt, lastScore: currentScore)
            state.currentPrompt = retryPrompt
            state.addMessage(role: .assistant, content: retryPrompt)
            state.assistantState = .speaking
            await tts.speak(retryPrompt)

            state.assistantState = .listening
            let retryTranscript = await listenWithTimeout(timeoutKey: "register_retry", checker: wordChecker)

            let retryResult = scoreWordRecall(transcript: retryTranscript, wordList: state.words)
            state.registrationResults.append(retryResult.count)
            if retryResult.count > currentScore {
                currentScore = retryResult.count
                state.wordRegistrationScore = currentScore
            }
        }

        // Transition
        let transition = state.getTransitionToClockPrompt()
        state.addMessage(role: .assistant, content: transition)
        state.assistantState = .speaking
        await tts.speak(transition)

        state.assistantState = .idle
        detailedStage = "words_complete"
    }

    private func startClockDrawing() {
        Task {
            detailedStage = "clock_intro"
            state.currentPhase = .clockDrawing
            state.addMessage(role: .system, content: "Clock Drawing Phase")

            let instructions = state.getClockInstructionsPrompt()
            state.currentPrompt = instructions
            state.addMessage(role: .assistant, content: instructions)

            if useRealtimeMode {
                realtimeManager.sendInstructionText("Tell the patient to draw a clock with all the numbers and set the hands to ten past eleven.")
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            } else {
                state.assistantState = .speaking
                await tts.speak(instructions)
                state.assistantState = .idle
            }

            detailedStage = "clock_drawing"
        }
    }

    private func handleClockComplete(image: UIImage, timeSec: Int) {
        Task {
            state.clockImage = image
            state.clockTimeSec = timeSec

            // Convert to base64
            if let data = image.pngData() {
                state.clockImageBase64 = data.base64EncodedString()
            }

            state.addMessage(role: .system, content: "Clock drawing completed in \(timeSec)s")

            // Thank you
            let thanks = state.getThankYouPrompt()
            state.addMessage(role: .assistant, content: thanks)

            if useRealtimeMode {
                realtimeManager.sendInstructionText("Say 'Thank you, nice job' to the patient.")
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            } else {
                state.assistantState = .speaking
                await tts.speak(thanks)
            }

            // Score with on-device CDT AI model
            var aiScore: Int = 1  // Default to moderate if AI fails
            if CDTOnDeviceScorer.shared.isReady {
                do {
                    let result = try await CDTOnDeviceScorer.shared.scoreClockDrawing(image: image)
                    aiScore = result.aiClass
                    state.addMessage(role: .system, content: "AI Clock Score: \(result.severity) (confidence: \(Int(result.confidence * 100))%)")
                    print("[CDT] On-device AI scored clock: \(result.aiClass) - \(result.severity)")
                } catch {
                    print("[CDT] On-device scoring failed: \(error)")
                    // Fallback to API if on-device fails
                    do {
                        let response = try await APIClient.shared.scoreClockDrawing(image: image)
                        aiScore = response.ai_class
                        state.addMessage(role: .system, content: "AI Clock Score: \(response.severity) (confidence: \(Int(response.confidence * 100))%)")
                        print("[CDT] API scored clock: \(response.ai_class) - \(response.severity)")
                    } catch {
                        print("[CDT] API scoring also failed: \(error)")
                        state.addMessage(role: .system, content: "AI scoring unavailable - using default")
                    }
                }
            } else {
                // On-device model not loaded, try API
                do {
                    let response = try await APIClient.shared.scoreClockDrawing(image: image)
                    aiScore = response.ai_class
                    state.addMessage(role: .system, content: "AI Clock Score: \(response.severity) (confidence: \(Int(response.confidence * 100))%)")
                    print("[CDT] API scored clock: \(response.ai_class) - \(response.severity)")
                } catch {
                    print("[CDT] API scoring failed: \(error)")
                    state.addMessage(role: .system, content: "AI scoring unavailable - using default")
                }
            }

            state.clockScore = aiScore
            state.clockScoreSource = .ai

            // Go to recall
            await runRecallPhase()
        }
    }

    private func handleClockScore(score: Int, source: ClockScoreSource) {
        state.clockScore = score
        state.clockScoreSource = source

        Task {
            await runRecallPhase()
        }
    }

    private func runRecallPhase() async {
        detailedStage = "recall_prompt"
        state.currentPhase = .recall
        state.addMessage(role: .system, content: "Word Recall Phase")

        let recallPrompt = "Now, what were those three words I asked you to remember earlier?"
        state.currentPrompt = recallPrompt
        state.addMessage(role: .assistant, content: recallPrompt)

        if useRealtimeMode {
            realtimeManager.sendInstructionText("Ask the patient: 'Now, what were those three words I asked you to remember earlier?' Listen for their response and be encouraging.")
            try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds for recall
            // TODO: Parse transcript from realtime events
        } else {
            state.assistantState = .speaking
            await tts.speak(recallPrompt)

            // Listen
            state.assistantState = .listening
            let recallChecker = makeRecallChecker(wordList: state.words)
            var transcript = await listenWithTimeout(timeoutKey: "recall_prompt", checker: recallChecker)

            var recallResult = scoreWordRecall(transcript: transcript, wordList: state.words)

            // Follow-up if needed
            if recallResult.count < 3 {
                detailedStage = "recall_followup"

                let followup = state.getRecallFollowupPrompt(count: recallResult.count)
                state.currentPrompt = followup
                state.addMessage(role: .assistant, content: followup)
                state.assistantState = .speaking
                await tts.speak(followup)

                state.assistantState = .listening
                let moreTranscript = await listenWithTimeout(timeoutKey: "recall_followup", checker: recallChecker)

                if !moreTranscript.isEmpty {
                    let combined = transcript + " " + moreTranscript
                    let newResult = scoreWordRecall(transcript: combined, wordList: state.words)
                    if newResult.count > recallResult.count {
                        recallResult = newResult
                    }
                }
            }

            state.recallScore = recallResult.count
            state.recalledWords = recallResult.recalled
        }

        state.assistantState = .idle

        // Offer AD8 if self-report
        if state.ad8State.respondentType == .selfReport {
            let offer = state.getAD8OfferPrompt()
            state.addMessage(role: .assistant, content: offer)

            if useRealtimeMode {
                realtimeManager.sendInstructionText("Ask if they'd like to answer a few brief optional questions about everyday memory.")
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            } else {
                state.assistantState = .speaking
                await tts.speak(offer)
                state.assistantState = .idle
            }

            detailedStage = "ad8_offer"
        } else {
            await completeAssessment()
        }
    }

    private func handleAD8Continue() {
        Task {
            await runAD8()
            await completeAssessment()
        }
    }

    private func handleAD8Skip() {
        state.ad8State.declined = true
        state.addMessage(role: .system, content: "AD8 declined")
        Task {
            await completeAssessment()
        }
    }

    private func runAD8() async {
        detailedStage = "ad8_intro"
        state.addMessage(role: .system, content: "AD8 Screening Phase")

        // Intro
        let intro = state.getAD8IntroPrompt()
        state.currentPrompt = intro
        state.addMessage(role: .assistant, content: intro)
        state.assistantState = .speaking
        await tts.speak(intro)

        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // Questions
        detailedStage = "ad8_questions"
        let acknowledgments = ["Okay.", "Got it.", "Alright.", "Thanks."]

        for i in 0..<AD8_QUESTIONS.count {
            state.ad8State.currentQuestion = i

            let question = AD8_QUESTIONS[i]
            state.currentPrompt = question
            state.addMessage(role: .assistant, content: question)
            state.assistantState = .speaking
            await tts.speak(question)

            // Listen
            state.assistantState = .listening
            let transcript = await listenWithTimeoutMs(timeoutMs: AD8_LISTEN_TIMEOUT, checker: isAD8ResponseComplete)

            let interpretation = interpretAD8Response(transcript)

            var finalAnswer: AD8Answer
            switch interpretation {
            case .yes: finalAnswer = .yes
            case .no: finalAnswer = .no
            default: finalAnswer = .na
            }

            state.ad8State.answers[i] = finalAnswer

            // Acknowledge
            if i < AD8_QUESTIONS.count - 1 {
                let ack = acknowledgments[i % acknowledgments.count]
                state.addMessage(role: .assistant, content: ack)
                state.assistantState = .speaking
                await tts.speak(ack)
            }
        }

        // Compute score
        state.ad8State.computeScore()

        // Closing
        let closing = "Okay, that's everything for this section. Thank you."
        state.addMessage(role: .assistant, content: closing)
        state.assistantState = .speaking
        await tts.speak(closing)

        state.assistantState = .idle
    }

    private func completeAssessment() async {
        // Stop realtime session if active
        if useRealtimeMode && realtimeManager.connectionState == .connected {
            realtimeManager.sendInstructionText("Thank the patient for completing the assessment and say we're all done.")
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            realtimeManager.stopSession()
        } else {
            // Thank you
            let thankYou = state.getFinalThankYouPrompt()
            state.addMessage(role: .assistant, content: thankYou)
            state.assistantState = .speaking
            await tts.speak(thankYou)
        }

        // Set clinician defaults
        state.clinicianClockScore = state.clockScore
        state.screenInterpretation = state.isPositiveScreen ? .positive : .negative

        // Compute composite risk
        state.computeCompositeRiskIfNeeded()

        state.assistantState = .complete
        detailedStage = "physician_ready"
    }

    private func handleTapToSpeak() {
        state.waitingForTapToSpeak = false
        state.canAutoListen = true
    }

    private func handleRestart() {
        cleanup()
        state.reset()
        realtimeTranscript = ""
        detailedStage = "idle"
    }

    private func handleFinalize() {
        let _ = state.buildResult()
        #if DEBUG
        print("[Assessment] Assessment finalized")
        #endif
        isActive = false
    }

    private func cleanup() {
        speechService.stopListening()
        tts.stop()
        if realtimeManager.connectionState == .connected {
            realtimeManager.stopSession()
        }
    }

    // MARK: - Listen Helpers

    private func listenWithTimeout(timeoutKey: String, checker: @escaping (String) -> Bool) async -> String {
        let timeoutMs = LISTEN_TIMEOUTS[timeoutKey] ?? LISTEN_TIMEOUTS["default"]!
        return await listenWithTimeoutMs(timeoutMs: timeoutMs, checker: checker)
    }

    private func listenWithTimeoutMs(timeoutMs: Int, checker: @escaping (String) -> Bool) async -> String {
        // Small delay for audio session transition
        try? await Task.sleep(nanoseconds: 300_000_000)

        speechService.transcript = ""

        do {
            try await speechService.startListening()
            try await Task.sleep(nanoseconds: UInt64(timeoutMs) * 1_000_000)
        } catch {
            print("[Assessment] Listening error: \(error)")
        }

        speechService.stopListening()

        let transcript = speechService.transcript
        state.transcript = transcript
        if !transcript.isEmpty {
            state.addMessage(role: .patient, content: transcript)
        }

        return transcript
    }
}

// MARK: - Phase Stepper

struct PhaseStepper: View {
    let currentStage: String

    private var currentPhaseKey: String {
        switch currentStage {
        case "idle", "greeting": return "greeting"
        case "register_words", "register_retry", "words_complete": return "registration"
        case "clock_intro", "clock_drawing", "clock_scoring": return "clock"
        case "recall_prompt", "recall_followup": return "recall"
        case "ad8_offer", "ad8_intro", "ad8_questions", "ad8_complete": return "ad8"
        case "physician_ready", "complete": return "results"
        default: return "greeting"
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(PHASE_META.enumerated()), id: \.element.key) { index, phase in
                let currentIdx = PHASE_META.firstIndex { $0.key == currentPhaseKey } ?? 0
                let isActive = index == currentIdx
                let isDone = index < currentIdx

                HStack(spacing: 4) {
                    // Circle indicator
                    ZStack {
                        Circle()
                            .fill(isDone ? MercyColors.success : (isActive ? phase.color : MercyColors.gray200))
                            .frame(width: 32, height: 32)
                            .scaleEffect(isActive ? 1.1 : 1.0)

                        if isDone {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                        } else {
                            Image(systemName: phase.iconName)
                                .font(.system(size: 14))
                                .foregroundColor(isActive ? .white : MercyColors.gray400)
                        }
                    }

                    // Label (only for active)
                    if isActive {
                        Text(phase.label)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(phase.color)
                            .lineLimit(1)
                    }
                }

                // Connector line
                if index < PHASE_META.count - 1 {
                    Rectangle()
                        .fill(isDone ? MercyColors.success : MercyColors.gray200)
                        .frame(height: 2)
                        .frame(maxWidth: 30)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Waveform View

struct WaveformView: View {
    let isActive: Bool
    let color: Color
    var barCount: Int = 5

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                WaveformBar(isActive: isActive, index: index, color: color)
            }
        }
    }
}

struct WaveformBar: View {
    let isActive: Bool
    let index: Int
    let color: Color

    @State private var scale: CGFloat = 0.3

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: 3.5, height: 28)
            .scaleEffect(y: scale, anchor: .center)
            .opacity(isActive ? 1 : 0.25)
            .animation(
                isActive
                    ? Animation.easeInOut(duration: 0.9)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.12)
                    : .default,
                value: scale
            )
            .onAppear {
                if isActive {
                    scale = 1.0
                }
            }
            .onChange(of: isActive) { _, active in
                scale = active ? 1.0 : 0.3
            }
    }
}

// MARK: - Settings Sheet

struct SettingsSheet: View {
    var tts: ElevenLabsService
    @Binding var useRealtime: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Use OpenAI Realtime", isOn: $useRealtime)
                } header: {
                    Text("Voice Mode")
                } footer: {
                    Text(useRealtime
                         ? "Low-latency bidirectional voice conversation powered by OpenAI Realtime."
                         : "Traditional mode using ElevenLabs TTS and Apple Speech Recognition.")
                }

                if !useRealtime {
                    Section {
                        SecureField("API Key", text: $apiKey)
                            .autocapitalization(.none)
                            .textContentType(.password)
                    } header: {
                        Text("ElevenLabs")
                    } footer: {
                        Text("Enter your ElevenLabs API key for high-quality voice. Without it, the app uses system TTS.")
                    }

                    Section {
                        Text("Voice: Sarah (calm, professional)")
                            .foregroundColor(MercyColors.gray500)
                        Text("Model: eleven_turbo_v2_5")
                            .foregroundColor(MercyColors.gray500)
                    } header: {
                        Text("Voice Settings")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        tts.setAPIKey(apiKey)
                        dismiss()
                    }
                }
            }
            .onAppear {
                apiKey = tts.apiKey
            }
        }
    }
}

#Preview {
    NavigationStack {
        AssessmentView(isActive: .constant(true))
    }
}
