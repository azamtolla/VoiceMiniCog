//
//  HomeView.swift
//  VoiceMiniCog
//
//  Clinical Workflows dashboard matching React MercyCognitive
//

import SwiftUI

struct HomeView: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            headerBar

            // Main content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Patient banner
                    patientBanner

                    // Clinical Workflows section
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Clinical Workflows")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(MercyColors.gray800)
                            Text("Select a pathway to begin")
                                .font(.system(size: 14))
                                .foregroundColor(MercyColors.gray500)
                        }

                        Spacer()

                        // AI Assistant button
                        Button(action: {}) {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 12))
                                Text("AI Assistant")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(MercyColors.mercyGreen)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(MercyColors.mercyGreen.opacity(0.1))
                            .cornerRadius(16)
                        }
                    }
                    .padding(.horizontal, 24)

                    // Workflow cards grid
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16)
                    ], spacing: 16) {
                        // Voice Mini-Cog card (primary)
                        WorkflowCard(
                            icon: "mic.fill",
                            iconBgColor: MercyColors.mercyBlue,
                            title: "Voice Mini-Cog",
                            duration: "~5 min",
                            tags: ["AI-Guided"],
                            status: .notStarted,
                            isPrimary: true,
                            action: onStart
                        )

                        // Primary Care
                        WorkflowCard(
                            icon: "list.clipboard",
                            iconBgColor: Color(hex: "#3B82F6"),
                            title: "Primary Care",
                            duration: "~20 min",
                            tags: ["G0438/G0439"],
                            status: .notStarted,
                            action: {}
                        )

                        // Neurology
                        WorkflowCard(
                            icon: "brain.head.profile",
                            iconBgColor: Color(hex: "#10B981"),
                            title: "Neurology",
                            duration: "~45 min",
                            tags: ["Cognitive"],
                            status: .notStarted,
                            action: {}
                        )

                        // Rehab Services
                        WorkflowCard(
                            icon: "figure.walk",
                            iconBgColor: Color(hex: "#F43F5E"),
                            title: "Rehab Services",
                            duration: nil,
                            tags: ["PT", "OT", "Speech"],
                            status: .notStarted,
                            action: {}
                        )

                        // Wellness & Mood
                        WorkflowCard(
                            icon: "heart.fill",
                            iconBgColor: Color(hex: "#A855F7"),
                            title: "Wellness & Mood",
                            duration: nil,
                            tags: ["PHQ", "GAD", "AUDIT"],
                            status: .notStarted,
                            action: {}
                        )

                        // Sensory
                        WorkflowCard(
                            icon: "ear",
                            iconBgColor: Color(hex: "#06B6D4"),
                            title: "Sensory",
                            duration: nil,
                            tags: ["Hearing", "Vision"],
                            status: .notStarted,
                            action: {}
                        )

                        // Driver Safety
                        WorkflowCard(
                            icon: "car.fill",
                            iconBgColor: Color(hex: "#F59E0B"),
                            title: "Driver Safety",
                            duration: "~5 min",
                            tags: ["Screening"],
                            status: .notStarted,
                            action: {}
                        )

                        // Track Results
                        WorkflowCard(
                            icon: "chart.line.uptrend.xyaxis",
                            iconBgColor: Color(hex: "#6366F1"),
                            title: "Track Results",
                            duration: nil,
                            tags: ["Charts", "Longitudinal"],
                            status: .notStarted,
                            action: {}
                        )
                    }
                    .padding(.horizontal, 24)

                    Spacer(minLength: 40)
                }
                .padding(.top, 16)
            }
            .background(
                LinearGradient(
                    colors: [Color(hex: "#F0F4F8"), Color(hex: "#E8F0F8")],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 16) {
            // Logo
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(MercyColors.mercyBlue.opacity(0.1))
                        .frame(width: 36, height: 36)

                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 18))
                        .foregroundColor(MercyColors.mercyBlue)
                }

                Text("MERCY WELLNESS")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(MercyColors.mercyBlue)
            }

            Spacer()

            // Status badges
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 12))
                    Text("Wellness Mode")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(MercyColors.mercyGreen)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(MercyColors.mercyGreen.opacity(0.1))
                .cornerRadius(16)

                HStack(spacing: 4) {
                    Circle()
                        .fill(MercyColors.mercyGreen)
                        .frame(width: 6, height: 6)
                    Text("Epic Connected")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(MercyColors.mercyGreen)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(MercyColors.mercyGreen.opacity(0.1))
                .cornerRadius(16)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("Clinical Workspace")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(MercyColors.gray700)
                Text("Clinician")
                    .font(.system(size: 12))
                    .foregroundColor(MercyColors.gray500)
            }

            Image(systemName: "chevron.down")
                .font(.system(size: 12))
                .foregroundColor(MercyColors.gray400)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Color.white)
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }

    // MARK: - Patient Banner

    private var patientBanner: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hex: "#FEE2E2"))
                    .frame(width: 36, height: 36)

                Image(systemName: "person.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: "#EF4444"))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("No patient selected")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: "#DC2626"))
                Text("Launch from Epic to load patient context.")
                    .font(.system(size: 13))
                    .foregroundColor(MercyColors.gray500)
            }

            Spacer()
        }
        .padding(16)
        .background(Color(hex: "#FEF2F2"))
        .cornerRadius(12)
        .padding(.horizontal, 24)
    }
}

// MARK: - Workflow Status

enum WorkflowStatus {
    case notStarted
    case inProgress
    case completed
}

// MARK: - Workflow Card

struct WorkflowCard: View {
    let icon: String
    let iconBgColor: Color
    let title: String
    let duration: String?
    let tags: [String]
    let status: WorkflowStatus
    var isPrimary: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                // Status badge
                HStack {
                    Spacer()
                    statusBadge
                }

                // Icon
                ZStack {
                    Circle()
                        .fill(iconBgColor.opacity(0.15))
                        .frame(width: 48, height: 48)

                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundColor(iconBgColor)
                }

                // Title
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(MercyColors.gray800)

                // Duration and tags
                HStack(spacing: 8) {
                    if let duration = duration {
                        Text(duration)
                            .font(.system(size: 12))
                            .foregroundColor(MercyColors.gray400)
                    }

                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(MercyColors.gray500)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(MercyColors.gray100)
                            .cornerRadius(4)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(Color.white)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isPrimary ? iconBgColor : MercyColors.gray200, lineWidth: isPrimary ? 2 : 1)
            )
            .shadow(color: .black.opacity(0.03), radius: 4, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(statusText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(statusColor)
        }
    }

    private var statusColor: Color {
        switch status {
        case .notStarted: return MercyColors.gray400
        case .inProgress: return Color(hex: "#F59E0B")
        case .completed: return MercyColors.success
        }
    }

    private var statusText: String {
        switch status {
        case .notStarted: return "Not Started"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        }
    }
}

#Preview {
    HomeView(onStart: {})
}
