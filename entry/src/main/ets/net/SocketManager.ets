// Socket IO 网络管理器 - 对应 socket/client.ts + App.tsx 中的事件处理
// 通过 npm 引入 socket.io-client
// ArkTS 兼容版本：移除所有 as any，使用 ESObject 处理动态类型

import { io, Socket } from 'socket.io-client'
import { SessionStore } from '../store/SessionStore'
import {
  RoomMembership, RoomView, GameSnapshot, GameCue,
  RoomPlayerEvent, SessionResumeResult, AckResult, AckError,
  ConnectionStatus, GameView
} from '../model/GameTypes'
import {
  CreateRoomPayload, JoinRoomPayload, LeaveRoomPayload,
  ReadyRoomPayload, UpdateRoomSettingsPayload, KickPlayerPayload,
  StartGamePayload, PlayCardsPayload, ChallengePayload,
  RestartGamePayload, ReturnToRoomPayload, ResumeSessionPayload,
  SelectCharacterPayload, SendEmotePayload,
  validateNickname, validateRoomCode, validateCardIndexes,
  ClientEvents, ServerEvents
} from '../model/Protocol'
import { V6GameMode, CharacterId, EmoteId } from '../model/GameTypes'

// 生成 UUID (用于 requestId)
function generateUUID(): string {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c: string): string => {
    const r: number = Math.floor(Math.random() * 16)
    const v: number = c === 'x' ? r : (r & 0x3 | 0x8)
    return v.toString(16)
  })
}

// 辅助函数：替代 ?? 操作符（ArkTS 不支持 ??）
function getErrorMessage(error: AckError | null, defaultMsg: string): string {
  if (error !== null && error.message !== null && error.message.length > 0) {
    return error.message
  }
  return defaultMsg
}

export class SocketManager {
  private socket: Socket | null = null
  private store: SessionStore
  private serverUrl: string = ''

  constructor(store: SessionStore) {
    this.store = store
  }

  // ====== 连接管理 ======

  connect(serverUrl: string): void {
    this.serverUrl = serverUrl
    this.store.setConnection('connecting')

    this.socket = io(serverUrl, {
      autoConnect: false,
      reconnection: true,
      reconnectionDelay: 500,
      reconnectionDelayMax: 4000,
      randomizationFactor: 0.2,
      transports: ['websocket'],
    })

    this.registerEventHandlers()
    this.socket.connect()
  }

  disconnect(): void {
    if (this.socket) {
      this.socket.disconnect()
      this.socket = null
    }
    this.store.setConnection('disconnected')
  }

  isConnected(): boolean {
    return this.socket !== null && this.socket.connected
  }

  // ====== 事件处理器注册 ======

  private registerEventHandlers(): void {
    if (!this.socket) return

    // 连接事件
    this.socket.on('connect', () => {
      this.store.setConnection('connected')
      this.tryResumeSession()
    })

    this.socket.on('disconnect', () => {
      this.store.setConnection('disconnected')
    })

    this.socket.on('connect_error', () => {
      this.store.setConnection('connecting')
    })

    // 房间事件
    this.socket.on(ServerEvents.ROOM_STATE, (room: RoomView) => {
      this.store.updateRoom(room)
    })

    this.socket.on(ServerEvents.ROOM_CLOSED, () => {
      this.store.leaveRoom()
      this.store.setNotice('房间已关闭')
    })

    this.socket.on(ServerEvents.ROOM_PLAYER_JOINED, (event: RoomPlayerEvent) => {
      // 玩家加入通知，room:state 会携带最新房间状态
    })

    this.socket.on(ServerEvents.ROOM_PLAYER_LEFT, (event: RoomPlayerEvent) => {
      // 玩家离开通知
    })

    this.socket.on(ServerEvents.ROOM_KICKED, (message: string) => {
      this.store.leaveRoom()
      this.store.setNotice(message)
    })

    this.socket.on(ServerEvents.SESSION_REPLACED, (message: string) => {
      this.store.setNotice(message)
    })

    // 游戏事件
    this.socket.on(ServerEvents.GAME_SNAPSHOT, (state: GameSnapshot) => {
      this.store.setGame(state)
    })

    this.socket.on(ServerEvents.GAME_CUE, (cue: GameCue) => {
      this.handleGameCue(cue)
    })

    this.socket.on(ServerEvents.GAME_STATE, (state: GameSnapshot) => {
      this.store.setGame(state)
    })

    this.socket.on(ServerEvents.GAME_TURN_STARTED, (state: GameSnapshot) => {
      this.store.setGame(state)
    })

    this.socket.on(ServerEvents.GAME_CARDS_PLAYED, (event: ESObject) => {
      // 出牌通知
    })

    this.socket.on(ServerEvents.GAME_CHALLENGE_STARTED, (event: ESObject) => {
      // 质疑开始通知
    })

    this.socket.on(ServerEvents.GAME_CHALLENGE_RESULT, (state: GameSnapshot) => {
      this.store.setGame(state)
    })

    this.socket.on(ServerEvents.GAME_PUNISHMENT_STARTED, (event: ESObject) => {
      // 惩罚开始通知
    })

    this.socket.on(ServerEvents.GAME_PUNISHMENT_RESULT, (state: GameSnapshot) => {
      this.store.setGame(state)
    })

    this.socket.on(ServerEvents.GAME_PLAYER_ELIMINATED, (event: ESObject) => {
      // 玩家淘汰通知
    })

    this.socket.on(ServerEvents.GAME_OVER, (state: GameSnapshot) => {
      this.store.setGame(state)
    })

    this.socket.on(ServerEvents.GAME_EMOTE, (event: ESObject) => {
      // 表情通知
    })
  }

  // ====== 游戏事件提示处理 ======

  private handleGameCue(cue: GameCue): void {
    // 根据 cue.type 触发声效或 UI 反馈
    // 后续与 AudioManager 集成
  }

  // ====== 会话恢复 ======

  private tryResumeSession(): void {
    if (!this.socket || !this.store.sessionToken) return

    const payload: ResumeSessionPayload = new ResumeSessionPayload()
    payload.sessionToken = this.store.sessionToken

    this.socket.emit(ClientEvents.SESSION_RESUME, payload, (result: AckResult) => {
      if (result.ok) {
        const data = result.data as SessionResumeResult
        this.store.enterRoom(data.room, data.playerId, data.sessionToken)
        if (data.game) {
          this.store.setGame(data.game)
        }
      }
    })
  }

  // ====== 客户端操作方法 ======

  // 创建房间
  createRoom(nickname: string, callback?: (success: boolean, error?: string) => void): void {
    if (!this.socket || !validateNickname(nickname)) {
      if (callback) callback(false, '昵称无效')
      return
    }

    const payload: CreateRoomPayload = new CreateRoomPayload()
    payload.nickname = nickname.trim()

    this.socket.emit(ClientEvents.ROOM_CREATE, payload, (result: AckResult) => {
      if (result.ok) {
        const data = result.data as RoomMembership
        this.store.enterRoom(data.room, data.playerId, data.sessionToken)
        if (callback) callback(true)
      } else {
        const errMsg = getErrorMessage(result.error, '创建房间失败')
        if (callback) callback(false, errMsg)
      }
    })
  }

  // 加入房间
  joinRoom(nickname: string, roomCode: string, callback?: (success: boolean, error?: string) => void): void {
    if (!this.socket || !validateNickname(nickname)) {
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

    this.socket.emit(ClientEvents.ROOM_JOIN, payload, (result: AckResult) => {
      if (result.ok) {
        const data = result.data as RoomMembership
        this.store.enterRoom(data.room, data.playerId, data.sessionToken)
        if (callback) callback(true)
      } else {
        const errMsg = getErrorMessage(result.error, '加入房间失败')
        if (callback) callback(false, errMsg)
      }
    })
  }

  // 离开房间
  leaveRoom(callback?: (success: boolean) => void): void {
    if (!this.socket || !this.store.room) {
      if (callback) callback(false)
      return
    }

    const payload: LeaveRoomPayload = new LeaveRoomPayload()
    payload.roomCode = this.store.room.code

    this.socket.emit(ClientEvents.ROOM_LEAVE, payload, () => {
      this.store.leaveRoom()
      if (callback) callback(true)
    })
  }

  // 准备/取消准备
  setReady(ready: boolean, callback?: (success: boolean) => void): void {
    if (!this.socket || !this.store.room) {
      if (callback) callback(false)
      return
    }

    const payload: ReadyRoomPayload = new ReadyRoomPayload()
    payload.roomCode = this.store.room.code
    payload.ready = ready
    payload.requestId = generateUUID()

    this.socket.emit(ClientEvents.ROOM_READY, payload, (result: AckResult) => {
      if (result.ok) {
        const data = result.data as RoomView
        this.store.updateRoom(data)
        if (callback) callback(true)
      } else {
        if (callback) callback(false)
      }
    })
  }

  // 更新房间设置
  updateSettings(maxPlayers: number, gameMode: string, callback?: (success: boolean) => void): void {
    if (!this.socket || !this.store.room) {
      if (callback) callback(false)
      return
    }

    const payload: UpdateRoomSettingsPayload = new UpdateRoomSettingsPayload()
    payload.roomCode = this.store.room.code
    payload.maxPlayers = maxPlayers
    payload.gameMode = gameMode as V6GameMode
    payload.requestId = generateUUID()

    this.socket.emit(ClientEvents.ROOM_UPDATE_SETTINGS, payload, (result: AckResult) => {
      if (result.ok) {
        const data = result.data as RoomView
        this.store.updateRoom(data)
        if (callback) callback(true)
      } else {
        if (callback) callback(false)
      }
    })
  }

  // 踢出玩家
  kickPlayer(targetPlayerId: string, callback?: (success: boolean) => void): void {
    if (!this.socket || !this.store.room) {
      if (callback) callback(false)
      return
    }

    const payload: KickPlayerPayload = new KickPlayerPayload()
    payload.roomCode = this.store.room.code
    payload.targetPlayerId = targetPlayerId
    payload.requestId = generateUUID()

    this.socket.emit(ClientEvents.ROOM_KICK, payload, (result: AckResult) => {
      if (result.ok) {
        const data = result.data as RoomView
        this.store.updateRoom(data)
        if (callback) callback(true)
      } else {
        if (callback) callback(false)
      }
    })
  }

  // 选择角色
  selectCharacter(characterId: string, callback?: (success: boolean) => void): void {
    if (!this.socket || !this.store.room) {
      if (callback) callback(false)
      return
    }

    const payload: SelectCharacterPayload = new SelectCharacterPayload()
    payload.roomCode = this.store.room.code
    payload.characterId = characterId as CharacterId

    this.socket.emit(ClientEvents.ROOM_SELECT_CHARACTER, payload, (result: AckResult) => {
      if (result.ok) {
        const data = result.data as RoomView
        this.store.updateRoom(data)
        if (callback) callback(true)
      } else {
        if (callback) callback(false)
      }
    })
  }

  // 开始游戏
  startGame(callback?: (success: boolean, error?: string) => void): void {
    if (!this.socket || !this.store.room) {
      if (callback) callback(false, '未在房间中')
      return
    }

    const payload: StartGamePayload = new StartGamePayload()
    payload.roomCode = this.store.room.code
    payload.requestId = generateUUID()

    this.socket.emit(ClientEvents.GAME_START, payload, (result: AckResult) => {
      if (result.ok) {
        const data = result.data as GameSnapshot
        this.store.setGame(data)
        if (callback) callback(true)
      } else {
        const errMsg = getErrorMessage(result.error, '开始游戏失败')
        if (callback) callback(false, errMsg)
      }
    })
  }

  // 出牌
  playCards(cardIndexes: number[], callback?: (success: boolean, error?: string) => void): void {
    if (!this.socket || !this.store.room) {
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

    this.socket.emit(ClientEvents.GAME_PLAY_CARDS, payload, (result: AckResult) => {
      if (result.ok) {
        const data = result.data as GameSnapshot
        this.store.setGame(data)
        if (callback) callback(true)
      } else {
        const errMsg = getErrorMessage(result.error, '出牌失败')
        if (callback) callback(false, errMsg)
      }
    })
  }

  // 质疑
  challenge(callback?: (success: boolean, error?: string) => void): void {
    if (!this.socket || !this.store.room) {
      if (callback) callback(false, '未在房间中')
      return
    }

    const payload: ChallengePayload = new ChallengePayload()
    payload.roomCode = this.store.room.code
    payload.requestId = generateUUID()

    this.socket.emit(ClientEvents.GAME_CHALLENGE, payload, (result: AckResult) => {
      if (result.ok) {
        const data = result.data as GameSnapshot
        this.store.setGame(data)
        if (callback) callback(true)
      } else {
        const errMsg = getErrorMessage(result.error, '质疑失败')
        if (callback) callback(false, errMsg)
      }
    })
  }

  // 重新开始
  restartGame(callback?: (success: boolean) => void): void {
    if (!this.socket || !this.store.room) {
      if (callback) callback(false)
      return
    }

    const payload: RestartGamePayload = new RestartGamePayload()
    payload.roomCode = this.store.room.code
    payload.requestId = generateUUID()

    this.socket.emit(ClientEvents.GAME_RESTART, payload, (result: AckResult) => {
      if (result.ok) {
        const data = result.data as GameSnapshot
        this.store.setGame(data)
        if (callback) callback(true)
      } else {
        if (callback) callback(false)
      }
    })
  }

  // 返回大厅
  returnToRoom(callback?: (success: boolean) => void): void {
    if (!this.socket || !this.store.room) {
      if (callback) callback(false)
      return
    }

    const payload: ReturnToRoomPayload = new ReturnToRoomPayload()
    payload.roomCode = this.store.room.code
    payload.requestId = generateUUID()

    this.socket.emit(ClientEvents.GAME_RETURN_TO_ROOM, payload, (result: AckResult) => {
      if (result.ok) {
        const data = result.data as RoomView
        this.store.clearGame()
        this.store.updateRoom(data)
        if (callback) callback(true)
      } else {
        if (callback) callback(false)
      }
    })
  }

  // 发送表情
  sendEmote(emoteId: string): void {
    if (!this.socket || !this.store.room) return

    const payload: SendEmotePayload = new SendEmotePayload()
    payload.roomCode = this.store.room.code
    payload.emoteId = emoteId as EmoteId

    this.socket.emit(ClientEvents.GAME_SEND_EMOTE, payload)
  }
}
