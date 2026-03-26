//
//  ContentView.swift
//  VoiceMiniCog
//

import SwiftUI

struct ContentView: View {
    @State private var isAssessmentActive = false
    @AppStorage("minicog.useAvatarLiveView") private var useAvatarLiveView = false

    var body: some View {
        NavigationStack {
            if isAssessmentActive {
                if useAvatarLiveView {
                    MiniCogLiveView(
                        isActive: $isAssessmentActive,
                        onRequestFallback: { useAvatarLiveView = false }
                    )
                } else {
                    AssessmentView(isActive: $isAssessmentActive)
                }
            } else {
                HomeView(onStart: {
                    isAssessmentActive = true
                })
            }
        }
    }
}

#Preview {
    ContentView()
}
