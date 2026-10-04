// 手牌组件 - 对应网页版 hand 区
// 统一米黄卡面（A/K/Q/JOKER 同卡面，JOKER 用小丑图）；选中上浮 + 金色描边

import { CardRank } from '../model/GameTypes'
import { getCardImage } from '../utils/ArtResources'

@ComponentV2
export struct CardHand {
  @Param hand: CardRank[] = []
  @Param selectedIndexes: number[] = []
  @Param disabled: boolean = false
  @Param reduceMotion: boolean = false
  @Param tipsy: boolean = false
  @Param syncedNow: number = 0
  @Event onCardSelect: (index: number) => void = (index: number) => {}

  // 检查某张牌是否被选中
  private isCardSelected(index: number): boolean {
    for (const idx of this.selectedIndexes) {
      if (idx === index) {
        return true
      }
    }
    return false
  }

  build() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
      ForEach(this.hand, (card: CardRank, index: number) => {
        this.CardItem(card, index)
      })
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }

  @Builder CardItem(card: CardRank, index: number) {
    Column() {
      if (card === 'JOKER') {
        Image(getCardImage('JOKER'))
          .width('100%')
          .height('100%')
          .borderRadius(10)
          .objectFit(ImageFit.Cover)
      } else {
        Text(card)
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor('#5B1F28')
      }
    }
    .width(68)
    .height(100)
    .backgroundColor('#E8DDC8')
    .borderRadius(10)
    .border({
      width: this.isCardSelected(index) ? 2 : 1,
      color: this.isCardSelected(index) ? '#F2C777' : '#A67C3D',
      style: BorderStyle.Solid
    })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .margin({ left: 5, right: 5, top: 5, bottom: 5 })
    .translate({ y: (this.isCardSelected(index) && !this.reduceMotion ? -10 : 0) - this.tipsyProgress(index) * 3 })
    .rotate({ angle: this.tipsyProgress(index) * 0.9 })
    .opacity(this.disabled ? 0.55 : 1.0)
    .animation({ duration: this.reduceMotion ? 0 : 150 })
    .onClick(() => {
      if (!this.disabled) {
        this.onCardSelect(index)
      }
    })
  }

  private tipsyProgress(index: number): number {
    if (!this.tipsy || this.reduceMotion) return 0
    return (1 - Math.cos((this.syncedNow - index * 160) / 1900 * Math.PI * 2)) / 2
  }
}
