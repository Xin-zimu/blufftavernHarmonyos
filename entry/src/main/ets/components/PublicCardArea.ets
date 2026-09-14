// 公共牌区组件 - 显示弃牌堆和上家声明

import { PublicLastPlay, TargetRank } from '../model/GameTypes'

@Component
export struct PublicCardArea {
  @Prop lastPlay: PublicLastPlay | null = null
  @Prop discardCount: number = 0
  @Prop targetRank: TargetRank | null = null

  build() {
    Column() {
      // 弃牌堆计数
      Row() {
        Text('弃牌堆')
          .fontSize(12)
          .fontColor('#888899')
          .margin({ right: 8 })
        Text(`${this.discardCount}`)
          .fontSize(16)
          .fontColor('#D4A574')
          .fontWeight(FontWeight.Bold)
      }
      .margin({ bottom: 8 })

      // 上家声明
      if (this.lastPlay) {
        Row() {
          Text('上家声明:')
            .fontSize(12)
            .fontColor('#888899')
            .margin({ right: 8 })

          // 声称的牌面（始终显示为 targetRank）
          Text(`${this.lastPlay.count}张 ${this.lastPlay.claimedRank}`)
            .fontSize(16)
            .fontColor('#D4A574')
            .fontWeight(FontWeight.Bold)

          // 牌背图标
          Row() {
            ForEach([1, 2, 3], (i: number) => {
              if (i <= this.lastPlay!.count) {
                Column() {
                  Text('?')
                    .fontSize(14)
                    .fontColor('#666680')
                }
                .width(24)
                .height(32)
                .backgroundColor('#2A2A4E')
                .borderRadius(4)
                .margin({ left: 2, right: 2 })
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
              }
            })
          }
          .margin({ left: 8 })
        }
      }
    }
    .width('90%')
    .padding(12)
    .backgroundColor('#2A2A4E')
    .borderRadius(8)
    .alignItems(HorizontalAlign.Center)
  }
}
