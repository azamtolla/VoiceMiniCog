//
//  AssessmentPersistence.swift
//  VoiceMiniCog
//
//  MARK: CLINICAL — assessment state persistence
//  Saves in-progress assessments so MAs can pause/resume when patients
//  are called out of rooms. Uses UserDefaults (encrypted via iOS Data Protection).
//
//  Also records abandonment + partial-score metadata for report routing.
//  Partial QMCI is NOT a valid QMCI per O'Caoimh 2012 — the report must
//  render "ASSESSMENT INCOMPLETE — NOT SCORABLE" for any session that
//  ended before all six subtests completed.
//

import Foundation

@MainActor
final class AssessmentPersistence {

    // MARK: - Storage keys

    private static let storageKey         = "mercycognitive.assessment.inProgress"
    private static let flowTypeKey        = "mercycognitive.assessment.flowType"
    private static let abandonedAtKey     = "mercycognitive.assessment.abandonedAt"
    private static let completedSubtestsKey = "mercycognitive.assessment.completedSubtests"
    private static let shutdownReasonKey  = "mercycognitive.assessment.shutdownReason"
    private static let partialPolicyKey   = "mercycognitive.assessment.partialScorePolicy"
    private static let handoffTimestampKey = "mercycognitive.assessment.handoffAt"
    private static let handoffPatientIDKey = "mercycognitive.assessment.handoffPatientID"
    private static let caregiverFlagsKey   = "mercycognitive.assessment.caregiverFlags"

    // MARK: - Partial-Score Policy

    /// Drives how the report renders for a session that ended before all
    /// subtests completed.
    enum PartialScorePolicy: String, Codable {
        /// Hide all scores. Report shows "ASSESSMENT INCOMPLETE" only.
        case showNone
        /// Show only subtests the patient actually completed, for clinician
        /// reference. Not a composite score. NOT VALID against QMCI norms.
        case showCompletedOnly
        /// Mark completed subtests "for clinician review" — flag the session
        /// as requiring manual review before any clinical use.
        case flagForClinicianReview
    }

    // MARK: - Save

    static func save(_ state: AssessmentState, flowType: AssessmentFlowType? = nil) {
        do {
            let data = try JSONEncoder().encode(state)
            UserDefaults.standard.set(data, forKey: storageKey)
            if let flowType {
                UserDefaults.standard.set(flowType.rawValue, forKey: flowTypeKey)
            }
        } catch {
            print("[AssessmentPersistence] save failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Restore

    static func restore() -> AssessmentState? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(AssessmentState.self, from: data)
        } catch {
            print("[AssessmentPersistence] restore failed (clearing): \(error.localizedDescription)")
            clear()
            return nil
        }
    }

    static func restoreFlowType() -> AssessmentFlowType {
        guard let raw = UserDefaults.standard.string(forKey: flowTypeKey),
              let flowType = AssessmentFlowType(rawValue: raw) else {
            return .quick
        }
        return flowType
    }

    // MARK: - Abandonment

    /// Record the exact time + reason the session ended before all subtests
    /// completed. Called from the .sessionAbandoned observer in the app's
    /// main view.
    static func recordAbandonment(
        at date: Date = Date(),
        reason: SessionShutdownReason,
        completedSubtests: [Phase],
        policy: PartialScorePolicy = .flagForClinicianReview
    ) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: abandonedAtKey)
        UserDefaults.standard.set(reason.rawValue, forKey: shutdownReasonKey)
        UserDefaults.standard.set(
            completedSubtests.map(\.rawValue),
            forKey: completedSubtestsKey
        )
        UserDefaults.standard.set(policy.rawValue, forKey: partialPolicyKey)
    }

    static var abandonedAt: Date? {
        let t = UserDefaults.standard.double(forKey: abandonedAtKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    static var shutdownReason: SessionShutdownReason? {
        guard let raw = UserDefaults.standard.string(forKey: shutdownReasonKey) else {
            return nil
        }
        return SessionShutdownReason(rawValue: raw)
    }

    static var completedSubtests: [Phase] {
        let rawList = UserDefaults.standard.stringArray(forKey: completedSubtestsKey) ?? []
        return rawList.compactMap(Phase.init(rawValue:))
    }

    static var partialScorePolicy: PartialScorePolicy {
        guard let raw = UserDefaults.standard.string(forKey: partialPolicyKey),
              let p = PartialScorePolicy(rawValue: raw) else {
            return .flagForClinicianReview
        }
        return p
    }

    /// True when the last persisted session ended before all subtests finished.
    static var isPartialSession: Bool {
        guard let reason = shutdownReason else { return false }
        return reason.isPartial
    }

    // MARK: - MA Handoff audit

    /// Record the MA handoff timestamp + patient-id for the audit trail.
    /// Called when the MA taps "Hand iPad to Patient".
    static func recordHandoff(patientID: String, at date: Date = Date()) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: handoffTimestampKey)
        UserDefaults.standard.set(patientID, forKey: handoffPatientIDKey)
    }

    static var lastHandoffAt: Date? {
        let t = UserDefaults.standard.double(forKey: handoffTimestampKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    static var lastHandoffPatientID: String? {
        UserDefaults.standard.string(forKey: handoffPatientIDKey)
    }

    // MARK: - Caregiver flagged-answers

    /// Struct for a single clinician-flagged caregiver-assisted answer.
    struct CaregiverFlag: Codable, Identifiable {
        let id: UUID
        let timestamp: Date
        let phase: String    // Phase.rawValue at the time of the flag
        let note: String?    // optional clinician note
    }

    static func appendCaregiverFlag(phase: Phase, note: String? = nil) {
        let flag = CaregiverFlag(id: UUID(), timestamp: Date(), phase: phase.rawValue, note: note)
        var flags = caregiverFlags
        flags.append(flag)
        if let data = try? JSONEncoder().encode(flags) {
            UserDefaults.standard.set(data, forKey: caregiverFlagsKey)
        }
    }

    static var caregiverFlags: [CaregiverFlag] {
        guard let data = UserDefaults.standard.data(forKey: caregiverFlagsKey) else { return [] }
        return (try? JSONDecoder().decode([CaregiverFlag].self, from: data)) ?? []
    }

    // MARK: - Clear

    static func clear() {
        [storageKey, flowTypeKey, abandonedAtKey, completedSubtestsKey,
         shutdownReasonKey, partialPolicyKey, handoffTimestampKey,
         handoffPatientIDKey, caregiverFlagsKey]
            .forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    // MARK: - Query

    static func hasInProgressAssessment() -> Bool {
        UserDefaults.standard.data(forKey: storageKey) != nil
    }
}
