//
//  ClinicianDashboardView.swift
//  VoiceMiniCog
//
//  Clinician-gated dashboard. Surfaces:
//    - Mode pre-select (Quick / Family Caregiver / Extended)
//    - Color-coded overall QMCI score at a glance (red/yellow/green)
//    - Tap-to-expand sub-scores + clock drawing + transcript
//    - PDF export for EHR manual attachment
//    - Family Caregiver "Flag that answer" controls (live during session)
//    - Per-patient longitudinal store browser
//
//  Gate: accessed via 5-tap chord on HomeView's brain icon, then passcode.
//  Passcode is a 4-digit PIN stored in Keychain; default on first launch
//  is "0000" — clinic admin must change it in Settings.
//

import SwiftUI

struct ClinicianDashboardView: View {

    let currentState: AssessmentState
    @Binding var flowType: AssessmentFlowType
    let onExit: () -> Void
    let onExportPDF: (Data) -> Void
    /// Called when clinician presses Start from the dashboard; flips to MA
    /// handoff or straight to assessment.
    let onGoToMAHandoff: () -> Void

    @State private var isUnlocked = false
    @State private var enteredPIN = ""
    @State private var showExpandedScore = false
    @State private var showCaregiverFlagSheet = false

    @AppStorage("voiceMiniCog.preselectedFlow") private var preselectedFlowRaw: String = AssessmentFlowType.quick.rawValue

    /// Guide preference (Task 6). nil until a clinician picks explicitly;
    /// GuideMode.resolved degrades an unusable avatar choice to voice.
    @AppStorage(GuideMode.storageKey) private var storedGuideMode: String?

    var body: some View {
        Group {
            if isUnlocked {
                unlockedView
            } else {
                pinGateView
            }
        }
    }

    // MARK: - PIN gate

    private var pinGateView: some View {
        VStack(spacing: 28) {
            Text("Clinician Access")
                .font(.system(size: 28, weight: .bold))
            Text("Enter 4-digit clinician PIN")
                .font(.system(size: 18))
                .foregroundColor(.secondary)

            SecureField("PIN", text: $enteredPIN)
                .textContentType(.oneTimeCode)
                .font(.system(size: 36, weight: .semibold, design: .monospaced))
                .multilineTextAlignment(.center)
                .frame(width: 220, height: 64)
                .background(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.4)))
                .onChange(of: enteredPIN) { _, new in
                    let digits = String(new.filter(\.isNumber).prefix(4))
                    if digits != new { enteredPIN = digits }
                    if digits.count == 4 { attemptUnlock(digits) }
                }

            HStack(spacing: 16) {
                Button("Cancel", action: onExit)
                    .font(.system(size: 18))
                    .buttonStyle(.bordered)
            }
        }
        .padding(40)
    }

    private func attemptUnlock(_ pin: String) {
        let storedPIN = KeychainHelper.read(key: "voiceMiniCog.clinician_pin") ?? "0000"
        if pin == storedPIN {
            isUnlocked = true
        } else {
            enteredPIN = ""
        }
    }

    // MARK: - Unlocked

    private var unlockedView: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Score glance
                    ScoreGlanceCard(state: currentState) {
                        showExpandedScore.toggle()
                    }

                    if showExpandedScore {
                        SubscoreBreakdown(state: currentState)
                    }

                    // Mode selection
                    modeCard

                    // Guide selection (voice clips vs Tavus video avatar)
                    guideCard

                    // MA handoff entry
                    Button {
                        onGoToMAHandoff()
                    } label: {
                        Label("Go to MA Handoff", systemImage: "arrow.right.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, minHeight: 60)
                            .background(RoundedRectangle(cornerRadius: 14).fill(MCDesign.Colors.primary700))
                    }
                    .buttonStyle(.plain)

                    // PDF export
                    Button {
                        let pdfData: Data
                        if AssessmentPersistence.isPartialSession {
                            pdfData = PartialScoreReport.generate(
                                state: currentState,
                                reason: AssessmentPersistence.shutdownReason ?? .unknown,
                                completed: AssessmentPersistence.completedSubtests,
                                policy: AssessmentPersistence.partialScorePolicy,
                                abandonedAt: AssessmentPersistence.abandonedAt
                            )
                        } else {
                            pdfData = PDFReportGenerator.generate(from: currentState)
                        }
                        onExportPDF(pdfData)
                    } label: {
                        Label("Export PDF Report", systemImage: "square.and.arrow.up")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.borderedProminent)

                    // Caregiver flags
                    if flowType == .caregiver {
                        caregiverFlagsCard
                    }

                    // Longitudinal patients browser
                    patientsCard
                }
                .padding(24)
            }
            .navigationTitle("Clinician Dashboard")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onExit)
                }
            }
        }
        .sheet(isPresented: $showCaregiverFlagSheet) {
            CaregiverFlagSheet(onClose: { showCaregiverFlagSheet = false })
        }
    }

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mode")
                .font(.system(size: 20, weight: .semibold))
            Picker("Mode", selection: $flowType) {
                Text("Quick").tag(AssessmentFlowType.quick)
                Text("Family Caregiver").tag(AssessmentFlowType.caregiver)
                Text("Extended").tag(AssessmentFlowType.extended)
            }
            .pickerStyle(.segmented)
            .onChange(of: flowType) { _, new in
                preselectedFlowRaw = new.rawValue
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.25)))
    }

    private var guideCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Guide")
                .font(.system(size: 20, weight: .semibold))
            Picker("Guide", selection: Binding(
                get: { GuideMode(rawValue: storedGuideMode ?? "") ?? GuideMode.current },
                set: { storedGuideMode = $0.rawValue })) {
                ForEach(GuideMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            if GuideMode(rawValue: storedGuideMode ?? "") == .avatar,
               GuideMode.current == .voice {
                Text("Video avatar requires a Tavus API key. Sessions will use the voice guide until one is configured.")
                    .font(.system(size: 14))
                    .foregroundColor(.orange)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.25)))
    }

    private var caregiverFlagsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Caregiver-Assisted Answers")
                .font(.system(size: 20, weight: .semibold))
            Text("Tap to flag the current answer as caregiver-assisted. Timestamped in the transcript.")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            Button {
                showCaregiverFlagSheet = true
            } label: {
                Label("Flag current answer", systemImage: "flag.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange))
            }
            .buttonStyle(.plain)

            let flags = AssessmentPersistence.caregiverFlags
            if !flags.isEmpty {
                Divider()
                Text("\(flags.count) flag(s) recorded this session:")
                    .font(.system(size: 14, weight: .semibold))
                ForEach(flags) { flag in
                    HStack {
                        Text(flag.phase)
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text(shortTime(flag.timestamp))
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.4)))
    }

    private var patientsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Patients")
                .font(.system(size: 20, weight: .semibold))
            let list = LongitudinalPatientStore.shared.allPatients()
            if list.isEmpty {
                Text("No patient records yet. Patients are created at MA handoff.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            } else {
                ForEach(list.prefix(12)) { p in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(p.displayName)
                                .font(.system(size: 16, weight: .semibold))
                            Text("ID: \(p.id) • \(p.languagePreference)")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(shortDate(p.lastSeen))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.25)))
    }

    private func shortTime(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f.string(from: d)
    }
    private func shortDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short; return f.string(from: d)
    }
}

// MARK: - Score glance

private struct ScoreGlanceCard: View {
    let state: AssessmentState
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                Text("QMCI Score")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.secondary)

                if AssessmentPersistence.isPartialSession {
                    Text("INCOMPLETE")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.red)
                    Text("Session ended before all subtests completed — not scorable.")
                        .font(.system(size: 14))
                        .foregroundColor(.red)
                } else {
                    let total = state.qmciState.totalScore
                    Text("\(total)/100")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundColor(color(for: total))
                    Text(tierLabel(for: total))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(color(for: total))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(color(for: state.qmciState.totalScore).opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }

    private func color(for total: Int) -> Color {
        if total >= 67 { return .green }
        if total >= 54 { return .orange }
        return .red
    }
    private func tierLabel(for total: Int) -> String {
        if total >= 67 { return "Normal range" }
        if total >= 54 { return "Possible MCI — further evaluation recommended" }
        return "Dementia range — clinical evaluation required"
    }
}

// MARK: - Subscore breakdown

private struct SubscoreBreakdown: View {
    let state: AssessmentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Subtest breakdown")
                .font(.system(size: 18, weight: .semibold))
            // Minimal inline rendering — full clinical scoring lives in
            // QMCIScoringEngine and the PDF generator.
            row(label: "Orientation",      value: "\(state.qmciState.orientationScore)/10")
            row(label: "Registration",     value: "\(state.qmciState.registrationScore)/5")
            row(label: "Clock Drawing",    value: "\(state.qmciState.effectiveClockDrawingScore)/15")
            row(label: "Verbal Fluency",   value: "\(state.qmciState.verbalFluencyScore)/20")
            row(label: "Story Recall",     value: "\(state.qmciState.logicalMemoryScore)/30")
            row(label: "Delayed Recall",   value: "\(state.qmciState.delayedRecallScore)/20")
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.25)))
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 16))
            Spacer()
            Text(value).font(.system(size: 16, weight: .semibold, design: .monospaced))
        }
    }
}

// MARK: - Caregiver flag sheet

private struct CaregiverFlagSheet: View {
    let onClose: () -> Void
    @State private var note: String = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Flag current answer as caregiver-assisted")
                    .font(.system(size: 18, weight: .semibold))
                Text("This marks the current transcript position for clinician review. Optional note below.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                TextField("Optional note", text: $note, axis: .vertical)
                    .lineLimit(3...6)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.3)))

                Button {
                    let phase = Phase.qmciOrientation  // Host can pass current phase in a real wiring
                    AssessmentPersistence.appendCaregiverFlag(phase: phase, note: note.isEmpty ? nil : note)
                    onClose()
                } label: {
                    Text("Flag")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange))
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(24)
            .navigationTitle("Caregiver Flag")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onClose)
                }
            }
        }
    }
}
