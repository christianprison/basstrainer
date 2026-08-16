import AVFoundation
import Foundation

/// Spieltechnik (Merkmale unterscheiden sich je Technik). Erst „fingered".
enum PlayTechnique: String, Codable, CaseIterable, Identifiable {
    case fingered, slap, pop, hammerOn, pullOff, slide
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fingered: return "Fingered"
        case .slap:     return "Slap"
        case .pop:      return "Pop"
        case .hammerOn: return "Hammer-on"
        case .pullOff:  return "Pull-off"
        case .slide:    return "Slide"
        }
    }
}

/// Ein bewerteter Kandidat (Saite/Bund) für einen gespielten Ton.
struct ScoredCandidate: Identifiable, Equatable {
    let id = UUID()
    let string: Int      // 1=B … 5=G
    let fret: Int
    let midi: Int
    let key: String      // Positions-Key, z. B. "E_005"
    let noteName: String
    var probability: Double
    var samples: Int     // Anzahl gelernter Beispiele für diese Position/Technik
}

/// Gelerntes Profil einer Position+Technik: Online-Mittelwert + Streuung (Welford)
/// über die Merkmalsvektoren aller Feedbacks.
struct NoteProfile: Codable {
    var count: Int
    var mean: [Double]
    var m2: [Double]

    mutating func update(_ x: [Double]) {
        if count == 0 || mean.count != x.count {
            mean = x; m2 = [Double](repeating: 0, count: x.count); count = 1; return
        }
        count += 1
        for i in x.indices {
            let d = x[i] - mean[i]
            mean[i] += d / Double(count)
            m2[i] += d * (x[i] - mean[i])
        }
    }
    func variance() -> [Double] { count > 1 ? m2.map { $0 / Double(count - 1) } : mean.map { _ in 1 } }
}

/// Merkmale + gelernte Profile für die Lagen-Erkennung. KEIN Sample-Vergleich:
/// die Erkennung lernt ausschließlich aus dem Feedback des Nutzers.
@MainActor
final class NoteMatcher: ObservableObject {
    @Published private(set) var totalSamples = 0     // Summe aller Beispiele (für UI)
    @Published private(set) var syncStatus: String?

    private var profiles: [String: NoteProfile] = [:]   // Key = "E_005|fingered"
    private var lastFeatures: [Double] = []
    private let auth = SupabaseAuth.shared

    private let openRealHz: [Int: Double] = [1: 30.87, 2: 41.20, 3: 55.00, 4: 73.42, 5: 98.00]
    private let harmonics = 8
    private let envFrames = 12

    private struct Pos { let string: Int; let fret: Int; let midi: Int; let freq: Double; let key: String; let noteName: String }

    private lazy var allPositions: [Pos] = {
        let map: [(Int, BassString)] = [(1, .b), (2, .e), (3, .a), (4, .d), (5, .g)]
        var res: [Pos] = []
        for (sid, bs) in map {
            guard let open = openRealHz[sid] else { continue }
            for f in 0...12 {
                let freq = open * pow(2.0, Double(f) / 12.0)
                let midi = Int((69.0 + 12.0 * log2(freq / 440.0)).rounded())
                res.append(Pos(string: sid, fret: f, midi: midi, freq: freq,
                               key: FretPosition(string: bs, fret: f).audioKey,
                               noteName: BassIntro.noteName(forMidi: midi)))
            }
        }
        return res
    }()

    private func storeKey(_ posKey: String, _ t: PlayTechnique) -> String { "\(posKey)|\(t.rawValue)" }

    // MARK: - Ranking

    /// Rankt alle Lagen der erkannten Tonhöhe nach dem gelernten Fingerabdruck.
    func rank(segment: [Float], sampleRate: Double, f0: Double, technique: PlayTechnique)
        -> (candidates: [ScoredCandidate], bestScore: Double) {
        guard f0 > 20, segment.count > 512 else { return ([], 0) }
        let feats = Self.features(segment: segment, sampleRate: sampleRate, f0: f0,
                                  harmonics: harmonics, envFrames: envFrames)
        lastFeatures = feats

        let cands = allPositions.filter { abs(1200 * log2(f0 / $0.freq)) < 50 }
        guard !cands.isEmpty else { return ([], 0) }

        // Log-Likelihood je Kandidat (nil = noch nichts gelernt).
        let lls: [Double?] = cands.map { logLikelihood(features: feats, key: storeKey($0.key, technique)) }
        let known = lls.compactMap { $0 }
        var probs = [Double](repeating: 0, count: cands.count)
        if known.isEmpty {
            // Kaltstart: alle gleich wahrscheinlich → Nutzer trainiert.
            for i in probs.indices { probs[i] = 1.0 / Double(cands.count) }
        } else {
            let floor = (known.min() ?? 0) - 4.0
            let raw = lls.map { $0 ?? floor }
            let mx = raw.max() ?? 0
            let exps = raw.map { exp($0 - mx) }
            let sum = exps.reduce(0, +)
            for i in probs.indices { probs[i] = sum > 0 ? exps[i] / sum : 0 }
        }

        var result: [ScoredCandidate] = cands.enumerated().map { i, c in
            ScoredCandidate(string: c.string, fret: c.fret, midi: c.midi, key: c.key,
                            noteName: c.noteName, probability: probs[i],
                            samples: profiles[storeKey(c.key, technique)]?.count ?? 0)
        }
        result.sort { $0.probability > $1.probability }
        return (result, result.first?.probability ?? 0)
    }

    /// Bestätigte Auswahl lernen: Merkmalsvektor in das Profil aufnehmen.
    func confirm(posKey: String, technique: PlayTechnique) {
        guard !lastFeatures.isEmpty else { return }
        let k = storeKey(posKey, technique)
        var p = profiles[k] ?? NoteProfile(count: 0, mean: [], m2: [])
        p.update(lastFeatures)
        profiles[k] = p
        totalSamples = profiles.values.reduce(0) { $0 + $1.count }
    }

    private func logLikelihood(features: [Double], key: String) -> Double? {
        guard let p = profiles[key], p.count >= 2, p.mean.count == features.count else { return nil }
        let v = p.variance()
        var ll = 0.0
        for i in features.indices {
            let vi = max(1e-4, v[i])
            let d = features[i] - p.mean[i]
            ll += -(d * d) / (2 * vi) - 0.5 * log(vi)
        }
        return ll
    }

    // MARK: - Merkmalsextraktion (Obertöne + rel. Hüllkurve + Helligkeit)

    nonisolated static func features(segment: [Float], sampleRate: Double, f0: Double,
                                     harmonics: Int, envFrames: Int) -> [Double] {
        let sr = sampleRate
        // Obertonspektrum aus einem stabilen Fenster (Attack überspringen).
        let sStart = min(max(0, segment.count - 1), Int(sr * 0.08))
        let sEnd = min(segment.count, sStart + Int(sr * 0.18))
        let steady = (sEnd > sStart + 256) ? Array(segment[sStart..<sEnd]) : segment
        var harm = [Double](repeating: 0, count: harmonics)
        for k in 1...harmonics {
            let f = f0 * Double(k)
            if f < sr / 2 { harm[k - 1] = Double(goertzel(steady, sampleRate: sr, freq: f)) }
        }
        let hnorm = l2norm(harm)
        // Helligkeit (spektraler Schwerpunkt über die Obertöne, 0…1).
        var hsum = 0.0
        var weighted = 0.0
        for k in 1...harmonics {
            let m = hnorm[k - 1]
            hsum += m
            weighted += Double(k) * m
        }
        let centroid = hsum > 0 ? weighted / hsum : 0.0
        let centroidNorm = centroid / Double(harmonics)
        // Relative Hüllkurve über das ganze Segment (auf Peak normiert).
        var env = [Double](repeating: 0, count: envFrames)
        let fl = max(1, segment.count / envFrames)
        for i in 0..<envFrames {
            let a = i * fl, b = min(segment.count, a + fl)
            if b > a {
                var s = 0.0
                for j in a..<b { s += Double(segment[j]) * Double(segment[j]) }
                env[i] = (s / Double(b - a)).squareRoot()
            }
        }
        let peak = env.max() ?? 1
        if peak > 0 { for i in env.indices { env[i] /= peak } }
        var out: [Double] = hnorm
        out.append(contentsOf: env)
        out.append(centroidNorm)
        return out
    }

    nonisolated static func goertzel(_ x: [Float], sampleRate: Double, freq: Double) -> Float {
        let w = 2 * Double.pi * freq / sampleRate
        let c = 2 * cos(w)
        var s1 = 0.0, s2 = 0.0
        for v in x { let s0 = Double(v) + c * s1 - s2; s2 = s1; s1 = s0 }
        let real = s1 - s2 * cos(w)
        let imag = s2 * sin(w)
        return Float(sqrt(real * real + imag * imag) / Double(max(1, x.count)))
    }

    nonisolated static func l2norm(_ v: [Double]) -> [Double] {
        let n = sqrt(v.reduce(0) { $0 + $1 * $1 })
        return n > 0 ? v.map { $0 / n } : v
    }

    // MARK: - Persistenz (Supabase, nur auf Knopfdruck)

    private struct ProfileRow: Codable {
        let pos_key: String
        let technique: String
        let count: Int
        let mean: [Double]
        let m2: [Double]
    }

    func saveToCloud() async {
        syncStatus = "Speichere …"
        do {
            let token = try await auth.token()
            // Eigene Profile ersetzen: erst löschen, dann neu schreiben.
            try await SupabaseConfig.authedData(method: "DELETE", path: "note_profiles",
                                                query: [URLQueryItem(name: "pos_key", value: "not.is.null")],
                                                token: token)
            let rows = profiles.map { (k, p) -> ProfileRow in
                let parts = k.split(separator: "|", maxSplits: 1).map(String.init)
                return ProfileRow(pos_key: parts.first ?? k,
                                  technique: parts.count > 1 ? parts[1] : "fingered",
                                  count: p.count, mean: p.mean, m2: p.m2)
            }
            if !rows.isEmpty {
                let body = try JSONEncoder().encode(rows)
                _ = try await SupabaseConfig.authedData(method: "POST", path: "note_profiles",
                                                        body: body, token: token, prefer: "return=minimal")
            }
            syncStatus = "Gespeichert (\(rows.count))"
        } catch {
            syncStatus = "Fehler: \(error.localizedDescription)"
        }
    }

    func loadFromCloud() async {
        do {
            let token = try await auth.token()
            let data = try await SupabaseConfig.authedData(
                method: "GET", path: "note_profiles",
                query: [URLQueryItem(name: "select", value: "pos_key,technique,count,mean,m2")],
                token: token)
            let rows = try JSONDecoder().decode([ProfileRow].self, from: data)
            var dict: [String: NoteProfile] = [:]
            for r in rows {
                dict["\(r.pos_key)|\(r.technique)"] = NoteProfile(count: r.count, mean: r.mean, m2: r.m2)
            }
            profiles = dict
            totalSamples = profiles.values.reduce(0) { $0 + $1.count }
            syncStatus = "Geladen (\(rows.count))"
        } catch {
            // Kein Fehler-Toast beim Start, wenn Tabelle/Netz fehlt.
        }
    }
}
