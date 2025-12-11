"use client"

import type React from "react"

import { useState, useEffect, useCallback, useRef } from "react"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Trophy, Clock, Pause, Play, RotateCcw } from "lucide-react"
import { Progress } from "@/components/ui/progress"
import confetti from "canvas-confetti"
import { useToast } from "@/hooks/use-toast"
import { Toaster } from "@/components/ui/toaster"
import { CALIBRATED_POSITIONS } from "@/lib/calibrated-positions"
import "@/lib/calibrated-positions.test"

// 5-string bass tuning (B-E-A-D-G from bottom to top)
const STRINGS = ["G", "D", "A", "E", "B"]
const FRETS = 24

const CALIBRATION_REFERENCE_WIDTH = 1883 // Width at which positions were calibrated

const LEARNING_LEVELS = {
  1: {
    name: "Level 1: First Frets",
    description: "Learn natural notes on frets 0, 3, 5, 7 with 50% balance",
    notes: ["C", "D", "E", "F", "G", "A", "B"],
    frets: [0, 3, 5, 7],
    targetBalance: 50,
    color: "oklch(0.80 0.15 90)",
  },
  2: {
    name: "Level 2: Add Fret 9",
    description: "Natural notes on frets 3, 5, 7, 9 with 60% balance",
    notes: ["C", "D", "E", "F", "G", "A", "B"],
    frets: [3, 5, 7, 9],
    targetBalance: 60,
    color: "oklch(0.75 0.15 110)",
  },
  3: {
    name: "Level 3: Add Fret 12",
    description: "Natural notes on frets 3, 5, 7, 9, 12 with 70% balance",
    notes: ["C", "D", "E", "F", "G", "A", "B"],
    frets: [3, 5, 7, 9, 12],
    targetBalance: 70,
    color: "oklch(0.70 0.18 130)",
  },
  4: {
    name: "Level 4: Add Fret 15",
    description: "Natural notes on frets 3, 5, 7, 9, 12, 15 with 80% balance",
    notes: ["C", "D", "E", "F", "G", "A", "B"],
    frets: [3, 5, 7, 9, 12, 15],
    targetBalance: 80,
    color: "oklch(0.65 0.20 150)",
  },
  5: {
    name: "Level 5: Add Fret 17",
    description: "Natural notes on frets 3, 5, 7, 9, 12, 15, 17 with 90% balance",
    notes: ["C", "D", "E", "F", "G", "A", "B"],
    frets: [3, 5, 7, 9, 12, 15, 17],
    targetBalance: 90,
    color: "oklch(0.60 0.22 170)",
  },
  6: {
    name: "Level 6: Add Sharps/Flats",
    description: "All notes on frets 3, 5, 7, 9, 12, 15, 17, 19 with 50% balance",
    notes: ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"],
    frets: [3, 5, 7, 9, 12, 15, 17, 19],
    targetBalance: 50,
    color: "oklch(0.55 0.25 200)",
  },
  7: {
    name: "Level 7: Add Fret 21",
    description: "All notes on frets 3, 5, 7, 9, 12, 15, 17, 19, 21 with 70% balance",
    notes: ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"],
    frets: [3, 5, 7, 9, 12, 15, 17, 19, 21],
    targetBalance: 70,
    color: "oklch(0.50 0.28 230)",
  },
  8: {
    name: "Level 8: Master All Frets",
    description: "All notes on frets 3, 5, 7, 9, 12, 15, 17, 19, 21, 24 with 90% balance",
    notes: ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"],
    frets: [3, 5, 7, 9, 12, 15, 17, 19, 21, 24],
    targetBalance: 90,
    color: "oklch(0.45 0.30 260)",
  },
}

// Calculate note at specific string and fret
function getNoteAtPosition(stringIndex: number, fret: number): string {
  const stringNotes = {
    0: ["G", "G#", "A", "A#", "B", "C", "C#", "D", "D#", "E", "F", "F#"], // G string
    1: ["D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B", "C", "C#"], // D string
    2: ["A", "A#", "B", "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#"], // A string
    3: ["E", "F", "F#", "G", "G#", "A", "A#", "B", "C", "C#", "D", "D#"], // E string
    4: ["B", "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#"], // B string
  }

  const notePattern = stringNotes[stringIndex as keyof typeof stringNotes]
  return notePattern[fret % 12]
}

interface GameStats {
  correct: number
  incorrect: number
  streak: number
  bestStreak: number
  totalTime: number
  averageTime: number
  level: number
  levelProgress: number
}

interface ResponseTimeData {
  [key: string]: {
    // key format: "note-string-fret"
    times: number[]
    average: number
    count: number
    wrongCount: number // Track wrong answers
  }
}

// Define the BassAudioEngine interface
interface BassAudioEngine {
  preloadAudio(): Promise<void>
  unlockAudioContext(): Promise<void>
  playBassNote(stringIndex: number, fret: number): Promise<void> // Changed to return Promise
  playBassTone(stringIndex: number, fret: number): Promise<void> // Changed to return Promise
  playTestBeep(): void // Changed to return void
  playTestWav(): Promise<void> // Adding WAV test method
  playTestMP3?(): Promise<void> // Adding MP3 test method
  playFireworks(): Promise<void> // Add fireworks method
  playFanfare(): Promise<void> // Add fanfare method
  isUnlocked: boolean // Add isUnlocked to the interface
  audioContext: AudioContext | null // Add audioContext to the interface
  playGroove(beatNumber: number): void // Add playGroove method to the interface
}

class SimpleBeepGenerator {
  private audioContext: AudioContext | null = null

  private initAudioContext() {
    if (!this.audioContext) {
      this.audioContext = new (window.AudioContext || (window as any).webkitAudioContext)()
    }
  }

  async playBeep(frequency = 440, duration = 0.3) {
    try {
      this.initAudioContext()
      if (!this.audioContext) return

      // Resume context (wichtig für iOS)
      if (this.audioContext.state === "suspended") {
        await this.audioContext.resume()
      }

      const oscillator = this.audioContext.createOscillator()
      const gainNode = this.audioContext.createGain()

      oscillator.connect(gainNode)
      gainNode.connect(this.audioContext.destination)

      oscillator.frequency.value = frequency
      oscillator.type = "sine"

      gainNode.gain.setValueAtTime(0.3, this.audioContext.currentTime)
      gainNode.gain.exponentialRampToValueAtTime(0.01, this.audioContext.currentTime + duration)

      oscillator.start(this.audioContext.currentTime)
      oscillator.stop(this.audioContext.currentTime + duration)

      console.log("[v0] Beep played at", frequency, "Hz")
    } catch (error) {
      console.error("[v0] Error playing beep:", error)
    }
  }

  async playWavTest() {
    console.log("[v0] Playing WAV test...")
    const audio = new Audio("https://www.soundjay.com/buttons/sounds/beep-07.wav")
    audio.crossOrigin = "anonymous"

    try {
      await audio.play()
      console.log("[v0] WAV test played successfully")
    } catch (error) {
      console.error("[v0] WAV test error:", error)
    }
  }

  async playFireworks() {
    try {
      this.initAudioContext()
      if (!this.audioContext) return

      if (this.audioContext.state === "suspended") {
        await this.audioContext.resume()
      }

      const now = this.audioContext.currentTime

      // PUFF - Tiefer Abschuss-Sound
      const puffOsc = this.audioContext.createOscillator()
      const puffGain = this.audioContext.createGain()

      puffOsc.connect(puffGain)
      puffGain.connect(this.audioContext.destination)

      puffOsc.frequency.setValueAtTime(80, now)
      puffOsc.frequency.exponentialRampToValueAtTime(40, now + 0.15)
      puffOsc.type = "sine"

      puffGain.gain.setValueAtTime(0.3, now)
      puffGain.gain.exponentialRampToValueAtTime(0.01, now + 0.15)

      puffOsc.start(now)
      puffOsc.stop(now + 0.15)

      // PAUSE (400ms)

      // KNISTER KNISTER KNISTER - Mehrere kurze hohe Crackle-Sounds
      const knisterStart = 0.55 // nach puff + pause
      for (let i = 0; i < 15; i++) {
        const delay = knisterStart + Math.random() * 0.8
        const duration = 0.02 + Math.random() * 0.03

        // Weißes Rauschen für Knister-Effekt
        const noise = this.audioContext.createBufferSource()
        const noiseBuffer = this.audioContext.createBuffer(
          1,
          this.audioContext.sampleRate * duration,
          this.audioContext.sampleRate,
        )
        const output = noiseBuffer.getChannelData(0)
        for (let j = 0; j < output.length; j++) {
          output[j] = Math.random() * 2 - 1
        }
        noise.buffer = noiseBuffer

        const noiseGain = this.audioContext.createGain()
        const noiseFilter = this.audioContext.createBiquadFilter()
        noiseFilter.type = "highpass"
        noiseFilter.frequency.value = 3000 + Math.random() * 2000

        noise.connect(noiseFilter)
        noiseFilter.connect(noiseGain)
        noiseGain.connect(this.audioContext.destination)

        const startTime = now + delay
        noiseGain.gain.setValueAtTime(0.1 + Math.random() * 0.15, startTime)
        noiseGain.gain.exponentialRampToValueAtTime(0.01, startTime + duration)

        noise.start(startTime)
        noise.stop(startTime + duration)
      }
    } catch (error) {
      console.error("[v0] Error playing fireworks:", error)
    }
  }

  async playFanfare() {
    try {
      this.initAudioContext()
      if (!this.audioContext) return

      if (this.audioContext.state === "suspended") {
        await this.audioContext.resume()
      }

      const now = this.audioContext.currentTime
      const notes = [
        { freq: 523.25, time: 0 }, // C5
        { freq: 659.25, time: 0.15 }, // E5
        { freq: 783.99, time: 0.3 }, // G5
        { freq: 1046.5, time: 0.45 }, // C6
      ]

      notes.forEach(({ freq, time }) => {
        const oscillator = this.audioContext!.createOscillator()
        const gainNode = this.audioContext!.createGain()

        oscillator.connect(gainNode)
        gainNode.connect(this.audioContext!.destination)

        oscillator.frequency.value = freq
        oscillator.type = "triangle"

        const startTime = now + time
        gainNode.gain.setValueAtTime(0.3, startTime)
        gainNode.gain.exponentialRampToValueAtTime(0.01, startTime + 0.3)

        oscillator.start(startTime)
        oscillator.stop(startTime + 0.3)
      })
    } catch (error) {
      console.error("[v0] Error playing fanfare:", error)
    }
  }

  // Replaced SimpleBeepGenerator.playBeep with a more complex groove
  // Removed playGroove from here as it's now part of RealBassAudioEngine
}

class RealBassAudioEngine implements BassAudioEngine {
  private audioContext: AudioContext | null = null
  private audioBuffers: Map<string, AudioBuffer> = new Map()
  private _isUnlocked = false
  private beepGenerator = new SimpleBeepGenerator()

  private readonly audioSources: Record<string, string> = {
    B_000: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/B_000-FeNysNeY4B7OeQNT13Yo5mvFPlDFhh.mp3",
    B_001: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/B_001-jh6CZgsA1vCQSi0qA12o0KuBWCfCeS.mp3",
    B_002: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/B_002-5rbRsWg8xHmewKcyxu3ZCxugs5XdwX.mp3",
    B_003: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/B_003-Q3WGuRARsZMtMxMOAV7jSfOCFVBO8v.mp3",
    B_004: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/B_004-eRdfPOvoXhz8LoXqC05MGemeNyskJi.mp3",
    B_005: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/B_005-2Ig6PvAK63fg9MvDxInxzWbHODMtCY.mp3",
    B_006: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/B_006-o7ltsjmkvQ5v2GIK6dE6Tu5Nyh3On5.mp3",
    B_007: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/B_007-XFVqLAo4HVkRaJNxlLmvjMxG9i1CJI.mp3",
    B_008: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/B_008-qv4o11rR21QgJzgk3TKIf95UmKIaj4.mp3",
    B_009: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/B_009-xpZ75flVMUp9pOaTTtAaFNBrZlccqF.mp3",
    B_010: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/B_010-97bLAdlvbbA82MbdFjZL5nlr18f32m.mp3",
    B_011: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/B_011-eXeNHIZD7rNHVXVzJwsjgxLzXRiTns.mp3",
    B_012: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/B_012-00yhlMKhCn7nlSanfy1XlKv2OXtVFn.mp3",
    E_000: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/E_000-8XiKLfO8usjuD4lcUHr8TBQE6ht5xf.mp3",
    E_001: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/E_001-gQWpBqrCI5CxKBLlbw8YisBi2Z8rHp.mp3",
    E_002: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/E_002-2BMKO95RIzZvgFcTRCFujUl263V7Oh.mp3",
    E_003: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/E_003-a5B1xl96kRO1mQu6NQsM1Ww7I47CaT.mp3",
    E_004: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/E_004-rqSjF8PT73gvgnR3XVG8GI6Igs2fcp.mp3",
    E_005: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/E_005-geCBQc0VOYGoPjZVUisHpUBXvr80dw.mp3",
    E_006: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/E_006-Rk6CIpTUNjtOesk5Tt0AeeDvPEDvvC.mp3",
    E_007: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/E_007-N4so9dL1PfOtnbtM9lJ3coQW9sgRNc.mp3",
    E_008: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/E_008-RYxiVQi6rSbd21mZEaqqeVz2Fsmk7G.mp3",
    E_009: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/E_009-OzNczjrn3Yv3zRLRfe7AovQdpjzvCq.mp3",
    E_010: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/E_010-kwcBwkek4QHxEwHWhc6yJLGz2va7DP.mp3",
    E_011: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/E_011-7Q7AkvlqJR4oqQWcyQzEZ9MYRXPCLQ.mp3",
    E_012: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/E_012-NRO5hGh0gh0Znx16u6MpRSvbGAWhRi.mp3",
    A_000: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/A_000-n1wP0wWaVVFAQ7Gfpm1rjZLcnJcWZF.mp3",
    A_001: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/A_001-w0YA4hgLw2qR5tDhZ4JoHk7wBmNPfE.mp3",
    A_002: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/A_002-QsTu2UPtrj1hyeXxDx1N6gSEHkthux.mp3",
    A_003: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/A_003-6nHbCkv6rEhmk7Ue4bOKuWuv5H5tnS.mp3",
    A_004: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/A_004-G1f56nczk2dmbRAsaejoEVfE6DpDOl.mp3",
    A_005: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/A_005-uxygYwBTKYsjvwM8yjJcs2lKokbhEb.mp3",
    A_006: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/A_006-jDzPWLYdQOLkNQ2gwYaSZFRpx5oXIl.mp3",
    A_007: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/A_007-C1cr3WrmY54RU6VzRlMvyDBAsJ3W0S.mp3",
    A_008: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/A_008-pRBv0rgsMZXbFtZAC3NtIu20WgnUkp.mp3",
    A_009: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/A_009-s3SNCkcebaeKo3sXWRJfOTOclkFs1E.mp3",
    A_010: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/A_010-BqnBZ5DBWQ1DDChfGt3hyYGTaRdUTK.mp3",
    A_011: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/A_011-2eNs8Zf8S8U9gJ8sdK8OBpKKSfKLQy.mp3",
    A_012: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/A_012-GQah8UrTNpH2breV32PBER5sWqSDKh.mp3",
    D_000: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/D_000-6RiUal4vF5Nm1XnKmMbYIVgtk6W4EN.mp3",
    D_001: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/D_001-eO9UPBsftB2iiyebxoyqZrjswyKqfY.mp3",
    D_002: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/D_002-7JznZaa4MWxZtLaXdCWbuo2EpJHNfR.mp3",
    D_003: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/D_003-KQhZOTzMLqOCmtI5isWJJkQuqHd5jF.mp3",
    D_004: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/D_004-yuHyBNowfT9FAKzGvggPgCv1lEqj2E.mp3",
    D_005: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/D_005-NXHcVqxbpC6QNkoEhNq0Ut6eCrKZ5K.mp3",
    D_006: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/D_006-ScxGfkC8Dt95yMVaP1BfVOTe4Q1ghk.mp3",
    D_007: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/D_007-E6Mbcm290hkG4NlZcp2SwLjzKs9rIe.mp3",
    D_008: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/D_008-omSa53zTaUVjWVly42t6SgCrTwi89Q.mp3",
    D_009: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/D_009-ZxxXmg74jMHCiiJ43LuEyPdYpcwPDV.mp3",
    D_010: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/D_010-oU5q0mqrTfOaPSOXvXGHAcNu6U0gp0.mp3",
    D_011: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/D_011-81jyfQXs6DjEB0oo9Kky5KolIH7JPF.mp3",
    D_012: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/D_012-3Vn0jUVjzexo9mB6erXivewI7qf7SN.mp3",
    G_000: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/G_000-2FEOTkp5wWEUYCP4WPFJgkg2lR2I6P.mp3",
    G_001: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/G_001-mnMSLfpyS9EuLjNaKJCAC56ZOVjiph.mp3",
    G_002: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/G_002-POT0V8ICau6HHmVRQeq4ZrLgOJFiMM.mp3",
    G_003: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/G_003-YxvfhHLhwB7pAYIPIzEhKo1qSfDx4l.mp3",
    G_004: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/G_004-Us2cOuWPwCibcuknw3KHlSLFW0KWEJ.mp3",
    G_005: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/G_005-7rpS3u75Ky4oVOVdImQpIODEWJBHq9.mp3",
    G_006: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/G_006-f0liOINUxpnWVqwevpDBA6w1rPGOQb.mp3",
    G_007: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/G_007-UMwbRVHLo2z73sMmdudm29ICmNuhZy.mp3",
    G_008: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/G_008-QOeHNbx258szcdnZTOZvbAHRHohE3P.mp3",
    G_009: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/G_009-24DBqF2Gum4hmb55kG5KVkWo32gchr.mp3",
    G_010: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/G_010-40F0btfDyNQ53MUVIo8JsJpVftT711.mp3",
    G_011: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/G_011-TQqvv817NvCVc1sr6TMO6ZEWZJHR2G.mp3",
    G_012: "https://hebbkx1anhila5yf.public.blob.vercel-storage.com/G_012-BoiJKO8VLQMXngCzWu2Fz5xvEUZv7g.mp3",
  }

  constructor() {
    this.audioContext = new (window.AudioContext || (window as any).webkitAudioContext)()
    console.log("[v0] Web Audio API initialized")
  }

  get isUnlocked(): boolean {
    return this._isUnlocked
  }

  // Add audioContext getter to the class
  get audioContext(): AudioContext | null {
    return this.audioContext
  }

  private getAudioKey(stringIndex: number, fret: number): string {
    const stringName = STRINGS[stringIndex]
    const fretPadded = fret.toString().padStart(3, "0")
    return `${stringName}_${fretPadded}`
  }

  async preloadAudio(): Promise<void> {
    console.log("[v0] Preloading audio with Web Audio API...")

    // Nur die ersten paar Dateien laden für schnelleren Start
    const keysToPreload = Object.keys(this.audioSources).slice(0, 10)

    const promises = keysToPreload.map(async (key) => {
      const url = this.audioSources[key]
      try {
        const response = await fetch(url)
        const arrayBuffer = await response.arrayBuffer()
        const audioBuffer = await this.audioContext!.decodeAudioData(arrayBuffer)
        this.audioBuffers.set(key, audioBuffer)
        console.log("[v0] Loaded:", key)
      } catch (error) {
        console.warn("[v0] Failed to load:", key, error)
      }
    })

    await Promise.all(promises)
    console.log("[v0] Audio preload complete")
  }

  async unlockAudioContext(): Promise<void> {
    if (this._isUnlocked || !this.audioContext) return

    console.log("[v0] Unlocking Web Audio API...")

    // iOS unlock: stummes Abspielen
    if (this.audioContext.state === "suspended") {
      await this.audioContext.resume()
    }

    this._isUnlocked = true
    console.log("[v0] Web Audio API unlocked")
  }

  async playBassNote(stringIndex: number, fret: number): Promise<void> {
    if (!this.audioContext) return

    const key = this.getAudioKey(stringIndex, fret)

    // iOS beim ersten Mal entsperren
    if (!this._isUnlocked) {
      await this.unlockAudioContext()
    }

    // Buffer laden, falls nicht schon geladen
    let buffer = this.audioBuffers.get(key)
    if (!buffer) {
      const url = this.audioSources[key]
      if (!url) {
        console.warn("[v0] Audio not found:", key)
        return
      }

      try {
        console.log("[v0] Loading on-demand:", key)
        const response = await fetch(url)
        const arrayBuffer = await response.arrayBuffer()
        buffer = await this.audioContext.decodeAudioData(arrayBuffer)
        this.audioBuffers.set(key, buffer)
      } catch (error) {
        console.error("[v0] Error loading audio:", key, error)
        return
      }
    }

    // Abspielen mit Web Audio API
    const source = this.audioContext.createBufferSource()
    source.buffer = buffer
    source.connect(this.audioContext.destination)
    source.start(0)
    console.log("[v0] Playing:", key)
  }

  playTestBeep(): void {
    this.beepGenerator.playBeep()
  }

  async playTestWav(): Promise<void> {
    console.log("[v0] Testing external WAV...")
    const audio = new Audio()
    audio.src = "https://www.soundjay.com/misc/sounds/bell-ringing-05.wav"
    try {
      await audio.play()
      console.log("[v0] WAV playing")
    } catch (error) {
      console.error("[v0] WAV error:", error)
    }
  }

  async playTestMP3(): Promise<void> {
    console.log("[v0] Testing external MP3...")
    const audio = new Audio()
    audio.src = "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3"
    try {
      await audio.play()
      console.log("[v0] MP3 playing")
    } catch (error) {
      console.error("[v0] MP3 error:", error)
    }
  }

  async playBassTone(stringIndex: number, fret: number): Promise<void> {
    await this.playBassNote(stringIndex, fret)
  }

  async playFireworks(): Promise<void> {
    await this.beepGenerator.playFireworks()
  }

  async playFanfare(): Promise<void> {
    await this.beepGenerator.playFanfare()
  }

  playGroove(beatNumber: number) {
    if (!this.audioContext) return

    const ctx = this.audioContext
    const now = ctx.currentTime

    // Kick drum on beats 1 and 3 (quarters)
    if (beatNumber % 4 === 0 || beatNumber % 4 === 2) {
      const kickOsc = ctx.createOscillator()
      const kickGain = ctx.createGain()
      kickOsc.connect(kickGain)
      kickGain.connect(ctx.destination)

      kickOsc.frequency.setValueAtTime(150, now)
      kickOsc.frequency.exponentialRampToValueAtTime(40, now + 0.1)
      kickGain.gain.setValueAtTime(0.8, now)
      kickGain.gain.exponentialRampToValueAtTime(0.01, now + 0.15)

      kickOsc.start(now)
      kickOsc.stop(now + 0.15)
    }

    // Snare on beats 2 and 4
    if (beatNumber % 4 === 1 || beatNumber % 4 === 3) {
      const snareOsc = ctx.createOscillator()
      const snareNoise = ctx.createBufferSource()
      const snareGain = ctx.createGain()
      const snareFilter = ctx.createBiquadFilter()

      const bufferSize = ctx.sampleRate * 0.05
      const buffer = ctx.createBuffer(1, bufferSize, ctx.sampleRate)
      const data = buffer.getChannelData(0)
      for (let i = 0; i < bufferSize; i++) {
        data[i] = Math.random() * 2 - 1
      }
      snareNoise.buffer = buffer

      snareFilter.type = "highpass"
      snareFilter.frequency.value = 1000

      snareOsc.connect(snareGain)
      snareNoise.connect(snareFilter)
      snareFilter.connect(snareGain)
      snareGain.connect(ctx.destination)

      snareOsc.frequency.value = 200
      snareGain.gain.setValueAtTime(0.4, now)
      snareGain.gain.exponentialRampToValueAtTime(0.01, now + 0.1)

      snareOsc.start(now)
      snareNoise.start(now)
      snareOsc.stop(now + 0.1)
      snareNoise.stop(now + 0.1)
    }

    // Hi-hat on all 8th notes (every beat)
    const hihatNoise = ctx.createBufferSource()
    const hihatGain = ctx.createGain()
    const hihatFilter = ctx.createBiquadFilter()

    const bufferSize = ctx.sampleRate * 0.02
    const buffer = ctx.createBuffer(1, bufferSize, ctx.sampleRate)
    const data = buffer.getChannelData(0)
    for (let i = 0; i < bufferSize; i++) {
      data[i] = Math.random() * 2 - 1
    }
    hihatNoise.buffer = buffer

    hihatFilter.type = "highpass"
    hihatFilter.frequency.value = 7000

    hihatNoise.connect(hihatFilter)
    hihatFilter.connect(hihatGain)
    hihatGain.connect(ctx.destination)

    hihatGain.gain.setValueAtTime(0.15, now)
    hihatGain.gain.exponentialRampToValueAtTime(0.01, now + 0.03)

    hihatNoise.start(now)
    hihatNoise.stop(now + 0.03)
  }
}

export default function BassTrainer() {
  const [isPlaying, setIsPlaying] = useState(false)
  const [currentPosition, setCurrentPosition] = useState<{ string: number; fret: number } | null>(null)
  const [currentNote, setCurrentNote] = useState<string>("")
  const [userInput, setUserInput] = useState("")
  const [timeLeft, setTimeLeft] = useState(0)
  const [gameStats, setGameStats] = useState<GameStats>({
    correct: 0,
    incorrect: 0,
    streak: 0,
    bestStreak: 0,
    totalTime: 0,
    averageTime: 0,
    level: 1,
    levelProgress: 0,
  })
  const [feedback, setFeedback] = useState<"correct" | "incorrect" | null>(null)
  const [startTime, setStartTime] = useState<number>(0)
  const [gameComplete, setGameComplete] = useState(false)
  const [levelFeedback, setLevelFeedback] = useState<string | null>(null) // Changed to string | null
  const [achievements, setAchievements] = useState<Set<string>>(new Set())
  const { toast } = useToast()

  const [responseTimes, setResponseTimes] = useState<ResponseTimeData>({})
  const [imageScale, setImageScale] = useState(1)

  const [recentNotes, setRecentNotes] = useState<Array<{ note: string; timestamp: number }>>([])
  const [metronomeInterval, setMetronomeInterval] = useState<NodeJS.Timeout | null>(null)
  const [gameStartTime, setGameStartTime] = useState<number>(0)

  // Use the new audio engine class
  const audioEngineRef = useRef<RealBassAudioEngine | null>(null)
  const fretboardRef = useRef<HTMLDivElement>(null)
  const imageRef = useRef<HTMLImageElement>(null)

  const playGrooveCallback = useCallback((beatNumber: number) => {
    if (audioEngineRef.current?.audioContext) {
      audioEngineRef.current.playGroove(beatNumber)
    }
  }, [])

  const playMetronomeClick = useCallback(() => {
    if (!audioEngineRef.current?.audioContext) return

    const ctx = audioEngineRef.current.audioContext
    const oscillator = ctx.createOscillator()
    const gainNode = ctx.createGain()

    oscillator.connect(gainNode)
    gainNode.connect(ctx.destination)

    oscillator.frequency.value = 800
    oscillator.type = "sine"

    gainNode.gain.setValueAtTime(0.3, ctx.currentTime)
    gainNode.gain.exponentialRampToValueAtTime(0.01, ctx.currentTime + 0.05)

    oscillator.start(ctx.currentTime)
    oscillator.stop(ctx.currentTime + 0.05)
  }, [])

  const triggerConfetti = useCallback((intensity: "small" | "medium" | "large" = "medium") => {
    const particleCount = intensity === "small" ? 50 : intensity === "medium" ? 100 : 200
    const spread = intensity === "small" ? 60 : intensity === "medium" ? 90 : 120

    confetti({
      particleCount,
      spread,
      origin: { y: 0.6 },
      colors: ["#ff6b6b", "#4ecdc4", "#45b7d1", "#f9ca24", "#6c5ce7"],
    })

    if (audioEngineRef.current) {
      audioEngineRef.current.playFireworks()
    }
  }, [])

  const getNotePositionData = useCallback(
    (level: number) => {
      // Added level parameter
      const positionData: Array<{
        string: number
        fret: number
        note: string
        average: number
        count: number
        sortKey: number
      }> = []

      const levelData = LEARNING_LEVELS[level as keyof typeof LEARNING_LEVELS]

      // Collect all positions for current level
      Object.keys(responseTimes).forEach((key) => {
        const [note, stringStr, fretStr] = key.split("-")
        const string = Number.parseInt(stringStr)
        const fret = Number.parseInt(fretStr)

        if (levelData.notes.includes(note) && levelData.frets.includes(fret) && responseTimes[key].times.length > 0) {
          // Sort by fret first (lower frets first), then by string (lower strings first)
          // This groups positions by fret, with all strings for each fret together
          const sortKey = fret * 100 + (4 - string) // (4-string) for B->G order, 0->4

          positionData.push({
            string,
            fret,
            note,
            average: responseTimes[key].average,
            count: responseTimes[key].times.length,
            sortKey,
          })
        }
      })

      // Sort by fret first, then by string (low to high)
      positionData.sort((a, b) => a.sortKey - b.sortKey)

      return positionData
    },
    [responseTimes],
  )

  const checkAchievements = useCallback(
    (key: string, count: number, note: string, string: number, fret: number) => {
      const achievementKey = `${key}-3x`

      if (count === 3 && !achievements.has(achievementKey)) {
        setAchievements((prev) => new Set(prev).add(achievementKey))
      }

      if (
        gameStats.correct > 0 &&
        gameStats.correct % 50 === 0 &&
        !achievements.has(`50-correct-${gameStats.correct}`)
      ) {
        setAchievements((prev) => new Set(prev).add(`50-correct-${gameStats.correct}`))
        triggerConfetti("large")
        setTimeout(() => {
          toast({
            description: `${gameStats.correct} correct notes! 🎯`,
            duration: 2000,
          })
        }, 0)
      }

      if (gameStartTime > 0) {
        const elapsedMinutes = Math.floor((Date.now() - gameStartTime) / 60000)
        if (elapsedMinutes > 0 && elapsedMinutes % 5 === 0 && !achievements.has(`5-min-${elapsedMinutes}`)) {
          setAchievements((prev) => new Set(prev).add(`5-min-${elapsedMinutes}`))
          triggerConfetti("medium")
          setTimeout(() => {
            toast({
              description: `${elapsedMinutes} minutes! Keep going! ⏱️`,
              duration: 2000,
            })
          }, 0)
        }
      }

      // Track recent notes for pattern detection
      const now = Date.now()
      const updatedNotes = [...recentNotes, { note, timestamp: now }].filter((n) => now - n.timestamp < 10000) // Keep only notes from last 10 seconds
      setRecentNotes(updatedNotes)

      // Triple A achievement
      if (updatedNotes.length >= 3) {
        const lastThree = updatedNotes.slice(-3).map((n) => n.note)
        if (lastThree.every((n) => n === "A")) {
          setTimeout(() => {
            triggerConfetti("medium")
            toast({
              description: "Triple A! 🎯",
              duration: 2000,
            })
          }, 0)
        }
      }

      // BACH achievement
      if (updatedNotes.length >= 4) {
        const lastFour = updatedNotes.slice(-4).map((n) => n.note)
        if (lastFour.every((n) => ["B", "A", "C", "H"].includes(n)) && lastFour.join("") === "BACH") {
          setAchievements((prev) => new Set(prev).add("bach"))
          triggerConfetti("large")
          setTimeout(() => {
            toast({
              description: "B-A-C-H! 🎼",
              duration: 3000,
            })
          }, 0)
        }
      }

      // Speed demon: 3 correct notes in 2 seconds
      if (updatedNotes.length >= 3) {
        const lastThree = updatedNotes.slice(-3)
        if (lastThree[2].timestamp - lastThree[0].timestamp < 2000) {
          setAchievements((prev) => new Set(prev).add("speed-demon"))
          triggerConfetti("medium")
          setTimeout(() => {
            toast({
              description: "Speed Demon! ⚡",
              duration: 2000,
            })
          }, 0)
        }
      }

      // All strings: played all 5 strings
      const uniqueStrings = new Set(updatedNotes.map((n) => n.note[0])) // Assuming note is like "A", "C#", etc.
      if (uniqueStrings.size === 5 && !achievements.has("all-strings")) {
        setAchievements((prev) => new Set(prev).add("all-strings"))
        triggerConfetti("medium")
        setTimeout(() => {
          toast({
            description: "All Strings! 🎸",
            duration: 2000,
          })
          setRecentNotes([]) // Reset after achievement
        }, 0)
      }

      // Perfect fifth: C and G in sequence
      if (updatedNotes.length >= 2) {
        const lastTwo = updatedNotes.slice(-2).map((n) => n.note)
        if ((lastTwo[0] === "C" && lastTwo[1] === "G") || (lastTwo[0] === "G" && lastTwo[1] === "C")) {
          setAchievements((prev) => new Set(prev).add("perfect-fifth"))
          triggerConfetti("small")
          setTimeout(() => {
            toast({
              description: "Perfect Fifth! 🎵",
              duration: 2000,
            })
          }, 0)
        }
      }

      // Chromatic: 3 consecutive semitones
      const noteOrder = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
      if (updatedNotes.length >= 3) {
        const lastThreeNotes = updatedNotes.slice(-3).map((n) => n.note)
        const indices = lastThreeNotes.map((n) => noteOrder.indexOf(n)).filter((i) => i !== -1)
        if (
          indices.length === 3 &&
          indices[1] === indices[0] + 1 &&
          indices[2] === indices[1] + 1 &&
          !achievements.has("chromatic")
        ) {
          setAchievements((prev) => new Set(prev).add("chromatic"))
          triggerConfetti("medium")
          setTimeout(() => {
            toast({
              description: "Chromatic Run! 🎹",
              duration: 2000,
            })
          }, 0)
        }
      }

      // Check progress milestones
      const levelPositions = getNotePositionData(gameStats.level)
      const totalPositions = levelPositions.length
      const positionsWithMinAttempts = Object.values(responseTimes).filter((rt) => rt.count >= 3).length // Use 3 for consistency with balanceReady

      const progress = totalPositions > 0 ? positionsWithMinAttempts / totalPositions : 0

      if (progress >= 0.25 && !achievements.has(`level-${gameStats.level}-25`)) {
        setAchievements((prev) => new Set(prev).add(`level-${gameStats.level}-25`))
        triggerConfetti("small")
        setTimeout(() => {
          toast({
            description: `25% mastered`,
            duration: 2000,
          })
        }, 0)
      }

      if (progress >= 0.5 && !achievements.has(`level-${gameStats.level}-50`)) {
        setAchievements((prev) => new Set(prev).add(`level-${gameStats.level}-50`))
        triggerConfetti("medium")
        setTimeout(() => {
          toast({
            description: `50% mastered`,
            duration: 2000,
          })
        }, 0)
      }

      if (progress >= 0.75 && !achievements.has(`level-${gameStats.level}-75`)) {
        setAchievements((prev) => new Set(prev).add(`level-${gameStats.level}-75`))
        triggerConfetti("medium")
        setTimeout(() => {
          toast({
            description: `75% mastered`,
            duration: 2000,
          })
        }, 0)
      }
    },
    [
      achievements,
      gameStats.level,
      responseTimes,
      triggerConfetti,
      toast,
      recentNotes,
      getNotePositionData,
      gameStats.correct,
      gameStartTime,
    ],
  )

  useEffect(() => {
    // Only trigger the toast if levelFeedback is not null
    if (levelFeedback) {
      setTimeout(() => {
        triggerConfetti("medium")
        if (audioEngineRef.current) {
          audioEngineRef.current.playFanfare()
        }
        toast({
          description: levelFeedback,
          duration: 3000,
        })
      }, 100)
      setLevelFeedback(null) // Reset after showing the toast
    }
  }, [levelFeedback, toast, triggerConfetti])

  const calculateBalanceScore = useCallback(
    (level: number): number => {
      const currentLevel = LEARNING_LEVELS[level as keyof typeof LEARNING_LEVELS]

      const relevantKeys = Object.keys(responseTimes).filter((key) => {
        const [note, , fret] = key.split("-")
        const fretNum = Number.parseInt(fret)
        return (
          currentLevel.notes.includes(note) && currentLevel.frets.includes(fretNum) && responseTimes[key].count >= 3
        ) // Need at least 3 correct attempts
      })

      if (relevantKeys.length < 2) {
        return 0
      }

      const averages = relevantKeys.map((key) => {
        const times = responseTimes[key].times.slice(-50)
        return times.reduce((sum, time) => sum + time, 0) / times.length
      })

      const overallAverage = averages.reduce((sum, avg) => sum + avg, 0) / averages.length
      const maxDeviation = Math.max(...averages.map((avg) => Math.abs(avg - overallAverage)))

      // Balance = 100% - (max_deviation / overall_average * 100%)
      const deviationPercentage = (maxDeviation / overallAverage) * 100

      const balance = Math.max(0, 100 - deviationPercentage)

      return balance
    },
    [responseTimes],
  )

  const checkLevelCompletion = useCallback(
    (level: number): boolean => {
      const currentLevel = LEARNING_LEVELS[level as keyof typeof LEARNING_LEVELS]
      const balanceScore = calculateBalanceScore(level)

      const allPositions: string[] = []
      for (let string = 0; string < 5; string++) {
        for (const fret of currentLevel.frets) {
          const note = getNoteAtPosition(string, fret)
          if (currentLevel.notes.includes(note)) {
            allPositions.push(`${note}-${string}-${fret}`)
          }
        }
      }

      // Check if all positions have at least 3 correct attempts
      const allPositionsReady = allPositions.every((key) => {
        const data = responseTimes[key]
        return data && data.count >= 3
      })

      if (!allPositionsReady) return false

      // Check if balance meets the target for this level
      return balanceScore >= currentLevel.targetBalance
    },
    [calculateBalanceScore, responseTimes],
  )

  const generateAdaptivePosition = useCallback(() => {
    const currentLevel = LEARNING_LEVELS[gameStats.level as keyof typeof LEARNING_LEVELS]

    // Get all valid positions
    const validPositions: Array<{ string: number; fret: number; note: string; weight: number }> = []

    for (let string = 0; string < 5; string++) {
      for (const fret of currentLevel.frets) {
        const note = getNoteAtPosition(string, fret)
        if (currentLevel.notes.includes(note)) {
          const key = `${note}-${string}-${fret}`
          const responseData = responseTimes[key]

          // Calculate weight: higher average time = higher weight (more likely to be selected)
          let weight = 1
          if (responseData && responseData.count > 0) {
            // Normalize weight based on average response time
            const avgTime = responseData.average
            const maxTime = Math.max(
              ...Object.values(responseTimes)
                .filter((data) => data.count > 0)
                .map((data) => data.average),
              2000,
            )
            weight = Math.max(0.1, avgTime / maxTime) * 2 // Slower responses get higher weight
          } else {
            weight = 2 // New positions get high weight
          }

          validPositions.push({ string, fret, note, weight })
        }
      }
    }

    if (validPositions.length === 0) {
      // Fallback to random selection
      const string = Math.floor(Math.random() * 5)
      const fret = currentLevel.frets[Math.floor(Math.random() * currentLevel.frets.length)]
      const note = getNoteAtPosition(string, fret)
      return { string, fret, note }
    }

    // Weighted random selection
    const totalWeight = validPositions.reduce((sum, pos) => sum + pos.weight, 0)
    let random = Math.random() * totalWeight

    for (const position of validPositions) {
      random -= position.weight
      if (random <= 0) {
        return { string: position.string, fret: position.fret, note: position.note }
      }
    }

    // Fallback
    return validPositions[0]
  }, [gameStats.level, responseTimes])

  // Start new round
  const startNewRound = useCallback(() => {
    const position = generateAdaptivePosition()
    setCurrentPosition({ string: position.string, fret: position.fret })
    setCurrentNote(position.note)
    setUserInput("")
    setFeedback(null)
    setTimeLeft(8000) // 8 second time limit
    setStartTime(Date.now())
  }, [generateAdaptivePosition])

  const submitAnswer = useCallback(
    (answer: string) => {
      if (!currentNote || !isPlaying || !currentPosition) return

      const responseTime = Date.now() - startTime
      const isCorrect = answer.toLowerCase() === currentNote.toLowerCase()

      setFeedback(isCorrect ? "correct" : "incorrect")

      // </CHANGE> Removed toast for wrong answers - only show toasts with confetti

      if (isCorrect && audioEngineRef.current && currentPosition) {
        audioEngineRef.current.playBassNote(currentPosition.string, currentPosition.fret)
      }

      const key = `${currentNote}-${currentPosition.string}-${currentPosition.fret}`
      setResponseTimes((prev) => {
        const existing = prev[key] || { times: [], average: 0, count: 0, wrongCount: 0 }

        if (isCorrect) {
          const newTimes = [...existing.times, responseTime].slice(-10) // Keep last 10 attempts
          const newAverage = newTimes.reduce((sum, time) => sum + time, 0) / newTimes.length
          const newCount = existing.count + 1

          checkAchievements(key, newCount, currentNote, currentPosition.string, currentPosition.fret)

          return {
            ...prev,
            [key]: {
              times: newTimes,
              average: newAverage,
              count: newCount,
              wrongCount: existing.wrongCount,
            },
          }
        } else {
          // Wrong answer: add 10s penalty to average calculation
          const penaltyTime = 10000
          const newTimes = [...existing.times, penaltyTime].slice(-10)
          const newAverage = newTimes.reduce((sum, time) => sum + time, 0) / newTimes.length

          return {
            ...prev,
            [key]: {
              times: newTimes,
              average: newAverage,
              count: existing.count,
              wrongCount: existing.wrongCount + 1,
            },
          }
        }
      })

      setGameStats((prev) => {
        const newStats = {
          ...prev,
          correct: prev.correct + (isCorrect ? 1 : 0),
          incorrect: prev.incorrect + (isCorrect ? 0 : 1),
          streak: isCorrect ? prev.streak + 1 : 0,
          bestStreak: isCorrect ? Math.max(prev.bestStreak, prev.streak + 1) : prev.bestStreak,
          totalTime: prev.totalTime + (isCorrect ? responseTime : 0),
          averageTime: 0,
          level: prev.level,
          levelProgress: 0,
        }

        if (newStats.correct > 0) {
          newStats.averageTime = newStats.totalTime / newStats.correct
        }

        return newStats
      })

      // Check for level progression after a delay
      setTimeout(() => {
        if (isCorrect && gameStats.level < 8) {
          const levelComplete = checkLevelCompletion(gameStats.level)
          if (levelComplete) {
            const nextLevel = gameStats.level + 1
            if (nextLevel > 8) {
              triggerConfetti("large")
              setGameComplete(true)
              setLevelFeedback("Game complete! You've mastered all levels!") // <-- MERGE START
              setIsPlaying(false)
            } else {
              triggerConfetti("medium")
              setResponseTimes({})
              setAchievements(new Set()) // Reset achievements for new level
              const nextLevelInfo = LEARNING_LEVELS[(gameStats.level + 1) as keyof typeof LEARNING_LEVELS]

              setLevelFeedback(`Welcome to ${nextLevelInfo.name}`) // <-- MERGE END
            }
          }
        }
      }, 100)

      // Start next round after brief delay
      setTimeout(() => {
        if (isPlaying && !gameComplete) {
          startNewRound()
        }
      }, 1000)
    },
    [
      currentNote,
      isPlaying,
      startTime,
      startNewRound,
      currentPosition,
      gameStats.level,
      checkLevelCompletion,
      gameComplete,
      checkAchievements,
      triggerConfetti,
      toast,
      gameStats.correct,
      gameStartTime,
    ],
  )

  const getAttemptsProgress = useCallback((): { completed: number; total: number } => {
    const currentLevel = LEARNING_LEVELS[gameStats.level as keyof typeof LEARNING_LEVELS]

    const allPositions: string[] = []
    for (let string = 0; string < 5; string++) {
      for (const fret of currentLevel.frets) {
        const note = getNoteAtPosition(string, fret)
        if (currentLevel.notes.includes(note)) {
          allPositions.push(`${note}-${string}-${fret}`)
        }
      }
    }

    const completed = allPositions.filter((key) => {
      const data = responseTimes[key]
      return data && data.count >= 3
    }).length

    return { completed, total: allPositions.length }
  }, [responseTimes, gameStats.level])

  const updateDebugPosition = (key: string, axis: "x" | "y", value: string) => {
    const numValue = Number.parseFloat(value) || 0
    // setDebugPositions((prev) => ({
    //   ...prev,
    //   [key]: {
    //     ...prev[key],
    //     [axis]: numValue,
    //   },
    // }))
  }

  const handleMouseDown = (key: string) => {
    // setDraggingPoint(key)
  }

  const handleMouseMove = (e: React.MouseEvent<HTMLDivElement>) => {
    // if (!draggingPoint || !fretboardRef.current) return
    // const rect = fretboardRef.current.getBoundingClientRect()
    // const x = e.clientX - rect.left
    // const y = e.clientY - rect.top
    // setDebugPositions((prev) => ({
    //   ...prev,
    //   [draggingPoint]: {
    //     x: Math.round(x),
    //     y: Math.round(y),
    //   },
    // }))
  }

  const handleMouseUp = () => {
    // setDraggingPoint(null)
  }

  const extrapolatePositions = (stage: number) => {
    // setDebugPositions((prev) => {
    //   const newPositions = JSON.parse(JSON.stringify(prev))
    //   if (stage === 2) {
    //     for (let stringIndex = 0; stringIndex < 5; stringIndex++) {
    //       const pos0 = prev[`${stringIndex}-0`]
    //       const pos12 = prev[`${stringIndex}-12`]
    //       if (pos0 && pos12) {
    //         // Fret 7 is 7/12 of the way from 0 to 12
    //         const ratio7 = 7 / 12
    //         newPositions[`${stringIndex}-7`] = {
    //           x: pos0.x + (pos12.x - pos0.x) * ratio7,
    //           y: pos0.y + (pos12.y - pos0.y) * ratio7,
    //         }
    //         // Fret 19 is extrapolated: 12 + (19-12)/12 * (12-0)
    //         const ratio19 = (19 - 12) / 12
    //         newPositions[`${stringIndex}-19`] = {
    //           x: pos12.x + (pos12.x - pos0.x) * ratio19,
    //           y: pos12.y + (pos12.y - pos0.y) * ratio19,
    //         }
    //       }
    //     }
    //   } else if (stage === 3) {
    //     for (let stringIndex = 0; stringIndex < 5; stringIndex++) {
    //       const pos0 = prev[`${stringIndex}-0`]
    //       const pos7 = prev[`${stringIndex}-7`]
    //       const pos12 = prev[`${stringIndex}-12`]
    //       const pos19 = prev[`${stringIndex}-19`]
    //       if (pos0 && pos7 && pos12 && pos19) {
    //         // Fret 3: between 0 and 7
    //         newPositions[`${stringIndex}-3`] = {
    //           x: pos0.x + (pos7.x - pos0.x) * (3 / 7),
    //           y: pos0.y + (pos7.y - pos0.y) * (3 / 7),
    //         }
    //         // Fret 5: between 0 and 7
    //         newPositions[`${stringIndex}-5`] = {
    //           x: pos0.x + (pos7.x - pos0.x) * (5 / 7),
    //           y: pos0.y + (pos7.y - pos0.y) * (5 / 7),
    //         }
    //         // Fret 9: between 7 and 12
    //         newPositions[`${stringIndex}-9`] = {
    //           x: pos7.x + (pos12.x - pos7.x) * ((9 - 7) / (12 - 7)),
    //           y: pos7.y + (pos12.y - pos7.y) * ((9 - 7) / (12 - 7)),
    //         }
    //         // Fret 15: between 12 and 19
    //         newPositions[`${stringIndex}-15`] = {
    //           x: pos12.x + (pos19.x - pos12.x) * ((15 - 12) / (19 - 12)),
    //           y: pos12.y + (pos19.y - pos12.y) * ((15 - 12) / (19 - 12)),
    //         }
    //         // Fret 17: between 12 and 19
    //         newPositions[`${stringIndex}-17`] = {
    //           x: pos12.x + (pos19.x - pos12.x) * ((17 - 12) / (19 - 12)),
    //           y: pos12.y + (pos19.y - pos12.y) * ((17 - 12) / (19 - 12)),
    //         }
    //         // Fret 21: extrapolate beyond 19
    //         newPositions[`${stringIndex}-21`] = {
    //           x: pos19.x + (pos19.x - pos12.x) * ((21 - 19) / (19 - 12)),
    //           y: pos19.y + (pos19.y - pos12.y) * ((21 - 19) / (19 - 12)),
    //         }
    //       }
    //     }
    //   }
    //   return newPositions
    // })
  }

  const advanceCalibrationStage = () => {
    // if (calibrationStage < 3) {
    //   const nextStage = calibrationStage + 1
    //   extrapolatePositions(nextStage)
    //   setCalibrationStage(nextStage)
    // }
  }

  const exportPositions = () => {
    // const positionsCode = `const CALIBRATED_POSITIONS = ${JSON.stringify(debugPositions, null, 2)}`
    // console.log("[v0] Corrected positions:")
    // console.log(positionsCode)
    // alert("Corrected positions have been logged to console. Copy them to replace CALIBRATED_POSITIONS in the code.")
  }

  const getNotePosition = (stringIndex: number, fret: number): { x: number; y: number } | null => {
    // Check if we have exact position
    const exactKey = `${stringIndex}-${fret}`
    if (CALIBRATED_POSITIONS[exactKey as keyof typeof CALIBRATED_POSITIONS]) {
      const pos = CALIBRATED_POSITIONS[exactKey as keyof typeof CALIBRATED_POSITIONS]
      return {
        x: pos.x * imageScale,
        y: pos.y * imageScale,
      }
    }

    // Interpolation between nearest calibration points
    const calibrationFrets = [0, 3, 5, 7, 9, 12, 15, 17, 19, 21, 24]

    // Find the two nearest calibration points that bracket the target fret
    let lowerFret = 0
    let upperFret = 24

    for (let i = 0; i < calibrationFrets.length - 1; i++) {
      if (fret >= calibrationFrets[i] && fret <= calibrationFrets[i + 1]) {
        lowerFret = calibrationFrets[i]
        upperFret = calibrationFrets[i + 1]
        break
      }
    }

    const lowerKey = `${stringIndex}-${lowerFret}`
    const upperKey = `${stringIndex}-${upperFret}`

    const lowerPos = CALIBRATED_POSITIONS[lowerKey as keyof typeof CALIBRATED_POSITIONS]
    const upperPos = CALIBRATED_POSITIONS[upperKey as keyof typeof CALIBRATED_POSITIONS]

    if (!lowerPos || !upperPos) return null

    // Calculate interpolation ratio
    const ratio = (fret - lowerFret) / (upperFret - lowerFret)

    return {
      x: (lowerPos.x + (upperPos.x - lowerPos.x) * ratio) * imageScale,
      y: (lowerPos.y + (upperPos.y - lowerPos.y) * ratio) * imageScale,
    }
  }

  // Start new round // Renamed from playNextNote to startNewRound
  const playNextNote = useCallback(() => {
    const position = generateAdaptivePosition()
    setCurrentPosition({ string: position.string, fret: position.fret })
    setCurrentNote(position.note)
    setUserInput("")
    setFeedback(null)
    setTimeLeft(8000) // 8 second time limit
    setStartTime(Date.now())
  }, [generateAdaptivePosition])

  // Start/stop game
  const toggleGame = () => {
    if (isPlaying) {
      setIsPlaying(false)
      stopGroove() // Stop groove when pausing
      setCurrentPosition(null) // Added to reset position on pause
      setTimeLeft(0) // Added to reset timer on pause
    } else {
      if (audioEngineRef.current && !audioEngineRef.current.isUnlocked) {
        audioEngineRef.current.unlockAudioContext()
      }

      if (gameComplete) {
        // Reset everything for new game
        setGameComplete(false)
        setGameStats({
          correct: 0,
          incorrect: 0,
          streak: 0,
          bestStreak: 0,
          totalTime: 0,
          averageTime: 0,
          level: 1,
          levelProgress: 0,
        })
        setResponseTimes({})
        setAchievements(new Set()) // Reset achievements for new game
        setRecentNotes([]) // Reset recent notes
        setGameStartTime(0) // Reset game start time
      }

      setIsPlaying(true)
      setGameStartTime(Date.now()) // Track game start time
      playNextNote()
    }
  }

  // Reset stats
  const resetGame = () => {
    // Renamed from resetStats to resetGame
    setIsPlaying(false)
    stopGroove() // Stop groove on reset
    setGameStats({
      correct: 0,
      incorrect: 0,
      streak: 0,
      bestStreak: 0,
      totalTime: 0,
      averageTime: 0,
      level: 1,
      levelProgress: 0,
    })
    setResponseTimes({})
    setAchievements(new Set())
    setRecentNotes([]) // Reset recent notes
    setCurrentNote("") // Reset current note
    setCurrentPosition(null) // Reset current position
    setFeedback(null) // Reset feedback
    setGameComplete(false) // Reset game complete state
    setLevelFeedback(null) // Reset to null
    setGameStartTime(0) // Reset game start time
  }

  const startGroove = useCallback(() => {
    if (metronomeInterval) return // Already running

    const bpm = 80
    const interval = ((60 / bpm) * 1000) / 2 // 8th notes

    let beatCounter = 0
    playGrooveCallback(beatCounter)
    beatCounter++

    const intervalId = setInterval(() => {
      playGrooveCallback(beatCounter)
      beatCounter++
    }, interval)
    setMetronomeInterval(intervalId)
  }, [metronomeInterval, playGrooveCallback])

  // Stop metronome is now stopGroove
  const stopGroove = useCallback(() => {
    if (metronomeInterval) {
      clearInterval(metronomeInterval)
      setMetronomeInterval(null)
    }
  }, [metronomeInterval])

  // </CHANGE> Start groove after 200 attempts instead of 200 seconds
  useEffect(() => {
    if (isPlaying) {
      const totalAttempts = gameStats.correct + gameStats.incorrect
      if (totalAttempts >= 200 && !metronomeInterval) {
        startGroove()
      }
    } else if (!isPlaying && metronomeInterval) {
      stopGroove()
    }
  }, [isPlaying, gameStats.correct, gameStats.incorrect, metronomeInterval, startGroove, stopGroove])

  // Handle keyboard input
  useEffect(() => {
    const handleKeyPress = (e: KeyboardEvent) => {
      if (!isPlaying) return

      const key = e.key.toLowerCase()
      if (key === "enter" && userInput) {
        submitAnswer(userInput)
        return
      }

      // Direct note input
      const noteMap: { [key: string]: string } = {
        c: "C",
        d: "D",
        e: "E",
        f: "F",
        g: "G",
        a: "A",
        b: "B",
      }

      if (noteMap[key]) {
        submitAnswer(noteMap[key])
      }
    }

    window.addEventListener("keydown", handleKeyPress)
    return () => window.removeEventListener("keydown", handleKeyPress)
  }, [isPlaying, userInput, submitAnswer])

  useEffect(() => {
    audioEngineRef.current = new RealBassAudioEngine() // Instantiate the new engine
    audioEngineRef.current.preloadAudio() // Preload audio on component mount
  }, [])

  useEffect(() => {
    const updateImageScale = () => {
      if (imageRef.current) {
        const renderedWidth = imageRef.current.width
        const scale = renderedWidth / CALIBRATION_REFERENCE_WIDTH
        setImageScale(scale)
        console.log("[v0] Calibration reference width:", CALIBRATION_REFERENCE_WIDTH, "px")
        console.log("[v0] Image rendered width:", renderedWidth, "px")
        console.log("[v0] Scale factor:", scale)
      }
    }

    updateImageScale()
    window.addEventListener("resize", updateImageScale)

    return () => window.removeEventListener("resize", updateImageScale)
  }, [])

  const currentLevel = LEARNING_LEVELS[gameStats.level as keyof typeof LEARNING_LEVELS]
  const balanceScore = calculateBalanceScore(gameStats.level)

  const getNoteAverages = useCallback(() => {
    const noteAverages: { [note: string]: { average: number; count: number } } = {}

    currentLevel.notes.forEach((note) => {
      let totalTime = 0
      let totalCount = 0

      Object.keys(responseTimes).forEach((key) => {
        const [keyNote, , fret] = key.split("-")
        const fretNum = Number.parseInt(fret)

        if (keyNote === note && currentLevel.frets.includes(fretNum)) {
          totalTime += responseTimes[key].average * responseTimes[key].times.length
          totalCount += responseTimes[key].times.length
        }
      })

      if (totalCount > 0) {
        noteAverages[note] = {
          average: totalTime / totalCount,
          count: totalCount,
        }
      }
    })

    return noteAverages
  }, [currentLevel, responseTimes])

  const noteAverages = getNoteAverages()

  const getLevelProgress = useCallback((): { progress: number; balanceReady: boolean } => {
    const currentLevel = LEARNING_LEVELS[gameStats.level as keyof typeof LEARNING_LEVELS]

    const allPositions: string[] = []
    for (let string = 0; string < 5; string++) {
      for (const fret of currentLevel.frets) {
        const note = getNoteAtPosition(string, fret)
        if (currentLevel.notes.includes(note)) {
          allPositions.push(`${note}-${string}-${fret}`)
        }
      }
    }

    const balanceReady = allPositions.every((key) => {
      const data = responseTimes[key]
      return data && data.count >= 3
    })

    if (!balanceReady) {
      return { progress: 0, balanceReady: false }
    }

    // Calculate progress only if balance is ready
    const progress = Math.min(100, (balanceScore / currentLevel.targetBalance) * 100)
    return { progress, balanceReady: true }
  }, [balanceScore, currentLevel, responseTimes, gameStats.level])

  const getColorForTime = (timeInSeconds: number): string => {
    if (timeInSeconds >= 10) {
      // Red: >10s
      return "oklch(0.55 0.22 25)" // Red
    } else if (timeInSeconds >= 5) {
      // Orange-Red: 5-10s
      return "oklch(0.60 0.20 45)" // Orange-Red
    } else if (timeInSeconds >= 2) {
      // Yellow-Orange: 2-5s
      return "oklch(0.70 0.18 70)" // Yellow-Orange
    } else if (timeInSeconds >= 1) {
      // Yellow-Green: 1-2s
      return "oklch(0.75 0.15 110)" // Yellow-Green
    } else {
      // Green: <1s
      return "oklch(0.70 0.18 145)" // Green
    }
  }

  const levelProgress = getLevelProgress()
  const notePositionData = getNotePositionData(gameStats.level)

  return (
    <div className="min-h-screen bg-background p-2">
      <div className="w-full space-y-2">
        {/* Compact Header with Level Progression and Stats */}
        <Card>
          <CardContent className="p-3">
            <div className="flex flex-wrap items-center justify-between gap-4">
              {/* Level Progression */}
              <div className="flex items-center gap-2">
                <span className="text-xs font-medium">Level:</span>
                {[1, 2, 3, 4, 5, 6, 7, 8].map((level) => (
                  <div
                    key={level}
                    className={`w-7 h-7 rounded-full flex items-center justify-center text-xs font-bold transition-all ${
                      level === gameStats.level
                        ? "bg-primary text-primary-foreground scale-110 ring-2 ring-primary"
                        : level < gameStats.level
                          ? "bg-accent text-accent-foreground"
                          : "bg-muted text-muted-foreground"
                    }`}
                  >
                    {level}
                  </div>
                ))}
              </div>

              {/* Compact Stats */}
              <div className="flex items-center gap-4 text-sm">
                <div className="flex items-center gap-1">
                  <span className="text-muted-foreground">Correct:</span>
                  <span className="font-bold text-accent">{gameStats.correct}</span>
                </div>
                <div className="flex items-center gap-1">
                  <span className="text-muted-foreground">Wrong:</span>
                  <span className="font-bold text-destructive">{gameStats.incorrect}</span>
                </div>
                <div className="flex items-center gap-1">
                  <span className="text-muted-foreground">Streak:</span>
                  <span className="font-bold text-primary">{gameStats.streak}</span>
                </div>
                <div className="flex items-center gap-1">
                  <Trophy className="w-4 h-4 text-chart-3" />
                  <span className="font-bold text-chart-3">{gameStats.bestStreak}</span>
                </div>
              </div>

              {/* Control Buttons */}
              <div className="flex items-center gap-2">
                <Button onClick={toggleGame} size="sm" variant={isPlaying ? "outline" : "default"} className="gap-2">
                  {isPlaying ? (
                    <>
                      <Pause className="h-4 w-4" />
                      Pause
                    </>
                  ) : (
                    <>
                      <Play className="h-4 w-4" />
                      Start
                    </>
                  )}
                </Button>
                <Button onClick={resetGame} size="sm" variant="outline" className="gap-2 bg-transparent">
                  {" "}
                  {/* Changed to resetGame */}
                  <RotateCcw className="h-4 w-4" />
                  Reset
                </Button>
              </div>
            </div>

            {/* Level Description */}
            <div className="text-center mt-2 pt-2 border-t">
              <p className="text-xs font-medium">{currentLevel.name}</p>
              <p className="text-xs text-muted-foreground">{currentLevel.description}</p>
            </div>
          </CardContent>
        </Card>

        {/* Compact Progress Section - Speedometer and Response Times Side by Side */}
        <Card>
          <CardContent className="p-3">
            <div className="grid grid-cols-1 md:grid-cols-[300px_1fr] gap-4">
              {/* Compact Speedometer - Now only shows balance progress */}
              <div className="flex flex-col items-center">
                {!levelProgress.balanceReady ? (
                  <div className="flex items-center gap-4">
                    <div className="flex-1 space-y-2">
                      <div className="flex items-center justify-between text-xs">
                        <span className="text-muted-foreground">Progress to Balance Tracking</span>
                        <span className="font-medium">
                          {getAttemptsProgress().completed} / {getAttemptsProgress().total} positions (3+ attempts)
                        </span>
                      </div>
                      <Progress
                        value={(getAttemptsProgress().completed / getAttemptsProgress().total) * 100}
                        className="h-2"
                      />
                      <p className="text-xs text-muted-foreground">
                        Each string/fret combination needs 3+ correct answers before balance is calculated
                      </p>
                    </div>
                  </div>
                ) : (
                  <div className="flex items-center gap-4">
                    <div className="flex-shrink-0 w-32">
                      <svg viewBox="0 0 120 120" className="w-full h-auto">
                        {/* speedometer SVG */}
                        <circle
                          cx="60"
                          cy="60"
                          r="50"
                          fill="none"
                          stroke="oklch(0.3 0 0)"
                          strokeWidth="10"
                          strokeLinecap="round"
                          strokeDasharray="157 314"
                          strokeDashoffset="78.5"
                        />
                        <circle
                          cx="60"
                          cy="60"
                          r="50"
                          fill="none"
                          stroke={
                            balanceScore >= currentLevel.targetBalance
                              ? "oklch(0.7 0.2 142)"
                              : balanceScore >= 50
                                ? "oklch(0.8 0.2 85)"
                                : balanceScore >= 30
                                  ? "oklch(0.8 0.2 60)"
                                  : "oklch(0.7 0.2 27)"
                          }
                          strokeWidth="10"
                          strokeLinecap="round"
                          strokeDasharray={`${(balanceScore / 100) * 157} 314`}
                          strokeDashoffset="78.5"
                          transform="rotate(-90 60 60)"
                        />
                        <text x="60" y="55" textAnchor="middle" className="text-2xl font-bold fill-foreground">
                          {balanceScore.toFixed(0)}%
                        </text>
                        <text x="60" y="75" textAnchor="middle" className="text-xs fill-muted-foreground">
                          Balance
                        </text>
                      </svg>

                      <div className="w-full space-y-2 mt-2">
                        <div className="space-y-1">
                          <div className="flex items-center justify-between text-xs">
                            <span className="text-muted-foreground">Balance</span>
                            <span
                              className={balanceScore >= currentLevel.targetBalance ? "text-accent font-medium" : ""}
                            >
                              {balanceScore.toFixed(0)}% / {currentLevel.targetBalance}%
                            </span>
                          </div>
                          <Progress value={balanceScore} className="h-1.5" />
                        </div>
                      </div>
                    </div>
                  </div>
                )}
              </div>

              {/* Response Times Bar Chart */}
              <div className="space-y-2">
                <h3 className="text-xs font-semibold">Response Times by Position (String & Fret)</h3>
                <div className="flex items-end justify-between gap-0.5 h-32 overflow-x-auto">
                  {notePositionData.map((position, idx) => {
                    const avgTime = position.average / 1000
                    const maxTime = 10
                    const barHeight = Math.min(100, (avgTime / maxTime) * 100)
                    const barColor = getColorForTime(avgTime)

                    return (
                      <div
                        key={`${position.string}-${position.fret}-${idx}`}
                        className="flex-1 min-w-[20px] flex flex-col items-center gap-1"
                      >
                        <div className="text-[9px] font-bold text-foreground/60">{position.count}x</div>
                        <div className="w-full flex flex-col justify-end items-center" style={{ height: "100px" }}>
                          <div
                            className="w-full transition-all duration-300 rounded-t"
                            style={{
                              height: `${barHeight}%`,
                              backgroundColor: barColor,
                            }}
                            title={`${position.note} - ${STRINGS[position.string]} string, Fret ${position.fret}: ${avgTime.toFixed(1)}s (${position.count} attempts)`}
                          />
                        </div>
                        <div className="text-[10px] font-mono font-bold leading-tight text-center">{position.note}</div>
                        <div className="text-[8px] text-muted-foreground leading-tight text-center">
                          {STRINGS[position.string]}
                          {position.fret}
                        </div>
                      </div>
                    )
                  })}
                </div>
                <div className="flex items-center justify-between text-xs text-muted-foreground pt-2 border-t">
                  <div className="flex items-center gap-1">
                    <span className="text-[10px]">Grouped by fret, then by string (B→E→A→D→G)</span>
                  </div>
                  <div className="flex items-center gap-2">
                    <div className="flex items-center gap-1">
                      <div className="w-2 h-2 rounded" style={{ backgroundColor: "oklch(0.70 0.18 145)" }}></div>
                      <span>&lt;1s</span>
                    </div>
                    <div className="flex items-center gap-1">
                      <div className="w-2 h-2 rounded" style={{ backgroundColor: "oklch(0.75 0.15 110)" }}></div>
                      <span>1-2s</span>
                    </div>
                    <div className="flex items-center gap-1">
                      <div className="w-2 h-2 rounded" style={{ backgroundColor: "oklch(0.70 0.18 70)" }}></div>
                      <span>2-5s</span>
                    </div>
                    <div className="flex items-center gap-1">
                      <div className="w-2 h-2 rounded" style={{ backgroundColor: "oklch(0.60 0.20 45)" }}></div>
                      <span>5-10s</span>
                    </div>
                    <div className="flex items-center gap-1">
                      <div className="w-2 h-2 rounded" style={{ backgroundColor: "oklch(0.55 0.22 25)" }}></div>
                      <span>&gt;10s</span>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            {levelFeedback && (
              <div className="text-center p-2 bg-accent/20 rounded-lg mt-3">
                <p className="text-xs font-medium text-accent-foreground">{levelFeedback}</p>
              </div>
            )}
          </CardContent>
        </Card>

        {/* Bass Neck - Full Width */}
        <Card className="w-full">
          <CardContent className="p-0">
            <div className="relative w-full">
              <div className="relative w-full">
                <div ref={fretboardRef} className="relative w-full">
                  <img
                    ref={imageRef}
                    src="/images/bass-fretboard.png"
                    alt="Bass guitar fretboard"
                    className="w-full h-auto block"
                  />

                  {STRINGS.map((string, stringIndex) => (
                    <div
                      key={`string-label-${stringIndex}`}
                      className="absolute text-sm font-mono font-bold text-white bg-black/70 px-2 py-1 rounded shadow-lg"
                      style={{
                        left: "-60px",
                        top: `${15 + stringIndex * 16}%`,
                        transform: "translateY(-50%)",
                      }}
                    >
                      {string}
                    </div>
                  ))}

                  {currentPosition &&
                    isPlaying &&
                    (() => {
                      const position = getNotePosition(currentPosition.string, currentPosition.fret)
                      if (!position) return null

                      return (
                        <div
                          className="absolute z-10 rounded-full animate-pulse"
                          style={{
                            left: `${position.x}px`,
                            top: `${position.y}px`,
                            width: "10px",
                            height: "10px",
                            background: `radial-gradient(circle, ${currentLevel.color}, ${currentLevel.color}80)`,
                            boxShadow: `0 0 10px ${currentLevel.color}, 0 0 20px ${currentLevel.color}40`,
                            transform: "translate(-50%, -50%)",
                            border: "2px solid white",
                          }}
                        />
                      )
                    })()}
                </div>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Note Input Buttons - Compact */}
        {isPlaying && !gameComplete && (
          <Card>
            <CardContent className="p-3">
              <div className="text-center space-y-2">
                <h3 className="text-sm font-semibold">What note is highlighted?</h3>
                <div className="flex flex-wrap justify-center gap-3">
                  {currentLevel.notes.map((note) => (
                    <Button
                      key={note}
                      onClick={() => submitAnswer(note)}
                      variant="outline"
                      size="lg"
                      className="w-16 h-16 text-xl font-mono font-bold"
                      disabled={feedback !== null}
                    >
                      {note}
                    </Button>
                  ))}
                </div>
                <p className="text-xs text-muted-foreground">
                  <Clock className="w-3 h-3 inline mr-1" />
                  Keyboard: C, D, E, F, G, A, B | Real bass tones play on correct answers
                </p>
              </div>
            </CardContent>
          </Card>
        )}
      </div>
      <Toaster />
    </div>
  )
}
