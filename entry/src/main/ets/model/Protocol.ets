// 事件协议定义 - 对应 shared/protocol/index.ts
// ArkTS 不支持 Zod，使用手动验证

import {
  Ack, RoomMembership, RoomView, GameView, GameSnapshot, GameCue,
  RoomPlayerEvent, SessionResumeResult, CharacterId, EmoteId, ItemId,
  GameMode, V6GameMode
} from './GameTypes'
import {
  ROOM_CODE_LENGTH, ROOM_CODE_ALPHABET, MIN_NICKNAME_LENGTH,
  MAX_NICKNAME_LENGTH, MAX_PLAYERS, MIN_PLAYERS, MAX_CARDS_PER_PLAY
} from './Constants'

// ====== 输入验证函数 ======

export function validateNickname(nickname: string): boolean {
  const trimmed = nickname.trim()
  return trimmed.length >= MIN_NICKNAME_LENGTH && trimmed.length <= MAX_NICKNAME_LENGTH
}

export function validateRoomCode(code: string): boolean {
  const trimmed = code.trim().toUpperCase()
  if (trimmed.length !== ROOM_CODE_LENGTH) return false
  for (const ch of trimmed) {
    if (!ROOM_CODE_ALPHABET.includes(ch)) return false
  }
  return true
}

export function validateCardIndexes(indexes: number[]): boolean {
  if (indexes.length < 1 || indexes.length > MAX_CARDS_PER_PLAY) return false
  const set = new Set<number>(indexes)
  return set.size === indexes.length
}

// ====== 客户端 -> 服务端事件 payload 类型 ======

export class CreateRoomPayload {
  nickname: string = ''
}

export class JoinRoomPayload {
  nickname: string = ''
  roomCode: string = ''
}

export class LeaveRoomPayload {
  roomCode: string = ''
}

export class ReadyRoomPayload {
  roomCode: string = ''
  ready: boolean = false
  requestId: string = ''
}

export class UpdateRoomSettingsPayload {
  roomCode: string = ''
  maxPlayers: number = 8
  gameMode: V6GameMode = 'CLASSIC'
  turnDurationSeconds: number | null = null
  eventEnabled: boolean | null = null
  bulletCount: number | null = null
  requestId: string = ''
}

export class KickPlayerPayload {
  roomCode: string = ''
  targetPlayerId: string = ''
  requestId: string = ''
}

export class StartGamePayload {
  roomCode: string = ''
  requestId: string = ''
}

export class PlayCardsPayload {
  roomCode: string = ''
  cardIndexes: number[] = []
  requestId: string = ''
}

export class ChallengePayload {
  roomCode: string = ''
  requestId: string = ''
}

export class RestartGamePayload {
  roomCode: string = ''
  requestId: string = ''
}

export class ReturnToRoomPayload {
  roomCode: string = ''
  requestId: string = ''
}

export class ResumeSessionPayload {
  sessionToken: string = ''
}

export class SelectCharacterPayload {
  roomCode: string = ''
  characterId: CharacterId = 'WOLF'
}

export class SendEmotePayload {
  roomCode: string = ''
  emoteId: EmoteId = 'CHEER'
}

export class UseItemPayload {
  roomCode: string = ''
  itemId: ItemId = 'SPYGLASS'
  requestId: string = ''
}

// ====== 服务端 -> 客户端事件数据类型 ======

export class CardsPlayedEvent {
  playerId: string = ''
  count: number = 0
  roundNumber: number = 0
}

export class ChallengeStartedEvent {
  challengerId: string = ''
  challengedPlayerId: string = ''
}

export class PunishmentStartedEvent {
  playerId: string = ''
  chamber: number = 0
}

export class PlayerEliminatedEvent {
  playerId: string = ''
}

export class EmoteEvent {
  playerId: string = ''
  emoteId: EmoteId = 'CHEER'
}

// ====== 事件名称常量 ======

// 客户端 -> 服务端
export const CLIENT_EVENTS = {
  ROOM_CREATE: 'room:create',
  ROOM_JOIN: 'room:join',
  ROOM_LEAVE: 'room:leave',
  ROOM_READY: 'room:ready',
  ROOM_UPDATE_SETTINGS: 'room:updateSettings',
  ROOM_KICK: 'room:kick',
  ROOM_SELECT_CHARACTER: 'room:selectCharacter',
  GAME_START: 'game:start',
  GAME_PLAY_CARDS: 'game:playCards',
  GAME_CHALLENGE: 'game:challenge',
  GAME_RESTART: 'game:restart',
  GAME_RETURN_TO_ROOM: 'game:returnToRoom',
  GAME_SEND_EMOTE: 'game:sendEmote',
  GAME_USE_ITEM: 'game:useItem',
  SESSION_RESUME: 'session:resume',
} as const

// 服务端 -> 客户端
export const SERVER_EVENTS = {
  ROOM_STATE: 'room:state',
  ROOM_CLOSED: 'room:closed',
  ROOM_PLAYER_JOINED: 'room:playerJoined',
  ROOM_PLAYER_LEFT: 'room:playerLeft',
  ROOM_KICKED: 'room:kicked',
  SESSION_REPLACED: 'session:replaced',
  GAME_SNAPSHOT: 'game:snapshot',
  GAME_CUE: 'game:cue',
  GAME_STATE: 'game:state',
  GAME_TURN_STARTED: 'game:turnStarted',
  GAME_CARDS_PLAYED: 'game:cardsPlayed',
  GAME_CHALLENGE_STARTED: 'game:challengeStarted',
  GAME_CHALLENGE_RESULT: 'game:challengeResult',
  GAME_PUNISHMENT_STARTED: 'game:punishmentStarted',
  GAME_PUNISHMENT_RESULT: 'game:punishmentResult',
  GAME_PLAYER_ELIMINATED: 'game:playerEliminated',
  GAME_OVER: 'game:over',
  GAME_EMOTE: 'game:emote',
} as const
