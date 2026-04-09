//
//  AssessmentCard.swift
//  VoiceMiniCog
//
//  Reusable card component for the Home Screen assessment launcher.
//  Icon + title, HA-inspired shadow, staggered entrance, press animation.
//

import SwiftUI

struct AssessmentCard: View {
    let title: String
    let icon: String
    let accentColor: Color
    let staggerIndex: Int
    let action: () -> Void

    @State private var appeared = false
    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            VStack(spacing: 16) {
                // Icon circle
                ZStack {
                    RoundedRectangle(cornerRadius: MCDesign.Radius.medium)
                        .fill(
                            LinearGradient(
                                colors: [accentColor.opacity(0.13), accentColor.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)

                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(accentColor)
                }

                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(MCDesign.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .padding(.horizontal, 24)
            .background(MCDesign.Colors.surface)
            .cornerRadius(MCDesign.Radius.medium)
            .mcShadow(MCDesign.Shadow.card)
            .scaleEffect(isPressed ? 0.96 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in withAnimation(.spring(response: 0.15, dampingFraction: 0.85)) { isPressed = true } }
                .onEnded { _ in withAnimation(.spring(response: 0.15, dampingFraction: 0.85)) { isPressed = false } }
        )
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.easeOut(duration: 0.45).delay(Double(staggerIndex) * 0.12 + 0.2)) {
                    appeared = true
                }
            }
        }
    }
}

#Preview {
    HStack(spacing: 20) {
        AssessmentCard(title: "Quick\nAssessment", icon: "bolt.fill", accentColor: .blue, staggerIndex: 0) {}
        AssessmentCard(title: "Family / Caregiver\nQuestionnaire", icon: "person.2.fill", accentColor: .indigo, staggerIndex: 1) {}
        AssessmentCard(title: "Extended\nAssessment", icon: "list.clipboard.fill", accentColor: .green, staggerIndex: 2) {}
    }
    .padding(40)
    .background(Color(hex: "#F1F5F9"))
}
