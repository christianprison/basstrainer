"use client"

import { useCallback, useEffect, useRef, useState } from "react"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { ArrowLeft, Bug, Mic, Play, Square } from "lucide-react"
import { ListeningEngine } from "@/lib/listening-engine"

interface PrecisionOctavesProps {
  onBack: () => void
}

// Bewertungsfenster: Abweichung |Δ| zum nächsten Beat (ms) -> Wertung.
const PERFECT_MS = 40
const GOOD_MS = 90
const OK_MS = 160

// Progressives Tempo
const START_BPM = 70
const MIN_BPM = 50
const MAX_BPM = 160
const BEATS_PER_EVAL = 4 // nach so vielen abgeschlossenen Beats Tempo anpassen

type Phase = "intro" | "running" | "denied"

interface HitRating {
  delta: number // signierte Abweichung in ms (+ = zu spät)
  rating: "perfect" | "good" | "ok" | "miss"
}

// Ein geplanter Beat mit stabiler ID (kein Array-Index, der durch Beschneiden
// verrutscht). "settled" = bereits getroffen oder als verpasst gewertet.
interface ScheduledBeat {
  id: number
  time: number
  accent: boolean
  settled: boolean
}

export default function PrecisionOctaves({ onBack }: PrecisionOctavesProps) {
  const [phase, setPhase] = useState<Phase>("intro")
  const [bpm, setBpm] = useState(START_BPM)
  const [level, setLevel] = useState(0)
  const [lastHit, setLastHit] = useState<HitRating | null>(null)
  const [recentRatings, setRecentRatings] = useState<HitRating["rating"][]>([])
  const [stats, setStats] = useState({ perfect: 0, good: 0, ok: 0, miss: 0 })
  const [recording, setRecording] = useState(false)
  const [debugInfo, setDebugInfo] = useState<string | null>(null)

  const engineRef = useRef<ListeningEngine | null>(null)
  // Geplante Beats (mit stabiler ID) in performance.now()-Domain.
  const beatsRef = useRef<ScheduledBeat[]>([])
  const schedulerRef = useRef<number | null>(null)
  const reaperRef = useRef<number | null>(null)
  const beatCountRef = useRef(0)
  // Bewertungen abgeschlossener Beats (Treffer UND Misses) seit letzter Anpassung.
  const evalWindowRef = useRef<HitRating["rating"][]>([])
  const bpmRef = useRef(START_BPM)
  // Aktueller Beat-Index für eine pulsierende Anzeige.
  const [beatPulse, setBeatPulse] = useState(0)

  // Tick-Sound über separaten, kurzlebigen Oszillator (Ausgabe-Context der Engine).
  const playTick = useCallback((accent: boolean) => {
    const ctx = engineRef.current?.context
    if (!ctx) return
    const osc = ctx.createOscillator()
    const gain = ctx.createGain()
    osc.connect(gain)
    gain.connect(ctx.destination)
    osc.frequency.value = accent ? 1200 : 800
    osc.type = "square"
    const t = ctx.currentTime
    gain.gain.setValueAtTime(0.0001, t)
    gain.gain.exponentialRampToValueAtTime(0.25, t + 0.002)
    gain.gain.exponentialRampToValueAtTime(0.0001, t + 0.05)
    osc.start(t)
    osc.stop(t + 0.06)
  }, [])

  const stopExercise = useCallback(() => {
    if (schedulerRef.current != null) {
      clearInterval(schedulerRef.current)
      schedulerRef.current = null
    }
    if (reaperRef.current != null) {
      clearInterval(reaperRef.current)
      reaperRef.current = null
    }
    engineRef.current?.stop()
    engineRef.current = null
    beatsRef.current = []
    setPhase("intro")
  }, [])

  // Zentrale Bewertung eines abgeschlossenen Beats (Treffer oder Miss):
  // aktualisiert Stats, Verlauf und das Tempo-Fenster + ggf. Tempo-Anpassung.
  const settleBeat = useCallback((rating: HitRating["rating"], delta: number | null) => {
    if (delta != null) setLastHit({ delta: Math.round(delta), rating })
    setStats((s) => ({ ...s, [rating]: s[rating] + 1 }))
    setRecentRatings((r) => [rating, ...r].slice(0, 8))

    const w = evalWindowRef.current
    w.push(rating)
    if (w.length >= BEATS_PER_EVAL) {
      const score = w.reduce((a, r) => a + (r === "perfect" ? 1 : r === "good" ? 0.7 : r === "ok" ? 0.3 : 0), 0) / w.length
      evalWindowRef.current = []
      let next = bpmRef.current
      if (score >= 0.75) next = Math.min(MAX_BPM, bpmRef.current + 6) // präzise -> schneller
      else if (score < 0.4) next = Math.max(MIN_BPM, bpmRef.current - 6) // ungenau -> langsamer
      if (next !== bpmRef.current) {
        bpmRef.current = next
        setBpm(next)
      }
    }
  }, [])

  // Ordnet einen Anschlag dem nächstgelegenen, noch offenen Beat zu.
  const evaluateOnset = useCallback((onsetTime: number) => {
    const beats = beatsRef.current
    let best: ScheduledBeat | null = null
    let bestAbs = Infinity
    for (const b of beats) {
      if (b.settled) continue
      const d = Math.abs(onsetTime - b.time)
      if (d < bestAbs) {
        bestAbs = d
        best = b
      }
    }
    // Nur werten, wenn der Anschlag plausibel zu einem Beat gehört.
    if (!best || bestAbs > OK_MS + 60) return

    const delta = onsetTime - best.time
    const abs = Math.abs(delta)
    let rating: HitRating["rating"]
    if (abs <= PERFECT_MS) rating = "perfect"
    else if (abs <= GOOD_MS) rating = "good"
    else if (abs <= OK_MS) rating = "ok"
    else rating = "miss"

    best.settled = true
    settleBeat(rating, delta)
  }, [settleBeat])

  const startExercise = useCallback(async () => {
    const engine = new ListeningEngine({
      detectPitch: false,
      // Werte beziehen sich auf das um inputGain verstärkte Signal.
      onsetThreshold: 0.06,
      refractoryMs: 100,
      lowpassHz: 180, // Metronom-Tick (hochfrequent) stark dämpfen
      inputGain: 25, // sehr leises Mikrofon in brauchbaren Bereich heben
    })
    engine.onLevel = (rms) => setLevel(rms)
    engine.onOnset = (e) => evaluateOnset(e.time)
    engineRef.current = engine

    try {
      await engine.start()
    } catch {
      setPhase("denied")
      return
    }

    setPhase("running")
    setStats({ perfect: 0, good: 0, ok: 0, miss: 0 })
    setRecentRatings([])
    setLastHit(null)
    bpmRef.current = START_BPM
    setBpm(START_BPM)
    beatCountRef.current = 0
    beatsRef.current = []
    evalWindowRef.current = []

    // Look-ahead Scheduler: plant Beats in der performance.now()-Domain.
    const SCHED_INTERVAL = 25 // ms
    const LOOKAHEAD = 120 // ms
    // Zwei Takte Vorlauf, bevor gewertet wird (Einzählen).
    const beatMs0 = 60000 / bpmRef.current
    let nextBeatTime = performance.now() + beatMs0 * 2
    let warmupUntilId = 4 // erste 4 Beats nicht werten (Einzähler)

    schedulerRef.current = window.setInterval(() => {
      const now = performance.now()
      const beatMs = 60000 / bpmRef.current
      while (nextBeatTime < now + LOOKAHEAD) {
        const id = beatCountRef.current
        const accent = id % 4 === 0
        const isWarmup = id < warmupUntilId
        beatsRef.current.push({ id, time: nextBeatTime, accent, settled: isWarmup })
        if (beatsRef.current.length > 48) beatsRef.current.shift()
        playTick(accent)
        setBeatPulse(id)
        beatCountRef.current++
        nextBeatTime += beatMs
      }
    }, SCHED_INTERVAL)

    // Reaper: wertet vergangene, nicht getroffene Beats als "miss" — so läuft
    // die Tempo-Anpassung auch dann, wenn Anschläge ganz ausbleiben.
    reaperRef.current = window.setInterval(() => {
      const now = performance.now()
      for (const b of beatsRef.current) {
        if (!b.settled && now - b.time > OK_MS + 70) {
          b.settled = true
          settleBeat("miss", null)
        }
      }
    }, 60)
  }, [evaluateOnset, playTick, settleBeat])

  const recordDebug = useCallback(async () => {
    const engine = engineRef.current
    if (!engine || recording) return
    setRecording(true)
    setDebugInfo("Nimm 6 s auf … bitte NICHT mitspielen, nur Metronom laufen lassen.")
    try {
      const res = await engine.recordDebug(6000)
      const url = URL.createObjectURL(res.wav)
      const a = document.createElement("a")
      a.href = url
      a.download = `mic-debug-${Date.now()}.wav`
      document.body.appendChild(a)
      a.click()
      a.remove()
      setTimeout(() => URL.revokeObjectURL(url), 5000)
      const fmt = (v: number) => v.toFixed(4)
      setDebugInfo(
        `Aufnahme gespeichert (${res.sampleRate} Hz). ` +
          `Roh: Peak ${fmt(res.rawPeak)}, RMS ${fmt(res.rawRms)} · ` +
          `Gefiltert: Peak ${fmt(res.filteredPeak)}, RMS ${fmt(res.filteredRms)}. ` +
          `WAV: links = roh, rechts = gefiltert.`,
      )
    } catch (e) {
      setDebugInfo("Aufnahme fehlgeschlagen: " + (e as Error).message)
    } finally {
      setRecording(false)
    }
  }, [recording])

  useEffect(() => {
    return () => {
      if (schedulerRef.current != null) clearInterval(schedulerRef.current)
      if (reaperRef.current != null) clearInterval(reaperRef.current)
      engineRef.current?.stop()
    }
  }, [])

  const total = stats.perfect + stats.good + stats.ok + stats.miss
  const accuracy = total > 0 ? Math.round(((stats.perfect + stats.good) / total) * 100) : 0

  return (
    <div className="flex min-h-screen flex-col items-center gap-6 p-6">
      <div className="flex w-full max-w-md items-center gap-3">
        <Button variant="ghost" size="icon" onClick={() => { stopExercise(); onBack() }} aria-label="Zurück">
          <ArrowLeft className="h-5 w-5" />
        </Button>
        <div>
          <h1 className="text-2xl font-bold">Oktaven nach Metronom</h1>
          <p className="text-sm text-muted-foreground">Präzision · Tempo passt sich automatisch an</p>
        </div>
      </div>

      {phase === "intro" && (
        <Card className="w-full max-w-md">
          <CardContent className="flex flex-col items-center gap-4 py-8 text-center">
            <Mic className="h-10 w-10 text-muted-foreground" />
            <p className="text-muted-foreground">
              Spiele Oktaven (z.B. E–E) genau auf jeden Metronom-Schlag. Das Mikrofon misst dein Timing; bei sauberem
              Spiel wird das Tempo erhöht, bei Ungenauigkeit gesenkt.
            </p>
            <Button onClick={startExercise}>
              <Play className="mr-2 h-4 w-4" />
              Mikrofon freigeben & starten
            </Button>
          </CardContent>
        </Card>
      )}

      {phase === "denied" && (
        <Card className="w-full max-w-md">
          <CardContent className="flex flex-col items-center gap-4 py-8 text-center">
            <p className="text-muted-foreground">
              Kein Mikrofon-Zugriff. Bitte erlaube den Zugriff in den Browser-Einstellungen und versuche es erneut.
            </p>
            <Button variant="outline" onClick={() => setPhase("intro")}>Zurück</Button>
          </CardContent>
        </Card>
      )}

      {phase === "running" && (
        <div className="flex w-full max-w-md flex-col gap-4">
          <Card>
            <CardContent className="flex flex-col items-center gap-3 py-6">
              <div className="flex items-baseline gap-2">
                <span className="text-5xl font-bold tabular-nums">{bpm}</span>
                <span className="text-sm text-muted-foreground">BPM</span>
              </div>

              {/* Beat-Indikator: 4 Punkte, der aktuelle Schlag im Takt leuchtet */}
              <div className="flex gap-2">
                {[0, 1, 2, 3].map((i) => {
                  const activeInBar = beatPulse % 4 === i
                  return (
                    <span
                      key={i}
                      className={
                        "h-4 w-4 rounded-full transition-all duration-75 " +
                        (activeInBar
                          ? i === 0
                            ? "scale-125 bg-primary"
                            : "scale-125 bg-foreground"
                          : "bg-muted")
                      }
                    />
                  )
                })}
              </div>

              {/* VU-Meter mit Label */}
              <div className="w-full">
                <div className="mb-1 flex justify-between text-xs text-muted-foreground">
                  <span>Mikrofon-Pegel</span>
                  <span>{Math.round(level * 100)}%</span>
                </div>
                <div className="h-2 w-full overflow-hidden rounded bg-muted">
                  <div
                    className="h-full bg-green-500 transition-[width] duration-75"
                    style={{ width: `${Math.min(100, Math.round(level * 100))}%` }}
                  />
                </div>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardContent className="flex flex-col items-center gap-2 py-6">
              {lastHit ? (
                <>
                  <div
                    className={
                      "text-3xl font-bold " +
                      (lastHit.rating === "perfect"
                        ? "text-green-500"
                        : lastHit.rating === "good"
                          ? "text-lime-500"
                          : lastHit.rating === "ok"
                            ? "text-yellow-500"
                            : "text-red-500")
                    }
                  >
                    {lastHit.rating.toUpperCase()}
                  </div>
                  <div className="text-sm text-muted-foreground tabular-nums">
                    {lastHit.delta > 0 ? "+" : ""}
                    {lastHit.delta} ms {lastHit.delta > 0 ? "(zu spät)" : lastHit.delta < 0 ? "(zu früh)" : ""}
                  </div>
                </>
              ) : (
                <div className="text-muted-foreground">Spiele auf den Beat …</div>
              )}
              <div className="mt-2 flex gap-1">
                {recentRatings.map((r, i) => (
                  <span
                    key={i}
                    className={
                      "h-3 w-3 rounded-full " +
                      (r === "perfect"
                        ? "bg-green-500"
                        : r === "good"
                          ? "bg-lime-500"
                          : r === "ok"
                            ? "bg-yellow-500"
                            : "bg-red-500")
                    }
                  />
                ))}
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardContent className="grid grid-cols-2 gap-2 py-4 text-center text-sm">
              <div>Genauigkeit: <span className="font-semibold tabular-nums">{accuracy}%</span></div>
              <div>Treffer: <span className="font-semibold tabular-nums">{total}</span></div>
              <div className="text-green-500">Perfect: {stats.perfect}</div>
              <div className="text-lime-500">Good: {stats.good}</div>
              <div className="text-yellow-500">Ok: {stats.ok}</div>
              <div className="text-red-500">Miss: {stats.miss}</div>
            </CardContent>
          </Card>

          <Button variant="secondary" onClick={recordDebug} disabled={recording}>
            <Bug className="mr-2 h-4 w-4" />
            {recording ? "Nimm auf …" : "Debug-Aufnahme (6 s)"}
          </Button>

          {debugInfo && (
            <Card>
              <CardContent className="py-3 text-xs text-muted-foreground">{debugInfo}</CardContent>
            </Card>
          )}

          <Button variant="outline" onClick={stopExercise}>
            <Square className="mr-2 h-4 w-4" />
            Stoppen
          </Button>
        </div>
      )}
    </div>
  )
}
