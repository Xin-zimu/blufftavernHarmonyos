// 左轮手枪显示组件 - 惩罚相位显示弹巢状态和结果

import { PublicPunishmentState } from '../model/GameTypes'

@ComponentV2
export struct RevolverDisplay {
  @Param punishment: PublicPunishmentState | null = null

  build() {
    if (this.punishment !== null) {
      Column() {
        // 弹巢位置指示（6 膛位）
        Row() {
          ForEach([0, 1, 2, 3, 4, 5], (chamber: number) => {
            Circle()
              .width(18)
              .height(18)
              .fill(chamber === this.punishment?.chamber ? '#FF756D' : '#2B1914')
              .stroke(chamber === this.punishment?.chamber ? '#FF756D' : '#4D3830')
              .strokeWidth(1)
              .margin({ left: 4, right: 4 })
          })
        }
        .margin({ bottom: 8 })

        // 结果显示
        if (this.punishment?.hit === true) {
          Text('中弹淘汰')
            .fontSize(20)
            .fontColor('#FF756D')
            .fontWeight(FontWeight.Bold)
        } else {
          Text('空枪，继续游戏')
            .fontSize(20)
            .fontColor('#F2C777')
            .fontWeight(FontWeight.Bold)
        }

        // 连击信息（双倍危机）
        if (this.punishment !== null && this.punishment.totalShots > 1) {
          Text(`第 ${this.punishment.shotNumber}/${this.punishment.totalShots} 枪`)
            .fontSize(12)
            .fontColor('#A67C3D')
            .margin({ top: 4 })
        }
      }
      .width('100%')
      .padding(14)
      .backgroundColor('#231713')
      .borderRadius(10)
      .border({ width: 1, color: '#4D3830', style: BorderStyle.Solid })
      .alignItems(HorizontalAlign.Center)
    } else {
      Blank()
    }
  }
}
