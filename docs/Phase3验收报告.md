# Phase 3 验收报告（native-ws-checkpoint）

日期：2026-10-03
验证形态：**HarmonyOS App（模拟器）+ Node 探针联机**，非双鸿蒙客户端。
基线：App 端 V2 状态管理（`@ComponentV2`/`@Local`/`@Monitor`）+ router 导航；
服务端双传输（原生 `/ws` + Socket.IO），backend 测试 91/91 通过
（上游全仓 125，差额为未纳入本仓库的 web 测试）。

## 场景验收结果

### 场景1：质疑 / 揭示 / 惩罚 / 状态同步 — 通过

- App 回合内点击"质疑" → 服务器 `challenge_called`（challengerId=App）、
  探针收到 `game:challengeStarted` 广播。
- 演出渲染：揭示牌（★JOKER）、判定（"诚实！"/"诈唬！"）、左轮惩罚
  （"中弹！"/"玩家被淘汰"）均由快照驱动正确显示；质疑后回合正常重开、
  双方新手牌同步。
- 两局胜负均由质疑链决定（探针被淘汰一局、App 被淘汰一局），判定方向两次都正确
  （诚实→质疑者受罚，诈唬→出牌者受罚）。

### 场景2：对局结束 / 再来一局 / 返回大厅 — 通过（含 1 项 bug 修复）

- 4 局完整对局打完，结算面板正确：游戏结束/胜者名/质疑统计（次数、成功、失败）/
  再来一局/返回大厅。
- "再来一局"验证 2 次：`game:restart` 后房间回 PLAYING、新局从回合 1 重新发牌。
- "返回大厅"验证：服务器 `game_returned_to_room`、房间回 LOBBY、App 落到大厅页。
- **修复**：会话恢复后页面栈为 Home→Game 时，"返回大厅"的 `router.back()`
  会错误落回 HomePage。修复为按栈深判断（`Number(router.getLength()) >= 3` 才
  back，否则 `replaceUrl('pages/LobbyPage')`），见 `GamePage.ets`。修复后真实
  复测：强停恢复 → 打完 → 返回大厅，正确落到 LobbyPage。

### 场景3：PLAYING 中断线恢复 — 通过（2 次）

- 对局中（本人回合、倒计时进行中）`aa force-stop` 强停 → 服务器
  `player_disconnected`，对局由服务器自动推进 → 重启 App → `session resumed` +
  服务器 `player_reconnected` → 自动导航进 GamePage，回合数/目标牌/本人手牌/
  当前行动者/倒计时均与探针视角快照一致。

### 附加：被踢 — 通过

- 探针当房主建房，App 经 UI 加入 → 探针 `room:kick` → App 收 `room:kicked`
  后回 HomePage 并提示"你已被房主移出房间"。

## 保留的已验证修复

| 修复 | 位置 |
|------|------|
| 返回大厅导航栈判断（本次新增） | `entry/src/main/ets/pages/GamePage.ets` |
| AppStorage 持有 ObservedV2 store 改为模块单例 | `SocketManager.ets` / store |
| ArkTS 编译修复（fix-1~fix-20 系列，见 git log） | 全局 |

诊断 hilog（info 级）按约定保留在代码中，未做清理构建。

## 剩余限制（未验证 / 未实现）

1. **房主踢人 UI 未实现**（LobbyPage 无踢出按钮），App 主动踢人路径未验证；
   仅验证了被踢方。服务器踢人逻辑由其测试覆盖。
2. 表情（`game:sendEmote`）未验证，App 无对应 UI 入口。
3. 全程为"鸿蒙 App + Node 探针"，无第二台鸿蒙设备，双端真机场景未覆盖。
4. 质疑演出中段（reveal 逐张翻牌瞬间）未逐帧截取，仅演出终态有 UI 证据。
5. App 服务器地址硬编码在 `EntryAbility.ets`（宿主机 LAN IP），换网络环境需改代码重编。

## 本分支内容说明

`phase3/native-ws-checkpoint` 分支包含：

- 鸿蒙工程根目录（全部已验证修复，含 GamePage 返回大厅导航修复）；
- `backend/`：双传输服务端源码（含 shared 协议、workspace/锁文件、91 项测试），
  作为普通源码目录纳入，无嵌套 .git；
- `tools/`：联机探针（play-probe / kick-host / join-ready）与 UI 操作脚本
  （click-text.ps1），本机路径已参数化；
- `docs/`：构建、服务端启动、联调方法与本验收报告。
