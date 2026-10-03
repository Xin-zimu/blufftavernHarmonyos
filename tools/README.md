# tools/ — 联机探针与 UI 操作脚本

Phase 3 联调验证使用的一组可复用脚本。协议与联调方法见 `docs/联调方法.md`。

## 前置条件

1. 在 `backend/` 执行过 `pnpm install`（探针依赖其中的 `ws` 包）。
2. 游戏服务器已启动（见 `docs/服务端启动.md`）。

探针通过 `tools/ws-lib.mjs` 从**当前工作目录**解析 `ws`，因此必须在
`backend/apps/server` 目录下运行：

```powershell
cd backend/apps/server
node ../../../tools/play-probe.mjs <roomCode>
```

## 脚本清单

| 脚本 | 作用 | 用法 |
|------|------|------|
| `play-probe.mjs` | 第二玩家自动对局探针：join+ready，轮到自己自动出牌，mustChallenge/手牌空时自动质疑，每 10s 主动 @ping，打印全部对局事件 | `node play-probe.mjs <roomCode>` |
| `kick-host.mjs` | 房主探针：创建房间并打印房间码，玩家加入 2.5s 后将其踢出 | `node kick-host.mjs` |
| `join-ready.mjs` | 观察探针：join+ready 后只打印推送不自动操作（留档备用） | `node join-ready.mjs <roomCode>` |
| `click-text.ps1` | 模拟器 UI 操作：dumpLayout → 按文本定位 → 点击中心 | `.\click-text.ps1 -Text "加入房间"` |
| `ws-lib.mjs` | 探针公共库（ws 解析 + URL 默认值） | 被探针 import，不单独运行 |

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `WS_URL` | `ws://127.0.0.1:3001/ws` | 探针连接的服务器 ws 地址 |
| `PROBE_NICKNAME` | 各脚本内置昵称 | 探针在房间中显示的昵称 |
| `HDC_PATH` | DevEco Studio 工具链 | `click-text.ps1` 使用的 hdc.exe 路径 |
| `HDC_TARGET` | `127.0.0.1:5555` | hdc 目标（模拟器默认地址） |
| `DUMP_DIR` | `.\.verify-dumps` | UI dump 文件保存目录 |

## 注意事项

- **心跳协议为客户端主动**：服务器从不主动发 `@ping`，探针每 10s 主动发送，
  服务器回 `@pong`。只响应不主动心跳的连接会在约 45s 空闲后被服务器断开。
- 探针日志前缀：`[P2]` 第二玩家探针、`[H]` 房主探针。
- `click-text.ps1` 每次点击前都会重新 dumpLayout（模拟器重启后 UI 坐标可能偏移，
  不要缓存旧坐标）。
