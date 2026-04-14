//
//  MAHandoffView.swift
//  VoiceMiniCog
//
//  Medical-assistant handoff screen — the bridge between clinician-controlled
//  setup and autonomous patient operation.
//
//  FLOW:
//    1. MA enters patient ID (or QR scans — scan path fills both name + ID).
//    2. MA confirms patient display name + language preference.
//    3. MA taps "Hand iPad to Patient" — this writes a timestamped audit
//       record via AssessmentPersistence.recordHandoff() and flips the UI
//       to the patient-facing single-button home.
//
//  After handoff, patient sees only HomeView's one big "Tap to Begin" button.
//

import SwiftUI

struct MAHandoffView: View {

    /// Pre-selected assessment flow (Quick / Family Caregiver / Extended).
    @Binding var flowType: AssessmentFlowType

    /// Called after handoff is confirmed. Host flips to the patient-facing
    /// HomeView and records the handoff timestamp.
    let onHandoffConfirmed: (_ patientID: String) -> Void

    /// Called if the MA cancels handoff.
    let onCancel: () -> Void

    @State private var patientID: String = ""
    @State private var displayName: String = ""
    @State private var language: String = "en-US"
    @State private var showQRScanner: Bool = false

    @AppStorage("voiceMiniCog.stt_language") private var sttLanguage: String = "en-US"
    @AppStorage("voiceMiniCog.preselectedFlow") private var preselectedFlowRaw: String = AssessmentFlowType.quick.rawValue

    private var canHandoff: Bool {
        !patientID.trimmingCharacters(in: .whitespaces).isEmpty
            && !displayName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ZStack {
            MCDesign.Colors.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {

                HStack {
                    Text("Clinician — MA Handoff")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(MCDesign.Colors.primary700)
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(MCDesign.Colors.primary700)
                }

                Text("Confirm patient details, then hand the iPad to the patient. The timestamp is recorded for the audit log.")
                    .font(.system(size: 16))
                    .foregroundColor(MCDesign.Colors.textSecondary)

                Divider()

                // Patient ID + QR scan
                labeledField(
                    title: "Patient ID (MRN or chart ID)",
                    text: $patientID,
                    trailing: AnyView(
                        Button {
                            showQRScanner = true
                        } label: {
                            Label("Scan", systemImage: "qrcode.viewfinder")
                                .labelStyle(.titleAndIcon)
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Scan QR code to fill patient ID")
                    )
                )

                // Display name
                labeledField(title: "Patient's preferred name", text: $displayName)

                // Language
                VStack(alignment: .leading, spacing: 8) {
                    Text("Language")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(MCDesign.Colors.textPrimary)
                    Picker("Language", selection: $language) {
                        Text("English (US)").tag("en-US")
                        Text("Español (US)").tag("es-US")
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 360)
                }

                // Flow type (pre-selected by clinician for this handoff)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Assessment type")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(MCDesign.Colors.textPrimary)
                    Picker("Assessment type", selection: $flowType) {
                        Text("Quick").tag(AssessmentFlowType.quick)
                        Text("Family Caregiver").tag(AssessmentFlowType.caregiver)
                        Text("Extended").tag(AssessmentFlowType.extended)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 500)
                }

                Spacer()

                // Big confirmation button
                Button {
                    performHandoff()
                } label: {
                    Text("Hand iPad to Patient")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 72)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(canHandoff ? MCDesign.Colors.primary700 : Color.gray)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canHandoff)
                .accessibilityHint("Records handoff timestamp and switches to patient view")
            }
            .padding(32)
        }
        .sheet(isPresented: $showQRScanner) {
            // Real QR scanner UIKit bridge is a post-v1 item. Stubbed for
            // now with a simulated scan that fills demo data.
            QRScanStubView { scanned in
                patientID = scanned.id
                displayName = scanned.name
                showQRScanner = false
            }
        }
    }

    // MARK: - Field row

    private func labeledField(
        title: String,
        text: Binding<String>,
        trailing: AnyView? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(MCDesign.Colors.textPrimary)
            HStack {
                TextField(title, text: text)
                    .font(.system(size: 20))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                if let t = trailing { t }
            }
        }
    }

    // MARK: - Handoff

    private func performHandoff() {
        let pid = patientID.trimmingCharacters(in: .whitespaces)
        let name = displayName.trimmingCharacters(in: .whitespaces)
        guard !pid.isEmpty, !name.isEmpty else { return }

        // Persist patient + language + audit.
        LongitudinalPatientStore.shared.upsert(
            id: pid,
            displayName: name,
            languagePreference: language
        )
        sttLanguage = language
        preselectedFlowRaw = flowType.rawValue
        AssessmentPersistence.recordHandoff(patientID: pid)

        onHandoffConfirmed(pid)
    }
}

// MARK: - QR stub

private struct ScannedPatient {
    let id: String
    let name: String
}

private struct QRScanStubView: View {
    let onScanned: (ScannedPatient) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("QR Scanner (stub)")
                .font(.system(size: 22, weight: .semibold))
            Text("Real camera scanner ships post-v1. Tap below to simulate a scan.")
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                onScanned(ScannedPatient(id: "DEMO-\(Int(Date().timeIntervalSince1970) % 100000)", name: "Demo Patient"))
            } label: {
                Text("Simulate scan")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.blue))
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
}
