import React from 'react'
import styles from './GaugeBar.module.css'

interface Props {
  value: number  // 0~1
}

export default function GaugeBar({ value }: Props) {
  const pct = Math.round(value * 100)

  let barColor = '#4caf50'
  if (value >= 0.72) barColor = '#e03020'
  else if (value >= 0.30) barColor = '#e8732a'

  return (
    <div className={styles.wrap}>
      <span className={styles.label}>Strike Force</span>
      <div className={styles.track}>
        <div className={styles.sweetZone} />
        <div className={styles.fill} style={{ width: `${pct}%`, background: barColor }} />
      </div>
      <span className={styles.pct}>{pct}%</span>
    </div>
  )
}
