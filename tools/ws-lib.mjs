// 公共辅助：从当前工作目录解析 ws 依赖。
// 探针脚本位于 tools/，而 ws 安装在 backend/apps/server/node_modules，
// 因此必须在 backend/apps/server 目录下运行探针（详见 tools/README.md）。
import { createRequire } from 'node:module'
import { resolve } from 'node:path'

const require = createRequire(resolve(process.cwd(), 'probe.js'))

/** 从 cwd 解析 ws 包；找不到时给出可操作的报错。 */
export function loadWebSocket() {
  try {
    return require('ws')
  } catch {
    console.error(
      '[ws-lib] Cannot resolve "ws" from current directory: ' + process.cwd() +
      '\n[ws-lib] Run probes from backend/apps/server (after `pnpm install` in backend/), e.g.:' +
      '\n[ws-lib]   cd backend/apps/server && node ../../../tools/play-probe.mjs <roomCode>'
    )
    process.exit(1)
  }
}

/** 默认 ws://127.0.0.1:3001/ws，可用环境变量 WS_URL 覆盖。 */
export function wsUrl() {
  return process.env.WS_URL || 'ws://127.0.0.1:3001/ws'
}
