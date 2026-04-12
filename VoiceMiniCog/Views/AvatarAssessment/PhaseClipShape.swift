//
//  PhaseClipShape.swift
//  VoiceMiniCog
//
//  Animatable shape that morphs between RoundedRectangle and Circle.
//  Used to clip the persistent TavusCVIView during phase transitions.
//  iOS 15 compatible (no AnyShape dependency).
//

import SwiftUI

struct PhaseClipShape: Shape {
    /// 0.0 = rounded rectangle, 1.0 = circle
    var circleProgress: CGFloat

    var animatableData: CGFloat {
        get { circleProgress }
        set { circleProgress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let maxRadius = min(rect.width, rect.height) / 2
        let minRadius = AssessmentTheme.Avatar.videoCornerRadius - 2
        let radius = minRadius + (maxRadius - minRadius) * circleProgress
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
            .path(in: rect)
    }
}
