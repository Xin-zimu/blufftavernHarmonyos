// 演出动画覆盖层 - 对应 CinematicLayer.tsx
// 根据游戏阶段显示不同的动画演出

import { GameSnapshot, GamePhase, CardRank } from '../model/GameTypes'
import { CINEMATIC_TIMING } from '../model/Constants'

@Component
export struct CinematicOverlay {
  @Prop game: GameSnapshot | null = null
  @State animationOpacity: number = 0
  @State animationScale: number = 1.0
  @State showOverlay: boolean = false

  // 监听游戏阶段变化
  aboutToAppear(): void {
    this.updateAnimation()
  }

  // 当 game 变化时更新动画状态
  private updateAnimation(): void {
    if (!this.game) {
      this.showOverlay = false
      return
    }

    const phase = this.game.phase
    const isCinematicPhase =
      phase === 'ROUND_START' ||
      phase === 'CHALLENGE_CALLOUT' ||
      phase === 'REVEAL' ||
      phase === 'VERDICT' ||
      phase === 'PUNISHMENT_INTRO' ||
      phase === 'PUNISHMENT_TRIGGER' ||
      phase === 'PUNISHMENT_RESULT' ||
      phase === 'GAME_OVER'

    if (isCinematicPhase) {
      this.showOverlay = true
      this.animationOpacity = 0
      this.animationScale = 0.8

      // 入场动画
      animateTo({
        duration: 300,
        curve: Curve.EaseOut,
        onFinish: () => {
          this.animationOpacity = 1
          this.animationScale = 1.0
        }
      }, () => {
        this.animationOpacity = 1
        this.animationScale = 1.0
      })
    } else {
      // 退场动画
      animateTo({
        duration: 200,
        curve: Curve.EaseIn,
        onFinish: () => {
          this.showOverlay = false
        }
      }, () => {
        this.animationOpacity = 0
      })
    }
  }

  // ====== 辅助计算方法（@Builder 外） ======

  // 获取当前回合数（替代 ?? 0）
  private getRoundNumber(): number {
    if (this.game !== null) {
      return this.game.roundNumber
    }
    return 0
  }

  // 获取目标牌显示文本（替代 ?? 链）
  private getTargetRankText(): string {
    if (this.game !== null) {
      if (this.game.targetRank !== null) {
        return this.game.targetRank
      }
      if (this.game.targetCard !== null) {
        return this.game.targetCard
      }
    }
    return 'A'
  }

  // 获取揭示的牌列表（替代 ?? []）
  private getRevealedCards(): CardRank[] {
    if (this.game !== null && this.game.challenge !== null) {
      if (this.game.challenge.revealedCards !== null) {
        return this.game.challenge.revealedCards
      }
    }
    return []
  }

  // 获取质疑者名称
  private getChallengerName(): string {
    if (!this.game || !this.game.challenge) return ''
    for (const player of this.game.players) {
      if (player.playerId === this.game.challenge?.challengerId) return player.name
    }
    return ''
  }

  // 获取被质疑者名称
  private getChallengedName(): string {
    if (!this.game || !this.game.challenge) return ''
    for (const player of this.game.players) {
      if (player.playerId === this.game.challenge?.challengedId) return player.name
    }
    return ''
  }

  // 获取受罚者名称
  private getPunishedName(): string {
    if (!this.game || !this.game.punishment) return ''
    for (const player of this.game.players) {
      if (player.playerId === this.game.punishment?.punishedPlayerId) return player.name
    }
    return ''
  }

  // 获取淘汰者名称
  private getEliminatedName(): string {
    if (!this.game || !this.game.punishment || !this.game.punishment.eliminatedPlayerId) return ''
    for (const player of this.game.players) {
      if (player.playerId === this.game.punishment?.eliminatedPlayerId) return player.name
    }
    return ''
  }

  // 获取胜者名称
  private getWinnerName(): string {
    if (!this.game || !this.game.winnerId) return ''
    for (const player of this.game.players) {
      if (player.playerId === this.game.winnerId) return player.name
    }
    return ''
  }

  build() {
    if (!this.showOverlay || !this.game) {
      Blank()
    } else {
      Stack() {
        // 半透明背景遮罩
        Column() {
          Blank()
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#000000')
        .opacity(this.animationOpacity * 0.6)

        // 演出内容
        Column() {
          this.CinematicContent()
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .opacity(this.animationOpacity)
        .scale({ x: this.animationScale, y: this.animationScale })
      }
      .width('100%')
      .height('100%')
    }
  }

  // 根据当前阶段显示不同演出内容（if-else if 代替 switch）
  @Builder CinematicContent() {
    if (this.game === null) {
      Blank()
    } else if (this.game.phase === 'ROUND_START') {
      this.RoundStartCinematic()
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
    } else if (this.game.phase === 'GAME_OVER') {
      this.GameOverCinematic()
    } else {
      Blank()
    }
  }

  // 回合开始演出
  @Builder RoundStartCinematic() {
    Column() {
      Text(`第 ${this.getRoundNumber()} 回合`)
        .fontSize(32)
        .fontWeight(FontWeight.Bold)
        .fontColor('#D4A574')
        .margin({ bottom: 16 })

      Row() {
        Text('目标牌:')
          .fontSize(20)
          .fontColor('#FFFFFF')
          .margin({ right: 8 })
        Text(this.getTargetRankText())
          .fontSize(36)
          .fontWeight(FontWeight.Bold)
          .fontColor('#D4A574')
      }
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  // 质疑呼叫演出
  @Builder ChallengeCalloutCinematic() {
    Column() {
      Text('质疑!')
        .fontSize(36)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FF6B6B')
        .margin({ bottom: 16 })

      Text(`${this.getChallengerName()} 质疑 ${this.getChallengedName()}`)
        .fontSize(20)
        .fontColor('#FFFFFF')
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  // 翻牌演出
  @Builder RevealCinematic() {
    Column() {
      Text('翻牌!')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor('#D4A574')
        .margin({ bottom: 16 })

      // 显示翻开的牌
      if (this.game !== null && this.game.challenge !== null && this.game.challenge.revealedCards !== null) {
        Row() {
          ForEach(this.getRevealedCards(), (card: CardRank) => {
            Column() {
              if (card === 'JOKER') {
                Text('★')
                  .fontSize(24)
                  .fontColor('#FFD700')
                  .fontWeight(FontWeight.Bold)
              } else {
                Text(card)
                  .fontSize(24)
                  .fontColor('#FFFFFF')
                  .fontWeight(FontWeight.Bold)
              }
            }
            .width(48)
            .height(64)
            .backgroundColor('#2A2A4E')
            .borderRadius(8)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .margin({ left: 8, right: 8 })
            .border({
              width: 2,
              color: '#D4A574',
              style: BorderStyle.Solid
            })
          })
        }
      }
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  // 判定演出
  @Builder VerdictCinematic() {
    Column() {
      if (this.game?.challenge?.wasBluff === true) {
        Text('诈唬!')
          .fontSize(36)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FF6B6B')
          .margin({ bottom: 8 })
        Text('出牌者受罚')
          .fontSize(18)
          .fontColor('#FFFFFF')
      } else if (this.game?.challenge?.wasBluff === false) {
        Text('诚实!')
          .fontSize(36)
          .fontWeight(FontWeight.Bold)
          .fontColor('#4CAF50')
          .margin({ bottom: 8 })
        Text('质疑者受罚')
          .fontSize(18)
          .fontColor('#FFFFFF')
      } else {
        Blank()
      }
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  // 左轮准备演出
  @Builder PunishmentIntroCinematic() {
    Column() {
      Text('左轮手枪')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor('#D4A574')

      Text(`${this.getPunishedName()} 准备接受惩罚`)
        .fontSize(18)
        .fontColor('#FFFFFF')
        .margin({ top: 8 })
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  // 扣动扳机演出
  @Builder PunishmentTriggerCinematic() {
    Column() {
      Text('扣动扳机...')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FF6B6B')
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  // 惩罚结果演出
  @Builder PunishmentResultCinematic() {
    Column() {
      if (this.game?.punishment?.hit) {
        Text('中弹!')
          .fontSize(40)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FF6B6B')
          .margin({ bottom: 8 })

        Text(`${this.getEliminatedName()} 被淘汰`)
          .fontSize(20)
          .fontColor('#FFFFFF')
      } else {
        Text('空枪!')
          .fontSize(40)
          .fontWeight(FontWeight.Bold)
          .fontColor('#4CAF50')
          .margin({ bottom: 8 })

        Text('继续游戏')
          .fontSize(20)
          .fontColor('#FFFFFF')
      }
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  // 游戏结束演出
  @Builder GameOverCinematic() {
    Column() {
      Text('游戏结束')
        .fontSize(36)
        .fontWeight(FontWeight.Bold)
        .fontColor('#D4A574')
        .margin({ bottom: 16 })

      Text(`${this.getWinnerName()} 获胜!`)
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor('#4CAF50')
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
