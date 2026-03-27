import React from 'react'
import { getGrade } from '../game/gameState'
import styles from './ResultOverlay.module.css'

interface Props {
  quality: number
  onRestart: () => void
}

export default function ResultOverlay({ quality, onRestart }: Props) {
  const success = quality >= 30
  const { grade, desc } = getGrade(quality)

  return (
    <div className={styles.overlay}>
      <h2 className={`${styles.title} ${success ? styles.success : styles.fail}`}>
        {success ? 'Forged' : 'Shattered'}
      </h2>
      <div className={styles.grade}>{grade}</div>
      <div className={styles.desc}>{desc}</div>
      <button onClick={onRestart}>Knap Again</button>
    </div>
  )
}
