export class PerlinNoise {
  private perm: Uint8Array

  constructor(seed = 137) {
    const q = new Uint8Array(256)
    for (let i = 0; i < 256; i++) q[i] = i
    let s = seed >>> 0
    for (let i = 255; i > 0; i--) {
      s = (s * 1664525 + 1013904223) >>> 0
      const j = s % (i + 1);
      [q[i], q[j]] = [q[j], q[i]]
    }
    this.perm = new Uint8Array(512)
    for (let i = 0; i < 512; i++) this.perm[i] = q[i & 255]
  }

  private fade(t: number) { return t * t * t * (t * (t * 6 - 15) + 10) }
  private lerp(a: number, b: number, t: number) { return a + t * (b - a) }
  private grad(h: number, x: number, y: number, z: number) {
    h &= 15
    const u = h < 8 ? x : y
    const v = h < 4 ? y : (h === 12 || h === 14 ? x : z)
    return ((h & 1) ? -u : u) + ((h & 2) ? -v : v)
  }

  noise(x: number, y: number, z: number): number {
    const X = Math.floor(x) & 255
    const Y = Math.floor(y) & 255
    const Z = Math.floor(z) & 255
    x -= Math.floor(x); y -= Math.floor(y); z -= Math.floor(z)
    const u = this.fade(x), v = this.fade(y), w = this.fade(z)
    const p = this.perm
    const A = p[X] + Y, AA = p[A] + Z, AB = p[A + 1] + Z
    const B = p[X + 1] + Y, BA = p[B] + Z, BB = p[B + 1] + Z
    return this.lerp(
      this.lerp(
        this.lerp(this.grad(p[AA], x, y, z),     this.grad(p[BA], x-1, y, z),   u),
        this.lerp(this.grad(p[AB], x, y-1, z),   this.grad(p[BB], x-1, y-1, z), u), v),
      this.lerp(
        this.lerp(this.grad(p[AA+1], x, y, z-1), this.grad(p[BA+1], x-1, y, z-1), u),
        this.lerp(this.grad(p[AB+1], x, y-1, z-1), this.grad(p[BB+1], x-1, y-1, z-1), u), v), w)
  }

  fbm(x: number, y: number, z: number, octaves = 4): number {
    let value = 0, amplitude = 0.5, frequency = 1
    for (let i = 0; i < octaves; i++) {
      value += amplitude * this.noise(x * frequency, y * frequency, z * frequency)
      amplitude *= 0.5
      frequency *= 2
    }
    return value
  }
}
