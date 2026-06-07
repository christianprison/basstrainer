import Foundation

/// Monophonic pitch detector based on the YIN algorithm
/// (de Cheveigné & Kawahara, 2002). Dependency-free, suitable for
/// the low frequency range of a bass (down to ~31 Hz / low B).
///
/// Usage: feed mono Float samples (one analysis window at a time) into
/// `detect(_:sampleRate:)`. Returns the fundamental frequency in Hz, or
/// nil if no confident pitch was found (silence, noise, transients).
struct PitchDetector {
    /// YIN absolute threshold. Lower = stricter. 0.10–0.15 works well for bass.
    var threshold: Float = 0.15

    /// Minimum RMS level below which we treat the signal as silence.
    var silenceThreshold: Float = 0.01

    /// Plausible frequency band for a 5-string bass (B0 ≈ 31 Hz to G4 ≈ 392 Hz
    /// plus headroom for harmonics/overtones detection up to ~700 Hz).
    var minFrequency: Double = 28.0
    var maxFrequency: Double = 700.0

    /// Detect the fundamental frequency of `samples`.
    /// - Parameter samples: mono PCM in [-1, 1]
    /// - Parameter sampleRate: e.g. 44100 or 48000
    /// - Returns: (frequency in Hz, clarity 0…1) or nil
    func detect(_ samples: [Float], sampleRate: Double) -> (frequency: Double, clarity: Float)? {
        let n = samples.count
        guard n >= 1024 else { return nil }

        // Gate on loudness so we don't lock onto background noise.
        let rms = Self.rms(samples)
        guard rms >= silenceThreshold else { return nil }

        // tau search range derived from the frequency band of interest.
        let maxTau = min(n / 2, Int(sampleRate / minFrequency))
        let minTau = max(2, Int(sampleRate / maxFrequency))
        guard maxTau > minTau else { return nil }

        // Step 1+2: cumulative mean normalized difference function (CMNDF).
        var diff = [Float](repeating: 0, count: maxTau)
        for tau in 1..<maxTau {
            var sum: Float = 0
            var j = 0
            while j < maxTau {
                let delta = samples[j] - samples[j + tau]
                sum += delta * delta
                j += 1
            }
            diff[tau] = sum
        }

        var cmnd = [Float](repeating: 1, count: maxTau)
        var runningSum: Float = 0
        for tau in 1..<maxTau {
            runningSum += diff[tau]
            cmnd[tau] = runningSum > 0 ? diff[tau] * Float(tau) / runningSum : 1
        }

        // Step 3: absolute threshold — first dip below threshold, then descend to its local min.
        var tauEstimate = -1
        var tau = minTau
        while tau < maxTau {
            if cmnd[tau] < threshold {
                while tau + 1 < maxTau && cmnd[tau + 1] < cmnd[tau] {
                    tau += 1
                }
                tauEstimate = tau
                break
            }
            tau += 1
        }

        // Fallback: no value crossed the threshold → take global minimum in range.
        if tauEstimate == -1 {
            var bestTau = minTau
            var bestVal = cmnd[minTau]
            for t in minTau..<maxTau where cmnd[t] < bestVal {
                bestVal = cmnd[t]
                bestTau = t
            }
            // Only accept a reasonably clear minimum.
            guard bestVal < 0.3 else { return nil }
            tauEstimate = bestTau
        }

        // Step 4: parabolic interpolation around the estimate for sub-sample accuracy.
        let refinedTau = Self.parabolicInterpolation(cmnd, tau: tauEstimate)
        guard refinedTau > 0 else { return nil }

        let frequency = sampleRate / Double(refinedTau)
        guard frequency >= minFrequency && frequency <= maxFrequency else { return nil }

        let clarity = 1 - min(cmnd[tauEstimate], 1)
        return (frequency, clarity)
    }

    // MARK: - Helpers

    static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        return (sum / Float(samples.count)).squareRoot()
    }

    private static func parabolicInterpolation(_ array: [Float], tau: Int) -> Float {
        guard tau > 0 && tau < array.count - 1 else { return Float(tau) }
        let x0 = array[tau - 1]
        let x1 = array[tau]
        let x2 = array[tau + 1]
        let denom = x0 + x2 - 2 * x1
        guard denom != 0 else { return Float(tau) }
        return Float(tau) + (x0 - x2) / (2 * denom)
    }
}
