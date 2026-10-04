// 应用入口 Ability - 管理应用生命周期和全局状态初始化

import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit'
import { window } from '@kit.ArkUI'
import { BusinessError } from '@kit.BasicServicesKit'
import { common } from '@kit.AbilityKit'
import { SessionStore, globalSessionStore } from '../store/SessionStore'
import { SessionPersistence } from '../store/SessionPersistence'
import { SocketManager } from '../net/SocketManager'
import { ServerConfig } from '../net/ServerConfig'
import { AudioManager } from '../audio/AudioManager'
import { accessibility } from '@kit.AccessibilityKit'

function onAnimationReduceChanged(enabled: boolean): void {
  globalSessionStore.systemReduceMotion = enabled
}

export default class EntryAbility extends UIAbility {
  private sessionStore: SessionStore = globalSessionStore
  private sessionPersistence: SessionPersistence = new SessionPersistence()
  private socketManager: SocketManager = new SocketManager(this.sessionStore, this.sessionPersistence)
  private audioManager: AudioManager = new AudioManager()
  private motionListenerActive: boolean = false

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 初始化全局状态
    // 注意：SessionStore 是 @ObservedV2 类，禁止存入 V1 AppStorage（运行时会崩溃），
    // 页面通过 store/SessionStore.ets 的 globalSessionStore 单例共享
    AppStorage.setOrCreate<SocketManager>('socketManager', this.socketManager)
    AppStorage.setOrCreate<AudioManager>('audioManager', this.audioManager)

    // 检测设备性能
    this.detectDevicePerformance()
    try {
      this.sessionStore.systemReduceMotion = accessibility.isAnimationReduceEnabledSync()
      accessibility.onAnimationReduceStateChange(onAnimationReduceChanged)
      this.motionListenerActive = true
    } catch (error) {
      // 不支持系统偏好的设备仍可使用游戏内的手动动画开关。
    }

    // 初始化音效管理器（传入 AbilityContext）
    this.audioManager.init(this.context)

    // 先恢复持久化的会话令牌，再建立连接
    // （连接成功后 SocketManager 会自动用该令牌执行 session:resume 续玩）
    this.sessionPersistence.init(this.context)
      .then((): Promise<string | null> => {
        return this.sessionPersistence.loadToken()
      })
      .then((token: string | null): void => {
        if (token !== null) {
          this.sessionStore.sessionToken = token
        }
        this.socketManager.connect(this.getServerUrl())
      })
      .catch((): void => {
        // 令牌恢复失败不影响连接建立
        this.socketManager.connect(this.getServerUrl())
      })
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // 设置竖屏
    windowStage.getMainWindow().then((mainWindow: window.Window) => {
      mainWindow.setPreferredOrientation(window.Orientation.PORTRAIT)
    })

    // 加载首页
    windowStage.loadContent('pages/HomePage')
  }

  onWindowStageDestroy(): void {
    // 断开 Socket 连接
    this.socketManager.disconnect()
    // 音频统一在 onDestroy 释放，避免两个生命周期回调并发关闭 rawfile 描述符。
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

  onDestroy(): void {
    if (this.motionListenerActive) {
      accessibility.offAnimationReduceStateChange(onAnimationReduceChanged)
      this.motionListenerActive = false
    }
    this.socketManager.disconnect()
    this.audioManager.release()
  }

  // 检测设备性能
  private detectDevicePerformance(): void {
    this.sessionStore.lowPowerActive = false
  }

  // 获取服务器地址（集中配置于 net/ServerConfig.ets）
  getServerUrl(): string {
    return ServerConfig.SERVER_URL
  }
}
