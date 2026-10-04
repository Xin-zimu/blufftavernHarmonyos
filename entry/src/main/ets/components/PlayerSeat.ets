// 玩家座位组件 - 对应网页版 game-players 列表项
// 角色头像 + 昵称（你）（离线） + 出牌中 · 角色名 · n 张手牌 / 手牌数量隐藏 / 已淘汰

import { PublicPlayerState } from '../model/GameTypes'
import { getCharacterImage } from '../utils/ArtResources'
import { CHARACTER_NAMES } from '../model/Constants'

@ComponentV2
export struct PlayerSeat {
  @Param player: PublicPlayerState = new PublicPlayerState()
  @Param characterId: string = ''
  @Param characterName: string = ''
  @Param isCurrentTurn: boolean = false
  @Param isMe: boolean = false
  @Param newlyEliminated: boolean = false
  @Param isWinner: boolean = false

  private getHandCountText(): string {
    if (!this.player.alive) {
      return '已淘汰'
    }
    if (this.player.cardCount === null) {
      return '手牌数量隐藏'
    }
    return `${this.player.cardCount} 张手牌`
  }

  private getCharacterName(): string {
    if (this.characterName.length > 0) {
      return this.characterName
    }
    if (this.characterId.length > 0) {
      const name: string | undefined = CHARACTER_NAMES.get(this.characterId)
      if (name !== undefined) {
        return name
      }
    }
    return '未选角色'
  }

  build() {
    Row() {
      // 角色头像
      Stack() {
        if (this.characterId.length > 0 && this.player.alive) {
          Image(getCharacterImage(this.characterId, this.isWinner ? 'victory' : 'idle'))
            .width(44)
            .height(44)
            .borderRadius(22)
            .objectFit(ImageFit.Cover)
        } else if (this.characterId.length > 0) {
          Image(getCharacterImage(this.characterId, 'eliminated'))
            .width(44)
            .height(44)
            .borderRadius(22)
            .objectFit(ImageFit.Cover)
            .grayscale(1)
            .opacity(0.55)
        } else {
          Column() {
            Text(this.player.name.length > 0 ? this.player.name.substring(0, 1) : '?')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#D4A85D')
          }
          .width(44)
          .height(44)
          .backgroundColor('#2B1914')
          .borderRadius(22)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }

        // 当前回合金色描边
        if (this.isCurrentTurn) {
          Circle()
            .width(50)
            .height(50)
            .fill(Color.Transparent)
            .stroke('#F2C777')
            .strokeWidth(2)
        }
      }
      .width(52)
      .height(52)

      // 座位文案
      Column() {
        Row() {
          Text(this.player.name)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.player.alive ? '#E8DDC8' : '#6B5A4A')
          if (this.isMe) {
            Text('（你）')
              .fontSize(12)
              .fontColor('#F2C777')
          }
          if (!this.player.connected) {
            Text('（离线）')
              .fontSize(12)
              .fontColor('#FF756D')
          }
        }
        .constraintSize({ maxWidth: '88%' })

        Row() {
          if (this.isCurrentTurn) {
            Text('出牌中 · ')
              .fontSize(11)
              .fontColor('#F2C777')
          }
          Text(`${this.getCharacterName()} · ${this.getHandCountText()}`)
            .fontSize(11)
            .fontColor(this.player.alive ? '#A67C3D' : '#6B5A4A')
        }
        .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 10 })
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .borderRadius(10)
    .backgroundColor(this.isMe ? '#2B1914' : '#231713')
    .border({
      width: this.isCurrentTurn ? 1 : 1,
      color: this.isCurrentTurn ? '#F2C777' : (this.newlyEliminated ? '#FF756D' : '#4D3830'),
      style: BorderStyle.Solid
    })
    .opacity(this.player.alive ? 1.0 : 0.62)
  }
}
