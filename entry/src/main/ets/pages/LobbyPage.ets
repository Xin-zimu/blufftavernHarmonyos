// 大厅页面 - 对应 LobbyScreen.tsx
// 显示房间码、玩家列表、角色选择、准备/开始按钮

import { SessionStore } from '../store/SessionStore'
import { SocketManager } from '../net/SocketManager'
import { PlayerView, CharacterId } from '../model/GameTypes'
import { CHARACTER_IDS, CHARACTER_NAMES, MAX_PLAYERS, MIN_PLAYERS } from '../model/Constants'
import { getCharacterIdleImage } from '../utils/ArtResources'

// 辅助函数：替代 ?? 操作符
function getErrorOrDefault(error: string | undefined, defaultMsg: string): string {
  if (error !== undefined && error !== null) {
    return error
  }
  return defaultMsg
}

@Entry
@Component
struct LobbyPage {
  @StorageLink('sessionStore') store: SessionStore = new SessionStore()
  @StorageLink('socketManager') socketManager: SocketManager = new SocketManager(new SessionStore())
  @State selectedCharacter: string = ''
  @State errorMessage: string = ''
  @State copiedNotice: string = ''

  // ====== 计算辅助方法（@Builder 外） ======

  // 获取房间码
  private getRoomCode(): string {
    if (this.store.room !== null) {
      return this.store.room.code
    }
    return ''
  }

  // 获取玩家数量
  private getPlayerCount(): number {
    if (this.store.room !== null) {
      return this.store.room.players.length
    }
    return 0
  }

  // 获取最大玩家数
  private getMaxPlayers(): number {
    if (this.store.room !== null) {
      return this.store.room.maxPlayers
    }
    return 8
  }

  // 获取游戏模式
  private getGameMode(): string {
    if (this.store.room !== null) {
      return this.store.room.settings.gameMode
    }
    return 'CLASSIC'
  }

  // 获取玩家列表
  private getRoomPlayers(): PlayerView[] {
    if (this.store.room !== null) {
      return this.store.room.players
    }
    return []
  }

  // 检查角色是否已被其他玩家选中
  private isCharacterTaken(charId: string): boolean {
    if (!this.store.room) return false
    for (const player of this.store.room.players) {
      if (player.characterId === charId && player.id !== this.store.playerId) {
        return true
      }
    }
    return false
  }

  // 检查角色是否被自己选中
  private isCharacterMine(charId: string): boolean {
    if (!this.store.room) return false
    for (const player of this.store.room.players) {
      if (player.characterId === charId && player.id === this.store.playerId) {
        return true
      }
    }
    return false
  }

  // 检查当前玩家是否已准备
  private getMyReady(): boolean {
    if (!this.store.room || !this.store.playerId) return false
    for (const player of this.store.room.players) {
      if (player.id === this.store.playerId && player.status === 'READY') {
        return true
      }
    }
    return false
  }

  // 检查是否所有玩家都已准备
  private getAllReady(): boolean {
    if (!this.store.room) return false
    for (const player of this.store.room.players) {
      if (player.status !== 'READY') return false
    }
    return true
  }

  // 获取角色中文名
  private getCharacterName(charId: string): string {
    const name = CHARACTER_NAMES.get(charId)
    if (name !== undefined) {
      return name
    }
    return charId
  }

  // 是否为房主
  private isHostPlayer(playerId: string): boolean {
    if (this.store.room !== null) {
      return playerId === this.store.room.hostPlayerId
    }
    return false
  }

  build() {
    Column() {
      // 顶部：房间码和操作
      this.RoomHeader()

      // 通知区域
      if (this.store.notice !== null && this.store.notice !== undefined) {
        Text(this.store.notice)
          .fontSize(14)
          .fontColor('#FF6B6B')
          .margin({ top: 8, bottom: 8 })
      }

      if (this.errorMessage.length > 0) {
        Text(this.errorMessage)
          .fontSize(14)
          .fontColor('#FF6B6B')
          .margin({ top: 8, bottom: 8 })
      }

      if (this.copiedNotice.length > 0) {
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
        Text(this.getRoomCode())
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
      Text(`玩家 (${this.getPlayerCount()}/${this.getMaxPlayers()})`)
        .fontSize(16)
        .fontColor('#D4A574')
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 8 })

      ForEach(this.getRoomPlayers(), (player: PlayerView) => {
        Row() {
          // 角色头像
          if (player.characterId !== null && player.characterId !== undefined) {
            Image(getCharacterIdleImage(player.characterId))
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
          if (this.isHostPlayer(player.id)) {
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
    Column() {
      Image(getCharacterIdleImage(charId))
        .width(48)
        .height(48)
        .borderRadius(24)
        .opacity(this.isCharacterTaken(charId) ? 0.3 : 1.0)

      Text(this.getCharacterName(charId))
        .fontSize(12)
        .fontColor(this.isCharacterTaken(charId) ? '#666680' : (this.isCharacterMine(charId) ? '#D4A574' : '#FFFFFF'))
        .margin({ top: 4 })
    }
    .width('25%')
    .height(80)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .borderRadius(8)
    .backgroundColor(this.isCharacterMine(charId) ? '#3A3A5E' : '#2A2A4E')
    .border({
      width: this.isCharacterMine(charId) ? 2 : 0,
      color: '#D4A574',
      style: BorderStyle.Solid
    })
    .margin({ bottom: 8 })
    .onClick(() => {
      if (!this.isCharacterTaken(charId)) {
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
              const current = this.getMaxPlayers()
              if (current > MIN_PLAYERS) {
                this.socketManager.updateSettings(current - 1, this.getGameMode())
              }
            })

          Text(`${this.getMaxPlayers()}`)
            .fontSize(16)
            .fontColor('#FFFFFF')
            .margin({ left: 12, right: 12 })

          Button('+')
            .width(36)
            .height(36)
            .backgroundColor('#2A2A4E')
            .fontColor('#FFFFFF')
            .onClick(() => {
              const current = this.getMaxPlayers()
              if (current < MAX_PLAYERS) {
                this.socketManager.updateSettings(current + 1, this.getGameMode())
              }
            })

          Blank()

          // 游戏模式切换
          Text('模式:')
            .fontSize(14)
            .fontColor('#888899')
            .margin({ right: 8 })

          Button(this.getGameMode() === 'CLASSIC' ? '经典' : '快速')
            .height(36)
            .backgroundColor('#2A2A4E')
            .fontColor('#D4A574')
            .onClick(() => {
              const currentMode = this.getGameMode()
              const newMode = currentMode === 'CLASSIC' ? 'QUICK' : 'CLASSIC'
              this.socketManager.updateSettings(this.getMaxPlayers(), newMode)
            })
        }
        .width('90%')
        .margin({ bottom: 12 })
      }

      // 准备/取消准备按钮
      Row() {
        Button(this.getMyReady() ? '取消准备' : '准备')
          .width('45%')
          .height(48)
          .backgroundColor(this.getMyReady() ? '#4A2A2E' : '#3A5A1E')
          .fontColor(this.getMyReady() ? '#FF6B6B' : '#4CAF50')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .borderRadius(8)
          .onClick(() => {
            this.socketManager.setReady(!this.getMyReady())
          })

        // 房主的开始游戏按钮
        if (this.store.isHost) {
          Button('开始牌局')
            .width('45%')
            .height(48)
            .backgroundColor('#D4A574')
            .fontColor('#1A1A2E')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .borderRadius(8)
            .enabled(this.getAllReady() && this.getPlayerCount() >= MIN_PLAYERS)
            .onClick(() => {
              this.socketManager.startGame((success: boolean, error?: string) => {
                if (!success) {
                  this.errorMessage = getErrorOrDefault(error, '开始游戏失败')
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
