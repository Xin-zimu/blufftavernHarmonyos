import { randomBytes, randomUUID } from 'node:crypto';
import { DEFAULT_V7_EXTENSION_SETTINGS, MAX_PLAYERS, MIN_PLAYERS, type CharacterId, type PlayerView, type RoomMembership, type RoomSettings, type RoomView } from '@bluff-tavern/shared';
import { createRoomCode, type RandomIndex } from './room-code.js';

interface InternalPlayer extends PlayerView { socketId: string; sessionToken: string }
interface InternalRoom extends Omit<RoomView, 'players'> { players: InternalPlayer[] }
export interface Departure { code: string; player: PlayerView; room: RoomView | null }
export interface KickResult { room: RoomView; kickedPlayer: PlayerView; kickedSocketId: string }
export interface RoomReconnect extends RoomMembership { previousSocketId: string | null }

export class RoomError extends Error {
  constructor(public readonly code: string, message: string) { super(message); }
}

export class RoomStore {
  private readonly rooms = new Map<string, InternalRoom>();
  constructor(private readonly randomIndex?: RandomIndex) {}

  create(nickname: string, socketId: string): RoomMembership {
    const code = this.generateUniqueCode();
    const player = this.makePlayer(nickname, socketId);
    const now = Date.now();
    this.rooms.set(code, {
      id: randomUUID(), code, hostPlayerId: player.id, status: 'LOBBY', maxPlayers: MAX_PLAYERS,
      settings: { maxPlayers: MAX_PLAYERS, gameMode: 'CLASSIC', turnDurationSeconds: 15, eventEnabled: false, bulletCount: null, v7: { ...DEFAULT_V7_EXTENSION_SETTINGS } }, players: [player], createdAt: now,
    });
    return { room: this.getView(code), playerId: player.id, sessionToken: player.sessionToken };
  }

  join(code: string, nickname: string, socketId: string): RoomMembership {
    const room = this.requireRoom(code);
    if (room.status !== 'LOBBY') throw new RoomError('ROOM_NOT_JOINABLE', '牌局已经开始');
    if (room.players.length >= room.maxPlayers) throw new RoomError('ROOM_FULL', '房间已满');
    if (room.players.some((player) => player.nickname.toLocaleLowerCase() === nickname.toLocaleLowerCase())) {
      throw new RoomError('NICKNAME_TAKEN', '该昵称已在房间中使用');
    }
    const player = this.makePlayer(nickname, socketId);
    room.players.push(player);
    return { room: this.getView(code), playerId: player.id, sessionToken: player.sessionToken };
  }

  setReady(code: string, playerId: string, ready: boolean): RoomView {
    const room = this.requireMember(code, playerId);
    if (room.status !== 'LOBBY') throw new RoomError('ROOM_NOT_READYABLE', '当前房间无法准备');
    const player = room.players.find((candidate) => candidate.id === playerId)!;
    player.status = ready ? 'READY' : 'CONNECTED';
    return this.getView(code);
  }

  selectCharacter(code: string, playerId: string, characterId: CharacterId): RoomView {
    const room = this.requireMember(code, playerId);
    if (room.status !== 'LOBBY') throw new RoomError('ROOM_NOT_CONFIGURABLE', '牌局已经开始');
    if (room.players.some((player) => player.id !== playerId && player.characterId === characterId)) throw new RoomError('CHARACTER_TAKEN', '该角色已被其他玩家选择');
    room.players.find((player) => player.id === playerId)!.characterId = characterId;
    return this.getView(code);
  }

  updateSettings(code: string, hostPlayerId: string, settings: RoomSettings): RoomView {
    const room = this.requireMember(code, hostPlayerId);
    this.requireHost(room, hostPlayerId);
    if (room.status !== 'LOBBY') throw new RoomError('ROOM_NOT_CONFIGURABLE', '牌局已经开始');
    if (settings.maxPlayers < room.players.length) throw new RoomError('MAX_PLAYERS_TOO_LOW', '最大人数不能小于当前玩家数');
    room.settings = { ...settings, v7: { ...settings.v7 } };
    room.maxPlayers = settings.maxPlayers;
    room.players.forEach((player) => { player.status = 'CONNECTED'; });
    return this.getView(code);
  }

  kick(code: string, hostPlayerId: string, targetPlayerId: string): KickResult {
    const room = this.requireMember(code, hostPlayerId);
    this.requireHost(room, hostPlayerId);
    if (room.status !== 'LOBBY') throw new RoomError('ROOM_NOT_CONFIGURABLE', '牌局已经开始');
    if (targetPlayerId === hostPlayerId) throw new RoomError('CANNOT_KICK_HOST', '房主不能踢出自己');
    const index = room.players.findIndex((player) => player.id === targetPlayerId);
    if (index < 0) throw new RoomError('PLAYER_NOT_FOUND', '玩家不在房间中');
    const kicked = room.players[index]!;
    room.players.splice(index, 1);
    return { room: this.getView(code), kickedPlayer: this.toPlayerView(kicked), kickedSocketId: kicked.socketId };
  }

  startGame(code: string, hostPlayerId: string): RoomView {
    const room = this.requireMember(code, hostPlayerId);
    this.requireHost(room, hostPlayerId);
    if (room.status !== 'LOBBY') throw new RoomError('GAME_ALREADY_STARTED', '牌局已经开始');
    if (room.players.length < MIN_PLAYERS) throw new RoomError('NOT_ENOUGH_PLAYERS', '至少需要两名玩家');
    if (!room.players.every((player) => player.status === 'READY')) throw new RoomError('PLAYERS_NOT_READY', '所有玩家准备后才能开始');
    room.status = 'PLAYING';
    room.players.forEach((player) => { player.status = 'PLAYING'; });
    return this.getView(code);
  }

  eliminatePlayer(code: string, playerId: string): RoomView {
    const room = this.requireMember(code, playerId);
    const player = room.players.find((candidate) => candidate.id === playerId)!;
    player.status = 'ELIMINATED';
    return this.getView(code);
  }

  finishGame(code: string): RoomView {
    const room = this.requireRoom(code);
    room.status = 'GAME_OVER';
    return this.getView(code);
  }

  restartGame(code: string, hostPlayerId: string): RoomView {
    const room = this.requireMember(code, hostPlayerId);
    this.requireHost(room, hostPlayerId);
    if (room.status !== 'GAME_OVER') throw new RoomError('GAME_NOT_OVER', '当前牌局尚未结束');
    room.status = 'PLAYING';
    room.players.forEach((player) => { player.status = 'PLAYING'; });
    return this.getView(code);
  }

  returnToLobby(code: string, playerId: string): RoomView {
    const room = this.requireMember(code, playerId);
    if (room.status !== 'GAME_OVER') throw new RoomError('GAME_NOT_OVER', '当前牌局尚未结束');
    room.status = 'LOBBY';
    room.players.forEach((player) => {
      player.status = player.isConnected ? 'CONNECTED' : 'DISCONNECTED';
    });
    if (!room.players.some((player) => player.id === room.hostPlayerId && player.isConnected)) {
      const nextHost = room.players.find((player) => player.isConnected) ?? room.players[0];
      if (nextHost) room.hostPlayerId = nextHost.id;
    }
    return this.getView(code);
  }

  disconnect(socketId: string): Departure | null {
    for (const [code, room] of this.rooms) {
      const player = room.players.find((candidate) => candidate.socketId === socketId);
      if (!player) continue;
      // A completed game must remain resumable too: its host may need to restart it.
      // Lobby departures still free their seats immediately.
      if (room.status === 'LOBBY') return this.leaveBySocket(socketId);
      player.isConnected = false;
      return { code, player: this.toPlayerView(player), room: this.getView(code) };
    }
    return null;
  }

  resume(sessionToken: string, socketId: string): RoomReconnect {
    for (const [code, room] of this.rooms) {
      const player = room.players.find((candidate) => candidate.sessionToken === sessionToken);
      if (!player) continue;
      const previousSocketId = player.socketId !== socketId ? player.socketId : null;
      player.socketId = socketId;
      player.isConnected = true;
      return { room: this.getView(code), playerId: player.id, sessionToken: player.sessionToken, previousSocketId };
    }
    throw new RoomError('SESSION_NOT_FOUND', '无法恢复会话');
  }

  leaveBySocket(socketId: string): Departure | null {
    for (const [code, room] of this.rooms) {
      const index = room.players.findIndex((player) => player.socketId === socketId);
      if (index < 0) continue;
      const departed = room.players[index]!;
      if (room.status === 'PLAYING' || room.status === 'ROUND_RESULT') {
        departed.isConnected = false;
        departed.status = 'DISCONNECTED';
        departed.socketId = '';
        if (room.hostPlayerId === departed.id) this.transferHost(room);
        return { code, player: this.toPlayerView(departed), room: this.getView(code) };
      }
      room.players.splice(index, 1);
      if (room.players.length === 0) {
        this.rooms.delete(code);
        return { code, player: this.toPlayerView(departed), room: null };
      }
      if (room.hostPlayerId === departed.id || !room.players.some((p) => p.id === room.hostPlayerId)) this.transferHost(room);
      return { code, player: this.toPlayerView(departed), room: this.getView(code) };
    }
    return null;
  }

  has(code: string): boolean { return this.rooms.has(code); }

  getStats(): { rooms: number; connections: number; players: number } {
    let connections = 0;
    let players = 0;
    for (const room of this.rooms.values()) {
      players += room.players.length;
      connections += room.players.filter((player) => player.isConnected).length;
    }
    return { rooms: this.rooms.size, connections, players };
  }

  getSocketId(code: string, playerId: string): string | null {
    return this.rooms.get(code)?.players.find((player) => player.id === playerId)?.socketId ?? null;
  }

  isCurrentSocket(code: string, playerId: string, socketId: string): boolean {
    return this.getSocketId(code, playerId) === socketId;
  }

  getView(code: string): RoomView {
    const room = this.requireRoom(code);
    return {
      id: room.id, code: room.code, hostPlayerId: room.hostPlayerId, status: room.status,
      maxPlayers: room.maxPlayers, createdAt: room.createdAt,
      settings: { ...room.settings, v7: { ...room.settings.v7 } },
      players: room.players.map((player) => this.toPlayerView(player)),
    };
  }

  private requireRoom(code: string): InternalRoom {
    const room = this.rooms.get(code);
    if (!room) throw new RoomError('ROOM_NOT_FOUND', '房间不存在');
    return room;
  }

  private requireMember(code: string, playerId: string): InternalRoom {
    const room = this.requireRoom(code);
    if (!room.players.some((player) => player.id === playerId)) throw new RoomError('NOT_IN_ROOM', '你不在这个房间中');
    return room;
  }

  private requireHost(room: InternalRoom, playerId: string): void {
    if (room.hostPlayerId !== playerId) throw new RoomError('NOT_HOST', '你不是房主');
  }

  private transferHost(room: InternalRoom): void {
    const nextHost = room.players.find((player) => player.isConnected) ?? room.players[0];
    if (nextHost) room.hostPlayerId = nextHost.id;
  }

  private toPlayerView(player: InternalPlayer): PlayerView {
    return { id: player.id, nickname: player.nickname, status: player.status, joinedAt: player.joinedAt, isConnected: player.isConnected, characterId: player.characterId };
  }

  private makePlayer(nickname: string, socketId: string): InternalPlayer {
    return { id: randomUUID(), nickname, socketId, sessionToken: randomBytes(32).toString('base64url'), status: 'CONNECTED', joinedAt: Date.now(), isConnected: true, characterId: null };
  }

  private generateUniqueCode(): string {
    for (let attempt = 0; attempt < 100; attempt += 1) {
      const code = createRoomCode(this.randomIndex);
      if (!this.rooms.has(code)) return code;
    }
    throw new RoomError('CODE_EXHAUSTED', '暂时无法创建房间，请稍后再试');
  }
}
