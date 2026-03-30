import React, { useState, useRef, useCallback, useEffect } from 'react'
import ForgeCanvas from './components/ForgeCanvas'
import GaugeBar from './components/GaugeBar'
import StrikeZones from './components/StrikeZones'
import ResultOverlay from './components/ResultOverlay'
import { initialState, GameState, STAGE_LABELS, ZoneResult } from './game/gameState'
import styles from './App.module.css'

export default function App() {
  const [gs, setGs] = useState<GameState>(initialState())
  const holdRAF   = useRef<number>(0)
  const holdStart = useRef<number>(0)
  const shakeRef  = useRef<((p: number) => void) | null>(null)

  // Animate gauge while holding
  const loopHold = useCallback(() => {
    const p = Math.min((performance.now() - holdStart.current) / 1300, 1)
    setGs(prev => ({ ...prev, holdDuration: p }))
    holdRAF.current = requestAnimationFrame(loopHold)
  }, [])

  const handleHoldStart = useCallback(() => {
    setGs(prev => {
      if (prev.over || prev.holding) return prev
      holdStart.current = performance.now()
      holdRAF.current = requestAnimationFrame(loopHold)
      return { ...prev, holding: true, holdDuration: 0 }
    })
  }, [loopHold])

  const handleHoldEnd = useCallback(() => {
    setGs(prev => {
      if (!prev.holding) return prev
      cancelAnimationFrame(holdRAF.current)
      const power = prev.holdDuration
      return strike(prev, power)
    })
  }, [])

  function strike(prev: GameState, power: number): GameState {
    if (prev.over || prev.hits >= prev.total) return prev

    const zones = [...prev.zones] as ZoneResult[]
    let quality = prev.quality

    if (power >= 0.28 && power <= 0.70) {
      zones[prev.hits] = 'hit'
      shakeRef.current?.(power)
    } else if (power < 0.28) {
      zones[prev.hits] = 'miss'
      quality = Math.max(0, quality - 13)
    } else {
      zones[prev.hits] = 'miss'
      quality = Math.max(0, quality - 24)
      shakeRef.current?.(power * 1.6)
    }

    const hits  = prev.hits + 1
    const stage = Math.min(hits, 4)
    const over  = hits >= prev.total

    return { ...prev, holding: false, holdDuration: 0, hits, stage, quality, zones, over }
  }

  const restart = useCallback(() => {
    setGs(initialState())
  }, [])

  const qualityPct = gs.quality / 100

  return (
    <div className={styles.root}>
      {/* Header */}
      <header className={styles.header}>
        <h1 className={styles.title}>Stone Forge</h1>
        <span className={styles.stageLbl}>Knapping · {STAGE_LABELS[gs.stage]}</span>
      </header>

      {/* Quality bar */}
      <div className={styles.qualBar}>
        <span className={styles.qualLbl}>Quality</span>
        <div className={styles.qualTrack}>
          <div className={styles.qualFill} style={{ width: `${gs.quality}%` }} />
        </div>
      </div>

      {/* Three.js canvas */}
      <div className={styles.canvasWrap}>
        <ForgeCanvas
          stage={gs.stage}
          onHoldStart={handleHoldStart}
          onHoldEnd={handleHoldEnd}
          gameOver={gs.over}
          shakeRef={shakeRef}
        />
        {gs.over && <ResultOverlay quality={gs.quality} onRestart={restart} />}
      </div>

      {/* HUD */}
      <div className={styles.hud}>
        <GaugeBar value={gs.holding ? gs.holdDuration : 0} />
        <StrikeZones zones={gs.zones} />
        <p className={styles.hint}>
          {gs.over ? '' : 'Hold & release to strike · Green zone = perfect blow'}
        </p>
      </div>
    </div>
  )
}
