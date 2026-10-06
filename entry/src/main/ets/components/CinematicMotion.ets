// Numeric transcription of styles.css at 9e7f88b. Times are milliseconds.
// The native Animator supplies interpolated time; the 100ms state clock never
// drives frames. CSS timing functions apply BETWEEN keyframes, not globally.
export function bezier(t: number, x1: number, y1: number, x2: number, y2: number): number {
  if (t <= 0) return 0
  if (t >= 1) return 1
  let lo: number = 0
  let hi: number = 1
  let u: number = t
  for (let i: number = 0; i < 20; i++) {
    u = (lo + hi) / 2
    const x: number = 3 * (1-u) * (1-u) * u * x1 + 3 * (1-u) * u * u * x2 + u*u*u
    if (x < t) lo = u
    else hi = u
  }
  return 3*(1-u)*(1-u)*u*y1 + 3*(1-u)*u*u*y2 + u*u*u
}

export function keyframe(elapsed: number, duration: number, stops: number[], values: number[],
  curve: number[] = [0, 0, 0.58, 1]): number {
  const t: number = Math.max(0, Math.min(1, elapsed / duration))
  for (let i: number = 1; i < stops.length; i++) {
    if (t <= stops[i]) {
      const p: number = bezier((t-stops[i-1])/(stops[i]-stops[i-1]), curve[0], curve[1], curve[2], curve[3])
      return values[i-1] + (values[i]-values[i-1])*p
    }
  }
  return values[values.length-1]
}

export function revealProgress(elapsed: number, index: number, reduced: boolean): number {
  const flippedAt: number = 500 + index * 750
  if (reduced) return elapsed >= flippedAt ? 1 : 0
  return bezier((elapsed - flippedAt - index * 90) / 500, 0.2, 0.72, 0.18, 1)
}

export function cinematicIdentity(matchId: string, round: number, phase: string, startedAt: number): string {
  return `${matchId}:${round}:${phase}:${startedAt}`
}
