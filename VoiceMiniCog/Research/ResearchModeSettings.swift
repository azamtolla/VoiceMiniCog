//
//  ResearchModeSettings.swift
//  VoiceMiniCog
//
//  MERIDIAN-1 Research Mode toggle.
//  Research-build only: wrapped in `#if DEBUG || RESEARCH` so research-mode
//  code is compiled out of the App Store binary and leaves no strings in
//  it. The `RESEARCH` flag is the forward path for a signed, non-DEBUG
//  institutional/TestFlight capture build (Execution Checklist Phase 2);
//  add `RESEARCH` to a dedicated build configuration's active compilation
//  conditions so the instrument ships in the signed research build without
//  DEBUG. Until that configuration exists this compiles exactly as before
//  (DEBUG only).
//
//  Two distinct identifiers, deliberately kept separate (2026-07-29 audit):
//   • siteStudyID  — a site/session gate token (e.g. "MERIDIAN-001"),
//                    validated on entry, NEVER written to a filename.
//   • participantID — the per-participant 5-character study code
//                    (Protocol 8.1), which becomes the stream filename
//                    prefix and the de-identification key. This is what
//                    RawStreamRecorder.beginTask consumes as activeStudyID.
//
//  Persistence: Keychain with a short session TTL, bound to device
//  (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) so the token
//  survives an unexpected reboot mid-visit but cannot migrate to another
//  device via encrypted backup. The TTL covers a single 30–45 min visit
//  plus a reboot margin — it is intentionally NOT overnight, so the
//  clinical app cannot remain structurally unreachable for hours. The
//  retest visit (Protocol 5.5) is a separate, fresh activation.
//
//  Call `deactivate()` after RawStreamRecorder confirms transfer to the
//  Mercy Health research drive (Section 8.2 post-session wipe).
//

#if DEBUG || RESEARCH
import Foundation
import Security

@Observable
class ResearchModeSettings {
    static let shared = ResearchModeSettings()

    private let keychainKey = "com.mercycognitive.research.sessionToken"
    private let ttlSeconds: TimeInterval = 2 * 3600  // one visit + reboot margin

    private(set) var isActive: Bool = false
    /// The per-participant 5-char study code that flows to the filename.
    private(set) var activeStudyID: String? = nil
    /// The site/session gate token; recorded in the manifest, never a path.
    private(set) var siteStudyID: String? = nil

    /// Valid site/session gate tokens. These gate entry to Research Mode;
    /// they are NOT participant IDs and are never written to disk. Rotate
    /// as sites/sessions require.
    static let selectableSiteTokens = ["MERIDIAN-001", "MERIDIAN-002", "MERIDIAN-003"]
    private static let validSiteTokens = Set(selectableSiteTokens)

    /// Participant code format: 5 chars, no confusable 0/O and 1/I/L
    /// (Execution Checklist study-ID generator).
    static let participantIDPattern = "^[A-HJ-NP-Z2-9]{5}$"

    init() { _ = loadFromKeychain() }

    /// Activate Research Mode for one participant. Gated on a valid site
    /// token AND a well-formed participant ID; the participant ID becomes
    /// `activeStudyID` and reaches the recorder/filename.
    func activate(siteToken: String, participantID: String) -> Bool {
        guard Self.validSiteTokens.contains(siteToken) else { return false }
        guard participantID.range(of: Self.participantIDPattern,
                                  options: .regularExpression) != nil else { return false }

        let expiry = Date().addingTimeInterval(ttlSeconds)
        let payload = "\(siteToken)|\(participantID)|\(expiry.timeIntervalSince1970)"
        guard let data = payload.data(using: .utf8) else { return false }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: keychainKey,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { return false }

        siteStudyID = siteToken
        activeStudyID = participantID
        isActive = true
        return true
    }

    func deactivate() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: keychainKey
        ]
        SecItemDelete(query as CFDictionary)
        siteStudyID = nil
        activeStudyID = nil
        isActive = false
    }

    @discardableResult
    private func loadFromKeychain() -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: keychainKey,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let payload = String(data: data, encoding: .utf8) else {
            isActive = false
            return false
        }
        let parts = payload.split(separator: "|")
        guard parts.count == 3,
              let expiryEpoch = TimeInterval(parts[2]),
              Date().timeIntervalSince1970 < expiryEpoch else {
            deactivate()   // expired or malformed — clean up
            return false
        }
        siteStudyID = String(parts[0])
        activeStudyID = String(parts[1])
        isActive = true
        return true
    }
}
#endif
