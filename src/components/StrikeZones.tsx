import React from 'react'
import { ZoneResult } from '../game/gameState'
import styles from './StrikeZones.module.css'

const LABELS = ['I', 'II', 'III', 'IV', 'V']

interface Props {
  zones: ZoneResult[]
}

export default function StrikeZones({ zones }: Props) {
  return (
    <div className={styles.wrap}>
      {zones.map((z, i) => (
        <div key={i} className={`${styles.zone} ${styles[z]}`}>
          {LABELS[i]}
        </div>
      ))}
    </div>
  )
}
