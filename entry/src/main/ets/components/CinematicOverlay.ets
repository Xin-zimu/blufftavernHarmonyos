// 演出动画覆盖层 - 对应网页版 7.2 CinematicLayer.tsx + cinematic-reveal-state.ts
// 关键原则：所有演出由服务端 phaseStartedAt/phaseEndsAt 驱动
// progress = (syncedNow - phaseStartedAt) / (phaseEndsAt - phaseStartedAt)
// 不使用本地 setTimeout 编排；唯一逐帧时刻表是 REVEAL 的 500ms 序 + 每张 750ms

import { GameSnapshot, CardRank, GamePhase } from '../model/GameTypes'

// REVEAL 时刻表（毫秒），与网页版 REVEAL_TIMING 一致
const REVEAL_INTRO_MS: number = 500
const REVEAL_PER_CARD_MS: number = 750
// GAME_OVER 演出显示时长，之后交给结算面板
const GAME_OVER_HOLD_MS: number = 3000

// 相位标签（与网页版 phaseLabels 一致）
export function getPhaseLabel(phase: GamePhase): string {
  if (phase === 'LOBBY') return '等待开局'
  if (phase === 'MATCH_START') return '牌局开始'
  if (phase === 'ROUND_START') return '新一轮'
  if (phase === 'TURN') return '行动中'
  if (phase === 'CHALLENGE_WINDOW') return '质疑窗口'
  if (phase === 'CHALLENGE_CALLOUT') return '质疑'
  if (phase === 'REVEAL') return '翻牌'
  if (phase === 'VERDICT') return '判定'
  if (phase === 'PUNISHMENT_INTRO') return '左轮准备'
  if (phase === 'PUNISHMENT_TRIGGER') return '扣动扳机'
  if (phase === 'PUNISHMENT_RESULT') return '惩罚结果'
  if (phase === 'ROUND_END') return '回合结束'
  return '最终胜者'
}

// 静态公开牌相位（与网页版 STATIC_REVEAL_PHASES 一致）
function isStaticRevealPhase(phase: GamePhase): boolean {
  return phase === 'VERDICT' || phase === 'PUNISHMENT_INTRO' ||
    phase === 'PUNISHMENT_TRIGGER' || phase === 'PUNISHMENT_RESULT' ||
    phase === 'ROUND_END'
}

@ComponentV2
export struct CinematicOverlay {
  @Param game: GameSnapshot | null = null
  // 服务器同步时钟（GamePage 每 100ms 刷新传入）
  @Param syncedNow: number = 0
  @Param reduceMotion: boolean = false
  @Param lowPower: boolean = false

  private motionDuration(duration: number): number {
    return this.reduceMotion || this.lowPower ? 0 : duration
  }

  // ====== 相位时钟计算 ======

  private getElapsed(): number {
    if (this.game === null) {
      return 0
    }
    const elapsed: number = this.syncedNow - this.game.phaseStartedAt
    return elapsed > 0 ? elapsed : 0
  }

  private getDuration(): number {
    if (this.game === null || this.game.phaseEndsAt === null) {
      return 1
    }
    const duration: number = this.game.phaseEndsAt - this.game.phaseStartedAt
    return duration > 0 ? duration : 1
  }

  private getProgress(): number {
    const progress: number = this.getElapsed() / this.getDuration()
    if (progress < 0) {
      return 0
    }
    if (progress > 1) {
      return 1
    }
    return progress
  }

  private getProgressPercent(): string {
    return `${Math.floor(this.getProgress() * 100)}%`
  }

  // 出牌/质疑窗口相位不显示演出（与网页版一致）
  private isVisible(): boolean {
    if (this.game === null) {
      return false
    }
    const phase: GamePhase = this.game.phase
    if (phase === 'TURN' || phase === 'CHALLENGE_WINDOW') {
      return false
    }
    if (phase === 'GAME_OVER' && this.getElapsed() > GAME_OVER_HOLD_MS) {
      return false
    }
    return true
  }

  // ====== 名称与文案辅助 ======

  private playerName(id: string | null): string {
    if (this.game === null || id === null || id === '') {
      return '玩家'
    }
    for (const player of this.game.players) {
      if (player.playerId === id) {
        return player.name
      }
    }
    return '玩家'
  }

  private getChallengerName(): string {
    if (this.game !== null && this.game.challenge !== null) {
      return this.playerName(this.game.challenge.challengerId)
    }
    return '玩家'
  }

  private getChallengedName(): string {
    if (this.game !== null && this.game.challenge !== null) {
      return this.playerName(this.game.challenge.challengedId)
    }
    return '玩家'
  }

  // 受罚者：优先取质疑状态中的受罚者（与网页版 challenged.punishedPlayerId ?? punishment.punishedPlayerId 一致）
  private getPunishedName(): string {
    if (this.game === null) {
      return '玩家'
    }
    if (this.game.challenge !== null && this.game.challenge.punishedPlayerId !== null) {
      return this.playerName(this.game.challenge.punishedPlayerId)
    }
    if (this.game.punishment !== null) {
      return this.playerName(this.game.punishment.punishedPlayerId)
    }
    return '玩家'
  }

  private getWinnerName(): string {
    if (this.game !== null) {
      return this.playerName(this.game.winnerId)
    }
    return '玩家'
  }

  private getTargetRankText(): string {
    if (this.game === null) {
      return 'A'
    }
    if (this.game.targetRank !== null) {
      return this.game.targetRank
    }
    return this.game.targetCard
  }

  private getRevealedCards(): CardRank[] {
    if (this.game !== null && this.game.challenge !== null && this.game.challenge.revealedCards !== null) {
      return this.game.challenge.revealedCards
    }
    return []
  }

  // REVEAL：第 i 张牌的翻转时刻
  private isCardFlipped(index: number): boolean {
    return this.getElapsed() >= REVEAL_INTRO_MS + index * REVEAL_PER_CARD_MS
  }

  // 翻开后按是否匹配目标牌判定描边：诚实金 / 谎言红（与网页版 honest 计算一致）
  private isCardHonest(rank: CardRank): boolean {
    if (rank === 'JOKER') {
      // 禁忌小丑之夜 Joker 不视为目标牌
      if (this.game !== null && this.game.tavernEvent !== null && this.game.tavernEvent.type === 'NO_JOKER') {
        return false
      }
      return true
    }
    return rank === this.getTargetRankText()
  }

  // 静态公开牌条：VERDICT / PUNISHMENT_* / ROUND_END 相位全程显示
  private showRevealedStrip(): boolean {
    if (this.game === null) {
      return false
    }
    return isStaticRevealPhase(this.game.phase) && this.getRevealedCards().length > 0
  }

  // ROUND_START：Party 模式有事件时走事件介绍分支
  private isPartyIntro(): boolean {
    return this.game !== null && this.game.gameMode === 'PARTY' && this.game.tavernEvent !== null
  }

  // PUNISHMENT_TRIGGER 标题：双倍危机事件特判
  private getTriggerTitle(): string {
    if (this.game !== null && this.game.tavernEvent !== null && this.game.tavernEvent.type === 'DOUBLE_DANGER') {
      return '双倍危机'
    }
    return '扣动扳机'
  }

  build() {
    if (!this.isVisible()) {
      Blank()
    } else {
      Stack() {
        // 半透明酒馆暗色遮罩
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#17110F')
          .opacity(0.88)

        // 演出面板 + 底部进度条
        Column() {
          this.PhaseContent()

          // 底部相位进度条（金）
          Column() {
            Row()
              .width(this.getProgressPercent())
              .height('100%')
              .backgroundColor('#F2C777')
          }
          .width('70%')
          .height(3)
          .backgroundColor('#2B1914')
          .borderRadius(2)
          .margin({ top: 28 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
    }
  }

  // ====== 相位分发 ======

  @Builder PhaseContent() {
    if (this.game === null) {
      Blank()
    } else {
      Column() {
        // 相位标签
        Text(getPhaseLabel(this.game.phase))
          .fontSize(13)
          .fontColor('#D4A85D')
          .letterSpacing(2)
          .margin({ bottom: 18 })

        if (this.game.phase === 'MATCH_START') {
          Text('酒馆开局')
            .fontSize(34)
            .fontWeight(FontWeight.Bold)
            .fontColor('#F2C777')
        } else if (this.game.phase === 'ROUND_START') {
          if (this.isPartyIntro()) {
            this.PartyEventIntroCinematic()
          } else {
            this.RoundStartCinematic()
          }
        } else if (this.game.phase === 'CHALLENGE_CALLOUT') {
          this.ChallengeCalloutCinematic()
        } else if (this.game.phase === 'REVEAL') {
          this.RevealCinematic()
        } else if (this.game.phase === 'VERDICT') {
          this.VerdictCinematic()
        } else if (this.game.phase === 'PUNISHMENT_INTRO') {
          this.PunishmentIntroCinematic()
        } else if (this.game.phase === 'PUNISHMENT_TRIGGER') {
          this.PunishmentTriggerCinematic()
        } else if (this.game.phase === 'PUNISHMENT_RESULT') {
          this.PunishmentResultCinematic()
        } else if (this.game.phase === 'ROUND_END') {
          this.RoundEndCinematic()
        } else if (this.game.phase === 'GAME_OVER') {
          this.GameOverCinematic()
        } else if (this.game.phase === 'LOBBY') {
          Text('等待入席')
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor('#F2C777')
        }

        // 静态公开牌条（判定/惩罚/回合结束相位）
        if (this.showRevealedStrip()) {
          this.RevealedStrip()
        }
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
  }

  // ====== 各相位演出（文案对齐网页版 7.2） ======

  // 普通回合开始：ROUND N + 目标牌宣告 + 事件行
  @Builder RoundStartCinematic() {
    Column() {
      Text(`ROUND ${this.game?.roundNumber}`)
        .fontSize(30)
        .fontWeight(FontWeight.Bold)
        .fontColor('#F2C777')
        .margin({ bottom: 14 })

      if (this.getProgress() > 0.22) {
        Text('本轮目标')
          .fontSize(15)
          .fontColor('#D4A85D')
          .margin({ bottom: 8 })
          .animation({ duration: this.motionDuration(300) })
      }
      if (this.getProgress() > 0.34) {
        Text(this.getTargetRankText())
          .fontSize(56)
          .fontWeight(FontWeight.Bold)
          .fontColor('#F2C777')
          .margin({ bottom: 10 })
          .animation({ duration: this.motionDuration(300) })
      }
      if (this.getProgress() > 0.48) {
        Text(`所有玩家本轮声明的牌均视为 ${this.getTargetRankText()}`)
          .fontSize(15)
          .fontColor('#E8DDC8')
          .animation({ duration: this.motionDuration(300) })
      }

      // 非乱斗模式的酒馆事件行（快速夜/烛火摇曳）
      if (this.game !== null && this.game.tavernEvent !== null && this.getProgress() > 0.58) {
        Text(`${this.game.tavernEvent.title}：${this.game.tavernEvent.description}`)
          .fontSize(13)
          .fontColor('#D4A85D')
          .margin({ top: 10 })
          .textAlign(TextAlign.Center)
          .animation({ duration: this.motionDuration(300) })
      }

      // 发牌线：5 张牌背依次点亮
      if (!this.lowPower && this.getProgress() > 0.45) {
        Row() {
          ForEach([0, 1, 2, 3, 4], (i: number) => {
            Column()
              .width(22)
              .height(32)
              .backgroundColor('#5B1F28')
              .borderRadius(3)
              .border({ width: 1, color: '#A67C3D', style: BorderStyle.Solid })
              .margin({ left: 4, right: 4 })
              .opacity(this.getProgress() > 0.45 + i * 0.05 ? 1 : 0.15)
              .animation({ duration: this.motionDuration(250) })
          })
        }
        .margin({ top: 18 })
      }
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 28, right: 28 })
  }

  // Party 模式事件介绍
  @Builder PartyEventIntroCinematic() {
    Column() {
      if (this.getProgress() > 0.06) {
        Text('酒馆乱斗')
          .fontSize(14)
          .fontColor('#D4A85D')
          .margin({ bottom: 8 })
          .animation({ duration: this.motionDuration(250) })
      }
      if (this.game !== null && this.game.tavernEvent !== null && this.getProgress() > 0.14) {
        Text(this.game.tavernEvent.title)
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor('#F2C777')
          .margin({ bottom: 10 })
          .animation({ duration: this.motionDuration(250) })
      }
      if (this.game !== null && this.game.tavernEvent !== null && this.getProgress() > 0.24) {
        Text(this.game.tavernEvent.description)
          .fontSize(15)
          .fontColor('#E8DDC8')
          .textAlign(TextAlign.Center)
          .animation({ duration: this.motionDuration(250) })
      }
      if (this.getProgress() > 0.34) {
        Text(`第 ${this.game?.roundNumber} 轮 · 目标牌 ${this.getTargetRankText()}`)
          .fontSize(13)
          .fontColor('#A67C3D')
          .margin({ top: 10 })
          .animation({ duration: this.motionDuration(250) })
      }
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 32, right: 32 })
  }

  // 质疑宣告
  @Builder ChallengeCalloutCinematic() {
    Column() {
      Text('质疑！')
        .fontSize(44)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FF756D')
        .margin({ bottom: 12 })
      Text(`${this.getChallengerName()} 质疑 ${this.getChallengedName()}`)
        .fontSize(19)
        .fontColor('#E8DDC8')
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  // 翻牌演出：序 500ms + 每张 750ms 逐张翻转
  @Builder RevealCinematic() {
    Column() {
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
        ForEach(this.getRevealedCards(), (card: CardRank, index?: number) => {
          Stack() {
            // 牌背
            Column() {
              Image($r('app.media.card_card_back'))
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Cover)
            }
            .width(64)
            .height(96)
            .backgroundColor('#5B1F28')
            .borderRadius(8)
            .border({ width: 1, color: '#A67C3D', style: BorderStyle.Solid })
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .opacity(this.isCardFlipped(index ?? 0) ? 0 : 1)
            .animation({ duration: this.motionDuration(400) })

            // 牌面
            Column() {
              if (card === 'JOKER') {
                Text('★')
                  .fontSize(30)
                  .fontColor('#5B1F28')
                  .fontWeight(FontWeight.Bold)
              } else {
                Text(card)
                  .fontSize(30)
                  .fontColor('#5B1F28')
                  .fontWeight(FontWeight.Bold)
              }
            }
            .width(64)
            .height(96)
            .backgroundColor('#E8DDC8')
            .borderRadius(8)
            .border({
              width: this.isCardFlipped(index ?? 0) ? 2 : 1,
              color: this.isCardFlipped(index ?? 0)
                ? (this.isCardHonest(card) ? '#F2C777' : '#FF756D') : '#A67C3D',
              style: BorderStyle.Solid
            })
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .opacity(this.isCardFlipped(index ?? 0) ? 1 : 0)
            .scale({
              x: this.reduceMotion || this.isCardFlipped(index ?? 0) ? 1.0 : 0.8,
              y: this.reduceMotion || this.isCardFlipped(index ?? 0) ? 1.0 : 0.8
            })
            .animation({ duration: this.motionDuration(400) })
          }
          .width(64)
          .height(96)
          .margin(6)
        })
      }
      .width('90%')
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  // 判定：谎言 / 质疑失败（文案对齐网页版 7.2）
  @Builder VerdictCinematic() {
    Column() {
      if (this.game !== null && this.game.challenge !== null && this.game.challenge.wasBluff === true) {
        Text('谎言！')
          .fontSize(44)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FF756D')
          .margin({ bottom: 8 })
        Text(`${this.getPunishedName()} 受罚`)
          .fontSize(18)
          .fontColor('#E8DDC8')
      } else if (this.game !== null && this.game.challenge !== null && this.game.challenge.wasBluff === false) {
        Text('质疑失败')
          .fontSize(44)
          .fontWeight(FontWeight.Bold)
          .fontColor('#F2C777')
          .margin({ bottom: 8 })
        Text(`${this.getPunishedName()} 受罚`)
          .fontSize(18)
          .fontColor('#E8DDC8')
      }
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  // 惩罚开场：弹巢旋转
  @Builder RevolverArt() {
    Stack() {
      Image($r('app.media.cinematic_revolver_side_v1'))
        .width('100%')
        .height(140)
        .objectFit(ImageFit.Contain)
      if (this.game?.phase === 'PUNISHMENT_RESULT' && this.game?.punishment?.hit === true && !this.lowPower) {
        Image($r('app.media.cinematic_muzzle_flash_smoke_v1'))
          .width('100%')
          .height(140)
          .objectFit(ImageFit.Contain)
          .opacity(this.reduceMotion ? 0.5 : Math.max(0, 1 - this.getProgress()))
      }
    }
    .width('80%')
    .height(150)
    .rotate({ angle: !this.reduceMotion && !this.lowPower && this.game?.phase === 'PUNISHMENT_INTRO' ? Math.sin(this.getProgress() * Math.PI * 8) * 2 : 0 })
  }

  @Builder PunishmentIntroCinematic() {
    Column() {
      this.RevolverArt()
      Text(`${this.getPunishedName()} 受罚`)
        .fontSize(34)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FF756D')
        .margin({ bottom: 10 })
      Text('弹巢旋转')
        .fontSize(17)
        .fontColor('#E8DDC8')
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  // 扣压扳机（双倍危机事件特判标题）
  @Builder PunishmentTriggerCinematic() {
    Column() {
      this.RevolverArt()
      Text(this.getTriggerTitle())
        .fontSize(34)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FF756D')
        .margin({ bottom: 10 })
      Text(`${this.getPunishedName()} 面对左轮`)
        .fontSize(17)
        .fontColor('#E8DDC8')
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  // 惩罚结果：这一发有/没有子弹
  @Builder PunishmentResultCinematic() {
    Column() {
      this.RevolverArt()
      if (this.game !== null && this.game.punishment !== null && this.game.punishment.hit) {
        Text('这一发有子弹')
          .fontSize(36)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FF756D')
          .margin({ bottom: 8 })
        if (this.game.punishment.totalShots > 1) {
          Text(`第 ${this.game.punishment.shotNumber}/${this.game.punishment.totalShots} 枪 · ${this.getPunishedName()} 已淘汰`)
            .fontSize(16)
            .fontColor('#E8DDC8')
        } else {
          Text(`${this.getPunishedName()} 已淘汰`)
            .fontSize(16)
            .fontColor('#E8DDC8')
        }
      } else {
        Text('这一发没有子弹')
          .fontSize(36)
          .fontWeight(FontWeight.Bold)
          .fontColor('#F2C777')
          .margin({ bottom: 8 })
        if (this.game !== null && this.game.punishment !== null && this.game.punishment.totalShots > 1) {
          Text(`第 ${this.game.punishment.shotNumber}/${this.game.punishment.totalShots} 枪 · ${this.getPunishedName()} 暂时安全`)
            .fontSize(16)
            .fontColor('#E8DDC8')
        } else {
          Text(`${this.getPunishedName()} 暂时安全`)
            .fontSize(16)
            .fontColor('#E8DDC8')
        }
      }
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  // 回合结束：清理牌桌
  @Builder RoundEndCinematic() {
    Column() {
      Text('清理牌桌')
        .fontSize(32)
        .fontWeight(FontWeight.Bold)
        .fontColor('#D4A85D')
        .margin({ bottom: 8 })
      Text('公开牌保持到下一轮开始')
        .fontSize(15)
        .fontColor('#E8DDC8')
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  // 终局（3000ms 后隐藏，交给结算面板）
  @Builder GameOverCinematic() {
    Column() {
      Text('最终胜者')
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor('#D4A85D')
        .margin({ bottom: 10 })
      Text(this.getWinnerName())
        .fontSize(34)
        .fontWeight(FontWeight.Bold)
        .fontColor('#F2C777')
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  // 静态公开牌条（判定/惩罚/回合结束相位，与网页版 StaticRevealedCards 一致）
  @Builder RevealedStrip() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
      ForEach(this.getRevealedCards(), (card: CardRank) => {
        Column() {
          if (card === 'JOKER') {
            Text('★')
              .fontSize(20)
              .fontColor('#5B1F28')
              .fontWeight(FontWeight.Bold)
          } else {
            Text(card)
              .fontSize(20)
              .fontColor('#5B1F28')
              .fontWeight(FontWeight.Bold)
          }
        }
        .width(42)
        .height(60)
        .backgroundColor('#E8DDC8')
        .borderRadius(6)
        .border({
          width: 2,
          color: this.isCardHonest(card) ? '#F2C777' : '#FF756D',
          style: BorderStyle.Solid
        })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .margin(4)
      })
    }
    .width('90%')
    .margin({ top: 18 })
  }
}
