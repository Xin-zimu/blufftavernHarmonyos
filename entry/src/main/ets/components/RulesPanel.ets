// 规则面板组件 - 对应网页版 7.2 RulesPanel.tsx
// 基础规则 + 当前模式规则 + 当前事件规则

class RuleItem {
  title: string = ''
  body: string = ''

  constructor(title: string, body: string) {
    this.title = title
    this.body = body
  }
}

@ComponentV2
export struct RulesPanel {
  @Param visible: boolean = false
  @Param gameMode: string = 'CLASSIC'
  @Param tavernEventType: string = ''
  @Event onClose: () => void = () => {}

  private getBaseRules(): RuleItem[] {
    const rules: RuleItem[] = []
    rules.push(new RuleItem('目标牌', '每轮会公布一个目标牌，所有出牌声明都围绕这张牌结算。'))
    rules.push(new RuleItem('出牌', '轮到你时选择 1 至 3 张手牌，实际牌面可以与声明不同。'))
    rules.push(new RuleItem('质疑', '质疑成功则上一手出牌者受罚；质疑失败则质疑者受罚。'))
    rules.push(new RuleItem('Joker', '通常 Joker 视为当前目标牌；若本轮事件明确禁用 Joker，则按事件规则结算。'))
    rules.push(new RuleItem('惩罚', '失败者触发左轮惩罚，命中淘汰，空枪继续。'))
    rules.push(new RuleItem('胜利', '只剩最后一名存活玩家时，本局结束。'))
    return rules
  }

  private getModeRules(): RuleItem[] {
    if (this.gameMode === 'QUICK') {
      return [new RuleItem('快速模式', '每名玩家只有 7 秒行动时间，超时由服务器自动执行合法操作。')]
    }
    if (this.gameMode === 'ESCALATION') {
      return [new RuleItem('加注模式', '本次出牌数量不能少于上一手；手牌不足以跟上时必须质疑。')]
    }
    if (this.gameMode === 'SHARED_REVOLVER') {
      return [new RuleItem('死亡左轮', '全桌共用一把左轮，空膛进度会保留；命中淘汰后重新装填并旋转。')]
    }
    if (this.gameMode === 'FREE_CHALLENGE') {
      return [new RuleItem('全民质疑', '出牌后开启 3 秒质疑窗口，除出牌者外的存活玩家都能抢先质疑；窗口结束后下一名玩家只能继续出牌。')]
    }
    if (this.gameMode === 'PARTY') {
      return [new RuleItem('酒馆乱斗', '每轮开始抽取一个公开事件，事件只影响当前轮，下一轮重新抽取。')]
    }
    return [new RuleItem('经典模式', '只有下一名玩家可以在自己的回合质疑上一手。')]
  }

  private getEventRules(): RuleItem[] {
    if (this.tavernEventType === 'HIDDEN_BET') {
      return [new RuleItem('暗注夜', '其他玩家的剩余手牌数量不会显示，每次出牌的数量也不会立即公开。质疑并翻牌时，才会公开被质疑那一手实际出了几张牌。')]
    }
    if (this.tavernEventType === 'DRUNKEN') {
      return [new RuleItem('醉酒之夜', '本轮出牌方向反转，下一玩家、强制质疑和下一轮起手都按反方向计算。')]
    }
    if (this.tavernEventType === 'RAPID_NIGHT') {
      return [new RuleItem('快速夜', '本轮所有玩家行动时间缩短。')]
    }
    if (this.tavernEventType === 'DOUBLE_DANGER') {
      return [new RuleItem('双倍危机', '本轮受罚者最多连续接受两次左轮判定；第一枪命中时第二枪取消。')]
    }
    if (this.tavernEventType === 'NO_JOKER') {
      return [new RuleItem('禁忌小丑', '本轮 Joker 不再视为目标牌；仍可打出，但质疑时会被判为假牌。')]
    }
    if (this.tavernEventType === 'FORCED_BET') {
      return [new RuleItem('强制豪赌', '本轮首手可出 1 至 3 张；从第二手开始每次至少出 2 张，手牌不足时必须质疑。')]
    }
    if (this.tavernEventType === 'ONE_CARD_ONLY') {
      return [new RuleItem('单张夜', '本轮每次只能出 1 张牌，超时也只会自动出 1 张。')]
    }
    if (this.tavernEventType === 'MATCH_BET') {
      return [new RuleItem('跟注夜', '本轮第一手决定张数，之后所有玩家必须出相同张数；手牌不足时必须质疑。')]
    }
    if (this.tavernEventType === 'HEAVY_HAND') {
      return [new RuleItem('豪饮之夜', '本轮从第一手开始每次至少出 2 张牌，最多仍为 3 张。')]
    }
    if (this.tavernEventType === 'LAST_CALL') {
      return [new RuleItem('最后点单', '本轮每完成一次出牌，下一位玩家行动时间缩短，最低为 6 秒。')]
    }
    if (this.tavernEventType === 'CANDLE_FLICKER') {
      return [new RuleItem('烛火摇曳', '本轮揭牌演出更紧张，核心判定不变。')]
    }
    return []
  }

  private getAllRules(): RuleItem[] {
    const rules: RuleItem[] = []
    for (const item of this.getBaseRules()) {
      rules.push(item)
    }
    for (const item of this.getModeRules()) {
      rules.push(item)
    }
    for (const item of this.getEventRules()) {
      rules.push(item)
    }
    return rules
  }

  build() {
    if (this.visible) {
      // 半透明遮罩 + 规则面板
      Column() {
        Column() {
          // 标题
          Column() {
            Text('游戏规则')
              .fontSize(12)
              .fontColor('#A67C3D')
              .margin({ bottom: 4 })
            Text('诡牌酒馆规则')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor('#F2C777')
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .margin({ bottom: 14 })

          // 规则列表
          Scroll() {
            Column() {
              ForEach(this.getAllRules(), (rule: RuleItem) => {
                Column() {
                  Text(rule.title)
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#F2C777')
                    .margin({ bottom: 4 })
                    .alignSelf(ItemAlign.Start)
                  Text(rule.body)
                    .fontSize(13)
                    .fontColor('#E8DDC8')
                    .lineHeight(20)
                    .alignSelf(ItemAlign.Start)
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
                .padding(12)
                .backgroundColor('#2B1914')
                .borderRadius(10)
                .border({ width: 1, color: '#4D3830', style: BorderStyle.Solid })
                .margin({ bottom: 8 })
              })
            }
            .width('100%')
          }
          .layoutWeight(1)
          .width('100%')
          .align(Alignment.Start)

          // 关闭按钮
          Button('关闭')
            .width('100%')
            .height(44)
            .fontSize(15)
            .backgroundColor('#2B1914')
            .fontColor('#F2C777')
            .borderRadius(10)
            .border({ width: 1, color: '#A67C3D', style: BorderStyle.Solid })
            .margin({ top: 10 })
            .onClick(() => {
              this.onClose()
            })
        }
        .width('86%')
        .height('78%')
        .padding(20)
        .backgroundColor('#231713')
        .borderRadius(16)
        .border({ width: 1, color: '#4D3830', style: BorderStyle.Solid })
      }
      .width('100%')
      .height('100%')
      .backgroundColor('rgba(23,17,15,0.8)')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .onClick(() => {
        this.onClose()
      })
    }
  }
}
