//
//  ResearchRootView.swift
//  VoiceMiniCog
//
//  MERIDIAN-1 research-mode root view + entry.
//
//  Shape: alternative root (Option 1). Swapped in at the App-struct level
//  when `ResearchModeSettings.shared.isActive == true`. This is a
//  deliberate departure from the swiftui-patterns "stable view tree"
//  heuristic: identity reset on activation is the security feature — the
//  clinical view stack (ContentView, Tavus, avatar, mic) is never
//  instantiated during a research session and cannot be reached from this
//  subtree.
//
//  Section 5.1 compliance:
//  - No avatar, no TTS, no Tavus REST calls, no Daily SDK.
//  - No PCPReportView in reachable tree (suppression is structural).
//  - Drawing surface feeds the raw UITouch stream into RawStreamRecorder.
//
//  Entry: because the app only swaps in this root once isActive is true,
//  activation must originate from the clinical side. `researchModeEntry()`
//  adds a hidden staff affordance (five taps in the top-leading corner)
//  presenting the activation sheet, applied to ContentView at the App
//  level so ContentView itself is never modified.
//

#if DEBUG || RESEARCH
import SwiftUI

// MARK: - Tasks

enum DrawingTask: String, CaseIterable, Identifiable {
    case commandClock = "Command Clock"
    case copyClock    = "Copy Clock"
    case spiral       = "Archimedean Spiral"

    var id: String { rawValue }

    /// Filesystem-safe component for the stream filename.
    var fileToken: String {
        switch self {
        case .commandClock: return "commandclock"
        case .copyClock:    return "copyclock"
        case .spiral:       return "spiral"
        }
    }

    /// Fixed task duration hint shown to the examiner (seconds); the spiral
    /// is time-boxed at 90 s per protocol, the clocks are untimed.
    var durationHintSeconds: Int? {
        self == .spiral ? 90 : nil
    }
}

// MARK: - Root

struct ResearchRootView: View {
    @State private var recorder = RawStreamRecorder()
    @State private var settings = ResearchModeSettings.shared
    @State private var selectedTask: DrawingTask = .commandClock
    @State private var session = 1
    @State private var sessionActive = false
    @State private var taskStartEpoch: Double = 0
    @State private var banner: String?

    var body: some View {
        NavigationStack {
            Group {
                if sessionActive {
                    ResearchDrawingSessionView(
                        task: selectedTask,
                        recorder: recorder,
                        taskStartEpoch: taskStartEpoch,
                        onEnd: endTask
                    )
                } else {
                    ResearchModeLauncherView(
                        settings: settings,
                        selectedTask: $selectedTask,
                        session: $session,
                        banner: $banner,
                        onStart: startTask,
                        onWipe: wipeAll,
                        onExit: { settings.deactivate() }
                    )
                }
            }
            .navigationTitle("MERIDIAN-1 Research")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func startTask() {
        do {
            try recorder.beginTask(platform: "iPad", task: selectedTask.fileToken, session: session)
            taskStartEpoch = recorder.taskStartMonotonicMs
            banner = nil
            sessionActive = true
        } catch {
            banner = error.localizedDescription
        }
    }

    private func endTask() {
        do { try recorder.endTask() }
        catch { banner = error.localizedDescription }
        sessionActive = false
    }

    /// Operator-confirmed transfer: the caller has verified files are on
    /// secure storage before invoking. Wipes exactly the present set and
    /// deactivates once the directory is empty.
    private func wipeAll() {
        do {
            let files = Set(try recorder.streamFiles())
            try recorder.wipeConfirmedTransfers(files)
        } catch {
            banner = error.localizedDescription
        }
    }
}

// MARK: - Launcher (config screen; reached only while active)

struct ResearchModeLauncherView: View {
    let settings: ResearchModeSettings
    @Binding var selectedTask: DrawingTask
    @Binding var session: Int
    @Binding var banner: String?
    let onStart: () -> Void
    let onWipe: () -> Void
    let onExit: () -> Void

    @State private var showWipeConfirm = false

    var body: some View {
        Form {
            if let banner {
                Section {
                    Label(banner, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }

            if settings.isActive {
                participantSection
                taskSection
                startSection
                dangerSection
            } else {
                Section {
                    ContentUnavailableView(
                        "Not Activated",
                        systemImage: "lock.fill",
                        description: Text("Research Mode is not active. Exit and use the staff activation gesture.")
                    )
                }
            }
        }
    }

    private var participantSection: some View {
        Section("Session") {
            LabeledContent("Participant", value: settings.activeStudyID ?? "—")
            LabeledContent("Site / token", value: settings.siteStudyID ?? "—")
        }
    }

    private var taskSection: some View {
        Section("Task") {
            Picker("Task", selection: $selectedTask) {
                ForEach(DrawingTask.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Stepper("Session #\(session)", value: $session, in: 1...9)
            if let secs = selectedTask.durationHintSeconds {
                Text("Time-boxed at \(secs) s.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var startSection: some View {
        Section {
            Button {
                onStart()
            } label: {
                Label("Start \(selectedTask.rawValue)", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var dangerSection: some View {
        Section("After transfer") {
            Button(role: .destructive) {
                showWipeConfirm = true
            } label: {
                Label("Transfer confirmed — wipe device", systemImage: "trash")
            }
            .confirmationDialog(
                "Permanently delete all captured files on this device?",
                isPresented: $showWipeConfirm, titleVisibility: .visible
            ) {
                Button("Delete all captures", role: .destructive, action: onWipe)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Only proceed after confirming every file has been copied to secure research storage. This cannot be undone.")
            }

            Button(role: .cancel, action: onExit) {
                Label("Exit Research Mode", systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
    }
}

// MARK: - Active drawing session

struct ResearchDrawingSessionView: View {
    let task: DrawingTask
    let recorder: RawStreamRecorder
    let taskStartEpoch: Double
    let onEnd: () -> Void

    @State private var startDate = Date()

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            UITouchCaptureView(recorder: recorder, taskStartEpoch: taskStartEpoch)
                .background(Color(uiColor: .secondarySystemBackground))
                .accessibilityLabel("Drawing capture surface")
            Button(role: .destructive, action: onEnd) {
                Label("End Task", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
        .onAppear { startDate = Date() }
        .navigationBarBackButtonHidden(true)
    }

    /// Timeline refresh drives both the elapsed clock and a live capture-
    /// health read of the (non-Observable) recorder.
    private var statusBar: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let elapsed = context.date.timeIntervalSince(startDate)
            HStack {
                VStack(alignment: .leading) {
                    Text(task.rawValue).font(.headline)
                    Text(String(format: "%.1f s", elapsed))
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                captureHealth
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var captureHealth: some View {
        if recorder.captureFailed || recorder.droppedSampleCount > 0 {
            Label("\(recorder.droppedSampleCount) dropped", systemImage: "exclamationmark.triangle.fill")
                .font(.footnote).foregroundStyle(.orange)
        } else {
            Label("Recording", systemImage: "record.circle")
                .font(.footnote).foregroundStyle(.green)
        }
    }
}

// MARK: - Activation (staff entry from the clinical side)

struct ResearchActivationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var siteToken = ResearchModeSettings.selectableSiteTokens.first ?? ""
    @State private var participantID = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Activate Research Mode") {
                    Picker("Site / session", selection: $siteToken) {
                        ForEach(ResearchModeSettings.selectableSiteTokens, id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                    TextField("Participant ID (5 chars)", text: $participantID)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                    Text("5 characters, no O/0, I/1 or L.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Research Login")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Activate", action: activate)
                }
            }
        }
    }

    private func activate() {
        let id = participantID.uppercased()
        if ResearchModeSettings.shared.activate(siteToken: siteToken, participantID: id) {
            dismiss()   // isActive → true triggers the App-level root swap
        } else {
            error = "Invalid site token or participant ID (need 5 chars, no O/0/I/1/L)."
        }
    }
}

// MARK: - Hidden staff entry

private struct ResearchModeEntryModifier: ViewModifier {
    @State private var taps = 0
    @State private var showActivation = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) {
                Color.clear
                    .frame(width: 64, height: 64)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        taps += 1
                        if taps >= 5 { taps = 0; showActivation = true }
                    }
                    .accessibilityHidden(true)
            }
            .sheet(isPresented: $showActivation) { ResearchActivationView() }
    }
}

extension View {
    /// Adds the hidden five-tap staff entry that presents the Research Mode
    /// activation sheet. Applied to the clinical root at the App level.
    func researchModeEntry() -> some View {
        modifier(ResearchModeEntryModifier())
    }
}
#endif
