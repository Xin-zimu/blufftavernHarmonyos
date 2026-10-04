# Phase 4 修复交付与 GLM 验收

日期：2026-10-04。依据 Phase4-Review.md 的八项问题，修改前重新读取了目标工作区，八项均仍存在。保留 GLM 已有未提交修改，以针对性补丁修复；没有用审查副本源码覆盖工作区。

## 逐项结果

| 报告项 | 状态 | 本次实现 |
|---|---|---|
| 1 临时失败丢会话 | 已修复 | 未连接不发恢复、不消耗节流；只允许一个在途恢复；临时错误保留 token 并延迟重试；只有服务端现有永久失效码 SESSION_NOT_FOUND 清理 token、room、game |
| 2 被替换客户端抢回会话 | 已修复 | SESSION_REPLACED 清理会话并断开，取消重试；会话/连接代际使旧 ACK、旧 open/message/close 回调失效；前台连接不能恢复旧 token；显式创建/加入新会话仍可用 |
| 3 直接 restart 卡旧结算 | 已修复 | 服务端公开已有 matchId，客户端按新局标识重置并拒绝已结束对局的迟到快照；兼容旧服务端 GAME_OVER→PLAYING 权威房间边界；gameEpoch 清理选牌、音效去重、规则层及旧分享提示 |
| 4 性能/减少动画无效 | 已修复 | 省电刷新从 100ms 调整为 250ms，停用非必要发牌/枪口动态效果；减少动画停止手牌位移、酒杯晃动和演出过渡；保持翻牌时间和真实阶段截止时间；支持系统减少动画监听与手动覆盖 |
| 5 酒杯只有文案 | 已修复 | 本人未过期 TAVERN_MUG_TIPSY 驱动 1.9 秒手牌轻微晃动，期满归零；低功耗/减少动画时停止晃动，保留提示；不改变任何牌值或判定 |
| 6 音效文件缺失 | 已修复 | 按上游音调、时长与噪声参数离线合成 12 个 PCM WAV；区分真假判定及转弹巢/扣扳机；通过 getRawFd+SoundPool.load(fd,offset,length) 加载，loadComplete 后可播；静音停止活跃音效且不振动，释放后关闭描述符 |
| 7 分享结果缺失 | 已修复 | 结算提供“分享结果（复制战报）”，含胜者、人数、时间、质疑统计和淘汰顺序；使用原生剪贴板，并显示成功/失败结果 |
| 8 演出素材未接入 | 已修复 | 首页徽章、首页/大厅/游戏/结算背景、公共区与揭牌牌背、赢家 victory 头像已接入；新增上游左轮/枪口素材并用于惩罚演出 |
| 其他平台入口 | 已修复 | 游戏页提供原生全屏：窗口布局、系统栏和自动旋转；退出页面恢复竖屏。结算改为可滚动，支持较小高度 |
| 设备验收 | 仍待 GLM 运行验证 | 本次没有操作模拟器/HDC。代码与构建无阻断；最终视觉、SoundPool 实际播放和系统窗口行为不能由 Node 测试证明 |

“最新代码已解决”：本轮八项问题没有属于此状态的项目，均在最新代码中确认仍存在后进行了修复。

## 关键文件

- [entry/src/main/ets/net/SocketManager.ets](D:/HUAWEI-DEV/Bluff-Tavern-HARMONEYOS/entry/src/main/ets/net/SocketManager.ets:151)：会话结束、回调隔离、单在途恢复和重试、新局快照处理。
- [entry/src/main/ets/store/SessionPersistence.ets](D:/HUAWEI-DEV/Bluff-Tavern-HARMONEYOS/entry/src/main/ets/store/SessionPersistence.ets)：串行提交 token 写入/清除，防止较早 save 异步完成覆盖替换后的清理。
- [entry/src/main/ets/store/SessionStore.ets](D:/HUAWEI-DEV/Bluff-Tavern-HARMONEYOS/entry/src/main/ets/store/SessionStore.ets)、[entry/src/main/ets/model/Parsers.ets](D:/HUAWEI-DEV/Bluff-Tavern-HARMONEYOS/entry/src/main/ets/model/Parsers.ets)、[entry/src/main/ets/model/GameTypes.ets](D:/HUAWEI-DEV/Bluff-Tavern-HARMONEYOS/entry/src/main/ets/model/GameTypes.ets)：gameEpoch、系统动画偏好、matchId 模型和解析。
- [backend/apps/server/src/game/game-service.ts](D:/HUAWEI-DEV/Bluff-Tavern-HARMONEYOS/backend/apps/server/src/game/game-service.ts:562)、[backend/packages/shared/src/types/index.ts](D:/HUAWEI-DEV/Bluff-Tavern-HARMONEYOS/backend/packages/shared/src/types/index.ts:221)：公开原本已有的对局标识（可选新增字段，兼容旧客户端）。不改变六种模式规则、随机抽取过程、隐私分发或协议事件名称。
- [entry/src/main/ets/pages/GamePage.ets](D:/HUAWEI-DEV/Bluff-Tavern-HARMONEYOS/entry/src/main/ets/pages/GamePage.ets:138)：新局界面清理、酒杯、偏好消费、战报、原生全屏、可滚动结算。
- [entry/src/main/ets/components/CinematicOverlay.ets](D:/HUAWEI-DEV/Bluff-Tavern-HARMONEYOS/entry/src/main/ets/components/CinematicOverlay.ets)、[entry/src/main/ets/components/CardHand.ets](D:/HUAWEI-DEV/Bluff-Tavern-HARMONEYOS/entry/src/main/ets/components/CardHand.ets)、[entry/src/main/ets/components/PublicCardArea.ets](D:/HUAWEI-DEV/Bluff-Tavern-HARMONEYOS/entry/src/main/ets/components/PublicCardArea.ets)、[entry/src/main/ets/components/PlayerSeat.ets](D:/HUAWEI-DEV/Bluff-Tavern-HARMONEYOS/entry/src/main/ets/components/PlayerSeat.ets)：实际演出与资源接入。
- [entry/src/main/ets/audio/AudioManager.ets](D:/HUAWEI-DEV/Bluff-Tavern-HARMONEYOS/entry/src/main/ets/audio/AudioManager.ets:54)、[scripts/generate-audio.cjs](D:/HUAWEI-DEV/Bluff-Tavern-HARMONEYOS/scripts/generate-audio.cjs)、[entry/src/main/ets/entryability/EntryAbility.ets](D:/HUAWEI-DEV/Bluff-Tavern-HARMONEYOS/entry/src/main/ets/entryability/EntryAbility.ets)：打包音效加载、生成器、系统动画偏好与生命周期清理。
- [tests/harmony-session.test.cjs](D:/HUAWEI-DEV/Bluff-Tavern-HARMONEYOS/tests/harmony-session.test.cjs)、[tests/harmony-presentation.test.cjs](D:/HUAWEI-DEV/Bluff-Tavern-HARMONEYOS/tests/harmony-presentation.test.cjs)：客户端回归与表现逻辑检查。
- [backend/apps/server/tests/game-service.test.ts](D:/HUAWEI-DEV/Bluff-Tavern-HARMONEYOS/backend/apps/server/tests/game-service.test.ts)、[backend/apps/server/tests/ws-transport.test.ts](D:/HUAWEI-DEV/Bluff-Tavern-HARMONEYOS/backend/apps/server/tests/ws-transport.test.ts)：对局标识与跨传输非房主直接重开回归。

## 验证结果与命令

- 客户端 **22/22** 通过。包含 TIMEOUT / DISCONNECTED / SEND_FAILED / RATE_LIMITED / SERVER_ERROR 保留 token 与重试、离线/重连、节流及单在途、永久失效、替换时旧成功 ACK/操作 ACK/旧连接推送/前台 connect/既有重试定时器失效、允许新会话、直接 restart、离线跨局、旧服务端兼容、页面状态清理、HIDDEN_BET null、系统偏好、酒杯过期、分享失败、资源完整性与持久化写入排序。
- 三个核心回归用例针对修复前审查副本运行，**3/3 如预期失败**；同一测试在修复后通过。未放宽断言或删掉既有测试。
- game-service、game-scheduler、shared protocol：**72/72**；双传输 WS 集成：**6/6**。合计 **78/78**。
- shared/server TypeScript typecheck：通过。
- 鸿蒙 assembleHap：**BUILD SUCCESSFUL**，ArkTS 编译通过。仍有原有 deprecated API / 可选系统能力告警；没有配置签名，产物为 unsigned。
- 检查生成 HAP 的 ZIP 内容：**12 个 WAV + 两张新增左轮演出素材已打包**；源码中的 app.media 引用均能定位资源。全部音频具备有效 PCM 头、非静音采样且未削波。
- git diff --check：通过。

在工作区根目录：

```powershell
node --test tests/harmony-session.test.cjs tests/harmony-presentation.test.cjs
node scripts/generate-audio.cjs  # 仅需重新生成音效时执行
```

在 backend 目录：

```powershell
pnpm --filter @bluff-tavern/shared build
pnpm -r typecheck
pnpm exec vitest run apps/server/tests/game-service.test.ts apps/server/tests/game-scheduler.test.ts packages/shared/tests/protocol.test.ts apps/server/tests/ws-transport.test.ts
```

构建使用本机 DevEco 工具链，未调用设备命令：

```powershell
$env:DEVECO_SDK_HOME = 'D:\HUAWEI-DEV\DevEco Studio\sdk'
$env:JAVA_HOME = 'D:\HUAWEI-DEV\DevEco Studio\jbr'
& 'D:\HUAWEI-DEV\DevEco Studio\tools\node\node.exe' 'D:\HUAWEI-DEV\DevEco Studio\tools\hvigor\bin\hvigorw.js' --mode module -p product=default -p module=entry@default assembleHap --no-daemon
```

产物：[entry/build/default/outputs/default/entry-default-unsigned.hap](D:/HUAWEI-DEV/Bluff-Tavern-HARMONEYOS/entry/build/default/outputs/default/entry-default-unsigned.hap)。由 GLM 使用现有 DevEco 签名配置完成设备运行；本次未改签名配置。

日志：[.cache/phase4-fixes/client-tests.txt](D:/HUAWEI-DEV/Bluff-Tavern-HARMONEYOS/.cache/phase4-fixes/client-tests.txt)、[.cache/phase4-fixes/baseline-regression.txt](D:/HUAWEI-DEV/Bluff-Tavern-HARMONEYOS/.cache/phase4-fixes/baseline-regression.txt)、[.cache/phase4-fixes/hap-build.txt](D:/HUAWEI-DEV/Bluff-Tavern-HARMONEYOS/.cache/phase4-fixes/hap-build.txt)。.cache 为本地验证记录，不需要提交。

## GLM 简短运行复测步骤

1. **断线恢复**：两人开局，在 TURN 即将超时时断开鸿蒙端网络，保持超过 ACK 超时时长和阶段宽限，再恢复。确认同 playerId、同手牌身份自动续玩，未要求重新加入；反复断开仍可恢复。永久失效令牌应清回首页并显示原因。不能以“socket 已连接”代替验证恢复了玩家身份。
2. **会话替换**：在受控测试客户端用同一 token 执行 session:resume。旧鸿蒙端应回首页；等待超过 10 秒、反复前后台切换/手动重连，新客户端仍保有身份，旧端不得再次抢回。再在旧端显式创建/加入新房，确认可正常使用且不会收到旧局状态。
3. **直接重开**：使用测试房主客户端直接发送 game:restart（不是“再来一局→返回大厅”按钮），鸿蒙端作为非房主停在旧 GAME_OVER。确认立即进入新 ROUND_START、sequence=1、新 matchId，结算层/旧选牌消失。另测鸿蒙断线期间房主重开，恢复后进入新局而非旧结算。新版服务端发布 matchId；仍运行旧服务端时只能验收正常在线权威房间边界兼容，离线跨局完整验收需要 GLM 按其联调流程加载新服务端代码。
4. **效果与偏好**：启用道具，使用酒杯只使本人手牌短暂晃动，到期停止；开启“动画少”或“性能省”立即停止晃动/非必要过渡，但逐张翻牌、质疑窗口、倒计时和多枪结果仍完整；切系统减少动画，未手动覆盖时应同步生效。
5. **音效与资源**：经历开局、质疑、逐张揭牌、真假判定、转弹巢、扣扳机、空枪/中弹、终局，确认音效可播且“音效关”停止声音/振动；检查徽章、牌背、左轮/枪口、赢家头像和背景显示，重复牌翻转及多次惩罚没有遮挡/残留。音效是上游参数的原生离线合成版本，不声称平台间波形/音色完全一致。
6. **分享与窗口**：结算点“分享结果（复制战报）”，粘贴核对真实统计；全屏可旋转，返回大厅后恢复竖屏/系统栏；横竖屏都能滚动到结算按钮。记录视觉或设备能力问题，不能仅凭本次构建视为运行通过。

## 范围与边界

六种模式、动态出牌范围、隐藏数量、共享左轮、事件历史、八个被动角色能力、私有状态隔离保持原实现；未启用的 CUSTOM、换牌手套、封口蜡印及参考网页同样没有 UI 的表情入口没有擅自新增游戏规则。

没有 commit、push、部署；没有运行模拟器、HDC、现有联调探针，也未连接、手动启停当前联调服务器。集成测试只启动自有 127.0.0.1:随机端口临时服务并自行关闭。

美术源：上游 codex/v7.2-party-expansion 指定提交 9e7f88b15e6ee07585e47575b4f76fe4619c4109 的 revolver_side_v1.png / muzzle_flash_smoke_v1.png；新增资产复制，未覆盖最新源码。音效生成脚本记录同一上游版本与合成参数，重新执行可稳定生成。

