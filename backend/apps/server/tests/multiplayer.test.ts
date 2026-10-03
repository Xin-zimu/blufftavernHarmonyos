import { randomUUID } from 'node:crypto';
import { afterEach, describe, expect, it } from 'vitest';
import { io as createClient, type Socket as ClientSocket } from 'socket.io-client';
import type { Ack, ClientToServerEvents, GameView, PlayableGameMode, RoomMembership, RoomView, ServerToClientEvents, SessionResumeResult } from '@bluff-tavern/shared';
import { createApp } from '../src/app.js';

const clients: ClientSocket<ServerToClientEvents, ClientToServerEvents>[] = [];
afterEach(() => { clients.forEach((client) => client.disconnect()); clients.length = 0; });

function connect(url: string) {
  const client = createClient(url, { transports: ['websocket'], forceNew: true });
  clients.push(client);
  return new Promise<typeof client>((resolve, reject) => {
    client.once('connect', () => resolve(client));
    client.once('connect_error', reject);
  });
}

function emitAck<T>(client: ClientSocket<ServerToClientEvents, ClientToServerEvents>, event: 'room:create' | 'room:join' | 'room:ready' | 'room:updateSettings' | 'room:kick' | 'room:selectCharacter' | 'game:start' | 'game:playCards' | 'game:challenge' | 'game:useItem' | 'session:resume', payload: object) {
  return new Promise<Ack<T>>((resolve) => client.emit(event, payload as never, resolve as never));
}

function waitForGameState(client: ClientSocket<ServerToClientEvents, ClientToServerEvents>, predicate: (state: GameView) => boolean, timeoutMs = 6_000) {
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

const zeroRandom = { nextInt: () => 0 };

function wait(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function startSocketApp(random?: { nextInt(maxExclusive: number): number }) {
  const { app } = await createApp({ host: '127.0.0.1', port: 0, clientOrigin: '*', logLevel: 'silent', ...(random ? { random } : {}) });
  await app.listen({ host: '127.0.0.1', port: 0 });
  const address = app.server.address();
  if (!address || typeof address === 'string') throw new Error('Missing address');
  return { app, url: `http://127.0.0.1:${address.port}` };
}

async function createStartedSocketGame(url: string, playerCount: number, gameMode: PlayableGameMode) {
  const host = await connect(url);
  const created = await emitAck<RoomMembership>(host, 'room:create', { nickname: 'A' });
  if (!created.ok) throw new Error(created.error.message);
  const peers = await Promise.all(Array.from({ length: playerCount - 1 }, async (_, index) => {
    const peer = await connect(url);
    const joined = await emitAck<RoomMembership>(peer, 'room:join', { nickname: String.fromCharCode(66 + index), roomCode: created.data.room.code });
    if (!joined.ok) throw new Error(joined.error.message);
    return { client: peer, membership: joined.data };
  }));
  const settings = await emitAck<RoomView>(host, 'room:updateSettings', {
    roomCode: created.data.room.code,
    maxPlayers: playerCount,
    gameMode,
    requestId: randomUUID(),
  });
  if (!settings.ok) throw new Error(settings.error.message);
  const players = [{ client: host, membership: created.data }, ...peers];
  await Promise.all(players.map(({ client }) => emitAck<RoomView>(client, 'room:ready', {
    roomCode: created.data.room.code,
    ready: true,
    requestId: randomUUID(),
  })));
  const started = await emitAck<GameView>(host, 'game:start', { roomCode: created.data.room.code, requestId: randomUUID() });
  if (!started.ok) throw new Error(started.error.message);
  const turn = await waitForGameState(host, (state) => state.phase === 'TURN' && state.gameMode === gameMode);
  const clientsByPlayer = new Map(players.map(({ client, membership }) => [membership.playerId, client] as const));
  return { roomCode: created.data.room.code, players, clientsByPlayer, turn };
}

async function playOneCardIntoChallengeWindow(roomCode: string, turn: GameView, clientsByPlayer: Map<string, ClientSocket<ServerToClientEvents, ClientToServerEvents>>) {
  if (!turn.turnPlayerId) throw new Error('Missing turn player');
  const turnClient = clientsByPlayer.get(turn.turnPlayerId);
  if (!turnClient) throw new Error('Missing turn client');
  const played = await emitAck<GameView>(turnClient, 'game:playCards', {
    roomCode,
    cardIndexes: [0],
    requestId: randomUUID(),
  });
  expect(played).toMatchObject({ ok: true, data: { phase: 'CHALLENGE_WINDOW', gameMode: 'FREE_CHALLENGE' } });
  if (!played.ok) throw new Error(played.error.message);
  return { windowState: played.data, playerId: turn.turnPlayerId, client: turnClient };
}

describe('real Socket.IO multiplayer', () => {
  it('closes promptly while Socket.IO clients are still connected', async () => {
    const { app } = await createApp({ host: '127.0.0.1', port: 0, clientOrigin: '*', logLevel: 'silent' });
    await app.listen({ host: '127.0.0.1', port: 0 });
    const address = app.server.address();
    if (!address || typeof address === 'string') throw new Error('Missing address');
    const url = `http://127.0.0.1:${address.port}`;
    let closePromise: Promise<void> | null = null;
    try {
      const host = await connect(url);
      const created = await emitAck<RoomMembership>(host, 'room:create', { nickname: 'CloseCheck' });
      expect(created.ok).toBe(true);

      closePromise = app.close();
      await expect(Promise.race([
        closePromise.then(() => 'closed'),
        new Promise((_, reject) => setTimeout(() => reject(new Error('Timed out waiting for app.close()')), 1_500)),
      ])).resolves.toBe('closed');
    } finally {
      clients.forEach((client) => client.disconnect());
      clients.length = 0;
      if (closePromise) await closePromise.catch(() => undefined);
      else await app.close().catch(() => undefined);
    }
  });

  it('synchronizes eight clients and restores a disconnected eighth seat', async () => {
    const { app } = await createApp({ host: '127.0.0.1', port: 0, clientOrigin: '*', logLevel: 'silent' });
    await app.listen({ host: '127.0.0.1', port: 0 });
    const address = app.server.address();
    if (!address || typeof address === 'string') throw new Error('Missing address');
    const url = `http://127.0.0.1:${address.port}`;
    try {
      const host = await connect(url);
      const created = await emitAck<RoomMembership>(host, 'room:create', { nickname: 'Host8' });
      if (!created.ok) throw new Error(created.error.message);
      const joined = await Promise.all(Array.from({ length: 7 }, async (_, index) => {
        const peer = await connect(url);
        const result = await emitAck<RoomMembership>(peer, 'room:join', { nickname: `E${index + 2}`, roomCode: created.data.room.code });
        if (!result.ok) throw new Error(result.error.message);
        return { peer, membership: result.data };
      }));
      await Promise.all([host, ...joined.map(({ peer }) => peer)].map((client) => emitAck<RoomView>(client, 'room:ready', { roomCode: created.data.room.code, ready: true, requestId: randomUUID() })));
      const started = await emitAck<GameView>(host, 'game:start', { roomCode: created.data.room.code, requestId: randomUUID() });
      if (!started.ok) throw new Error(started.error.message);
      expect(started.data.players).toHaveLength(8);
      expect(started.data.players.reduce((sum, player) => sum + (player.cardCount ?? 0), 0)).toBe(40);
      const last = joined[6]!;
      last.peer.disconnect();
      await new Promise((resolve) => setTimeout(resolve, 30));
      const restored = await connect(url);
      const resumed = await emitAck<SessionResumeResult>(restored, 'session:resume', { sessionToken: last.membership.sessionToken });
      expect(resumed).toMatchObject({ ok: true, data: { playerId: last.membership.playerId } });
    } finally { clients.forEach((client) => client.disconnect()); clients.length = 0; await app.close(); }
  });

  it('starts a real six-player Grand Table with the 30-card deck', async () => {
    const { app } = await createApp({ host: '127.0.0.1', port: 0, clientOrigin: '*', logLevel: 'silent' });
    await app.listen({ host: '127.0.0.1', port: 0 });
    const address = app.server.address();
    if (!address || typeof address === 'string') throw new Error('Missing address');
    const url = `http://127.0.0.1:${address.port}`;
    try {
      const host = await connect(url);
      const created = await emitAck<RoomMembership>(host, 'room:create', { nickname: 'Host6' });
      if (!created.ok) throw new Error(created.error.message);
      const peers = await Promise.all(Array.from({ length: 5 }, async (_, index) => {
        const peer = await connect(url);
        const joined = await emitAck<RoomMembership>(peer, 'room:join', { nickname: `P${index + 2}`, roomCode: created.data.room.code });
        if (!joined.ok) throw new Error(joined.error.message);
        return peer;
      }));
      const settings = await emitAck<RoomView>(host, 'room:updateSettings', { roomCode: created.data.room.code, maxPlayers: 6, gameMode: 'QUICK', requestId: randomUUID() });
      expect(settings).toMatchObject({ ok: true, data: { settings: { maxPlayers: 6, gameMode: 'QUICK' } } });
      await Promise.all([host, ...peers].map((client) => emitAck<RoomView>(client, 'room:ready', { roomCode: created.data.room.code, ready: true, requestId: randomUUID() })));
      const started = await emitAck<GameView>(host, 'game:start', { roomCode: created.data.room.code, requestId: randomUUID() });
      expect(started).toMatchObject({ ok: true, data: { gameMode: 'QUICK', turnDurationSeconds: 7 } });
      if (!started.ok) throw new Error('Game did not start');
      expect(started.data.players).toHaveLength(6);
      expect(started.data.players.reduce((sum, player) => sum + (player.cardCount ?? 0), 0)).toBe(30);
    } finally {
      clients.forEach((client) => client.disconnect());
      clients.length = 0;
      await app.close();
    }
  });

  it('starts and synchronizes a real Escalation mode turn', async () => {
    const { app } = await createApp({ host: '127.0.0.1', port: 0, clientOrigin: '*', logLevel: 'silent' });
    await app.listen({ host: '127.0.0.1', port: 0 });
    const address = app.server.address();
    if (!address || typeof address === 'string') throw new Error('Missing address');
    const url = `http://127.0.0.1:${address.port}`;
    try {
      const host = await connect(url);
      const created = await emitAck<RoomMembership>(host, 'room:create', { nickname: 'HostMode' });
      if (!created.ok) throw new Error(created.error.message);
      const guest = await connect(url);
      const joined = await emitAck<RoomMembership>(guest, 'room:join', { nickname: 'GuestMode', roomCode: created.data.room.code });
      if (!joined.ok) throw new Error(joined.error.message);
      const settings = await emitAck<RoomView>(host, 'room:updateSettings', {
        roomCode: created.data.room.code,
        maxPlayers: 2,
        gameMode: 'ESCALATION',
        v7: { tavernEventsEnabled: true },
        requestId: randomUUID(),
      });
      expect(settings).toMatchObject({ ok: true, data: { settings: { gameMode: 'ESCALATION', turnDurationSeconds: 15, v7: { tavernEventsEnabled: false } } } });
      await Promise.all([host, guest].map((client) => emitAck<RoomView>(client, 'room:ready', {
        roomCode: created.data.room.code, ready: true, requestId: randomUUID(),
      })));
      const started = await emitAck<GameView>(host, 'game:start', { roomCode: created.data.room.code, requestId: randomUUID() });
      expect(started).toMatchObject({ ok: true, data: { gameMode: 'ESCALATION', minimumPlayCount: 1 } });
      const turn = await waitForGameState(host, (state) => state.phase === 'TURN' && state.gameMode === 'ESCALATION');
      if (!turn.turnPlayerId) throw new Error('Missing turn player');
      const clientsByPlayer = new Map<string, ClientSocket<ServerToClientEvents, ClientToServerEvents>>([
        [created.data.playerId, host],
        [joined.data.playerId, guest],
      ]);
      const turnClient = clientsByPlayer.get(turn.turnPlayerId);
      if (!turnClient) throw new Error('Missing turn client');

      const played = await emitAck<GameView>(turnClient, 'game:playCards', {
        roomCode: created.data.room.code,
        cardIndexes: [0, 1],
        requestId: randomUUID(),
      });

      expect(played).toMatchObject({ ok: true, data: { gameMode: 'ESCALATION', lastPlay: { count: 2 }, minimumPlayCount: 2 } });
    } finally {
      clients.forEach((client) => client.disconnect());
      clients.length = 0;
      await app.close();
    }
  });

  it('uses a V7 item through the real Socket.IO flow', async () => {
    const { app } = await createApp({ host: '127.0.0.1', port: 0, clientOrigin: '*', logLevel: 'silent' });
    await app.listen({ host: '127.0.0.1', port: 0 });
    const address = app.server.address();
    if (!address || typeof address === 'string') throw new Error('Missing address');
    const url = `http://127.0.0.1:${address.port}`;
    try {
      const host = await connect(url);
      const created = await emitAck<RoomMembership>(host, 'room:create', { nickname: 'Host' });
      if (!created.ok) throw new Error(created.error.message);
      const guest = await connect(url);
      const joined = await emitAck<RoomMembership>(guest, 'room:join', { nickname: 'Guest', roomCode: created.data.room.code });
      if (!joined.ok) throw new Error(joined.error.message);
      const settings = await emitAck<RoomView>(host, 'room:updateSettings', {
        roomCode: created.data.room.code,
        maxPlayers: 2,
        gameMode: 'CLASSIC',
        v7: { itemsEnabled: true },
        requestId: randomUUID(),
      });
      expect(settings).toMatchObject({ ok: true, data: { settings: { v7: { itemsEnabled: true } } } });
      await Promise.all([host, guest].map((client) => emitAck<RoomView>(client, 'room:ready', {
        roomCode: created.data.room.code, ready: true, requestId: randomUUID(),
      })));
      const started = await emitAck<GameView>(host, 'game:start', { roomCode: created.data.room.code, requestId: randomUUID() });
      expect(started.ok).toBe(true);
      const turn = await waitForGameState(host, (state) => state.phase === 'TURN' && state.items.length === 1);
      const item = turn.items[0];
      if (!item) throw new Error('Missing V7 item');

      const used = await emitAck<GameView>(host, 'game:useItem', { roomCode: created.data.room.code, itemId: item, requestId: randomUUID() });

      expect(used).toMatchObject({ ok: true, data: { items: [] } });
      if (!used.ok) throw new Error('Item use failed');
      expect(used.data.itemEffect?.itemId).toBe(item);
    } finally {
      clients.forEach((client) => client.disconnect());
      clients.length = 0;
      await app.close();
    }
  });

  it('starts a V7 character ability through the real Socket.IO flow', async () => {
    const { app } = await createApp({ host: '127.0.0.1', port: 0, clientOrigin: '*', logLevel: 'silent' });
    await app.listen({ host: '127.0.0.1', port: 0 });
    const address = app.server.address();
    if (!address || typeof address === 'string') throw new Error('Missing address');
    const url = `http://127.0.0.1:${address.port}`;
    try {
      const host = await connect(url);
      const created = await emitAck<RoomMembership>(host, 'room:create', { nickname: 'Host' });
      if (!created.ok) throw new Error(created.error.message);
      const guest = await connect(url);
      const joined = await emitAck<RoomMembership>(guest, 'room:join', { nickname: 'Guest', roomCode: created.data.room.code });
      if (!joined.ok) throw new Error(joined.error.message);

      const selected = await emitAck<RoomView>(host, 'room:selectCharacter', { roomCode: created.data.room.code, characterId: 'CAT' });
      expect(selected.ok).toBe(true);
      if (!selected.ok) throw new Error(selected.error.message);
      expect(selected.data.players.find((player) => player.id === created.data.playerId)).toMatchObject({ characterId: 'CAT' });
      const settings = await emitAck<RoomView>(host, 'room:updateSettings', {
        roomCode: created.data.room.code,
        maxPlayers: 2,
        gameMode: 'CLASSIC',
        v7: { characterAbilitiesEnabled: true },
        requestId: randomUUID(),
      });
      expect(settings).toMatchObject({ ok: true, data: { settings: { v7: { characterAbilitiesEnabled: true } } } });
      await Promise.all([host, guest].map((client) => emitAck<RoomView>(client, 'room:ready', {
        roomCode: created.data.room.code, ready: true, requestId: randomUUID(),
      })));

      const started = await emitAck<GameView>(host, 'game:start', { roomCode: created.data.room.code, requestId: randomUUID() });

      expect(started).toMatchObject({ ok: true, data: { abilityEffect: { characterId: 'CAT', abilityId: 'CAT_NIGHT_EYE', type: 'RISK_HINT' } } });
    } finally {
      clients.forEach((client) => client.disconnect());
      clients.length = 0;
      await app.close();
    }
  });

  it('synchronizes four players joining and one disconnecting', async () => {
    const { app } = await createApp({ host: '127.0.0.1', port: 0, clientOrigin: '*', logLevel: 'silent' });
    await app.listen({ host: '127.0.0.1', port: 0 });
    const address = app.server.address();
    if (!address || typeof address === 'string') throw new Error('Missing address');
    const url = `http://127.0.0.1:${address.port}`;
    try {
      const a = await connect(url);
      const created = await emitAck<RoomMembership>(a, 'room:create', { nickname: 'A' });
      if (!created.ok) throw new Error(created.error.message);
      const fourPlayers = new Promise<number>((resolve) => {
        const timer = setTimeout(() => resolve(-1), 2_000);
        a.on('room:state', (room: RoomView) => {
          if (room.players.length === 4) { clearTimeout(timer); resolve(4); }
        });
      });
      const peers = await Promise.all(['B', 'C', 'D'].map(async (nickname) => {
        const peer = await connect(url);
        const joined = await emitAck<RoomMembership>(peer, 'room:join', { nickname, roomCode: created.data.room.code });
        expect(joined.ok).toBe(true);
        if (!joined.ok) throw new Error('Join failed');
        return { peer, playerId: joined.data.playerId };
      }));
      expect(await fourPlayers).toBe(4);
      const nonHostSettings = await emitAck<RoomView>(peers[0]!.peer, 'room:updateSettings', {
        roomCode: created.data.room.code, maxPlayers: 4, requestId: randomUUID(),
      });
      expect(nonHostSettings).toMatchObject({ ok: false, error: { code: 'NOT_HOST' } });
      const changedSettings = await emitAck<RoomView>(a, 'room:updateSettings', {
        roomCode: created.data.room.code, maxPlayers: 4, requestId: randomUUID(),
      });
      expect(changedSettings).toMatchObject({ ok: true, data: { settings: { maxPlayers: 4 } } });
      await Promise.all([a, ...peers.map(({ peer }) => peer)].map((client) => emitAck<RoomView>(client, 'room:ready', {
        roomCode: created.data.room.code, ready: true, requestId: randomUUID(),
      })));
      const playerClients = new Map<string, typeof a>();
      playerClients.set(created.data.playerId, a);
      peers.forEach(({ peer, playerId }) => playerClients.set(playerId, peer));
      const gameStates = new Map<string, GameView>();
      for (const [playerId, client] of playerClients) client.on('game:state', (state: GameView) => gameStates.set(playerId, state));
      const started = await emitAck<GameView>(a, 'game:start', { roomCode: created.data.room.code, requestId: randomUUID() });
      expect(started.ok).toBe(true);
      const turnReady = await waitForGameState(a, (state) => state.phase === 'TURN');
      await new Promise((resolve) => setTimeout(resolve, 20));
      expect(gameStates.size).toBe(4);
      if (!started.ok) throw new Error('Game did not start');
      if (!turnReady.turnPlayerId) throw new Error('Missing turn player');
      const turnState = gameStates.get(turnReady.turnPlayerId);
      const turnClient = playerClients.get(turnReady.turnPlayerId);
      if (!turnState || !turnClient) throw new Error('Missing turn state');
      const played = await emitAck<GameView>(turnClient, 'game:playCards', {
        roomCode: created.data.room.code, cardIndexes: [0], requestId: randomUUID(),
      });
      expect(played).toMatchObject({ ok: true, data: { discardCount: 1 } });
      const afterLeave = new Promise<number>((resolve) => a.on('room:state', (room: RoomView) => {
        if (room.players.length === 4 && room.players.some((player) => !player.isConnected)) resolve(4);
      }));
      peers[0]!.peer.disconnect();
      expect(await afterLeave).toBe(4);
    } finally {
      clients.forEach((client) => client.disconnect());
      clients.length = 0;
      await app.close();
    }
  });

  it('restores a disconnected game player through a real Socket.IO session', async () => {
    const { app } = await createApp({ host: '127.0.0.1', port: 0, clientOrigin: '*', logLevel: 'silent' });
    await app.listen({ host: '127.0.0.1', port: 0 });
    const address = app.server.address();
    if (!address || typeof address === 'string') throw new Error('Missing address');
    const url = `http://127.0.0.1:${address.port}`;
    try {
      const host = await connect(url);
      const created = await emitAck<RoomMembership>(host, 'room:create', { nickname: 'Host' });
      if (!created.ok) throw new Error(created.error.message);
      const guest = await connect(url);
      const joined = await emitAck<RoomMembership>(guest, 'room:join', { nickname: 'Guest', roomCode: created.data.room.code });
      if (!joined.ok) throw new Error(joined.error.message);
      await Promise.all([host, guest].map((client) => emitAck<RoomView>(client, 'room:ready', {
        roomCode: created.data.room.code, ready: true, requestId: randomUUID(),
      })));
      const guestSnapshot = waitForGameState(guest, (state) => state.roundNumber === 1 && state.hand.length === 5);
      const started = await emitAck<GameView>(host, 'game:start', { roomCode: created.data.room.code, requestId: randomUUID() });
      expect(started.ok).toBe(true);
      const beforeDisconnect = await guestSnapshot;
      guest.disconnect();
      await new Promise((resolve) => setTimeout(resolve, 30));
      const restored = await connect(url);
      const resumed = await emitAck<SessionResumeResult>(restored, 'session:resume', { sessionToken: joined.data.sessionToken });
      expect(resumed).toMatchObject({ ok: true, data: { playerId: joined.data.playerId } });
      if (!resumed.ok) throw new Error('Resume failed');
      expect(resumed.data.room.players).toHaveLength(2);
      expect(resumed.data.room.players.find((player) => player.id === joined.data.playerId)?.isConnected).toBe(true);
      expect(resumed.data.game?.roundNumber).toBe(beforeDisconnect.roundNumber);
      expect(resumed.data.game?.hand).toEqual(beforeDisconnect.hand);
      expect(resumed.data.game?.players.some((player) => player.playerId === joined.data.playerId && player.connected)).toBe(true);
    } finally {
      clients.forEach((client) => client.disconnect());
      clients.length = 0;
      await app.close();
    }
  });

  it('replaces an older socket when the same session resumes elsewhere', async () => {
    const { app } = await createApp({ host: '127.0.0.1', port: 0, clientOrigin: '*', logLevel: 'silent' });
    await app.listen({ host: '127.0.0.1', port: 0 });
    const address = app.server.address();
    if (!address || typeof address === 'string') throw new Error('Missing address');
    const url = `http://127.0.0.1:${address.port}`;
    try {
      const host = await connect(url);
      const created = await emitAck<RoomMembership>(host, 'room:create', { nickname: 'Host' });
      if (!created.ok) throw new Error(created.error.message);
      const guest = await connect(url);
      const joined = await emitAck<RoomMembership>(guest, 'room:join', { nickname: 'Guest', roomCode: created.data.room.code });
      if (!joined.ok) throw new Error(joined.error.message);

      const replaced = new Promise<string>((resolve) => guest.once('session:replaced', resolve));
      const restored = await connect(url);
      const resumed = await emitAck<SessionResumeResult>(restored, 'session:resume', { sessionToken: joined.data.sessionToken });
      expect(resumed).toMatchObject({ ok: true, data: { playerId: joined.data.playerId, game: null } });
      expect(await replaced).toBe('你的会话已在新连接中恢复');

      const staleReady = await emitAck<RoomView>(guest, 'room:ready', {
        roomCode: created.data.room.code,
        ready: true,
        requestId: randomUUID(),
      });
      expect(staleReady).toMatchObject({ ok: false, error: { code: 'NOT_AUTHENTICATED' } });

      const restoredReady = await emitAck<RoomView>(restored, 'room:ready', {
        roomCode: created.data.room.code,
        ready: true,
        requestId: randomUUID(),
      });
      expect(restoredReady).toMatchObject({ ok: true });
    } finally {
      clients.forEach((client) => client.disconnect());
      clients.length = 0;
      await app.close();
    }
  });

  it('keeps three clients on the same V6 phase sequence without leaking punishment result early', async () => {
    const { app } = await createApp({ host: '127.0.0.1', port: 0, clientOrigin: '*', logLevel: 'silent' });
    await app.listen({ host: '127.0.0.1', port: 0 });
    const address = app.server.address();
    if (!address || typeof address === 'string') throw new Error('Missing address');
    const url = `http://127.0.0.1:${address.port}`;
    try {
      const host = await connect(url);
      const created = await emitAck<RoomMembership>(host, 'room:create', { nickname: 'A' });
      if (!created.ok) throw new Error(created.error.message);
      const peers = await Promise.all(['B', 'C'].map(async (nickname) => {
        const peer = await connect(url);
        const joined = await emitAck<RoomMembership>(peer, 'room:join', { nickname, roomCode: created.data.room.code });
        if (!joined.ok) throw new Error(joined.error.message);
        return { peer, playerId: joined.data.playerId };
      }));
      await Promise.all([host, ...peers.map(({ peer }) => peer)].map((client) => emitAck<RoomView>(client, 'room:ready', {
        roomCode: created.data.room.code, ready: true, requestId: randomUUID(),
      })));
      const started = await emitAck<GameView>(host, 'game:start', { roomCode: created.data.room.code, requestId: randomUUID() });
      expect(started.ok).toBe(true);
      const turn = await waitForGameState(host, (state) => state.phase === 'TURN');
      if (!turn.turnPlayerId) throw new Error('Missing turn player');
      const clientsByPlayer = new Map<string, ClientSocket<ServerToClientEvents, ClientToServerEvents>>([
        [created.data.playerId, host],
        ...peers.map(({ peer, playerId }) => [playerId, peer] as const),
      ]);
      const turnClient = clientsByPlayer.get(turn.turnPlayerId);
      if (!turnClient) throw new Error('Missing turn client');
      const played = await emitAck<GameView>(turnClient, 'game:playCards', { roomCode: created.data.room.code, cardIndexes: [0], requestId: randomUUID() });
      expect(played.ok).toBe(true);
      if (!played.ok) throw new Error('Play failed');
      const nextTurn = played.data;
      if (!nextTurn.turnPlayerId) throw new Error('Missing challenger');
      const challengerClient = clientsByPlayer.get(nextTurn.turnPlayerId);
      if (!challengerClient) throw new Error('Missing challenger client');
      const challenged = await emitAck<GameView>(challengerClient, 'game:challenge', { roomCode: created.data.room.code, requestId: randomUUID() });
      expect(challenged).toMatchObject({ ok: true, data: { phase: 'CHALLENGE_CALLOUT', punishment: null } });

      const revealStates = await Promise.all([host, ...peers.map(({ peer }) => peer)].map((client) => waitForGameState(client, (state) => state.phase === 'REVEAL')));
      expect(new Set(revealStates.map((state) => state.sequence)).size).toBe(1);
      expect(revealStates.every((state) => state.punishment === null)).toBe(true);

      const trigger = await waitForGameState(host, (state) => state.phase === 'PUNISHMENT_TRIGGER');
      expect(trigger.punishment).toBeNull();
      const result = await waitForGameState(host, (state) => state.phase === 'PUNISHMENT_RESULT');
      expect(result.punishment?.hit).toEqual(expect.any(Boolean));
    } finally {
      clients.forEach((client) => client.disconnect());
      clients.length = 0;
      await app.close();
    }
  });

  it('accepts only one concurrent Free Challenge challenger and broadcasts that challenger to every client', async () => {
    const { app, url } = await startSocketApp();
    try {
      const { roomCode, players, clientsByPlayer, turn } = await createStartedSocketGame(url, 5, 'FREE_CHALLENGE');
      const { windowState, playerId: challengedId } = await playOneCardIntoChallengeWindow(roomCode, turn, clientsByPlayer);
      const challengerPlayers = players.filter(({ membership }) => membership.playerId !== challengedId);
      const finalSnapshots = players.map(({ client }) => waitForGameState(client, (state) => state.phase === 'CHALLENGE_CALLOUT'));

      const attempts = await Promise.all(challengerPlayers.map(({ client }) => emitAck<GameView>(client, 'game:challenge', {
        roomCode,
        requestId: randomUUID(),
      })));

      const successes = attempts.filter((attempt) => attempt.ok);
      const failures = attempts.filter((attempt) => !attempt.ok);
      expect(windowState.freeChallenge?.challengerId).toBeNull();
      expect(successes).toHaveLength(1);
      expect(failures).toHaveLength(challengerPlayers.length - 1);
      expect(failures.every((attempt) => !attempt.ok && attempt.error.code === 'CHALLENGE_ALREADY_TAKEN')).toBe(true);
      const challengerId = successes[0]!.data.challenge?.challengerId;
      expect(challengerId).toBeTruthy();

      const snapshots = await Promise.all(finalSnapshots);
      expect(new Set(snapshots.map((snapshot) => snapshot.challenge?.challengerId))).toEqual(new Set([challengerId]));
      expect(new Set(snapshots.map((snapshot) => snapshot.challenge?.challengedId))).toEqual(new Set([challengedId]));
    } finally {
      clients.forEach((client) => client.disconnect());
      clients.length = 0;
      await app.close();
    }
  });

  it('keeps Free Challenge unique at the window closing boundary', async () => {
    const { app, url } = await startSocketApp();
    try {
      const { roomCode, players, clientsByPlayer, turn } = await createStartedSocketGame(url, 4, 'FREE_CHALLENGE');
      const { windowState, playerId: challengedId } = await playOneCardIntoChallengeWindow(roomCode, turn, clientsByPlayer);
      const settledState = waitForGameState(players[0]!.client, (state) => state.phase !== 'CHALLENGE_WINDOW', 7_000);
      await wait(Math.max(0, (windowState.phaseEndsAt ?? Date.now()) - Date.now() - 5));

      const attempts = await Promise.all(players
        .filter(({ membership }) => membership.playerId !== challengedId)
        .map(({ client }) => emitAck<GameView>(client, 'game:challenge', { roomCode, requestId: randomUUID() })));

      const successes = attempts.filter((attempt) => attempt.ok);
      expect(successes.length).toBeLessThanOrEqual(1);
      if (successes.length === 1) {
        const challengerId = successes[0]!.data.challenge?.challengerId;
        const settled = await settledState;
        expect(settled.phase).toBe('CHALLENGE_CALLOUT');
        expect(settled.challenge?.challengerId).toBe(challengerId);
      } else {
        expect(attempts.every((attempt) => !attempt.ok && attempt.error.code === 'CHALLENGE_WINDOW_CLOSED')).toBe(true);
        const settled = await settledState;
        expect(settled.phase).toBe('TURN');
        expect(settled.freeChallenge).toBeNull();
      }
    } finally {
      clients.forEach((client) => client.disconnect());
      clients.length = 0;
      await app.close();
    }
  });

  it('returns to the next turn when nobody takes a Free Challenge window', async () => {
    const { app, url } = await startSocketApp();
    try {
      const { roomCode, players, clientsByPlayer, turn } = await createStartedSocketGame(url, 3, 'FREE_CHALLENGE');
      const { playerId: challengedId } = await playOneCardIntoChallengeWindow(roomCode, turn, clientsByPlayer);

      const nextTurn = await waitForGameState(players[0]!.client, (state) => state.phase === 'TURN' && state.freeChallenge === null);
      expect(nextTurn.turnPlayerId).not.toBe(challengedId);
      const nextTurnClient = clientsByPlayer.get(nextTurn.turnPlayerId ?? '');
      if (!nextTurnClient) throw new Error('Missing next turn client');

      const staleChallenge = await emitAck<GameView>(nextTurnClient, 'game:challenge', { roomCode, requestId: randomUUID() });
      expect(staleChallenge).toMatchObject({ ok: false, error: { code: 'CHALLENGE_WINDOW_CLOSED' } });
    } finally {
      clients.forEach((client) => client.disconnect());
      clients.length = 0;
      await app.close();
    }
  });

  it('rejects the Free Challenge play owner challenging themself', async () => {
    const { app, url } = await startSocketApp();
    try {
      const { roomCode, clientsByPlayer, turn } = await createStartedSocketGame(url, 3, 'FREE_CHALLENGE');
      const { client: playOwnerClient } = await playOneCardIntoChallengeWindow(roomCode, turn, clientsByPlayer);

      const selfChallenge = await emitAck<GameView>(playOwnerClient, 'game:challenge', { roomCode, requestId: randomUUID() });

      expect(selfChallenge).toMatchObject({ ok: false, error: { code: 'CANNOT_CHALLENGE_SELF' } });
    } finally {
      clients.forEach((client) => client.disconnect());
      clients.length = 0;
      await app.close();
    }
  });

  it('rejects an eliminated player trying to take a later Free Challenge window', async () => {
    const { app, url } = await startSocketApp(zeroRandom);
    try {
      const { roomCode, players, clientsByPlayer, turn } = await createStartedSocketGame(url, 3, 'FREE_CHALLENGE');
      const { playerId: challengedId } = await playOneCardIntoChallengeWindow(roomCode, turn, clientsByPlayer);
      const firstChallenger = players.find(({ membership }) => membership.playerId !== challengedId);
      if (!firstChallenger) throw new Error('Missing first challenger');
      const challenged = await emitAck<GameView>(firstChallenger.client, 'game:challenge', { roomCode, requestId: randomUUID() });
      expect(challenged.ok).toBe(true);

      const punished = await waitForGameState(players[0]!.client, (state) => state.phase === 'PUNISHMENT_RESULT' && state.punishment?.eliminatedPlayerId !== null, 12_000);
      const eliminatedPlayerId = punished.punishment?.eliminatedPlayerId;
      if (!eliminatedPlayerId) throw new Error('Missing eliminated player');
      const eliminatedClient = clientsByPlayer.get(eliminatedPlayerId);
      if (!eliminatedClient) throw new Error('Missing eliminated client');

      const nextTurn = await waitForGameState(players[0]!.client, (state) => state.phase === 'TURN' && !state.alivePlayerIds.includes(eliminatedPlayerId), 8_000);
      await playOneCardIntoChallengeWindow(roomCode, nextTurn, clientsByPlayer);

      const eliminatedChallenge = await emitAck<GameView>(eliminatedClient, 'game:challenge', { roomCode, requestId: randomUUID() });
      expect(eliminatedChallenge).toMatchObject({ ok: false, error: { code: 'PLAYER_ELIMINATED' } });
    } finally {
      clients.forEach((client) => client.disconnect());
      clients.length = 0;
      await app.close();
    }
  }, 25_000);

  it('does not reset the Free Challenge window when a player reconnects', async () => {
    const { app, url } = await startSocketApp();
    try {
      const { roomCode, players, clientsByPlayer, turn } = await createStartedSocketGame(url, 4, 'FREE_CHALLENGE');
      const { windowState, playerId: challengedId } = await playOneCardIntoChallengeWindow(roomCode, turn, clientsByPlayer);
      const reconnecting = players.find(({ membership }) => membership.playerId !== challengedId);
      if (!reconnecting) throw new Error('Missing reconnecting challenger');
      const originalEndsAt = windowState.freeChallenge?.endsAt;
      if (!originalEndsAt || !windowState.phaseEndsAt) throw new Error('Missing challenge deadline');

      reconnecting.client.disconnect();
      await wait(80);
      const restored = await connect(url);
      const resumed = await emitAck<SessionResumeResult>(restored, 'session:resume', { sessionToken: reconnecting.membership.sessionToken });
      expect(resumed.ok).toBe(true);
      if (!resumed.ok) throw new Error(resumed.error.message);
      expect(resumed.data.game).toMatchObject({
        phase: 'CHALLENGE_WINDOW',
        phaseEndsAt: windowState.phaseEndsAt,
        freeChallenge: { endsAt: originalEndsAt, challengerId: null },
      });

      const challenge = await emitAck<GameView>(restored, 'game:challenge', { roomCode, requestId: randomUUID() });
      expect(challenge).toMatchObject({ ok: true, data: { phase: 'CHALLENGE_CALLOUT', challenge: { challengerId: reconnecting.membership.playerId, challengedId } } });
    } finally {
      clients.forEach((client) => client.disconnect());
      clients.length = 0;
      await app.close();
    }
  });
});
