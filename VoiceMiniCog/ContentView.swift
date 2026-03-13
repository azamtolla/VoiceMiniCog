//
//  ContentView.swift
//  VoiceMiniCog
//

import SwiftUI

struct ContentView: View {
    @State private var isAssessmentActive = false

    var body: some View {
        NavigationStack {
            if isAssessmentActive {
                AssessmentView(isActive: $isAssessmentActive)
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
