import SwiftUI

struct ConfettiView: View {
    let intensity: ConfettiIntensity

    @State private var particles: [ConfettiParticle] = []

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(particles) { particle in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(particle.color)
                        .frame(width: particle.size.width, height: particle.size.height)
                        .rotationEffect(.degrees(particle.rotation))
                        .position(particle.position)
                        .opacity(particle.opacity)
                }
            }
            .onAppear {
                createParticles(in: geometry.size)
                animateParticles(in: geometry.size)
            }
        }
        .allowsHitTesting(false)
    }

    private func createParticles(in size: CGSize) {
        let colors: [Color] = [
            .red, .blue, .green, .yellow, .purple, .orange, .pink, .cyan,
        ]

        particles = (0..<intensity.particleCount).map { _ in
            ConfettiParticle(
                color: colors.randomElement()!,
                size: CGSize(
                    width: CGFloat.random(in: 6...12),
                    height: CGFloat.random(in: 4...8)
                ),
                position: CGPoint(
                    x: size.width / 2 + CGFloat.random(in: -80...80),
                    y: -20
                ),
                rotation: Double.random(in: 0...360),
                opacity: 1.0,
                targetX: size.width / 2 + CGFloat.random(in: -300...300),
                targetY: size.height + 40,
                duration: Double.random(in: 1.5...3.0)
            )
        }
    }

    private func animateParticles(in size: CGSize) {
        for i in particles.indices {
            let delay = Double.random(in: 0...0.5)
            let duration = particles[i].duration

            withAnimation(.easeIn(duration: duration).delay(delay)) {
                particles[i].position = CGPoint(
                    x: particles[i].targetX,
                    y: particles[i].targetY
                )
                particles[i].rotation += Double.random(in: 180...720)
                particles[i].opacity = 0
            }
        }
    }
}

struct ConfettiParticle: Identifiable {
    let id = UUID()
    let color: Color
    let size: CGSize
    var position: CGPoint
    var rotation: Double
    var opacity: Double
    let targetX: CGFloat
    let targetY: CGFloat
    let duration: Double
}

// MARK: - Achievement Banner

struct AchievementBannerView: View {
    let message: String

    @State private var isVisible = false

    var body: some View {
        Text(message)
            .font(.headline)
            .fontWeight(.bold)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.2), radius: 8)
            )
            .scaleEffect(isVisible ? 1.0 : 0.5)
            .opacity(isVisible ? 1.0 : 0.0)
            .onAppear {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    isVisible = true
                }
                withAnimation(.easeOut(duration: 0.3).delay(2.0)) {
                    isVisible = false
                }
            }
    }
}

#Preview {
    ZStack {
        Color.black.opacity(0.1)
        ConfettiView(intensity: .large)
        AchievementBannerView(message: "Speed Demon!")
    }
}
