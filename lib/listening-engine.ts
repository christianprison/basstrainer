// Zentrale Hör-Engine: nimmt das Mikrofon ab und liefert
// (a) Onset-/Anschlag-Ereignisse für Timing-/Präzisionsübungen und
// (b) optionale Tonhöhe (Autokorrelation, für Bass-Frequenzen ausgelegt).
//
// Bewusst frei von React. Alle Browser-APIs werden erst in start()
// angefasst, damit der statische Export (SSR/Prerender) nicht crasht.

export interface OnsetEvent {
  /** Zeitstempel in performance.now()-Millisekunden. */
  time: number
  /** Lautstärke (RMS) zum Zeitpunkt des Anschlags. */
  level: number
}

export interface PitchResult {
  frequency: number
  /** Notenname inkl. Oktave, z.B. "E2". */
  note: string
  /** Abweichung in Cent zum nächstgelegenen Halbton. */
  cents: number
}

export type EnginePermission = "idle" | "requesting" | "granted" | "denied"

const NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

function frequencyToNote(freq: number): { note: string; cents: number } {
  // A4 = 440 Hz, MIDI 69
  const midi = 69 + 12 * Math.log2(freq / 440)
  const rounded = Math.round(midi)
  const cents = Math.round((midi - rounded) * 100)
  const name = NOTE_NAMES[((rounded % 12) + 12) % 12]
  const octave = Math.floor(rounded / 12) - 1
  return { note: `${name}${octave}`, cents }
}

// Autokorrelation für Grundfrequenz. Gibt -1 zurück, wenn kein klarer Ton.
function detectPitch(buf: Float32Array, sampleRate: number): number {
  const size = buf.length
  let rms = 0
  for (let i = 0; i < size; i++) rms += buf[i] * buf[i]
  rms = Math.sqrt(rms / size)
  if (rms < 0.01) return -1 // zu leise

  // Trim auf Bereiche oberhalb eines kleinen Schwellwerts
  let r1 = 0
  let r2 = size - 1
  const thres = 0.2
  for (let i = 0; i < size / 2; i++) {
    if (Math.abs(buf[i]) < thres) {
      r1 = i
      break
    }
  }
  for (let i = 1; i < size / 2; i++) {
    if (Math.abs(buf[size - i]) < thres) {
      r2 = size - i
      break
    }
  }
  const trimmed = buf.subarray(r1, r2)
  const n = trimmed.length

  const c = new Float32Array(n).fill(0)
  for (let lag = 0; lag < n; lag++) {
    for (let i = 0; i < n - lag; i++) {
      c[lag] += trimmed[i] * trimmed[i + lag]
    }
  }

  // Erstes Minimum überspringen, dann höchsten Peak suchen
  let d = 0
  while (d < n - 1 && c[d] > c[d + 1]) d++
  let maxval = -1
  let maxpos = -1
  for (let i = d; i < n; i++) {
    if (c[i] > maxval) {
      maxval = c[i]
      maxpos = i
    }
  }
  let t0 = maxpos
  if (t0 <= 0) return -1

  // Parabolische Interpolation für höhere Genauigkeit
  const x1 = c[t0 - 1] ?? 0
  const x2 = c[t0]
  const x3 = c[t0 + 1] ?? 0
  const a = (x1 + x3 - 2 * x2) / 2
  const b = (x3 - x1) / 2
  if (a) t0 = t0 - b / (2 * a)

  return sampleRate / t0
}

export interface ListeningEngineOptions {
  /** Absoluter RMS-Schwellwert für einen Anschlag (0..1). */
  onsetThreshold?: number
  /** Mindestabstand zwischen zwei Anschlägen in ms. */
  refractoryMs?: number
  /** Tonhöhe bei jedem Anschlag mitberechnen. */
  detectPitch?: boolean
  /**
   * Tiefpass-Grenzfrequenz in Hz. Lässt die tiefen Bass-Grundtöne durch und
   * dämpft hohe Anteile wie das durchblutende Metronom (800/1200 Hz Tick).
   * 0 deaktiviert den Filter. Default: 250 Hz.
   */
  lowpassHz?: number
  /**
   * Verstärkung des analysierten Signals (Onset/Pitch/VU). Hebt sehr leise
   * Mikrofone in einen brauchbaren Bereich. Default: 1 (keine Verstärkung).
   * Der rohe Debug-Kanal bleibt davon unberührt.
   */
  inputGain?: number
}

export class ListeningEngine {
  private audioContext: AudioContext | null = null
  private analyser: AnalyserNode | null = null
  private stream: MediaStream | null = null
  private rafId: number | null = null
  private timeBuf: Float32Array = new Float32Array(0)
  private prevLevel = 0
  private noiseFloor = 0.005
  private lastOnset = 0
  private running = false

  // Knoten für Debug-Aufnahme: rohes (vor Filter) und gefiltertes Signal.
  private rawNode: AudioNode | null = null
  private filteredNode: AudioNode | null = null

  private readonly onsetThreshold: number
  private readonly refractoryMs: number
  private readonly wantPitch: boolean
  private readonly lowpassHz: number
  private readonly inputGain: number
  // Gleitendes Maximum des Pegels für ein auto-skalierendes VU-Meter.
  private levelMax = 0.01

  onOnset?: (e: OnsetEvent) => void
  onPitch?: (p: PitchResult | null) => void
  /** Live-Pegel (RMS) für eine Anzeige/VU-Meter. */
  onLevel?: (rms: number) => void

  constructor(opts: ListeningEngineOptions = {}) {
    this.onsetThreshold = opts.onsetThreshold ?? 0.04
    this.refractoryMs = opts.refractoryMs ?? 120
    this.wantPitch = opts.detectPitch ?? true
    this.lowpassHz = opts.lowpassHz ?? 250
    this.inputGain = opts.inputGain ?? 1
  }

  get isRunning() {
    return this.running
  }

  async start(): Promise<void> {
    if (this.running) return
    const Ctx = window.AudioContext || (window as any).webkitAudioContext
    this.audioContext = new Ctx()
    if (this.audioContext.state === "suspended") await this.audioContext.resume()

    this.stream = await navigator.mediaDevices.getUserMedia({
      audio: { echoCancellation: false, noiseSuppression: false, autoGainControl: false },
    })

    const source = this.audioContext.createMediaStreamSource(this.stream)
    this.analyser = this.audioContext.createAnalyser()
    this.analyser.fftSize = 2048
    this.rawNode = source

    // Optionaler Gain VOR dem Analyser hebt sehr leise Mikrofone an.
    // Der Debug-Abgriff (filteredNode) liegt davor, bleibt also ungeboostet.
    const gain = this.audioContext.createGain()
    gain.gain.value = this.inputGain

    if (this.lowpassHz > 0) {
      // Zwei kaskadierte Tiefpässe (~24 dB/Oktave): Bass-Grundtöne bleiben,
      // der hohe Metronom-Tick (800/1200 Hz) wird stark gedämpft.
      const lp1 = this.audioContext.createBiquadFilter()
      const lp2 = this.audioContext.createBiquadFilter()
      lp1.type = "lowpass"
      lp2.type = "lowpass"
      lp1.frequency.value = this.lowpassHz
      lp2.frequency.value = this.lowpassHz
      lp1.Q.value = 0.707
      lp2.Q.value = 0.707
      source.connect(lp1)
      lp1.connect(lp2)
      lp2.connect(gain)
      gain.connect(this.analyser)
      this.filteredNode = lp2
    } else {
      source.connect(gain)
      gain.connect(this.analyser)
      this.filteredNode = source
    }

    this.timeBuf = new Float32Array(this.analyser.fftSize)

    this.running = true
    this.loop()
  }

  /** Liefert die Audio-Uhr (für präzise Metronom-Planung). */
  get context(): AudioContext | null {
    return this.audioContext
  }

  private loop = () => {
    if (!this.running || !this.analyser) return
    this.analyser.getFloatTimeDomainData(this.timeBuf)

    let sum = 0
    for (let i = 0; i < this.timeBuf.length; i++) sum += this.timeBuf[i] * this.timeBuf[i]
    const rms = Math.sqrt(sum / this.timeBuf.length)

    // Auto-skalierendes VU: relativ zum gleitenden Maximum, damit auch sehr
    // leise Mikrofone vollen Ausschlag zeigen. Max langsam abklingen lassen.
    if (rms > this.levelMax) this.levelMax = rms
    else this.levelMax = Math.max(0.01, this.levelMax * 0.999)
    this.onLevel?.(Math.min(1, rms / this.levelMax))

    // Adaptiver Rauschteppich (langsame EMA, nur wenn leise)
    if (rms < this.noiseFloor * 1.5) {
      this.noiseFloor = this.noiseFloor * 0.995 + rms * 0.005
    }

    // Onset-Schwelle: tiefer absoluter Boden + relativ zum Rauschteppich.
    const dynamicThreshold = Math.max(this.onsetThreshold, this.noiseFloor * 5)
    const now = performance.now()
    const rising = rms > dynamicThreshold && this.prevLevel <= dynamicThreshold
    if (rising && now - this.lastOnset > this.refractoryMs) {
      this.lastOnset = now
      this.onOnset?.({ time: now, level: rms })
      if (this.wantPitch && this.onPitch) {
        const freq = detectPitch(this.timeBuf, this.audioContext!.sampleRate)
        if (freq > 0) {
          const { note, cents } = frequencyToNote(freq)
          this.onPitch({ frequency: freq, note, cents })
        } else {
          this.onPitch(null)
        }
      }
    }
    this.prevLevel = rms
    this.rafId = requestAnimationFrame(this.loop)
  }

  /**
   * Zeichnet `durationMs` lang das Mikrofonsignal auf und gibt eine Stereo-WAV
   * zurück: Kanal L = rohes Signal (vor Filter), Kanal R = gefiltertes Signal
   * (nach Tiefpass). Für Debugging des Metronom-Bleeds und der Pegel.
   * Liefert zusätzlich Spitzen-/RMS-Pegel beider Kanäle.
   */
  async recordDebug(durationMs = 6000): Promise<{
    wav: Blob
    sampleRate: number
    rawPeak: number
    rawRms: number
    filteredPeak: number
    filteredRms: number
  }> {
    if (!this.audioContext || !this.rawNode || !this.filteredNode) {
      throw new Error("Engine not started")
    }
    const ctx = this.audioContext
    const bufSize = 4096
    const rawProc = ctx.createScriptProcessor(bufSize, 1, 1)
    const filtProc = ctx.createScriptProcessor(bufSize, 1, 1)
    const rawChunks: Float32Array[] = []
    const filtChunks: Float32Array[] = []

    rawProc.onaudioprocess = (e) => rawChunks.push(new Float32Array(e.inputBuffer.getChannelData(0)))
    filtProc.onaudioprocess = (e) => filtChunks.push(new Float32Array(e.inputBuffer.getChannelData(0)))

    // ScriptProcessor braucht eine Verbindung zum Destination, um zu laufen.
    // Über einen stummen Gain, damit nichts hörbar zurückkommt.
    const mute = ctx.createGain()
    mute.gain.value = 0
    this.rawNode.connect(rawProc)
    this.filteredNode.connect(filtProc)
    rawProc.connect(mute)
    filtProc.connect(mute)
    mute.connect(ctx.destination)

    await new Promise((r) => setTimeout(r, durationMs))

    rawProc.disconnect()
    filtProc.disconnect()
    mute.disconnect()

    const raw = flatten(rawChunks)
    const filt = flatten(filtChunks)
    const n = Math.min(raw.length, filt.length)

    let rawPeak = 0
    let rawSum = 0
    let filtPeak = 0
    let filtSum = 0
    for (let i = 0; i < n; i++) {
      const a = Math.abs(raw[i])
      const b = Math.abs(filt[i])
      if (a > rawPeak) rawPeak = a
      if (b > filtPeak) filtPeak = b
      rawSum += raw[i] * raw[i]
      filtSum += filt[i] * filt[i]
    }

    const wav = encodeWavStereo(raw.subarray(0, n), filt.subarray(0, n), ctx.sampleRate)
    return {
      wav,
      sampleRate: ctx.sampleRate,
      rawPeak,
      rawRms: Math.sqrt(rawSum / n),
      filteredPeak: filtPeak,
      filteredRms: Math.sqrt(filtSum / n),
    }
  }

  stop(): void {
    this.running = false
    this.rawNode = null
    this.filteredNode = null
    if (this.rafId != null) cancelAnimationFrame(this.rafId)
    this.rafId = null
    this.stream?.getTracks().forEach((t) => t.stop())
    this.stream = null
    this.analyser = null
    if (this.audioContext && this.audioContext.state !== "closed") {
      this.audioContext.close().catch(() => {})
    }
    this.audioContext = null
  }
}

function flatten(chunks: Float32Array[]): Float32Array {
  let total = 0
  for (const c of chunks) total += c.length
  const out = new Float32Array(total)
  let off = 0
  for (const c of chunks) {
    out.set(c, off)
    off += c.length
  }
  return out
}

// Kodiert zwei Mono-Spuren als 16-bit PCM Stereo-WAV (L=left, R=right).
function encodeWavStereo(left: Float32Array, right: Float32Array, sampleRate: number): Blob {
  const numFrames = Math.min(left.length, right.length)
  const numChannels = 2
  const bytesPerSample = 2
  const blockAlign = numChannels * bytesPerSample
  const dataSize = numFrames * blockAlign
  const buffer = new ArrayBuffer(44 + dataSize)
  const view = new DataView(buffer)

  const writeStr = (offset: number, s: string) => {
    for (let i = 0; i < s.length; i++) view.setUint8(offset + i, s.charCodeAt(i))
  }
  const clamp = (v: number) => Math.max(-1, Math.min(1, v))

  writeStr(0, "RIFF")
  view.setUint32(4, 36 + dataSize, true)
  writeStr(8, "WAVE")
  writeStr(12, "fmt ")
  view.setUint32(16, 16, true)
  view.setUint16(20, 1, true) // PCM
  view.setUint16(22, numChannels, true)
  view.setUint32(24, sampleRate, true)
  view.setUint32(28, sampleRate * blockAlign, true)
  view.setUint16(32, blockAlign, true)
  view.setUint16(34, 8 * bytesPerSample, true)
  writeStr(36, "data")
  view.setUint32(40, dataSize, true)

  let off = 44
  for (let i = 0; i < numFrames; i++) {
    const l = clamp(left[i]) * 0x7fff
    const r = clamp(right[i]) * 0x7fff
    view.setInt16(off, l, true)
    off += 2
    view.setInt16(off, r, true)
    off += 2
  }
  return new Blob([buffer], { type: "audio/wav" })
}
