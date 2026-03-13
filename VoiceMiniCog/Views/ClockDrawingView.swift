//
//  ClockDrawingView.swift
//  VoiceMiniCog
//
//  Clock drawing canvas matching React implementation with timer
//

import SwiftUI

struct ClockDrawingView: View {
    var state: AssessmentState
    var onComplete: (UIImage, Int) -> Void

    @State private var lines: [[CGPoint]] = []
    @State private var currentLine: [CGPoint] = []
    @State private var timeLeft: Int = 180  // 3 minutes
    @State private var startTime: Date = Date()
    @State private var strokeCount: Int = 0
    @State private var timer: Timer?
    @State private var isDone: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text("Clock Drawing")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(MercyColors.gray800)

                Spacer()

                // Timer
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .font(.system(size: 16))
                        .foregroundColor(isLowTime ? .red : MercyColors.gray400)

                    Text(formatTime(timeLeft))
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundColor(isLowTime ? .red : MercyColors.gray800)
                        .animation(isLowTime ? .easeInOut(duration: 0.5).repeatForever() : .default, value: isLowTime)
                }
            }
            .padding(.horizontal)

            // Canvas
            GeometryReader { geo in
                let size = min(geo.size.width - 32, 550)

                ZStack {
                    // White background with border
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isLowTime ? Color.red.opacity(0.4) : MercyColors.gray200, lineWidth: 2)
                        )
                        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)

                    // Dashed circle guide
                    Circle()
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [10, 5]))
                        .foregroundColor(MercyColors.gray300)
                        .frame(width: size * 0.8, height: size * 0.8)

                    // Drawing canvas
                    Canvas { context, canvasSize in
                        for line in lines {
                            drawLine(line, in: context)
                        }
                        if !currentLine.isEmpty {
                            drawLine(currentLine, in: context)
                        }
                    }
                    .frame(width: size, height: size)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let point = value.location
                                if currentLine.isEmpty {
                                    strokeCount += 1
                                }
                                currentLine.append(point)
                            }
                            .onEnded { _ in
                                if !currentLine.isEmpty {
                                    lines.append(currentLine)
                                    currentLine = []
                                }
                            }
                    )
                }
                .frame(width: size, height: size)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Stroke count
            Text("\(strokeCount) stroke\(strokeCount != 1 ? "s" : "")")
                .font(.system(size: 12))
                .foregroundColor(MercyColors.gray400)

            // Buttons
            HStack(spacing: 16) {
                Button(action: clearCanvas) {
                    Text("Clear")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(MercyColors.gray700)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.white)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(MercyColors.gray300, lineWidth: 1)
                        )
                }
                .disabled(strokeCount == 0)
                .opacity(strokeCount == 0 ? 0.5 : 1)

                Button(action: submitDrawing) {
                    Text("Done Drawing")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(strokeCount >= 3 ? MercyColors.mercyBlue : MercyColors.gray300)
                        .cornerRadius(12)
                }
                .disabled(strokeCount < 3)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .onAppear {
            startTime = Date()
            startTimer()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    private var isLowTime: Bool {
        timeLeft <= 30
    }

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private func drawLine(_ points: [CGPoint], in context: GraphicsContext) {
        guard points.count >= 2 else {
            if let point = points.first {
                // Draw a dot for single point
                var path = Path()
                path.addEllipse(in: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4))
                context.fill(path, with: .color(MercyColors.gray800))
            }
            return
        }

        var path = Path()
        path.move(to: points[0])

        if points.count == 2 {
            path.addLine(to: points[1])
        } else {
            // Use quadratic curves for smoother lines
            for i in 1..<points.count {
                let mid = CGPoint(
                    x: (points[i-1].x + points[i].x) / 2,
                    y: (points[i-1].y + points[i].y) / 2
                )
                path.addQuadCurve(to: mid, control: points[i-1])
            }
            if let last = points.last {
                path.addLine(to: last)
            }
        }

        context.stroke(path, with: .color(MercyColors.gray800), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if timeLeft > 0 {
                timeLeft -= 1
            } else {
                timer?.invalidate()
                if !isDone {
                    submitDrawing()
                }
            }
        }
    }

    private func clearCanvas() {
        lines = []
        currentLine = []
        strokeCount = 0
    }

    private func submitDrawing() {
        guard !isDone else { return }
        isDone = true
        timer?.invalidate()

        let timeSec = Int(Date().timeIntervalSince(startTime))

        // Render canvas to image
        let renderer = ImageRenderer(content: canvasContent)
        renderer.scale = 2.0

        if let image = renderer.uiImage {
            onComplete(image, timeSec)
        }
    }

    private var canvasContent: some View {
        Canvas { context, size in
            // White background
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(.white)
            )

            // Circle outline
            let circleRect = CGRect(
                x: size.width * 0.1,
                y: size.height * 0.1,
                width: size.width * 0.8,
                height: size.height * 0.8
            )
            context.stroke(
                Path(ellipseIn: circleRect),
                with: .color(MercyColors.gray300),
                lineWidth: 2
            )

            // Draw all lines
            for line in lines {
                drawLine(line, in: context)
            }
        }
        .frame(width: 600, height: 600)
        .background(Color.white)
    }
}

#Preview {
    ClockDrawingView(state: AssessmentState()) { image, time in
        print("Completed in \(time) seconds")
    }
}
