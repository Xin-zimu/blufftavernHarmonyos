// 游戏主页面 - 对应 GameScreen.tsx
// 最复杂的页面，包含 HUD、座位、手牌、操作按钮、演出层等

import { SessionStore } from '../store/SessionStore'
import { SocketManager } from '../net/SocketManager'
import {
  GameSnapshot, PublicPlayerState, GamePhase,
  CardRank, TargetRank, PublicLastPlay, PublicPunishmentState
} from '../model/GameTypes'
import { MAX_CARDS_PER_PLAY } from '../model/Constants'
import { TargetHUD } from '../components/TargetHUD'
import { PlayerSeat } from '../components/PlayerSeat'
import { CardHand } from '../components/CardHand'
import { PublicCardArea } from '../components/PublicCardArea'
import { RevolverDisplay } from '../components/RevolverDisplay'
import { ConnectionBadge } from '../components/ConnectionBadge'
import { RulesPanel } from '../components/RulesPanel'
import { CinematicOverlay } from '../components/CinematicOverlay'

@Entry
@Component
struct GamePage {
  @StorageLink('sessionStore') store: SessionStore = new SessionStore()
  @StorageLink('socketManager') socketManager: SocketManager = new SocketManager(new SessionStore())
  @State selectedCardIndexes: number[] = []
  @State showRules: boolean = false
  @State turnTimer: number = 0
  private timerId: number = -1

  aboutToAppear(): void {
    this.startTurnTimer()
  }

  aboutToDisappear(): void {
    this.stopTurnTimer()
  }

  // 回合计时器
  private startTurnTimer(): void {
    this.stopTurnTimer()
    this.timerId = setInterval(() => {
      if (this.store.game && this.store.game.phase === 'TURN') {
        this.turnTimer = this.store.getTurnRemainingSeconds()
      } else {
        this.turnTimer = 0
      }
    }, 500)
  }

  private stopTurnTimer(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId)
      this.timerId = -1
    }
  }

  // 选牌切换 - 必须重新赋值数组以触发 UI 更新
  private toggleCardSelection(index: number): void {
    const pos = this.selectedCardIndexes.indexOf(index)
    if (pos >= 0) {
      const newArr: number[] = []
      for (const idx of this.selectedCardIndexes) {
        if (idx !== index) newArr.push(idx)
      }
      this.selectedCardIndexes = newArr
    } else {
      if (this.selectedCardIndexes.length < MAX_CARDS_PER_PLAY) {
        const newArr: number[] = [...this.selectedCardIndexes, index]
        this.selectedCardIndexes = newArr
      }
    }
  }

  // 是否可以出牌
  private canPlay(): boolean {
    const game = this.store.game
    if (!game) return false
    return game.turnPlayerId === this.store.playerId &&
           !game.mustChallenge &&
           this.selectedCardIndexes.length > 0 &&
           this.selectedCardIndexes.length <= MAX_CARDS_PER_PLAY
  }

  // 是否可以质疑
  private canChallenge(): boolean {
    const game = this.store.game
    if (!game) return false
    return game.turnPlayerId === this.store.playerId && game.lastPlay !== null
  }

  // ====== 辅助 getter 方法（替代 ?? 操作符） ======

  // 获取目标牌排名
  private getTargetRank(): TargetRank | null {
    if (this.store.game !== null) {
      return this.store.game.targetRank
    }
    return null
  }

  // 获取目标牌默认牌
  private getTargetCard(): TargetRank {
    if (this.store.game !== null) {
      return this.store.game.targetCard
    }
    return 'A'
  }

  // 获取回合数
  private getRoundNumber(): number {
    if (this.store.game !== null) {
      return this.store.game.roundNumber
    }
    return 0
  }

  // 获取最后出牌
  private getLastPlay(): PublicLastPlay | null {
    if (this.store.game !== null) {
      return this.store.game.lastPlay
    }
    return null
  }

  // 获取弃牌数
  private getDiscardCount(): number {
    if (this.store.game !== null) {
      return this.store.game.discardCount
    }
    return 0
  }

  // 获取玩家列表
  private getPlayers(): PublicPlayerState[] {
    if (this.store.game !== null) {
      return this.store.game.players
    }
    return []
  }

  // 获取惩罚状态
  private getPunishment(): PublicPunishmentState | null {
    if (this.store.game !== null) {
      return this.store.game.punishment
    }
    return null
  }

  // 获取手牌
  private getHand(): CardRank[] {
    if (this.store.game !== null) {
      return this.store.game.hand
    }
    return []
  }

  // 获取揭示的牌
  private getRevealedCards(): CardRank[] {
    if (this.store.game !== null && this.store.game.challengeResult !== null) {
      if (this.store.game.challengeResult.revealedCards !== null) {
        return this.store.game.challengeResult.revealedCards
      }
    }
    return []
  }

  // 是否有质疑结果
  private hasChallengeResult(): boolean {
    return this.store.game !== null && this.store.game.challengeResult !== null
  }

  // 质疑是否为诈唬
  private getWasBluff(): boolean {
    if (this.store.game !== null && this.store.game.challengeResult !== null) {
      return this.store.game.challengeResult.wasBluff
    }
    return false
  }

  // 获取质疑次数
  private getChallengeCount(): number {
    if (this.store.game !== null && this.store.game.summary !== null) {
      return this.store.game.summary.challengeCount
    }
    return 0
  }

  // 获取成功质疑次数
  private getSuccessfulChallenges(): number {
    if (this.store.game !== null && this.store.game.summary !== null) {
      return this.store.game.summary.successfulChallenges
    }
    return 0
  }

  // 获取失败质疑次数
  private getFailedChallenges(): number {
    if (this.store.game !== null && this.store.game.summary !== null) {
      return this.store.game.summary.failedChallenges
    }
    return 0
  }

  // 是否有惩罚
  private hasPunishment(): boolean {
    return this.store.game !== null && this.store.game.punishment !== null
  }

  // 是否有摘要
  private hasSummary(): boolean {
    return this.store.game !== null && this.store.game.summary !== null
  }

  // 是否有胜者
  private hasWinner(): boolean {
    return this.store.game !== null && this.store.game.winnerId !== null
  }

  // 获取玩家角色ID
  private getPlayerCharacterId(playerId: string): string {
    if (!this.store.room) return ''
    for (const player of this.store.room.players) {
      if (player.id === playerId) {
        if (player.characterId !== null) {
          return player.characterId
        }
        return ''
      }
    }
    return ''
  }

  // 获取胜者名称
  private getWinnerName(): string {
    if (!this.store.game || !this.store.game.winnerId) return ''
    for (const player of this.store.game.players) {
      if (player.playerId === this.store.game.winnerId) {
        return player.name
      }
    }
    return ''
  }

  // 当前阶段是否为 TURN
  private isPhaseTurn(): boolean {
    return this.store.game !== null && this.store.game.phase === 'TURN'
  }

  // 当前阶段是否为 GAME_OVER
  private isPhaseGameOver(): boolean {
    return this.store.game !== null && this.store.game.phase === 'GAME_OVER'
  }

  build() {
    Stack() {
      // 主游戏内容
      Column() {
        // 顶部：目标牌 HUD + 连接状态
        Row() {
          TargetHUD({
            targetRank: this.getTargetRank(),
            targetCard: this.getTargetCard(),
            roundNumber: this.getRoundNumber()
          })

          Blank()

          ConnectionBadge({ status: this.store.connection })
        }
        .width('90%')
        .margin({ top: 8 })

        // 回合计时器
        if (this.isPhaseTurn() && this.store.isMyTurn) {
          Row() {
            Text('剩余时间:')
              .fontSize(14)
              .fontColor('#888899')
            Text(`${this.turnTimer}s`)
              .fontSize(20)
              .fontColor(this.turnTimer <= 5 ? '#FF6B6B' : '#D4A574')
              .fontWeight(FontWeight.Bold)
          }
          .margin({ top: 8 })
        }

        // 公共牌区
        PublicCardArea({
          lastPlay: this.getLastPlay(),
          discardCount: this.getDiscardCount(),
          targetRank: this.getTargetRank()
        })
        .margin({ top: 8 })

        // 玩家座位列表
        Row() {
          ForEach(this.getPlayers(), (player: PublicPlayerState) => {
            PlayerSeat({
              player: player,
              isCurrentTurn: this.store.game !== null && player.playerId === this.store.game.turnPlayerId,
              isMe: player.playerId === this.store.playerId,
              characterId: this.getPlayerCharacterId(player.playerId)
            })
          })
        }
        .width('90%')
        .justifyContent(FlexAlign.SpaceAround)
        .margin({ top: 12 })

        // 左轮手枪显示（惩罚阶段）
        if (this.hasPunishment()) {
          RevolverDisplay({
            punishment: this.getPunishment()
          })
          .margin({ top: 12 })
        }

        // 质疑结果展示
        if (this.hasChallengeResult()) {
          this.ChallengeResultDisplay()
        }

        Blank()

        // 手牌区
        CardHand({
          hand: this.getHand(),
          selectedIndexes: $selectedCardIndexes,
          disabled: !this.store.isMyTurn || this.store.mustChallenge,
          onCardSelect: (index: number) => {
            this.toggleCardSelection(index)
          }
        })

        // 操作按钮
        Row() {
          // 出牌按钮
          Button('出牌')
            .width('30%')
            .height(48)
            .backgroundColor('#D4A574')
            .fontColor('#1A1A2E')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .borderRadius(8)
            .enabled(this.canPlay())
            .onClick(() => {
              this.socketManager.playCards([...this.selectedCardIndexes], (success: boolean, error?: string) => {
                if (success) {
                  this.selectedCardIndexes = []
                }
              })
            })

          // 质疑按钮
          Button('质疑')
            .width('30%')
            .height(48)
            .backgroundColor('#FF6B6B')
            .fontColor('#FFFFFF')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .borderRadius(8)
            .enabled(this.canChallenge())
            .onClick(() => {
              this.socketManager.challenge()
              this.selectedCardIndexes = []
            })

          // 规则按钮
          Button('规则')
            .width('30%')
            .height(48)
            .backgroundColor('#2A2A4E')
            .fontColor('#D4A574')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .borderRadius(8)
            .onClick(() => {
              this.showRules = true
            })
        }
        .width('90%')
        .justifyContent(FlexAlign.SpaceBetween)
        .margin({ top: 8, bottom: 8 })

        // 必须质疑提示
        if (this.store.mustChallenge) {
          Text('上家已出完手牌，必须质疑!')
            .fontSize(16)
            .fontColor('#FF6B6B')
            .fontWeight(FontWeight.Bold)
            .margin({ bottom: 8 })
        }
      }
      .width('100%')
      .height('100%')

      // 演出动画覆盖层
      CinematicOverlay({ game: this.store.game })

      // 规则面板弹窗
      if (this.showRules) {
        Column() {
          RulesPanel({
            visible: true,
            onClose: () => {
              this.showRules = false
            }
          })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#000000')
        .opacity(0.8)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.showRules = false
        })
      }

      // 游戏结束结算面板
      if (this.isPhaseGameOver()) {
        this.GameOverPanel()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#1A1A2E')
  }

  // 质疑结果展示
  @Builder ChallengeResultDisplay() {
    Column() {
      Text('质疑结果')
        .fontSize(16)
        .fontColor('#D4A574')
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 8 })

      // 翻开的牌
      Row() {
        ForEach(this.getRevealedCards(), (card: CardRank) => {
          Column() {
            if (card === 'JOKER') {
              Text('★')
                .fontSize(18)
                .fontColor('#FFD700')
            } else {
              Text(card)
                .fontSize(18)
                .fontColor('#FFFFFF')
            }
          }
          .width(32)
          .height(44)
          .backgroundColor('#2A2A4E')
          .borderRadius(4)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .margin({ left: 4, right: 4 })
        })
      }
      .margin({ bottom: 8 })

      // 诈唬判定
      Row() {
        Text(this.getWasBluff() ? '诈唬!' : '诚实!')
          .fontSize(20)
          .fontColor(this.getWasBluff() ? '#FF6B6B' : '#4CAF50')
          .fontWeight(FontWeight.Bold)
      }
    }
    .width('90%')
    .padding(12)
    .backgroundColor('#2A2A4E')
    .borderRadius(8)
    .alignItems(HorizontalAlign.Center)
    .margin({ top: 8 })
  }

  // 游戏结束结算面板
  @Builder GameOverPanel() {
    Column() {
      // 胜者
      Text('游戏结束')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor('#D4A574')
        .margin({ bottom: 16 })

      if (this.hasWinner()) {
        Text(`${this.getWinnerName()} 获胜!`)
          .fontSize(24)
          .fontColor('#4CAF50')
          .fontWeight(FontWeight.Bold)
          .margin({ bottom: 16 })
      }

      // 统计数据
      if (this.hasSummary()) {
        Column() {
          Row() {
            Text('质疑次数:')
              .fontSize(14)
              .fontColor('#888899')
            Text(`${this.getChallengeCount()}`)
              .fontSize(14)
              .fontColor('#D4A574')
              .fontWeight(FontWeight.Bold)
          }
          .margin({ bottom: 4 })

          Row() {
            Text('成功质疑:')
              .fontSize(14)
              .fontColor('#888899')
            Text(`${this.getSuccessfulChallenges()}`)
              .fontSize(14)
              .fontColor('#4CAF50')
              .fontWeight(FontWeight.Bold)
          }
          .margin({ bottom: 4 })

          Row() {
            Text('失败质疑:')
              .fontSize(14)
              .fontColor('#888899')
            Text(`${this.getFailedChallenges()}`)
              .fontSize(14)
              .fontColor('#FF6B6B')
              .fontWeight(FontWeight.Bold)
          }
        }
        .margin({ bottom: 16 })
      }

      // 操作按钮
      Row() {
        if (this.store.isHost) {
          Button('再来一局')
            .width('40%')
            .height(48)
            .backgroundColor('#D4A574')
            .fontColor('#1A1A2E')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .borderRadius(8)
            .onClick(() => {
              this.socketManager.restartGame()
            })
        }

        Button('返回大厅')
          .width('40%')
          .height(48)
          .backgroundColor('#2A2A4E')
          .fontColor('#D4A574')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .borderRadius(8)
          .onClick(() => {
            this.socketManager.returnToRoom()
          })
      }
      .justifyContent(FlexAlign.SpaceAround)
    }
    .width('80%')
    .padding(24)
    .backgroundColor('#1A1A2E')
    .borderRadius(12)
    .border({
      width: 2,
      color: '#D4A574',
      style: BorderStyle.Solid
    })
    .alignItems(HorizontalAlign.Center)
  }
}
