// Transport-agnostic command dispatcher: schema validation, identity checks,
// business invocation, request idempotency, ack error conversion, state
// publishing and scheduler wiring. Socket.IO and the raw-WS gateway are thin
// adapters that feed commands into this class.

import {
  challengeSchema,
  createRoomSchema,
  joinRoomSchema,
  kickPlayerSchema,
  leaveRoomSchema,
  playCardsSchema,
  readyRoomSchema,
  restartGameSchema,
  resumeSessionSchema,
  returnToRoomSchema,
  selectCharacterSchema,
  sendEmoteSchema,
  startGameSchema,
  updateRoomSettingsSchema,
  useItemSchema,
  type Ack,
  type GameCue,
  type GameView,
  type RoomView,
  type SessionResumeResult,
} from '@bluff-tavern/shared';
import type { GameScheduler } from '../game/game-scheduler.js';
import type { GameService } from '../game/game-service.js';
import { RoomError, type RoomStore } from '../rooms/room-store.js';
import type { ConnectionIdentity, ConnectionRegistry } from './connection-registry.js';
import type { RealtimePublisher } from './realtime-publisher.js';

export interface CommandContext {
  readonly connectionId: string;
  sendAck(result: Ack<unknown>): void;
  close(): void;
}

export interface DispatcherLogger {
  info: (data: object) => void;
  error: (data: object) => void;
}

export interface RateLimitPolicy {
  windowMs: number;
  maxCommands: number;
}

const BUSINESS_EVENTS: ReadonlySet<string> = new Set([
  'room:create',
  'room:join',
  'room:leave',
  'room:ready',
  'room:updateSettings',
  'room:kick',
  'room:selectCharacter',
  'game:start',
  'game:playCards',
  'game:challenge',
  'game:restart',
  'game:returnToRoom',
  'game:sendEmote',
  'game:useItem',
  'session:resume',
]);

const DEFAULT_RATE_LIMIT: RateLimitPolicy = { windowMs: 10_000, maxCommands: 50 };

const invalid = { ok: false as const, error: { code: 'INVALID_REQUEST', message: '输入内容无效' } };
const notAuthenticated = { ok: false as const, error: { code: 'NOT_AUTHENTICATED', message: '请先加入房间或恢复会话' } };
const rateLimited = { ok: false as const, error: { code: 'RATE_LIMITED', message: '请求过于频繁，请稍后再试' } };

function failure(error: unknown): Ack<never> {
  return error instanceof RoomError
    ? { ok: false as const, error: { code: error.code, message: error.message } }
    : { ok: false as const, error: { code: 'SERVER_ERROR', message: '服务器暂时不可用' } };
}

interface RateWindow {
  startedAt: number;
  commands: number;
}

type V7SettingsPatch = {
  [Key in keyof RoomView['settings']['v7']]?: RoomView['settings']['v7'][Key] | undefined;
};

export class CommandDispatcher {
  private readonly processedRoomRequests = new Map<string, Ack<RoomView>>();
  private readonly processedGameRequests = new Map<string, Ack<GameView>>();
  private readonly rateWindows = new Map<string, RateWindow>();

  constructor(
    private readonly rooms: RoomStore,
    private readonly games: GameService,
    private readonly scheduler: GameScheduler,
    private readonly registry: ConnectionRegistry,
    private readonly publisher: RealtimePublisher,
    private readonly logger: DispatcherLogger,
    private readonly rateLimit: RateLimitPolicy = DEFAULT_RATE_LIMIT,
  ) {}

  isBusinessEvent(event: string): boolean {
    return BUSINESS_EVENTS.has(event);
  }

  handleCommand(ctx: CommandContext, event: string, payload: unknown): void {
    if (!this.allowCommand(ctx.connectionId)) {
      ctx.sendAck(rateLimited);
      ctx.close();
      return;
    }
    switch (event) {
      case 'room:create': return this.createRoom(ctx, payload);
      case 'room:join': return this.joinRoom(ctx, payload);
      case 'room:leave': return this.leaveRoom(ctx, payload);
      case 'room:ready': return this.setReady(ctx, payload);
      case 'room:updateSettings': return this.updateSettings(ctx, payload);
      case 'room:kick': return this.kickPlayer(ctx, payload);
      case 'room:selectCharacter': return this.selectCharacter(ctx, payload);
      case 'game:start': return this.startGame(ctx, payload);
      case 'game:playCards': return this.playCards(ctx, payload);
      case 'game:challenge': return this.challenge(ctx, payload);
      case 'game:restart': return this.restartGame(ctx, payload);
      case 'game:returnToRoom': return this.returnToRoom(ctx, payload);
      case 'game:sendEmote': return this.sendEmote(ctx, payload);
      case 'game:useItem': return this.useItem(ctx, payload);
      case 'session:resume': return this.resumeSession(ctx, payload);
      default: ctx.sendAck(invalid);
    }
  }

  handleDisconnect(connectionId: string): void {
    this.rateWindows.delete(connectionId);
    this.disconnectCurrent(connectionId);
  }

  // ====== command handlers ======

  private createRoom(ctx: CommandContext, payload: unknown): void {
    const parsed = createRoomSchema.safeParse(payload);
    if (!parsed.success) return ctx.sendAck(invalid);
    this.leaveCurrent(ctx.connectionId);
    try {
      const result = this.rooms.create(parsed.data.nickname, ctx.connectionId);
      this.bindIdentity(ctx.connectionId, { playerId: result.playerId, roomCode: result.room.code });
      this.logger.info({ event: 'room_created', roomCode: result.room.code, playerId: result.playerId });
      ctx.sendAck({ ok: true, data: result });
    } catch (error) {
      this.logger.error({ event: 'server_error', error });
      ctx.sendAck(failure(error));
    }
  }

  private joinRoom(ctx: CommandContext, payload: unknown): void {
    const parsed = joinRoomSchema.safeParse(payload);
    if (!parsed.success) return ctx.sendAck(invalid);
    this.leaveCurrent(ctx.connectionId);
    try {
      const result = this.rooms.join(parsed.data.roomCode, parsed.data.nickname, ctx.connectionId);
      this.bindIdentity(ctx.connectionId, { playerId: result.playerId, roomCode: result.room.code });
      this.logger.info({ event: 'room_joined', roomCode: result.room.code, playerId: result.playerId });
      ctx.sendAck({ ok: true, data: result });
      this.publisher.broadcastToRoom(result.room.code, 'room:playerJoined', {
        roomCode: result.room.code,
        player: result.room.players.find((player) => player.id === result.playerId)!,
      });
      this.publisher.broadcastToRoom(result.room.code, 'room:state', result.room);
    } catch (error) {
      ctx.sendAck(failure(error));
    }
  }

  private leaveRoom(ctx: CommandContext, payload: unknown): void {
    const identity = this.identity(ctx.connectionId);
    if (!identity.playerId) return ctx.sendAck(notAuthenticated);
    const parsed = leaveRoomSchema.safeParse(payload);
    if (!parsed.success || identity.roomCode !== parsed.data.roomCode) return ctx.sendAck(invalid);
    this.leaveCurrent(ctx.connectionId);
    ctx.sendAck({ ok: true, data: null });
  }

  private setReady(ctx: CommandContext, payload: unknown): void {
    const identity = this.identity(ctx.connectionId);
    if (!identity.playerId) return ctx.sendAck(notAuthenticated);
    const parsed = readyRoomSchema.safeParse(payload);
    if (!parsed.success || !this.isCurrentMember(ctx.connectionId, identity, parsed.data.roomCode)) return ctx.sendAck(invalid);
    const requestKey = roomRequestKey(parsed.data.roomCode, identity.playerId, parsed.data.requestId);
    const cached = this.processedRoomRequests.get(requestKey);
    if (cached) return ctx.sendAck(cached);
    try {
      const room = this.rooms.setReady(parsed.data.roomCode, identity.playerId, parsed.data.ready);
      const result: Ack<RoomView> = { ok: true, data: room };
      this.processedRoomRequests.set(requestKey, result);
      this.publisher.broadcastToRoom(room.code, 'room:state', room);
      ctx.sendAck(result);
    } catch (error) {
      const result = failure(error);
      this.processedRoomRequests.set(requestKey, result);
      ctx.sendAck(result);
    }
  }

  private selectCharacter(ctx: CommandContext, payload: unknown): void {
    const identity = this.identity(ctx.connectionId);
    if (!identity.playerId) return ctx.sendAck(notAuthenticated);
    const parsed = selectCharacterSchema.safeParse(payload);
    if (!parsed.success || !this.isCurrentMember(ctx.connectionId, identity, parsed.data.roomCode)) return ctx.sendAck(invalid);
    try {
      const room = this.rooms.selectCharacter(parsed.data.roomCode, identity.playerId, parsed.data.characterId);
      this.publisher.broadcastToRoom(room.code, 'room:state', room);
      ctx.sendAck({ ok: true, data: room });
    } catch (error) {
      ctx.sendAck(failure(error));
    }
  }

  private sendEmote(ctx: CommandContext, payload: unknown): void {
    const identity = this.identity(ctx.connectionId);
    if (!identity.playerId) return ctx.sendAck(notAuthenticated);
    const parsed = sendEmoteSchema.safeParse(payload);
    if (!parsed.success || !this.isCurrentMember(ctx.connectionId, identity, parsed.data.roomCode)) return ctx.sendAck(invalid);
    this.publisher.broadcastToRoom(parsed.data.roomCode, 'game:emote', { playerId: identity.playerId, emoteId: parsed.data.emoteId });
    ctx.sendAck({ ok: true, data: null });
  }

  private useItem(ctx: CommandContext, payload: unknown): void {
    const identity = this.identity(ctx.connectionId);
    if (!identity.playerId) return ctx.sendAck(notAuthenticated);
    const parsed = useItemSchema.safeParse(payload);
    if (!parsed.success || !this.isCurrentMember(ctx.connectionId, identity, parsed.data.roomCode)) return ctx.sendAck(invalid);
    const key = gameRequestKey(parsed.data.roomCode, identity.playerId, parsed.data.requestId);
    const cached = this.processedGameRequests.get(key);
    if (cached) return ctx.sendAck(cached);
    try {
      const state = this.games.useItem(parsed.data.roomCode, identity.playerId, parsed.data.itemId);
      const result: Ack<GameView> = { ok: true, data: state };
      this.processedGameRequests.set(key, result);
      this.logger.info({ event: 'item_used', roomCode: parsed.data.roomCode, playerId: identity.playerId, itemId: parsed.data.itemId });
      this.broadcastGameSnapshots(parsed.data.roomCode);
      this.scheduleGame(parsed.data.roomCode);
      ctx.sendAck(result);
    } catch (error) {
      const result = failure(error);
      this.processedGameRequests.set(key, result);
      ctx.sendAck(result);
    }
  }

  private updateSettings(ctx: CommandContext, payload: unknown): void {
    const identity = this.identity(ctx.connectionId);
    if (!identity.playerId) return ctx.sendAck(notAuthenticated);
    const parsed = updateRoomSettingsSchema.safeParse(payload);
    if (!parsed.success || !this.isCurrentMember(ctx.connectionId, identity, parsed.data.roomCode)) return ctx.sendAck(invalid);
    const requestKey = roomRequestKey(parsed.data.roomCode, identity.playerId, parsed.data.requestId);
    const cached = this.processedRoomRequests.get(requestKey);
    if (cached) return ctx.sendAck(cached);
    try {
      const previous = this.rooms.getView(parsed.data.roomCode);
      const room = this.rooms.updateSettings(parsed.data.roomCode, identity.playerId, {
        maxPlayers: parsed.data.maxPlayers,
        gameMode: parsed.data.gameMode,
        turnDurationSeconds: turnDurationForMode(parsed.data.gameMode, parsed.data.turnDurationSeconds ?? previous.settings.turnDurationSeconds),
        eventEnabled: false,
        bulletCount: null,
        v7: mergeV7Settings(previous.settings.v7, parsed.data.v7, parsed.data.gameMode),
      });
      const result: Ack<RoomView> = { ok: true, data: room };
      this.processedRoomRequests.set(requestKey, result);
      this.logger.info({ event: 'room_settings_updated', roomCode: room.code, playerId: identity.playerId });
      this.publisher.broadcastToRoom(room.code, 'room:state', room);
      ctx.sendAck(result);
    } catch (error) {
      const result = failure(error);
      this.processedRoomRequests.set(requestKey, result);
      ctx.sendAck(result);
    }
  }

  private kickPlayer(ctx: CommandContext, payload: unknown): void {
    const identity = this.identity(ctx.connectionId);
    if (!identity.playerId) return ctx.sendAck(notAuthenticated);
    const parsed = kickPlayerSchema.safeParse(payload);
    if (!parsed.success || !this.isCurrentMember(ctx.connectionId, identity, parsed.data.roomCode)) return ctx.sendAck(invalid);
    const requestKey = roomRequestKey(parsed.data.roomCode, identity.playerId, parsed.data.requestId);
    const cached = this.processedRoomRequests.get(requestKey);
    if (cached) return ctx.sendAck(cached);
    try {
      const result = this.rooms.kick(parsed.data.roomCode, identity.playerId, parsed.data.targetPlayerId);
      const ackResult: Ack<RoomView> = { ok: true, data: result.room };
      this.processedRoomRequests.set(requestKey, ackResult);
      this.detachConnection(result.kickedSocketId, 'room:kicked', '你已被房主移出房间');
      this.logger.info({ event: 'room_player_kicked', roomCode: result.room.code, playerId: result.kickedPlayer.id });
      this.publisher.broadcastToRoom(result.room.code, 'room:playerLeft', { roomCode: result.room.code, player: result.kickedPlayer });
      this.publisher.broadcastToRoom(result.room.code, 'room:state', result.room);
      ctx.sendAck(ackResult);
    } catch (error) {
      const result = failure(error);
      this.processedRoomRequests.set(requestKey, result);
      ctx.sendAck(result);
    }
  }

  private startGame(ctx: CommandContext, payload: unknown): void {
    const identity = this.identity(ctx.connectionId);
    if (!identity.playerId) return ctx.sendAck(notAuthenticated);
    const parsed = startGameSchema.safeParse(payload);
    if (!parsed.success || !this.isCurrentMember(ctx.connectionId, identity, parsed.data.roomCode)) return ctx.sendAck(invalid);
    const key = gameRequestKey(parsed.data.roomCode, identity.playerId, parsed.data.requestId);
    const cached = this.processedGameRequests.get(key);
    if (cached) return ctx.sendAck(cached);
    try {
      const room = this.rooms.startGame(parsed.data.roomCode, identity.playerId);
      const state = this.games.start(room);
      const result: Ack<GameView> = { ok: true, data: state };
      this.processedGameRequests.set(key, result);
      this.logger.info({ event: 'game_started', roomCode: room.code, playerId: identity.playerId });
      this.publisher.broadcastToRoom(room.code, 'room:state', room);
      this.broadcastGameSnapshots(room.code);
      this.scheduleGame(room.code);
      ctx.sendAck(result);
    } catch (error) {
      const result = failure(error);
      this.processedGameRequests.set(key, result);
      ctx.sendAck(result);
    }
  }

  private playCards(ctx: CommandContext, payload: unknown): void {
    const identity = this.identity(ctx.connectionId);
    if (!identity.playerId) return ctx.sendAck(notAuthenticated);
    const parsed = playCardsSchema.safeParse(payload);
    if (!parsed.success || !this.isCurrentMember(ctx.connectionId, identity, parsed.data.roomCode)) return ctx.sendAck(invalid);
    const key = gameRequestKey(parsed.data.roomCode, identity.playerId, parsed.data.requestId);
    const cached = this.processedGameRequests.get(key);
    if (cached) return ctx.sendAck(cached);
    try {
      const result = this.games.playCards(parsed.data.roomCode, identity.playerId, parsed.data.cardIndexes);
      const ackResult: Ack<GameView> = { ok: true, data: result.state };
      this.processedGameRequests.set(key, ackResult);
      this.logger.info({ event: 'cards_played', roomCode: parsed.data.roomCode, playerId: identity.playerId, count: result.cue.count });
      this.emitCue(result.cue);
      this.publisher.broadcastToRoom(parsed.data.roomCode, 'game:cardsPlayed', {
        playerId: identity.playerId,
        count: result.cue.count ?? 0,
        roundNumber: result.state.roundNumber,
      });
      this.broadcastGameSnapshots(parsed.data.roomCode);
      this.scheduleGame(parsed.data.roomCode);
      ctx.sendAck(ackResult);
    } catch (error) {
      const result = failure(error);
      this.processedGameRequests.set(key, result);
      ctx.sendAck(result);
    }
  }

  private challenge(ctx: CommandContext, payload: unknown): void {
    const identity = this.identity(ctx.connectionId);
    if (!identity.playerId) return ctx.sendAck(notAuthenticated);
    const parsed = challengeSchema.safeParse(payload);
    if (!parsed.success || !this.isCurrentMember(ctx.connectionId, identity, parsed.data.roomCode)) return ctx.sendAck(invalid);
    const key = gameRequestKey(parsed.data.roomCode, identity.playerId, parsed.data.requestId);
    const cached = this.processedGameRequests.get(key);
    if (cached) return ctx.sendAck(cached);
    try {
      const result = this.games.challenge(parsed.data.roomCode, identity.playerId);
      const ackResult: Ack<GameView> = { ok: true, data: result.state };
      this.processedGameRequests.set(key, ackResult);
      this.logger.info({ event: 'challenge_called', roomCode: parsed.data.roomCode, challengerId: identity.playerId, challengedPlayerId: result.state.challenge?.challengedId });
      this.emitCue(result.cue);
      if (result.state.challenge) {
        this.publisher.broadcastToRoom(parsed.data.roomCode, 'game:challengeStarted', {
          challengerId: result.state.challenge.challengerId,
          challengedPlayerId: result.state.challenge.challengedId,
        });
      }
      this.broadcastGameSnapshots(parsed.data.roomCode);
      this.scheduleGame(parsed.data.roomCode);
      ctx.sendAck(ackResult);
    } catch (error) {
      const result = failure(error);
      this.processedGameRequests.set(key, result);
      ctx.sendAck(result);
    }
  }

  private restartGame(ctx: CommandContext, payload: unknown): void {
    const identity = this.identity(ctx.connectionId);
    if (!identity.playerId) return ctx.sendAck(notAuthenticated);
    const parsed = restartGameSchema.safeParse(payload);
    if (!parsed.success || !this.isCurrentMember(ctx.connectionId, identity, parsed.data.roomCode)) return ctx.sendAck(invalid);
    const key = gameRequestKey(parsed.data.roomCode, identity.playerId, parsed.data.requestId);
    const cached = this.processedGameRequests.get(key);
    if (cached) return ctx.sendAck(cached);
    try {
      const room = this.rooms.restartGame(parsed.data.roomCode, identity.playerId);
      const state = this.games.restart(room);
      const result: Ack<GameView> = { ok: true, data: state };
      this.processedGameRequests.set(key, result);
      this.publisher.broadcastToRoom(room.code, 'room:state', room);
      this.broadcastGameSnapshots(room.code);
      this.scheduleGame(room.code);
      ctx.sendAck(result);
    } catch (error) {
      const result = failure(error);
      this.processedGameRequests.set(key, result);
      ctx.sendAck(result);
    }
  }

  private returnToRoom(ctx: CommandContext, payload: unknown): void {
    const identity = this.identity(ctx.connectionId);
    if (!identity.playerId) return ctx.sendAck(notAuthenticated);
    const parsed = returnToRoomSchema.safeParse(payload);
    if (!parsed.success || !this.isCurrentMember(ctx.connectionId, identity, parsed.data.roomCode)) return ctx.sendAck(invalid);
    const key = roomRequestKey(parsed.data.roomCode, identity.playerId, parsed.data.requestId);
    const cached = this.processedRoomRequests.get(key);
    if (cached) return ctx.sendAck(cached);
    try {
      const room = this.rooms.returnToLobby(parsed.data.roomCode, identity.playerId);
      this.games.end(room.code);
      this.scheduler.cancel(room.code);
      const result: Ack<RoomView> = { ok: true, data: room };
      this.processedRoomRequests.set(key, result);
      this.logger.info({ event: 'game_returned_to_room', roomCode: room.code, playerId: identity.playerId });
      this.publisher.broadcastToRoom(room.code, 'room:state', room);
      ctx.sendAck(result);
    } catch (error) {
      const result = failure(error);
      this.processedRoomRequests.set(key, result);
      ctx.sendAck(result);
    }
  }

  private resumeSession(ctx: CommandContext, payload: unknown): void {
    const parsed = resumeSessionSchema.safeParse(payload);
    if (!parsed.success) return ctx.sendAck(invalid);
    try {
      const result = this.rooms.resume(parsed.data.sessionToken, ctx.connectionId);
      if (result.previousSocketId) this.replacePreviousConnection(result.previousSocketId, result.room.code);
      this.bindIdentity(ctx.connectionId, { playerId: result.playerId, roomCode: result.room.code });
      this.games.updateConnections(result.room);
      this.publisher.broadcastToRoom(result.room.code, 'room:state', result.room);
      let game: GameView | null = null;
      try {
        game = this.games.getView(result.room.code, result.playerId);
        this.broadcastGameSnapshots(result.room.code);
      } catch {
        // Lobby has no game state.
      }
      this.logger.info({ event: 'player_reconnected', roomCode: result.room.code, playerId: result.playerId });
      const data: SessionResumeResult = {
        room: result.room,
        playerId: result.playerId,
        sessionToken: result.sessionToken,
        game,
      };
      ctx.sendAck({ ok: true, data });
    } catch (error) {
      ctx.sendAck(failure(error));
    }
  }

  // ====== shared lifecycle helpers ======

  private leaveCurrent(connectionId: string): void {
    const result = this.rooms.leaveBySocket(connectionId);
    if (!result) return;
    this.registry.leaveAllRooms(connectionId);
    this.registry.clearIdentity(connectionId);
    this.logger.info({ event: 'room_left', roomCode: result.code });
    if (result.room) {
      this.publisher.broadcastToRoom(result.code, 'room:playerLeft', { roomCode: result.code, player: result.player });
      this.publisher.broadcastToRoom(result.code, 'room:state', result.room);
    } else {
      this.scheduler.cancel(result.code);
      this.publisher.broadcastToRoom(result.code, 'room:closed', null);
    }
  }

  private disconnectCurrent(connectionId: string): void {
    const result = this.rooms.disconnect(connectionId);
    if (!result) return;
    this.registry.leaveAllRooms(connectionId);
    this.registry.clearIdentity(connectionId);
    this.logger.info({ event: 'player_disconnected', roomCode: result.code, playerId: result.player.id });
    if (result.room) {
      this.games.updateConnections(result.room);
      this.publisher.broadcastToRoom(result.code, 'room:state', result.room);
      try {
        this.broadcastGameSnapshots(result.code);
      } catch {
        // Lobby has no game state.
      }
    }
  }

  private replacePreviousConnection(previousConnectionId: string, roomCode: string): void {
    this.detachConnection(previousConnectionId, 'session:replaced', '你的会话已在新连接中恢复');
  }

  private detachConnection(connectionId: string, event: string, message: string): void {
    const connection = this.registry.get(connectionId);
    if (!connection) return;
    this.registry.leaveAllRooms(connectionId);
    this.registry.clearIdentity(connectionId);
    connection.send(event, message);
  }

  private bindIdentity(connectionId: string, identity: ConnectionIdentity): void {
    this.registry.setIdentity(connectionId, identity);
    if (identity.roomCode) this.registry.joinRoom(connectionId, identity.roomCode);
  }

  private identity(connectionId: string): ConnectionIdentity {
    return this.registry.getIdentity(connectionId);
  }

  private isCurrentMember(connectionId: string, identity: ConnectionIdentity, roomCode: string): boolean {
    return identity.roomCode === roomCode
      && identity.playerId !== undefined
      && this.rooms.isCurrentSocket(roomCode, identity.playerId, connectionId);
  }

  private allowCommand(connectionId: string): boolean {
    const now = Date.now();
    let window = this.rateWindows.get(connectionId);
    if (!window || now - window.startedAt > this.rateLimit.windowMs) {
      window = { startedAt: now, commands: 0 };
      this.rateWindows.set(connectionId, window);
    }
    window.commands += 1;
    return window.commands <= this.rateLimit.maxCommands;
  }

  // ====== shared publishing helpers ======

  // Builds each player's private snapshot (including their hand) and sends it
  // only to that player's connection. Never broadcast a snapshot to a room.
  private broadcastGameSnapshots(roomCode: string): void {
    this.games.updateConnections(this.rooms.getView(roomCode));
    for (const [playerId, state] of this.games.getViews(roomCode)) {
      const socketId = this.rooms.getSocketId(roomCode, playerId);
      if (!socketId) continue;
      this.publisher.sendToConnection(socketId, 'game:snapshot', state);
      this.publisher.sendToConnection(socketId, 'game:state', state);
      if (state.phase === 'TURN') this.publisher.sendToConnection(socketId, 'game:turnStarted', state);
    }
  }

  private scheduleGame(roomCode: string): void {
    let phaseEndsAt: number | null;
    try {
      phaseEndsAt = this.games.getPhaseEndsAt(roomCode);
    } catch {
      return;
    }

    this.scheduler.schedule(roomCode, phaseEndsAt, () => {
      try {
        const result = this.games.advancePhase(roomCode);
        if (result.eliminatedPlayerId) {
          this.publisher.broadcastToRoom(roomCode, 'game:playerEliminated', { playerId: result.eliminatedPlayerId });
        }
        if (result.gameOver) {
          const room = this.rooms.finishGame(roomCode);
          this.publisher.broadcastToRoom(room.code, 'room:state', room);
          this.publisher.broadcastToRoom(room.code, 'game:over', publicGameView(result.state));
        }
        for (const cue of result.cues) this.emitCue(cue);
        if (result.state.phase === 'VERDICT') this.publisher.broadcastToRoom(roomCode, 'game:challengeResult', publicGameView(result.state));
        if (result.state.phase === 'PUNISHMENT_INTRO' && result.state.challenge?.punishedPlayerId) {
          this.publisher.broadcastToRoom(roomCode, 'game:punishmentStarted', { playerId: result.state.challenge.punishedPlayerId, chamber: 0 });
        }
        if (result.state.phase === 'PUNISHMENT_RESULT') this.publisher.broadcastToRoom(roomCode, 'game:punishmentResult', publicGameView(result.state));
        this.broadcastGameSnapshots(roomCode);
        this.scheduleGame(roomCode);
      } catch (error) {
        this.logger.error({ event: 'phase_advance_failed', roomCode, error });
      }
    });
  }

  private emitCue(cue: GameCue): void {
    this.publisher.broadcastToRoom(cue.roomCode, 'game:cue', cue);
  }
}

function roomRequestKey(roomCode: string, playerId: string, requestId: string): string {
  return `${roomCode}:${playerId}:${requestId}`;
}

// Strips viewer-private fields (hand, items and personal effects) from a game
// view before it is broadcast room-wide via presentation events. Private
// snapshots are only ever delivered per-player via game:snapshot/game:state.
function publicGameView(state: GameView): GameView {
  return { ...state, hand: [], items: [], itemEffect: null, abilityEffect: null };
}

function gameRequestKey(roomCode: string, playerId: string, requestId: string): string {
  return `${roomCode}:${playerId}:${requestId}`;
}

function mergeV7Settings(previous: RoomView['settings']['v7'], patch: V7SettingsPatch | undefined, gameMode: RoomView['settings']['gameMode']): RoomView['settings']['v7'] {
  return {
    itemsEnabled: patch?.itemsEnabled ?? previous.itemsEnabled,
    tavernEventsEnabled: supportsLegacyTavernEvents(gameMode) ? patch?.tavernEventsEnabled ?? previous.tavernEventsEnabled : false,
    characterAbilitiesEnabled: patch?.characterAbilitiesEnabled ?? previous.characterAbilitiesEnabled,
  };
}

function supportsLegacyTavernEvents(gameMode: RoomView['settings']['gameMode']): boolean {
  return gameMode === 'CLASSIC' || gameMode === 'QUICK';
}

function turnDurationForMode(gameMode: RoomView['settings']['gameMode'], requestedSeconds: number): number {
  if (gameMode === 'QUICK') return 7;
  return gameMode === 'CUSTOM' ? requestedSeconds : 15;
}
