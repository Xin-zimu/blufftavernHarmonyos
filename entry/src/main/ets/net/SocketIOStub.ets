// socket.io-client 本地替代 stub
// 原因：socket.io-client 为 npm 包，ohpm 仓库不存在，无法安装。
// 本 stub 保持与 socket.io-client 相同的调用签名（io / Socket / on / emit），
// 使项目可编译、UI 与单机逻辑可继续开发；联机功能待后续接入真实实现时移除本文件。

import { AckResult, AckError } from '../model/GameTypes'
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN: number = 0x0000
const TAG: string = 'SocketIOStub'

export class Socket {
  connected: boolean = false

  connect(): void {
    hilog.warn(DOMAIN, TAG, 'stub connect(): 联机功能未接入')
  }

  disconnect(): void {
    this.connected = false
    hilog.warn(DOMAIN, TAG, 'stub disconnect()')
  }

  on(event: string, handler: (data: ESObject) => void): void {
    hilog.warn(DOMAIN, TAG, `stub on('${event}')`)
  }

  emit(event: string, payload: ESObject, ack?: (result: AckResult) => void): void {
    hilog.warn(DOMAIN, TAG, `stub emit('${event}')`)
    if (ack !== undefined) {
      const err: AckError = new AckError()
      err.code = 'STUB_NOT_CONNECTED'
      err.message = '联机功能未接入（socket.io-client stub）'
      const result: AckResult = new AckResult()
      result.ok = false
      result.error = err
      ack(result)
    }
  }
}

export function io(serverUrl: string, options: ESObject): Socket {
  hilog.warn(DOMAIN, TAG, `stub io('${serverUrl}')`)
  return new Socket()
}
