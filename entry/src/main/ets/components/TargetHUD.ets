// 目标牌 HUD 组件 - 对应网页版 RoundTargetHud
// 本轮目标 + 目标牌 + 第 N 轮 · 出牌声明均视为 X

import { TargetRank } from '../model/GameTypes'

@ComponentV2
export struct TargetHUD {
  @Param targetCard: TargetRank = 'A'
  @Param roundNumber: number = 0

  build() {
    Column() {
      Text('本轮目标')
        .fontSize(11)
        .fontColor('#D4A85D')
        .margin({ bottom: 6 })

      // 目标牌牌面（米黄卡面）
      Text(this.targetCard)
        .fontSize(30)
        .fontWeight(FontWeight.Bold)
        .fontColor('#5B1F28')
        .width(52)
        .height(64)
        .textAlign(TextAlign.Center)
        .backgroundColor('#E8DDC8')
        .borderRadius(8)
        .border({ width: 2, color: '#A67C3D', style: BorderStyle.Solid })
        .margin({ bottom: 6 })

      Text(`第 ${this.roundNumber} 轮 · 出牌声明均视为 ${this.targetCard}`)
        .fontSize(12)
        .fontColor('#E8DDC8')
    }
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 10, bottom: 10, left: 14, right: 14 })
    .backgroundColor('#231713')
    .borderRadius(10)
    .border({ width: 1, color: '#4D3830', style: BorderStyle.Solid })
  }
}
