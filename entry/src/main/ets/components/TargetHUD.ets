// 目标牌 HUD 组件 - 显示本轮目标牌和轮次编号

import { TargetRank } from '../model/GameTypes'

@Component
export struct TargetHUD {
  @Prop targetRank: TargetRank | null = null
  @Prop targetCard: TargetRank = 'A'
  @Prop roundNumber: number = 0

  build() {
    Row() {
      // 回合编号
      Column() {
        Text('回合')
          .fontSize(10)
          .fontColor('#888899')
        Text(`${this.roundNumber}`)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#D4A574')
      }
      .alignItems(HorizontalAlign.Center)
      .margin({ right: 16 })

      // 目标牌
      Column() {
        Text('目标牌')
          .fontSize(10)
          .fontColor('#888899')
        Row() {
          Text(this.targetRank ?? this.targetCard)
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor('#D4A574')
        }
        .width(48)
        .height(48)
        .backgroundColor('#2A2A4E')
        .borderRadius(8)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .border({
          width: 2,
          color: '#D4A574',
          style: BorderStyle.Solid
        })
      }
      .alignItems(HorizontalAlign.Center)
    }
    .width('90%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .backgroundColor('#2A2A4E')
    .borderRadius(8)
  }
}
