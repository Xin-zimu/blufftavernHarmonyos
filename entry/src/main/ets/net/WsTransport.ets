// 原生 WebSocket 传输层 - 连接服务器 /ws 端点
// 线协议（与服务端 ws-gateway.ts 对齐，全部为 JSON 帧）：
//   客户端 -> 服务端业务请求: { v: 1, id: "c-1", event: "room:create", payload: {...} }
//   服务端 -> 客户端 ack:     { v: 1, id: "c-1", ok: true, data: {...} }
//                            { v: 1, id: "c-1", ok: false, error: { code, message } }
//   服务端 -> 客户端推送:     { v: 1, event: "game:snapshot", payload: {...} }
//   心跳:                    { v: 1, event: "@ping" } / { v: 1, event: "@pong" }
// 客户端不得发送 ack/推送形状的帧（服务端会以协议违规断开）。
//
// 特性：
// - 请求/ack 关联：挂起的 ack 10 秒超时（TIMEOUT），断开时统一失败（DISCONNECTED）
// - 心跳：每 10 秒发送 @ping，连续 3 次未收到 @pong 判定连接死亡并触发重连
// - 重连：意外断开时按 500ms→4000ms 指数退避 + ±20% 抖动重试，连接成功后归零
// - 手动 disconnect() 不触发重连

import { webSocket } from '@kit.NetworkKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AckResult } from '../model/GameTypes'
import { makeErrorAck } from '../model/Protocol'

const DOMAIN: number = 0x0000
const TAG: string = 'WsTransport'

const PROTOCOL_VERSION: number = 1
const ACK_TIMEOUT_MS: number = 10000
const HEARTBEAT_INTERVAL_MS: number = 10000
const HEARTBEAT_MAX_MISSES: number = 3
const RECONNECT_BASE_MS: number = 500
const RECONNECT_MAX_MS: number = 4000
const RECONNECT_JITTER: number = 0.2

// 挂起中的 ack 请求
class PendingAck {
  callback: (result: AckResult) => void
  timerId: number = -1

  constructor(callback: (result: AckResult) => void) {
    this.callback = callback
  }
}

// 从 HTTP 服务器地址推导 WebSocket 端点地址
// http://host:port -> ws://host:port/ws ；https:// -> wss://
export function deriveWsUrl(serverUrl: string): string {
  let url: string = serverUrl.trim()
  if (url.startsWith('https://')) {
    url = 'wss://' + url.substring('https://'.length)
  } else if (url.startsWith('http://')) {
    url = 'ws://' + url.substring('http://'.length)
  } else if (!url.startsWith('ws://') && !url.startsWith('wss://')) {
    url = 'ws://' + url
  }
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1)
  }
  if (url.endsWith('/ws')) {
    return url
  }
  return url + '/ws'
}

export class WsTransport {
  private readonly onPush: (event: string, payload: ESObject) => void
  private readonly onOpenCallback: () => void
  private readonly onCloseCallback: (willReconnect: boolean) => void

  private ws: webSocket.WebSocket | null = null
  private wsUrl: string = ''
  private connected: boolean = false
  private manualClosed: boolean = false
  private generation: number = 0

  private idSeq: number = 0
  private pending: Map<string, PendingAck> = new Map<string, PendingAck>()

  private heartbeatTimer: number = -1
  private heartbeatWaiting: boolean = false
  private heartbeatMisses: number = 0

  private reconnectTimer: number = -1
  private reconnectAttempts: number = 0

  constructor(
    onPush: (event: string, payload: ESObject) => void,
    onOpenCallback: () => void,
    onCloseCallback: (willReconnect: boolean) => void
  ) {
    this.onPush = onPush
    this.onOpenCallback = onOpenCallback
    this.onCloseCallback = onCloseCallback
  }

  // ====== 连接管理 ======

  connect(serverUrl: string): void {
    this.wsUrl = deriveWsUrl(serverUrl)
    this.manualClosed = false
    this.reconnectAttempts = 0
    this.cancelReconnectTimer()
    if (this.ws !== null) {
      // 丢弃旧连接，重开新连接
      this.teardownSocket()
    }
    this.openSocket()
  }

  disconnect(): void {
    this.manualClosed = true
    this.cancelReconnectTimer()
    this.stopHeartbeat()
    if (this.ws !== null) {
      this.teardownSocket()
      this.onCloseCallback(false)
    }
    this.failPendingAcks('DISCONNECTED', '连接已断开')
  }

  isConnected(): boolean {
    return this.connected && this.ws !== null
  }

  isConnecting(): boolean {
    if (this.manualClosed) return false
    if (this.ws !== null && !this.connected) return true
    return this.reconnectTimer !== -1
  }

  // ====== 业务请求发送（请求-ack 关联） ======

  send(event: string, payload: ESObject, callback?: (result: AckResult) => void): void {
    if (!this.isConnected()) {
      if (callback !== undefined) {
        callback(makeErrorAck('NOT_CONNECTED', '未连接到服务器'))
      }
      return
    }
    this.idSeq = this.idSeq + 1
    const id: string = `c-${this.idSeq}`
    const normalizedPayload: ESObject = payload === undefined ? null : payload
    const frame: Record<string, ESObject> = {
      'v': PROTOCOL_VERSION,
      'id': id,
      'event': event,
      'payload': normalizedPayload
    }
    if (callback !== undefined) {
      const pendingAck: PendingAck = new PendingAck(callback)
      pendingAck.timerId = setTimeout(() => {
        const pending: PendingAck | undefined = this.pending.get(id)
        if (pending === undefined) return
        this.pending.delete(id)
        hilog.warn(DOMAIN, TAG, `ack timeout: event=${event}`)
        pending.callback(makeErrorAck('TIMEOUT', '请求超时，请重试'))
      }, ACK_TIMEOUT_MS)
      this.pending.set(id, pendingAck)
    }
    const socket: webSocket.WebSocket | null = this.ws
    if (socket === null) {
      this.clearPending(id)
      if (callback !== undefined) {
        callback(makeErrorAck('NOT_CONNECTED', '未连接到服务器'))
      }
      return
    }
    const text: string = JSON.stringify(frame)
    socket.send(text, (err: BusinessError, value: boolean) => {
      if (err) {
        hilog.warn(DOMAIN, TAG, `send failed: event=${event} code=${err.code}`)
        const pending: PendingAck | undefined = this.pending.get(id)
        if (pending !== undefined) {
          this.pending.delete(id)
          if (pending.timerId !== -1) {
            clearTimeout(pending.timerId)
          }
          pending.callback(makeErrorAck('SEND_FAILED', '发送失败，请重试'))
        }
      }
    })
  }

  // ====== 内部实现 ======

  private openSocket(): void {
    this.generation = this.generation + 1
    const gen: number = this.generation
    this.connected = false
    this.manualClosed = false

    const socket: webSocket.WebSocket = webSocket.createWebSocket()
    this.ws = socket

    socket.on('open', (err: BusinessError, value: Object) => {
      if (gen !== this.generation) return
      if (err) {
        hilog.warn(DOMAIN, TAG, `open error: ${err.code} ${err.message}`)
        return
      }
      hilog.info(DOMAIN, TAG, 'ws connected')
      this.connected = true
      this.reconnectAttempts = 0
      this.startHeartbeat()
      this.onOpenCallback()
    })

    socket.on('message', (err: BusinessError<void>, value: string | ArrayBuffer) => {
      if (gen !== this.generation) return
      if (err) {
        hilog.warn(DOMAIN, TAG, `message error: ${err.code}`)
        return
      }
      if (typeof value !== 'string') return
      this.handleFrame(value)
    })

    socket.on('close', (err: BusinessError, value: webSocket.CloseResult) => {
      if (gen !== this.generation) return
      hilog.info(DOMAIN, TAG, `ws closed: code=${value.code} reason=${value.reason} err=${err ? err.code : 0}`)
      this.handleSocketClosed()
    })

    socket.on('error', (err: BusinessError) => {
      if (gen !== this.generation) return
      hilog.warn(DOMAIN, TAG, `ws error: ${err.code} ${err.message}`)
      if (!this.connected) {
        // 兜底：个别失败场景 close 事件可能不触发，延迟检查并补触发重连
        setTimeout(() => {
          if (gen !== this.generation) return
          if (!this.connected && !this.manualClosed && this.reconnectTimer === -1 && this.ws !== null) {
            this.handleSocketClosed()
          }
        }, 2000)
      }
    })

    hilog.info(DOMAIN, TAG, `connecting to ${this.wsUrl}`)
    socket.connect(this.wsUrl, (err: BusinessError, value: boolean) => {
      if (gen !== this.generation) return
      if (err) {
        hilog.warn(DOMAIN, TAG, `connect failed: ${err.code} ${err.message}`)
        return
      }
      if (!value) {
        hilog.warn(DOMAIN, TAG, 'connect request rejected')
      }
    })
  }

  private teardownSocket(): void {
    this.generation = this.generation + 1
    const socket: webSocket.WebSocket | null = this.ws
    this.ws = null
    this.connected = false
    this.stopHeartbeat()
    if (socket !== null) {
      try {
        socket.off('open')
        socket.off('message')
        socket.off('close')
        socket.off('error')
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'off handlers failed')
      }
      try {
        socket.close((err: BusinessError, value: boolean) => {
          // 关闭结果无需处理
        })
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'close socket failed')
      }
    }
  }

  private handleSocketClosed(): void {
    if (this.ws === null) return
    this.teardownSocket()
    this.failPendingAcks('DISCONNECTED', '连接已断开')
    if (this.manualClosed) {
      this.onCloseCallback(false)
      return
    }
    this.scheduleReconnect()
  }

  private scheduleReconnect(): void {
    this.reconnectAttempts = this.reconnectAttempts + 1
    let delay: number = RECONNECT_BASE_MS * Math.pow(2, this.reconnectAttempts - 1)
    if (delay > RECONNECT_MAX_MS) {
      delay = RECONNECT_MAX_MS
    }
    const jitter: number = delay * RECONNECT_JITTER * (Math.random() * 2 - 1)
    delay = Math.round(delay + jitter)
    hilog.info(DOMAIN, TAG, `reconnect in ${delay}ms (attempt ${this.reconnectAttempts})`)
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = -1
      if (this.manualClosed) return
      this.openSocket()
    }, delay)
    this.onCloseCallback(true)
  }

  private cancelReconnectTimer(): void {
    if (this.reconnectTimer !== -1) {
      clearTimeout(this.reconnectTimer)
      this.reconnectTimer = -1
    }
  }

  // ====== 帧解析 ======

  private handleFrame(raw: string): void {
    let frame: ESObject
    try {
      frame = JSON.parse(raw) as ESObject
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'invalid json frame ignored')
      return
    }
    if (typeof frame !== 'object' || frame === null || Array.isArray(frame)) {
      return
    }
    const rec: Record<string, ESObject> = frame as Record<string, ESObject>
    const version: ESObject = rec['v']
    if (typeof version !== 'number' || version !== PROTOCOL_VERSION) {
      return
    }
    // 系统帧（心跳）
    const event: ESObject = rec['event']
    if (typeof event === 'string') {
      if (event === '@pong') {
        this.heartbeatWaiting = false
        this.heartbeatMisses = 0
        return
      }
      if (event.startsWith('@')) {
        return
      }
      const payload: ESObject = rec['payload']
      this.onPush(event, payload === undefined ? null : payload)
      return
    }
    // ack 帧
    const id: ESObject = rec['id']
    if (typeof id !== 'string') return
    const pending: PendingAck | undefined = this.pending.get(id)
    if (pending === undefined) return
    this.pending.delete(id)
    if (pending.timerId !== -1) {
      clearTimeout(pending.timerId)
    }
    const result: AckResult = new AckResult()
    const ok: ESObject = rec['ok']
    result.ok = ok === true
    if (result.ok) {
      const data: ESObject = rec['data']
      result.data = data === undefined ? null : data
    } else {
      const errorRaw: ESObject = rec['error']
      const errorRec: Record<string, ESObject> | null =
        typeof errorRaw === 'object' && errorRaw !== null && !Array.isArray(errorRaw)
          ? (errorRaw as Record<string, ESObject>)
          : null
      const code: ESObject = errorRec !== null ? errorRec['code'] : undefined
      const message: ESObject = errorRec !== null ? errorRec['message'] : undefined
      result.error.code = typeof code === 'string' ? code : 'UNKNOWN'
      result.error.message = typeof message === 'string' ? message : '未知错误'
    }
    pending.callback(result)
  }

  // ====== 挂起 ack 清理 ======

  private clearPending(id: string): void {
    const pending: PendingAck | undefined = this.pending.get(id)
    if (pending === undefined) return
    this.pending.delete(id)
    if (pending.timerId !== -1) {
      clearTimeout(pending.timerId)
    }
  }

  private failPendingAcks(code: string, message: string): void {
    this.pending.forEach((pending: PendingAck, id: string) => {
      if (pending.timerId !== -1) {
        clearTimeout(pending.timerId)
      }
      pending.callback(makeErrorAck(code, message))
    })
    this.pending.clear()
  }

  // ====== 心跳 ======

  private startHeartbeat(): void {
    this.stopHeartbeat()
    this.heartbeatWaiting = false
    this.heartbeatMisses = 0
    this.heartbeatTimer = setInterval(() => {
      if (this.heartbeatWaiting) {
        this.heartbeatMisses = this.heartbeatMisses + 1
        if (this.heartbeatMisses >= HEARTBEAT_MAX_MISSES) {
          hilog.warn(DOMAIN, TAG, 'heartbeat: 3 pings unanswered, dropping connection')
          this.handleSocketClosed()
          return
        }
      }
      this.heartbeatWaiting = true
      this.sendRawFrame('{"v":1,"event":"@ping"}')
    }, HEARTBEAT_INTERVAL_MS)
  }

  private stopHeartbeat(): void {
    if (this.heartbeatTimer !== -1) {
      clearInterval(this.heartbeatTimer)
      this.heartbeatTimer = -1
    }
    this.heartbeatWaiting = false
    this.heartbeatMisses = 0
  }

  private sendRawFrame(text: string): void {
    const socket: webSocket.WebSocket | null = this.ws
    if (socket === null || !this.connected) return
    socket.send(text, (err: BusinessError, value: boolean) => {
      if (err) {
        hilog.warn(DOMAIN, TAG, `raw send failed: ${err.code}`)
      }
    })
  }
}
