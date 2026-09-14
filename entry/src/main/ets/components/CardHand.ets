// 手牌组件 - 显示当前玩家的手牌，支持选牌交互

import { CardRank } from '../model/GameTypes'
import { MAX_CARDS_PER_PLAY } from '../model/Constants'

@Component
export struct CardHand {
  @Prop hand: CardRank[] = []
  @Link selectedIndexes: number[]
  @Prop disabled: boolean = false
  onCardSelect: (index: number) => void = () => {}

  build() {
    Row() {
      ForEach(this.hand, (card: CardRank, index: number) => {
        this.CardItem(card, index)
      })
    }
    .width('90%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: 8, bottom: 8 })
  }

  @Builder CardItem(card: CardRank, index: number) {
    let isSelected: boolean = this.selectedIndexes.includes(index)

    Column() {
      // 牌面
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

      // 牌面装饰
      if (card === 'A') {
        Text('♠')
          .fontSize(12)
          .fontColor('#888899')
      } else if (card === 'K') {
        Text('♥')
          .fontSize(12)
          .fontColor('#888899')
      } else if (card === 'Q') {
        Text('♦')
          .fontSize(12)
          .fontColor('#888899')
      } else if (card === 'JOKER') {
        Text('JOKER')
          .fontSize(8)
          .fontColor('#FFD700')
      }
    }
    .width(56)
    .height(80)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .borderRadius(8)
    .backgroundColor(isSelected ? '#3A5A1E' : '#2A2A4E')
    .border({
      width: isSelected ? 2 : 1,
      color: isSelected ? '#4CAF50' : '#444466',
      style: BorderStyle.Solid
    })
    .margin({ left: 4, right: 4 })
    .opacity(this.disabled ? 0.5 : 1.0)
    .onClick(() => {
      if (!this.disabled) {
        this.onCardSelect(index)
      }
    })
  }
}
