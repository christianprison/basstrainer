import AVFoundation
import Combine
import Foundation

/// A detected musical note with tuning information.
struct DetectedNote: Equatable {
    let note: NoteName
    let octave: Int
    let frequency: Double
    /// Deviation from the equal-tempered pitch, in cents (-50…+50).
    let cents: Double
    let clarity: Float

    /// e.g. "A2"
    var label: String { "\(note.rawValue)\(octave)" }
}

/// Live input pitch detection via AVAudioEngine + YIN.
///
/// Captures the microphone / USB-audio-interface input, runs monophonic
/// pitch detection and publishes the detected note. This intentionally uses
/// AVAudioEngine (required for input taps) and a `.playAndRecord` session so
/// it can coexist with the existing AVAudioPlayer-based playback.
@MainActor
final class TunerEngine: ObservableObject {
    @Published private(set) var detected: DetectedNote?
    @Published private(set) var level: Float = 0          // input RMS, 0…1
    @Published private(set) var isRunning = false
    @Published private(set) var permissionDenied = false
    @Published private(set) var inputName: String = "—"
    @Published private(set) var lastError: String?

    private let engine = AVAudioEngine()
    private var detector = PitchDetector()

    /// Callback, wenn ein Ton stabil gehalten wird: (Eingangsfenster, SampleRate, f0).
    /// Für die Sample-Vergleichs-Erkennung.
    var onNoteHeld: ((_ samples: [Float], _ sampleRate: Double, _ frequency: Double) -> Void)?
    private var lastWindow: [Float] = []
    private var lastWindowSR: Double = 48000
    private var holdPitch: Int?
    private var holdCount = 0
    private var emitted = false
    private let holdGateRMS: Float = 0.012

    /// Analysis window. ~170 ms at 48 kHz — genug Perioden auch für tiefe Töne
    /// (low B ~31 Hz) und einen stabileren Obertön-Fingerprint.
    private let analysisSize = 8192
    private var ringBuffer: [Float] = []
    private let detectionQueue = DispatchQueue(label: "de.prisons.basstrainer.pitch", qos: .userInitiated)
    private var detectionInFlight = false

    // MARK: - Control

    func start() {
        guard !isRunning else { return }
        requestPermission { [weak self] granted in
            guard let self else { return }
            if granted {
                self.beginCapture()
            } else {
                self.permissionDenied = true
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        detected = nil
        level = 0
        ringBuffer.removeAll(keepingCapacity: true)

        // Restore the playback-only session so game audio returns to normal.
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Permission (iOS 17 API)

    private func requestPermission(_ completion: @escaping (Bool) -> Void) {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            completion(true)
        case .denied:
            completion(false)
        case .undetermined:
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        @unknown default:
            completion(false)
        }
    }

    // MARK: - Capture

    private func beginCapture() {
        do {
            let session = AVAudioSession.sharedInstance()
            // .measurement disables internal signal processing (AGC, EQ) for
            // the most faithful input — ideal for pitch detection.
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
            try session.setActive(true)
            selectExternalInput(on: session)
            inputName = session.currentRoute.inputs.first?.portName ?? "—"

            let input = engine.inputNode
            let format = input.inputFormat(forBus: 0)
            let sampleRate = format.sampleRate

            input.installTap(onBus: 0, bufferSize: UInt32(analysisSize), format: format) { [weak self] buffer, _ in
                self?.process(buffer: buffer, sampleRate: sampleRate)
            }

            engine.prepare()
            try engine.start()
            isRunning = true
            permissionDenied = false
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            isRunning = false
        }
    }

    /// Prefer an external audio interface (e.g. Behringer UM2) over the
    /// built-in microphone. iOS usually auto-selects a connected USB interface,
    /// but pinning it explicitly avoids the occasional fallback to the iPad mic.
    private func selectExternalInput(on session: AVAudioSession) {
        guard let inputs = session.availableInputs else { return }

        // Priority: USB audio first, then any other non-built-in input
        // (line-in, BT-HFP), and only the built-in mic as last resort.
        let preferred = inputs.first { $0.portType == .usbAudio }
            ?? inputs.first { $0.portType != .builtInMic }

        guard let preferred else { return }
        do {
            try session.setPreferredInput(preferred)
        } catch {
            lastError = "Input-Auswahl fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    /// Called on the realtime audio thread. Copies samples and offloads the
    /// (heavier) YIN analysis to a background queue, then publishes on main.
    private nonisolated func process(buffer: AVAudioPCMBuffer, sampleRate: Double) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        let channel0 = channelData[0]
        var chunk = [Float](repeating: 0, count: frameCount)
        for i in 0..<frameCount { chunk[i] = channel0[i] }

        Task { @MainActor [weak self] in
            self?.accumulate(chunk, sampleRate: sampleRate)
        }
    }

    private func accumulate(_ chunk: [Float], sampleRate: Double) {
        ringBuffer.append(contentsOf: chunk)
        // Keep memory bounded.
        if ringBuffer.count > analysisSize * 3 {
            ringBuffer.removeFirst(ringBuffer.count - analysisSize * 2)
        }
        guard ringBuffer.count >= analysisSize, !detectionInFlight else { return }

        let window = Array(ringBuffer.suffix(analysisSize))
        lastWindow = window
        lastWindowSR = sampleRate
        // Slide forward, keeping 50% overlap for responsiveness.
        if ringBuffer.count > analysisSize / 2 {
            ringBuffer.removeFirst(ringBuffer.count - analysisSize / 2)
        }

        detectionInFlight = true
        let detectorCopy = detector
        detectionQueue.async { [weak self] in
            let rms = PitchDetector.rms(window)
            let result = detectorCopy.detect(window, sampleRate: sampleRate)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.level = min(rms * 6, 1) // scale for a usable meter
                if let result {
                    self.detected = Self.makeNote(frequency: result.frequency, clarity: result.clarity)
                    // Stabil gehaltenen Ton einmalig als Capture melden.
                    let mrounded = Int((69.0 + 12.0 * log2(result.frequency / 440.0)).rounded())
                    if self.holdPitch == mrounded { self.holdCount += 1 }
                    else { self.holdPitch = mrounded; self.holdCount = 1; self.emitted = false }
                    if !self.emitted, self.holdCount >= 3, rms > self.holdGateRMS {
                        self.emitted = true
                        self.onNoteHeld?(self.lastWindow, self.lastWindowSR, result.frequency)
                    }
                } else {
                    self.detected = nil
                    self.holdPitch = nil; self.holdCount = 0; self.emitted = false
                }
                self.detectionInFlight = false
            }
        }
    }

    // MARK: - Frequency → Note

    static func makeNote(frequency: Double, clarity: Float) -> DetectedNote {
        // MIDI note number (A4 = 69 = 440 Hz).
        let midiExact = 69.0 + 12.0 * log2(frequency / 440.0)
        let midiRounded = Int(midiExact.rounded())
        let cents = (midiExact - Double(midiRounded)) * 100.0

        let pitchClass = ((midiRounded % 12) + 12) % 12
        // NoteName.allCases is declared chromatically from C, so index == pitch class.
        let note = NoteName.allCases[pitchClass]
        let octave = midiRounded / 12 - 1

        return DetectedNote(
            note: note,
            octave: octave,
            frequency: frequency,
            cents: cents,
            clarity: clarity
        )
    }
}
