//
//  VoiceMiniCogApp.swift
//  VoiceMiniCog
//
//  Created by Azam Tolla on 3/12/26.
//

import SwiftUI

@main
struct VoiceMiniCogApp: App {
    #if DEBUG || RESEARCH
    // MERIDIAN-1 research-mode swap. @State anchors the App struct to
    // the shared @Observable singleton so `isActive` changes trigger
    // re-evaluation of the Scene body. The identity reset on swap is
    // deliberate: clinical and research view trees are mutually
    // exclusive, so any lingering clinical state is destroyed on
    // activation (and vice versa on deactivate()).
    @State private var settings = ResearchModeSettings.shared
    #endif

    var body: some Scene {
        WindowGroup {
            #if DEBUG || RESEARCH
            if settings.isActive {
                ResearchRootView()
            } else {
                // Clinical root, with the hidden staff activation entry
                // attached here so ContentView itself is never modified.
                ContentView()
                    .researchModeEntry()
            }
            #else
            ContentView()
            #endif
        }
    }
}
