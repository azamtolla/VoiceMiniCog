//
//  PhaseView.swift
//  VoiceMiniCog
//
//  Generic view for intro, word registration, and recall phases
//

import SwiftUI

struct PhaseView: View {
    var state: AssessmentState
    var speechService: SpeechService
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Prompt card
            VStack(spacing: 16) {
                Image(systemName: promptIcon)
                    .font(.system(size: 40))
                    .foregroundColor(.blue)

                Text(state.currentPrompt)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(Color.blue.opacity(0.05))
            .cornerRadius(16)
            .padding(.horizontal)

            // Listening indicator
            if speechService.isListening {
                VStack(spacing: 12) {
                    // Animated waveform
                    HStack(spacing: 4) {
                        ForEach(0..<5, id: \.self) { index in
                            WaveformBar(isActive: true, index: index, color: MercyColors.success)
                        }
                    }
                    .frame(height: 40)

                    Text("Listening...")
                        .font(.subheadline)
                        .foregroundColor(MercyColors.success)
                }
            }

            // Live transcript
            if !speechService.transcript.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("You said:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(speechService.transcript)
                        .font(.body)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                }
                .padding(.horizontal)
            }

            Spacer()

            // Next button
            Button(action: onNext) {
                HStack {
                    Text(nextButtonTitle)
                    Image(systemName: "arrow.right")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .cornerRadius(12)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)

            // Error message
            if let error = state.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.bottom, 8)
            }
        }
    }

    private var promptIcon: String {
        switch state.currentPhase {
        case .intro:
            return "hand.wave"
        case .wordRegistration:
            return "text.word.spacing"
        case .recall:
            return "brain"
        default:
            return "checkmark.circle"
        }
    }

    private var nextButtonTitle: String {
        switch state.currentPhase {
        case .intro:
            return "I'm Ready"
        case .wordRegistration:
            return "Continue"
        case .recall:
            return "Finish"
        default:
            return "Next"
        }
    }
}

#Preview {
    let state = AssessmentState()
    state.currentPrompt = "Hello! I'm going to walk you through a short memory exercise."

    let speechService = SpeechService()

    return PhaseView(state: state, speechService: speechService, onNext: {})
}
