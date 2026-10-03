export class GameScheduler {
  private readonly timers = new Map<string, ReturnType<typeof setTimeout>>();

  schedule(roomCode: string, phaseEndsAt: number | null, onElapsed: () => void): void {
    this.cancel(roomCode);
    if (phaseEndsAt === null) return;
    const delay = Math.max(0, phaseEndsAt - Date.now());
    const timer = setTimeout(() => {
      this.timers.delete(roomCode);
      onElapsed();
    }, delay);
    timer.unref?.();
    this.timers.set(roomCode, timer);
  }

  cancel(roomCode: string): void {
    const timer = this.timers.get(roomCode);
    if (!timer) return;
    clearTimeout(timer);
    this.timers.delete(roomCode);
  }

  has(roomCode: string): boolean {
    return this.timers.has(roomCode);
  }
}
