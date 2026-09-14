// 规则面板组件 - 弹出显示游戏规则

@Component
export struct RulesPanel {
  @Prop isVisible: boolean = false
  onClose: () => void = () => {}

  build() {
    if (this.isVisible) {
      Column() {
        // 标题
        Row() {
          Text('游戏规则')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#D4A574')

          Blank()

          Button('关闭')
            .height(32)
            .backgroundColor('#2A2A4E')
            .fontColor('#888899')
            .onClick(() => {
              this.onClose()
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })

        // 规则内容
        Scroll() {
          Column() {
            this.RuleSection('基本玩法', [
              '2-8人在线诈唬卡牌游戏',
              '每轮随机指定目标牌（A/K/Q）',
              '每位玩家发5张牌（含JOKER）',
              '轮到自己时：出牌 或 质疑上家'
            ])

            this.RuleSection('出牌', [
              '每次可出1-3张牌',
              '声明出的牌都是目标牌',
              'JOKER可充当任意目标牌',
              '出完手牌后，下家必须质疑'
            ])

            this.RuleSection('质疑', [
              '质疑上家出的牌是否真实',
              '若上家诈唬（有假牌）：上家受罚',
              '若上家诚实（全是真牌）：质疑者受罚',
              '受罚方式：左轮手枪扣扳机'
            ])

            this.RuleSection('左轮手枪', [
              '6弹巢，子弹随机位置',
              '中弹者淘汰出局',
              '空枪则继续游戏',
              '最后存活者获胜'
            ])
          }
          .padding(16)
        }
        .layoutWeight(1)
      }
      .width('90%')
      .height('80%')
      .backgroundColor('#1A1A2E')
      .borderRadius(12)
      .border({
        width: 2,
        color: '#D4A574',
        style: BorderStyle.Solid
      })
    } else {
      Blank()
    }
  }

  @Builder RuleSection(title: string, rules: string[]) {
    Column() {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#D4A574')
        .margin({ bottom: 8 })

      ForEach(rules, (rule: string) => {
        Row() {
          Text('•')
            .fontSize(14)
            .fontColor('#D4A574')
            .margin({ right: 8 })
          Text(rule)
            .fontSize(14)
            .fontColor('#FFFFFF')
        }
        .margin({ bottom: 4 })
      })
    }
    .margin({ bottom: 16 })
  }
}
