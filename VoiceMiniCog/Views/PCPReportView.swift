//
//  PCPReportView.swift
//  VoiceMiniCog
//
//  PCP Summary Report — one-page structured output with:
//  traffic-light risk, anti-amyloid eligibility, cognitive profile,
//  order set, referral recommendation, billing codes.
//

import SwiftUI

struct PCPReportView: View {
    @Bindable var state: AssessmentState
    let onRestart: () -> Void
    let onFinalize: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 1. Risk Banner
                riskBanner

                // 2. Anti-Amyloid Eligibility
                if let triage = state.amyloidTriage {
                    amyloidSection(triage)
                }

                // 3. Cognitive Profile (Qmci)
                qmciProfileSection

                // 4. QDRS Summary
                if state.qdrsState.answeredCount > 0 {
                    qdrsSection
                }

                // 5. Clock Drawing
                if state.clockImage != nil {
                    clockSection
                }

                // 6. Depression Screen
                if state.phq2State.isComplete {
                    phq2Section
                }

                // 7. Recommended Orders
                ordersSection

                // 8. Questions to Ask
                questionsSection

                // 9. Billing Codes
                billingSection

                // Actions
                actionButtons

                Spacer().frame(height: 32)
            }
            .padding(20)
        }
        .background(MCDesign.Colors.surfaceInset)
        .onAppear { computeResults() }
    }

    // MARK: - Risk Banner

    private var riskBanner: some View {
        let risk = state.compositeRisk
        let color: Color = risk?.tier == .low ? MCDesign.Colors.success :
                           risk?.tier == .intermediate ? MCDesign.Colors.warning : MCDesign.Colors.error
        let icon = risk?.tier == .low ? "checkmark.shield.fill" :
                   risk?.tier == .intermediate ? "exclamationmark.triangle.fill" : "xmark.shield.fill"

        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundColor(color)

                VStack(alignment: .leading, spacing: 4) {
                    Text(risk?.label ?? "Scoring...")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(color)
                    Text(risk?.summaryLine ?? "")
                        .font(.system(size: 14))
                        .foregroundColor(MCDesign.Colors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let narrative = risk?.narrative, !narrative.isEmpty {
                Text(narrative)
                    .font(.system(size: 14))
                    .foregroundColor(MCDesign.Colors.textPrimary)
                    .italic()
            }
        }
        .padding(18)
        .background(Color.white)
        .cornerRadius(14)
        .overlay(
            Rectangle()
                .fill(color)
                .frame(width: 6),
            alignment: .leading
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    // MARK: - Anti-Amyloid

    private func amyloidSection(_ triage: AmyloidTriageResult) -> some View {
        let color: Color = triage.eligibility == .candidate ? MCDesign.Colors.primary700 :
                           triage.eligibility == .notEligible ? MCDesign.Colors.textSecondary : MCDesign.Colors.warning

        return reportCard(title: "Anti-Amyloid Therapy Eligibility", icon: "pills.fill", accentColor: color) {
            VStack(alignment: .leading, spacing: 12) {
                // Status
                Text(triage.eligibility.rawValue)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(color)

                // Checklist
                ForEach(triage.checklist) { item in
                    HStack(spacing: 10) {
                        checklistIcon(item.status)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.label)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(MCDesign.Colors.textPrimary)
                            Text(item.detail)
                                .font(.system(size: 12))
                                .foregroundColor(MCDesign.Colors.textSecondary)
                        }
                    }
                }

                // Next steps
                if !triage.nextSteps.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Next Steps")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(MCDesign.Colors.textSecondary)
                        ForEach(triage.nextSteps, id: \.self) { step in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•").foregroundColor(MCDesign.Colors.textTertiary)
                                Text(step)
                                    .font(.system(size: 13))
                                    .foregroundColor(MCDesign.Colors.textPrimary)
                            }
                        }
                    }
                    .padding(12)
                    .background(MCDesign.Colors.surfaceInset)
                    .cornerRadius(8)
                }
            }
        }
    }

    private func checklistIcon(_ status: ChecklistStatus) -> some View {
        Group {
            switch status {
            case .met:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(MCDesign.Colors.success)
            case .notMet:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(MCDesign.Colors.error)
            case .needsReview:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(MCDesign.Colors.warning)
            case .notAssessed:
                Image(systemName: "minus.circle")
                    .foregroundColor(MCDesign.Colors.border)
            }
        }
        .font(.system(size: 16))
    }

    // MARK: - Qmci Profile

    private var qmciProfileSection: some View {
        let q = state.qmciState

        return reportCard(title: "Cognitive Profile (Qmci)", icon: "brain", accentColor: MCDesign.Colors.primary700) {
            VStack(spacing: 14) {
                // Total score
                HStack {
                    Text("\(q.totalScore)")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(scoreColor(q.classification))
                    Text("/ 100")
                        .font(.system(size: 18))
                        .foregroundColor(MCDesign.Colors.textTertiary)
                    Spacer()
                    Text(q.classification.rawValue)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(scoreColor(q.classification))
                        .cornerRadius(8)
                }

                // Subtest bars
                ForEach(QmciSubtest.allCases, id: \.rawValue) { subtest in
                    let score = subtestScore(subtest, state: q)
                    let max = subtest.maxScore

                    HStack(spacing: 10) {
                        Image(systemName: subtest.iconName)
                            .font(.system(size: 12))
                            .foregroundColor(MCDesign.Colors.textTertiary)
                            .frame(width: 20)

                        Text(subtest.displayName)
                            .font(.system(size: 13))
                            .foregroundColor(MCDesign.Colors.textPrimary)
                            .frame(width: 100, alignment: .leading)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(MCDesign.Colors.background)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(MCDesign.Colors.primary700)
                                    .frame(width: max > 0 ? geo.size.width * CGFloat(score) / CGFloat(max) : 0)
                            }
                        }
                        .frame(height: 8)

                        Text("\(score)/\(max)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(MCDesign.Colors.textSecondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
        }
    }

    // MARK: - QDRS

    private var qdrsSection: some View {
        reportCard(title: "QDRS Patient-Reported", icon: "list.clipboard", accentColor: Color(hex: "#ea580c")) {
            HStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text(String(format: "%.1f", state.qdrsState.totalScore))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(state.qdrsState.riskColor)
                    Text("/ 10")
                        .font(.system(size: 13))
                        .foregroundColor(MCDesign.Colors.textTertiary)
                    Text(state.qdrsState.riskLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(state.qdrsState.riskColor)
                }

                if !state.qdrsState.flaggedDomains.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Flagged Domains")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(MCDesign.Colors.textSecondary)
                        ForEach(state.qdrsState.flaggedDomains, id: \.self) { domain in
                            Text("• \(domain)")
                                .font(.system(size: 13))
                                .foregroundColor(MCDesign.Colors.textPrimary)
                        }
                    }
                }
                Spacer()
            }
        }
    }

    // MARK: - Clock

    private var clockSection: some View {
        reportCard(title: "Clock Drawing", icon: "clock.fill", accentColor: MCDesign.Colors.clockAccent) {
            HStack(spacing: 16) {
                if let img = state.clockImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(MCDesign.Colors.border, lineWidth: 1)
                        )
                }

                VStack(alignment: .leading, spacing: 6) {
                    if let score = state.clockScore {
                        Text("AI Score: \(score)/2")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(MCDesign.Colors.textPrimary)
                    }
                    if let analysis = state.clockAnalysis {
                        Text(analysis.severity)
                            .font(.system(size: 13))
                            .foregroundColor(MCDesign.Colors.textSecondary)
                        Text("Shulman \(analysis.shulmanRange)")
                            .font(.system(size: 12))
                            .foregroundColor(MCDesign.Colors.textSecondary)
                    }
                }
                Spacer()
            }
        }
    }

    // MARK: - PHQ-2

    private var phq2Section: some View {
        let score = state.phq2State.totalScore
        let positive = state.phq2State.isPositive

        return reportCard(title: "Depression Screen (PHQ-2)", icon: "heart.text.square.fill",
                          accentColor: positive ? MCDesign.Colors.warning : MCDesign.Colors.success) {
            HStack {
                Text("\(score)/6")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(positive ? MCDesign.Colors.warning : MCDesign.Colors.success)

                Text(positive ? "Positive — Order PHQ-9" : "Negative")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(positive ? MCDesign.Colors.warning : MCDesign.Colors.success)

                Spacer()
            }
        }
    }

    // MARK: - Orders

    private var ordersSection: some View {
        reportCard(title: "Recommended Orders", icon: "list.bullet.clipboard.fill", accentColor: MCDesign.Colors.primary700) {
            VStack(alignment: .leading, spacing: 8) {
                if state.workupOrders.isEmpty {
                    Text("No orders generated. Run scoring first.")
                        .font(.system(size: 13))
                        .foregroundColor(MCDesign.Colors.textTertiary)
                } else {
                    ForEach(state.workupOrders) { order in
                        HStack(spacing: 10) {
                            Image(systemName: order.isSelected ? "checkmark.square.fill" : "square")
                                .font(.system(size: 16))
                                .foregroundColor(order.isSelected ? MCDesign.Colors.primary700 : MCDesign.Colors.border)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(order.name)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(MCDesign.Colors.textPrimary)
                                Text(order.rationale)
                                    .font(.system(size: 11))
                                    .foregroundColor(MCDesign.Colors.textSecondary)
                            }

                            Spacer()

                            priorityBadge(order.priority)
                        }
                    }
                }
            }
        }
    }

    private func priorityBadge(_ priority: OrderPriority) -> some View {
        let label: String
        let color: Color
        switch priority {
        case .required: label = "Required"; color = MCDesign.Colors.error
        case .recommended: label = "Rec'd"; color = MCDesign.Colors.warning
        case .optional: label = "Optional"; color = MCDesign.Colors.textTertiary
        }
        return Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.1))
            .cornerRadius(4)
    }

    // MARK: - Questions

    private var questionsSection: some View {
        let questions = [
            "Have you or your family noticed any changes in your ability to manage finances?",
            "Have you had any falls in the past year?",
            "Are you still driving? Any close calls?",
            "Do you ever forget to take your medications?",
            "Is there a family member who could come to a follow-up visit?",
        ]

        return reportCard(title: "Questions to Ask the Patient", icon: "questionmark.bubble.fill", accentColor: Color(hex: "#6366F1")) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(questions, id: \.self) { q in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(hex: "#6366F1"))
                            .padding(.top, 3)
                        Text(q)
                            .font(.system(size: 14))
                            .foregroundColor(MCDesign.Colors.textPrimary)
                    }
                }
            }
        }
    }

    // MARK: - Billing

    private var billingSection: some View {
        reportCard(title: "Billing & ICD-10", icon: "dollarsign.circle.fill", accentColor: MCDesign.Colors.textSecondary) {
            VStack(alignment: .leading, spacing: 8) {
                if state.qmciState.classification.isPositive {
                    codeBadge(code: "99483", label: "Cognitive Assessment & Care Plan (positive screen)")
                }
                codeBadge(code: "G0439", label: "Annual Wellness Visit (subsequent)")
                codeBadge(code: state.suggestedICD10, label: "Suggested diagnosis code")
            }
        }
    }

    private func codeBadge(code: String, label: String) -> some View {
        HStack(spacing: 10) {
            Text(code)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(MCDesign.Colors.primary700)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(MCDesign.Colors.primary700.opacity(0.1))
                .cornerRadius(4)

            Text(label)
                .font(.system(size: 13))
                .foregroundColor(MCDesign.Colors.textSecondary)
        }
    }

    // MARK: - Actions

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: onFinalize) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Finalize & Save")
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(MCDesign.Colors.primary700)
                .cornerRadius(12)
            }

            Button(action: onRestart) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Start Over")
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(MCDesign.Colors.textSecondary)
            }
        }
    }

    // MARK: - Helpers

    private func reportCard<Content: View>(
        title: String, icon: String, accentColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(accentColor)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(MCDesign.Colors.textPrimary)
            }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }

    private func scoreColor(_ classification: QmciClassification) -> Color {
        switch classification {
        case .normal: return MCDesign.Colors.success
        case .mciProbable: return MCDesign.Colors.warning
        case .dementiaRange: return MCDesign.Colors.error
        }
    }

    private func subtestScore(_ subtest: QmciSubtest, state q: QmciState) -> Int {
        switch subtest {
        case .orientation: return q.orientationScore
        case .registration: return q.registrationScore
        case .clockDrawing: return q.clockDrawingScore
        case .verbalFluency: return q.verbalFluencyScore
        case .logicalMemory: return q.logicalMemoryScore
        case .delayedRecall: return q.delayedRecallScore
        }
    }

    private func computeResults() {
        // Compute composite risk
        state.compositeRisk = computeCompositeRiskQmciQDRS(
            qmciState: state.qmciState,
            qdrsState: state.qdrsState,
            phq2Score: state.phq2State.totalScore,
            clockAnalysis: state.clockAnalysis
        )

        // Compute amyloid triage
        state.amyloidTriage = computeAmyloidTriage(
            qmciState: state.qmciState,
            qdrsState: state.qdrsState,
            medications: state.medicationFlags
        )

        // Generate orders
        state.workupOrders = generateWorkupOrders(
            qmciClassification: state.qmciState.classification,
            phq2Score: state.phq2State.totalScore,
            isFirstEvaluation: true
        )
    }
}

#Preview {
    PCPReportView(
        state: AssessmentState(),
        onRestart: {},
        onFinalize: {}
    )
}
