import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { GameScheduler } from '../src/game/game-scheduler.js';

describe('GameScheduler', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(1_000);
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('runs the scheduled room callback when the phase ends', () => {
    const scheduler = new GameScheduler();
    const elapsed = vi.fn();
    scheduler.schedule('ABC234', Date.now() + 100, elapsed);

    vi.advanceTimersByTime(99);
    expect(elapsed).not.toHaveBeenCalled();

    vi.advanceTimersByTime(1);
    expect(elapsed).toHaveBeenCalledTimes(1);
    expect(scheduler.has('ABC234')).toBe(false);
  });

  it('clears the previous room timer when a new phase is scheduled', () => {
    const scheduler = new GameScheduler();
    const oldElapsed = vi.fn();
    const newElapsed = vi.fn();

    scheduler.schedule('ABC234', Date.now() + 100, oldElapsed);
    scheduler.schedule('ABC234', Date.now() + 200, newElapsed);

    vi.advanceTimersByTime(100);
    expect(oldElapsed).not.toHaveBeenCalled();
    expect(newElapsed).not.toHaveBeenCalled();

    vi.advanceTimersByTime(100);
    expect(oldElapsed).not.toHaveBeenCalled();
    expect(newElapsed).toHaveBeenCalledTimes(1);
  });
});
