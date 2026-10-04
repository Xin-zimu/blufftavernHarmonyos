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
  SelectCharacterPayload, SendEmotePayload, UseItemPayload,
  validateNickname, validateRoomCode, validateCardIndexes,
  makeErrorAck, ClientEvents, ServerEvents
} from '../model/Protocol'
import { V7ExtensionSettings, PlayableGameMode, CharacterId, EmoteId, ItemId } from '../model/GameTypes'
import { MAX_CARDS_PER_PLAY } from '../model/Constants'
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
  // 同序列号的最近 serverNow，用于平手判定（与网页版 shouldAcceptGameSnapshot 一致）
  private lastServerNow: number = -1
  // 权威重同步节流（网页版 RESYNC_THROTTLE_MS = 4000）
  private lastResyncAt: number = 0
  private sessionEpoch: number = 0
  private transportEpoch: number = 0
  private recoveryBlocked: boolean = false
  private resumeInFlight: boolean = false
  private resumeSerial: number = 0
  private resumeRetryTimer: number = -1
  private retiredMatchIds: string[] = []

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
    const epoch: number = ++this.transportEpoch
    const transport: WsTransport = new WsTransport(
      (event: string, payload: ESObject): void => {
        if (epoch !== this.transportEpoch) return
        this.handlePush(event, payload)
      },
      (): void => {
        if (epoch !== this.transportEpoch) return
        this.handleOpen()
      },
      (willReconnect: boolean): void => {
        if (epoch !== this.transportEpoch) return
        this.handleClose(willReconnect)
      }
    )
    this.transport = transport
    this.store.setConnection('connecting')
    transport.connect(serverUrl)
  }

  disconnect(): void {
    this.transportEpoch++
    this.cancelResume()
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
    this.cancelResume()
    this.store.setConnection(willReconnect ? 'connecting' : 'disconnected')
  }

  // ====== 推送事件处理 ======

  private handlePush(event: string, payload: ESObject): void {
    switch (event) {
      case ServerEvents.ROOM_STATE: {
        const room: RoomView | null = parseRoomView(payload)
        if (room !== null) {
          this.prepareRoomState(room)
          this.store.updateRoom(room)
        }
        break
      }
      case ServerEvents.ROOM_CLOSED:
        this.endSession()
        this.store.setNotice('房间已关闭')
        break
      case ServerEvents.ROOM_KICKED: {
        const message: string = typeof payload === 'string' ? payload : '你已被移出房间'
        this.endSession()
        this.store.setNotice(message)
        break
      }
      case ServerEvents.SESSION_REPLACED: {
        const message: string = typeof payload === 'string' ? payload : '你的会话已在新连接中恢复'
        // endSession 递增 sessionEpoch，挂起 ACK 一律作废。
        // 不主动 disconnect：保持传输连接（对齐网页版），recoveryBlocked
        // 已阻止自动 resume，用户可立即创建/加入新房间。
        this.endSession()
        this.recoveryBlocked = true
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
    if (this.recoveryBlocked || this.store.room === null) return
    if (snapshot.matchId.length > 0 && this.retiredMatchIds.indexOf(snapshot.matchId) >= 0) return
    const previous: GameSnapshot | null = this.store.game
    if (previous !== null && previous.matchId.length > 0 && snapshot.matchId.length > 0 &&
      previous.matchId !== snapshot.matchId) {
      this.clearMatch()
    }
    // 快照接受门卫：sequence 严格递增；相同 sequence 时要求 serverNow 不回退
    if (snapshot.sequence < this.lastSequence) {
      return
    }
    if (snapshot.sequence === this.lastSequence && snapshot.serverNow < this.lastServerNow) {
      return
    }
    this.lastSequence = snapshot.sequence
    this.lastServerNow = snapshot.serverNow
    this.store.setGame(snapshot)
  }

  private resetGameTracking(): void {
    this.lastSequence = -1
    this.lastServerNow = -1
  }

  private clearMatch(): void {
    const matchId: string = this.store.game?.matchId ?? ''
    if (matchId.length > 0 && this.retiredMatchIds.indexOf(matchId) < 0) {
      this.retiredMatchIds.push(matchId)
    }
    this.resetGameTracking()
    this.store.clearGame()
  }

  private prepareRoomState(room: RoomView): void {
    const previous: RoomView | null = this.store.room
    // 兼容尚未携带 matchId 的服务端：restart 的权威房间状态先于新快照到达。
    if (room.status === 'LOBBY' || (previous !== null && previous.code !== room.code) ||
      (room.status === 'PLAYING' && (previous?.status === 'GAME_OVER' || this.store.game?.phase === 'GAME_OVER'))) {
      if (this.store.game !== null) this.clearMatch()
    }
  }

  private cancelResume(): void {
    this.resumeSerial++
    this.resumeInFlight = false
    if (this.resumeRetryTimer !== -1) clearTimeout(this.resumeRetryTimer)
    this.resumeRetryTimer = -1
  }

  private endSession(): void {
    this.sessionEpoch++
    this.cancelResume()
    this.clearMatch()
    this.retiredMatchIds = []
    this.store.leaveRoom()
    this.persistence.clearToken()
  }

  private beginMembership(room: RoomView, playerId: string, token: string): void {
    this.sessionEpoch++
    this.cancelResume()
    this.recoveryBlocked = false
    this.clearMatch()
    this.retiredMatchIds = []
    this.lastResyncAt = 0
    this.store.enterRoom(room, playerId, token)
    this.persistence.saveToken(token)
  }

  // ====== 会话恢复 ======

  // 请求权威重同步：节流 4 秒（网页版 RESYNC_THROTTLE_MS）
  requestAuthoritativeResync(): void {
    const now: number = Date.now()
    if (now - this.lastResyncAt < 4000) {
      return
    }
    this.tryResumeSession()
  }

  // 操作被服务器按相位拒绝时触发重同步（网页版 RESYNC_ON_ERROR_CODES）
  private maybeResyncFromError(code: string | undefined): void {
    if (code === undefined) {
      return
    }
    if (code === 'NOT_YOUR_TURN' || code === 'PHASE_LOCKED' || code === 'MUST_CHALLENGE' || code === 'CHALLENGE_WINDOW_CLOSED') {
      this.requestAuthoritativeResync()
    }
  }

  private tryResumeSession(): void {
    const token: string | null = this.store.sessionToken
    if (this.recoveryBlocked || this.resumeInFlight || !this.isConnected() || token === null || token.length === 0) return
    if (this.resumeRetryTimer !== -1) clearTimeout(this.resumeRetryTimer)
    this.resumeRetryTimer = -1
    this.lastResyncAt = Date.now()
    this.resumeInFlight = true
    const serial: number = ++this.resumeSerial

    const payload: ResumeSessionPayload = new ResumeSessionPayload()
    payload.sessionToken = token

    this.sendCommand(ClientEvents.SESSION_RESUME, payload, (result: AckResult) => {
      if (serial !== this.resumeSerial || this.recoveryBlocked || token !== this.store.sessionToken) return
      this.resumeInFlight = false
      if (result.ok) {
        const data: SessionResumeResult | null = parseSessionResumeResult(result.data)
        if (data !== null) {
          this.prepareRoomState(data.room)
          this.store.enterRoom(data.room, data.playerId, data.sessionToken)
          this.persistence.saveToken(data.sessionToken)
          if (data.game !== null) {
            this.applyGameSnapshot(data.game)
          } else {
            this.clearMatch()
          }
          hilog.info(DOMAIN, TAG, `session resumed: room=${data.room.code}`)
        }
      } else {
        hilog.warn(DOMAIN, TAG, `session resume failed: ${result.error.code}`)
        if (result.error.code === 'SESSION_NOT_FOUND') {
          this.endSession()
          this.store.setNotice(result.error.message)
        } else {
          // 传输/限流/服务端暂时故障不能撤销凭证；只允许一个延迟重试。
          this.resumeRetryTimer = setTimeout(() => {
            this.resumeRetryTimer = -1
            if (serial === this.resumeSerial && token === this.store.sessionToken) this.tryResumeSession()
          }, 4000)
        }
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
    const epoch: number = this.sessionEpoch
    const connectionEpoch: number = this.transportEpoch
    transport.send(event, payload, (result: AckResult): void => {
      if (epoch !== this.sessionEpoch || connectionEpoch !== this.transportEpoch || transport !== this.transport) return
      if (callback !== undefined) callback(result)
    })
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
          this.beginMembership(membership.room, membership.playerId, membership.sessionToken)
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
          this.beginMembership(membership.room, membership.playerId, membership.sessionToken)
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
        this.endSession()
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

  // 更新房间设置（7.2：完整字段，与网页版 updateSettings 载荷一致）
  updateSettings(maxPlayers: number, gameMode: PlayableGameMode,
    turnDurationSeconds: number, v7: V7ExtensionSettings, callback?: (success: boolean) => void): void {
    if (!this.store.room) {
      if (callback) callback(false)
      return
    }

    const payload: UpdateRoomSettingsPayload = new UpdateRoomSettingsPayload()
    payload.roomCode = this.store.room.code
    payload.maxPlayers = maxPlayers
    payload.gameMode = gameMode
    payload.turnDurationSeconds = turnDurationSeconds
    payload.eventEnabled = false
    payload.bulletCount = null
    payload.v7 = v7
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
    // 按当前快照的动态出牌范围校验（7.2：minimum/maximumPlayCount 随模式/事件变化）
    const game: GameSnapshot | null = this.store.game
    const minCount: number = game !== null ? game.minimumPlayCount : 1
    const maxCount: number = game !== null ? game.maximumPlayCount : MAX_CARDS_PER_PLAY
    if (!validateCardIndexes(cardIndexes, minCount, maxCount)) {
      if (callback) callback(false, '选牌数量无效')
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
        this.maybeResyncFromError(result.error.code)
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
        this.maybeResyncFromError(result.error.code)
        if (callback) callback(false, getErrorMessage(result, '质疑失败'))
      }
    })
  }

  // 使用道具
  useItem(itemId: ItemId, callback?: (success: boolean, error?: string) => void): void {
    if (!this.store.room) {
      if (callback) callback(false, '未在房间中')
      return
    }

    const payload: UseItemPayload = new UseItemPayload()
    payload.roomCode = this.store.room.code
    payload.itemId = itemId
    payload.requestId = generateUUID()

    this.sendCommand(ClientEvents.GAME_USE_ITEM, payload, (result: AckResult) => {
      if (result.ok) {
        const snapshot: GameSnapshot | null = parseGameSnapshot(result.data)
        if (snapshot !== null) {
          this.applyGameSnapshot(snapshot)
        }
        if (callback) callback(true)
      } else {
        this.maybeResyncFromError(result.error.code)
        if (callback) callback(false, getErrorMessage(result, '道具使用失败'))
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
