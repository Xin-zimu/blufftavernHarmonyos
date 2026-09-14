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

  // 根据当前阶段显示不同演出内容
  @Builder CinematicContent() {
    if (this.game) {
      switch (this.game.phase) {
        case 'ROUND_START':
          this.RoundStartCinematic()
          break
        case 'CHALLENGE_CALLOUT':
          this.ChallengeCalloutCinematic()
          break
        case 'REVEAL':
          this.RevealCinematic()
          break
        case 'VERDICT':
          this.VerdictCinematic()
          break
        case 'PUNISHMENT_INTRO':
          this.PunishmentIntroCinematic()
          break
        case 'PUNISHMENT_TRIGGER':
          this.PunishmentTriggerCinematic()
          break
        case 'PUNISHMENT_RESULT':
          this.PunishmentResultCinematic()
          break
        case 'GAME_OVER':
          this.GameOverCinematic()
          break
        default:
          Blank()
      }
    }
  }

  // 回合开始演出
  @Builder RoundStartCinematic() {
    Column() {
      Text(`第 ${this.game?.roundNumber ?? 0} 回合`)
        .fontSize(32)
        .fontWeight(FontWeight.Bold)
        .fontColor('#D4A574')
        .margin({ bottom: 16 })

      Row() {
        Text('目标牌:')
          .fontSize(20)
          .fontColor('#FFFFFF')
          .margin({ right: 8 })
        Text(this.game?.targetRank ?? this.game?.targetCard ?? 'A')
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
      // 找到质疑者和被质疑者名称
      let challengerName: string = ''
      let challengedName: string = ''
      if (this.game?.challenge) {
        for (const player of this.game?.players ?? []) {
          if (player.playerId === this.game?.challenge?.challengerId) {
            challengerName = player.name
          }
          if (player.playerId === this.game?.challenge?.challengedId) {
            challengedName = player.name
          }
        }
      }

      Text('质疑!')
        .fontSize(36)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FF6B6B')
        .margin({ bottom: 16 })

      Text(`${challengerName} 质疑 ${challengedName}`)
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
      if (this.game?.challenge?.revealedCards) {
        Row() {
          ForEach(this.game?.challenge?.revealedCards ?? [], (card: CardRank) => {
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
      if (this.game?.challenge?.wasBluff !== null && this.game?.challenge?.wasBluff !== undefined) {
        if (this.game?.challenge?.wasBluff) {
          Text('诈唬!')
            .fontSize(36)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FF6B6B')
            .margin({ bottom: 8 })
          Text('出牌者受罚')
            .fontSize(18)
            .fontColor('#FFFFFF')
        } else {
          Text('诚实!')
            .fontSize(36)
            .fontWeight(FontWeight.Bold)
            .fontColor('#4CAF50')
            .margin({ bottom: 8 })
          Text('质疑者受罚')
            .fontSize(18)
            .fontColor('#FFFFFF')
        }
      }
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  // 左轮准备演出
  @Builder PunishmentIntroCinematic() {
    Column() {
      Image($r('app.media.cinematic_revolver_side_v1'))
        .width(160)
        .height(80)
        .margin({ bottom: 16 })

      Text('左轮手枪')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor('#D4A574')

      // 找到受罚者名称
      let punishedName: string = ''
      if (this.game?.punishment) {
        for (const player of this.game?.players ?? []) {
          if (player.playerId === this.game?.punishment?.punishedPlayerId) {
            punishedName = player.name
            break
          }
        }
      }

      Text(`${punishedName} 准备接受惩罚`)
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
      // 枪口火焰效果
      Image($r('app.media.cinematic_muzzle_flash_smoke_v1'))
        .width(120)
        .height(80)
        .margin({ bottom: 16 })

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

        // 找到淘汰者名称
        let eliminatedName: string = ''
        if (this.game?.punishment?.eliminatedPlayerId) {
          for (const player of this.game?.players ?? []) {
            if (player.playerId === this.game?.punishment?.eliminatedPlayerId) {
              eliminatedName = player.name
              break
            }
          }
        }

        Text(`${eliminatedName} 被淘汰`)
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

      // 找到胜者名称
      let winnerName: string = ''
      if (this.game?.winnerId) {
        for (const player of this.game?.players ?? []) {
          if (player.playerId === this.game?.winnerId) {
            winnerName = player.name
            break
          }
        }
      }

      Text(`${winnerName} 获胜!`)
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor('#4CAF50')
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
