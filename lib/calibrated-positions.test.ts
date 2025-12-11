// Automatic validation test for calibrated positions
// This ensures positions are never lost during code changes

import { CALIBRATED_POSITIONS } from "./calibrated-positions"

// Expected structure: 5 strings × 11 frets = 55 positions
const EXPECTED_POSITIONS = {
  strings: [0, 1, 2, 3, 4], // B, E, A, D, G
  frets: [0, 3, 5, 7, 9, 12, 15, 17, 19, 21, 24],
}

function validatePositions() {
  const errors: string[] = []
  let totalPositions = 0

  // Check each expected position exists
  for (const string of EXPECTED_POSITIONS.strings) {
    for (const fret of EXPECTED_POSITIONS.frets) {
      const key = `${string}-${fret}` as keyof typeof CALIBRATED_POSITIONS
      const position = CALIBRATED_POSITIONS[key]

      if (!position) {
        errors.push(`Missing position: ${key}`)
      } else {
        totalPositions++

        // Validate coordinate structure
        if (typeof position.x !== "number" || typeof position.y !== "number") {
          errors.push(`Invalid coordinates for ${key}: x=${position.x}, y=${position.y}`)
        }

        // Validate reasonable coordinate ranges
        if (position.x < 0 || position.x > 2000) {
          errors.push(`X coordinate out of range for ${key}: ${position.x}`)
        }
        if (position.y < -10 || position.y > 100) {
          errors.push(`Y coordinate out of range for ${key}: ${position.y}`)
        }
      }
    }
  }

  // Check for unexpected positions
  const allKeys = Object.keys(CALIBRATED_POSITIONS)
  for (const key of allKeys) {
    const [stringStr, fretStr] = key.split("-")
    const string = Number.parseInt(stringStr)
    const fret = Number.parseInt(fretStr)

    if (!EXPECTED_POSITIONS.strings.includes(string) || !EXPECTED_POSITIONS.frets.includes(fret)) {
      errors.push(`Unexpected position found: ${key}`)
    }
  }

  // Final count validation
  const expectedTotal = EXPECTED_POSITIONS.strings.length * EXPECTED_POSITIONS.frets.length
  if (totalPositions !== expectedTotal) {
    errors.push(`Position count mismatch: expected ${expectedTotal}, found ${totalPositions}`)
  }

  if (errors.length > 0) {
    console.error("❌ CALIBRATED_POSITIONS VALIDATION FAILED:")
    errors.forEach((err) => console.error(`  - ${err}`))
    throw new Error(`Calibrated positions validation failed with ${errors.length} error(s)`)
  }

  console.log(`✅ CALIBRATED_POSITIONS validated: ${totalPositions} positions OK`)
  return true
}

// Run validation immediately
validatePositions()

export { validatePositions }
