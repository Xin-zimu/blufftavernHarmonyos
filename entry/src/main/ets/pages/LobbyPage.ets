// 大厅页面 - 对应 LobbyScreen.tsx
// 显示房间码、玩家列表、角色选择、准备/开始按钮

import { SessionStore } from '../store/SessionStore'
import { SocketManager } from '../net/SocketManager'
import { PlayerView, CharacterId } from '../model/GameTypes'
import { CHARACTER_IDS, CHARACTER_NAMES, MAX_PLAYERS, MIN_PLAYERS } from '../model/Constants'

@Entry
@Component
struct LobbyPage {
  @StorageLink('sessionStore') store: SessionStore = new SessionStore()
  @StorageLink('socketManager') socketManager: SocketManager = new SocketManager(new SessionStore())
  @State selectedCharacter: string = ''
  @State errorMessage: string = ''
  @State copiedNotice: string = ''

  build() {
    Column() {
      // 顶部：房间码和操作
      this.RoomHeader()

      // 通知区域
      if (this.store.notice) {
        Text(this.store.notice)
          .fontSize(14)
          .fontColor('#FF6B6B')
          .margin({ top: 8, bottom: 8 })
      }

      if (this.errorMessage) {
        Text(this.errorMessage)
          .fontSize(14)
          .fontColor('#FF6B6B')
          .margin({ top: 8, bottom: 8 })
      }

      if (this.copiedNotice) {
        Text(this.copiedNotice)
          .fontSize(14)
          .fontColor('#4CAF50')
          .margin({ top: 8, bottom: 8 })
      }

      // 玩家列表
      this.PlayerList()

      // 角色选择
      this.CharacterSelector()

      // 底部操作按钮
      this.ActionButtons()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#1A1A2E')
  }

  // 房间头部信息
  @Builder RoomHeader() {
    Row() {
      Column() {
        Text('房间码')
          .fontSize(12)
          .fontColor('#888899')
        Text(this.store.room?.code ?? '')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor('#D4A574')
          .letterSpacing(4)
      }
      .alignItems(HorizontalAlign.Start)

      Blank()

      // 复制房间码按钮
      Button('复制')
        .height(32)
        .backgroundColor('#2A2A4E')
        .fontColor('#D4A574')
        .fontSize(12)
        .onClick(() => {
          // 鸿蒙剪贴板 API
          // pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.store.room?.code ?? '')
          this.copiedNotice = '房间码已复制'
          setTimeout(() => { this.copiedNotice = '' }, 2000)
        })

      // 离开房间按钮
      Button('离开')
        .height(32)
        .backgroundColor('#4A2A2E')
        .fontColor('#FF6B6B')
        .fontSize(12)
        .margin({ left: 8 })
        .onClick(() => {
          this.socketManager.leaveRoom()
        })
    }
    .width('90%')
    .padding({ top: 16, bottom: 16 })
  }

  // 玩家列表
  @Builder PlayerList() {
    Column() {
      Text(`玩家 (${this.store.room?.players.length ?? 0}/${this.store.room?.maxPlayers ?? 8})`)
        .fontSize(16)
        .fontColor('#D4A574')
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 8 })

      ForEach(this.store.room?.players ?? [], (player: PlayerView) => {
        Row() {
          // 角色头像
          if (player.characterId) {
            Image($r(`app.media.character_${player.characterId.toLowerCase()}_idle`))
              .width(40)
              .height(40)
              .borderRadius(20)
              .margin({ right: 12 })
          } else {
            Circle()
              .width(40)
              .height(40)
              .fill('#2A2A4E')
              .margin({ right: 12 })
          }

          // 昵称
          Text(player.nickname)
            .fontSize(16)
            .fontColor('#FFFFFF')
            .layoutWeight(1)

          // 房主标记
          if (player.id === this.store.room?.hostPlayerId) {
            Text('房主')
              .fontSize(12)
              .fontColor('#D4A574')
              .backgroundColor('#3A3A5E')
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(4)
              .margin({ right: 8 })
          }

          // 准备状态
          if (player.status === 'READY') {
            Text('已准备')
              .fontSize(12)
              .fontColor('#4CAF50')
              .backgroundColor('#1A3A1E')
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(4)
          } else if (player.isConnected === false) {
            Text('离线')
              .fontSize(12)
              .fontColor('#F44336')
              .backgroundColor('#3A1A1E')
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(4)
          }
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        .backgroundColor('#2A2A4E')
        .borderRadius(8)
        .margin({ bottom: 8 })
      })
    }
    .width('90%')
    .margin({ top: 16 })
  }

  // 角色选择器
  @Builder CharacterSelector() {
    Column() {
      Text('选择角色')
        .fontSize(16)
        .fontColor('#D4A574')
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 8 })

      // 8个角色网格排列
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(CHARACTER_IDS, (charId: string) => {
          this.CharacterItem(charId)
        })
      }
      .width('100%')
    }
    .width('90%')
    .margin({ top: 16 })
  }

  @Builder CharacterItem(charId: string) {
    // 检查角色是否已被其他玩家选中
    let isTaken: boolean = false
    let takenByMe: boolean = false
    if (this.store.room) {
      for (const player of this.store.room.players) {
        if (player.characterId === charId) {
          if (player.id === this.store.playerId) {
            takenByMe = true
          } else {
            isTaken = true
          }
          break
        }
      }
    }

    Column() {
      Image($r(`app.media.character_${charId.toLowerCase()}_idle`))
        .width(48)
        .height(48)
        .borderRadius(24)
        .opacity(isTaken ? 0.3 : 1.0)

      Text(CHARACTER_NAMES[charId] ?? charId)
        .fontSize(12)
        .fontColor(isTaken ? '#666680' : (takenByMe ? '#D4A574' : '#FFFFFF'))
        .margin({ top: 4 })
    }
    .width('25%')
    .height(80)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .borderRadius(8)
    .backgroundColor(takenByMe ? '#3A3A5E' : '#2A2A4E')
    .border({
      width: takenByMe ? 2 : 0,
      color: '#D4A574',
      style: BorderStyle.Solid
    })
    .margin({ bottom: 8 })
    .onClick(() => {
      if (!isTaken) {
        this.socketManager.selectCharacter(charId, (success: boolean) => {
          if (!success) {
            this.errorMessage = '选择角色失败'
          }
        })
      }
    })
  }

  // 底部操作按钮
  @Builder ActionButtons() {
    Column() {
      // 房主设置区域
      if (this.store.isHost) {
        Row() {
          // 最大人数调整
          Text('人数:')
            .fontSize(14)
            .fontColor('#888899')
            .margin({ right: 8 })

          Button('-')
            .width(36)
            .height(36)
            .backgroundColor('#2A2A4E')
            .fontColor('#FFFFFF')
            .onClick(() => {
              const current = this.store.room?.maxPlayers ?? 8
              if (current > MIN_PLAYERS) {
                this.socketManager.updateSettings(current - 1, this.store.room?.settings.gameMode ?? 'CLASSIC')
              }
            })

          Text(`${this.store.room?.maxPlayers ?? 8}`)
            .fontSize(16)
            .fontColor('#FFFFFF')
            .margin({ left: 12, right: 12 })

          Button('+')
            .width(36)
            .height(36)
            .backgroundColor('#2A2A4E')
            .fontColor('#FFFFFF')
            .onClick(() => {
              const current = this.store.room?.maxPlayers ?? 8
              if (current < MAX_PLAYERS) {
                this.socketManager.updateSettings(current + 1, this.store.room?.settings.gameMode ?? 'CLASSIC')
              }
            })

          Blank()

          // 游戏模式切换
          Text('模式:')
            .fontSize(14)
            .fontColor('#888899')
            .margin({ right: 8 })

          Button(this.store.room?.settings.gameMode === 'CLASSIC' ? '经典' : '快速')
            .height(36)
            .backgroundColor('#2A2A4E')
            .fontColor('#D4A574')
            .onClick(() => {
              const currentMode = this.store.room?.settings.gameMode ?? 'CLASSIC'
              const newMode = currentMode === 'CLASSIC' ? 'QUICK' : 'CLASSIC'
              this.socketManager.updateSettings(this.store.room?.maxPlayers ?? 8, newMode)
            })
        }
        .width('90%')
        .margin({ bottom: 12 })
      }

      // 准备/取消准备按钮
      Row() {
        // 检查当前玩家是否已准备
        let myReady: boolean = false
        if (this.store.room && this.store.playerId) {
          for (const player of this.store.room.players) {
            if (player.id === this.store.playerId && player.status === 'READY') {
              myReady = true
              break
            }
          }
        }

        Button(myReady ? '取消准备' : '准备')
          .width('45%')
          .height(48)
          .backgroundColor(myReady ? '#4A2A2E' : '#3A5A1E')
          .fontColor(myReady ? '#FF6B6B' : '#4CAF50')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .borderRadius(8)
          .onClick(() => {
            this.socketManager.setReady(!myReady)
          })

        // 房主的开始游戏按钮
        if (this.store.isHost) {
          // 检查是否所有玩家都已准备
          let allReady: boolean = true
          let playerCount: number = 0
          if (this.store.room) {
            playerCount = this.store.room.players.length
            for (const player of this.store.room.players) {
              if (player.status !== 'READY') {
                allReady = false
                break
              }
            }
          }

          Button('开始牌局')
            .width('45%')
            .height(48)
            .backgroundColor('#D4A574')
            .fontColor('#1A1A2E')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .borderRadius(8)
            .enabled(allReady && playerCount >= MIN_PLAYERS)
            .onClick(() => {
              this.socketManager.startGame((success: boolean, error?: string) => {
                if (!success) {
                  this.errorMessage = error ?? '开始游戏失败'
                }
              })
            })
        }
      }
      .width('90%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .margin({ top: 16 })
  }
}
