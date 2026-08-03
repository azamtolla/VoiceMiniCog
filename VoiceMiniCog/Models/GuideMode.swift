//
//  GuideMode.swift
//  VoiceMiniCog
//
//  Which guide administers the assessment: pre-rendered voice (default)
//  or the Tavus video avatar (requires configured API key).
//  Spec: docs/superpowers/specs/2026-08-03-voice-mode-pre-rendered-design.md
//

import Foundation

enum GuideMode: String, CaseIterable, Identifiable {
    case voice
    case avatar

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .voice:  return "Voice (recommended)"
        case .avatar: return "Video avatar (requires Tavus)"
        }
    }

    /// UserDefaults key for the user's stored preference.
    static let storageKey = "guideMode"

    /// Resolve the effective mode. Avatar is only usable with a Tavus key;
    /// an unusable stored choice degrades to .voice, never the reverse.
    static func resolved(storedRawValue: String?, tavusKeyConfigured: Bool) -> GuideMode {
        let stored = storedRawValue.flatMap(GuideMode.init(rawValue:))
        switch (stored, tavusKeyConfigured) {
        case (.voice, _):        return .voice
        case (.avatar, true):    return .avatar
        case (.avatar, false):   return .voice
        case (nil, true):        return .avatar
        case (nil, false):       return .voice
        }
    }
}
