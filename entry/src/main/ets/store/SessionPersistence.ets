// 会话令牌持久化 - 基于 Preferences
// 应用重启后恢复 sessionToken，配合 session:resume 实现断线/重启续玩

import { preferences } from '@kit.ArkData'
import { Context } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN: number = 0x0000
const TAG: string = 'SessionPersistence'

const STORE_NAME: string = 'bluff_tavern_session'
const KEY_TOKEN: string = 'sessionToken'

export class SessionPersistence {
  private store: preferences.Preferences | null = null

  // 初始化 Preferences（应用启动时调用一次）
  async init(context: Context): Promise<void> {
    try {
      this.store = await preferences.getPreferences(context, STORE_NAME)
    } catch (error) {
      const err = error as BusinessError
      hilog.warn(DOMAIN, TAG, `init failed: ${err.code} ${err.message}`)
    }
  }

  // 读取持久化的会话令牌（无则返回 null）
  async loadToken(): Promise<string | null> {
    if (this.store === null) return null
    try {
      const value: preferences.ValueType = await this.store.get(KEY_TOKEN, '')
      return typeof value === 'string' && value.length > 0 ? value : null
    } catch (error) {
      const err = error as BusinessError
      hilog.warn(DOMAIN, TAG, `loadToken failed: ${err.code} ${err.message}`)
      return null
    }
  }

  // 保存会话令牌
  async saveToken(token: string): Promise<void> {
    if (this.store === null || token.length === 0) return
    try {
      await this.store.put(KEY_TOKEN, token)
      await this.store.flush()
    } catch (error) {
      const err = error as BusinessError
      hilog.warn(DOMAIN, TAG, `saveToken failed: ${err.code} ${err.message}`)
    }
  }

  // 清除会话令牌
  async clearToken(): Promise<void> {
    if (this.store === null) return
    try {
      await this.store.delete(KEY_TOKEN)
      await this.store.flush()
    } catch (error) {
      const err = error as BusinessError
      hilog.warn(DOMAIN, TAG, `clearToken failed: ${err.code} ${err.message}`)
    }
  }
}
