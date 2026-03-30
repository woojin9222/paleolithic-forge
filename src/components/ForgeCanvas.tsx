import React, { useEffect, useRef, useCallback } from 'react'
import * as THREE from 'three'
import { buildStoneMesh, buildCracks, spawnChips } from '../game/StoneBuilder'
import { GameState, STAGE_LABELS } from '../game/gameState'

interface Props {
  stage: number
  onHoldStart: () => void
  onHoldEnd: () => void
  gameOver: boolean
  // expose scene shake to parent via ref
  shakeRef: React.MutableRefObject<((power: number) => void) | null>
}

export default function ForgeCanvas({ stage, onHoldStart, onHoldEnd, gameOver, shakeRef }: Props) {
  const mountRef   = useRef<HTMLDivElement>(null)
  const sceneRef   = useRef<THREE.Scene | null>(null)
  const groupRef   = useRef<THREE.Group | null>(null)
  const rotYRef    = useRef(0)
  const camShRef   = useRef({ on: false, i: 0, f: 0 })
  const cameraRef  = useRef<THREE.PerspectiveCamera | null>(null)
  const rafRef     = useRef<number>(0)

  // Expose shake to parent
  shakeRef.current = (power: number) => {
    camShRef.current = { on: true, i: power * 0.09, f: 10 }
    if (groupRef.current) {
      const ii = power * 0.2
      groupRef.current.position.set((Math.random() - 0.5) * ii, (Math.random() - 0.5) * ii * 0.5, 0)
      setTimeout(() => groupRef.current?.position.set(0, 0, 0), 85)
    }
    if (sceneRef.current) spawnChips(stage, sceneRef.current)
  }

  // Build / rebuild stone when stage changes
  useEffect(() => {
    const group = groupRef.current
    const scene = sceneRef.current
    if (!group || !scene) return

    while (group.children.length) group.remove(group.children[0])
    group.add(buildStoneMesh(stage))
    buildCracks(stage, group)
  }, [stage])

  // Init Three.js once
  useEffect(() => {
    const mount = mountRef.current!
    const W = mount.clientWidth
    const H = mount.clientHeight

    const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false })
    renderer.setPixelRatio(Math.min(devicePixelRatio, 2))
    renderer.setSize(W, H)
    renderer.setClearColor(0x1a1208, 1)
    renderer.shadowMap.enabled = true
    renderer.toneMapping = THREE.ACESFilmicToneMapping
    renderer.toneMappingExposure = 1.2
    mount.appendChild(renderer.domElement)

    const scene = new THREE.Scene()
    scene.fog = new THREE.FogExp2(0x1a1208, 0.065)
    sceneRef.current = scene

    const camera = new THREE.PerspectiveCamera(50, W / H, 0.1, 100)
    camera.position.set(0, 0.3, 3.8)
    camera.lookAt(0, 0, 0)
    cameraRef.current = camera

    // Lights
    const fire1 = new THREE.PointLight(0xe87030, 5, 14)
    fire1.position.set(-2.2, 1.4, 2.5)
    fire1.castShadow = true
    scene.add(fire1)
    const fire2 = new THREE.PointLight(0xf5a820, 2.2, 8)
    fire2.position.set(1.8, 0.5, 1.8)
    scene.add(fire2)
    scene.add(new THREE.AmbientLight(0x201408, 4))
    const back = new THREE.DirectionalLight(0x334466, 0.3)
    back.position.set(0.5, 2, -3)
    scene.add(back)

    // Floor
    const fl = new THREE.Mesh(
      new THREE.PlaneGeometry(20, 20),
      new THREE.MeshStandardMaterial({ color: 0x100c04, roughness: 1 })
    )
    fl.rotation.x = -Math.PI / 2
    fl.position.y = -1.4
    fl.receiveShadow = true
    scene.add(fl)

    // Background pebbles
    for (let i = 0; i < 7; i++) {
      const g = new THREE.IcosahedronGeometry(0.06 + Math.random() * 0.1, 1)
      const p = g.attributes.position as THREE.BufferAttribute
      for (let j = 0; j < p.count; j++)
        p.setXYZ(j, p.getX(j) * (0.8 + Math.random() * 0.4), p.getY(j) * (0.55 + Math.random() * 0.4), p.getZ(j) * (0.7 + Math.random() * 0.4))
      g.computeVertexNormals()
      const m = new THREE.Mesh(g, new THREE.MeshStandardMaterial({ color: 0x1e1810, roughness: 1 }))
      m.position.set((Math.random() - 0.5) * 4.5, -1.38, (Math.random() - 0.5) * 3 - 0.5)
      scene.add(m)
    }

    // Stone group
    const group = new THREE.Group()
    scene.add(group)
    groupRef.current = group
    group.add(buildStoneMesh(0))

    // Animate
    const clock = new THREE.Clock()
    const animate = () => {
      rafRef.current = requestAnimationFrame(animate)
      const dt = clock.getDelta()
      const t  = clock.getElapsedTime()

      rotYRef.current += dt * (gameOver ? 1.0 : 0.32)
      group.rotation.y = rotYRef.current
      group.rotation.x = Math.sin(t * 0.22) * 0.06

      fire1.intensity = 5.0 + Math.sin(t * 7.6) * 0.9 + Math.sin(t * 15.1) * 0.35
      fire2.intensity = 2.2 + Math.sin(t * 5.4) * 0.5
      fire1.position.x = -2.2 + Math.sin(t * 3.0) * 0.13

      const cs = camShRef.current
      if (cs.on && cs.f > 0) {
        camera.position.x = (Math.random() - 0.5) * cs.i
        camera.position.y = 0.3 + (Math.random() - 0.5) * cs.i
        if (--cs.f <= 0) { camera.position.x = 0; camera.position.y = 0.3; cs.on = false }
      }

      renderer.render(scene, camera)
    }
    animate()

    // Resize
    const ro = new ResizeObserver(() => {
      const w = mount.clientWidth, h = mount.clientHeight
      renderer.setSize(w, h)
      camera.aspect = w / h
      camera.updateProjectionMatrix()
    })
    ro.observe(mount)

    return () => {
      cancelAnimationFrame(rafRef.current)
      ro.disconnect()
      renderer.dispose()
      mount.removeChild(renderer.domElement)
    }
  }, [])

  return (
    <div
      ref={mountRef}
      style={{ width: '100%', height: '100%', cursor: 'crosshair', touchAction: 'none' }}
      onMouseDown={onHoldStart}
      onMouseUp={onHoldEnd}
      onMouseLeave={onHoldEnd}
      onTouchStart={e => { e.preventDefault(); onHoldStart() }}
      onTouchEnd={e => { e.preventDefault(); onHoldEnd() }}
    />
  )
}
