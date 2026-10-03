// 实时通信管理器 - 对应 web 端 socket/client.ts + App.tsx 事件处理
// 基于 /ws 原生 WebSocket 传输（WsTransport），协议与服务端 command-dispatcher 对齐
// 处理：连接生命周期、会话恢复、房间/游戏命令、推送事件解析、快照序列去重

import { WsTransport } from './WsTransport'
import { SessionStore } from '../store/SessionStore'
import { SessionPersistence } from '../store/SessionPersistence'
import {
  RoomView, GameSnapshot, GameCue,
  SessionResumeResult, AckResult
} from '../model/GameTypes'
import {
  parseRoomView, parseRoomMembership, parseSessionResumeResult,
  parseGameSnapshot, parseGameCue
} from '../model/Parsers'
import {
  CreateRoomPayload, JoinRoomPayload, LeaveRoomPayload,
  ReadyRoomPayload, UpdateRoomSettingsPayload, KickPlayerPayload,
  StartGamePayload, PlayCardsPayload, ChallengePayload,
  RestartGamePayload, ReturnToRoomPayload, ResumeSessionPayload,
  SelectCharacterPayload, SendEmotePayload,
  validateNickname, validateRoomCode, validateCardIndexes,
  makeErrorAck, ClientEvents, ServerEvents
} from '../model/Protocol'
import { V6GameMode, CharacterId, EmoteId } from '../model/GameTypes'
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN: number = 0x0000
const TAG: string = 'SocketManager'

// 生成 UUID (用于 requestId，服务端要求 uuid 格式)
function generateUUID(): string {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c: string): string => {
    const r: number = Math.floor(Math.random() * 16)
    const v: number = c === 'x' ? r : (r & 0x3 | 0x8)
    return v.toString(16)
  })
}

// 辅助函数：从 AckError 提取可读信息
function getErrorMessage(error: AckResult, defaultMsg: string): string {
  if (error.error !== null && error.error.message.length > 0) {
    return error.error.message
  }
  return defaultMsg
}

export class SocketManager {
  private transport: WsTransport | null = null
  private store: SessionStore
  private persistence: SessionPersistence
  private serverUrl: string = ''
  // 最近应用的快照序列号；服务端每局游戏重置序列，因此开局/重启/返回大厅/恢复会话时需重置
  private lastSequence: number = -1

  constructor(store: SessionStore, persistence: SessionPersistence) {
    this.store = store
    this.persistence = persistence
  }

  // ====== 连接管理 ======

  connect(serverUrl: string): void {
    this.serverUrl = serverUrl
    if (this.transport !== null) {
      if (this.transport.isConnected() || this.transport.isConnecting()) {
        return
      }
      this.transport.disconnect()
    }
    const transport: WsTransport = new WsTransport(
      (event: string, payload: ESObject): void => {
        this.handlePush(event, payload)
      },
      (): void => {
        this.handleOpen()
      },
      (willReconnect: boolean): void => {
        this.handleClose(willReconnect)
      }
    )
    this.transport = transport
    this.store.setConnection('connecting')
    transport.connect(serverUrl)
  }

  disconnect(): void {
    if (this.transport !== null) {
      this.transport.disconnect()
      this.transport = null
    }
    this.store.setConnection('disconnected')
  }

  isConnected(): boolean {
    return this.transport !== null && this.transport.isConnected()
  }

  // ====== 连接回调 ======

  private handleOpen(): void {
    this.store.setConnection('connected')
    this.tryResumeSession()
  }

  private handleClose(willReconnect: boolean): void {
    this.store.setConnection(willReconnect ? 'connecting' : 'disconnected')
  }

  // ====== 推送事件处理 ======

  private handlePush(event: string, payload: ESObject): void {
    switch (event) {
      case ServerEvents.ROOM_STATE: {
        const room: RoomView | null = parseRoomView(payload)
        if (room !== null) {
          this.store.updateRoom(room)
        }
        break
      }
      case ServerEvents.ROOM_CLOSED:
        this.resetGameTracking()
        this.store.leaveRoom()
        this.store.setNotice('房间已关闭')
        break
      case ServerEvents.ROOM_KICKED: {
        const message: string = typeof payload === 'string' ? payload : '你已被移出房间'
        this.resetGameTracking()
        this.store.leaveRoom()
        this.store.setNotice(message)
        break
      }
      case ServerEvents.SESSION_REPLACED: {
        const message: string = typeof payload === 'string' ? payload : '你的会话已在新连接中恢复'
        this.store.setNotice(message)
        break
      }
      case ServerEvents.GAME_SNAPSHOT:
      case ServerEvents.GAME_STATE:
      case ServerEvents.GAME_TURN_STARTED:
      case ServerEvents.GAME_CHALLENGE_RESULT:
      case ServerEvents.GAME_PUNISHMENT_RESULT:
      case ServerEvents.GAME_OVER: {
        const snapshot: GameSnapshot | null = parseGameSnapshot(payload)
        if (snapshot !== null) {
          this.applyGameSnapshot(snapshot)
        }
        break
      }
      case ServerEvents.GAME_CUE: {
        const cue: GameCue | null = parseGameCue(payload)
        if (cue !== null) {
          this.handleGameCue(cue)
        }
        break
      }
      default:
        // room:playerJoined / room:playerLeft / game:cardsPlayed 等通知事件：
        // 状态已由 room:state / game:snapshot 推送覆盖
        break
    }
  }

  // ====== 游戏事件提示处理 ======

  private handleGameCue(cue: GameCue): void {
    // 根据 cue.type 触发声效或 UI 反馈
    // 后续与 AudioManager 集成
    hilog.info(DOMAIN, TAG, `game cue: ${cue.type} seq=${cue.sequence}`)
  }

  // ====== 快照序列去重 ======

  private applyGameSnapshot(snapshot: GameSnapshot): void {
    if (snapshot.sequence < this.lastSequence) {
      // 丢弃过期快照（乱序到达的旧状态）
      return
    }
    this.lastSequence = snapshot.sequence
    this.store.setGame(snapshot)
  }

  private resetGameTracking(): void {
    this.lastSequence = -1
  }

  // ====== 会话恢复 ======

  private tryResumeSession(): void {
    const token: string | null = this.store.sessionToken
    if (token === null || token.length === 0) return

    const payload: ResumeSessionPayload = new ResumeSessionPayload()
    payload.sessionToken = token

    this.sendCommand(ClientEvents.SESSION_RESUME, payload, (result: AckResult) => {
      if (result.ok) {
        const data: SessionResumeResult | null = parseSessionResumeResult(result.data)
        if (data !== null) {
          this.store.enterRoom(data.room, data.playerId, data.sessionToken)
          this.persistence.saveToken(data.sessionToken)
          this.resetGameTracking()
          if (data.game !== null) {
            this.applyGameSnapshot(data.game)
          }
          hilog.info(DOMAIN, TAG, `session resumed: room=${data.room.code}`)
        }
      } else {
        // 会话已失效（房间关闭/令牌过期）：清除本地令牌，用户需重新加入
        hilog.warn(DOMAIN, TAG, `session resume failed: ${result.error.code}`)
        this.store.sessionToken = null
        this.persistence.clearToken()
      }
    })
  }

  // ====== 命令发送辅助 ======

  private sendCommand(event: string, payload: ESObject, callback?: (result: AckResult) => void): void {
    const transport: WsTransport | null = this.transport
    if (transport === null || !transport.isConnected()) {
      if (callback !== undefined) {
        callback(makeErrorAck('NOT_CONNECTED', '未连接到服务器'))
      }
      return
    }
    transport.send(event, payload, callback)
  }

  // ====== 客户端操作方法 ======

  // 创建房间
  createRoom(nickname: string, callback?: (success: boolean, error?: string) => void): void {
    if (!this.ensureConnected(callback)) return
    if (!validateNickname(nickname)) {
      if (callback) callback(false, '昵称无效')
      return
    }

    const payload: CreateRoomPayload = new CreateRoomPayload()
    payload.nickname = nickname.trim()

    this.sendCommand(ClientEvents.ROOM_CREATE, payload, (result: AckResult) => {
      hilog.info(DOMAIN, TAG, `createRoom ack received, ok=${result.ok}`)
      if (result.ok) {
        const membership = parseRoomMembership(result.data)
        hilog.info(DOMAIN, TAG, `createRoom membership parse: ${membership === null ? 'null' : membership.room.code}`)
        if (membership !== null) {
          this.store.enterRoom(membership.room, membership.playerId, membership.sessionToken)
          this.persistence.saveToken(membership.sessionToken)
          if (callback) callback(true)
        } else {
          if (callback) callback(false, '服务器响应异常')
        }
      } else {
        if (callback) callback(false, getErrorMessage(result, '创建房间失败'))
      }
    })
  }

  // 加入房间
  joinRoom(nickname: string, roomCode: string, callback?: (success: boolean, error?: string) => void): void {
    if (!this.ensureConnected(callback)) return
    if (!validateNickname(nickname)) {
      if (callback) callback(false, '昵称无效')
      return
    }
    if (!validateRoomCode(roomCode)) {
      if (callback) callback(false, '房间码无效')
      return
    }

    const payload: JoinRoomPayload = new JoinRoomPayload()
    payload.nickname = nickname.trim()
    payload.roomCode = roomCode.trim().toUpperCase()

    this.sendCommand(ClientEvents.ROOM_JOIN, payload, (result: AckResult) => {
      if (result.ok) {
        const membership = parseRoomMembership(result.data)
        if (membership !== null) {
          this.store.enterRoom(membership.room, membership.playerId, membership.sessionToken)
          this.persistence.saveToken(membership.sessionToken)
          if (callback) callback(true)
        } else {
          if (callback) callback(false, '服务器响应异常')
        }
      } else {
        if (callback) callback(false, getErrorMessage(result, '加入房间失败'))
      }
    })
  }

  // 离开房间（仅在服务端确认成功后清除本地房间状态）
  leaveRoom(callback?: (success: boolean) => void): void {
    if (!this.store.room) {
      if (callback) callback(false)
      return
    }

    const payload: LeaveRoomPayload = new LeaveRoomPayload()
    payload.roomCode = this.store.room.code

    this.sendCommand(ClientEvents.ROOM_LEAVE, payload, (result: AckResult) => {
      if (result.ok) {
        this.resetGameTracking()
        this.store.leaveRoom()
        this.persistence.clearToken()
        if (callback) callback(true)
      } else {
        if (callback) callback(false)
      }
    })
  }

  // 准备/取消准备
  setReady(ready: boolean, callback?: (success: boolean) => void): void {
    if (!this.store.room) {
      if (callback) callback(false)
      return
    }

    const payload: ReadyRoomPayload = new ReadyRoomPayload()
    payload.roomCode = this.store.room.code
    payload.ready = ready
    payload.requestId = generateUUID()

    this.sendCommand(ClientEvents.ROOM_READY, payload, (result: AckResult) => {
      if (result.ok) {
        const room: RoomView | null = parseRoomView(result.data)
        if (room !== null) {
          this.store.updateRoom(room)
        }
        if (callback) callback(true)
      } else {
        if (callback) callback(false)
      }
    })
  }

  // 更新房间设置（仅 maxPlayers / gameMode）
  updateSettings(maxPlayers: number, gameMode: string, callback?: (success: boolean) => void): void {
    if (!this.store.room) {
      if (callback) callback(false)
      return
    }

    const payload: UpdateRoomSettingsPayload = new UpdateRoomSettingsPayload()
    payload.roomCode = this.store.room.code
    payload.maxPlayers = maxPlayers
    payload.gameMode = gameMode as V6GameMode
    payload.requestId = generateUUID()

    this.sendCommand(ClientEvents.ROOM_UPDATE_SETTINGS, payload, (result: AckResult) => {
      if (result.ok) {
        const room: RoomView | null = parseRoomView(result.data)
        if (room !== null) {
          this.store.updateRoom(room)
        }
        if (callback) callback(true)
      } else {
        if (callback) callback(false)
      }
    })
  }

  // 踢出玩家
  kickPlayer(targetPlayerId: string, callback?: (success: boolean) => void): void {
    if (!this.store.room) {
      if (callback) callback(false)
      return
    }

    const payload: KickPlayerPayload = new KickPlayerPayload()
    payload.roomCode = this.store.room.code
    payload.targetPlayerId = targetPlayerId
    payload.requestId = generateUUID()

    this.sendCommand(ClientEvents.ROOM_KICK, payload, (result: AckResult) => {
      if (result.ok) {
        const room: RoomView | null = parseRoomView(result.data)
        if (room !== null) {
          this.store.updateRoom(room)
        }
        if (callback) callback(true)
      } else {
        if (callback) callback(false)
      }
    })
  }

  // 选择角色
  selectCharacter(characterId: string, callback?: (success: boolean) => void): void {
    if (!this.store.room) {
      if (callback) callback(false)
      return
    }

    const payload: SelectCharacterPayload = new SelectCharacterPayload()
    payload.roomCode = this.store.room.code
    payload.characterId = characterId as CharacterId

    this.sendCommand(ClientEvents.ROOM_SELECT_CHARACTER, payload, (result: AckResult) => {
      if (result.ok) {
        const room: RoomView | null = parseRoomView(result.data)
        if (room !== null) {
          this.store.updateRoom(room)
        }
        if (callback) callback(true)
      } else {
        if (callback) callback(false)
      }
    })
  }

  // 开始游戏
  startGame(callback?: (success: boolean, error?: string) => void): void {
    if (!this.store.room) {
      if (callback) callback(false, '未在房间中')
      return
    }

    const payload: StartGamePayload = new StartGamePayload()
    payload.roomCode = this.store.room.code
    payload.requestId = generateUUID()

    this.sendCommand(ClientEvents.GAME_START, payload, (result: AckResult) => {
      if (result.ok) {
        this.resetGameTracking()
        const snapshot: GameSnapshot | null = parseGameSnapshot(result.data)
        if (snapshot !== null) {
          this.applyGameSnapshot(snapshot)
        }
        if (callback) callback(true)
      } else {
        if (callback) callback(false, getErrorMessage(result, '开始游戏失败'))
      }
    })
  }

  // 出牌
  playCards(cardIndexes: number[], callback?: (success: boolean, error?: string) => void): void {
    if (!this.store.room) {
      if (callback) callback(false, '未在房间中')
      return
    }
    if (!validateCardIndexes(cardIndexes)) {
      if (callback) callback(false, '选牌无效')
      return
    }

    const payload: PlayCardsPayload = new PlayCardsPayload()
    payload.roomCode = this.store.room.code
    payload.cardIndexes = cardIndexes
    payload.requestId = generateUUID()

    this.sendCommand(ClientEvents.GAME_PLAY_CARDS, payload, (result: AckResult) => {
      if (result.ok) {
        const snapshot: GameSnapshot | null = parseGameSnapshot(result.data)
        if (snapshot !== null) {
          this.applyGameSnapshot(snapshot)
        }
        if (callback) callback(true)
      } else {
        if (callback) callback(false, getErrorMessage(result, '出牌失败'))
      }
    })
  }

  // 质疑
  challenge(callback?: (success: boolean, error?: string) => void): void {
    if (!this.store.room) {
      if (callback) callback(false, '未在房间中')
      return
    }

    const payload: ChallengePayload = new ChallengePayload()
    payload.roomCode = this.store.room.code
    payload.requestId = generateUUID()

    this.sendCommand(ClientEvents.GAME_CHALLENGE, payload, (result: AckResult) => {
      if (result.ok) {
        const snapshot: GameSnapshot | null = parseGameSnapshot(result.data)
        if (snapshot !== null) {
          this.applyGameSnapshot(snapshot)
        }
        if (callback) callback(true)
      } else {
        if (callback) callback(false, getErrorMessage(result, '质疑失败'))
      }
    })
  }

  // 重新开始
  restartGame(callback?: (success: boolean) => void): void {
    if (!this.store.room) {
      if (callback) callback(false)
      return
    }

    const payload: RestartGamePayload = new RestartGamePayload()
    payload.roomCode = this.store.room.code
    payload.requestId = generateUUID()

    this.sendCommand(ClientEvents.GAME_RESTART, payload, (result: AckResult) => {
      if (result.ok) {
        this.resetGameTracking()
        const snapshot: GameSnapshot | null = parseGameSnapshot(result.data)
        if (snapshot !== null) {
          this.applyGameSnapshot(snapshot)
        }
        if (callback) callback(true)
      } else {
        if (callback) callback(false)
      }
    })
  }

  // 返回大厅
  returnToRoom(callback?: (success: boolean) => void): void {
    if (!this.store.room) {
      if (callback) callback(false)
      return
    }

    const payload: ReturnToRoomPayload = new ReturnToRoomPayload()
    payload.roomCode = this.store.room.code
    payload.requestId = generateUUID()

    this.sendCommand(ClientEvents.GAME_RETURN_TO_ROOM, payload, (result: AckResult) => {
      if (result.ok) {
        this.resetGameTracking()
        this.store.clearGame()
        const room: RoomView | null = parseRoomView(result.data)
        if (room !== null) {
          this.store.updateRoom(room)
        }
        if (callback) callback(true)
      } else {
        if (callback) callback(false)
      }
    })
  }

  // 发送表情
  sendEmote(emoteId: string): void {
    if (!this.store.room) return

    const payload: SendEmotePayload = new SendEmotePayload()
    payload.roomCode = this.store.room.code
    payload.emoteId = emoteId as EmoteId

    this.sendCommand(ClientEvents.GAME_SEND_EMOTE, payload)
  }

  // ====== 内部辅助 ======

  // 连接守卫：未连接时直接回调失败（此时不做昵称等参数校验）
  private ensureConnected(callback?: (success: boolean, error?: string) => void): boolean {
    if (this.transport === null || !this.transport.isConnected()) {
      if (callback) callback(false, '未连接到服务器')
      return false
    }
    return true
  }
}
