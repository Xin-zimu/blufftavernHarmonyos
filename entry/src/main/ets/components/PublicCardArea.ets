// 公共牌区组件 - 对应网页版 TablePile + game-table-pile.ts
// 揭牌相位显示公开牌；平时显示牌背；暗注夜恒 1 张牌背且数量隐藏

import { PublicLastPlay, TargetRank, CardRank } from '../model/GameTypes'

const TABLE_REVEAL_PHASES: string[] = ['VERDICT', 'PUNISHMENT_INTRO', 'PUNISHMENT_TRIGGER', 'PUNISHMENT_RESULT', 'ROUND_END']

@ComponentV2
export struct PublicCardArea {
  @Param phase: string = 'LOBBY'
  @Param lastPlay: PublicLastPlay | null = null
  @Param lastPlayerName: string = ''
  @Param discardCount: number | null = null
  @Param targetCard: TargetRank = 'A'
  @Param revealedCards: CardRank[] = []

  private isRevealPhase(): boolean {
    for (const phase of TABLE_REVEAL_PHASES) {
      if (phase === this.phase) {
        return true
      }
    }
    return false
  }

  // 是否为暗注夜（count 隐藏）
  private isHiddenBet(): boolean {
    return this.lastPlay !== null && this.lastPlay.count === null
  }

  // 牌背数量（与网页版 pileCards 逻辑一致，最多显示 3 张）
  private getPileBackCount(): number {
    const visibleDiscard: number = this.discardCount ?? 0
    const lastCount: number = this.lastPlay !== null && this.lastPlay.count !== null ? this.lastPlay.count : 0
    const raw: number = this.isHiddenBet() ? 1 : Math.max(lastCount > 0 ? lastCount : Math.min(visibleDiscard, 3), visibleDiscard > 0 ? 1 : 0)
    return Math.min(raw, 3)
  }

  // 上家声明文案（与网页版 describeLastPlay 一致）
  private getLastPlayText(): string {
    if (this.lastPlay === null) {
      return '本轮尚未有人出牌'
    }
    const playerName: string = this.lastPlayerName.length > 0 ? this.lastPlayerName : '玩家'
    if (this.lastPlay.count === null) {
      return `${playerName} 已下注，声明了一手 ${this.lastPlay.claimedRank}`
    }
    return `${playerName} 声明：${this.lastPlay.count} 张 ${this.lastPlay.claimedRank}`
  }

  // 底部小字（与网页版一致）
  private getFootnoteText(): string {
    if (this.isRevealPhase()) {
      return '已公开至本轮结束'
    }
    if (this.lastPlay !== null) {
      return this.isHiddenBet() ? '数量暂时隐藏' : '当前可质疑对象'
    }
    return `目标牌是 ${this.targetCard}`
  }

  build() {
    Column() {
      // 牌堆：揭牌相位显示公开牌，平时显示牌背
      if (this.isRevealPhase() && this.revealedCards.length > 0) {
        Row() {
          ForEach(this.revealedCards, (card: CardRank) => {
            Text(card === 'JOKER' ? '★' : card)
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor('#5B1F28')
              .width(40)
              .height(56)
              .textAlign(TextAlign.Center)
              .backgroundColor('#E8DDC8')
              .borderRadius(6)
              .border({ width: 1, color: '#A67C3D', style: BorderStyle.Solid })
              .margin({ left: 3, right: 3 })
          })
        }
        .margin({ bottom: 8 })
      } else if (this.getPileBackCount() > 0) {
        Row() {
          ForEach([0, 1, 2], (i: number) => {
            if (i < this.getPileBackCount()) {
              Column() {
                Image($r('app.media.card_card_back'))
                  .width('100%')
                  .height('100%')
                  .objectFit(ImageFit.Cover)
              }
              .width(36)
              .height(50)
              .backgroundColor('#5B1F28')
              .borderRadius(6)
              .border({ width: 1, color: '#A67C3D', style: BorderStyle.Solid })
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .margin({ left: 3, right: 3 })
            }
          })
        }
        .margin({ bottom: 8 })
      } else {
        Text('等待出牌')
          .fontSize(14)
          .fontColor('#6B5A4A')
          .fontStyle(FontStyle.Italic)
          .margin({ bottom: 8 })
      }

      Text('公共牌区')
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor('#E8DDC8')
        .margin({ bottom: 4 })

      Text(this.getLastPlayText())
        .fontSize(12)
        .fontColor('#A67C3D')
        .margin({ bottom: 4 })

      Text(this.getFootnoteText())
        .fontSize(11)
        .fontColor('#6B5A4A')
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#231713')
    .borderRadius(10)
    .border({ width: 1, color: '#4D3830', style: BorderStyle.Solid })
    .alignItems(HorizontalAlign.Center)
  }
}
