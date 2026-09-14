// 会话状态管理 - 对应 session-store.ts
// 使用 @ObservedV2 + @Trace 实现响应式状态

import { ConnectionStatus, RoomView, GameSnapshot } from '../model/GameTypes'

@ObservedV2
export class SessionStore {
  // 连接状态
  @Trace connection: ConnectionStatus = 'connecting'

  // 网络在线状态
  @Trace networkOnline: boolean = true

  // 当前房间视图
  @Trace room: RoomView | null = null

  // 当前玩家ID
  @Trace playerId: string | null = null

  // 会话恢复令牌
  @Trace sessionToken: string | null = null

  // 通知消息
  @Trace notice: string | null = null

  // 当前游戏视图
  @Trace game: GameSnapshot | null = null

  // 服务器时间偏移（用于倒计时计算）
  @Trace serverTimeOffset: number = 0

  // 低性能模式
  @Trace lowPowerActive: boolean = false

  // 动画偏好
  @Trace motionPreference: string = 'system' // 'system' | 'full' | 'reduced'

  // ====== 操作方法 ======

  setConnection(connection: ConnectionStatus): void {
    this.connection = connection
  }

  setNetworkOnline(networkOnline: boolean): void {
    this.networkOnline = networkOnline
  }

  enterRoom(room: RoomView, playerId: string, sessionToken: string): void {
    this.room = room
    this.playerId = playerId
    this.sessionToken = sessionToken
    this.notice = null
  }

  updateRoom(room: RoomView): void {
    this.room = room
  }

  leaveRoom(): void {
    this.room = null
    this.playerId = null
    this.sessionToken = null
    this.game = null
  }

  setNotice(notice: string | null): void {
    this.notice = notice
  }

  setGame(game: GameSnapshot): void {
    // 更新服务器时间偏移
    if (game.serverNow > 0) {
      this.serverTimeOffset = game.serverNow - Date.now()
    }
    this.game = game
  }

  clearGame(): void {
    this.game = null
  }

  // ====== 计算属性 ======

  // 当前屏幕路由（替代 React 条件渲染）
  get currentScreen(): string {
    if (this.room !== null && this.game !== null && this.room.status !== 'LOBBY') {
      return 'game'
    } else if (this.room !== null) {
      return 'lobby'
    } else {
      return 'home'
    }
  }

  // 是否是房主
  get isHost(): boolean {
    return this.playerId !== null && this.room !== null && this.room.hostPlayerId === this.playerId
  }

  // 当前玩家是否轮到出牌
  get isMyTurn(): boolean {
    return this.game !== null &&
      this.game.turnPlayerId !== null &&
      this.game.turnPlayerId === this.playerId
  }

  // 是否可以质疑
  get canChallenge(): boolean {
    return this.isMyTurn && this.game !== null && this.game.lastPlay !== null
  }

  // 是否必须质疑（上家出完手牌）
  get mustChallenge(): boolean {
    return this.game !== null && this.game.mustChallenge && this.isMyTurn
  }

  // 计算当前阶段剩余时间（毫秒）
  getPhaseRemainingMs(): number {
    if (this.game === null || this.game.phaseEndsAt === null) return 0
    const serverNow = Date.now() + this.serverTimeOffset
    return Math.max(0, this.game.phaseEndsAt - serverNow)
  }

  // 计算回合剩余时间（秒）
  getTurnRemainingSeconds(): number {
    if (this.game === null) return 0
    const remainingMs = this.getPhaseRemainingMs()
    return Math.ceil(remainingMs / 1000)
  }
}
