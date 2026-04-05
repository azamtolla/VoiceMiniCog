//
//  AssessmentPersistence.swift
//  VoiceMiniCog
//
//  MARK: CLINICAL — assessment state persistence
//  Saves in-progress assessments so MAs can pause/resume when patients
//  are called out of rooms. Uses UserDefaults (encrypted via iOS Data Protection).
//

import Foundation

@MainActor
final class AssessmentPersistence {

    private static let storageKey = "mercycognitive.assessment.inProgress"

    // MARK: - Save

    /// Encodes the current assessment state to JSON and stores it in UserDefaults.
    static func save(_ state: AssessmentState) {
        do {
            let data = try JSONEncoder().encode(state)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            // Non-fatal — log and continue. The assessment keeps running in memory.
            print("[AssessmentPersistence] save failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Restore

    /// Attempts to decode a previously saved assessment. Returns nil if nothing
    /// is stored or if the JSON is corrupted (in which case the stale data is cleared).
    static func restore() -> AssessmentState? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return nil
        }
        do {
            let state = try JSONDecoder().decode(AssessmentState.self, from: data)
            return state
        } catch {
            // Corrupted — clear stale data and start fresh
            print("[AssessmentPersistence] restore failed (clearing): \(error.localizedDescription)")
            clear()
            return nil
        }
    }

    // MARK: - Clear

    /// Removes any persisted assessment data.
    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    // MARK: - Query

    /// Returns true if there is a persisted in-progress assessment.
    static func hasInProgressAssessment() -> Bool {
        UserDefaults.standard.data(forKey: storageKey) != nil
    }
}
