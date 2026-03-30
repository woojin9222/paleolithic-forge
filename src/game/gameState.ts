export type ZoneResult = 'pending' | 'hit' | 'miss'

export interface GameState {
  stage: number       // 0~4
  hits: number        // 0~5
  total: number       // 5
  quality: number     // 0~100
  holding: boolean
  holdStart: number
  holdDuration: number
  over: boolean
  zones: ZoneResult[]
}

export const initialState = (): GameState => ({
  stage: 0,
  hits: 0,
  total: 5,
  quality: 100,
  holding: false,
  holdStart: 0,
  holdDuration: 0,
  over: false,
  zones: Array(5).fill('pending'),
})

export const STAGE_LABELS = [
  'Raw Stone',
  'First Strike',
  'Shaping',
  'Refining',
  'Finished Axe',
]

export function getGrade(quality: number): { grade: string; desc: string } {
  if (quality >= 90) return { grade: 'Masterwork Handaxe', desc: "A near-perfect symmetry — a flintknapper's finest hour." }
  if (quality >= 70) return { grade: 'Superior Handaxe',  desc: 'A keen, well-formed edge has emerged from the stone.' }
  if (quality >= 50) return { grade: 'Serviceable Tool',  desc: 'Rough at the edges, but it will serve its purpose.' }
  if (quality >= 30) return { grade: 'Crude Chopper',     desc: 'Barely functional. The ancestors would not be impressed.' }
  return               { grade: 'Shattered Flint',        desc: 'The stone fractured. Nothing salvageable remains.' }
}
