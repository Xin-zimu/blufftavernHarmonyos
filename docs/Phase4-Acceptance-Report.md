# Phase 4 设备验收报告（web v7.2 对齐）

- 日期：2026-10-04
- 分支：`phase4/web-v72-parity`（未合并 main、未部署线上）
- 设备：Mate 90 Pro 模拟器（127.0.0.1:5555），App 包 `com.blufftavern.app`
- 后端：本机 `http://127.0.0.1:3001`（v7.2.0，验收期以 `P4_DEBUG=1` 启动；**默认不带该变量启动时调试端点完全不注册**，见 app.ts:104）
- 联机组合：**App（模拟器） + Node 探针**（`tools/play-probe.mjs` / `tools/host-probe.mjs`）。双 App 组合未测试。
- 参照：上游 `codex/v7.2-party-expansion`（9e7f88b）+ 网页版源码 `GameScreen.tsx`

## 一、验收结果总览

| # | 验收项 | 结果 | 关键证据 |
|---|--------|------|----------|
| 1 | 大厅/准备/开局流程（含 PARTY） | **PASS** | 房 S7DMGD；修复 B 生效：自己行即时显示"你 · 在线 · 已准备" |
| 2 | 断线重连（3 变体，见 §2.2 限定） | **PASS** | 冷恢复 TBNCDU（~200ms）；服务端重启 backoff 重连；socket 强杀 G9B26Q 618ms 恢复 |
| 3 | 会话替换 SESSION_REPLACED | **PASS** | 修复 C：通知 + 回大厅后可立即建房（不再死局）；旧端不抢回已验证（§2.3） |
| 4 | 再来一局 / 大厅重置（仅房主视角） | **PASS** | 状态重置未准备、设置保留、matchId 每局刷新；**非房主 restart 未验证** |
| 5 | 游戏内开关交互 | **PASS（见 §2.5 翻转/生效区分）** | 三开关翻转、全屏进出、复制战报、音效播放 |
| 6 | 游戏模式 | **5/6 实测通过** | 已测 5 种见 §2.6；QUICK 未测，CUSTOM 不可玩 |

## 二、验收详情

### 2.1 READY 同步 — 已验证
- 修复 B（LobbyPage 玩家列表 ForEach key 由 playerId 生成）：自己点准备后行内状态即时更新，与按钮一致（S7DMGD、PGC5PD、3MSB22 多次复现）。
- 对端 READY 双向可见：探针 ready（probe log `room:state [..:READY]`）与 App 端玩家行显示一致；App ready 后探针同样收到状态推送。
- PARTY 下设置开关锁定（修复 A）实测正常。

### 2.2 断网续玩 — 已验证（含方式限定）
- **冷恢复**（TBNCDU）：对局中 `aa force-stop` 杀 App → 重启直接回到对局/结算；hilog 单条 `session resumed`，服务端单次 `player_reconnected`。
- **服务端重启**（暖路径）：backoff 1191ms→1883ms 单次 resume；超宽限期外 SESSION_NOT_FOUND → "无法恢复会话" + 清 token（永久失效路径）。
- **对局中 socket 强杀**（G9B26Q，`POST /debug/kick` → 服务端 `socket.terminate()` RST 级断连）：ws error → 597ms 重连 → session resumed，共 618ms，对局无缝继续，无 resync 风暴。
- **限定说明**：断连由服务端 terminate 模拟（App 侧表现等价于网络中断）；模拟器无 root 无法执行网卡级断网（ifconfig 拒绝、防火墙需管理员），**真机飞行模式/物理断网未验证**。

### 2.3 会话替换后旧端不抢回 — 已验证
- `tools/resume-probe.mjs` 用 App 的 sessionToken 二连 resume → App 收 SESSION_REPLACED → GamePage 返回大厅 + 通知"你的会话已在新连接中恢复"。
- 杀抢占端后持续观察 12s+：原端无任何重连/抢回；Home/`aa start` 前后台切换均不触发抢回（recoveryBlocked 阻断 resume，传输保持连接）。
- **修复 C（本会话发现）**：原 handler 调 `disconnect()` 使传输永久断开，配合 HomePage:193 `enabled(... && connection === 'connected')` 造成创建/加入按钮永久禁用死局；修复后实测通知后可立即创建新房间（5PRMNN）。

### 2.4 再来一局 / 大厅重置 — 已验证（仅房主视角）
- 结算 → 再来一局 → 大厅重置：全员未准备、模式/V7/角色设置保留、matchId 每局刷新（`G9B26Q-1791055868143-925687` 格式）。
- **非房主视角的再来一局（观察按钮可见性、点击行为、房主确认流程）：未验证**——所有对局中 App 均为房主或对局自动推进结束。

### 2.5 游戏内开关 — 状态翻转与实际生效分开结论

| 开关 | 状态翻转 | 效果实际生效 |
|------|----------|--------------|
| 音效 开↔关 | ✓ 实测 | **开时出声已验证**（hilog `SoundPoolCallBackNapi OnPlayFinished`/`AudioStream Stop end`）；**关后是否静音未验证** |
| 性能 满↔省 | ✓ 实测 | **未验证**（降帧/关闭特效的实际效果无量化证据） |
| 动画 全↔少 | ✓ 实测 | **未验证**（动画实际减弱未对比确认） |
| 全屏 进/出 | ✓ 实测 | ✓ 已验证（状态栏隐藏/恢复、按钮变"退出全屏"） |
| 分享结果（复制战报） | — | ✓ 已验证：剪贴板实测内容 `诡牌酒馆战报：<胜者> 获胜！…`（粘贴回输入框确认） |

- 备注：动画开关早期"点不翻"为**坐标过期假象**（横幅重渲染导致行位移 + 结算浮层遮挡），非代码缺陷。

### 2.6 游戏模式 — 已实测 5 / 6，QUICK 未测

可玩模式全集（shared/constants `PLAYABLE_GAME_MODES`）：CLASSIC、QUICK、PARTY、FREE_CHALLENGE、SHARED_REVOLVER、ESCALATION。CUSTOM 在 GAME_MODES 中但不可玩。

| 模式 | 状态 | 房间 | App 端验证点 |
|------|------|------|--------------|
| CLASSIC 经典 | **已测** | PMBSUA/TBNCDU | 基础流程、质疑、个人轮盘、结算 |
| PARTY 酒馆乱斗 | **已测** | S7DMGD | 事件（强制豪赌/跟注夜）、道具/角色开关锁定（修复 A） |
| FREE_CHALLENGE 全民质疑 | **已测** | 5PRMNN | 质疑窗口 banner/状态/面板/倒计时；窗口外无"质疑上一手"（符合服务端 FREE_WINDOW 模型 mode-rules.ts:56） |
| ESCALATION 加注 | **已测** | PGC5PD | "本次至少出 1 张"、"已出 X 张，至少出 X 张或质疑"动态提示、模式 banner |
| SHARED_REVOLVER 死亡左轮 | **已测** | 3MSB22 | "共享左轮 · 连续空膛：N · 剩余膛位：6" HUD；空膛跨轮保留（0/6→1/5）；结算"轮盘第 3 弹巢：中弹淘汰" |
| QUICK 快速 | **未测** | — | 仅确认卡片与 7 秒倒计时选项存在，未开局实测 |

## 三、本会话代码改动
1. **修复 B**：LobbyPage 玩家列表 ForEach key（:693）。
2. **修复 C**：`SocketManager.ets` SESSION_REPLACED case 移除 `disconnect()`，保持传输（对齐 web）。
3. backend 调试端点（`P4_DEBUG=1` 显式开启才注册，默认关闭，不影响生产行为）：`GET /debug/rooms`、`POST /debug/kick`；`ClientConnection.terminate()`；`RoomStore.debugSnapshot()/getSocketId()`。
4. 新增可复用工具：`tools/host-probe.mjs`（房主探针：建房/设模式/ready/自动开局）、`tools/resume-probe.mjs`（会话抢占探针）。

## 四、未验证项清单
- **网页版视觉对比**：web72 无 node_modules/dist，且无头浏览器无法交互；本次以共享后端行为 + GameScreen.tsx 源码对照代替。
- **双 App 联机组合**（需两台设备/模拟器）。
- **ESCALATION 最少出牌数升至 2**：探针固定出 1 张无法推高下限；UI 显示由服务端状态驱动，未实际演示。
- **QUICK 快速模式**开局实测。
- **非房主 restart**、**音效关闭后静音**、**性能/动画开关的实际效果**、**真机物理断网**（见 §2.2–§2.5）。
- 8 分钟离线超宽限期恢复失败为**预期行为**（服务端移除座位 → SESSION_NOT_FOUND）；会话永久失效后昵称清空需重输（现有设计，非回归）。

## 五、提交前检查结论
- `P4_DEBUG` 调试路由仅 `process.env.P4_DEBUG === '1'` 时注册（app.ts:104），普通启动无调试行为 ✓
- `.gitignore` 覆盖 `*.p12/*.cer/*.p7b/*.jks/*.pem/*.token`、`*.log`、`*.pid`、`dist/`、`build/`、`node_modules/`、`.preview/`、`local.properties`、`.env*` ✓
- diff 无密码/密钥/凭证；`ServerConfig.ets` 中 `192.168.2.66:3001` 为既有仓库内联调地址（原 EntryAbility.ets:85 已存在），本次仅集中化，非新增泄露 ✓
- 验收期临时产物（dumps/截图/pid/log）均在系统 Temp 目录，不在仓库 ✓

## 六、证据文件
- 截图（`Temp\deveco\phase4\shots\`，Temp 不入库）：`app-party-game.jpeg`、`app-party-over.jpeg`、`app-fc-game.jpeg`、`app-sr-game.jpeg`、`app-sr-over.jpeg` 等。
- 探针日志：`probe4.log`～`probe7.log`、`resume-probe.log`；后端日志 `backend-out.log`/`backend-err.log`（均 Temp）。
- 房间历史：PMBSUA、RYMNZU、S7DMGD、TBNCDU、G9B26Q、2KA2B4、5PRMNN、PGC5PD、3MSB22。

## 七、结论
Codex 八项修复 + 修复 A/B/C 后，鸿蒙端在会话韧性（冷恢复/断线续玩/会话替换）与 v7.2 模式 UI 上与网页版行为一致；构建（devecocli build）与 ArkTS 静态检查通过。剩余未验证项（§四）不阻塞本次存档，建议合并前补双 App 联机、QUICK 模式与网页视觉对比。
