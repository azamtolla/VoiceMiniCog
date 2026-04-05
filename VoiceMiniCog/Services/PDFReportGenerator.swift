//
//  PDFReportGenerator.swift
//  VoiceMiniCog
//
//  Generates a clinical PDF report from AssessmentState using UIKit's
//  UIGraphicsPDFRenderer.  Letter-size (8.5 x 11"), single accent color
//  (#1a5276 navy-teal), designed for printing in primary care.
//
//  IMPORTANT: This PDF shows performance scores only — no diagnostic labels
//  such as "MCI" or "dementia." The composite risk tier is shown with the
//  required clinical disclaimer.
//

import UIKit

// MARK: - PDFReportGenerator

struct PDFReportGenerator {

    // MARK: Constants

    /// US Letter in points (72 pt/in)
    private static let pageWidth: CGFloat  = 612
    private static let pageHeight: CGFloat = 792
    private static let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

    private static let marginLeft: CGFloat   = 48
    private static let marginRight: CGFloat  = 48
    private static let marginTop: CGFloat    = 44
    private static let marginBottom: CGFloat = 52
    private static let contentWidth: CGFloat = pageWidth - marginLeft - marginRight

    // Accent colour — Mercy Health navy-teal
    private static let accent = UIColor(red: 0x1A/255, green: 0x52/255, blue: 0x76/255, alpha: 1)
    private static let accentLight = UIColor(red: 0x1A/255, green: 0x52/255, blue: 0x76/255, alpha: 0.08)

    // Semantic colours
    private static let successColor = UIColor(red: 0x05/255, green: 0x96/255, blue: 0x69/255, alpha: 1)
    private static let warningColor = UIColor(red: 0xD9/255, green: 0x77/255, blue: 0x06/255, alpha: 1)
    private static let errorColor   = UIColor(red: 0xDC/255, green: 0x26/255, blue: 0x26/255, alpha: 1)

    private static let textPrimary   = UIColor(red: 0x1E/255, green: 0x29/255, blue: 0x3B/255, alpha: 1)
    private static let textSecondary = UIColor(red: 0x47/255, green: 0x55/255, blue: 0x69/255, alpha: 1)
    private static let textTertiary  = UIColor(red: 0x94/255, green: 0xA3/255, blue: 0xB8/255, alpha: 1)
    private static let borderColor   = UIColor(red: 0xE2/255, green: 0xE8/255, blue: 0xF0/255, alpha: 1)

    // Fonts
    private static let titleFont       = UIFont.systemFont(ofSize: 18, weight: .bold)
    private static let headingFont     = UIFont.systemFont(ofSize: 13, weight: .semibold)
    private static let bodyFont        = UIFont.systemFont(ofSize: 11, weight: .regular)
    private static let bodyBoldFont    = UIFont.systemFont(ofSize: 11, weight: .semibold)
    private static let captionFont     = UIFont.systemFont(ofSize: 9.5, weight: .regular)
    private static let captionBoldFont = UIFont.systemFont(ofSize: 9.5, weight: .semibold)
    private static let monoFont        = UIFont.monospacedSystemFont(ofSize: 10, weight: .medium)
    private static let scoreLargeFont  = UIFont.systemFont(ofSize: 28, weight: .bold)

    // MARK: - Public API

    /// Generate PDF Data from the current assessment state.
    static func generate(from state: AssessmentState) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        var y: CGFloat = 0

        let data = renderer.pdfData { context in
            // --- Page 1 ---
            context.beginPage()
            y = marginTop

            y = drawHeader(y: y)
            y = drawRiskBanner(y: y, state: state)
            y = drawCognitiveProfile(y: y, state: state)
            y = drawQDRSSection(y: y, state: state)
            y = drawPHQ2Section(y: y, state: state)

            // Clock image — may need a new page
            if state.clockImage != nil || state.clockAnalysis != nil {
                if y > pageHeight - marginBottom - 140 {
                    drawFooter()
                    context.beginPage()
                    y = marginTop
                }
                y = drawClockSection(y: y, state: state)
            }

            // Amyloid triage
            if let triage = state.amyloidTriage {
                if y > pageHeight - marginBottom - 140 {
                    drawFooter()
                    context.beginPage()
                    y = marginTop
                }
                y = drawAmyloidSection(y: y, triage: triage)
            }

            // Orders
            if y > pageHeight - marginBottom - 120 {
                drawFooter()
                context.beginPage()
                y = marginTop
            }
            y = drawOrdersSection(y: y, state: state)

            // Billing
            if y > pageHeight - marginBottom - 80 {
                drawFooter()
                context.beginPage()
                y = marginTop
            }
            y = drawBillingSection(y: y, state: state)

            drawFooter()
        }
        return data
    }

    // MARK: - Header

    private static func drawHeader(y: CGFloat) -> CGFloat {
        var cy = y
        let title = "MercyCognitive Cognitive Screening Report"
        let attrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: accent]
        let titleSize = (title as NSString).size(withAttributes: attrs)
        (title as NSString).draw(at: CGPoint(x: marginLeft, y: cy), withAttributes: attrs)
        cy += titleSize.height + 4

        // Date
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short
        let dateStr = "Date: \(dateFormatter.string(from: Date()))"
        drawText(dateStr, at: CGPoint(x: marginLeft, y: cy), font: captionFont, color: textSecondary)
        cy += 14

        // Divider
        cy += 4
        drawHorizontalLine(y: cy, color: accent, thickness: 2)
        cy += 8

        // Disclaimer
        let disclaimer = "These results reflect patient performance on a standardized cognitive assessment. Clinical diagnosis of MCI or dementia requires physician evaluation."
        cy = drawWrappedText(disclaimer, x: marginLeft, y: cy, width: contentWidth,
                             font: captionFont, color: textSecondary, lineSpacing: 2)
        cy += 12
        return cy
    }

    // MARK: - Risk Banner

    private static func drawRiskBanner(y: CGFloat, state: AssessmentState) -> CGFloat {
        guard let risk = state.compositeRisk else { return y }
        var cy = y

        let bannerColor: UIColor
        switch risk.tier {
        case .low: bannerColor = successColor
        case .intermediate: bannerColor = warningColor
        case .high: bannerColor = errorColor
        }

        let bannerHeight: CGFloat = 56
        let bannerRect = CGRect(x: marginLeft, y: cy, width: contentWidth, height: bannerHeight)

        // Banner background (light tint)
        let ctx = UIGraphicsGetCurrentContext()!
        ctx.saveGState()
        ctx.setFillColor(bannerColor.withAlphaComponent(0.08).cgColor)
        let roundedPath = UIBezierPath(roundedRect: bannerRect, cornerRadius: 6)
        ctx.addPath(roundedPath.cgPath)
        ctx.fillPath()

        // Left accent strip
        let stripRect = CGRect(x: marginLeft, y: cy, width: 5, height: bannerHeight)
        ctx.setFillColor(bannerColor.cgColor)
        let stripPath = UIBezierPath(roundedRect: stripRect, byRoundingCorners: [.topLeft, .bottomLeft],
                                      cornerRadii: CGSize(width: 6, height: 6))
        ctx.addPath(stripPath.cgPath)
        ctx.fillPath()
        ctx.restoreGState()

        // Tier label
        let tierText = risk.tier.rawValue.uppercased() + " RISK"
        let tierAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 14, weight: .bold),
                                                         .foregroundColor: bannerColor]
        (tierText as NSString).draw(at: CGPoint(x: marginLeft + 14, y: cy + 8), withAttributes: tierAttrs)

        // Label
        drawText(risk.label, at: CGPoint(x: marginLeft + 14, y: cy + 28), font: bodyFont, color: textPrimary)

        // Summary on right side
        let summaryWidth: CGFloat = contentWidth * 0.5
        let summaryX = marginLeft + contentWidth - summaryWidth
        _ = drawWrappedText(risk.summaryLine, x: summaryX, y: cy + 8, width: summaryWidth,
                            font: captionFont, color: textSecondary, lineSpacing: 2)

        cy += bannerHeight + 8

        // Narrative (if present)
        if !risk.narrative.isEmpty {
            cy = drawWrappedText(risk.narrative, x: marginLeft, y: cy, width: contentWidth,
                                 font: captionFont, color: textSecondary, lineSpacing: 2)
            cy += 6
        }

        cy += 8
        return cy
    }

    // MARK: - Cognitive Profile (Qmci)

    private static func drawCognitiveProfile(y: CGFloat, state: AssessmentState) -> CGFloat {
        var cy = y
        cy = drawSectionHeader("Cognitive Profile (Qmci)", y: cy)

        let q = state.qmciState

        // Total score
        let totalStr = "\(q.totalScore)"
        let totalAttrs: [NSAttributedString.Key: Any] = [.font: scoreLargeFont, .foregroundColor: accent]
        (totalStr as NSString).draw(at: CGPoint(x: marginLeft, y: cy), withAttributes: totalAttrs)
        let totalSize = (totalStr as NSString).size(withAttributes: totalAttrs)
        drawText("/ 100", at: CGPoint(x: marginLeft + totalSize.width + 4, y: cy + 10),
                 font: bodyFont, color: textTertiary)
        cy += totalSize.height + 8

        // Subtest bars
        let subtests: [(name: String, score: Int, max: Int)] = [
            ("Orientation",    q.orientationScore,    10),
            ("Word Learning",  q.registrationScore,   5),
            ("Clock Drawing",  q.clockDrawingScore,   15),
            ("Verbal Fluency", q.verbalFluencyScore,  20),
            ("Story Recall",   q.logicalMemoryScore,  30),
            ("Word Recall",    q.delayedRecallScore,  20),
        ]

        let barHeight: CGFloat = 10
        let labelWidth: CGFloat = 100
        let scoreWidth: CGFloat = 44
        let barX = marginLeft + labelWidth + 8
        let barWidth = contentWidth - labelWidth - scoreWidth - 16

        for subtest in subtests {
            // Label
            drawText(subtest.name, at: CGPoint(x: marginLeft, y: cy), font: captionFont, color: textPrimary)

            // Bar background
            let bgRect = CGRect(x: barX, y: cy + 2, width: barWidth, height: barHeight)
            let ctx = UIGraphicsGetCurrentContext()!
            ctx.setFillColor(borderColor.cgColor)
            ctx.fill(bgRect)

            // Bar fill
            let fillWidth = subtest.max > 0 ? barWidth * CGFloat(subtest.score) / CGFloat(subtest.max) : 0
            let fillRect = CGRect(x: barX, y: cy + 2, width: fillWidth, height: barHeight)
            ctx.setFillColor(accent.cgColor)
            ctx.fill(fillRect)

            // Score text
            let scoreStr = "\(subtest.score)/\(subtest.max)"
            drawText(scoreStr, at: CGPoint(x: barX + barWidth + 8, y: cy), font: monoFont, color: textSecondary)

            cy += barHeight + 8
        }

        cy += 8
        return cy
    }

    // MARK: - QDRS

    private static func drawQDRSSection(y: CGFloat, state: AssessmentState) -> CGFloat {
        guard state.qdrsState.answeredCount > 0 else { return y }
        var cy = y
        cy = drawSectionHeader("QDRS Patient-Reported", y: cy)

        let totalStr = String(format: "%.1f", state.qdrsState.totalScore)
        drawText("\(totalStr) / 10", at: CGPoint(x: marginLeft, y: cy), font: bodyBoldFont, color: textPrimary)
        let riskLabel = state.qdrsState.riskLabel
        drawText("  —  \(riskLabel)", at: CGPoint(x: marginLeft + 80, y: cy), font: bodyFont, color: textSecondary)
        cy += 16

        let flagged = state.qdrsState.flaggedDomains
        if !flagged.isEmpty {
            drawText("Flagged Domains:", at: CGPoint(x: marginLeft, y: cy), font: captionBoldFont, color: textSecondary)
            cy += 14
            let domainStr = flagged.map { "  \u{2022} \($0)" }.joined(separator: "\n")
            cy = drawWrappedText(domainStr, x: marginLeft, y: cy, width: contentWidth,
                                 font: captionFont, color: textPrimary, lineSpacing: 3)
            cy += 4
        }

        cy += 10
        return cy
    }

    // MARK: - PHQ-2

    private static func drawPHQ2Section(y: CGFloat, state: AssessmentState) -> CGFloat {
        guard state.phq2State.isComplete else { return y }
        var cy = y
        cy = drawSectionHeader("Depression Screen (PHQ-2)", y: cy)

        let score = state.phq2State.totalScore
        let positive = state.phq2State.isPositive
        let color = positive ? warningColor : successColor
        let statusStr = positive ? "Positive — Consider PHQ-9" : "Negative"

        drawText("\(score)/6", at: CGPoint(x: marginLeft, y: cy), font: bodyBoldFont, color: color)
        drawText("  —  \(statusStr)", at: CGPoint(x: marginLeft + 40, y: cy), font: bodyFont, color: color)
        cy += 20
        return cy
    }

    // MARK: - Clock Drawing

    private static func drawClockSection(y: CGFloat, state: AssessmentState) -> CGFloat {
        var cy = y
        cy = drawSectionHeader("Clock Drawing", y: cy)

        let startX = marginLeft
        var imageEndX = startX

        // Draw clock image if available
        if let img = state.clockImage {
            let maxDim: CGFloat = 100
            let aspect = img.size.width / img.size.height
            let imgW = aspect >= 1 ? maxDim : maxDim * aspect
            let imgH = aspect >= 1 ? maxDim / aspect : maxDim
            let imgRect = CGRect(x: startX, y: cy, width: imgW, height: imgH)
            img.draw(in: imgRect)

            // Border
            let ctx = UIGraphicsGetCurrentContext()!
            ctx.setStrokeColor(borderColor.cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(imgRect)

            imageEndX = startX + imgW + 12
            let textY = cy
            if let score = state.clockScore {
                drawText("Score: \(score)/2", at: CGPoint(x: imageEndX, y: textY), font: bodyBoldFont, color: textPrimary)
            }
            if let analysis = state.clockAnalysis {
                drawText(analysis.severity, at: CGPoint(x: imageEndX, y: textY + 16), font: captionFont, color: textSecondary)
                drawText("Shulman \(analysis.shulmanRange)", at: CGPoint(x: imageEndX, y: textY + 30), font: captionFont, color: textSecondary)
            }
            cy += max(imgH, 48) + 8
        } else {
            if let score = state.clockScore {
                drawText("Score: \(score)/2", at: CGPoint(x: startX, y: cy), font: bodyBoldFont, color: textPrimary)
                cy += 16
            }
            if let analysis = state.clockAnalysis {
                drawText("\(analysis.severity) — Shulman \(analysis.shulmanRange)",
                         at: CGPoint(x: startX, y: cy), font: captionFont, color: textSecondary)
                cy += 16
            }
        }

        cy += 8
        return cy
    }

    // MARK: - Anti-Amyloid Eligibility

    private static func drawAmyloidSection(y: CGFloat, triage: AmyloidTriageResult) -> CGFloat {
        var cy = y
        cy = drawSectionHeader("Anti-Amyloid Therapy Eligibility", y: cy)

        // Status
        let statusColor: UIColor
        switch triage.eligibility {
        case .candidate: statusColor = accent
        case .notEligible: statusColor = textSecondary
        case .needsFurtherEval: statusColor = warningColor
        case .tooImpaired: statusColor = errorColor
        }
        drawText(triage.eligibility.rawValue, at: CGPoint(x: marginLeft, y: cy), font: bodyBoldFont, color: statusColor)
        cy += 18

        // Checklist
        for item in triage.checklist {
            let icon: String
            let iconColor: UIColor
            switch item.status {
            case .met: icon = "\u{2713}"; iconColor = successColor
            case .notMet: icon = "\u{2717}"; iconColor = errorColor
            case .needsReview: icon = "\u{26A0}"; iconColor = warningColor
            case .notAssessed: icon = "\u{2014}"; iconColor = textTertiary
            }
            drawText(icon, at: CGPoint(x: marginLeft, y: cy), font: bodyFont, color: iconColor)
            drawText(item.label, at: CGPoint(x: marginLeft + 18, y: cy), font: captionBoldFont, color: textPrimary)
            drawText(item.detail, at: CGPoint(x: marginLeft + 18, y: cy + 13), font: captionFont, color: textSecondary)
            cy += 28
        }

        // Next steps
        if !triage.nextSteps.isEmpty {
            drawText("Next Steps:", at: CGPoint(x: marginLeft, y: cy), font: captionBoldFont, color: textSecondary)
            cy += 14
            for step in triage.nextSteps {
                drawText("\u{2022} \(step)", at: CGPoint(x: marginLeft + 8, y: cy), font: captionFont, color: textPrimary)
                cy += 14
            }
        }

        cy += 8
        return cy
    }

    // MARK: - Recommended Orders

    private static func drawOrdersSection(y: CGFloat, state: AssessmentState) -> CGFloat {
        var cy = y
        cy = drawSectionHeader("Recommended Orders", y: cy)

        if state.workupOrders.isEmpty {
            drawText("No orders generated.", at: CGPoint(x: marginLeft, y: cy), font: captionFont, color: textTertiary)
            cy += 16
            return cy
        }

        // Table header
        let nameX = marginLeft
        let priorityX = marginLeft + contentWidth - 70
        drawText("Order", at: CGPoint(x: nameX, y: cy), font: captionBoldFont, color: textSecondary)
        drawText("Priority", at: CGPoint(x: priorityX, y: cy), font: captionBoldFont, color: textSecondary)
        cy += 14
        drawHorizontalLine(y: cy, color: borderColor, thickness: 0.5)
        cy += 4

        for order in state.workupOrders {
            let priorityStr: String
            let priorityColor: UIColor
            switch order.priority {
            case .required: priorityStr = "Required"; priorityColor = errorColor
            case .recommended: priorityStr = "Rec'd"; priorityColor = warningColor
            case .optional: priorityStr = "Optional"; priorityColor = textTertiary
            }

            let checkmark = order.isSelected ? "\u{2611}" : "\u{2610}"
            drawText(checkmark, at: CGPoint(x: nameX, y: cy), font: bodyFont, color: accent)
            drawText(order.name, at: CGPoint(x: nameX + 18, y: cy), font: captionBoldFont, color: textPrimary)
            drawText(priorityStr, at: CGPoint(x: priorityX, y: cy), font: captionBoldFont, color: priorityColor)
            cy += 13
            drawText(order.rationale, at: CGPoint(x: nameX + 18, y: cy), font: captionFont, color: textSecondary)
            cy += 16
        }

        cy += 8
        return cy
    }

    // MARK: - Billing Codes

    private static func drawBillingSection(y: CGFloat, state: AssessmentState) -> CGFloat {
        var cy = y
        cy = drawSectionHeader("Billing & ICD-10", y: cy)

        if state.qmciState.classification.isPositive {
            cy = drawCodeRow(code: "99483", label: "Cognitive Assessment & Care Plan (positive screen)", y: cy)
        }
        cy = drawCodeRow(code: "G0439", label: "Annual Wellness Visit (subsequent)", y: cy)
        cy = drawCodeRow(code: state.suggestedICD10, label: "Suggested diagnosis code", y: cy)

        cy += 8
        return cy
    }

    private static func drawCodeRow(code: String, label: String, y: CGFloat) -> CGFloat {
        var cy = y
        // Code badge
        let codeAttrs: [NSAttributedString.Key: Any] = [.font: monoFont, .foregroundColor: accent]
        let codeSize = (code as NSString).size(withAttributes: codeAttrs)

        let badgeRect = CGRect(x: marginLeft, y: cy - 1, width: codeSize.width + 10, height: codeSize.height + 4)
        let ctx = UIGraphicsGetCurrentContext()!
        ctx.saveGState()
        ctx.setFillColor(accentLight.cgColor)
        let badgePath = UIBezierPath(roundedRect: badgeRect, cornerRadius: 3)
        ctx.addPath(badgePath.cgPath)
        ctx.fillPath()
        ctx.restoreGState()

        (code as NSString).draw(at: CGPoint(x: marginLeft + 5, y: cy + 1), withAttributes: codeAttrs)

        // Label
        drawText(label, at: CGPoint(x: marginLeft + badgeRect.width + 10, y: cy + 1),
                 font: captionFont, color: textSecondary)
        cy += max(codeSize.height + 6, 16) + 4
        return cy
    }

    // MARK: - Footer

    private static func drawFooter() {
        let footerText = "Generated by MercyCognitive v4.0  |  For clinical use only  |  Not a diagnosis"
        let attrs: [NSAttributedString.Key: Any] = [.font: captionFont, .foregroundColor: textTertiary]
        let size = (footerText as NSString).size(withAttributes: attrs)
        let x = (pageWidth - size.width) / 2
        let footerY = pageHeight - marginBottom + 8
        drawHorizontalLine(y: footerY - 4, color: borderColor, thickness: 0.5)
        (footerText as NSString).draw(at: CGPoint(x: x, y: footerY), withAttributes: attrs)
    }

    // MARK: - Drawing Helpers

    private static func drawText(_ text: String, at point: CGPoint, font: UIFont, color: UIColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        (text as NSString).draw(at: point, withAttributes: attrs)
    }

    private static func drawSectionHeader(_ title: String, y: CGFloat) -> CGFloat {
        var cy = y
        // Accent bar
        let ctx = UIGraphicsGetCurrentContext()!
        ctx.setFillColor(accent.cgColor)
        ctx.fill(CGRect(x: marginLeft, y: cy + 2, width: 3, height: 14))

        let attrs: [NSAttributedString.Key: Any] = [.font: headingFont, .foregroundColor: accent]
        (title as NSString).draw(at: CGPoint(x: marginLeft + 10, y: cy), withAttributes: attrs)
        cy += 22
        return cy
    }

    private static func drawHorizontalLine(y: CGFloat, color: UIColor, thickness: CGFloat) {
        let ctx = UIGraphicsGetCurrentContext()!
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(thickness)
        ctx.move(to: CGPoint(x: marginLeft, y: y))
        ctx.addLine(to: CGPoint(x: pageWidth - marginRight, y: y))
        ctx.strokePath()
    }

    /// Draw text that wraps within a given width.  Returns the Y position
    /// after the last line.
    @discardableResult
    private static func drawWrappedText(
        _ text: String,
        x: CGFloat, y: CGFloat,
        width: CGFloat,
        font: UIFont,
        color: UIColor,
        lineSpacing: CGFloat
    ) -> CGFloat {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle,
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let boundingRect = attrStr.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        attrStr.draw(in: CGRect(x: x, y: y, width: width, height: boundingRect.height))
        return y + ceil(boundingRect.height)
    }
}
