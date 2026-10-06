// 演出动画覆盖层 - 对应网页版 7.2 CinematicLayer.tsx + cinematic-reveal-state.ts
// 关键原则：所有演出由服务端 phaseStartedAt/phaseEndsAt 驱动
// progress = (syncedNow - phaseStartedAt) / (phaseEndsAt - phaseStartedAt)
// 原生 Animator 插值阶段内时间；服务端决定阶段，重复快照不会重启动画。

import { GameSnapshot, CardRank, GamePhase } from '../model/GameTypes'
import { AnimatorResult } from '@ohos.animator'
import { CardArtwork } from './CardArtwork'
import { RevealCard, StaticRevealedCard } from './RevealCard'
import { keyframe, revealProgress, cinematicIdentity } from './CinematicMotion'

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

  @Param clockOffset: number = 0
  @Local animationElapsed: number = 0
  private animator: AnimatorResult | null = null
  private activeIdentity: string = ''
  private disposed: boolean = false

  aboutToAppear(): void {
    this.disposed = false
    this.startPhaseAnimation(true)
  }

  aboutToDisappear(): void {
    this.disposed = true
    this.stopPhaseAnimation()
  }

  @Monitor('game', 'reduceMotion', 'lowPower')
  onPhaseSnapshot(monitor: IMonitor): void {
    const settingsChanged: boolean = monitor.dirty.includes('reduceMotion') || monitor.dirty.includes('lowPower')
    this.startPhaseAnimation(settingsChanged)
  }

  private phaseIdentity(): string {
    if (this.game === null) return ''
    return cinematicIdentity(this.game.matchId, this.game.roundNumber, this.game.phase, this.game.phaseStartedAt)
  }

  private stopPhaseAnimation(): void {
    if (this.animator !== null) {
      this.animator.onframe = (value: number) => {}
      this.animator.cancel()
      this.animator = null
    }
  }

  private startPhaseAnimation(force: boolean = false): void {
    if (this.disposed) return
    const identity: string = this.phaseIdentity()
    if (!force && identity === this.activeIdentity) return
    this.stopPhaseAnimation()
    this.activeIdentity = identity
    if (this.game === null) { this.animationElapsed = 0; return }
    const elapsed: number = Math.max(0, Date.now() + this.clockOffset - this.game.phaseStartedAt)
    this.animationElapsed = elapsed
    if (this.reduceMotion || this.lowPower || !this.isVisible()) return
    const duration: number = this.game.phaseEndsAt === null ? 3001 : this.getDuration()
    if (elapsed >= duration) return
    const nativeAnimator: AnimatorResult = this.getUIContext().createAnimator({
      duration: duration, delay: -elapsed, easing: 'linear',
      iterations: 1, fill: 'forwards', direction: 'normal', begin: 0, end: duration
    })
    nativeAnimator.onframe = (value: number) => {
      if (!this.disposed && this.activeIdentity === identity) this.animationElapsed = Math.max(this.animationElapsed, value)
    }
    this.animator = nativeAnimator
    nativeAnimator.play()
  }

  private motionDuration(duration: number): number {
    return this.reduceMotion || this.lowPower ? 0 : duration
  }

  // ====== 相位时钟计算 ======

  private getElapsed(): number {
    if (this.game === null) return 0
    if (this.reduceMotion || this.lowPower) return Math.max(0, this.syncedNow - this.game.phaseStartedAt)
    return this.animationElapsed
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
      Stack({ alignContent: Alignment.Bottom }) {
        // 半透明酒馆暗色遮罩
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#94080504')
          .backdropBlur(this.motionOff() ? 0 : 4)

        if (!this.motionOff() && this.game?.phase === 'PUNISHMENT_RESULT' && this.game?.punishment?.hit) {
          Column().width('100%').height('100%').backgroundColor('#FFFFFF')
            .opacity(keyframe(this.getElapsed(), 280, [0, 1], [.86, 0]))
        }

        // 演出面板 + 底部进度条
        Column() {
          this.PhaseContent()
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)

        Column() {
          Row().width(this.getProgressPercent()).height('100%')
            .linearGradient({ angle: 90, colors: [['#A67C3D', 0], ['#F2C777', 1]] })
        }
        .width('72%').constraintSize({ maxWidth: 480 }).height(5)
        .alignItems(HorizontalAlign.Start).backgroundColor('#24E8DDC8').borderRadius(99)
        .align(Alignment.Bottom).margin({ bottom: 18 })
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)
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

        if (this.showRevealedStrip()) {
          this.RevealedStrip()
        }

        if (this.game.phase === 'MATCH_START') {
          Text('酒馆开局')
            .fontSize(30)
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


      }
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .width('92%').constraintSize({ maxWidth: 620, minHeight: 228 })
      .padding(20).borderRadius(8)
      .linearGradient({ angle: 145, colors: [['#EB231511', 0], ['#F50C0807', 1]] })
      .border({ width: 1, color: this.panelColor() })
      .shadow({ radius: 32, color: '#BB000000', offsetY: 24 })
      .translate({ x: this.panelShake() })
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
        CardArtwork({ rank: this.getTargetRankText(), cardWidth: 92 })
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
            CardArtwork({ concealed: true, cardWidth: 22 })
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
        .fontSize(32)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFDFD2')
        .margin({ bottom: 12 })
      Text(`${this.getChallengerName()} 质疑 ${this.getChallengedName()}`)
        .fontSize(19)
        .fontColor('#E8DDC8')
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .scale({ x: this.calloutScale(), y: this.calloutScale() })
    .opacity(this.motionOff() ? 1 : keyframe(this.getElapsed(), 650, [0, 0.58, 1], [0, 1, 1], [0.2, 1, 0.24, 1]))
  }

  // 翻牌演出：序 500ms + 每张 750ms 逐张翻转
  @Builder RevealCinematic() {
    Row({ space: 14 }) {
      ForEach(this.getRevealedCards(), (card: CardRank, index: number) => {
        RevealCard({ rank: card, honest: this.isCardHonest(card),
          progress: revealProgress(this.getElapsed(), index, this.reduceMotion || this.lowPower) })
      }, (card: CardRank, index: number) => `${this.phaseIdentity()}:${index}:${card}`)
    }.justifyContent(FlexAlign.Center).margin({ top: 8, bottom: 8 })
  }

  // 判定：谎言 / 质疑失败（文案对齐网页版 7.2）
  @Builder VerdictCinematic() {
    Column() {
      if (this.game !== null && this.game.challenge !== null && this.game.challenge.wasBluff === true) {
        Text('谎言！')
          .translate({ x: this.verdictX() }).rotate({ angle: this.verdictAngle() })
          .fontSize(32)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FF756D')
          .margin({ bottom: 8 })
        Text(`${this.getPunishedName()} 受罚`)
          .fontSize(18)
          .fontColor('#E8DDC8')
      } else if (this.game !== null && this.game.challenge !== null && this.game.challenge.wasBluff === false) {
        Text('质疑失败')
          .fontSize(32)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.truthColor(242, 199, 119))
          .margin({ bottom: 8 })
        Text(`${this.getPunishedName()} 受罚`)
          .fontSize(18)
          .fontColor(this.truthColor(232, 221, 200))
      }
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .scale({ x: this.truthScale(), y: this.truthScale() })
  }

  // 惩罚开场：弹巢旋转
  // Coordinates and transform origins are percentages of the 1774:887 stage.
  // Six holes rotate independently of the gun image.
  @Builder RevolverArt() {
    Stack({ alignContent: Alignment.TopStart }) {
      Image($r('app.media.cinematic_revolver_side_v1'))
        .syncLoad(true).zIndex(0)
        .width('100%').height('100%').objectFit(ImageFit.Contain)
        .translate({ x: this.recoilX() })
        .rotate({ angle: this.recoilAngle(), centerX: '33%', centerY: '58%' })
      Stack({ alignContent: Alignment.TopStart }) {
        ForEach([0, 1, 2, 3, 4, 5], (index: number) => {
          Column().width('12%').height('18%').borderRadius(99)
            .backgroundColor(this.currentChamber() === index ? '#FFF0B4' : '#8AFFEAB2')
            .opacity(this.currentChamber() === index ? 1 : 0.58)
            .shadow({ radius: this.currentChamber() === index ? 14 : 7, color: '#75F2C777' })
            .position({ x: '44%', y: '7%' })
            .rotate({ angle: index * 60, centerX: '50%', centerY: '240%' })
        }, (index: number) => index.toString())
      }
      .width('13.4%').aspectRatio(1).position({ x: '36.5%', y: '31.5%' })
      .zIndex(1)
      .rotate({ angle: this.cylinderAngle() })
      Image($r('app.media.cinematic_muzzle_flash_smoke_v1'))
        .syncLoad(true).zIndex(2)
        .width('38%').height('48%').objectFit(ImageFit.Contain)
        .position({ x: '77%', y: '25%' })
        .opacity(this.flashOpacity())
        .scale({ x: this.flashScale(), y: this.flashScale(), centerX: '0%', centerY: '50%' })
        .translate({ x: this.flashTranslate() })
        .grayscale(this.game?.punishment?.hit ? 0 : 0.7)
        .brightness(this.game?.punishment?.hit ? 1 : 0.7)
        .blendMode(BlendMode.SCREEN)
    }
    .width(292).height(146)
    .translate({ y: this.triggerValue(5) })
    .rotate({ angle: this.triggerValue(-1.4), centerX: '40%', centerY: '58%' })
    .scale({ x: 1 + this.triggerValue(-0.008), y: 1 + this.triggerValue(-0.008), centerX: '40%', centerY: '58%' })
  }

  private motionOff(): boolean { return this.reduceMotion || this.lowPower }

  private panelColor(): string {
    if (this.game?.phase === 'CHALLENGE_CALLOUT') return '#D15D52'
    if (this.game?.phase === 'PUNISHMENT_TRIGGER' && this.game?.tavernEvent?.type === 'DOUBLE_DANGER') return '#B8FF756D'
    return '#80F2C777'
  }

  private panelShake(): number {
    if (this.motionOff()) return 0
    const duration: number = this.game?.phase === 'CHALLENGE_CALLOUT' ? 380 :
      this.game?.phase === 'PUNISHMENT_RESULT' && this.game?.punishment?.hit ? 420 : 0
    return duration === 0 ? 0 : keyframe(this.getElapsed(), duration, [0, .2, .4, .6, .8, 1], [0, -8, 7, -4, 3, 0])
  }

  private calloutScale(): number {
    return this.motionOff() ? 1 : keyframe(this.getElapsed(), 650, [0, .58, 1], [.82, 1.08, 1], [.2, 1, .24, 1])
  }

  private verdictX(): number {
    return this.motionOff() ? 0 : keyframe(this.getElapsed(), 550, [0, .25, .5, .75, 1], [0, -5, 5, -2, 0])
  }

  private verdictAngle(): number {
    return this.motionOff() ? 0 : keyframe(this.getElapsed(), 550, [0, .25, .5, .75, 1], [0, -1, 1, 0, 0])
  }

  private truthScale(): number {
    return this.motionOff() || this.game?.challenge?.wasBluff !== false ? 1 :
      keyframe(this.getElapsed(), 700, [0, 1], [1.04, 1])
  }

  // ArkUI brightness also affects the transparent layer bounds. Apply the CSS
  // brightness multiplier to glyph colors to preserve transparent text backing.
  private truthColor(red: number, green: number, blue: number): string {
    const gain: number = this.motionOff() ? 1 : keyframe(this.getElapsed(), 700, [0, 1], [1, 1.12])
    return `rgb(${Math.min(255, Math.round(red * gain))},${Math.min(255, Math.round(green * gain))},${Math.min(255, Math.round(blue * gain))})`
  }

  private currentChamber(): number {
    return this.game?.phase === 'PUNISHMENT_RESULT' ? (this.game?.punishment?.chamber ?? -1) : -1
  }

  private cylinderAngle(): number {
    if (this.motionOff()) return 0
    if (this.game?.phase === 'PUNISHMENT_TRIGGER') {
      return keyframe(this.getElapsed(), 340, [0, .76, 1], [-65, 10, 0], [.2, .8, .24, 1])
    }
    // CSS keeps the cylinder spinning in result stages too.
    return (this.getElapsed() % 780) / 780 * 360
  }

  private triggerValue(peak: number): number {
    if (this.motionOff() || this.game?.phase !== 'PUNISHMENT_TRIGGER') return 0
    return keyframe(this.getElapsed(), 720, [0, .48, .72, 1], [0, 0, peak, 0], [.2, .9, .2, 1])
  }

  private recoilX(): number {
    if (this.motionOff() || this.game?.phase !== 'PUNISHMENT_RESULT' || !this.game?.punishment?.hit) return 0
    return keyframe(this.getElapsed(), 300, [0, .34, 1], [0, -18, 0], [.15, .85, .28, 1])
  }

  private recoilAngle(): number { return this.recoilX() / 18 * 2.4 }

  private flashOpacity(): number {
    if (this.motionOff() || this.game?.phase !== 'PUNISHMENT_RESULT') return 0
    return this.game?.punishment?.hit ? keyframe(this.getElapsed(), 480, [0, .12, 1], [0, 1, 0]) :
      keyframe(this.getElapsed(), 720, [0, .24, 1], [0, .34, 0])
  }

  private flashScale(): number {
    return this.game?.punishment?.hit ? keyframe(this.getElapsed(), 480, [0, .12, 1], [.38, 1.04, 1.24]) :
      keyframe(this.getElapsed(), 720, [0, .24, 1], [.42, .7, .88])
  }

  private flashTranslate(): number {
    const percent: number = this.game?.punishment?.hit ? keyframe(this.getElapsed(), 480, [0, .12, 1], [-.16, -.04, .1]) :
      keyframe(this.getElapsed(), 720, [0, .24, 1], [-.12, -.02, .08])
    return 292 * .38 * percent
  }

  @Builder PunishmentIntroCinematic() {
    Column() {
      Text(`${this.getPunishedName()} 受罚`)
        .fontSize(30)
        .fontWeight(FontWeight.Bold)
        .fontColor('#F2C777')
        .margin({ bottom: 10 })
      this.RevolverArt()
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
      Text(this.getTriggerTitle())
        .fontSize(30)
        .fontWeight(FontWeight.Bold)
        .fontColor('#F2C777')
        .margin({ bottom: 10 })
      this.RevolverArt()
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
      if (this.game !== null && this.game.punishment !== null && this.game.punishment.hit) {
        Text('这一发有子弹')
          .fontSize(27)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FF756D')
          .margin({ bottom: 8 })
        this.RevolverArt()
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
          .fontSize(27)
          .fontWeight(FontWeight.Bold)
          .fontColor('#F2C777')
          .margin({ bottom: 8 })
        this.RevolverArt()
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
      if (this.game?.punishment !== null) {
        Text(`弹巢 ${(this.game?.punishment?.chamber ?? 0) + 1}/6 · 第 ${this.game?.punishment?.shotNumber ?? 1}/${this.game?.punishment?.totalShots ?? 1} 枪`)
          .fontSize(12).fontColor('#D4A85D').margin({ top: 8 })
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
        .fontSize(30)
        .fontWeight(FontWeight.Bold)
        .fontColor('#F2C777')
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  // 静态公开牌条（判定/惩罚/回合结束相位，与网页版 StaticRevealedCards 一致）
  @Builder RevealedStrip() {
    Row({ space: 10 }) {
      ForEach(this.getRevealedCards(), (card: CardRank) => {
        StaticRevealedCard({ rank: card, honest: this.isCardHonest(card) })
      }, (card: CardRank, index: number) => `${this.game?.matchId}:${this.game?.roundNumber}:${index}:${card}`)
    }.justifyContent(FlexAlign.Center).margin({ bottom: 12 })
  }
}
