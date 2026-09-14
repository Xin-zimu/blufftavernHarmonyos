// 左轮手枪显示组件 - 显示弹巢状态和惩罚结果

import { PublicPunishmentState } from '../model/GameTypes'

@Component
export struct RevolverDisplay {
  @Prop punishment: PublicPunishmentState | null = null

  build() {
    if (this.punishment) {
      Column() {
        // 左轮手枪图标
        Image($r('app.media.cinematic_revolver_side_v1'))
          .width(120)
          .height(60)
          .margin({ bottom: 8 })

        // 弹巢位置指示
        Row() {
          ForEach([0, 1, 2, 3, 4, 5], (chamber: number) => {
            Circle()
              .width(20)
              .height(20)
              .fill(chamber === this.punishment!.chamber ? '#FF6B6B' : '#2A2A4E')
              .stroke(chamber === this.punishment!.chamber ? '#FF6B6B' : '#444466')
              .strokeWidth(1)
              .margin({ left: 4, right: 4 })
          })
        }
        .margin({ bottom: 8 })

        // 结果显示
        if (this.punishment.hit) {
          Text('中弹!')
            .fontSize(24)
            .fontColor('#FF6B6B')
            .fontWeight(FontWeight.Bold)
        } else {
          Text('空枪')
            .fontSize(24)
            .fontColor('#4CAF50')
            .fontWeight(FontWeight.Bold)
        }

        // 淘汰信息
        if (this.punishment.eliminatedPlayerId) {
          Text('玩家被淘汰')
            .fontSize(14)
            .fontColor('#FF6B6B')
            .margin({ top: 4 })
        }
      }
      .width('90%')
      .padding(16)
      .backgroundColor('#2A2A4E')
      .borderRadius(8)
      .alignItems(HorizontalAlign.Center)
    } else {
      Blank()
    }
  }
}
