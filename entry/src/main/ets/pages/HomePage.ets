// 首页页面 - 对应 HomeScreen.tsx
// 提供创建房间和加入房间两个入口

import { SessionStore } from '../store/SessionStore'
import { SocketManager } from '../net/SocketManager'
import { validateNickname, validateRoomCode } from '../model/Protocol'
import { MAX_NICKNAME_LENGTH, ROOM_CODE_LENGTH } from '../model/Constants'

// 辅助函数：替代 ?? 操作符
function getErrorOrDefault(error: string | undefined, defaultMsg: string): string {
  if (error !== undefined && error !== null) {
    return error
  }
  return defaultMsg
}

@Entry
@Component
struct HomePage {
  @StorageLink('sessionStore') store: SessionStore = new SessionStore()
  @StorageLink('socketManager') socketManager: SocketManager = new SocketManager(new SessionStore())
  @State nickname: string = ''
  @State roomCode: string = ''
  @State errorMessage: string = ''
  @State isProcessing: boolean = false

  build() {
    Column() {
      // 顶部品牌区域
      this.BrandArea()

      // 通知消息
      if (this.store.notice) {
        Text(this.store.notice)
          .fontSize(14)
          .fontColor('#FF6B6B')
          .margin({ top: 10, bottom: 10 })
      }

      // 错误消息
      if (this.errorMessage) {
        Text(this.errorMessage)
          .fontSize(14)
          .fontColor('#FF6B6B')
          .margin({ top: 10, bottom: 10 })
      }

      // 创建房间区域
      this.CreateRoomArea()

      // 分隔线
      Row() {
        Divider()
          .width('40%')
          .color('#D4A574')
        Text('或')
          .fontSize(14)
          .fontColor('#D4A574')
          .margin({ left: 10, right: 10 })
        Divider()
          .width('40%')
          .color('#D4A574')
      }
      .width('80%')
      .margin({ top: 20, bottom: 20 })

      // 加入房间区域
      this.JoinRoomArea()

      // 连接状态指示
      this.ConnectionStatus()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#1A1A2E')
    .justifyContent(FlexAlign.Center)
  }

  // 品牌区域
  @Builder BrandArea() {
    Column() {
      Text('诡牌酒馆')
        .fontSize(42)
        .fontWeight(FontWeight.Bold)
        .fontColor('#D4A574')
        .margin({ bottom: 8 })

      Text('BLUFF TAVERN')
        .fontSize(16)
        .fontColor('#8B7355')
        .letterSpacing(4)
    }
    .margin({ bottom: 40 })
  }

  // 创建房间区域
  @Builder CreateRoomArea() {
    Column() {
      TextInput({ placeholder: '输入昵称', text: this.nickname })
        .maxLength(MAX_NICKNAME_LENGTH)
        .width('80%')
        .height(48)
        .backgroundColor('#2A2A4E')
        .fontColor('#FFFFFF')
        .placeholderColor('#666680')
        .borderRadius(8)
        .onChange((value: string) => {
          this.nickname = value
          this.errorMessage = ''
        })

      Button('创建房间')
        .width('80%')
        .height(48)
        .backgroundColor('#D4A574')
        .fontColor('#1A1A2E')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .borderRadius(8)
        .margin({ top: 12 })
        .enabled(!this.isProcessing && validateNickname(this.nickname))
        .onClick(() => {
          this.isProcessing = true
          this.errorMessage = ''
          this.socketManager.createRoom(this.nickname, (success: boolean, error?: string) => {
            this.isProcessing = false
            if (!success) {
              this.errorMessage = getErrorOrDefault(error, '创建房间失败')
            }
          })
        })
    }
    .width('100%')
  }

  // 加入房间区域
  @Builder JoinRoomArea() {
    Column() {
      TextInput({ placeholder: '输入昵称', text: this.nickname })
        .maxLength(MAX_NICKNAME_LENGTH)
        .width('80%')
        .height(48)
        .backgroundColor('#2A2A4E')
        .fontColor('#FFFFFF')
        .placeholderColor('#666680')
        .borderRadius(8)
        .onChange((value: string) => {
          this.nickname = value
          this.errorMessage = ''
        })

      TextInput({ placeholder: `输入${ROOM_CODE_LENGTH}位房间码`, text: this.roomCode })
        .maxLength(ROOM_CODE_LENGTH)
        .width('80%')
        .height(48)
        .backgroundColor('#2A2A4E')
        .fontColor('#FFFFFF')
        .placeholderColor('#666680')
        .borderRadius(8)
        .margin({ top: 12 })
        .onChange((value: string) => {
          // 自动过滤非字母数字字符并转大写
          this.roomCode = value.toUpperCase().replace(/[^A-Z0-9]/g, '')
          this.errorMessage = ''
        })

      Button('加入房间')
        .width('80%')
        .height(48)
        .backgroundColor('#8B7355')
        .fontColor('#FFFFFF')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .borderRadius(8)
        .margin({ top: 12 })
        .enabled(!this.isProcessing && validateNickname(this.nickname) && validateRoomCode(this.roomCode))
        .onClick(() => {
          this.isProcessing = true
          this.errorMessage = ''
          this.socketManager.joinRoom(this.nickname, this.roomCode, (success: boolean, error?: string) => {
            this.isProcessing = false
            if (!success) {
              this.errorMessage = getErrorOrDefault(error, '加入房间失败')
            }
          })
        })
    }
    .width('100%')
  }

  // 连接状态指示
  @Builder ConnectionStatus() {
    Row() {
      Circle()
        .width(8)
        .height(8)
        .fill(this.store.connection === 'connected' ? '#4CAF50' :
              this.store.connection === 'connecting' ? '#FFC107' : '#F44336')
        .margin({ right: 6 })

      Text(this.store.connection === 'connected' ? '已连接' :
           this.store.connection === 'connecting' ? '连接中...' : '未连接')
        .fontSize(12)
        .fontColor('#888899')
    }
    .margin({ top: 30 })
  }
}
