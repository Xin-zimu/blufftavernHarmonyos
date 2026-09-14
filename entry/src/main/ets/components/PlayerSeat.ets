// 玩家座位组件 - 显示单个玩家的信息

import { PublicPlayerState } from '../model/GameTypes'

@Component
export struct PlayerSeat {
  @Prop player: PublicPlayerState = new PublicPlayerState()
  @Prop isCurrentTurn: boolean = false
  @Prop isMe: boolean = false
  @Prop characterId: string = ''

  build() {
    Column() {
      // 角色头像
      Stack() {
        if (this.characterId) {
          Image($r(`app.media.character_${this.characterId.toLowerCase()}_idle`))
            .width(48)
            .height(48)
            .borderRadius(24)
        } else {
          Circle()
            .width(48)
            .height(48)
            .fill('#2A2A4E')
        }

        // 当前回合标记
        if (this.isCurrentTurn) {
          Circle()
            .width(56)
            .height(56)
            .fill(Color.Transparent)
            .stroke('#D4A574')
            .strokeWidth(2)
        }

        // 淘汰标记
        if (!this.player.alive) {
          Circle()
            .width(48)
            .height(48)
            .fill('#000000')
            .opacity(0.6)
            .borderRadius(24)
        }
      }
      .width(56)
      .height(56)

      // 昵称
      Text(this.player.name)
        .fontSize(12)
        .fontColor(this.player.alive ? '#FFFFFF' : '#666680')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: 80 })

      // 手牌数
      if (this.player.alive) {
        Row() {
          ForEach([1, 2, 3, 4, 5], (i: number) => {
            Circle()
              .width(6)
              .height(6)
              .fill(i <= this.player.cardCount ? '#D4A574' : '#2A2A4E')
              .margin({ left: 2, right: 2 })
          })
        }
        .height(8)
      }

      // 离线标记
      if (!this.player.connected && this.player.alive) {
        Text('离线')
          .fontSize(10)
          .fontColor('#F44336')
      }
    }
    .width(80)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 4, bottom: 4 })
    .borderRadius(8)
    .backgroundColor(this.isMe ? '#3A3A5E' : '#2A2A4E')
    .border({
      width: this.isCurrentTurn ? 2 : 0,
      color: '#D4A574',
      style: BorderStyle.Solid
    })
  }
}
