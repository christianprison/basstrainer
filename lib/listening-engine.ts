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

  private readonly onsetThreshold: number
  private readonly refractoryMs: number
  private readonly wantPitch: boolean

  onOnset?: (e: OnsetEvent) => void
  onPitch?: (p: PitchResult | null) => void
  /** Live-Pegel (RMS) für eine Anzeige/VU-Meter. */
  onLevel?: (rms: number) => void

  constructor(opts: ListeningEngineOptions = {}) {
    this.onsetThreshold = opts.onsetThreshold ?? 0.04
    this.refractoryMs = opts.refractoryMs ?? 120
    this.wantPitch = opts.detectPitch ?? true
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
    source.connect(this.analyser)
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

    this.onLevel?.(rms)

    // Adaptiver Rauschteppich (langsame EMA, nur wenn leise)
    if (rms < this.noiseFloor * 1.5) {
      this.noiseFloor = this.noiseFloor * 0.995 + rms * 0.005
    }

    const dynamicThreshold = Math.max(this.onsetThreshold, this.noiseFloor * 4)
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

  stop(): void {
    this.running = false
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
