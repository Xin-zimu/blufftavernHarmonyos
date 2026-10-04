import { randomUUID } from 'node:crypto';
import { afterEach, describe, expect, it } from 'vitest';
import { io as createClient, type Socket as ClientSocket } from 'socket.io-client';
import WebSocket from 'ws';
import type { Ack, CardRank, ClientToServerEvents, GameView, RoomMembership, RoomView, ServerToClientEvents, SessionResumeResult } from '@bluff-tavern/shared';
import { createApp } from '../src/app.js';

interface AckFrame {
  v?: number;
  id?: string;
  ok?: boolean;
  data?: unknown;
  error?: { code: string; message: string };
}

interface PushRecord {
  event: string;
  payload: unknown;
}

const zeroRandom = { nextInt: () => 0 };

class WsTestClient {
  readonly socket: WebSocket;
  readonly pushes: PushRecord[] = [];
  private nextId = 1;
  private readonly pending = new Map<string, (ack: AckFrame) => void>();
  readonly closed: Promise<void>;

  constructor(url: string) {
    this.socket = new WebSocket(url);
    this.closed = new Promise((resolve) => {
      this.socket.on('close', () => {
        for (const resolvePending of this.pending.values()) {
          resolvePending({ v: 1, id: '', ok: false, error: { code: 'DISCONNECTED', message: 'connection closed' } });
        }
        this.pending.clear();
        resolve();
      });
    });
    this.socket.on('message', (raw: unknown) => {
      const frame = this.parse(raw);
      if (!frame) return;
      if (typeof frame.event === 'string') {
        this.pushes.push({ event: frame.event, payload: frame.payload ?? null });
        return;
      }
      if (typeof frame.id === 'string') {
        const resolve = this.pending.get(frame.id);
        if (resolve) {
          this.pending.delete(frame.id);
          resolve(frame);
        }
      }
    });
  }

  ready(): Promise<this> {
    return new Promise((resolve, reject) => {
      this.socket.once('open', () => resolve(this));
      this.socket.once('error', reject);
    });
  }

  send(frame: object): void {
    this.socket.send(JSON.stringify(frame));
  }

  request(event: string, payload: unknown): Promise<AckFrame> {
    const id = `t-${this.nextId}`;
    this.nextId += 1;
    return new Promise<AckFrame>((resolve) => {
      this.pending.set(id, resolve);
      this.send({ v: 1, id, event, payload });
    });
  }

  async requestOk(event: string, payload: unknown): Promise<Record<string, unknown>> {
    const ack = await this.request(event, payload);
    if (!ack.ok) throw new Error(`${event} failed: ${ack.error?.code} ${ack.error?.message}`);
    return (ack.data ?? {}) as Record<string, unknown>;
  }

  waitPush<T = unknown>(event: string, predicate: (payload: T) => boolean = () => true, timeoutMs = 8_000): Promise<T> {
    return this.waitNextPush<T>(event, -1, predicate, timeoutMs);
  }

  // Waits for a push whose index in `pushes` is greater than `afterIndex`.
  // Used to distinguish a second game's phases from an identical first game.
  waitNextPush<T = unknown>(event: string, afterIndex: number, predicate: (payload: T) => boolean = () => true, timeoutMs = 8_000): Promise<T> {
    for (let index = afterIndex + 1; index < this.pushes.length; index += 1) {
      const frame = this.pushes[index]!;
      if (frame.event === event && predicate(frame.payload as T)) return Promise.resolve(frame.payload as T);
    }
    return new Promise<T>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.socket.off('message', onMessage);
        reject(new Error(`Timed out waiting for push ${event}`));
      }, timeoutMs);
      const onMessage = (raw: unknown) => {
        const frame = this.parse(raw);
        if (!frame || frame.event !== event || !predicate(frame.payload as T)) return;
        clearTimeout(timer);
        this.socket.off('message', onMessage);
        resolve(frame.payload as T);
      };
      this.socket.on('message', onMessage);
    });
  }

  waitForRaw(predicate: (frame: AckFrame) => boolean, timeoutMs = 8_000): Promise<AckFrame> {
    return new Promise<AckFrame>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.socket.off('message', onMessage);
        reject(new Error('Timed out waiting for raw frame'));
      }, timeoutMs);
      const onMessage = (raw: unknown) => {
        const frame = this.parse(raw);
        if (!frame || !predicate(frame)) return;
        clearTimeout(timer);
        this.socket.off('message', onMessage);
        resolve(frame);
      };
      this.socket.on('message', onMessage);
    });
  }

  close(): void {
    this.socket.close();
  }

  private parse(raw: unknown): (AckFrame & { event?: string; payload?: unknown }) | null {
    try {
      return JSON.parse(typeof raw === 'string' ? raw : String(raw)) as AckFrame & { event?: string; payload?: unknown };
    } catch {
      return null;
    }
  }
}

const ioClients: ClientSocket<ServerToClientEvents, ClientToServerEvents>[] = [];
const wsClients: WsTestClient[] = [];

afterEach(() => {
  ioClients.forEach((client) => client.disconnect());
  ioClients.length = 0;
  wsClients.forEach((client) => client.close());
  wsClients.length = 0;
});

function wait(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function startApp(random?: { nextInt(maxExclusive: number): number }, wsIdleTimeoutMs?: number) {
  const { app } = await createApp({
    host: '127.0.0.1',
    port: 0,
    clientOrigin: '*',
    logLevel: 'silent',
    ...(random ? { random } : {}),
    ...(wsIdleTimeoutMs !== undefined ? { wsIdleTimeoutMs } : {}),
  });
  await app.listen({ host: '127.0.0.1', port: 0 });
  const address = app.server.address();
  if (!address || typeof address === 'string') throw new Error('Missing address');
  return { app, httpUrl: `http://127.0.0.1:${address.port}`, wsUrl: `ws://127.0.0.1:${address.port}/ws` };
}

function connectIo(url: string): Promise<ClientSocket<ServerToClientEvents, ClientToServerEvents>> {
  const client = createClient(url, { transports: ['websocket'], forceNew: true });
  ioClients.push(client);
  return new Promise((resolve, reject) => {
    client.once('connect', () => resolve(client));
    client.once('connect_error', reject);
  });
}

function ioAck<T>(client: ClientSocket<ServerToClientEvents, ClientToServerEvents>, event: 'room:create' | 'room:join' | 'room:ready' | 'game:challenge' | 'session:resume', payload: object): Promise<Ack<T>> {
  return new Promise((resolve) => client.emit(event, payload as never, resolve as never));
}

function ioWaitGameState(client: ClientSocket<ServerToClientEvents, ClientToServerEvents>, predicate: (state: GameView) => boolean, timeoutMs = 8_000): Promise<GameView> {
  return new Promise<GameView>((resolve, reject) => {
    const timer = setTimeout(() => {
      client.off('game:snapshot', onState);
      reject(new Error('Timed out waiting for game state'));
    }, timeoutMs);
    const onState = (state: GameView) => {
      if (!predicate(state)) return;
      clearTimeout(timer);
      client.off('game:snapshot', onState);
      resolve(state);
    };
    client.on('game:snapshot', onState);
  });
}

describe('raw WebSocket transport', () => {
  it('rejects protocol violations without crashing the server', async () => {
    const { app, wsUrl } = await startApp();
    try {
      // Invalid JSON closes the connection.
      const invalidJson = await new WsTestClient(wsUrl).ready();
      invalidJson.socket.send('{not json');
      await invalidJson.closed;
      expect(invalidJson.socket.readyState).toBe(WebSocket.CLOSED);

      // Ack-shaped client frames are protocol violations.
      const impersonator = await new WsTestClient(wsUrl).ready();
      impersonator.send({ v: 1, id: 'x', ok: true, data: {} });
      await impersonator.closed;

      // Business requests require a non-empty id.
      const noId = await new WsTestClient(wsUrl).ready();
      noId.send({ v: 1, event: 'room:create', payload: { nickname: 'X' } });
      await noId.closed;

      // Wrong protocol version with an id gets a correlated INVALID_ENVELOPE ack.
      const badVersion = await new WsTestClient(wsUrl).ready();
      const invalidEnvelope = badVersion.waitForRaw((frame) => frame.id === 'vv' && frame.ok === false);
      badVersion.send({ v: 99, id: 'vv', event: 'room:create', payload: { nickname: 'X' } });
      const envelopeError = await invalidEnvelope;
      expect(envelopeError.error?.code).toBe('INVALID_ENVELOPE');
      badVersion.close();

      // Unknown business event gets an UNKNOWN_EVENT ack.
      const unknown = await new WsTestClient(wsUrl).ready();
      const unknownAck = await unknown.request('room:dance', {});
      expect(unknownAck.ok).toBe(false);
      expect(unknownAck.error?.code).toBe('UNKNOWN_EVENT');
      unknown.close();

      // Identity-requiring command without identity.
      const anon = await new WsTestClient(wsUrl).ready();
      const anonAck = await anon.request('room:ready', { roomCode: 'ABC234', ready: true, requestId: randomUUID() });
      expect(anonAck.ok).toBe(false);
      expect(anonAck.error?.code).toBe('NOT_AUTHENTICATED');
      anon.close();

      // Invalid payload on a public command.
      const badPayload = await new WsTestClient(wsUrl).ready();
      const badAck = await badPayload.request('room:create', { nickname: '' });
      expect(badAck.ok).toBe(false);
      expect(badAck.error?.code).toBe('INVALID_REQUEST');
      badPayload.close();

      // The server is still healthy after all of the abuse.
      const health = await app.inject({ method: 'GET', url: '/health' });
      expect(health.statusCode).toBe(200);
    } finally {
      await app.close();
    }
  });

  it('answers heartbeat pings and closes idle connections', async () => {
    const { app, wsUrl } = await startApp(undefined, 400);
    try {
      const client = await new WsTestClient(wsUrl).ready();
      const pong = client.waitPush('@pong');
      client.send({ v: 1, event: '@ping' });
      await pong;
      expect(client.socket.readyState).toBe(WebSocket.OPEN);

      // Stay silent past the idle timeout: the server must close the socket.
      await client.closed;
      expect(client.socket.readyState).toBe(WebSocket.CLOSED);
    } finally {
      await app.close();
    }
  }, 10_000);

  it('rate limits excessive business commands and closes the connection', async () => {
    const { app, wsUrl } = await startApp();
    try {
      const client = await new WsTestClient(wsUrl).ready();
      let lastAck: AckFrame | null = null;
      for (let attempt = 1; attempt <= 51; attempt += 1) {
        lastAck = await client.request('room:create', { nickname: `N${attempt}` });
        if (!lastAck.ok && lastAck.error?.code === 'RATE_LIMITED') break;
      }
      expect(lastAck?.error?.code).toBe('RATE_LIMITED');
      await client.closed;
    } finally {
      await app.close();
    }
  });

  it('runs a full mixed-transport classic game with private hands, idempotent replays, WS session resume and return to room', async () => {
    const { app, httpUrl, wsUrl } = await startApp(zeroRandom);
    try {
      // ===== game 1: WS host + Socket.IO guest =====
      const hostWs = await new WsTestClient(wsUrl).ready();
      wsClients.push(hostWs);
      const created = await hostWs.requestOk('room:create', { nickname: 'Host' }) as unknown as RoomMembership;
      const roomCode = created.room.code;

      const guestIo = await connectIo(httpUrl);
      const joined = await ioAck<RoomMembership>(guestIo, 'room:join', { nickname: 'Guest', roomCode });
      if (!joined.ok) throw new Error(joined.error.message);

      const hostReady = await hostWs.request('room:ready', { roomCode, ready: true, requestId: randomUUID() });
      expect(hostReady.ok).toBe(true);
      const guestReady = await ioAck<RoomView>(guestIo, 'room:ready', { roomCode, ready: true, requestId: randomUUID() });
      expect(guestReady.ok).toBe(true);

      const started = await hostWs.requestOk('game:start', { roomCode, requestId: randomUUID() }) as unknown as GameView;
      expect(started.phase).toBe('ROUND_START');
      expect(started.players).toHaveLength(2);

      const hostTurn = await hostWs.waitPush<GameView>('game:snapshot', (state) => state.phase === 'TURN');
      expect(hostTurn.turnPlayerId).toBe(created.playerId);
      expect(hostTurn.hand).toHaveLength(5);
      const initialHand: CardRank[] = [...hostTurn.hand];
      const afterPlay: CardRank[] = initialHand.slice(1);

      // The guest's private snapshot carries the guest's own hand, never the host's.
      const guestTurn = await ioWaitGameState(guestIo, (state) => state.phase === 'TURN');
      expect(guestTurn.hand).toHaveLength(5);
      expect(guestTurn.hand).not.toEqual(initialHand);

      // Idempotency: same requestId, different envelope ids -> a single execution.
      const requestId = randomUUID();
      const playOnce = await hostWs.requestOk('game:playCards', { roomCode, cardIndexes: [0], requestId }) as unknown as GameView;
      expect(playOnce.discardCount).toBe(1);
      expect(playOnce.hand).toEqual(afterPlay);
      const playTwice = await hostWs.requestOk('game:playCards', { roomCode, cardIndexes: [0], requestId }) as unknown as GameView;
      expect(playTwice.discardCount).toBe(1);
      expect(playTwice.sequence).toBe(playOnce.sequence);

      // Classic mode: the turn passed to the guest, who challenges from their turn.
      expect(playOnce.turnPlayerId).toBe(joined.data.playerId);
      const challenged = await ioAck<GameView>(guestIo, 'game:challenge', { roomCode, requestId: randomUUID() });
      expect(challenged.ok).toBe(true);

      // ZeroRandom: the host's K is a bluff -> punished -> first shot hits ->
      // host eliminated -> guest wins.
      const gameOver = await hostWs.waitPush<GameView>('game:snapshot', (state) => state.phase === 'GAME_OVER', 25_000);
      expect(gameOver.winnerId).toBe(joined.data.playerId);

      // Presentation events crossed transports.
      expect(hostWs.pushes.some((frame) => frame.event === 'game:challengeStarted')).toBe(true);
      expect(hostWs.pushes.some((frame) => frame.event === 'game:playerEliminated')).toBe(true);
      const eliminated = hostWs.pushes.find((frame) => frame.event === 'game:playerEliminated');
      expect(eliminated?.payload).toMatchObject({ playerId: created.playerId });

      // ===== game 2: restart, then the guest swaps to raw WS mid-game =====
      const indexAtRestart = hostWs.pushes.length;
      const passiveRestart = ioWaitGameState(guestIo, (state) => state.phase === 'ROUND_START' && state.matchId !== gameOver.matchId);
      const restarted = await hostWs.requestOk('game:restart', { roomCode, requestId: randomUUID() }) as unknown as GameView;
      expect(restarted.phase).toBe('ROUND_START');
      expect(restarted.hand).toEqual(initialHand);
      const guestRestarted = await passiveRestart;
      expect(restarted.matchId).toBeTruthy();
      expect(restarted.matchId).not.toBe(gameOver.matchId);
      expect(guestRestarted.matchId).toBe(restarted.matchId);
      expect(guestRestarted.sequence).toBe(1);
      expect(guestRestarted.summary).toBeNull();
      expect(guestRestarted.hand).not.toEqual(restarted.hand);

      const gameTwoTurn = await hostWs.waitNextPush<GameView>('game:snapshot', indexAtRestart, (state) => state.phase === 'TURN');
      expect(gameTwoTurn.turnPlayerId).toBe(created.playerId);

      guestIo.disconnect();
      await wait(100);
      const guestWs = await new WsTestClient(wsUrl).ready();
      wsClients.push(guestWs);
      const resumed = await guestWs.requestOk('session:resume', { sessionToken: joined.data.sessionToken }) as unknown as SessionResumeResult;
      expect(resumed.playerId).toBe(joined.data.playerId);
      expect(resumed.room.code).toBe(roomCode);
      expect(resumed.game?.phase).toBe('TURN');
      expect(resumed.game?.hand).toHaveLength(5);

      const playTwo = await hostWs.requestOk('game:playCards', { roomCode, cardIndexes: [0], requestId: randomUUID() }) as unknown as GameView;
      expect(playTwo.discardCount).toBe(1);
      const challengeTwo = await guestWs.request('game:challenge', { roomCode, requestId: randomUUID() });
      expect(challengeTwo.ok).toBe(true);

      const indexAtChallengeTwo = hostWs.pushes.length;
      const gameOverTwo = await hostWs.waitNextPush<GameView>('game:snapshot', indexAtChallengeTwo, (state) => state.phase === 'GAME_OVER', 25_000);
      expect(gameOverTwo.winnerId).toBe(joined.data.playerId);

      // ===== return to lobby and leave, all over WS =====
      const returned = await hostWs.requestOk('game:returnToRoom', { roomCode, requestId: randomUUID() }) as unknown as RoomView;
      expect(returned.status).toBe('LOBBY');
      const guestLeft = await guestWs.request('room:leave', { roomCode });
      expect(guestLeft.ok).toBe(true);
      const hostLeft = await hostWs.request('room:leave', { roomCode });
      expect(hostLeft.ok).toBe(true);

      // ===== privacy audit over every state frame the host ever received =====
      // Both games deal identical hands (zeroRandom), so while the host is
      // alive: discardCount === 0 -> initial deal; discardCount >= 1 -> hand
      // minus the played card. Once eliminated the hand is cleared server-side.
      const stateFrames = hostWs.pushes.filter((frame) => frame.event === 'game:snapshot' || frame.event === 'game:state' || frame.event === 'game:turnStarted');
      expect(stateFrames.length).toBeGreaterThan(3);
      for (const frame of stateFrames) {
        const state = frame.payload as GameView;
        const hostAlive = state.players.find((player) => player.playerId === created.playerId)?.alive ?? false;
        const expected = !hostAlive ? [] : (state.discardCount ?? 0) >= 1 ? afterPlay : initialHand;
        expect(state.hand).toEqual(expected);
      }

      // Room-wide presentation events must never carry private fields.
      for (const eventName of ['game:challengeResult', 'game:punishmentResult', 'game:over']) {
        const frames = hostWs.pushes.filter((candidate) => candidate.event === eventName);
        expect(frames.length).toBeGreaterThanOrEqual(2);
        for (const frame of frames) {
          const state = frame.payload as GameView;
          expect(state.hand).toEqual([]);
          expect(state.items).toEqual([]);
          expect(state.itemEffect).toBeNull();
          expect(state.abilityEffect).toBeNull();
        }
      }
    } finally {
      await app.close();
    }
  }, 60_000);

  it('replaces a Socket.IO session with a WS resume and vice versa', async () => {
    const { app, httpUrl, wsUrl } = await startApp();
    try {
      // --- Socket.IO connection is replaced by a raw WS resume ---
      const hostIo = await connectIo(httpUrl);
      const created = await ioAck<RoomMembership>(hostIo, 'room:create', { nickname: 'Host' });
      if (!created.ok) throw new Error(created.error.message);
      const roomCode = created.data.room.code;

      const firstWs = await new WsTestClient(wsUrl).ready();
      wsClients.push(firstWs);
      const joined = await firstWs.requestOk('room:join', { nickname: 'Guest', roomCode }) as unknown as RoomMembership;

      const replacedPromise = firstWs.waitPush('session:replaced');
      const secondIo = await connectIo(httpUrl);
      const resumed = await ioAck<SessionResumeResult>(secondIo, 'session:resume', { sessionToken: joined.sessionToken });
      expect(resumed.ok).toBe(true);
      await replacedPromise;

      // The replaced WS connection lost its identity.
      const staleAck = await firstWs.request('room:ready', { roomCode, ready: true, requestId: randomUUID() });
      expect(staleAck.ok).toBe(false);
      expect(staleAck.error?.code).toBe('NOT_AUTHENTICATED');

      // Closing the stale connection must not disturb the new session.
      firstWs.close();
      await firstWs.closed;
      await wait(50);
      const stillReady = await ioAck<RoomView>(secondIo, 'room:ready', { roomCode, ready: true, requestId: randomUUID() });
      expect(stillReady.ok).toBe(true);
      if (stillReady.ok) {
        expect(stillReady.data.players.find((player) => player.id === joined.playerId)?.isConnected).toBe(true);
      }

      // --- The Socket.IO connection is replaced by a raw WS resume ---
      const thirdWs = await new WsTestClient(wsUrl).ready();
      wsClients.push(thirdWs);
      const replacedIoPromise = new Promise<string>((resolve) => secondIo.once('session:replaced', resolve));
      const wsResume = await thirdWs.requestOk('session:resume', { sessionToken: joined.sessionToken }) as unknown as SessionResumeResult;
      expect(wsResume.playerId).toBe(joined.playerId);
      expect(await replacedIoPromise).toBe('你的会话已在新连接中恢复');

      const staleIoAck = await ioAck<RoomView>(secondIo, 'room:ready', { roomCode, ready: true, requestId: randomUUID() });
      expect(staleIoAck.ok).toBe(false);
      if (!staleIoAck.ok) expect(staleIoAck.error.code).toBe('NOT_AUTHENTICATED');

      secondIo.disconnect();
      await wait(50);
      const wsStillWorks = await thirdWs.request('room:ready', { roomCode, ready: false, requestId: randomUUID() });
      expect(wsStillWorks.ok).toBe(true);
    } finally {
      await app.close();
    }
  }, 30_000);

  it('keeps the Socket.IO polling transport working alongside the /ws gateway', async () => {
    const { app, httpUrl } = await startApp();
    try {
      const poller = createClient(httpUrl, { transports: ['polling'], forceNew: true });
      ioClients.push(poller);
      await new Promise<void>((resolve, reject) => {
        poller.once('connect', () => resolve());
        poller.once('connect_error', reject);
      });
      const created = await new Promise<Ack<RoomMembership>>((resolve) => poller.emit('room:create', { nickname: 'Poller' }, resolve as never));
      expect(created.ok).toBe(true);
    } finally {
      await app.close();
    }
  });
});
