// 首页页面 - 对应 HomeScreen.tsx
// 提供创建房间和加入房间两个入口

import { SessionStore, globalSessionStore } from '../store/SessionStore'
import { SessionPersistence } from '../store/SessionPersistence'
import { SocketManager } from '../net/SocketManager'
import { router } from '@kit.ArkUI'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { validateNickname } from '../model/Protocol'
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
          .fontSize(13)
          .fontColor('#E8DDC8')
          .backgroundColor('#7A2632')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .borderRadius(4)
          .margin({ top: 10 })
          .onClick(() => {
            this.store.setNotice(null)
          })
      }

      // 错误消息
      if (this.errorMessage) {
        Text(this.errorMessage)
          .fontSize(13)
          .fontColor('#D8AAA1')
          .margin({ top: 10, bottom: 10 })
      }

      // 入口面板
      this.EntryPanel()

      // 连接状态指示
      this.ConnectionStatus()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#17110F')
    .backgroundImage($r('app.media.background_bg_01_tavern_v1'))
    .backgroundImageSize(ImageSize.Cover)
    .justifyContent(FlexAlign.Center)
  }

  // 品牌区域
  @Builder BrandArea() {
    Column() {
      Image($r('app.media.ui_game_emblem'))
        .width(88)
        .height(88)
        .objectFit(ImageFit.Contain)
        .margin({ bottom: 12 })
      Text('BLUFF TAVERN')
        .fontSize(12)
        .fontColor('#D4A85D')
        .letterSpacing(6)
        .fontWeight(FontWeight.Bold)

      Text('诡牌酒馆')
        .fontSize(44)
        .fontWeight(FontWeight.Bold)
        .fontColor('#E8DDC8')
        .margin({ top: 8 })

      Text('推开暗门，找张椅子。今晚先从聚齐牌友开始。')
        .fontSize(13)
        .fontColor('#A99B8D')
        .textAlign(TextAlign.Center)
        .margin({ top: 14, bottom: 32 })
        .padding({ left: 24, right: 24 })
    }
    .alignItems(HorizontalAlign.Center)
  }

  // 入口面板（创建/加入）
  @Builder EntryPanel() {
    Column() {
      // 昵称
      Column() {
        Text('酒馆称呼')
          .fontSize(12)
          .fontColor('#C8B9A1')
          .margin({ bottom: 8 })
          .width('100%')
        TextInput({ placeholder: '输入 1–16 字昵称', text: this.nickname })
          .maxLength(MAX_NICKNAME_LENGTH)
          .width('100%')
          .height(50)
          .backgroundColor('#120D0B')
          .fontColor('#F2C777')
          .placeholderColor('#6E625B')
          .borderRadius(4)
          .border({ width: 1, color: '#6E625B' })
          .onChange((value: string) => {
            this.nickname = value
            this.errorMessage = ''
          })
      }
      .width('100%')

      // 创建房间
      Button('创建房间')
        .width('100%')
        .height(50)
        .backgroundColor('#8B303D')
        .fontColor('#E8DDC8')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .borderRadius(4)
        .border({ width: 1, color: '#A67C3D' })
        .margin({ top: 14 })
        .enabled(!this.isProcessing && validateNickname(this.nickname) && this.store.connection === 'connected')
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

      // 分隔线
      Row() {
        Divider()
          .layoutWeight(1)
          .color('#4D3830')
        Text('或凭房间码入席')
          .fontSize(11)
          .fontColor('#82756C')
          .margin({ left: 10, right: 10 })
        Divider()
          .layoutWeight(1)
          .color('#4D3830')
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ top: 28, bottom: 28 })

      // 房间码
      Column() {
        Text('6 位房间码')
          .fontSize(12)
          .fontColor('#C8B9A1')
          .margin({ bottom: 8 })
          .width('100%')
        TextInput({ placeholder: '例如 7K3M9X', text: this.roomCode })
          .maxLength(ROOM_CODE_LENGTH)
          .width('100%')
          .height(50)
          .backgroundColor('#120D0B')
          .fontColor('#F2C777')
          .placeholderColor('#6E625B')
          .borderRadius(4)
          .border({ width: 1, color: '#6E625B' })
          .textAlign(TextAlign.Center)
          .fontWeight(FontWeight.Bold)
          .onChange((value: string) => {
            // 自动过滤非字母数字字符并转大写
            this.roomCode = value.toUpperCase().replace(/[^A-Z0-9]/g, '')
            this.errorMessage = ''
          })
      }
      .width('100%')

      // 加入房间
      Button('加入房间')
        .width('100%')
        .height(50)
        .backgroundColor('#2B1914')
        .fontColor('#E8DDC8')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .borderRadius(4)
        .border({ width: 1, color: '#A67C3D' })
        .margin({ top: 14 })
        .enabled(!this.isProcessing && validateNickname(this.nickname)
          && this.roomCode.length === ROOM_CODE_LENGTH && this.store.connection === 'connected')
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
    .width('86%')
    .constraintSize({ maxWidth: 420 })
    .padding(22)
    .borderRadius(8)
    .border({ width: 1, color: 'rgba(166,124,61,0.5)' })
    .backgroundColor('#231713')
  }

  // 连接状态指示
  @Builder ConnectionStatus() {
    Row() {
      Circle()
        .width(8)
        .height(8)
        .fill(this.store.connection === 'connected' ? '#75A56A' :
              this.store.connection === 'connecting' ? '#D4A85D' : '#BC514C')
        .margin({ right: 6 })

      Text(this.store.connection === 'connected' ? '已连接' :
           this.store.connection === 'connecting' ? '连接中...' : '未连接')
        .fontSize(12)
        .fontColor('#81746B')
    }
    .margin({ top: 30 })
  }
}
