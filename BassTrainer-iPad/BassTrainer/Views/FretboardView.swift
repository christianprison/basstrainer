import SwiftUI

struct FretboardView: View {
    let currentPosition: FretPosition?
    let isPlaying: Bool
    let levelColor: Color

    // Calibrated positions reference width (from web version)
    private static let referenceWidth: CGFloat = 1883.0

    // Calibrated positions: "stringIndex-fret" -> (x, y) at reference width.
    // WICHTIG: Der Index entspricht direkt BassString.rawValue (g=0 oben … b=4 unten),
    // exakt wie die Web-Version (getNotePosition nutzt den String-Index direkt).
    // Der Kommentar "0=B" in lib/calibrated-positions.ts ist irreführend – das Web
    // verwendet 0 = oberste/dünnste Saite = G.
    private static let calibratedPositions: [String: CGPoint] = [
        "0-0": CGPoint(x: 110, y: 39),
        "0-3": CGPoint(x: 353, y: 33),
        "0-5": CGPoint(x: 536.4, y: 29),
        "0-7": CGPoint(x: 707, y: 25),
        "0-9": CGPoint(x: 872, y: 21),
        "0-12": CGPoint(x: 1095, y: 16),
        "0-15": CGPoint(x: 1303, y: 12),
        "0-17": CGPoint(x: 1422, y: 8),
        "0-19": CGPoint(x: 1533, y: 4),
        "0-21": CGPoint(x: 1632, y: 2),
        "0-24": CGPoint(x: 1775, y: -1),

        "1-0": CGPoint(x: 82, y: 48),
        "1-3": CGPoint(x: 338, y: 44),
        "1-5": CGPoint(x: 520.6, y: 40.1),
        "1-7": CGPoint(x: 696, y: 37),
        "1-9": CGPoint(x: 863, y: 33),
        "1-12": CGPoint(x: 1097, y: 30),
        "1-15": CGPoint(x: 1311, y: 25),
        "1-17": CGPoint(x: 1435, y: 22),
        "1-19": CGPoint(x: 1550, y: 20),
        "1-21": CGPoint(x: 1661, y: 21),
        "1-24": CGPoint(x: 1809, y: 15),

        "2-0": CGPoint(x: 57, y: 58),
        "2-3": CGPoint(x: 319, y: 53),
        "2-5": CGPoint(x: 506.3, y: 53),
        "2-7": CGPoint(x: 686, y: 51),
        "2-9": CGPoint(x: 850.8, y: 48.2),
        "2-12": CGPoint(x: 1098, y: 44),
        "2-15": CGPoint(x: 1319, y: 40),
        "2-17": CGPoint(x: 1453, y: 41),
        "2-19": CGPoint(x: 1576, y: 39),
        "2-21": CGPoint(x: 1700, y: 39),
        "2-24": CGPoint(x: 1848, y: 36),

        "3-0": CGPoint(x: 30, y: 69),
        "3-3": CGPoint(x: 297, y: 66),
        "3-5": CGPoint(x: 491.4, y: 66.9),
        "3-7": CGPoint(x: 676, y: 66),
        "3-9": CGPoint(x: 846.4, y: 64.8),
        "3-12": CGPoint(x: 1102, y: 63),
        "3-15": CGPoint(x: 1332, y: 64),
        "3-17": CGPoint(x: 1477, y: 63),
        "3-19": CGPoint(x: 1606, y: 61),
        "3-21": CGPoint(x: 1731, y: 60),
        "3-24": CGPoint(x: 1882, y: 59),

        "4-0": CGPoint(x: 5, y: 80),
        "4-3": CGPoint(x: 272, y: 79),
        "4-5": CGPoint(x: 476.4, y: 81.4),
        "4-7": CGPoint(x: 665, y: 82),
        "4-9": CGPoint(x: 842.2, y: 82.4),
        "4-12": CGPoint(x: 1108, y: 83),
        "4-15": CGPoint(x: 1345, y: 82),
        "4-17": CGPoint(x: 1498, y: 83),
        "4-19": CGPoint(x: 1638, y: 85),
        "4-21": CGPoint(x: 1767, y: 83),
        "4-24": CGPoint(x: 1883, y: 84),
    ]

    // Calibrated frets for interpolation
    private static let calibratedFrets = [0, 3, 5, 7, 9, 12, 15, 17, 19, 21, 24]

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            // Image aspect ratio: 4019 x 332
            let imageAspect: CGFloat = 4019.0 / 332.0
            let renderedWidth = size.width
            let renderedHeight = renderedWidth / imageAspect

            ZStack(alignment: .topLeading) {
                // Real bass fretboard photo
                Image("BassFretboard")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: renderedWidth)

                // Target dot
                if let position = currentPosition, isPlaying {
                    let point = notePosition(
                        position: position,
                        viewWidth: renderedWidth,
                        viewHeight: renderedHeight
                    )
                    TargetDotView(point: point, color: levelColor)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Position Mapping

    /// Map a BassString to the calibration string index.
    /// Direkt = BassString.rawValue (g=0 … b=4), passend zur Web-Version.
    private func calibrationStringIndex(for bassString: BassString) -> Int {
        bassString.rawValue
    }

    private func notePosition(position: FretPosition, viewWidth: CGFloat, viewHeight: CGFloat) -> CGPoint {
        let stringIdx = calibrationStringIndex(for: position.string)
        let fret = min(position.fret, 24)
        let scale = viewWidth / Self.referenceWidth

        // Try exact calibrated position
        let exactKey = "\(stringIdx)-\(fret)"
        if let exact = Self.calibratedPositions[exactKey] {
            return CGPoint(x: exact.x * scale, y: exact.y * scale)
        }

        // Interpolate between nearest calibrated frets
        let frets = Self.calibratedFrets
        var lowerFret = frets[0]
        var upperFret = frets[frets.count - 1]

        for i in 0..<(frets.count - 1) {
            if frets[i] <= fret && fret <= frets[i + 1] {
                lowerFret = frets[i]
                upperFret = frets[i + 1]
                break
            }
        }

        let lowerKey = "\(stringIdx)-\(lowerFret)"
        let upperKey = "\(stringIdx)-\(upperFret)"

        guard let lower = Self.calibratedPositions[lowerKey],
              let upper = Self.calibratedPositions[upperKey],
              upperFret != lowerFret else {
            // Fallback: center of view
            return CGPoint(x: viewWidth / 2, y: viewHeight / 2)
        }

        let ratio = CGFloat(fret - lowerFret) / CGFloat(upperFret - lowerFret)
        let x = (lower.x + (upper.x - lower.x) * ratio) * scale
        let y = (lower.y + (upper.y - lower.y) * ratio) * scale

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
                .frame(width: 19, height: 19)
                .scaleEffect(isPulsing ? 1.5 : 1.0)
                .opacity(isPulsing ? 0.0 : 0.5)

            // Main dot
            Circle()
                .fill(
                    RadialGradient(
                        colors: [color, color.opacity(0.7)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 6
                    )
                )
                .frame(width: 11, height: 11)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 1.5)
                )
                .shadow(color: color.opacity(0.8), radius: isPulsing ? 8 : 3)
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
