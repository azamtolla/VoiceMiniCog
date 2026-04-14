//
//  PartialScoreReport.swift
//  VoiceMiniCog
//
//  Partial-assessment PDF renderer.
//
//  CLINICAL CONSTRAINT:
//  Any QMCI session that ended before all six subtests completed is NOT a
//  valid QMCI score against O'Caoimh 2012 norms. This renderer produces a
//  PDF that:
//    1. Has a top-line banner: "ASSESSMENT INCOMPLETE — NOT SCORABLE"
//    2. Lists only the subtests that actually completed, as clinician
//       reference.
//    3. NEVER renders a composite /100 score, never renders MCI/dementia
//       tier language.
//    4. Includes the shutdown reason + timestamp for the audit trail.
//

import UIKit

struct PartialScoreReport {

    // Letter in points
    private static let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
    private static let marginLeft: CGFloat = 48
    private static let marginRight: CGFloat = 48
    private static let marginTop: CGFloat = 44
    private static let contentWidth: CGFloat = 612 - 96

    private static let accent = UIColor(red: 0x1A/255, green: 0x52/255, blue: 0x76/255, alpha: 1)
    private static let warning = UIColor(red: 0xD9/255, green: 0x77/255, blue: 0x06/255, alpha: 1)
    private static let errorColor = UIColor(red: 0xDC/255, green: 0x26/255, blue: 0x26/255, alpha: 1)
    private static let textPrimary = UIColor(red: 0x1E/255, green: 0x29/255, blue: 0x3B/255, alpha: 1)
    private static let textSecondary = UIColor(red: 0x47/255, green: 0x55/255, blue: 0x69/255, alpha: 1)

    private static let titleFont = UIFont.systemFont(ofSize: 20, weight: .bold)
    private static let headingFont = UIFont.systemFont(ofSize: 14, weight: .semibold)
    private static let bodyFont = UIFont.systemFont(ofSize: 12, weight: .regular)
    private static let captionFont = UIFont.systemFont(ofSize: 10, weight: .regular)

    /// Generate a partial-score PDF.
    ///
    /// - Parameters:
    ///   - state: assessment state (subscores still readable; composites ignored)
    ///   - reason: why the session ended early
    ///   - completed: which Phase subtests actually completed
    ///   - policy: drives whether completed subscores are shown at all
    ///   - abandonedAt: timestamp
    static func generate(
        state: AssessmentState,
        reason: SessionShutdownReason,
        completed: [Phase],
        policy: AssessmentPersistence.PartialScorePolicy,
        abandonedAt: Date?
    ) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { ctx in
            ctx.beginPage()
            var y: CGFloat = marginTop

            y = drawHeader(at: y)
            y = drawIncompleteBanner(at: y)
            y = drawWhatHappened(at: y, reason: reason, abandonedAt: abandonedAt)

            switch policy {
            case .showNone:
                y = drawPolicyNote(at: y,
                    text: "Per clinician policy, partial subtest scores are not shown on this report.")
            case .showCompletedOnly, .flagForClinicianReview:
                y = drawCompletedSubtests(at: y, state: state, completed: completed)
                if policy == .flagForClinicianReview {
                    y = drawReviewFlag(at: y)
                }
            }

            drawFooter()
        }
    }

    // MARK: - Sections

    private static func drawHeader(at y: CGFloat) -> CGFloat {
        var cy = y
        let title = "MercyCognitive — Partial Session Report"
        drawText(title, at: CGPoint(x: marginLeft, y: cy), font: titleFont, color: accent)
        cy += 28

        let df = DateFormatter()
        df.dateStyle = .long
        df.timeStyle = .short
        drawText("Generated: \(df.string(from: Date()))",
                 at: CGPoint(x: marginLeft, y: cy),
                 font: captionFont, color: textSecondary)
        cy += 18

        let line = UIBezierPath()
        line.move(to: CGPoint(x: marginLeft, y: cy))
        line.addLine(to: CGPoint(x: marginLeft + contentWidth, y: cy))
        accent.setStroke()
        line.lineWidth = 2
        line.stroke()
        cy += 14

        return cy
    }

    private static func drawIncompleteBanner(at y: CGFloat) -> CGFloat {
        var cy = y
        let rect = CGRect(x: marginLeft, y: cy, width: contentWidth, height: 56)
        errorColor.withAlphaComponent(0.08).setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 8).fill()
        errorColor.setStroke()
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 8)
        path.lineWidth = 1.5
        path.stroke()

        drawText("ASSESSMENT INCOMPLETE — NOT SCORABLE",
                 at: CGPoint(x: marginLeft + 14, y: cy + 10),
                 font: UIFont.systemFont(ofSize: 16, weight: .bold),
                 color: errorColor)
        drawText("This session ended before all QMCI subtests completed. Partial results are NOT valid against O'Caoimh 2012 norms and must not be interpreted as a cognitive score.",
                 at: CGPoint(x: marginLeft + 14, y: cy + 32),
                 font: captionFont,
                 color: textPrimary,
                 maxWidth: contentWidth - 28)
        cy += rect.height + 16
        return cy
    }

    private static func drawWhatHappened(at y: CGFloat, reason: SessionShutdownReason, abandonedAt: Date?) -> CGFloat {
        var cy = y
        drawText("What happened", at: CGPoint(x: marginLeft, y: cy), font: headingFont, color: textPrimary)
        cy += 20

        let label: String
        switch reason {
        case .participantLeft:   label = "Patient ended the session early or left the room."
        case .timeout:           label = "Session exceeded the maximum time limit."
        case .networkError:      label = "Network or service interruption prevented completion."
        case .abandonedSilence:  label = "150 seconds of continuous silence — patient did not respond to the gentle re-engagement prompt."
        case .completed:         label = "Session marked completed (unexpected for partial report)."
        case .unknown:           label = "Reason unknown."
        }
        drawText(label, at: CGPoint(x: marginLeft, y: cy), font: bodyFont, color: textSecondary, maxWidth: contentWidth)
        cy += 22

        if let at = abandonedAt {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .medium
            drawText("Ended at: \(df.string(from: at))",
                     at: CGPoint(x: marginLeft, y: cy),
                     font: captionFont, color: textSecondary)
            cy += 18
        }
        return cy + 8
    }

    private static func drawCompletedSubtests(at y: CGFloat, state: AssessmentState, completed: [Phase]) -> CGFloat {
        var cy = y
        drawText("Subtests completed (clinician reference only)",
                 at: CGPoint(x: marginLeft, y: cy),
                 font: headingFont, color: textPrimary)
        cy += 20

        if completed.isEmpty {
            drawText("No subtests completed.", at: CGPoint(x: marginLeft, y: cy), font: bodyFont, color: textSecondary)
            cy += 24
            return cy
        }

        for phase in completed where phase.isQmciSubtest {
            let label = phase.displayName
            drawText("• \(label)", at: CGPoint(x: marginLeft, y: cy), font: bodyFont, color: textPrimary)
            cy += 18
        }
        cy += 8
        return cy
    }

    private static func drawPolicyNote(at y: CGFloat, text: String) -> CGFloat {
        var cy = y
        drawText(text, at: CGPoint(x: marginLeft, y: cy), font: bodyFont, color: textSecondary, maxWidth: contentWidth)
        cy += 28
        return cy
    }

    private static func drawReviewFlag(at y: CGFloat) -> CGFloat {
        var cy = y + 4
        let rect = CGRect(x: marginLeft, y: cy, width: contentWidth, height: 38)
        warning.withAlphaComponent(0.10).setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 6).fill()
        drawText("⚠  Requires clinician review before any clinical use.",
                 at: CGPoint(x: marginLeft + 12, y: cy + 10),
                 font: UIFont.systemFont(ofSize: 12, weight: .semibold),
                 color: warning)
        return cy + rect.height + 16
    }

    private static func drawFooter() {
        let footerY = pageRect.height - 32
        let text = "MercyCognitive QMCI v1 · Partial report · This document is not a diagnostic instrument."
        drawText(text,
                 at: CGPoint(x: marginLeft, y: footerY),
                 font: captionFont, color: textSecondary)
    }

    // MARK: - Drawing helpers

    private static func drawText(
        _ text: String,
        at point: CGPoint,
        font: UIFont,
        color: UIColor,
        maxWidth: CGFloat? = nil
    ) {
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: para
        ]
        if let w = maxWidth {
            let rect = CGRect(x: point.x, y: point.y, width: w, height: .greatestFiniteMagnitude)
            (text as NSString).draw(with: rect,
                                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                                    attributes: attrs,
                                    context: nil)
        } else {
            (text as NSString).draw(at: point, withAttributes: attrs)
        }
    }
}
