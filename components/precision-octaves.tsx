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
const BEATS_PER_EVAL = 8 // nach so vielen Beats wird das Tempo angepasst

type Phase = "intro" | "running" | "denied"

interface HitRating {
  delta: number // signierte Abweichung in ms (+ = zu spät)
  rating: "perfect" | "good" | "ok" | "miss"
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
  // Geplante Beat-Zeiten in performance.now()-Domain.
  const beatTimesRef = useRef<number[]>([])
  const schedulerRef = useRef<number | null>(null)
  const beatCountRef = useRef(0)
  const evalWindowRef = useRef<HitRating["rating"][]>([])
  const bpmRef = useRef(START_BPM)
  const matchedBeatRef = useRef<Set<number>>(new Set())

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
    engineRef.current?.stop()
    engineRef.current = null
    beatTimesRef.current = []
    setPhase("intro")
  }, [])

  // Bewertet einen Anschlag gegen die nächstgelegene geplante Beat-Zeit.
  const evaluateOnset = useCallback((onsetTime: number) => {
    const beats = beatTimesRef.current
    if (beats.length === 0) return
    // nächstgelegenen Beat finden
    let bestIdx = -1
    let bestAbs = Infinity
    for (let i = 0; i < beats.length; i++) {
      const d = Math.abs(onsetTime - beats[i])
      if (d < bestAbs) {
        bestAbs = d
        bestIdx = i
      }
    }
    if (bestIdx < 0 || matchedBeatRef.current.has(bestIdx)) return
    matchedBeatRef.current.add(bestIdx)

    const delta = onsetTime - beats[bestIdx]
    const abs = Math.abs(delta)
    let rating: HitRating["rating"]
    if (abs <= PERFECT_MS) rating = "perfect"
    else if (abs <= GOOD_MS) rating = "good"
    else if (abs <= OK_MS) rating = "ok"
    else rating = "miss"

    const hit: HitRating = { delta: Math.round(delta), rating }
    setLastHit(hit)
    setStats((s) => ({ ...s, [rating]: s[rating] + 1 }))
    setRecentRatings((r) => [rating, ...r].slice(0, 8))
    evalWindowRef.current.push(rating)
  }, [])

  // Tempo-Anpassung anhand der letzten Bewertungs-Fensters.
  const maybeAdjustTempo = useCallback(() => {
    const w = evalWindowRef.current
    if (w.length < BEATS_PER_EVAL) return
    const score =
      w.reduce((acc, r) => acc + (r === "perfect" ? 1 : r === "good" ? 0.7 : r === "ok" ? 0.3 : 0), 0) / w.length
    evalWindowRef.current = []

    let next = bpmRef.current
    if (score >= 0.8) next = Math.min(MAX_BPM, bpmRef.current + 6) // sehr präzise -> schneller
    else if (score < 0.4) next = Math.max(MIN_BPM, bpmRef.current - 6) // ungenau -> langsamer
    bpmRef.current = next
    setBpm(next)
  }, [])

  const startExercise = useCallback(async () => {
    const engine = new ListeningEngine({
      detectPitch: false,
      onsetThreshold: 0.035,
      refractoryMs: 100,
      lowpassHz: 250, // Metronom-Tick (hochfrequent) aus dem Mikrofonsignal filtern
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
    bpmRef.current = START_BPM
    setBpm(START_BPM)
    beatCountRef.current = 0
    beatTimesRef.current = []
    evalWindowRef.current = []
    matchedBeatRef.current = new Set()

    // Look-ahead Scheduler: plant Beats in der performance.now()-Domain und
    // spielt den Tick. Bewertung erfolgt anhand der geplanten Zeiten.
    const SCHED_INTERVAL = 25 // ms
    const LOOKAHEAD = 120 // ms
    let nextBeatTime = performance.now() + 300 // kleiner Vorlauf

    schedulerRef.current = window.setInterval(() => {
      const now = performance.now()
      const beatMs = 60000 / bpmRef.current
      while (nextBeatTime < now + LOOKAHEAD) {
        const idx = beatCountRef.current
        beatTimesRef.current.push(nextBeatTime)
        // alte Beats beschneiden, Index-Set konsistent halten
        if (beatTimesRef.current.length > 32) {
          beatTimesRef.current.shift()
          // matched-Set zurücksetzen ist ok: alte Indizes sind vorbei
        }
        const accent = idx % 4 === 0
        // Tick zum geplanten Zeitpunkt (kleiner Versatz wird ignoriert)
        playTick(accent)
        beatCountRef.current++

        if (beatCountRef.current % BEATS_PER_EVAL === 0) maybeAdjustTempo()

        nextBeatTime += beatMs
      }
    }, SCHED_INTERVAL)
  }, [evaluateOnset, maybeAdjustTempo, playTick])

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
            <CardContent className="flex flex-col items-center gap-2 py-6">
              <div className="text-5xl font-bold tabular-nums">{bpm}</div>
              <div className="text-sm text-muted-foreground">BPM</div>
              {/* VU-Meter */}
              <div className="mt-2 h-2 w-full overflow-hidden rounded bg-muted">
                <div
                  className="h-full bg-primary transition-[width] duration-75"
                  style={{ width: `${Math.min(100, Math.round(level * 400))}%` }}
                />
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
