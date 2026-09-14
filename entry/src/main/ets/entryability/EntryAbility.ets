// 应用入口 Ability - 管理应用生命周期和全局状态初始化

import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit'
import { window } from '@kit.ArkUI'
import { BusinessError } from '@kit.BasicServicesKit'
import { common } from '@kit.AbilityKit'
import { SessionStore } from '../store/SessionStore'
import { SocketManager } from '../net/SocketManager'
import { AudioManager } from '../audio/AudioManager'

export default class EntryAbility extends UIAbility {
  private sessionStore: SessionStore = new SessionStore()
  private socketManager: SocketManager = new SocketManager(this.sessionStore)
  private audioManager: AudioManager = new AudioManager()

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 初始化全局状态
    AppStorage.setOrCreate<SessionStore>('sessionStore', this.sessionStore)
    AppStorage.setOrCreate<SocketManager>('socketManager', this.socketManager)
    AppStorage.setOrCreate<AudioManager>('audioManager', this.audioManager)

    // 检测设备性能
    this.detectDevicePerformance()

    // 初始化音效管理器（传入 AbilityContext）
    this.audioManager.init(this.context)
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // 设置横屏优先（游戏需要横屏）
    windowStage.getMainWindow().then((mainWindow: window.Window) => {
      mainWindow.setPreferredOrientation(window.Orientation.LANDSCAPE)
    })

    // 加载首页
    windowStage.loadUIContent('pages/HomePage')
  }

  onWindowStageDestroy(): void {
    // 断开 Socket 连接
    this.socketManager.disconnect()
    this.audioManager.release()
  }

  onForeground(): void {
    // 应用回到前台时尝试重连
    if (this.sessionStore.sessionToken && !this.socketManager.isConnected()) {
      this.socketManager.connect(this.getServerUrl())
    }
  }

  onBackground(): void {
    // 应用进入后台时保持连接（游戏需要断线重连）
  }

  // 检测设备性能
  private detectDevicePerformance(): void {
    this.sessionStore.lowPowerActive = false
  }

  // 获取服务器地址
  // 开发阶段：修改此处 IP 地址指向你的 Node.js 服务器
  // 生产环境：改为正式域名
  getServerUrl(): string {
    return 'http://192.168.1.100:3001'
  }
}
