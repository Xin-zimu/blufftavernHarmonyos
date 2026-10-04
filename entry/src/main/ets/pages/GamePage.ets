// 游戏主页面 - 对应网页版 7.2 GameScreen.tsx
// 相位时钟驱动的酒馆桌面：模式规则/事件横幅/自由质疑窗口/共享左轮/道具栏/演出层/结算面板
// 关键：同步时钟 syncedNow = tick + serverTimeOffset；相位超时触发权威重同步

import { SessionStore, globalSessionStore } from '../store/SessionStore'
import { SessionPersistence } from '../store/SessionPersistence'
import { SocketManager } from '../net/SocketManager'
import { AudioManager } from '../audio/AudioManager'
import { router, window } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { pasteboard } from '@kit.BasicServicesKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { BusinessError } from '@kit.BasicServicesKit'
import {
  GameSnapshot, PublicPlayerState, CardRank,
  PublicPunishmentState, ItemId, ActiveItemId
} from '../model/GameTypes'
import { CHARACTER_NAMES, ITEM_NAMES } from '../model/Constants'
import { getItemImage, getCharacterImage } from '../utils/ArtResources'
import { TargetHUD } from '../components/TargetHUD'
import { PlayerSeat } from '../components/PlayerSeat'
import { CardHand } from '../components/CardHand'
import { PublicCardArea } from '../components/PublicCardArea'
import { RevolverDisplay } from '../components/RevolverDisplay'
import { RulesPanel } from '../components/RulesPanel'
import { CinematicOverlay } from '../components/CinematicOverlay'

// 座位信息（合并房间成员与游戏公开状态，自己排在最后，与网页版一致）
class SeatInfo {
  player: PublicPlayerState = new PublicPlayerState()
  characterId: string = ''
  isMe: boolean = false
  isCurrentTurn: boolean = false
  newlyEliminated: boolean = false
}

// 揭牌相位（与网页版 TABLE_REVEAL_PHASES 一致）
const TABLE_REVEAL_PHASES: string[] = ['VERDICT', 'PUNISHMENT_INTRO', 'PUNISHMENT_TRIGGER', 'PUNISHMENT_RESULT', 'ROUND_END']
// 相位超时宽限：超时 2 秒仍未收到新相位则请求重同步（网页版 RESYNC_GRACE_MS）
const RESYNC_GRACE_MS: number = 2000

@Entry
@ComponentV2
struct GamePage {
  // SessionStore 为 @ObservedV2 类，用 @Local 持有以获得 V2 观察能力
  @Local store: SessionStore = globalSessionStore
  // 服务对象无需响应式，aboutToAppear 时从 AppStorage 取回全局实例
  socketManager: SocketManager = new SocketManager(new SessionStore(), new SessionPersistence())
  audioManager: AudioManager | null = null
  @Local selectedCardIndexes: number[] = []
  @Local showRules: boolean = false
  @Local dismissedTip: boolean = false
  @Local audioEnabled: boolean = true
  @Local shareNotice: string = ''
  @Local immersive: boolean = false
  // 相位时钟 tick（100ms 刷新，驱动 secondsLeft / 质疑窗口倒计时 / 演出进度）
  @Local tick: number = 0
  private timerId: number = -1
  private isTop: boolean = true
  private backGuard: boolean = false
  private exitGuard: boolean = false
  // 选牌作用域（变化时清空选牌，与网页版 selectionScope 一致）
  private lastPhase: string = ''
  private lastTurnPlayerId: string = ''
  private lastRoundNumber: number = -1
  private lastHandKey: string = ''
  // 音效去重：同 sequence 只播一次
  private playedAudioSequence: number = -1
  private presentationEpoch: number = -1

  aboutToAppear(): void {
    const sm: SocketManager | undefined = AppStorage.get<SocketManager>('socketManager')
    if (sm !== undefined) {
      this.socketManager = sm
    }
    const am: AudioManager | undefined = AppStorage.get<AudioManager>('audioManager')
    if (am !== undefined) {
      this.audioManager = am
    }
    this.tick = Date.now()
    this.audioEnabled = this.audioManager === null ? true : this.audioManager.isEnabled()
    this.startClock()
  }

  aboutToDisappear(): void {
    this.stopClock()
    if (this.immersive) this.setImmersive(false)
  }

  onPageShow(): void {
    this.isTop = true
  }

  onPageHide(): void {
    this.isTop = false
  }

  // 房间状态驱动的导航：返回大厅时退回大厅页；被踢/房间关闭时回首页
  @Monitor('store.room')
  onRoomChange(monitor: IMonitor): void {
    const room = this.store.room
    if (room === null) {
      if (!this.isTop || this.exitGuard) {
        return
      }
      this.exitGuard = true
      hilog.info(0xFF00, 'GamePage', 'go home')
      router.clear()
      router.replaceUrl({ url: 'pages/HomePage' })
        .catch((error: BusinessError) => {
          hilog.error(0xFF00, 'GamePage', `go home rejected: ${error.message}`)
        })
      return
    }
    if (room.status === 'LOBBY') {
      if (!this.isTop || this.backGuard) {
        return
      }
      this.backGuard = true
      hilog.info(0xFF00, 'GamePage', 'back to lobby')
      // 栈里没有 LobbyPage（如会话恢复后 Home→Game 直达）时，back() 会错误落回 HomePage；
      // 此时用 replaceUrl 直接落到 LobbyPage，保证回大厅语义
      if (Number(router.getLength()) >= 3) {
        router.back()
      } else {
        router.replaceUrl({ url: 'pages/LobbyPage' })
          .catch((error: BusinessError) => {
            hilog.error(0xFF00, 'GamePage', `replaceUrl lobby rejected: ${error.message}`)
          })
      }
      return
    }
    this.backGuard = false
  }

  // 快照变化：清空过期选牌 + 播放相位音效（sequence 去重）
  @Monitor('store.game')
  onGameChange(monitor: IMonitor): void {
    if (this.presentationEpoch !== this.store.gameEpoch) {
      this.presentationEpoch = this.store.gameEpoch
      this.selectedCardIndexes = []
      this.playedAudioSequence = -1
      this.lastPhase = ''
      this.lastTurnPlayerId = ''
      this.lastRoundNumber = -1
      this.lastHandKey = ''
      this.showRules = false
      this.shareNotice = ''
    }
    const game: GameSnapshot | null = this.store.game
    if (game === null) {
      this.selectedCardIndexes = []
      return
    }

    // 相位音效
    if (game.sequence !== this.playedAudioSequence) {
      this.playedAudioSequence = game.sequence
      this.playPhaseSound(game)
    }

    // 选牌作用域检测（与网页版一致：相位/回合人/轮次/手牌任一变化即清空）
    const handKey: string = game.hand.join('|')
    const scopeChanged: boolean = this.lastPhase !== game.phase ||
      this.lastTurnPlayerId !== (game.turnPlayerId ?? '') ||
      this.lastRoundNumber !== game.roundNumber ||
      this.lastHandKey !== handKey
    this.lastPhase = game.phase
    this.lastTurnPlayerId = game.turnPlayerId ?? ''
    this.lastRoundNumber = game.roundNumber
    this.lastHandKey = handKey
    const isMyTurnNow: boolean = game.turnPlayerId === this.store.playerId
    if (scopeChanged || game.phase !== 'TURN' || !isMyTurnNow) {
      this.selectedCardIndexes = []
    }
  }

  private playPhaseSound(game: GameSnapshot): void {
    if (this.audioManager === null || !this.audioEnabled) {
      return
    }
    if (game.phase === 'MATCH_START' || game.phase === 'ROUND_START') {
      this.audioManager.playRoundStart()
    } else if (game.phase === 'CHALLENGE_CALLOUT') {
      this.audioManager.playChallenge()
    } else if (game.phase === 'REVEAL') {
      this.audioManager.playReveal()
    } else if (game.phase === 'VERDICT') {
      this.audioManager.playVerdict(game.challenge?.wasBluff === true)
    } else if (game.phase === 'PUNISHMENT_INTRO') {
      this.audioManager.playRevolverSpin()
    } else if (game.phase === 'PUNISHMENT_TRIGGER') {
      this.audioManager.playTriggerClick()
    } else if (game.phase === 'PUNISHMENT_RESULT') {
      if (game.punishment !== null && game.punishment.hit) {
        this.audioManager.playGunshot()
      } else {
        this.audioManager.playEmptyClick()
      }
    } else if (game.phase === 'GAME_OVER') {
      this.audioManager.playVictory()
    }
  }

  // ====== 相位时钟 ======

  private startClock(): void {
    this.stopClock()
    this.timerId = setInterval(() => {
      this.tick = Date.now()
      this.checkPhaseResync()
    }, this.store.lowPowerActive ? 250 : 100)
  }

  private stopClock(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId)
      this.timerId = -1
    }
  }

  // 服务器同步时钟
  private getSyncedNow(): number {
    return this.tick + this.store.serverTimeOffset
  }

  // 相位剩余秒数（无截止时间返回 -1 表示不显示）
  private getSecondsLeft(): number {
    const game: GameSnapshot | null = this.store.game
    if (game === null || game.phaseEndsAt === null) {
      return -1
    }
    const remainMs: number = game.phaseEndsAt - this.getSyncedNow()
    const seconds: number = Math.ceil(remainMs / 1000)
    return seconds > 0 ? seconds : 0
  }

  // 相位超时重同步（500ms 粒度检查；SocketManager 内部 4 秒节流）
  private checkPhaseResync(): void {
    const game: GameSnapshot | null = this.store.game
    if (game === null || game.phaseEndsAt === null) {
      return
    }
    if (this.getSyncedNow() > game.phaseEndsAt + RESYNC_GRACE_MS) {
      this.socketManager.requestAuthoritativeResync()
    }
  }

  // ====== 状态判定 ======

  private getGame(): GameSnapshot | null {
    return this.store.game
  }

  private isTurn(): boolean {
    const game: GameSnapshot | null = this.store.game
    return game !== null && game.turnPlayerId === this.store.playerId && game.phase === 'TURN'
  }

  private canPlay(): boolean {
    return this.isTurn() && !this.store.mustChallenge
  }

  private canSubmitPlay(): boolean {
    const game: GameSnapshot | null = this.store.game
    if (game === null || !this.canPlay()) {
      return false
    }
    return this.selectedCardIndexes.length >= game.minimumPlayCount &&
      this.selectedCardIndexes.length <= game.maximumPlayCount
  }

  private canFreeChallenge(): boolean {
    const game: GameSnapshot | null = this.store.game
    if (game === null || game.phase !== 'CHALLENGE_WINDOW' || game.lastPlay === null) {
      return false
    }
    if (this.store.playerId === null || game.lastPlay.playerId === this.store.playerId) {
      return false
    }
    for (const id of game.alivePlayerIds) {
      if (id === this.store.playerId) {
        return true
      }
    }
    return false
  }

  private canChallengeInTurn(): boolean {
    const game: GameSnapshot | null = this.store.game
    return this.isTurn() && game !== null && game.lastPlay !== null && game.gameMode !== 'FREE_CHALLENGE'
  }

  private isGameOver(): boolean {
    const game: GameSnapshot | null = this.store.game
    return game !== null && game.phase === 'GAME_OVER'
  }

  private isTableRevealPhase(): boolean {
    const game: GameSnapshot | null = this.store.game
    if (game === null) {
      return false
    }
    for (const phase of TABLE_REVEAL_PHASES) {
      if (phase === game.phase) {
        return true
      }
    }
    return false
  }

  // ====== 文案（对齐网页版 7.2 GameScreen.tsx） ======

  private getModeName(): string {
    const game: GameSnapshot | null = this.store.game
    if (game === null) {
      return '经典'
    }
    if (game.gameMode === 'QUICK') {
      return '快速'
    }
    if (game.gameMode === 'PARTY') {
      return '乱斗'
    }
    if (game.gameMode === 'FREE_CHALLENGE') {
      return '全民质疑'
    }
    if (game.gameMode === 'SHARED_REVOLVER') {
      return '死亡左轮'
    }
    if (game.gameMode === 'ESCALATION') {
      return '加注'
    }
    return '经典'
  }

  private getTurnInstruction(): string {
    const game: GameSnapshot | null = this.store.game
    if (game === null) {
      return ''
    }
    if (game.minimumPlayCount === game.maximumPlayCount) {
      return `你的回合：请选择 ${game.minimumPlayCount} 张牌`
    }
    if (game.minimumPlayCount > 1) {
      return `你的回合：选择 ${game.minimumPlayCount} 至 ${game.maximumPlayCount} 张牌`
    }
    return `你的回合：选择 1 至 ${game.maximumPlayCount} 张牌`
  }

  private getPlayerNameById(id: string | null): string {
    const room = this.store.room
    if (id === null || id === '' || room === null) {
      return '玩家'
    }
    for (const player of room.players) {
      if (player.id === id) {
        return player.nickname
      }
    }
    return '玩家'
  }

  // 当前回合玩家名
  private getCurrentPlayerName(): string {
    const game: GameSnapshot | null = this.store.game
    if (game === null) {
      return '玩家'
    }
    return this.getPlayerNameById(game.turnPlayerId)
  }

  // 上一位出牌者名
  private getLastPlayerName(): string {
    const game: GameSnapshot | null = this.store.game
    if (game === null || game.lastPlay === null) {
      return '玩家'
    }
    return this.getPlayerNameById(game.lastPlay.playerId)
  }

  // 牌桌状态行（与网页版 describeMatchStatus 一致）
  private getMatchStatus(): string {
    const game: GameSnapshot | null = this.store.game
    if (game === null) {
      return '牌局演出中'
    }
    const currentPlayer: string = this.getCurrentPlayerName()
    const lastPlayer: string = this.getLastPlayerName()
    if (game.phase === 'GAME_OVER') {
      return '本局结束'
    }
    if (game.phase === 'ROUND_START') {
      return `第 ${game.roundNumber} 轮开始，目标牌 ${game.targetCard}`
    }
    if (game.phase === 'TURN') {
      if (game.mustChallenge) {
        return `${currentPlayer} 必须质疑上一手`
      }
      if (game.lastPlay !== null && game.lastPlay.count === null) {
        return `${lastPlayer} 已下注，等待 ${currentPlayer} 行动`
      }
      if (game.minimumPlayCount === game.maximumPlayCount && game.lastPlay !== null) {
        return `${lastPlayer} 已出 ${game.lastPlay.count} 张，${currentPlayer} 必须出 ${game.minimumPlayCount} 张或质疑`
      }
      if (game.gameMode === 'PARTY' && game.tavernEvent !== null && game.tavernEvent.type === 'FORCED_BET' && game.lastPlay !== null) {
        return `${lastPlayer} 已出 ${game.lastPlay.count} 张，${currentPlayer} 至少出 ${game.minimumPlayCount} 张或质疑`
      }
      if (game.gameMode === 'ESCALATION' && game.lastPlay !== null) {
        return `${lastPlayer} 已出 ${game.lastPlay.count} 张，${currentPlayer} 至少出 ${game.minimumPlayCount} 张或质疑`
      }
      if (game.lastPlay !== null) {
        return `${lastPlayer} 已出 ${game.lastPlay.count} 张，等待 ${currentPlayer} 行动`
      }
      return `等待 ${currentPlayer} 出牌`
    }
    if (game.phase === 'CHALLENGE_WINDOW') {
      return '全民质疑窗口开启，等待抢先质疑'
    }
    if (game.phase === 'CHALLENGE_CALLOUT') {
      return '质疑发起，所有操作已锁定'
    }
    if (game.phase === 'REVEAL') {
      if (game.tavernEvent !== null && game.tavernEvent.type === 'CANDLE_FLICKER') {
        return '烛火摇曳，正在逐张揭牌'
      }
      return '正在逐张揭牌'
    }
    if (game.phase === 'VERDICT') {
      if (game.challenge !== null && game.challenge.wasBluff === true) {
        return '质疑成功，谎言成立'
      }
      return '质疑失败，声明成立'
    }
    if (game.phase === 'PUNISHMENT_INTRO' || game.phase === 'PUNISHMENT_TRIGGER' || game.phase === 'PUNISHMENT_RESULT') {
      if (game.tavernEvent !== null && game.tavernEvent.type === 'DOUBLE_DANGER') {
        return '双倍危机下执行惩罚'
      }
      return '正在执行惩罚'
    }
    if (game.phase === 'ROUND_END') {
      return '本轮结算中'
    }
    return '牌局演出中'
  }

  // Party 事件规则行（与网页版 describePartyEventRule 一致）
  private getPartyEventRule(): string {
    const game: GameSnapshot | null = this.store.game
    if (game === null || game.tavernEvent === null) {
      return ''
    }
    const secondsLeft: number = this.getSecondsLeft()
    const suffix: string = secondsLeft >= 0 ? `，剩余 ${secondsLeft} 秒` : ''
    if (game.tavernEvent.type === 'ONE_CARD_ONLY') {
      return '单张夜：请选择 1 张'
    }
    if (game.tavernEvent.type === 'MATCH_BET') {
      if (game.minimumPlayCount === game.maximumPlayCount) {
        return `跟注夜：必须出 ${game.minimumPlayCount} 张`
      }
      return '跟注夜：第一手决定张数'
    }
    if (game.tavernEvent.type === 'HEAVY_HAND') {
      return '豪饮之夜：至少出 2 张'
    }
    if (game.tavernEvent.type === 'LAST_CALL') {
      return `最后点单：本回合 ${game.turnDurationSeconds} 秒${suffix}`
    }
    if (game.tavernEvent.type === 'NO_JOKER') {
      return '禁忌小丑：Joker 本轮按假牌判定'
    }
    if (game.tavernEvent.type === 'FORCED_BET') {
      return `强制豪赌：本次至少出 ${game.minimumPlayCount} 张`
    }
    if (game.tavernEvent.type === 'DRUNKEN') {
      return '醉酒之夜：本轮出牌方向反转'
    }
    if (game.tavernEvent.type === 'RAPID_NIGHT') {
      return `快速夜：本轮每人 ${game.turnDurationSeconds} 秒`
    }
    if (game.tavernEvent.type === 'DOUBLE_DANGER') {
      return '双倍危机：受罚者最多连续开两枪'
    }
    if (game.tavernEvent.type === 'HIDDEN_BET') {
      return '暗注夜：他人的手牌数与下注数量暂时隐藏'
    }
    return ''
  }

  // 模式规则胶囊（与网页版 describeModeRule 一致）
  private getModeRule(): string {
    const game: GameSnapshot | null = this.store.game
    if (game === null) {
      return ''
    }
    if (game.phase === 'CHALLENGE_WINDOW') {
      const secondsLeft: number = this.getSecondsLeft()
      const suffix: string = secondsLeft >= 0 ? `，剩余 ${secondsLeft} 秒` : ''
      return `全民质疑：所有其他存活玩家可抢先质疑${suffix}`
    }
    if (game.gameMode === 'ESCALATION' && game.phase === 'TURN') {
      return `加注模式：本次至少出 ${game.minimumPlayCount} 张`
    }
    if (game.gameMode === 'PARTY') {
      return this.getPartyEventRule()
    }
    return ''
  }

  // 新手提示（与网页版 describeNewPlayerHint 一致，无本地持久化）
  private getNewPlayerHint(): string {
    if (this.dismissedTip || this.isGameOver()) {
      return ''
    }
    const game: GameSnapshot | null = this.store.game
    if (game === null) {
      return ''
    }
    if (game.phase === 'ROUND_START') {
      return `本轮目标是 ${game.targetCard}。你可以出任意牌，但声明都会按 ${game.targetCard} 处理。`
    }
    if (this.isTurn() && game.gameMode === 'ESCALATION' && game.lastPlay !== null) {
      return `加注模式：这手至少出 ${game.minimumPlayCount} 张，也可以质疑上一手。`
    }
    if (game.gameMode === 'FREE_CHALLENGE' && game.phase === 'CHALLENGE_WINDOW') {
      return '全民质疑：不是出牌者的存活玩家都可以抢先质疑。'
    }
    if (game.gameMode === 'SHARED_REVOLVER' && game.sharedRevolver !== null) {
      return '死亡左轮：全桌共用一把枪，连续空膛会保留到下一次惩罚。'
    }
    if (game.gameMode === 'PARTY' && game.tavernEvent !== null) {
      return `${game.tavernEvent.title}：${game.tavernEvent.description}`
    }
    if (this.isTurn() && game.lastPlay === null) {
      return '选择 1 至 3 张手牌，然后点击出牌。真实牌面可以和目标牌不同。'
    }
    if (this.isTurn() && game.lastPlay !== null) {
      return '你可以相信上一手继续出牌，也可以质疑。质疑失败会由你受罚。'
    }
    if (game.phase === 'REVEAL') {
      return '质疑后会逐张揭示真实牌面，Joker 视为真实目标牌。'
    }
    return ''
  }

  // 惩罚备注（与网页版 describePunishmentNote 一致）
  private getPunishmentNote(): string {
    const game: GameSnapshot | null = this.store.game
    if (game === null || game.punishment === null) {
      return ''
    }
    const punishment: PublicPunishmentState = game.punishment
    const shotPrefix: string = punishment.totalShots > 1 ? `第 ${punishment.shotNumber}/${punishment.totalShots} 枪，` : ''
    let result: string
    if (punishment.hit) {
      result = '中弹淘汰'
    } else if (punishment.shotNumber < punishment.totalShots) {
      result = '空枪，还需再开一枪'
    } else {
      result = '空枪，继续游戏'
    }
    return `${shotPrefix}轮盘第 ${punishment.chamber + 1} 弹巢：${result}。`
  }

  // 道具说明（与网页版 describeItem 一致）
  private getItemDescription(item: ActiveItemId): string {
    if (item === 'SPYGLASS') {
      return '查看自己下一次受罚风险'
    }
    if (item === 'POCKET_WATCH') {
      return '自己的回合延长倒计时'
    }
    return '短暂干扰自己的界面提示，不改变判定'
  }

  // 道具可用性（与网页版 canUseItem 一致）
  private canUseItem(item: ActiveItemId): boolean {
    const game: GameSnapshot | null = this.store.game
    if (game === null || this.store.playerId === null || game.phase !== 'TURN') {
      return false
    }
    let alive: boolean = false
    for (const id of game.alivePlayerIds) {
      if (id === this.store.playerId) {
        alive = true
        break
      }
    }
    if (!alive) {
      return false
    }
    if (item === 'POCKET_WATCH') {
      return game.turnPlayerId === this.store.playerId
    }
    return true
  }

  private getItemName(item: ActiveItemId): string {
    const name: string | undefined = ITEM_NAMES.get(item)
    return name !== undefined ? name : item
  }

  // 弃牌数文案
  private getDiscardText(): string {
    const game: GameSnapshot | null = this.store.game
    if (game === null) {
      return '已出 0 张'
    }
    if (game.discardCount === null) {
      return '已出数量暂时隐藏'
    }
    return `已出 ${game.discardCount} 张`
  }

  // ====== 座位构建 ======

  private buildSeats(): SeatInfo[] {
    const room = this.store.room
    const game: GameSnapshot | null = this.store.game
    const seats: SeatInfo[] = []
    if (room === null) {
      return seats
    }
    let selfSeat: SeatInfo | null = null
    for (const member of room.players) {
      const seat: SeatInfo = new SeatInfo()
      const state: PublicPlayerState = new PublicPlayerState()
      state.playerId = member.id
      state.name = member.nickname
      state.connected = member.isConnected
      state.alive = true
      if (game !== null) {
        for (const gp of game.players) {
          if (gp.playerId === member.id) {
            state.cardCount = gp.cardCount
            state.handCount = gp.handCount
            break
          }
        }
        for (const id of game.alivePlayerIds) {
          if (id === member.id) {
            state.alive = true
            break
          }
          state.alive = false
        }
      }
      seat.player = state
      seat.characterId = member.characterId !== null ? member.characterId : ''
      seat.isMe = member.id === this.store.playerId
      seat.isCurrentTurn = game !== null && game.turnPlayerId === member.id
      seat.newlyEliminated = game !== null && game.punishment !== null &&
        game.punishment.eliminatedPlayerId === member.id
      if (seat.isMe) {
        selfSeat = seat
      } else {
        seats.push(seat)
      }
    }
    if (selfSeat !== null) {
      seats.push(selfSeat)
    }
    return seats
  }

  // ====== 交互 ======

  // 选牌切换（数量上限按快照 maximumPlayCount）
  private toggleCardSelection(index: number): void {
    const game: GameSnapshot | null = this.store.game
    const maxCount: number = game !== null ? game.maximumPlayCount : 3
    const pos = this.selectedCardIndexes.indexOf(index)
    if (pos >= 0) {
      const newArr: number[] = []
      for (const idx of this.selectedCardIndexes) {
        if (idx !== index) {
          newArr.push(idx)
        }
      }
      this.selectedCardIndexes = newArr
    } else {
      if (this.selectedCardIndexes.length < maxCount) {
        const newArr: number[] = [...this.selectedCardIndexes, index]
        this.selectedCardIndexes = newArr
      }
    }
  }

  private submitPlay(): void {
    if (!this.canSubmitPlay()) {
      return
    }
    if (this.audioManager !== null && this.audioEnabled) {
      this.audioManager.playCardPlay()
    }
    this.socketManager.playCards([...this.selectedCardIndexes], (success: boolean) => {
      if (success) {
        this.selectedCardIndexes = []
      }
    })
  }

  private doChallenge(): void {
    if (this.audioManager !== null && this.audioEnabled) {
      this.audioManager.playButtonClick()
    }
    this.socketManager.challenge()
    this.selectedCardIndexes = []
  }

  private doUseItem(item: ActiveItemId): void {
    this.socketManager.useItem(item as ItemId)
  }

  private leaveWithConfirm(): void {
    AlertDialog.show({
      message: '确定退出当前房间？退出后本局将继续进行，你的位置会从房间中移除。',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '退出',
        fontColor: '#FF756D',
        action: () => {
          this.socketManager.leaveRoom()
        }
      }
    })
  }

  private doReturnToRoom(): void {
    this.socketManager.returnToRoom()
  }

  private toggleAudio(): void {
    this.audioEnabled = !this.audioEnabled
    if (this.audioManager !== null) {
      this.audioManager.setEnabled(this.audioEnabled)
    }
  }

  private toggleLowPower(): void {
    this.store.lowPowerActive = !this.store.lowPowerActive
    this.startClock()
  }

  private toggleReduceMotion(): void {
    this.store.motionPreference = this.store.reduceMotion ? 'full' : 'reduced'
  }

  private isReducedMotion(): boolean {
    return this.store.reduceMotion || this.store.lowPowerActive
  }

  private isTipsy(): boolean {
    const effect = this.store.game?.itemEffect
    return effect !== null && effect !== undefined && effect.type === 'TAVERN_MUG_TIPSY' &&
      (effect.expiresAt === null || effect.expiresAt > this.getSyncedNow())
  }

  private shareResult(): void {
    const summary = this.store.game?.summary
    if (summary === null || summary === undefined) return
    const text: string = `诡牌酒馆战报：${this.getPlayerNameById(summary.winnerId)} 获胜！${summary.playerCount} 人局，` +
      `${summary.durationSeconds} 秒，${summary.challengeCount} 次质疑，${summary.successfulChallenges} 次成功。` +
      `淘汰顺序：${this.getEliminationOrderText()}`
    const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      this.shareNotice = '战报已复制，可粘贴分享给好友'
    }).catch(() => {
      this.shareNotice = '复制失败，请重试'
    })
  }

  private setImmersive(enabled: boolean): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    window.getLastWindow(context).then(async (mainWindow: window.Window) => {
      await mainWindow.setWindowLayoutFullScreen(enabled)
      await mainWindow.setWindowSystemBarEnable(enabled ? [] : ['status', 'navigation'])
      await mainWindow.setPreferredOrientation(enabled ? window.Orientation.AUTO_ROTATION : window.Orientation.PORTRAIT)
      this.immersive = enabled
    }).catch(() => {
      this.store.setNotice('无法切换全屏，请重试')
    })
  }

  // 有玩家离线时显示重连提示
  private hasOfflinePlayer(): boolean {
    const room = this.store.room
    if (room === null) {
      return false
    }
    for (const player of room.players) {
      if (!player.isConnected) {
        return true
      }
    }
    return false
  }

  // 质疑窗口剩余秒（1 位小数）
  private getChallengeWindowRemaining(): string {
    const game: GameSnapshot | null = this.store.game
    if (game === null || game.freeChallenge === null) {
      return '0.0'
    }
    const remainMs: number = game.freeChallenge.endsAt - this.getSyncedNow()
    const seconds: number = remainMs > 0 ? remainMs / 1000 : 0
    return seconds.toFixed(1)
  }

  // 结算面板：淘汰顺序
  private getEliminationOrderText(): string {
    const game: GameSnapshot | null = this.store.game
    if (game === null || game.summary === null || game.summary.eliminationOrder.length === 0) {
      return '无人淘汰'
    }
    const names: string[] = []
    for (const id of game.summary.eliminationOrder) {
      names.push(this.getPlayerNameById(id))
    }
    return names.join(' → ')
  }

  private getWinnerCharacter(): string {
    if (this.store.room !== null) {
      for (const player of this.store.room.players) {
        if (player.id === this.store.game?.winnerId) return player.characterId ?? ''
      }
    }
    return ''
  }

  // 质疑结果行
  private getChallengeResultText(): string {
    const game: GameSnapshot | null = this.store.game
    if (game === null || game.challengeResult === null) {
      return ''
    }
    const cards: string[] = []
    for (const card of game.challengeResult.revealedCards) {
      cards.push(card)
    }
    const bluffText: string = game.challengeResult.wasBluff ? '上一位玩家撒谎' : '质疑失败'
    const failedName: string = this.getPlayerNameById(game.challengeResult.failedPlayerId)
    return `翻牌：${cards.join('、')}；${bluffText}，失败者：${failedName}`
  }

  // 牌桌公开牌（揭牌相位）
  private getTableRevealedCards(): CardRank[] {
    const game: GameSnapshot | null = this.store.game
    if (game === null || !this.isTableRevealPhase() || game.challenge === null || game.challenge.revealedCards === null) {
      return []
    }
    return game.challenge.revealedCards
  }

  // ====== build ======

  build() {
    Stack() {
      // 主游戏内容
      Scroll() {
        Column() {
          // 页眉：轮次/模式 + 标题 + 相位时钟/弃牌/规则/退出
          this.GameHeader()

          // 演出设置行（音效/性能/动画）
          this.CinematicControls()
          if (this.store.notice !== null) {
            Text(this.store.notice ?? '')
              .fontColor('#F2C777')
              .fontSize(12)
              .padding(8)
          }

          // 新手提示
          if (this.getNewPlayerHint().length > 0) {
            this.OnboardingTip()
          }

          // 酒馆事件横幅
          if (this.getGame() !== null && this.getGame()?.tavernEvent !== null) {
            this.TavernEventBanner()
          }
          // 回合横幅
          if (!this.isGameOver()) {
            this.TurnBanner()
          }

          // 模式规则胶囊
          if (this.getModeRule().length > 0) {
            Text(this.getModeRule())
              .fontSize(12)
              .fontColor('#D4A85D')
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .backgroundColor('#231713')
              .borderRadius(14)
              .border({ width: 1, color: '#4D3830', style: BorderStyle.Solid })
              .margin({ top: 8 })
          }

          // 牌桌面板：状态行 + 目标 HUD / 共享左轮 / 公共牌区 + 座位列表
          this.GameTable()

          // 全民质疑窗口面板
          if (!this.isGameOver() && this.getGame()?.phase === 'CHALLENGE_WINDOW') {
            this.ChallengeWindowPanel()
          }

          // 左轮惩罚显示（惩罚相位）
          if (this.getGame() !== null && this.getGame()?.punishment !== null) {
            RevolverDisplay({ punishment: this.getGame()?.punishment })
              .margin({ top: 10 })
              .width('92%')
          }

          // 质疑结果行
          if (this.getGame() !== null && this.getGame()?.challengeResult !== null) {
            Column() {
              Text(this.getChallengeResultText())
                .fontSize(13)
                .fontColor('#E8DDC8')
                .textAlign(TextAlign.Center)
            }
            .width('92%')
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .backgroundColor('#231713')
            .borderRadius(10)
            .border({ width: 1, color: '#A67C3D', style: BorderStyle.Solid })
            .margin({ top: 10 })
          }

          // 惩罚备注
          if (this.getPunishmentNote().length > 0) {
            Text(this.getPunishmentNote())
              .fontSize(12)
              .fontColor('#A67C3D')
              .margin({ top: 8 })
          }

          // 手牌 + 操作（终局时隐藏）
          if (!this.isGameOver()) {
            this.HandSection()
          }
        }
        .width('100%')
        .padding({ bottom: 24 })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .align(Alignment.Top)

      // 演出动画覆盖层（相位时钟驱动）
      CinematicOverlay({
        game: this.store.game,
        syncedNow: this.getSyncedNow(),
        reduceMotion: this.isReducedMotion(),
        lowPower: this.store.lowPowerActive
      })

      // 离线重连提示
      if (this.hasOfflinePlayer()) {
        Column() {
          Text('有玩家暂时离线，对局状态会在重连后恢复。')
            .fontSize(12)
            .fontColor('#E8DDC8')
        }
        .width('100%')
        .padding({ top: 10, bottom: 10 })
        .backgroundColor('rgba(139,48,61,0.92)')
        .justifyContent(FlexAlign.Center)
      }

      // 规则面板弹窗
      if (this.showRules) {
        RulesPanel({
          visible: true,
          gameMode: this.getGame() !== null ? this.getGame()?.gameMode : 'CLASSIC',
          tavernEventType: this.getGame() !== null && this.getGame()?.tavernEvent !== null ? this.getGame()?.tavernEvent?.type : '',
          onClose: () => {
            this.showRules = false
          }
        })
      }

      // 本局结算面板
      if (this.isGameOver()) {
        this.VictoryPanel()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#17110F')
    .backgroundImage($r('app.media.background_bg_lobby'))
    .backgroundImageSize(ImageSize.Cover)
  }

  // 页眉
  @Builder GameHeader() {
    Row() {
      Column() {
        Text(`第 ${this.getGame()?.roundNumber ?? 0} 轮 · ${this.getModeName()} ${this.getGame()?.turnDurationSeconds ?? 15} 秒 · #${this.getGame()?.sequence ?? 0}`)
          .fontSize(11)
          .fontColor('#A67C3D')
        Text(this.isGameOver() ? '本局结算' : '诡牌酒桌')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#F2C777')
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Column() {
        if (this.getSecondsLeft() >= 0) {
          Text(`${this.getSecondsLeft()}s`)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getSecondsLeft() <= 5 ? '#FF756D' : '#F2C777')
            .margin({ bottom: 4 })
        }
        Text(this.getDiscardText())
          .fontSize(11)
          .fontColor('#A67C3D')
          .margin({ bottom: 6 })
        Row() {
          Button(this.immersive ? '退出全屏' : '全屏')
            .height(30)
            .fontSize(12)
            .backgroundColor('#2B1914')
            .fontColor('#F2C777')
            .onClick(() => this.setImmersive(!this.immersive))
          Button('规则')
            .height(30)
            .fontSize(12)
            .backgroundColor('#2B1914')
            .fontColor('#F2C777')
            .borderRadius(15)
            .border({ width: 1, color: '#A67C3D', style: BorderStyle.Solid })
            .padding({ left: 12, right: 12 })
            .onClick(() => {
              this.showRules = true
            })
          Button('退出房间')
            .height(30)
            .fontSize(12)
            .backgroundColor('#2B1914')
            .fontColor('#FF756D')
            .borderRadius(15)
            .border({ width: 1, color: '#8B303D', style: BorderStyle.Solid })
            .padding({ left: 12, right: 12 })
            .margin({ left: 6 })
            .onClick(() => {
              this.leaveWithConfirm()
            })
        }
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('92%')
    .margin({ top: 10 })
    .alignItems(VerticalAlign.Top)
  }

  // 演出设置行
  @Builder CinematicControls() {
    Row() {
      Button(this.audioEnabled ? '音效开' : '音效关')
        .height(26)
        .fontSize(11)
        .backgroundColor('#231713')
        .fontColor(this.audioEnabled ? '#F2C777' : '#6B5A4A')
        .borderRadius(13)
        .border({ width: 1, color: '#4D3830', style: BorderStyle.Solid })
        .padding({ left: 10, right: 10 })
        .onClick(() => {
          this.toggleAudio()
        })
      Button(this.store.lowPowerActive ? '性能省' : '性能满')
        .height(26)
        .fontSize(11)
        .backgroundColor('#231713')
        .fontColor(this.store.lowPowerActive ? '#F2C777' : '#6B5A4A')
        .borderRadius(13)
        .border({ width: 1, color: '#4D3830', style: BorderStyle.Solid })
        .padding({ left: 10, right: 10 })
        .margin({ left: 6 })
        .onClick(() => {
          this.toggleLowPower()
        })
      Button(this.store.reduceMotion ? '动画少' : '动画全')
        .height(26)
        .fontSize(11)
        .backgroundColor('#231713')
        .fontColor(this.store.reduceMotion ? '#F2C777' : '#6B5A4A')
        .borderRadius(13)
        .border({ width: 1, color: '#4D3830', style: BorderStyle.Solid })
        .padding({ left: 10, right: 10 })
        .margin({ left: 6 })
        .onClick(() => {
          this.toggleReduceMotion()
        })
    }
    .width('92%')
    .margin({ top: 8 })
  }

  // 新手提示
  @Builder OnboardingTip() {
    Row() {
      Text(this.getNewPlayerHint())
        .fontSize(12)
        .fontColor('#E8DDC8')
        .layoutWeight(1)
      Button('知道了')
        .height(26)
        .fontSize(11)
        .backgroundColor('#2B1914')
        .fontColor('#F2C777')
        .borderRadius(13)
        .border({ width: 1, color: '#A67C3D', style: BorderStyle.Solid })
        .padding({ left: 10, right: 10 })
        .margin({ left: 8 })
        .onClick(() => {
          this.dismissedTip = true
        })
    }
    .width('92%')
    .padding(10)
    .backgroundColor('#231713')
    .borderRadius(10)
    .border({ width: 1, color: '#4D3830', style: BorderStyle.Solid })
    .margin({ top: 10 })
    .alignItems(VerticalAlign.Center)
  }

  // 酒馆事件横幅
  @Builder TavernEventBanner() {
    Column() {
      Row() {
        Text(this.getGame()?.tavernEvent?.title ?? '')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#F2C777')
          .margin({ right: 8 })
        Text(this.getPartyEventRule().length > 0 ? this.getPartyEventRule() : (this.getGame()?.tavernEvent?.description ?? ''))
          .fontSize(12)
          .fontColor('#E8DDC8')
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 上一轮事件（历史 >1 时显示倒数第二个）
      if (this.getGame() !== null && this.getGame()?.partyEventHistory !== null &&
        (this.getGame()?.partyEventHistory?.length ?? 0) > 1) {
        Text(`上一轮：${this.getPreviousEventTitle()}`)
          .fontSize(11)
          .fontColor('#6B5A4A')
          .margin({ top: 4 })
          .alignSelf(ItemAlign.Start)
      }
    }
    .width('92%')
    .padding(10)
    .backgroundColor('#231713')
    .borderRadius(10)
    .border({ width: 1, color: '#A67C3D', style: BorderStyle.Solid })
    .margin({ top: 10 })
    .alignItems(HorizontalAlign.Start)
  }

  private getPreviousEventTitle(): string {
    const game: GameSnapshot | null = this.store.game
    if (game === null || game.partyEventHistory.length < 2) {
      return ''
    }
    return game.partyEventHistory[game.partyEventHistory.length - 2].title
  }

  // 回合横幅
  @Builder TurnBanner() {
    Text(this.getTurnBannerText())
      .fontSize(14)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.getTurnBannerColor())
      .width('92%')
      .textAlign(TextAlign.Center)
      .padding({ top: 10, bottom: 10 })
      .backgroundColor('#231713')
      .borderRadius(10)
      .border({ width: 1, color: '#4D3830', style: BorderStyle.Solid })
      .margin({ top: 10 })
  }

  private getTurnBannerText(): string {
    const game: GameSnapshot | null = this.store.game
    if (game === null) {
      return '牌局演出中'
    }
    if (this.isTurn()) {
      if (game.mustChallenge) {
        return '你的回合：必须质疑上一手'
      }
      return this.getTurnInstruction()
    }
    if (game.phase === 'CHALLENGE_WINDOW') {
      return '全民质疑窗口开启'
    }
    if (game.phase === 'TURN') {
      return `等待 ${this.getCurrentPlayerName()} 出牌`
    }
    return this.getMatchStatus()
  }

  private getTurnBannerColor(): string {
    if (this.isTurn()) {
      return '#F2C777'
    }
    const game: GameSnapshot | null = this.store.game
    if (game !== null && game.phase === 'CHALLENGE_WINDOW') {
      return '#FF756D'
    }
    return '#E8DDC8'
  }

  // 牌桌面板
  @Builder GameTable() {
    Column() {
      // 状态行
      Text(this.getMatchStatus())
        .fontSize(12)
        .fontColor('#A67C3D')
        .alignSelf(ItemAlign.Start)
        .margin({ bottom: 10 })

      // 目标 HUD + 共享左轮
      Row() {
        TargetHUD({
          targetCard: this.getGame()?.targetCard ?? 'A',
          roundNumber: this.getGame()?.roundNumber ?? 0
        })

        if (this.getGame() !== null && this.getGame()?.sharedRevolver !== null) {
          this.SharedRevolverHud()
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: 10 })

      // 公共牌区
      PublicCardArea({
        phase: this.getGame()?.phase ?? 'LOBBY',
        lastPlay: this.getGame()?.lastPlay ?? null,
        lastPlayerName: this.getLastPlayerName(),
        discardCount: this.getGame()?.discardCount ?? null,
        targetCard: this.getGame()?.targetCard ?? 'A',
        revealedCards: this.getTableRevealedCards()
      })

      // 座位列表
      Column() {
        ForEach(this.buildSeats(), (seat: SeatInfo) => {
          PlayerSeat({
            player: seat.player,
            characterId: seat.characterId,
            isCurrentTurn: seat.isCurrentTurn,
            isMe: seat.isMe,
            newlyEliminated: seat.newlyEliminated,
            isWinner: this.isGameOver() && seat.player.playerId === this.getGame()?.winnerId
          })
          .margin({ bottom: 6 })
        })
      }
      .width('100%')
      .margin({ top: 12 })
    }
    .width('92%')
    .padding(14)
    .backgroundColor('#231713')
    .borderRadius(14)
    .border({ width: 1, color: '#4D3830', style: BorderStyle.Solid })
    .margin({ top: 10 })
  }

  // 共享左轮 HUD
  @Builder SharedRevolverHud() {
    Column() {
      Text('共享左轮')
        .fontSize(11)
        .fontColor('#D4A85D')
        .margin({ bottom: 6 })

      // 膛位轨道
      Row() {
        ForEach(this.getSharedChamberIndexes(), (index: number) => {
          Circle()
            .width(12)
            .height(12)
            .fill(index < this.getSharedSpent() ? '#8B303D' : '#2B1914')
            .stroke('#4D3830')
            .strokeWidth(1)
            .margin({ left: 3, right: 3 })
        })
      }
      .margin({ bottom: 6 })

      Text(`连续空膛：${this.getSharedSpent()} · 剩余膛位：${this.getSharedRemaining()}`)
        .fontSize(11)
        .fontColor('#E8DDC8')

      if (this.getGame()?.punishment?.hit === true) {
        Text('重新装填并旋转弹巢')
          .fontSize(10)
          .fontColor('#FF756D')
          .margin({ top: 4 })
      }
    }
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .backgroundColor('#2B1914')
    .borderRadius(10)
    .border({ width: 1, color: '#4D3830', style: BorderStyle.Solid })
    .margin({ left: 10 })
  }

  private getSharedChamberIndexes(): number[] {
    const game: GameSnapshot | null = this.store.game
    const count: number = game !== null && game.sharedRevolver !== null ? game.sharedRevolver.chamberCount : 6
    const indexes: number[] = []
    for (let i = 0; i < count; i++) {
      indexes.push(i)
    }
    return indexes
  }

  private getSharedSpent(): number {
    const game: GameSnapshot | null = this.store.game
    if (game === null || game.sharedRevolver === null) {
      return 0
    }
    const spent: number = game.sharedRevolver.currentChamber
    return spent < game.sharedRevolver.chamberCount ? spent : game.sharedRevolver.chamberCount
  }

  private getSharedRemaining(): number {
    const game: GameSnapshot | null = this.store.game
    if (game === null || game.sharedRevolver === null) {
      return 6
    }
    return game.sharedRevolver.chamberCount - this.getSharedSpent()
  }

  // 全民质疑窗口面板
  @Builder ChallengeWindowPanel() {
    Column() {
      Row() {
        Text('质疑窗口')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#F2C777')
          .layoutWeight(1)
        Text(`${this.getChallengeWindowRemaining()}s`)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FF756D')
      }
      .width('100%')
      .margin({ bottom: 6 })

      Text(this.getChallengeWindowLastPlayText())
        .fontSize(12)
        .fontColor('#E8DDC8')
        .margin({ bottom: 10 })

      Button(this.canFreeChallenge() ? '质疑！' : '等待其他玩家质疑')
        .width('100%')
        .height(44)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .backgroundColor(this.canFreeChallenge() ? '#8B303D' : '#2B1914')
        .fontColor(this.canFreeChallenge() ? '#FFFFFF' : '#6B5A4A')
        .borderRadius(10)
        .border({
          width: 1,
          color: this.canFreeChallenge() ? '#FF756D' : '#4D3830',
          style: BorderStyle.Solid
        })
        .enabled(this.canFreeChallenge())
        .onClick(() => {
          this.doChallenge()
        })
    }
    .width('92%')
    .padding(14)
    .backgroundColor('#231713')
    .borderRadius(10)
    .border({ width: 1, color: '#8B303D', style: BorderStyle.Solid })
    .margin({ top: 10 })
    .alignItems(HorizontalAlign.Start)
  }

  private getChallengeWindowLastPlayText(): string {
    const game: GameSnapshot | null = this.store.game
    if (game === null || game.lastPlay === null) {
      return '等待质疑'
    }
    if (game.lastPlay.count === null) {
      return '上一手已下注，数量暂时隐藏'
    }
    return `上一手声明 ${game.lastPlay.claimedRank} × ${game.lastPlay.count}`
  }

  // 手牌 + 操作按钮区
  @Builder HandSection() {
    Column() {
      // 道具栏
      if (this.hasItemDock()) {
        this.ItemDock()
      }

      // 手牌
      CardHand({
        hand: this.getGame()?.hand ?? [],
        selectedIndexes: this.selectedCardIndexes,
        disabled: !this.canPlay(),
        reduceMotion: this.isReducedMotion(),
        tipsy: this.isTipsy(),
        syncedNow: this.getSyncedNow(),
        onCardSelect: (index: number) => {
          this.toggleCardSelection(index)
        }
      })

      // 出牌按钮
      Button(this.selectedCardIndexes.length > 0 ? `出 ${this.selectedCardIndexes.length} 张牌` : '出牌')
        .width('92%')
        .height(50)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .backgroundColor(this.canSubmitPlay() ? '#D4A85D' : '#2B1914')
        .fontColor(this.canSubmitPlay() ? '#17110F' : '#6B5A4A')
        .borderRadius(12)
        .border({
          width: 1,
          color: this.canSubmitPlay() ? '#F2C777' : '#4D3830',
          style: BorderStyle.Solid
        })
        .enabled(this.canSubmitPlay())
        .margin({ top: 6 })
        .onClick(() => {
          this.submitPlay()
        })

      // 质疑上一手按钮（全民质疑模式在窗口面板中质疑）
      if (this.canChallengeInTurn()) {
        Button('质疑上一手')
          .width('92%')
          .height(46)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .backgroundColor('#8B303D')
          .fontColor('#FFFFFF')
          .borderRadius(12)
          .border({ width: 1, color: '#FF756D', style: BorderStyle.Solid })
          .margin({ top: 8 })
          .onClick(() => {
            this.doChallenge()
          })
      }
    }
    .width('100%')
    .margin({ top: 12 })
  }

  // 是否显示道具栏
  private hasItemDock(): boolean {
    const game: GameSnapshot | null = this.store.game
    if (game === null) {
      return false
    }
    if (game.items.length > 0) {
      return true
    }
    return this.getActiveItemEffect().length > 0 || this.getActiveAbilityEffect().length > 0
  }

  // 生效中的道具效果（过期时间判断）
  private getActiveItemEffect(): string {
    const game: GameSnapshot | null = this.store.game
    if (game === null || game.itemEffect === null) {
      return ''
    }
    if (game.itemEffect.expiresAt !== null && game.itemEffect.expiresAt <= this.getSyncedNow()) {
      return ''
    }
    return game.itemEffect.message
  }

  // 生效中的角色技能效果
  private getActiveAbilityEffect(): string {
    const game: GameSnapshot | null = this.store.game
    if (game === null || game.abilityEffect === null) {
      return ''
    }
    if (game.abilityEffect.expiresAt !== null && game.abilityEffect.expiresAt <= this.getSyncedNow()) {
      return ''
    }
    return game.abilityEffect.message
  }

  private getActiveAbilityTitle(): string {
    const game: GameSnapshot | null = this.store.game
    if (game === null || game.abilityEffect === null) {
      return ''
    }
    if (game.abilityEffect.expiresAt !== null && game.abilityEffect.expiresAt <= this.getSyncedNow()) {
      return ''
    }
    return game.abilityEffect.title
  }

  // 道具栏
  @Builder ItemDock() {
    Column() {
      // 角色技能效果行
      if (this.getActiveAbilityEffect().length > 0) {
        Column() {
          Text(this.getActiveAbilityTitle())
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor('#F2C777')
          Text(this.getActiveAbilityEffect())
            .fontSize(12)
            .fontColor('#E8DDC8')
            .margin({ top: 2 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(10)
        .backgroundColor('#2B1914')
        .borderRadius(10)
        .border({ width: 1, color: '#F2C777', style: BorderStyle.Solid })
        .margin({ bottom: 6 })
      }

      // 道具效果行
      if (this.getActiveItemEffect().length > 0) {
        Text(this.getActiveItemEffect())
          .fontSize(12)
          .fontColor('#E8DDC8')
          .width('100%')
          .textAlign(TextAlign.Start)
          .padding(10)
          .backgroundColor('#2B1914')
          .borderRadius(10)
          .border({ width: 1, color: '#4D3830', style: BorderStyle.Solid })
          .margin({ bottom: 6 })
      }

      // 道具按钮
      if ((this.getGame()?.items?.length ?? 0) > 0) {
        Row() {
          ForEach(this.getGame()?.items ?? [], (item: ActiveItemId) => {
            Column() {
              Image(getItemImage(item))
                .width(30)
                .height(30)
                .objectFit(ImageFit.Contain)
                .opacity(this.canUseItem(item) ? 1.0 : 0.4)
              Text(this.getItemName(item))
                .fontSize(10)
                .fontColor(this.canUseItem(item) ? '#E8DDC8' : '#6B5A4A')
                .margin({ top: 2 })
            }
            .padding({ left: 10, right: 10, top: 8, bottom: 8 })
            .backgroundColor('#2B1914')
            .borderRadius(10)
            .border({
              width: 1,
              color: this.canUseItem(item) ? '#A67C3D' : '#4D3830',
              style: BorderStyle.Solid
            })
            .margin({ left: 4, right: 4 })
            .onClick(() => {
              if (this.canUseItem(item)) {
                this.doUseItem(item)
              }
            })
          })
        }
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('92%')
    .margin({ bottom: 8 })
  }

  // 本局结算面板（对应网页版 victory-panel）
  @Builder VictoryPanel() {
    Scroll() {
      Column() {
        if (this.getWinnerCharacter().length > 0) {
          Image(getCharacterImage(this.getWinnerCharacter(), 'victory'))
            .width(86)
            .height(86)
            .objectFit(ImageFit.Contain)
        }
        Text('酒馆最终胜者')
          .fontSize(12)
          .fontColor('#A67C3D')
          .margin({ bottom: 8 })

        Text(this.getPlayerNameById(this.getGame()?.winnerId ?? null))
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor('#F2C777')
          .margin({ bottom: 14 })

        // 四格统计
        if (this.getGame() !== null && this.getGame()?.summary !== null) {
          Row() {
            this.VictoryStat(`${this.getGame()?.summary?.playerCount ?? 0}`, '人局')
            this.VictoryStat(`${this.getGame()?.summary?.durationSeconds ?? 0}`, '秒')
            this.VictoryStat(`${this.getGame()?.summary?.challengeCount ?? 0}`, '次质疑')
            this.VictoryStat(`${this.getGame()?.summary?.successfulChallenges ?? 0}`, '次成功')
          }
          .margin({ bottom: 10 })

          Text(`淘汰顺序：${this.getEliminationOrderText()}`)
            .fontSize(12)
            .fontColor('#A67C3D')
            .margin({ bottom: 16 })
          Button('分享结果（复制战报）')
            .fontColor('#F2C777')
            .backgroundColor('#2B1914')
            .onClick(() => this.shareResult())
          if (this.shareNotice.length > 0) {
            Text(this.shareNotice).fontSize(12).fontColor('#E8DDC8').margin({ top: 8, bottom: 8 })
          }
        }

      // 操作按钮
        if (this.store.isHost) {
          Button('再来一局')
            .width('100%')
            .height(48)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .backgroundColor('#D4A85D')
            .fontColor('#17110F')
            .borderRadius(12)
            .margin({ bottom: 8 })
            .onClick(() => {
              this.doReturnToRoom()
            })
        }
        Button(this.store.isHost ? '返回房间 / 修改模式' : '返回房间')
          .width('100%')
          .height(44)
          .fontSize(15)
          .backgroundColor('#2B1914')
          .fontColor('#F2C777')
          .borderRadius(12)
          .border({ width: 1, color: '#A67C3D', style: BorderStyle.Solid })
          .margin({ bottom: 8 })
          .onClick(() => {
            this.doReturnToRoom()
          })
        Button('退出房间')
          .width('100%')
          .height(44)
          .fontSize(15)
          .backgroundColor('#231713')
          .fontColor('#FF756D')
          .borderRadius(12)
          .border({ width: 1, color: '#8B303D', style: BorderStyle.Solid })
          .onClick(() => {
            this.leaveWithConfirm()
          })
      }
      .width('86%')
      .padding(24)
      .backgroundColor('#231713')
      .borderRadius(16)
      .border({ width: 1, color: '#A67C3D', style: BorderStyle.Solid })
      .margin({ top: 20, bottom: 20 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(23,17,15,0.9)')
    .backgroundImage($r('app.media.background_bg_victory'))
    .backgroundImageSize(ImageSize.Cover)
    .scrollBar(BarState.Off)
  }

  @Builder VictoryStat(value: string, label: string) {
    Column() {
      Text(value)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#F2C777')
      Text(label)
        .fontSize(10)
        .fontColor('#A67C3D')
        .margin({ top: 2 })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }
}
