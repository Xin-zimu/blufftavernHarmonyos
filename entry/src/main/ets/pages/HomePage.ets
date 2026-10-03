// 首页页面 - 对应 HomeScreen.tsx
// 提供创建房间和加入房间两个入口

import { SessionStore, globalSessionStore } from '../store/SessionStore'
import { SessionPersistence } from '../store/SessionPersistence'
import { SocketManager } from '../net/SocketManager'
import { router } from '@kit.ArkUI'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { BusinessError } from '@kit.BasicServicesKit'
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
@ComponentV2
struct HomePage {
  // SessionStore 为 @ObservedV2 类，用 @Local 持有以获得 V2 观察能力
  @Local store: SessionStore = globalSessionStore
  // 服务对象无需响应式，aboutToAppear 时从 AppStorage 取回全局实例
  socketManager: SocketManager = new SocketManager(new SessionStore(), new SessionPersistence())
  @Local nickname: string = ''
  @Local roomCode: string = ''
  @Local errorMessage: string = ''
  @Local isProcessing: boolean = false
  private isTop: boolean = true
  private navGuard: boolean = false

  aboutToAppear(): void {
    const sm: SocketManager | undefined = AppStorage.get<SocketManager>('socketManager')
    hilog.info(0xFF00, 'HomePage', `aboutToAppear, AppStorage manager present: ${sm !== undefined}`)
    if (sm !== undefined) {
      this.socketManager = sm
    }
    this.navigateForRoom()
  }

  onPageShow(): void {
    this.isTop = true
  }

  onPageHide(): void {
    this.isTop = false
  }

  // 房间就绪统一导航：创建房间 / 加入房间 / 会话恢复成功后自动进入对应页面
  @Monitor('store.room')
  onRoomChange(monitor: IMonitor): void {
    hilog.info(0xFF00, 'HomePage', 'onRoomChange monitor fired')
    const room = this.store.room
    if (room === null) {
      this.navGuard = false
      return
    }
    this.navigateForRoom()
  }

  private navigateForRoom(): void {
    const room = this.store.room
    if (room === null) {
      return
    }
    if (!this.isTop || this.navGuard) {
      return
    }
    const state = router.getState()
    hilog.info(0xFF00, 'HomePage', `nav decision: path=[${state.path}] name=[${state.name}] index=${state.index}`)
    this.navGuard = true
    router.pushUrl({ url: room.status === 'LOBBY' ? 'pages/LobbyPage' : 'pages/GamePage' })
      .then(() => {
        hilog.info(0xFF00, 'HomePage', 'pushUrl resolved')
      })
      .catch((error: BusinessError) => {
        this.navGuard = false
        hilog.error(0xFF00, 'HomePage', `pushUrl rejected: ${error.message}`)
      })
  }

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
