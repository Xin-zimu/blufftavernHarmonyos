// 规则面板组件 - 显示游戏规则

@Component
export struct RulesPanel {
  @Prop visible: boolean = false
  onClose: () => void = () => {}

  build() {
    if (this.visible) {
      // 半透明遮罩
      Stack() {
        Column() {
          // 标题
          Text('诡牌酒馆 · 规则')
            .fontSize(20)
            .fontColor('#FFD700')
            .fontWeight(FontWeight.Bold)
            .margin({ bottom: 12 })

          // 规则内容
          Scroll() {
            Column() {
              Text('【基本玩法】')
                .fontSize(14)
                .fontColor('#FFD700')
                .fontWeight(FontWeight.Bold)
                .margin({ bottom: 4, top: 8 })
                .alignSelf(ItemAlign.Start)

              Text('每局开始时，系统随机抽取一张目标牌（A、K 或 Joker）。每位玩家轮流从牌堆中抽取一张手牌，然后选择 1-3 张牌打出，声称这就是目标牌。')
                .fontSize(12)
                .fontColor('#CCCCCC')
                .margin({ bottom: 8 })
                .alignSelf(ItemAlign.Start)

              Text('【质疑机制】')
                .fontSize(14)
                .fontColor('#FFD700')
                .fontWeight(FontWeight.Bold)
                .margin({ bottom: 4, top: 8 })
                .alignSelf(ItemAlign.Start)

              Text('当对手打出牌后，你可以选择质疑。如果质疑成功（对手确实在撒谎），对手将接受左轮惩罚；如果质疑失败（对手说的是真话），你将接受惩罚。')
                .fontSize(12)
                .fontColor('#CCCCCC')
                .margin({ bottom: 8 })
                .alignSelf(ItemAlign.Start)

              Text('【左轮惩罚】')
                .fontSize(14)
                .fontColor('#FFD700')
                .fontWeight(FontWeight.Bold)
                .margin({ bottom: 4, top: 8 })
                .alignSelf(ItemAlign.Start)

              Text('惩罚阶段，左轮手枪有 1/6 的概率击发。每轮惩罚会增加一颗子弹。被击中的玩家输掉本局。')
                .fontSize(12)
                .fontColor('#CCCCCC')
                .margin({ bottom: 8 })
                .alignSelf(ItemAlign.Start)

              Text('【胜利条件】')
                .fontSize(14)
                .fontColor('#FFD700')
                .fontWeight(FontWeight.Bold)
                .margin({ bottom: 4, top: 8 })
                .alignSelf(ItemAlign.Start)

              Text('对手被左轮击中，你赢得本局。')
                .fontSize(12)
                .fontColor('#CCCCCC')
                .margin({ bottom: 16 })
                .alignSelf(ItemAlign.Start)
            }
            .width('100%')
            .padding({ left: 16, right: 16 })
          }
          .layoutWeight(1)
          .width('100%')

          // 关闭按钮
          Button('关闭')
            .width(120)
            .height(40)
            .fontSize(14)
            .backgroundColor('#333355')
            .fontColor('#FFFFFF')
            .borderRadius(8)
            .margin({ top: 8, bottom: 16 })
            .onClick(() => {
              this.onClose()
            })
        }
        .width('80%')
        .height('70%')
        .backgroundColor('#1A1A2E')
        .borderRadius(16)
        .border({ width: 1, color: '#444466', style: BorderStyle.Solid })
      }
      .width('100%')
      .height('100%')
      .backgroundColor('rgba(0,0,0,0.7)')
      .onClick(() => {
        this.onClose()
      })
    }
  }
}
