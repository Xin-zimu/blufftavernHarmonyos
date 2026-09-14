// Socket.IO 网络管理器 - 对应 socket/client.ts + App.tsx 中的事件处理
// 鸿蒙中通过 npm 引入 socket.io-client

import { io, Socket } from 'socket.io-client'
import { SessionStore } from '../store/SessionStore'
import {
  Ack, RoomMembership, RoomView, GameSnapshot, GameCue,
  RoomPlayerEvent, SessionResumeResult, ConnectionStatus
} from '../model/GameTypes'
import {
  CLIENT_EVENTS, SERVER_EVENTS,
  CreateRoomPayload, JoinRoomPayload, LeaveRoomPayload,
  ReadyRoomPayload, UpdateRoomSettingsPayload, KickPlayerPayload,
  StartGamePayload, PlayCardsPayload, ChallengePayload,
  RestartGamePayload, ReturnToRoomPayload, ResumeSessionPayload,
  SelectCharacterPayload, SendEmotePayload, UseItemPayload,
  validateNickname, validateRoomCode, validateCardIndexes
} from '../model/Protocol'

// 生成 UUID (用于 requestId)
function generateUUID(): string {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c: string): string => {
    const r: number = Math.random() * 16 | 0
    const v: number = c === 'x' ? r : (r & 0x3 | 0x8)
    return v.toString(16)
  })
}

export class SocketManager {
  private socket: Socket | null = null
  private store: SessionStore
  private serverUrl: string = ''
  private pendingRequests: Map<string, (ack: Ack<any>) => void> = new Map()

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
    this.socket.on(SERVER_EVENTS.ROOM_STATE, (room: RoomView) => {
      this.store.updateRoom(room)
    })

    this.socket.on(SERVER_EVENTS.ROOM_CLOSED, () => {
      this.store.leaveRoom()
      this.store.setNotice('房间已关闭')
    })

    this.socket.on(SERVER_EVENTS.ROOM_PLAYER_JOINED, (event: RoomPlayerEvent) => {
      // 玩家加入通知，room:state 会携带最新房间状态
    })

    this.socket.on(SERVER_EVENTS.ROOM_PLAYER_LEFT, (event: RoomPlayerEvent) => {
      // 玩家离开通知
    })

    this.socket.on(SERVER_EVENTS.ROOM_KICKED, (message: string) => {
      this.store.leaveRoom()
      this.store.setNotice(message)
    })

    this.socket.on(SERVER_EVENTS.SESSION_REPLACED, (message: string) => {
      this.store.setNotice(message)
    })

    // 游戏事件
    this.socket.on(SERVER_EVENTS.GAME_SNAPSHOT, (state: GameSnapshot) => {
      this.store.setGame(state)
    })

    this.socket.on(SERVER_EVENTS.GAME_CUE, (cue: GameCue) => {
      this.handleGameCue(cue)
    })

    this.socket.on(SERVER_EVENTS.GAME_STATE, (state: GameSnapshot) => {
      this.store.setGame(state)
    })

    this.socket.on(SERVER_EVENTS.GAME_TURN_STARTED, (state: GameSnapshot) => {
      this.store.setGame(state)
    })

    this.socket.on(SERVER_EVENTS.GAME_CARDS_PLAYED, (event: any) => {
      // 出牌通知
    })

    this.socket.on(SERVER_EVENTS.GAME_CHALLENGE_STARTED, (event: any) => {
      // 质疑开始通知
    })

    this.socket.on(SERVER_EVENTS.GAME_CHALLENGE_RESULT, (state: GameSnapshot) => {
      this.store.setGame(state)
    })

    this.socket.on(SERVER_EVENTS.GAME_PUNISHMENT_STARTED, (event: any) => {
      // 惩罚开始通知
    })

    this.socket.on(SERVER_EVENTS.GAME_PUNISHMENT_RESULT, (state: GameSnapshot) => {
      this.store.setGame(state)
    })

    this.socket.on(SERVER_EVENTS.GAME_PLAYER_ELIMINATED, (event: any) => {
      // 玩家淘汰通知
    })

    this.socket.on(SERVER_EVENTS.GAME_OVER, (state: GameSnapshot) => {
      this.store.setGame(state)
    })

    this.socket.on(SERVER_EVENTS.GAME_EMOTE, (event: any) => {
      // 表情通知
    })
  }

  // ====== 游戏事件提示处理 ======

  private handleGameCue(cue: GameCue): void {
    // 根据 cue.type 触发音效或 UI 反馈
    // 后续与 AudioManager 集成
  }

  // ====== 会话恢复 ======

  private tryResumeSession(): void {
    if (!this.socket || !this.store.sessionToken) return

    const payload: ResumeSessionPayload = {
      sessionToken: this.store.sessionToken
    }

    this.socket.emit(CLIENT_EVENTS.SESSION_RESUME, payload, (result: Ack<SessionResumeResult>) => {
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
      callback?.(false, '昵称无效')
      return
    }

    const payload: CreateRoomPayload = { nickname: nickname.trim() }

    this.socket.emit(CLIENT_EVENTS.ROOM_CREATE, payload, (result: Ack<RoomMembership>) => {
      if (result.ok) {
        const data = result.data as RoomMembership
        this.store.enterRoom(data.room, data.playerId, data.sessionToken)
        callback?.(true)
      } else {
        const error = result.error as any
        callback?.(false, error?.message ?? '创建房间失败')
      }
    })
  }

  // 加入房间
  joinRoom(nickname: string, roomCode: string, callback?: (success: boolean, error?: string) => void): void {
    if (!this.socket || !validateNickname(nickname)) {
      callback?.(false, '昵称无效')
      return
    }
    if (!validateRoomCode(roomCode)) {
      callback?.(false, '房间码无效')
      return
    }

    const payload: JoinRoomPayload = {
      nickname: nickname.trim(),
      roomCode: roomCode.trim().toUpperCase()
    }

    this.socket.emit(CLIENT_EVENTS.ROOM_JOIN, payload, (result: Ack<RoomMembership>) => {
      if (result.ok) {
        const data = result.data as RoomMembership
        this.store.enterRoom(data.room, data.playerId, data.sessionToken)
        callback?.(true)
      } else {
        const error = result.error as any
        callback?.(false, error?.message ?? '加入房间失败')
      }
    })
  }

  // 离开房间
  leaveRoom(callback?: (success: boolean) => void): void {
    if (!this.socket || !this.store.room) {
      callback?.(false)
      return
    }

    const payload: LeaveRoomPayload = { roomCode: this.store.room.code }

    this.socket.emit(CLIENT_EVENTS.ROOM_LEAVE, payload, () => {
      this.store.leaveRoom()
      callback?.(true)
    })
  }

  // 准备/取消准备
  setReady(ready: boolean, callback?: (success: boolean) => void): void {
    if (!this.socket || !this.store.room) {
      callback?.(false)
      return
    }

    const payload: ReadyRoomPayload = {
      roomCode: this.store.room.code,
      ready: ready,
      requestId: generateUUID()
    }

    this.socket.emit(CLIENT_EVENTS.ROOM_READY, payload, (result: Ack<RoomView>) => {
      if (result.ok) {
        this.store.updateRoom(result.data as RoomView)
        callback?.(true)
      } else {
        callback?.(false)
      }
    })
  }

  // 更新房间设置
  updateSettings(maxPlayers: number, gameMode: string, callback?: (success: boolean) => void): void {
    if (!this.socket || !this.store.room) {
      callback?.(false)
      return
    }

    const payload: UpdateRoomSettingsPayload = {
      roomCode: this.store.room.code,
      maxPlayers: maxPlayers,
      gameMode: gameMode as any,
      requestId: generateUUID()
    }

    this.socket.emit(CLIENT_EVENTS.ROOM_UPDATE_SETTINGS, payload, (result: Ack<RoomView>) => {
      if (result.ok) {
        this.store.updateRoom(result.data as RoomView)
        callback?.(true)
      } else {
        callback?.(false)
      }
    })
  }

  // 踢出玩家
  kickPlayer(targetPlayerId: string, callback?: (success: boolean) => void): void {
    if (!this.socket || !this.store.room) {
      callback?.(false)
      return
    }

    const payload: KickPlayerPayload = {
      roomCode: this.store.room.code,
      targetPlayerId: targetPlayerId,
      requestId: generateUUID()
    }

    this.socket.emit(CLIENT_EVENTS.ROOM_KICK, payload, (result: Ack<RoomView>) => {
      if (result.ok) {
        this.store.updateRoom(result.data as RoomView)
        callback?.(true)
      } else {
        callback?.(false)
      }
    })
  }

  // 选择角色
  selectCharacter(characterId: string, callback?: (success: boolean) => void): void {
    if (!this.socket || !this.store.room) {
      callback?.(false)
      return
    }

    const payload: SelectCharacterPayload = {
      roomCode: this.store.room.code,
      characterId: characterId as any
    }

    this.socket.emit(CLIENT_EVENTS.ROOM_SELECT_CHARACTER, payload, (result: Ack<RoomView>) => {
      if (result.ok) {
        this.store.updateRoom(result.data as RoomView)
        callback?.(true)
      } else {
        callback?.(false)
      }
    })
  }

  // 开始游戏
  startGame(callback?: (success: boolean, error?: string) => void): void {
    if (!this.socket || !this.store.room) {
      callback?.(false, '未在房间中')
      return
    }

    const payload: StartGamePayload = {
      roomCode: this.store.room.code,
      requestId: generateUUID()
    }

    this.socket.emit(CLIENT_EVENTS.GAME_START, payload, (result: Ack<GameSnapshot>) => {
      if (result.ok) {
        this.store.setGame(result.data as GameSnapshot)
        callback?.(true)
      } else {
        const error = result.error as any
        callback?.(false, error?.message ?? '开始游戏失败')
      }
    })
  }

  // 出牌
  playCards(cardIndexes: number[], callback?: (success: boolean, error?: string) => void): void {
    if (!this.socket || !this.store.room) {
      callback?.(false, '未在房间中')
      return
    }
    if (!validateCardIndexes(cardIndexes)) {
      callback?.(false, '选牌无效')
      return
    }

    const payload: PlayCardsPayload = {
      roomCode: this.store.room.code,
      cardIndexes: cardIndexes,
      requestId: generateUUID()
    }

    this.socket.emit(CLIENT_EVENTS.GAME_PLAY_CARDS, payload, (result: Ack<GameSnapshot>) => {
      if (result.ok) {
        this.store.setGame(result.data as GameSnapshot)
        callback?.(true)
      } else {
        const error = result.error as any
        callback?.(false, error?.message ?? '出牌失败')
      }
    })
  }

  // 质疑
  challenge(callback?: (success: boolean, error?: string) => void): void {
    if (!this.socket || !this.store.room) {
      callback?.(false, '未在房间中')
      return
    }

    const payload: ChallengePayload = {
      roomCode: this.store.room.code,
      requestId: generateUUID()
    }

    this.socket.emit(CLIENT_EVENTS.GAME_CHALLENGE, payload, (result: Ack<GameSnapshot>) => {
      if (result.ok) {
        this.store.setGame(result.data as GameSnapshot)
        callback?.(true)
      } else {
        const error = result.error as any
        callback?.(false, error?.message ?? '质疑失败')
      }
    })
  }

  // 重新开始
  restartGame(callback?: (success: boolean) => void): void {
    if (!this.socket || !this.store.room) {
      callback?.(false)
      return
    }

    const payload: RestartGamePayload = {
      roomCode: this.store.room.code,
      requestId: generateUUID()
    }

    this.socket.emit(CLIENT_EVENTS.GAME_RESTART, payload, (result: Ack<GameSnapshot>) => {
      if (result.ok) {
        this.store.setGame(result.data as GameSnapshot)
        callback?.(true)
      } else {
        callback?.(false)
      }
    })
  }

  // 返回大厅
  returnToRoom(callback?: (success: boolean) => void): void {
    if (!this.socket || !this.store.room) {
      callback?.(false)
      return
    }

    const payload: ReturnToRoomPayload = {
      roomCode: this.store.room.code,
      requestId: generateUUID()
    }

    this.socket.emit(CLIENT_EVENTS.GAME_RETURN_TO_ROOM, payload, (result: Ack<RoomView>) => {
      if (result.ok) {
        this.store.clearGame()
        this.store.updateRoom(result.data as RoomView)
        callback?.(true)
      } else {
        callback?.(false)
      }
    })
  }

  // 发送表情
  sendEmote(emoteId: string): void {
    if (!this.socket || !this.store.room) return

    const payload: SendEmotePayload = {
      roomCode: this.store.room.code,
      emoteId: emoteId as any
    }

    this.socket.emit(CLIENT_EVENTS.GAME_SEND_EMOTE, payload)
  }
}
