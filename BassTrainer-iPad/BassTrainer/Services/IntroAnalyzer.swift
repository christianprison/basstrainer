import Foundation

/// Offline-Erkennung über eine aufgezeichnete Audiospur. Gleiche Logik wie der
/// Live-Detektor in `IntroRecorder`, aber als Batch — damit man die Parameter
/// nachträglich auf derselben Aufnahme tweaken kann (ohne neu zu spielen).
enum IntroAnalyzer {
    struct Params {
        let sensitivity: Float
        let gain: Float
        let gate: Float
        let attack: Float
        let release: Float
        let refractoryMs: Double
    }

    /// - Returns: erkannte Töne (Zeit in `startTime`-Domäne, MIDI) + Telemetrie für die Wellenform.
    static func analyze(samples: [Float], sampleRate: Double, startTime: Double, params p: Params)
        -> (notes: [(time: Double, midi: Int)], meter: [DetectionMeterSample]) {

        var notes: [(time: Double, midi: Int)] = []
        var meter: [DetectionMeterSample] = []
        let detector = PitchDetector()
        let analysisSize = 4096
        let hop = 256
        let ratio = 2.0 - p.sensitivity * 0.85

        var fastEnv: Float = 0
        var slowEnv: Float = 0.001
        var wasAbove = false
        var lastOnset = -1.0
        var meterHop = 0
        var meterOnset = false
        var onsetIdxs: [Int] = []

        let n = samples.count
        var i = 0
        while i < n {
            let end = min(i + hop, n)
            var sum: Float = 0
            var c = i
            while c < end { let x = samples[c] * p.gain; sum += x * x; c += 1 }
            let env = (sum / Float(end - i)).squareRoot()
            fastEnv += p.attack * (env - fastEnv)
            slowEnv += p.release * (env - slowEnv)
            let thresh = max(p.gate, slowEnv * ratio)
            let t = startTime + Double(i) / sampleRate
            var onsetHere = false
            if fastEnv > thresh {
                if !wasAbove && (lastOnset < 0 || (t - lastOnset) * 1000 > p.refractoryMs) {
                    lastOnset = t
                    onsetIdxs.append(i)
                    onsetHere = true
                }
                wasAbove = true
            } else if fastEnv < thresh * 0.7 {
                wasAbove = false
            }
            if onsetHere { meterOnset = true }
            meterHop += 1
            if meterHop >= 6 {
                meter.append(DetectionMeterSample(env: fastEnv, threshold: thresh, onset: meterOnset))
                meterHop = 0
                meterOnset = false
            }
            i = end
        }

        // Pitch je Anschlag (Fenster im Sustain, ~20–105 ms nach dem Onset).
        let offset = Int(0.02 * sampleRate)
        for idx in onsetIdxs {
            let s0 = min(n, idx + offset)
            let s1 = min(n, s0 + analysisSize)
            guard s1 - s0 >= 1024 else { continue }
            let window = Array(samples[s0..<s1])
            guard let res = detector.detect(window, sampleRate: sampleRate) else { continue }
            notes.append((time: startTime + Double(idx) / sampleRate, midi: BassIntro.midi(forFrequency: res.frequency)))
        }
        return (notes, meter)
    }
}
