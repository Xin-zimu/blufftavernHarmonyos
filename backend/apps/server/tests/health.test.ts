import { describe, expect, it } from 'vitest';
import { createApp } from '../src/app.js';

interface HealthPayload {
  status: string;
  version: string;
  uptime: number;
  rooms: number;
  connections: number;
  players: number;
  matches: number;
}

describe('health endpoint', () => {
  it('reports V7.2 runtime counters', async () => {
    const { app } = await createApp({ host: '127.0.0.1', port: 0, clientOrigin: '*', logLevel: 'silent' });
    try {
      const response = await app.inject({ method: 'GET', url: '/health' });
      const payload = response.json<HealthPayload>();
      expect(response.statusCode).toBe(200);
      expect(payload).toMatchObject({
        status: 'ok',
        version: '7.2.0',
        rooms: 0,
        connections: 0,
        players: 0,
        matches: 0,
      });
      expect(payload.uptime).toEqual(expect.any(Number));
    } finally {
      await app.close();
    }
  });
});
