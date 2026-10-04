// 大厅页面 - 对应 LobbyScreen.tsx（v7.2 Party Expansion）
// 房间码牌匾、7 模式选择卡+详情弹窗、V7 扩展开关、人数选择、
// 玩家列表（房主踢人）、角色选择（占用互斥+技能预览）、准备/开始

import { SessionStore, globalSessionStore } from '../store/SessionStore'
import { SessionPersistence } from '../store/SessionPersistence'
import { SocketManager } from '../net/SocketManager'
import { router, SymbolGlyphModifier } from '@kit.ArkUI'
import { pasteboard } from '@kit.BasicServicesKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { PlayerView, PlayableGameMode, V7ExtensionSettings } from '../model/GameTypes'
import {
  CHARACTER_IDS, CHARACTER_NAMES, CHARACTER_ABILITY_NAMES, CHARACTER_ABILITY_DESCRIPTIONS,
  MAX_PLAYERS, MIN_PLAYERS
} from '../model/Constants'
import { getCharacterIdleImage } from '../utils/ArtResources'

// ====== 模式选项数据（对齐 LobbyScreen.tsx MODE_OPTIONS） ======

type LobbyModeId = PlayableGameMode | 'CUSTOM'

class ModeOption {
  id: LobbyModeId = 'CLASSIC'
  title: string = ''
  badge: string = ''
  description: string = ''
  coreRules: string = ''
  classicDifference: string = ''
  enabled: boolean = true
}

function makeModeOption(id: LobbyModeId, title: string, badge: string, description: string,
  coreRules: string, classicDifference: string, enabled: boolean): ModeOption {
  const option: ModeOption = new ModeOption()
  option.id = id
  option.title = title
  option.badge = badge
  option.description = description
  option.coreRules = coreRules
  option.classicDifference = classicDifference
  option.enabled = enabled
  return option
}

const MODE_OPTIONS: ModeOption[] = [
  makeModeOption('CLASSIC', '经典模式', '15 秒',
    '标准诈唬、质疑、左轮惩罚。',
    '每轮公布目标牌，玩家轮流声明出牌；下一名玩家可以继续出牌或质疑上一手。',
    '这是基准规则，没有额外模式限制。', true),
  makeModeOption('QUICK', '快速模式', '7 秒',
    '更短回合倒计时，保持原规则。',
    '每名玩家只有 7 秒行动时间，超时由服务器自动执行合法操作。',
    '只压缩行动时间，不改变真假牌、质疑或惩罚规则。', true),
  makeModeOption('ESCALATION', '加注模式', '新开放',
    '每手出牌数不得低于上一手。',
    '首手可出 1 至 3 张；之后每手至少跟上上一手的出牌数量。',
    'Classic 每手都可自由选择 1 至 3 张；加注模式会逐步抬高最低出牌数。', true),
  makeModeOption('SHARED_REVOLVER', '死亡左轮', '新开放',
    '全桌共用一把左轮。',
    '所有受罚者共享同一把左轮，空枪后下一次惩罚继续使用后续膛位；命中后重新装填。',
    'Classic 中每名玩家有自己的左轮状态；死亡左轮把风险集中到全桌共享。', true),
  makeModeOption('FREE_CHALLENGE', '全民质疑', '新开放',
    '多人抢先质疑窗口。',
    '出牌后开启 3 秒质疑窗口，除出牌者外的存活玩家都可以抢先质疑。',
    'Classic 只有下一名玩家能质疑；全民质疑允许其他玩家在窗口内竞争质疑权。', true),
  makeModeOption('PARTY', '酒馆乱斗', '新开放',
    '每轮一个随机酒馆事件。',
    '每轮开始抽取一个公开事件，每轮只启用一个事件。事件池：暗注夜、醉酒之夜、快速夜、双倍危机、禁忌小丑、强制豪赌、单张夜、跟注夜、豪饮之夜、最后点单。',
    'Classic 没有每轮随机事件；酒馆乱斗每轮只附加一个独立事件。', true),
  makeModeOption('CUSTOM', '自定义', '计划中',
    '自由组合规则参数。',
    '计划提供可配置规则参数，由房主创建自定义玩法。',
    '当前版本还不能开局，只保留为后续入口。', false),
]

// 人数下拉选项（2-8 人）
function buildMaxPlayerOptions(): SelectOption[] {
  const options: SelectOption[] = []
  for (let n: number = MIN_PLAYERS; n <= MAX_PLAYERS; n++) {
    options.push({ value: `${n} 人` })
  }
  return options
}

const MAX_PLAYER_OPTIONS: SelectOption[] = buildMaxPlayerOptions()

// 辅助函数：替代 ?? 操作符
function getErrorOrDefault(error: string | undefined, defaultMsg: string): string {
  if (error !== undefined && error !== null) {
    return error
  }
  return defaultMsg
}

@Entry
@ComponentV2
struct LobbyPage {
  // SessionStore 为 @ObservedV2 类，用 @Local 持有以获得 V2 观察能力
  @Local store: SessionStore = globalSessionStore
  // 服务对象无需响应式，aboutToAppear 时从 AppStorage 取回全局实例
  socketManager: SocketManager = new SocketManager(new SessionStore(), new SessionPersistence())
  @Local errorMessage: string = ''
  @Local copiedNotice: string = ''
  // 模式详情弹窗：当前查看的模式 id（空串表示关闭）
  @Local modeDetailId: string = ''
  private isTop: boolean = true
  private navGuard: boolean = false
  private exitGuard: boolean = false
  // 最大人数下拉箭头：金色下箭头（深棕底上清晰可见）
  private selectArrowModifier: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.chevron_down'))
    .fontColor(['#D4A85D'])
    .fontSize(16)

  aboutToAppear(): void {
    const sm: SocketManager | undefined = AppStorage.get<SocketManager>('socketManager')
    if (sm !== undefined) {
      this.socketManager = sm
    }
    this.navigateByRoomState()
  }

  onPageShow(): void {
    this.isTop = true
  }

  onPageHide(): void {
    this.isTop = false
  }

  // 房间状态驱动的导航：开局进游戏页；被踢/房间关闭/离开房间时回首页
  @Monitor('store.room')
  onRoomChange(monitor: IMonitor): void {
    this.navigateByRoomState()
  }

  private navigateByRoomState(): void {
    const room = this.store.room
    if (room === null) {
      if (!this.isTop || this.exitGuard) {
        return
      }
      this.exitGuard = true
      hilog.info(0xFF00, 'LobbyPage', 'go home')
      router.clear()
      router.replaceUrl({ url: 'pages/HomePage' })
        .catch((error: BusinessError) => {
          hilog.error(0xFF00, 'LobbyPage', `go home rejected: ${error.message}`)
        })
      return
    }
    if (room.status === 'LOBBY') {
      this.navGuard = false
      return
    }
    if (!this.isTop || this.navGuard) {
      return
    }
    this.navGuard = true
    hilog.info(0xFF00, 'LobbyPage', `push game page, status=${room.status}`)
    router.pushUrl({ url: 'pages/GamePage' })
      .catch((error: BusinessError) => {
        this.navGuard = false
        hilog.error(0xFF00, 'LobbyPage', `push game page rejected: ${error.message}`)
      })
  }

  // ====== 状态辅助方法 ======

  private getRoomCode(): string {
    if (this.store.room !== null) {
      return this.store.room.code
    }
    return ''
  }

  private getPlayerCount(): number {
    if (this.store.room !== null) {
      return this.store.room.players.length
    }
    return 0
  }

  private getMaxPlayers(): number {
    if (this.store.room !== null) {
      return this.store.room.maxPlayers
    }
    return 8
  }

  // 当前选中模式（以服务端 RoomView 为唯一事实来源）
  private getSelectedMode(): LobbyModeId {
    if (this.store.room !== null) {
      return this.store.room.settings.gameMode
    }
    return 'CLASSIC'
  }

  private getRoomPlayers(): PlayerView[] {
    if (this.store.room !== null) {
      return this.store.room.players
    }
    return []
  }

  // 自己的玩家视图
  private getSelfPlayer(): PlayerView | null {
    const playerId: string | null = this.store.playerId
    if (playerId === null) return null
    for (const player of this.getRoomPlayers()) {
      if (player.id === playerId) {
        return player
      }
    }
    return null
  }

  // 自己已选角色 id（空串表示未选）
  private getSelfCharacterId(): string {
    const self: PlayerView | null = this.getSelfPlayer()
    if (self !== null && self.characterId !== null) {
      return self.characterId
    }
    return ''
  }

  private isCharacterTaken(charId: string): boolean {
    const playerId: string | null = this.store.playerId
    for (const player of this.getRoomPlayers()) {
      if (player.characterId === charId && player.id !== playerId) {
        return true
      }
    }
    return false
  }

  private isCharacterMine(charId: string): boolean {
    const playerId: string | null = this.store.playerId
    for (const player of this.getRoomPlayers()) {
      if (player.characterId === charId && player.id === playerId) {
        return true
      }
    }
    return false
  }

  private getMyReady(): boolean {
    const self: PlayerView | null = this.getSelfPlayer()
    return self !== null && self.status === 'READY'
  }

  private getAllReady(): boolean {
    for (const player of this.getRoomPlayers()) {
      if (player.status !== 'READY') return false
    }
    return true
  }

  private isHostPlayer(playerId: string): boolean {
    if (this.store.room !== null) {
      return playerId === this.store.room.hostPlayerId
    }
    return false
  }

  // V7 扩展开关读取
  private getV7ItemsEnabled(): boolean {
    if (this.store.room !== null) {
      return this.store.room.settings.v7.itemsEnabled
    }
    return false
  }

  private getV7EventsEnabled(): boolean {
    if (this.store.room !== null) {
      return this.store.room.settings.v7.tavernEventsEnabled
    }
    return false
  }

  private getV7AbilitiesEnabled(): boolean {
    if (this.store.room !== null) {
      return this.store.room.settings.v7.characterAbilitiesEnabled
    }
    return false
  }

  // 只有 CLASSIC / QUICK 允许"启用酒馆事件"开关
  private supportsLegacyTavernEvents(mode: LobbyModeId): boolean {
    return mode === 'CLASSIC' || mode === 'QUICK'
  }

  // 酒馆事件开关锁定状态：PARTY 固定开；其它非经典/快速模式锁定关
  private isEventsLockedOn(mode: LobbyModeId): boolean {
    return mode === 'PARTY'
  }

  private isEventsLockedOff(mode: LobbyModeId): boolean {
    return mode !== 'PARTY' && !this.supportsLegacyTavernEvents(mode)
  }

  private getCharacterName(charId: string): string {
    const name = CHARACTER_NAMES.get(charId)
    if (name !== undefined) {
      return name
    }
    return charId
  }

  // ====== 设置变更命令 ======

  // 房主切换模式：QUICK=7 秒，其它=15 秒；非经典/快速模式强制关闭酒馆事件
  private updateMode(mode: LobbyModeId): void {
    const room = this.store.room
    if (room === null || mode === 'CUSTOM') return
    const v7: V7ExtensionSettings = new V7ExtensionSettings()
    v7.itemsEnabled = room.settings.v7.itemsEnabled
    v7.tavernEventsEnabled = this.supportsLegacyTavernEvents(mode) ? room.settings.v7.tavernEventsEnabled : false
    v7.characterAbilitiesEnabled = room.settings.v7.characterAbilitiesEnabled
    const duration: number = mode === 'QUICK' ? 7 : 15
    this.socketManager.updateSettings(room.settings.maxPlayers, mode, duration, v7, (success: boolean) => {
      if (!success) {
        this.errorMessage = '模式切换失败'
      }
    })
  }

  // 房主切换 V7 扩展开关
  private updateExtension(key: string, enabled: boolean): void {
    const room = this.store.room
    if (room === null) return
    let mode: PlayableGameMode = 'CLASSIC'
    if (room.settings.gameMode !== 'CUSTOM') {
      mode = room.settings.gameMode
    }
    const v7: V7ExtensionSettings = new V7ExtensionSettings()
    v7.itemsEnabled = key === 'itemsEnabled' ? enabled : room.settings.v7.itemsEnabled
    v7.tavernEventsEnabled = key === 'tavernEventsEnabled' ? enabled : room.settings.v7.tavernEventsEnabled
    v7.characterAbilitiesEnabled = key === 'characterAbilitiesEnabled' ? enabled : room.settings.v7.characterAbilitiesEnabled
    const duration: number = mode === 'QUICK' ? 7 : 15
    this.socketManager.updateSettings(room.settings.maxPlayers, mode, duration, v7, (success: boolean) => {
      if (!success) {
        this.errorMessage = '设置更新失败'
      }
    })
  }

  // 房主修改最大人数（不允许低于当前玩家数）
  private updateMaxPlayers(count: number): void {
    const room = this.store.room
    if (room === null) return
    if (count < MIN_PLAYERS || count > MAX_PLAYERS) return
    if (count < room.players.length) {
      this.errorMessage = '人数不能低于当前玩家数'
      return
    }
    let mode: PlayableGameMode = 'CLASSIC'
    if (room.settings.gameMode !== 'CUSTOM') {
      mode = room.settings.gameMode
    }
    const v7: V7ExtensionSettings = new V7ExtensionSettings()
    v7.itemsEnabled = room.settings.v7.itemsEnabled
    v7.tavernEventsEnabled = room.settings.v7.tavernEventsEnabled
    v7.characterAbilitiesEnabled = room.settings.v7.characterAbilitiesEnabled
    const duration: number = mode === 'QUICK' ? 7 : 15
    this.socketManager.updateSettings(count, mode, duration, v7, (success: boolean) => {
      if (!success) {
        this.errorMessage = '人数修改失败'
      }
    })
  }

  // 玩家状态行："你 · 在线 · 已准备"
  private formatLobbyPlayerStatus(player: PlayerView): string {
    const parts: string[] = []
    if (player.id === this.store.playerId) {
      parts.push('你')
    }
    parts.push(player.isConnected ? '在线' : '离线')
    parts.push(player.status === 'READY' ? '已准备' : '未准备')
    return parts.join(' · ')
  }

  // 模式详情弹窗当前展示的选项
  private getModeDetail(): ModeOption | null {
    for (const option of MODE_OPTIONS) {
      if (option.id === this.modeDetailId) {
        return option
      }
    }
    return null
  }

  // 开关读取值（应用锁定规则后的实际状态）
  private getSwitchValue(key: string): boolean {
    const mode: LobbyModeId = this.getSelectedMode()
    if (key === 'itemsEnabled') {
      return this.getV7ItemsEnabled()
    }
    if (key === 'characterAbilitiesEnabled') {
      return this.getV7AbilitiesEnabled()
    }
    // tavernEventsEnabled：PARTY 视为开；其它非经典/快速模式视为关
    if (this.isEventsLockedOn(mode)) {
      return true
    }
    if (this.isEventsLockedOff(mode)) {
      return false
    }
    return this.getV7EventsEnabled()
  }

  private getSwitchStatusText(key: string): string {
    const mode: LobbyModeId = this.getSelectedMode()
    if (key === 'tavernEventsEnabled') {
      if (this.isEventsLockedOn(mode)) {
        return 'Party 固定启用'
      }
      if (this.isEventsLockedOff(mode)) {
        return '特殊模式不叠加'
      }
    }
    return this.getSwitchValue(key) ? '已开启' : '关闭'
  }

  // 角色卡文案：能力启用时 "名字 · 技能名"，否则仅名字
  private getCharacterCardLabel(charId: string): string {
    const name: string = this.getCharacterName(charId)
    if (this.getV7AbilitiesEnabled()) {
      const ability: string | undefined = CHARACTER_ABILITY_NAMES.get(charId)
      if (ability !== undefined) {
        return `${name} · ${ability}`
      }
    }
    return name
  }

  private getAbilityName(charId: string): string {
    const name: string | undefined = CHARACTER_ABILITY_NAMES.get(charId)
    return name !== undefined ? name : ''
  }

  private getAbilityDescription(charId: string): string {
    const desc: string | undefined = CHARACTER_ABILITY_DESCRIPTIONS.get(charId)
    return desc !== undefined ? desc : ''
  }

  private getNicknameInitial(nickname: string): string {
    if (nickname.length === 0) return '?'
    return nickname.substring(0, 1).toUpperCase()
  }

  // 详情弹窗按钮文案/可用性
  private canSelectModeFromDetail(): boolean {
    const detail: ModeOption | null = this.getModeDetail()
    if (detail === null) return false
    return this.store.isHost && detail.enabled && detail.id !== this.getSelectedMode()
  }

  private getModeDetailSelectText(): string {
    const detail: ModeOption | null = this.getModeDetail()
    if (detail === null) return ''
    if (detail.id === this.getSelectedMode()) return '当前模式'
    return detail.enabled ? '选择此模式' : '计划中'
  }

  private getModeDetailTitle(): string {
    const detail: ModeOption | null = this.getModeDetail()
    return detail !== null ? detail.title : ''
  }

  private getModeDetailDescription(): string {
    const detail: ModeOption | null = this.getModeDetail()
    return detail !== null ? detail.description : ''
  }

  private getModeDetailCoreRules(): string {
    const detail: ModeOption | null = this.getModeDetail()
    return detail !== null ? detail.coreRules : ''
  }

  private getModeDetailClassicDifference(): string {
    const detail: ModeOption | null = this.getModeDetail()
    return detail !== null ? detail.classicDifference : ''
  }

  private copyRoomCode(): void {
    const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.getRoomCode())
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      this.copiedNotice = '房间码已复制'
      setTimeout(() => {
        this.copiedNotice = ''
      }, 2000)
    })
  }

  build() {
    Stack() {
      Scroll() {
        Column() {
          this.LobbyHeader()
          this.NoticeArea()
          this.RoomSign()
          this.PlayerPanel()
          this.LobbyActions()
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ left: 16, right: 16, top: 12, bottom: 32 })
      }
      .scrollBar(BarState.Off)
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .backgroundColor('#17110F')
      .backgroundImage($r('app.media.background_bg_lobby'))
      .backgroundImageSize(ImageSize.Cover)

      // 模式详情模态
      if (this.modeDetailId.length > 0) {
        this.ModeDetailDialog()
      }
    }
    .width('100%')
    .height('100%')
  }

  // 顶部：标题 + 离开房间
  @Builder LobbyHeader() {
    Row() {
      Column() {
        Text('等待牌友入席')
          .fontSize(11)
          .fontColor('#D4A85D')
          .letterSpacing(3)
        Text('酒馆大厅')
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor('#E8DDC8')
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)

      Blank()

      Button('离开房间')
        .height(38)
        .backgroundColor('#2B1914')
        .fontColor('#E8DDC8')
        .fontSize(13)
        .border({ width: 1, color: '#A67C3D' })
        .borderRadius(4)
        .onClick(() => {
          this.socketManager.leaveRoom()
        })
    }
    .width('100%')
  }

  // 通知 / 错误 / 复制提示
  @Builder NoticeArea() {
    Column() {
      if (this.store.notice !== null && this.store.notice !== undefined) {
        Text(this.store.notice)
          .fontSize(13)
          .fontColor('#E8DDC8')
          .backgroundColor('#7A2632')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .borderRadius(4)
          .margin({ top: 12 })
          .onClick(() => {
            this.store.setNotice(null)
          })
      }

      if (this.errorMessage.length > 0) {
        Text(this.errorMessage)
          .fontSize(13)
          .fontColor('#D8AAA1')
          .margin({ top: 10 })
      }

      if (this.copiedNotice.length > 0) {
        Text(this.copiedNotice)
          .fontSize(13)
          .fontColor('#9ED18C')
          .margin({ top: 10 })
      }
    }
    .width('100%')
  }

  // 房间码牌匾
  @Builder RoomSign() {
    Column() {
      Text('房间码')
        .fontSize(12)
        .fontColor('#C8B9A1')
      Text(this.getRoomCode())
        .fontSize(40)
        .fontWeight(FontWeight.Bold)
        .fontColor('#F2C777')
        .letterSpacing(8)
        .margin({ top: 4 })
      Button('复制')
        .height(32)
        .backgroundColor('#2B1914')
        .fontColor('#F2C777')
        .fontSize(13)
        .border({ width: 1, color: '#A67C3D' })
        .borderRadius(4)
        .margin({ top: 8 })
        .onClick(() => {
          this.copyRoomCode()
        })
    }
    .width('100%')
    .padding({ top: 18, bottom: 18 })
    .margin({ top: 14 })
    .borderRadius(8)
    .border({ width: 1, color: 'rgba(166,124,61,0.5)' })
    .backgroundColor('#231713')
  }

  // 主面板：人数 + 模式卡 + 扩展开关 + 玩家列表 + 角色选择
  @Builder PlayerPanel() {
    Column() {
      // 面板标题
      Row() {
        Text('已入席玩家')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFE1A1')
        Blank()
        Text(`${this.getPlayerCount()} / ${this.getMaxPlayers()}`)
          .fontSize(13)
          .fontColor('#D4A85D')
      }
      .width('100%')
      .padding({ bottom: 10 })

      Divider()
        .color('#4D3830')
        .width('100%')

      // 人数选择（仅房主）
      if (this.store.isHost) {
        Row() {
          Text('最大人数')
            .fontSize(13)
            .fontColor('#C8B9A1')
          Blank()
          Select(MAX_PLAYER_OPTIONS)
            .selected(this.getMaxPlayers() - MIN_PLAYERS)
            .value(`${this.getMaxPlayers()} 人`)
            .font({ size: 13 })
            .fontColor('#E8DDC8')
            .selectedOptionFontColor('#F2C777')
            .optionFontColor('#E8DDC8')
            .backgroundColor('#231713')
            .borderRadius(4)
            .border({ width: 1, color: '#A67C3D' })
            .height(38)
            .width(110)
            .menuBackgroundColor('#231713')
            .optionBgColor('#231713')
            .selectedOptionBgColor('#8B303D')
            .divider({ strokeWidth: 1, color: '#3A2921', startMargin: 8, endMargin: 8 })
            .arrowModifier(this.selectArrowModifier)
            .onSelect((index: number) => {
              this.updateMaxPlayers(index + MIN_PLAYERS)
            })
        }
        .width('100%')
        .margin({ top: 10, bottom: 4 })
      }

      // 模式选择卡（点击打开详情弹窗）
      Text('游戏模式')
        .fontSize(13)
        .fontColor('#C8B9A1')
        .margin({ top: 12, bottom: 8 })
        .width('100%')
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        ForEach(MODE_OPTIONS, (option: ModeOption) => {
          this.ModeCard(option)
        }, (option: ModeOption) => option.id)
      }
      .width('100%')

      // V7 扩展开关
      Text('V7 扩展玩法')
        .fontSize(13)
        .fontColor('#C8B9A1')
        .margin({ top: 16, bottom: 8 })
        .width('100%')
      this.FeatureSwitch('itemsEnabled', '启用道具')
      this.FeatureSwitch('tavernEventsEnabled',
        this.isEventsLockedOn(this.getSelectedMode()) ? '每轮随机事件' : '启用酒馆事件')
      this.FeatureSwitch('characterAbilitiesEnabled', '启用角色能力')

      // 玩家列表
      Column() {
        ForEach(this.getRoomPlayers(), (player: PlayerView) => {
          this.PlayerListItem(player)
        }, (player: PlayerView) => `${player.id}_${player.status}_${player.characterId === null ? 'none' : player.characterId}_${player.isConnected}`)
      }
      .width('100%')
      .margin({ top: 16 })

      // 角色选择（仅显示给自己的选择器）
      if (this.getSelfPlayer() !== null) {
        this.CharacterPicker()
      }
    }
    .width('100%')
    .padding(16)
    .margin({ top: 14 })
    .borderRadius(8)
    .border({ width: 1, color: 'rgba(166,124,61,0.5)' })
    .backgroundColor('#231713')
  }

  // 模式卡
  @Builder ModeCard(option: ModeOption) {
    Column() {
      Row() {
        Text(option.title)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getSelectedMode() === option.id ? '#FFE1A1' : '#E8DDC8')
        Blank()
        Text(option.badge)
          .fontSize(9)
          .fontColor('#D4A85D')
          .border({ width: 1, color: 'rgba(166,124,61,0.52)' })
          .padding({ left: 5, right: 5, top: 2, bottom: 2 })
      }
      .width('100%')

      Text(option.description)
        .fontSize(11)
        .fontColor('#A99B8D')
        .margin({ top: 6 })
    }
    .width('48.6%')
    .padding(12)
    .margin({ bottom: 8 })
    .borderRadius(7)
    .alignItems(HorizontalAlign.Start)
    .border({
      width: 1,
      color: this.getSelectedMode() === option.id ? '#F2C777' : 'rgba(110,98,91,0.72)',
      style: option.enabled ? BorderStyle.Solid : BorderStyle.Dashed
    })
    .backgroundColor(this.getSelectedMode() === option.id ? '#3E1B22' : '#171110')
    .opacity(option.enabled ? 1.0 : 0.72)
    .onClick(() => {
      this.modeDetailId = option.id
    })
  }

  // V7 扩展开关行
  @Builder FeatureSwitch(key: string, label: string) {
    Row() {
      // 房主且未锁定时显示开关，否则显示状态指示灯（仅酒馆事件开关会随模式锁定）
      if (this.store.isHost && (key !== 'tavernEventsEnabled'
        || (!this.isEventsLockedOn(this.getSelectedMode()) && !this.isEventsLockedOff(this.getSelectedMode())))) {
        Toggle({ type: ToggleType.Switch, isOn: this.getSwitchValue(key) })
          .width(42)
          .height(24)
          .selectedColor('#F2C777')
          .onChange((isOn: boolean) => {
            this.updateExtension(key, isOn)
          })
      } else {
        Circle()
          .width(8)
          .height(8)
          .fill(this.getSwitchValue(key) ? '#F2C777' : '#6E625B')
      }

      Text(label)
        .fontSize(13)
        .fontColor('#E8DDC8')
        .margin({ left: 8 })

      Blank()

      Text(this.getSwitchStatusText(key))
        .fontSize(11)
        .fontColor('#81746B')
    }
    .width('100%')
    .height(40)
    .padding({ left: 8, right: 8 })
    .margin({ bottom: 4 })
    .borderRadius(4)
    .backgroundColor('rgba(0,0,0,0.14)')
  }

  // 玩家列表项
  @Builder PlayerListItem(player: PlayerView) {
    Row() {
      // 角色头像 / 昵称首字母
      if (player.characterId !== null) {
        Image(getCharacterIdleImage(player.characterId))
          .width(44)
          .height(44)
          .borderRadius(4)
          .margin({ right: 11 })
      } else {
        Stack() {
          Circle()
            .width(44)
            .height(44)
            .fill('#5B1F28')
            Text(this.getNicknameInitial(player.nickname))
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#F2C777')
        }
        .margin({ right: 11 })
      }

      Column() {
        Text(player.nickname)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#E8DDC8')
        Text(this.formatLobbyPlayerStatus(player))
          .fontSize(11)
          .fontColor('#81746B')
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (player.status === 'READY') {
        Text('准备')
          .fontSize(10)
          .fontColor('#9ED18C')
          .border({ width: 1, color: '#527845' })
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .margin({ right: 6 })
      }

      if (this.isHostPlayer(player.id)) {
        Text('创建者')
          .fontSize(10)
          .fontColor('#D4A85D')
          .border({ width: 1, color: '#7B5C31' })
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .margin({ right: 6 })
      }

      // 房主踢人（不能踢自己，无二次确认）
      if (this.store.isHost && player.id !== this.store.playerId) {
        Button('移出')
          .height(30)
          .backgroundColor(Color.Transparent)
          .fontColor('#D8AAA1')
          .fontSize(12)
          .border({ width: 1, color: '#7A2632' })
          .borderRadius(3)
          .onClick(() => {
            this.socketManager.kickPlayer(player.id)
          })
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .padding(9)
    .borderRadius(4)
    .backgroundColor('rgba(0,0,0,0.16)')
    .border({
      width: 1,
      color: player.id === this.store.playerId ? '#A67C3D' : '#49342B'
    })
    .margin({ bottom: 8 })
  }

  // 角色选择器（4 列网格）
  @Builder CharacterPicker() {
    Column() {
      Text('选择原创角色')
        .fontSize(13)
        .fontColor('#C8B9A1')
        .margin({ top: 12, bottom: 8 })
        .width('100%')

      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        ForEach(CHARACTER_IDS, (charId: string) => {
          this.CharacterCard(charId)
        }, (charId: string) => charId)
      }
      .width('100%')

      // 技能预览
      if (this.getSelfCharacterId().length > 0) {
        this.AbilityPreview(this.getSelfCharacterId())
      }
    }
    .width('100%')
  }

  @Builder CharacterCard(charId: string) {
    Column() {
      Image(getCharacterIdleImage(charId))
        .width('100%')
        .height(72)
        .objectFit(ImageFit.Contain)
        .opacity(this.isCharacterTaken(charId) ? 0.38 : 1.0)
        .grayscale(this.isCharacterTaken(charId) ? 0.8 : 0)

      Text(this.getCharacterCardLabel(charId))
        .fontSize(10)
        .fontColor(this.isCharacterMine(charId) ? '#F2C777' : (this.isCharacterTaken(charId) ? '#6E625B' : '#E8DDC8'))
        .margin({ top: 4 })
        .maxLines(1)
    }
    .width('23.5%')
    .height(104)
    .padding({ left: 4, right: 4, bottom: 6 })
    .margin({ bottom: 9 })
    .borderRadius(7)
    .border({
      width: 1,
      color: this.isCharacterMine(charId) ? '#F2C777' : '#6E625B'
    })
    .backgroundColor(this.isCharacterMine(charId) ? '#3E1B22' : '#1E1412')
    .onClick(() => {
      if (!this.isCharacterTaken(charId)) {
        this.socketManager.selectCharacter(charId, (success: boolean) => {
          if (!success) {
            this.errorMessage = '选择角色失败'
          }
        })
      }
    })
  }

  // 已选角色技能预览
  @Builder AbilityPreview(charId: string) {
    Column() {
      if (this.getV7AbilitiesEnabled()) {
        Text(`${this.getCharacterName(charId)} · ${this.getAbilityName(charId)}`)
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor('#F2C777')
        Text(this.getAbilityDescription(charId))
          .fontSize(11)
          .fontColor('#A99B8D')
          .margin({ top: 3 })
      } else {
        Text('角色能力未启用')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor('#C8B9A1')
        Text('本局角色仅作为玩家形象使用。')
          .fontSize(11)
          .fontColor('#A99B8D')
          .margin({ top: 3 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(10)
    .margin({ top: 4 })
    .borderRadius(6)
    .border({ width: 1, color: 'rgba(166,124,61,0.34)' })
    .backgroundColor('rgba(0,0,0,0.14)')
  }

  // 底部操作：准备 / 开始
  @Builder LobbyActions() {
    Column() {
      Row() {
        Button(this.getMyReady() ? '取消准备' : '准备就绪')
          .layoutWeight(1)
          .height(50)
          .backgroundColor(this.getMyReady() ? '#2B1914' : '#8B303D')
          .fontColor('#E8DDC8')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .borderRadius(4)
          .border({ width: 1, color: '#A67C3D' })
          .onClick(() => {
            this.socketManager.setReady(!this.getMyReady())
          })

        if (this.store.isHost) {
          Button('开始牌局')
            .layoutWeight(1)
            .height(50)
            .backgroundColor('#8B303D')
            .fontColor('#FFF0C9')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .borderRadius(4)
            .border({ width: 1, color: '#A67C3D' })
            .margin({ left: 10 })
            .enabled(this.getPlayerCount() >= MIN_PLAYERS && this.getAllReady())
            .onClick(() => {
              this.socketManager.startGame((success: boolean, error?: string) => {
                if (!success) {
                  this.errorMessage = getErrorOrDefault(error, '开始游戏失败')
                }
              })
            })
        }
      }
      .width('100%')

      Text('所有玩家准备后，由房主开始这局牌。')
        .fontSize(11)
        .fontColor('#756960')
        .margin({ top: 10 })
    }
    .width('100%')
    .margin({ top: 14 })
  }

  // 模式详情模态（Stack：遮罩 + 面板）
  @Builder ModeDetailDialog() {
    Stack() {
      // 背景遮罩：点击关闭
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(8,5,4,0.72)')
        .onClick(() => {
          this.modeDetailId = ''
        })

      Column() {
        Row() {
          Column() {
            Text('模式详情')
              .fontSize(11)
              .fontColor('#D4A85D')
              .letterSpacing(3)
            Text(this.getModeDetailTitle())
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFE1A1')
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)

          Blank()

          Button('×')
            .width(34)
            .height(34)
            .fontSize(18)
            .backgroundColor('rgba(0,0,0,0.18)')
            .fontColor('#F2C777')
            .border({ width: 1, color: '#7B5C31' })
            .borderRadius(4)
            .onClick(() => {
              this.modeDetailId = ''
            })
        }
        .width('100%')
        .padding({ bottom: 12 })

        Divider()
          .color('#4D3830')
          .width('100%')

        Scroll() {
          Column() {
            Text(this.getModeDetailDescription())
              .fontSize(13)
              .fontColor('#E8DDC8')
              .margin({ top: 12 })

            // 核心规则
            Column() {
              Text('核心规则')
                .fontSize(11)
                .fontColor('#D4A85D')
              Text(this.getModeDetailCoreRules())
                .fontSize(12)
                .fontColor('#E8DDC8')
                .margin({ top: 4 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(10)
            .margin({ top: 14 })
            .borderRadius(6)
            .backgroundColor('rgba(0,0,0,0.14)')

            // 与 Classic 的区别
            Column() {
              Text('与 Classic 的区别')
                .fontSize(11)
                .fontColor('#D4A85D')
              Text(this.getModeDetailClassicDifference())
                .fontSize(12)
                .fontColor('#E8DDC8')
                .margin({ top: 4 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(10)
            .margin({ top: 10 })
            .borderRadius(6)
            .backgroundColor('rgba(0,0,0,0.14)')

            // 动作区
            Column() {
              if (this.store.isHost) {
                Button(this.getModeDetailSelectText())
                  .width('100%')
                  .height(46)
                  .backgroundColor('#8B303D')
                  .fontColor('#E8DDC8')
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .borderRadius(4)
                  .border({ width: 1, color: '#A67C3D' })
                  .enabled(this.canSelectModeFromDetail())
                  .onClick(() => {
                    const detail: ModeOption | null = this.getModeDetail()
                    if (detail !== null && this.canSelectModeFromDetail()) {
                      this.updateMode(detail.id)
                      this.modeDetailId = ''
                    }
                  })
              } else {
                Text(this.getModeDetail()?.enabled === true ? '只有房主可以选择模式。' : '该模式计划中，当前不可选择。')
                  .fontSize(12)
                  .fontColor('#81746B')
              }
            }
            .width('100%')
            .margin({ top: 16 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
        }
        .scrollBar(BarState.Off)
        .layoutWeight(1)
      }
      .width('92%')
      .constraintSize({ maxHeight: '70%' })
      .padding(16)
      .borderRadius(8)
      .border({ width: 1, color: 'rgba(242,199,119,0.5)' })
      .backgroundColor('#1B1210')
    }
    .width('100%')
    .height('100%')
  }
}
