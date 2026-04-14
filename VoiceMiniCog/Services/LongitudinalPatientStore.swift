//
//  LongitudinalPatientStore.swift
//  VoiceMiniCog
//
//  App-side patient longitudinal database. Stored locally in iOS Data
//  Protection-encrypted UserDefaults (v1) — will move to SwiftData when
//  Mercy Health ships a HIPAA-compliant sync backend.
//
//  CLINICAL RULES:
//  1. Store only identifying convenience + logistical prefs:
//       - displayName (what the patient calls themselves)
//       - languagePreference (en-US / es-US)
//       - priorDifficultyFlags (e.g., "hearing aid", "left-handed")
//  2. NEVER store prior assessment scores here.
//  3. Prior-session scores go to the PCP report DB only, NEVER reach the
//     avatar's LLM context. This is a reproducibility requirement — the
//     avatar must behave identically across sessions regardless of a
//     patient's prior performance.
//  4. When injecting into conversation_context at session start, use
//     `conversationContextHeader(for:)` — it gates what's safe to surface.
//

import Foundation

public struct LongitudinalPatient: Codable, Identifiable, Equatable {
    public let id: String                  // patient_id as entered on MA handoff
    public var displayName: String         // "Mr. Johnson"
    public var languagePreference: String  // "en-US", "es-US"
    public var priorDifficultyFlags: [String]  // logistical ONLY, not cognitive
    public var lastSeen: Date
    public var createdAt: Date
}

@MainActor
final class LongitudinalPatientStore {

    private static let storageKey = "voiceMiniCog.longitudinal.patients"

    static let shared = LongitudinalPatientStore()

    private init() {}

    // MARK: - CRUD

    private func loadAll() -> [String: LongitudinalPatient] {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else { return [:] }
        return (try? JSONDecoder().decode([String: LongitudinalPatient].self, from: data)) ?? [:]
    }

    private func saveAll(_ all: [String: LongitudinalPatient]) {
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    /// Fetch or create a patient record. Called from MA handoff after the
    /// MA enters / scans patient_id. If the id is new, creates a record
    /// with the supplied name + language.
    @discardableResult
    func upsert(
        id: String,
        displayName: String,
        languagePreference: String
    ) -> LongitudinalPatient {
        var all = loadAll()
        if var existing = all[id] {
            existing.displayName = displayName
            existing.languagePreference = languagePreference
            existing.lastSeen = Date()
            all[id] = existing
            saveAll(all)
            return existing
        } else {
            let newPatient = LongitudinalPatient(
                id: id,
                displayName: displayName,
                languagePreference: languagePreference,
                priorDifficultyFlags: [],
                lastSeen: Date(),
                createdAt: Date()
            )
            all[id] = newPatient
            saveAll(all)
            return newPatient
        }
    }

    func fetch(id: String) -> LongitudinalPatient? {
        loadAll()[id]
    }

    func addDifficultyFlag(patientID: String, flag: String) {
        var all = loadAll()
        guard var p = all[patientID] else { return }
        if !p.priorDifficultyFlags.contains(flag) {
            p.priorDifficultyFlags.append(flag)
            all[patientID] = p
            saveAll(all)
        }
    }

    func removeDifficultyFlag(patientID: String, flag: String) {
        var all = loadAll()
        guard var p = all[patientID] else { return }
        p.priorDifficultyFlags.removeAll { $0 == flag }
        all[patientID] = p
        saveAll(all)
    }

    /// All patients, sorted by lastSeen desc. For clinician dashboard browsing.
    func allPatients() -> [LongitudinalPatient] {
        loadAll().values.sorted { $0.lastSeen > $1.lastSeen }
    }

    // MARK: - LLM context gate
    //
    // The ONLY safe per-patient context to inject at session start is
    // identifying-convenience data. Prior scores or performance MUST NOT
    // be mentioned.

    /// Build a conversation_context prefix for the avatar. Returns nil if
    /// no patient record exists. Inject via `avatarSetContext` at
    /// session-start (intro phase only).
    func conversationContextHeader(for patientID: String) -> String? {
        guard let p = fetch(id: patientID) else { return nil }

        var lines: [String] = []
        lines.append("PATIENT CONTEXT (identifying convenience only — NEVER mention prior performance or prior sessions):")
        lines.append("- Patient prefers to be called: \(p.displayName).")
        lines.append("- Primary language: \(p.languagePreference).")
        if !p.priorDifficultyFlags.isEmpty {
            lines.append("- Logistical notes: \(p.priorDifficultyFlags.joined(separator: ", ")).")
        }
        lines.append("IMPORTANT: Do NOT reference prior assessments, prior scores, or prior performance in any way. Treat every session as the first.")
        return lines.joined(separator: "\n")
    }
}
