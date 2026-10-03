# HarmonyOS 客户端构建说明

## 前置条件

- DevEco Studio（含 HarmonyOS SDK，API 26 基线）或 `devecocli` 命令行工具。
- Node.js / pnpm（仅在需要跑 `backend/` 联调时）。

## 构建

在仓库根目录（`build-profile.json5` 所在处）执行：

```powershell
devecocli build
```

或使用 DevEco Studio 打开工程后 Build → Build Hap(s)/APP(s)。

- 构建产物：`entry/build/default/outputs/default/*.hap`
- 构建输出目录（`build/`、`.hvigor/`、`oh_modules/`、`.cache/` 等）均已列入
  `.gitignore`，不会进入版本库。

## 安装到模拟器/真机

```powershell
devecocli run          # 构建并安装启动（需已连接设备/模拟器）
# 或手动安装：
hdc -t 127.0.0.1:5555 install entry/build/default/outputs/default/entry-default-signed.hap
```

模拟器启动（本机验证使用的环境）：

```powershell
devecocli emulator start "Mate 90 Pro"
```

## 代码静态检查

DevEco Studio 内置 ArkTS 严格模式检查（保存/构建时自动执行）。本轮所有改动
均以「ArkTS 0 错误 + `devecocli build` 通过」为基线。

## 模块结构（客户端）

```
entry/src/main/ets/
├── entryability/EntryAbility.ets   # 应用入口；服务器地址在此配置（见下）
├── pages/                          # HomePage / LobbyPage / GamePage（router 导航）
├── components/                     # CardHand、PlayerSeat 等自定义组件
├── net/                            # SocketManager（业务封装）、WsTransport（原生 ws 信封）
├── store/                          # SessionPersistence（会话恢复）
└── model/                          # GameTypes、Protocol、Parsers（严格类型与解析）
```

## 服务器地址配置

客户端当前在 `EntryAbility.ets`（约第 85 行）硬编码：

```ts
http://192.168.2.66:3001
```

联调时请替换为运行服务器的宿主机局域网 IP（模拟器内 `127.0.0.1` 指向模拟器
自身，不是宿主机）。修改后需重新构建安装。
