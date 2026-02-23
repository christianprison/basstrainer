import SwiftUI

struct FretboardView: View {
    let currentPosition: FretPosition?
    let isPlaying: Bool
    let levelColor: Color

    // Fret spacing uses the 12th root of 2 formula (real guitar physics)
    private static let maxFret = 24
    private static let maxFretNormalized: Double = {
        1.0 - pow(0.5, Double(maxFret) / 12.0)
    }()

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let neckRect = CGRect(
                x: 50,
                y: 10,
                width: size.width - 60,
                height: size.height - 20
            )

            ZStack {
                // Draw the fretboard using Canvas
                Canvas { context, _ in
                    drawNeck(context: context, rect: neckRect)
                    drawFrets(context: context, rect: neckRect)
                    drawDotMarkers(context: context, rect: neckRect)
                    drawStrings(context: context, rect: neckRect)
                    drawFretNumbers(context: context, rect: neckRect)
                }

                // String labels on the left
                ForEach(BassString.allCases) { string in
                    let y = Self.stringY(string: string.rawValue, in: neckRect)
                    Text(string.name)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(width: 30, height: 24)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(4)
                        .position(x: 20, y: y)
                }

                // Animated target dot
                if let position = currentPosition, isPlaying {
                    let point = targetPoint(position: position, in: neckRect)
                    TargetDotView(point: point, color: levelColor)
                }
            }
        }
        .background(Color.black.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Drawing Functions

    private func drawNeck(context: GraphicsContext, rect: CGRect) {
        // Neck background (rosewood-like gradient)
        let gradient = Gradient(colors: [
            Color(red: 0.35, green: 0.20, blue: 0.10),
            Color(red: 0.45, green: 0.28, blue: 0.15),
            Color(red: 0.40, green: 0.24, blue: 0.12),
        ])
        context.fill(
            Path(roundedRect: rect, cornerRadius: 6),
            with: .linearGradient(
                gradient,
                startPoint: CGPoint(x: rect.minX, y: rect.minY),
                endPoint: CGPoint(x: rect.minX, y: rect.maxY)
            )
        )
    }

    private func drawFrets(context: GraphicsContext, rect: CGRect) {
        for fret in 0...Self.maxFret {
            let x = Self.fretX(fret: fret, in: rect)
            var path = Path()
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))

            let lineWidth: CGFloat = fret == 0 ? 5 : 1.5
            let color: Color = fret == 0 ? .white : Color(white: 0.7, opacity: 0.7)
            context.stroke(path, with: .color(color), lineWidth: lineWidth)
        }
    }

    private func drawDotMarkers(context: GraphicsContext, rect: CGRect) {
        let singleDotFrets = [3, 5, 7, 9, 15, 17, 19, 21]
        let doubleDotFrets = [12, 24]
        let dotRadius: CGFloat = 5

        for fret in singleDotFrets {
            let x = Self.fretMidX(fret: fret, in: rect)
            let y = rect.midY
            let dotRect = CGRect(x: x - dotRadius, y: y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
            context.fill(Path(ellipseIn: dotRect), with: .color(.white.opacity(0.25)))
        }

        for fret in doubleDotFrets {
            let x = Self.fretMidX(fret: fret, in: rect)
            let y1 = rect.minY + rect.height * 0.25
            let y2 = rect.minY + rect.height * 0.75
            let dot1 = CGRect(x: x - dotRadius, y: y1 - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
            let dot2 = CGRect(x: x - dotRadius, y: y2 - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
            context.fill(Path(ellipseIn: dot1), with: .color(.white.opacity(0.25)))
            context.fill(Path(ellipseIn: dot2), with: .color(.white.opacity(0.25)))
        }
    }

    private func drawStrings(context: GraphicsContext, rect: CGRect) {
        for stringIndex in 0..<5 {
            let y = Self.stringY(string: stringIndex, in: rect)
            let thickness = CGFloat(1.0 + Double(stringIndex) * 0.6)
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))

            // Metallic string color
            let color = Color(white: 0.85, opacity: 0.9)
            context.stroke(path, with: .color(color), lineWidth: thickness)
        }
    }

    private func drawFretNumbers(context: GraphicsContext, rect: CGRect) {
        let displayFrets = [0, 3, 5, 7, 9, 12, 15, 17, 19, 21, 24]
        for fret in displayFrets {
            let x = Self.fretMidX(fret: fret, in: rect)
            let y = rect.maxY + 12
            let text = Text("\(fret)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
            context.draw(context.resolve(text), at: CGPoint(x: x, y: y))
        }
    }

    // MARK: - Position Calculations

    static func fretX(fret: Int, in rect: CGRect) -> CGFloat {
        guard fret > 0 else { return rect.minX }
        let position = 1.0 - pow(0.5, Double(fret) / 12.0)
        let normalized = position / maxFretNormalized
        return rect.minX + CGFloat(normalized) * rect.width
    }

    static func fretMidX(fret: Int, in rect: CGRect) -> CGFloat {
        let current = fretX(fret: fret, in: rect)
        let previous = fret > 0 ? fretX(fret: fret - 1, in: rect) : rect.minX
        return (current + previous) / 2
    }

    static func stringY(string: Int, in rect: CGRect) -> CGFloat {
        let padding: CGFloat = 15
        let usableHeight = rect.height - 2 * padding
        return rect.minY + padding + CGFloat(string) * usableHeight / 4.0
    }

    private func targetPoint(position: FretPosition, in rect: CGRect) -> CGPoint {
        let x: CGFloat
        if position.fret == 0 {
            x = rect.minX - 8 // Slightly left of nut for open string
        } else {
            x = Self.fretMidX(fret: position.fret, in: rect)
        }
        let y = Self.stringY(string: position.string.rawValue, in: rect)
        return CGPoint(x: x, y: y)
    }
}

// MARK: - Target Dot View

struct TargetDotView: View {
    let point: CGPoint
    let color: Color

    @State private var isPulsing = false

    var body: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: 30, height: 30)
                .scaleEffect(isPulsing ? 1.5 : 1.0)
                .opacity(isPulsing ? 0.0 : 0.5)

            // Main dot
            Circle()
                .fill(
                    RadialGradient(
                        colors: [color, color.opacity(0.7)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 10
                    )
                )
                .frame(width: 18, height: 18)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                )
                .shadow(color: color.opacity(0.8), radius: isPulsing ? 12 : 4)
                .scaleEffect(isPulsing ? 1.15 : 1.0)
        }
        .position(point)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
        .onChange(of: point) {
            isPulsing = false
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

#Preview {
    FretboardView(
        currentPosition: FretPosition(string: .a, fret: 5),
        isPlaying: true,
        levelColor: .blue
    )
    .frame(height: 160)
    .padding()
}
