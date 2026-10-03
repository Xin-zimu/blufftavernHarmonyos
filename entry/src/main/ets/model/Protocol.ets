// 事件协议定义 - 对应 shared/protocol/index.ts
// ArkTS 不支持 Zod，使用手动验证
// ArkTS 不支持 as const，使用普通 const 对象

import {
  RoomMembership, RoomView, GameView, GameSnapshot, GameCue,
  RoomPlayerEvent, SessionResumeResult, CharacterId, EmoteId, ItemId,
  GameMode, V6GameMode, AckResult, AckError
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
  for (const index of indexes) {
    if (!Number.isInteger(index) || index < 0) return false
  }
  const set = new Set<number>(indexes)
  return set.size === indexes.length
}

// 构造失败的 Ack 结果（未连接 / 超时 / 断开等本地错误）
export function makeErrorAck(code: string, message: string): AckResult {
  const ackError: AckError = new AckError()
  ackError.code = code
  ackError.message = message
  const result: AckResult = new AckResult()
  result.ok = false
  result.error = ackError
  return result
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

// 注意：服务端 schema 中 turnDurationSeconds / eventEnabled / bulletCount / v7
// 均为 optional（非 nullable），显式发送 null 会被 zod 拒绝。
// 本客户端仅更新 maxPlayers / gameMode，未设置的可选字段一律不发送。
export class UpdateRoomSettingsPayload {
  roomCode: string = ''
  maxPlayers: number = 8
  gameMode: V6GameMode = 'CLASSIC'
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
// ArkTS 不支持 as const，使用普通 string 属性的 class

// 客户端 -> 服务端
export class ClientEvents {
  static readonly ROOM_CREATE: string = 'room:create'
  static readonly ROOM_JOIN: string = 'room:join'
  static readonly ROOM_LEAVE: string = 'room:leave'
  static readonly ROOM_READY: string = 'room:ready'
  static readonly ROOM_UPDATE_SETTINGS: string = 'room:updateSettings'
  static readonly ROOM_KICK: string = 'room:kick'
  static readonly ROOM_SELECT_CHARACTER: string = 'room:selectCharacter'
  static readonly GAME_START: string = 'game:start'
  static readonly GAME_PLAY_CARDS: string = 'game:playCards'
  static readonly GAME_CHALLENGE: string = 'game:challenge'
  static readonly GAME_RESTART: string = 'game:restart'
  static readonly GAME_RETURN_TO_ROOM: string = 'game:returnToRoom'
  static readonly GAME_SEND_EMOTE: string = 'game:sendEmote'
  static readonly GAME_USE_ITEM: string = 'game:useItem'
  static readonly SESSION_RESUME: string = 'session:resume'
}

// 服务端 -> 客户端
export class ServerEvents {
  static readonly ROOM_STATE: string = 'room:state'
  static readonly ROOM_CLOSED: string = 'room:closed'
  static readonly ROOM_PLAYER_JOINED: string = 'room:playerJoined'
  static readonly ROOM_PLAYER_LEFT: string = 'room:playerLeft'
  static readonly ROOM_KICKED: string = 'room:kicked'
  static readonly SESSION_REPLACED: string = 'session:replaced'
  static readonly GAME_SNAPSHOT: string = 'game:snapshot'
  static readonly GAME_CUE: string = 'game:cue'
  static readonly GAME_STATE: string = 'game:state'
  static readonly GAME_TURN_STARTED: string = 'game:turnStarted'
  static readonly GAME_CARDS_PLAYED: string = 'game:cardsPlayed'
  static readonly GAME_CHALLENGE_STARTED: string = 'game:challengeStarted'
  static readonly GAME_CHALLENGE_RESULT: string = 'game:challengeResult'
  static readonly GAME_PUNISHMENT_STARTED: string = 'game:punishmentStarted'
  static readonly GAME_PUNISHMENT_RESULT: string = 'game:punishmentResult'
  static readonly GAME_PLAYER_ELIMINATED: string = 'game:playerEliminated'
  static readonly GAME_OVER: string = 'game:over'
  static readonly GAME_EMOTE: string = 'game:emote'
}
