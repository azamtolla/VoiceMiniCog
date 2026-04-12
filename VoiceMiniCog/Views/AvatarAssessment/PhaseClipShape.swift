//
//  PhaseClipShape.swift
//  VoiceMiniCog
//
//  Animatable shape that morphs between RoundedRectangle and Circle.
//  Used to clip the persistent TavusCVIView during phase transitions.
//  iOS 15 compatible (no AnyShape dependency).
//

import SwiftUI

struct PhaseClipShape: Shape, InsettableShape {
    /// 0.0 = rounded rectangle, 1.0 = circle
    var circleProgress: CGFloat

    /// Inset amount for InsettableShape conformance (used by strokeBorder)
    var insetAmount: CGFloat = 0

    init(circleProgress: CGFloat) {
        self.circleProgress = circleProgress
        self.insetAmount = 0
    }

    var animatableData: CGFloat {
        get { circleProgress }
        set { circleProgress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let maxRadius = min(insetRect.width, insetRect.height) / 2
        let minRadius = max(AssessmentTheme.Avatar.videoCornerRadius - 2 - insetAmount, 0)
        let radius = minRadius + (maxRadius - minRadius) * circleProgress
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
            .path(in: insetRect)
    }

    func inset(by amount: CGFloat) -> PhaseClipShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}
