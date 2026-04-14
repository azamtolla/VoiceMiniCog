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

    @State private var showShareSheet = false
    @State private var pdfData: Data?
    @State private var isClockScoringExpanded: Bool = true

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

                // 5. Clock Drawing (QMCI 15-point manual scoring + reference canvas)
                clockSection

                // 5b. Clinical Decision (required for finalization)
                clinicalDecisionSection

                // ASR Review (only if semantic substitutions exist)
                if !state.qmciState.recallSemanticSubstitutions.isEmpty {
                    asrReviewSection
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
        .sheet(isPresented: $showShareSheet) {
            if let data = pdfData {
                ShareSheet(activityItems: [PDFDataItem(data: data)])
            }
        }
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
        let age = state.patientAge
        let edu = state.patientEducationYears
        let adjustedClass = q.adjustedClassification(age: age, educationYears: edu)
        let adjustedScore = q.adjustedScore(age: age, educationYears: edu)
        let reasons = q.adjustmentReasons(age: age, educationYears: edu)
        let hasAdjustments = !reasons.isEmpty

        return reportCard(title: "Cognitive Profile (Qmci)", icon: "brain", accentColor: MCDesign.Colors.primary700) {
            VStack(spacing: 14) {
                // Raw total score
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

                Text("Raw score")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(MCDesign.Colors.textTertiary)
                    .tracking(0.6)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Demographics entry + adjusted classification
                demographicsAndAdjustmentSection(
                    adjustedClass: adjustedClass,
                    adjustedScore: adjustedScore,
                    reasons: reasons,
                    hasAdjustments: hasAdjustments
                )

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

                // Orientation question-by-question detail
                orientationDetailSection(state: q)
            }
        }
    }

    // MARK: - Demographics + Normative Adjustment

    @ViewBuilder
    private func demographicsAndAdjustmentSection(
        adjustedClass: QmciClassification,
        adjustedScore: Int,
        reasons: [String],
        hasAdjustments: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().padding(.vertical, 2)

            Text("NORMATIVE ADJUSTMENT")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(MCDesign.Colors.textTertiary)
                .tracking(0.8)

            // Clinician entry for age & education
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Age")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(MCDesign.Colors.textSecondary)
                    TextField("Age", value: $state.patientAge, format: .number)
                        .keyboardType(.numberPad)
                        .font(.system(size: 14))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(MCDesign.Colors.surfaceInset)
                        .cornerRadius(6)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Years of Education")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(MCDesign.Colors.textSecondary)
                    TextField("Education years", value: $state.patientEducationYears, format: .number)
                        .keyboardType(.numberPad)
                        .font(.system(size: 14))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(MCDesign.Colors.surfaceInset)
                        .cornerRadius(6)
                }
            }

            // Adjusted score + classification
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Adjusted score")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(MCDesign.Colors.textTertiary)
                        .tracking(0.6)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(adjustedScore)")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(scoreColor(adjustedClass))
                        Text("/ 100")
                            .font(.system(size: 13))
                            .foregroundColor(MCDesign.Colors.textTertiary)
                    }
                }

                Spacer()

                Text(adjustedClass.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(scoreColor(adjustedClass))
                    .cornerRadius(7)
            }
            .padding(10)
            .background(MCDesign.Colors.surfaceInset)
            .cornerRadius(8)

            // Adjustment reasoning
            if hasAdjustments {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(reasons, id: \.self) { reason in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(MCDesign.Colors.primary700)
                                .padding(.top, 2)
                            Text(reason)
                                .font(.system(size: 12))
                                .foregroundColor(MCDesign.Colors.textSecondary)
                        }
                    }
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundColor(MCDesign.Colors.textTertiary)
                    Text("No normative adjustments applied (age \u{2264} 75 and education \u{2265} 12 years).")
                        .font(.system(size: 12))
                        .foregroundColor(MCDesign.Colors.textTertiary)
                }
            }
        }
    }

    // MARK: - Orientation Detail

    private func orientationDetailSection(state q: QmciState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .padding(.vertical, 4)

            HStack {
                Text("ORIENTATION RESPONSES")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(MCDesign.Colors.textTertiary)
                    .tracking(0.8)

                Spacer()

                Text("\(q.orientationScore)/10")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(MCDesign.Colors.textSecondary)
            }

            Text("Review each response and adjust the score. 2 = correct, 1 = attempted but incorrect, 0 = no attempt or unrelated.")
                .font(.system(size: 11))
                .foregroundColor(MCDesign.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(0..<ORIENTATION_ITEMS.count, id: \.self) { i in
                orientationScoreRow(index: i, state: q)
            }
        }
    }

    @ViewBuilder
    private func orientationScoreRow(index i: Int, state q: QmciState) -> some View {
        let rawScore: Int? = (i < q.orientationScores.count) ? q.orientationScores[i] : nil
        let currentScore = rawScore ?? 0

        VStack(alignment: .leading, spacing: 6) {
            Text(ORIENTATION_ITEMS[i].question)
                .font(.system(size: 13))
                .foregroundColor(MCDesign.Colors.textPrimary)

            Picker("Score", selection: Binding<Int>(
                get: { currentScore },
                set: { newValue in
                    guard i < q.orientationScores.count else { return }
                    q.orientationScores[i] = newValue
                    // Refresh composite risk banner so it reflects the new total.
                    computeResults()
                }
            )) {
                Text("0").tag(0)
                Text("1").tag(1)
                Text("2").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.vertical, 4)
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
        let q = state.qmciState
        let currentScore = q.cdtComputedScore

        return reportCard(title: "Clock Drawing — QMCI 15-point Scoring",
                          icon: "clock.fill",
                          accentColor: MCDesign.Colors.clockAccent) {
            VStack(alignment: .leading, spacing: 14) {
                // MARK: - Header with drawing + current total
                HStack(alignment: .top, spacing: 16) {
                    // Drawing canvas (reference image)
                    if let img = state.clockImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 140, height: 140)
                            .background(Color.white)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(MCDesign.Colors.border, lineWidth: 1)
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(MCDesign.Colors.surfaceInset)
                            .frame(width: 140, height: 140)
                            .overlay(
                                VStack(spacing: 4) {
                                    Image(systemName: "clock.badge.questionmark")
                                        .font(.system(size: 22))
                                        .foregroundColor(MCDesign.Colors.textTertiary)
                                    Text("No drawing")
                                        .font(.system(size: 11))
                                        .foregroundColor(MCDesign.Colors.textTertiary)
                                }
                            )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Clinician Score")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(MCDesign.Colors.textTertiary)
                            .tracking(0.6)

                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(currentScore)")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundColor(MCDesign.Colors.primary700)
                            Text("/ 15")
                                .font(.system(size: 16))
                                .foregroundColor(MCDesign.Colors.textTertiary)
                        }

                        // Legacy AI score for reference (not authoritative)
                        if let analysis = state.clockAnalysis {
                            Text("AI reference: \(analysis.severity) (Shulman \(analysis.shulmanRange))")
                                .font(.system(size: 10))
                                .foregroundColor(MCDesign.Colors.textTertiary)
                                .italic()
                        }
                    }

                    Spacer()
                }

                // MARK: - Expand/Collapse header
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isClockScoringExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: isClockScoringExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(MCDesign.Colors.primary700)
                        Text(isClockScoringExpanded ? "Hide Manual Scoring" : "Show Manual Scoring")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(MCDesign.Colors.primary700)
                        Spacer()
                        Text("Clock Drawing: \(currentScore)/15")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(MCDesign.Colors.textSecondary)
                    }
                    .padding(10)
                    .background(MCDesign.Colors.surfaceInset)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)

                // MARK: - Expanded rubric
                if isClockScoringExpanded {
                    clockRubricEditor
                }
            }
        }
    }

    /// Clinician-editable rubric for QMCI 15-point clock drawing score.
    /// Structure:
    ///   • Numbers placed (12 checkboxes for 1..12, 1 pt each)
    ///   • Minute hand correct (toward 2)
    ///   • Hour hand correct (toward 11)
    ///   • Pivot correct
    ///   • Invalid-number penalty counter (-1 each)
    private var clockRubricEditor: some View {
        let q = state.qmciState

        return VStack(alignment: .leading, spacing: 16) {
            // --- Numbers placed section ---
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("NUMBERS PLACED (1 PT EACH)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(MCDesign.Colors.textTertiary)
                        .tracking(0.6)
                    Spacer()
                    Text("\(q.cdtNumbersPlaced.filter { $0 }.count)/12")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(MCDesign.Colors.textSecondary)
                }

                let columns = [GridItem(.adaptive(minimum: 64), spacing: 8)]
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(0..<12, id: \.self) { idx in
                        clockNumberToggle(index: idx)
                    }
                }
            }

            Divider()

            // --- Hands (0/1/2) + pivot section ---
            VStack(alignment: .leading, spacing: 8) {
                Text("HANDS & PIVOT")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(MCDesign.Colors.textTertiary)
                    .tracking(0.6)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Hands (both pointing correctly = 2, one = 1, neither = 0)")
                        .font(.system(size: 13))
                        .foregroundColor(MCDesign.Colors.textSecondary)
                    Picker("Hands score", selection: Binding(
                        get: { q.cdtHandsScore },
                        set: { newValue in
                            q.cdtHandsScore = newValue
                            q.recomputeClockDrawingScore()
                        }
                    )) {
                        Text("0").tag(0)
                        Text("1").tag(1)
                        Text("2").tag(2)
                    }
                    .pickerStyle(.segmented)
                }

                clockRubricRow(
                    label: "Pivot (center where hands meet)",
                    isOn: Binding(
                        get: { q.cdtPivotCorrect },
                        set: { newValue in
                            q.cdtPivotCorrect = newValue
                            q.recomputeClockDrawingScore()
                        }
                    )
                )
            }

            Divider()

            // --- Penalty counter ---
            VStack(alignment: .leading, spacing: 8) {
                Text("PENALTIES (-1 EACH)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(MCDesign.Colors.textTertiary)
                    .tracking(0.6)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Duplicate or >12 numbers")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(MCDesign.Colors.textPrimary)
                        Text("Each duplicate or out-of-range number subtracts 1 point")
                            .font(.system(size: 11))
                            .foregroundColor(MCDesign.Colors.textTertiary)
                    }

                    Spacer()

                    HStack(spacing: 10) {
                        Button(action: {
                            if q.cdtInvalidNumbersCount > 0 {
                                q.cdtInvalidNumbersCount -= 1
                                q.recomputeClockDrawingScore()
                            }
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(q.cdtInvalidNumbersCount > 0
                                                 ? MCDesign.Colors.error
                                                 : MCDesign.Colors.border)
                        }
                        .buttonStyle(.plain)
                        .disabled(q.cdtInvalidNumbersCount == 0)

                        Text("\(q.cdtInvalidNumbersCount)")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(MCDesign.Colors.textPrimary)
                            .frame(minWidth: 24)

                        Button(action: {
                            q.cdtInvalidNumbersCount += 1
                            q.recomputeClockDrawingScore()
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(MCDesign.Colors.primary700)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            // --- Total + reset ---
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TOTAL")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(MCDesign.Colors.textTertiary)
                        .tracking(0.6)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(q.cdtComputedScore)")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(MCDesign.Colors.primary700)
                        Text("/ 15")
                            .font(.system(size: 14))
                            .foregroundColor(MCDesign.Colors.textTertiary)
                    }
                }

                Spacer()

                Button(action: resetClockRubric) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Reset")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(MCDesign.Colors.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(MCDesign.Colors.surfaceInset)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }

            Divider().padding(.vertical, 4)

            Toggle(isOn: Binding(
                get: { state.qmciState.cdtReviewed },
                set: { state.qmciState.cdtReviewed = $0 }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("I have reviewed and scored this clock drawing")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Required before report can be finalized")
                        .font(.system(size: 12))
                        .foregroundStyle(MCDesign.Colors.textTertiary)
                }
            }
            .tint(MCDesign.Colors.success)
        }
    }

    /// Single tappable number tile for a clock number (1..12).
    private func clockNumberToggle(index: Int) -> some View {
        let q = state.qmciState
        let number = index + 1
        let isChecked = q.cdtNumbersPlaced.indices.contains(index)
            ? q.cdtNumbersPlaced[index]
            : false

        return Button(action: {
            guard q.cdtNumbersPlaced.indices.contains(index) else { return }
            q.cdtNumbersPlaced[index].toggle()
            q.recomputeClockDrawingScore()
        }) {
            HStack(spacing: 6) {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16))
                    .foregroundColor(isChecked
                                     ? MCDesign.Colors.primary700
                                     : MCDesign.Colors.border)
                Text("\(number)")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(isChecked
                                     ? MCDesign.Colors.textPrimary
                                     : MCDesign.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isChecked
                        ? MCDesign.Colors.primary700.opacity(0.08)
                        : MCDesign.Colors.surfaceInset)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isChecked
                            ? MCDesign.Colors.primary700.opacity(0.3)
                            : MCDesign.Colors.border,
                            lineWidth: 1)
            )
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    /// Single toggleable row (minute hand / hour hand / pivot).
    private func clockRubricRow(label: String, isOn: Binding<Bool>) -> some View {
        Button(action: { isOn.wrappedValue.toggle() }) {
            HStack(spacing: 10) {
                Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18))
                    .foregroundColor(isOn.wrappedValue
                                     ? MCDesign.Colors.primary700
                                     : MCDesign.Colors.border)
                Text(label)
                    .font(.system(size: 14))
                    .foregroundColor(MCDesign.Colors.textPrimary)
                Spacer()
                Text(isOn.wrappedValue ? "+1" : "0")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(isOn.wrappedValue
                                     ? MCDesign.Colors.success
                                     : MCDesign.Colors.textTertiary)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private func resetClockRubric() {
        let q = state.qmciState
        q.cdtNumbersPlaced = Array(repeating: false, count: 12)
        q.cdtHandsScore = 0
        q.cdtPivotCorrect = false
        q.cdtInvalidNumbersCount = 0
        q.recomputeClockDrawingScore()
    }

    // MARK: - Clinical Decision

    private var clinicalDecisionSection: some View {
        let q = state.qmciState
        let age = state.patientAge
        let edu = state.patientEducationYears

        return reportCard(title: "Clinical Decision", icon: "stethoscope", accentColor: MCDesign.Colors.primary700) {
            VStack(alignment: .leading, spacing: 16) {

                // 1. Score + classification
                HStack {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(q.totalScore)")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(scoreColor(q.classification))
                        Text("/ 100")
                            .font(.system(size: 14))
                            .foregroundColor(MCDesign.Colors.textTertiary)
                    }
                    Spacer()
                    Text(q.classification.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(scoreColor(q.classification))
                        .cornerRadius(7)
                }

                // 2. Age-adjusted (if demographics entered)
                if age > 0 {
                    let adjScore = q.adjustedScore(age: age, educationYears: edu)
                    let adjClass = q.adjustedClassification(age: age, educationYears: edu)
                    let reasons = q.adjustmentReasons(age: age, educationYears: edu)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("AGE-ADJUSTED")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(MCDesign.Colors.textTertiary)
                                    .tracking(0.6)
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text("\(adjScore)")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(scoreColor(adjClass))
                                    Text("/ 100")
                                        .font(.system(size: 12))
                                        .foregroundColor(MCDesign.Colors.textTertiary)
                                }
                            }
                            Spacer()
                            Text(adjClass.rawValue)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(scoreColor(adjClass))
                                .cornerRadius(6)
                        }
                        ForEach(reasons, id: \.self) { reason in
                            Text(reason)
                                .font(.system(size: 11))
                                .foregroundColor(MCDesign.Colors.textSecondary)
                        }
                    }
                    .padding(10)
                    .background(MCDesign.Colors.surfaceInset)
                    .cornerRadius(8)
                }

                // 3. Risk signals
                if !q.riskSignals.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(q.riskSignals.enumerated()), id: \.offset) { _, signal in
                            HStack(spacing: 8) {
                                Image(systemName: signal.severity == .critical ? "exclamationmark.triangle.fill" : "info.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(signal.severity == .critical ? MCDesign.Colors.error : MCDesign.Colors.warning)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(signal.domain)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(MCDesign.Colors.textPrimary)
                                    Text(signal.finding)
                                        .font(.system(size: 11))
                                        .foregroundColor(MCDesign.Colors.textSecondary)
                                }
                            }
                        }
                    }
                    .padding(10)
                    .background(MCDesign.Colors.errorSurface.opacity(0.3))
                    .cornerRadius(8)
                }

                Divider()

                // 4. Recommend workup?
                VStack(alignment: .leading, spacing: 8) {
                    Text("RECOMMEND WORKUP?")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(MCDesign.Colors.textTertiary)
                        .tracking(0.8)

                    HStack(spacing: 10) {
                        clinicalToggleButton(
                            label: "Yes",
                            isSelected: q.clinicianDecisionWorkup == .yes,
                            accentColor: MCDesign.Colors.primary700
                        ) {
                            q.clinicianDecisionWorkup = .yes
                            q.clinicianDecisionTimestamp = Date()
                        }
                        clinicalToggleButton(
                            label: "No",
                            isSelected: q.clinicianDecisionWorkup == .no,
                            accentColor: MCDesign.Colors.primary700
                        ) {
                            q.clinicianDecisionWorkup = .no
                            q.clinicianDecisionTimestamp = Date()
                        }
                        clinicalToggleButton(
                            label: "Defer",
                            isSelected: q.clinicianDecisionWorkup == .deferRepeat,
                            accentColor: MCDesign.Colors.primary700
                        ) {
                            q.clinicianDecisionWorkup = .deferRepeat
                            q.clinicianDecisionTimestamp = Date()
                        }
                    }

                    if q.clinicianDecisionWorkup == nil {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(MCDesign.Colors.warning)
                            Text("Required — select a workup recommendation to finalize")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(MCDesign.Colors.warning)
                        }
                    }
                }

                Divider()

                // 5. Repeat testing interval
                VStack(alignment: .leading, spacing: 8) {
                    Text("REPEAT TESTING IN")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(MCDesign.Colors.textTertiary)
                        .tracking(0.8)

                    HStack(spacing: 10) {
                        clinicalToggleButton(
                            label: "6 mo",
                            isSelected: q.clinicianDecisionRepeat == .sixMonths,
                            accentColor: MCDesign.Colors.primary500
                        ) {
                            q.clinicianDecisionRepeat = .sixMonths
                        }
                        clinicalToggleButton(
                            label: "12 mo",
                            isSelected: q.clinicianDecisionRepeat == .twelveMonths,
                            accentColor: MCDesign.Colors.primary500
                        ) {
                            q.clinicianDecisionRepeat = .twelveMonths
                        }
                        clinicalToggleButton(
                            label: "24 mo",
                            isSelected: q.clinicianDecisionRepeat == .twentyFourMonths,
                            accentColor: MCDesign.Colors.primary500
                        ) {
                            q.clinicianDecisionRepeat = .twentyFourMonths
                        }
                        clinicalToggleButton(
                            label: "None",
                            isSelected: q.clinicianDecisionRepeat == .some(RepeatInterval.none),
                            accentColor: MCDesign.Colors.primary500
                        ) {
                            q.clinicianDecisionRepeat = RepeatInterval.none
                        }
                    }
                }

                Divider()

                // 6. ICD-10 suggestion
                VStack(alignment: .leading, spacing: 4) {
                    Text("ICD-10 SUGGESTION")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(MCDesign.Colors.textTertiary)
                        .tracking(0.8)

                    HStack(spacing: 8) {
                        Text(q.icd10Suggestion.code)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(MCDesign.Colors.primary700)
                        Text("—")
                            .foregroundColor(MCDesign.Colors.textTertiary)
                        Text(q.icd10Suggestion.description)
                            .font(.system(size: 14))
                            .foregroundColor(MCDesign.Colors.textPrimary)
                    }
                    Text(q.icd10Suggestion.rationale)
                        .font(.system(size: 11))
                        .foregroundColor(MCDesign.Colors.textSecondary)
                }
            }
        }
    }

    /// A toggle-style button for the clinical decision picker rows.
    private func clinicalToggleButton(
        label: String,
        isSelected: Bool,
        accentColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isSelected ? .white : MCDesign.Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(isSelected ? accentColor : Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? accentColor : MCDesign.Colors.border, lineWidth: 1.5)
                )
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - ASR Review

    private var asrReviewSection: some View {
        let q = state.qmciState

        return reportCard(title: "Word Recall — ASR Review",
                          icon: "waveform.badge.magnifyingglass",
                          accentColor: MCDesign.Colors.primary700) {
            VStack(alignment: .leading, spacing: 14) {
                Text("The speech recognizer detected possible matches. Accept to credit the word, or reject.")
                    .font(MCDesign.Fonts.reportCaption)
                    .foregroundColor(MCDesign.Colors.textSecondary)

                ForEach(Array(q.recallSemanticSubstitutions.enumerated()), id: \.offset) { _, sub in
                    let override = q.recallClinicianOverrides[sub.target]

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 4) {
                            Text("Patient said")
                                .font(MCDesign.Fonts.reportCaption)
                                .foregroundColor(MCDesign.Colors.textSecondary)
                            Text("'\(sub.substitution)'")
                                .font(MCDesign.Fonts.reportBody.bold())
                                .foregroundColor(MCDesign.Colors.textPrimary)
                            Text("→ matched")
                                .font(MCDesign.Fonts.reportCaption)
                                .foregroundColor(MCDesign.Colors.textSecondary)
                            Text("'\(sub.target)'")
                                .font(MCDesign.Fonts.reportBody.bold())
                                .foregroundColor(MCDesign.Colors.textPrimary)
                        }

                        HStack(spacing: 10) {
                            Button(action: {
                                q.recallClinicianOverrides[sub.target] = true
                                if !q.delayedRecallWords.contains(sub.target) {
                                    q.delayedRecallWords.append(sub.target)
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                    Text("Accept")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .foregroundColor(override == true ? .white : MCDesign.Colors.success)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(override == true ? MCDesign.Colors.success : Color.clear)
                                .overlay(
                                    Capsule()
                                        .stroke(MCDesign.Colors.success, lineWidth: 1.5)
                                )
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)

                            Button(action: {
                                q.recallClinicianOverrides[sub.target] = false
                                q.delayedRecallWords.removeAll { $0 == sub.target }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 12, weight: .bold))
                                    Text("Reject")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .foregroundColor(override == false ? .white : MCDesign.Colors.error)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(override == false ? MCDesign.Colors.error : Color.clear)
                                .overlay(
                                    Capsule()
                                        .stroke(MCDesign.Colors.error, lineWidth: 1.5)
                                )
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)

                            Spacer()
                        }
                    }
                    .padding(10)
                    .background(MCDesign.Colors.surfaceInset)
                    .cornerRadius(8)
                }

                Divider()

                // Live delayed recall score
                HStack {
                    Text("Delayed Recall Score:")
                        .font(MCDesign.Fonts.reportBody)
                        .foregroundColor(MCDesign.Colors.textPrimary)
                    Spacer()
                    Text("\(q.delayedRecallScore)/20")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(MCDesign.Colors.primary700)
                }
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
        let canFinalize = state.qmciState.reportReadiness == .complete || state.qmciState.reportReadiness == .finalized

        return VStack(spacing: 12) {
            Button(action: {
                pdfData = PDFReportGenerator.generate(from: state)
                showShareSheet = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share Report")
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(MCDesign.Colors.primary700)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(MCDesign.Colors.primary700, lineWidth: 2)
                )
                .cornerRadius(12)
            }
            .disabled(!canFinalize)
            .opacity(canFinalize ? 1.0 : 0.5)

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
            .disabled(!canFinalize)
            .opacity(canFinalize ? 1.0 : 0.5)

            if state.qmciState.pendingReviewCount > 0 {
                Label("\(state.qmciState.pendingReviewCount) required field(s) remaining",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MCDesign.Colors.warning)
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
        case .clockDrawing: return q.effectiveClockDrawingScore
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

// MARK: - ShareSheet (UIKit bridge)

/// Wraps UIActivityViewController for SwiftUI presentation.
private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Vends PDF data to UIActivityViewController as a named PDF file,
/// enabling AirDrop, Print, Save to Files, email attachment, etc.
private final class PDFDataItem: NSObject, UIActivityItemSource {
    let data: Data

    init(data: Data) {
        self.data = data
        super.init()
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        data
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        data
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        "com.adobe.pdf"
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        "MercyCognitive Screening Report"
    }
}

#Preview {
    PCPReportView(
        state: AssessmentState(),
        onRestart: {},
        onFinalize: {}
    )
}
