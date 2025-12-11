// Unit test to validate CALIBRATED_POSITIONS integrity
import { CALIBRATED_POSITIONS } from "../lib/calibrated-positions"

// Expected structure: 5 strings (0-4), each with specific frets
const EXPECTED_POSITIONS = {
  0: [0, 3, 5, 7, 9, 12, 15, 17, 19, 21, 24], // B string
  1: [0, 3, 5, 7, 9, 12, 15, 17, 19, 21, 24], // E string
  2: [0, 3, 5, 7, 9, 12, 15, 17, 19, 21, 24], // A string
  3: [0, 3, 5, 7, 9, 12, 15, 17, 19, 21, 24], // D string
  4: [0, 3, 5, 7, 9, 12, 15, 17, 19, 21, 24], // G string
}

console.log("[v0] Validating CALIBRATED_POSITIONS...")

let allValid = true

// Check all expected positions exist
for (const [stringNum, frets] of Object.entries(EXPECTED_POSITIONS)) {
  for (const fret of frets) {
    const key = `${stringNum}-${fret}`
    const position = CALIBRATED_POSITIONS[key as keyof typeof CALIBRATED_POSITIONS]

    if (!position) {
      console.error(`❌ Missing position: ${key}`)
      allValid = false
    } else if (typeof position.x !== "number" || typeof position.y !== "number") {
      console.error(`❌ Invalid coordinates for ${key}:`, position)
      allValid = false
    } else if (position.x < 0 || position.x > 2000 || position.y < -10 || position.y > 100) {
      console.error(`❌ Coordinates out of expected range for ${key}:`, position)
      allValid = false
    } else {
      console.log(`✅ ${key}: x=${position.x}, y=${position.y}`)
    }
  }
}

// Count total positions
const totalPositions = Object.keys(CALIBRATED_POSITIONS).length
const expectedTotal = Object.values(EXPECTED_POSITIONS).reduce((sum, frets) => sum + frets.length, 0)

console.log(`\n[v0] Total positions: ${totalPositions}`)
console.log(`[v0] Expected positions: ${expectedTotal}`)

if (totalPositions !== expectedTotal) {
  console.error(`❌ Position count mismatch!`)
  allValid = false
}

// Check for unexpected positions
const allKeys = Object.keys(CALIBRATED_POSITIONS)
for (const key of allKeys) {
  const [stringStr, fretStr] = key.split("-")
  const string = Number.parseInt(stringStr)
  const fret = Number.parseInt(fretStr)

  if (!EXPECTED_POSITIONS[string as keyof typeof EXPECTED_POSITIONS]?.includes(fret)) {
    console.error(`❌ Unexpected position found: ${key}`)
    allValid = false
  }
}

if (allValid) {
  console.log("\n✅ All CALIBRATED_POSITIONS are valid!")
} else {
  console.error("\n❌ CALIBRATED_POSITIONS validation FAILED!")
  process.exit(1)
}
