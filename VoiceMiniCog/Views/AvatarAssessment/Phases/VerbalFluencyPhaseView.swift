//
//  VerbalFluencyPhaseView.swift
//  VoiceMiniCog
//
//  Phase 7 — Verbal Fluency (EXPANDED). 60-second animal naming task with
//  live word counter, animated progress bar, word chips, and manual entry.
//  Avatar at 30% width, 0.4 opacity. QmciState stores verbalFluencyWords.
//

import SwiftUI

// MARK: - VerbalFluencyPhaseView

struct VerbalFluencyPhaseView: View {

    // MARK: Properties

    let layoutManager: AvatarLayoutManager
    @Bindable var qmciState: QmciState

    @State private var timeRemaining = 60
    @State private var isRunning = false
    @State private var timer: Timer?
    @State private var wordsEntered: [String] = []
    @State private var currentWord = ""

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            if isRunning {
                activeView
            } else {
                preStartView
            }
        }
        .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
        .onDisappear {
            stopTimer()
            qmciState.verbalFluencyWords = wordsEntered
        }
    }

    // MARK: - Pre-Start View

    private var preStartView: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .foregroundStyle(layoutManager.accentColor)
                .padding(.bottom, 14)

            Text("Name as many animals\nas you can")
                .font(AssessmentTheme.Fonts.question)
                .foregroundStyle(AssessmentTheme.Content.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)

            Text("You have one minute.")
                .font(AssessmentTheme.Fonts.helper)
                .foregroundStyle(AssessmentTheme.Content.textSecondary)
                .padding(.bottom, 32)

            Button {
                let gen = UIImpactFeedbackGenerator(style: .medium)
                gen.impactOccurred()
                startTimer()
            } label: {
                Text("Start Timer")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 200, height: 56)
                    .background(layoutManager.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    // MARK: - Active View

    private var activeView: some View {
        VStack(spacing: 16) {

            // MARK: Counter Section
            VStack(spacing: 8) {

                // Big word count number
                Text("\(wordsEntered.count)")
                    .font(AssessmentTheme.Fonts.counterHero)
                    .foregroundStyle(layoutManager.accentColor)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: wordsEntered.count)

                Text("animals")
                    .font(AssessmentTheme.Fonts.helper)
                    .foregroundStyle(AssessmentTheme.Content.textSecondary)

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color.gray.opacity(0.15))
                            .frame(height: 4)

                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(layoutManager.accentColor)
                            .frame(
                                width: geo.size.width * CGFloat(60 - timeRemaining) / 60.0,
                                height: 4
                            )
                            .animation(.linear(duration: 1), value: timeRemaining)
                    }
                }
                .frame(height: 4)

                // Timer display
                Text("0:\(String(format: "%02d", timeRemaining))")
                    .font(AssessmentTheme.Fonts.timerSmall)
                    .foregroundStyle(timeRemaining <= 10 ? Color.red : AssessmentTheme.Content.textSecondary)
                    .animation(.easeInOut(duration: 0.2), value: timeRemaining <= 10)
            }
            .padding(.top, 8)

            // MARK: Word Chips
            ScrollView {
                FlowLayout(spacing: 6) {
                    ForEach(wordsEntered, id: \.self) { word in
                        Text(word)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AssessmentTheme.Content.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(layoutManager.accentColor.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: .infinity)

            // MARK: Word Entry
            HStack(spacing: 8) {
                TextField("Add animal...", text: $currentWord)
                    .font(.system(size: 16))
                    .frame(height: 44)
                    .padding(.horizontal, 12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .onSubmit { addWord() }

                Button {
                    addWord()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(layoutManager.accentColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 16)
        }
    }

    // MARK: - Add Word

    private func addWord() {
        let word = currentWord.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !word.isEmpty, !wordsEntered.contains(word) else { return }
        withAnimation(AssessmentTheme.Anim.chipAppear) { wordsEntered.append(word) }
        currentWord = ""
    }

    // MARK: - Timer Control

    private func startTimer() {
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if timeRemaining > 0 {
                timeRemaining -= 1
            } else {
                stopTimer()
                qmciState.verbalFluencyWords = wordsEntered
                layoutManager.advanceToNextPhase()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Preview

#Preview("Pre-Start") {
    VerbalFluencyPhaseView(
        layoutManager: AvatarLayoutManager(),
        qmciState: QmciState()
    )
    .background(AssessmentTheme.Content.background)
}

#Preview("Active") {
    let layout = AvatarLayoutManager()
    layout.transitionTo(.verbalFluency)
    let state = QmciState()
    return VerbalFluencyPhaseView(
        layoutManager: layout,
        qmciState: state
    )
    .background(AssessmentTheme.Content.background)
}
