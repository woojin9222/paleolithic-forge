import * as THREE from 'three'
import { PerlinNoise } from './PerlinNoise'

const pn = new PerlinNoise(137)

const STAGE_COLORS = [
  { color: 0x7e6e52, roughness: 0.97, metalness: 0.01 },
  { color: 0x72624a, roughness: 0.93, metalness: 0.02 },
  { color: 0x625646, roughness: 0.87, metalness: 0.04 },
  { color: 0x504438, roughness: 0.80, metalness: 0.06 },
  { color: 0x3a2e22, roughness: 0.68, metalness: 0.10 },
]

export function buildStoneMesh(stage: number): THREE.Mesh {
  const geo = new THREE.IcosahedronGeometry(1, 4)
  const pos = geo.attributes.position as THREE.BufferAttribute
  const t = stage / 4

  for (let i = 0; i < pos.count; i++) {
    const ox = pos.getX(i), oy = pos.getY(i), oz = pos.getZ(i)
    const len = Math.sqrt(ox * ox + oy * oy + oz * oz)
    const nx = ox / len, ny = oy / len, nz = oz / len

    // Surface noise — smooths as stage progresses
    const nAmt = 0.085 - stage * 0.010
    const nf   = 3.5   + stage * 0.4
    const noise =
      pn.fbm(nx * nf,       ny * nf,       nz * nf,       3) * nAmt +
      pn.fbm(nx * nf * 2.2, ny * nf * 2.2, nz * nf * 2.2, 2) * nAmt * 0.35

    // Raw ellipsoid params
    const rx = 0.88, ry = 0.72, rz = 0.80

    // Handaxe teardrop shape
    const tdX  = ny < 0 ? 1 + ny * (-0.1) : 1 - Math.pow(ny, 1.25) * 0.80
    const axeX = Math.max(0.04, tdX)
    const axeY = 1.05
    const lentZ = 1 - Math.pow(Math.abs(nx), 1.4) * 0.32
    const axeZ  = 0.28 * lentZ

    // Interpolate raw → axe
    const sx = rx * (1 - t) + axeX * t
    const sy = ry * (1 - t) + axeY * t
    const sz = rz * (1 - t) + axeZ  * t

    pos.setXYZ(i,
      nx * sx + noise * sx * 0.22,
      ny * sy + noise * sy * 0.18,
      nz * sz + noise * sz * 0.28,
    )
  }
  geo.computeVertexNormals()

  const cm = STAGE_COLORS[Math.min(stage, 4)]
  const mat = new THREE.MeshStandardMaterial({
    color:     cm.color,
    roughness: cm.roughness,
    metalness: cm.metalness,
  })

  const mesh = new THREE.Mesh(geo, mat)
  mesh.castShadow    = true
  mesh.receiveShadow = true
  return mesh
}

export function buildCracks(stage: number, group: THREE.Group): void {
  if (stage === 0) return
  const seeds = [17, 31, 53, 67, 89]

  for (let c = 0; c < stage; c++) {
    let s = seeds[c % 5]
    const r = () => { s = (s * 1664525 + 1013904223) >>> 0; return (s >>> 0) / 0xffffffff }

    const pts: THREE.Vector3[] = []
    const ba = (c / 5) * Math.PI * 2 + r() * 0.45
    const by = (r() - 0.5) * 0.52

    for (let i = 0; i <= 12; i++) {
      const ti  = i / 12
      const ang = ba + (r() - 0.5) * 0.52 * ti
      const t2  = stage / 4
      const rad = 0.70 - t2 * 0.22 + pn.noise(Math.cos(ang) * 3, by * 3, c) * 0.08
      pts.push(new THREE.Vector3(
        Math.cos(ang) * rad * (1 - Math.abs(by) * 0.2),
        by + (r() - 0.5) * 0.14,
        Math.sin(ang) * rad * (0.42 - t2 * 0.18),
      ))
    }

    const lineGeo = new THREE.BufferGeometry().setFromPoints(pts)
    const lineMat = new THREE.LineBasicMaterial({ color: 0x0a0804, transparent: true, opacity: 0.72 })
    group.add(new THREE.Line(lineGeo, lineMat))
  }
}

export function spawnChips(stage: number, scene: THREE.Scene): void {
  const count = 5 + stage * 2
  for (let i = 0; i < count; i++) {
    const geo  = new THREE.TetrahedronGeometry(0.03 + Math.random() * 0.05, 0)
    const mat  = new THREE.MeshStandardMaterial({ color: 0x58482e, roughness: 0.95, transparent: true })
    const chip = new THREE.Mesh(geo, mat)
    chip.position.set((Math.random() - 0.5) * 0.7, (Math.random() - 0.5) * 0.45, (Math.random() - 0.5) * 0.3)
    chip.rotation.set(Math.random() * 6, Math.random() * 6, Math.random() * 6)
    scene.add(chip)

    const vel = new THREE.Vector3(
      (Math.random() - 0.5) * 0.09,
      0.055 + Math.random() * 0.07,
      (Math.random() - 0.5) * 0.06,
    )
    let life = 0
    const tick = () => {
      life++
      vel.y -= 0.003
      chip.position.add(vel)
      chip.rotation.x += 0.12
      chip.rotation.z += 0.09
      mat.opacity = 1 - life / 32
      if (life < 32) requestAnimationFrame(tick)
      else scene.remove(chip)
    }
    requestAnimationFrame(tick)
  }
}
