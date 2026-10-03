// 游戏类型定义 - 对应 shared/types/index.ts
// ArkTS 严格类型版本

// 连接状态
export type ConnectionStatus = 'connected' | 'disconnected' | 'connecting'

// 房间状态
export type RoomStatus = 'LOBBY' | 'STARTING' | 'PLAYING' | 'ROUND_RESULT' | 'GAME_OVER' | 'CLOSED'

// 玩家状态
export type PlayerStatus = 'CONNECTED' | 'DISCONNECTED' | 'READY' | 'PLAYING' | 'ELIMINATED' | 'SPECTATING'

// 游戏模式
export type GameMode = 'CLASSIC' | 'QUICK' | 'PARTY' | 'FREE_CHALLENGE' | 'SHARED_REVOLVER' | 'ESCALATION' | 'CUSTOM'
export type PlayableGameMode = 'CLASSIC' | 'QUICK' | 'PARTY' | 'FREE_CHALLENGE' | 'SHARED_REVOLVER' | 'ESCALATION'
export type V6GameMode = 'CLASSIC' | 'QUICK'

// 酒馆事件类型
export type TavernEventType = 'BLACKOUT' | 'DRUNKEN' | 'RAPID_NIGHT' | 'CANDLE_FLICKER' | 'DOUBLE_DANGER' | 'NO_JOKER' | 'FORCED_BET'

// 角色ID
export type CharacterId = 'WOLF' | 'FOX' | 'BEAR' | 'RABBIT' | 'CAT' | 'RACCOON' | 'FROG' | 'PANDA'

// 道具ID
export type ItemId = 'SPYGLASS' | 'SWAP_GLOVE' | 'WAX_SEAL' | 'TAVERN_MUG' | 'POCKET_WATCH'
export type ActiveItemId = 'SPYGLASS' | 'TAVERN_MUG' | 'POCKET_WATCH'
export type ItemEffectType = 'SPYGLASS_RISK' | 'POCKET_WATCH_EXTENDED' | 'TAVERN_MUG_TIPSY'
export type ItemRiskLevel = 'LOW' | 'HIGH'

// 角色技能ID
export type CharacterAbilityId =
  | 'WOLF_TABLE_READ'
  | 'FOX_HAND_HINT'
  | 'BEAR_OPENING_NERVE'
  | 'RABBIT_QUICK_STEP'
  | 'CAT_NIGHT_EYE'
  | 'RACCOON_POCKET_FIND'
  | 'FROG_STEADY_BREATH'
  | 'PANDA_REVEAL_MEMORY'

export type AbilityEffectType =
  | 'ROUND_READ'
  | 'HAND_HINT'
  | 'TURN_TIME_EXTENDED'
  | 'RISK_HINT'
  | 'ITEM_GRANTED'
  | 'ITEM_SKIPPED'
  | 'FORCED_CHALLENGE_TIME'
  | 'REVEAL_MEMORY'

// 表情ID
export type EmoteId = 'CHEER' | 'SUSPECT' | 'BLUFF' | 'LAUGH' | 'GASP' | 'NERVOUS' | 'TOAST' | 'GOOD_GAME'

// 牌面等级
export type CardRank = 'A' | 'K' | 'Q' | 'JOKER'
export type TargetRank = 'A' | 'K' | 'Q'

// 游戏阶段
export type GamePhase =
  | 'LOBBY'
  | 'MATCH_START'
  | 'ROUND_START'
  | 'TURN'
  | 'CHALLENGE_WINDOW'
  | 'CHALLENGE_CALLOUT'
  | 'REVEAL'
  | 'VERDICT'
  | 'PUNISHMENT_INTRO'
  | 'PUNISHMENT_TRIGGER'
  | 'PUNISHMENT_RESULT'
  | 'ROUND_END'
  | 'GAME_OVER'

// 回合方向
export type TurnDirection = 'CLOCKWISE' | 'COUNTERCLOCKWISE'

// 角色表情类型
export type CharacterMood = 'idle' | 'suspicious' | 'bluff' | 'shocked' | 'laugh' | 'nervous' | 'eliminated' | 'victory'

// ====== 基础数据类 ======

// V7 扩展设置
export class V7ExtensionSettings {
  itemsEnabled: boolean = false
  tavernEventsEnabled: boolean = false
  characterAbilitiesEnabled: boolean = false
}

// 房间设置
export class RoomSettings {
  maxPlayers: number = 8
  gameMode: GameMode = 'CLASSIC'
  turnDurationSeconds: number = 15
  eventEnabled: boolean = false
  bulletCount: number | null = null
  v7: V7ExtensionSettings = new V7ExtensionSettings()
}

// 玩家视图
export class PlayerView {
  id: string = ''
  nickname: string = ''
  status: PlayerStatus = 'CONNECTED'
  joinedAt: number = 0
  isConnected: boolean = true
  characterId: CharacterId | null = null
}

// 房间视图
export class RoomView {
  id: string = ''
  code: string = ''
  hostPlayerId: string = ''
  status: RoomStatus = 'LOBBY'
  maxPlayers: number = 8
  settings: RoomSettings = new RoomSettings()
  players: PlayerView[] = []
  createdAt: number = 0
}

// 房间成员信息
export class RoomMembership {
  room: RoomView = new RoomView()
  playerId: string = ''
  sessionToken: string = ''
}

// 左轮手枪状态
export class RevolverState {
  chamberCount: number = 6
  bulletPosition: number = 0
  currentChamber: number = 0
  shotsTaken: number = 0
}

// 公共左轮手枪状态（共享左轮模式）
export class PublicSharedRevolverState {
  chamberCount: number = 6
  currentChamber: number = 0
  shotsTaken: number = 0
}

// 公开玩家状态
export class PublicPlayerState {
  playerId: string = ''
  name: string = ''
  seatIndex: number = 0
  connected: boolean = true
  alive: boolean = true
  handCount: number | null = null
  cardCount: number | null = null
}

// 公开上一次出牌
export class PublicLastPlay {
  playerId: string = ''
  count: number = 0
  claimedRank: TargetRank = 'A'
}

// 公开质疑状态
export class PublicChallengeState {
  challengerId: string = ''
  challengedId: string = ''
  revealedCards: CardRank[] | null = null
  wasBluff: boolean | null = null
  punishedPlayerId: string | null = null
}

// 公开惩罚状态
export class PublicPunishmentState {
  punishedPlayerId: string = ''
  playerId: string = ''
  chamber: number = 0
  hit: boolean = false
  eliminatedPlayerId: string | null = null
  shotNumber: number = 0
  totalShots: number = 1
}

// 公开胜者状态
export class PublicWinnerState {
  winnerId: string = ''
}

// 游戏总结
export class GameSummary {
  winnerId: string = ''
  playerCount: number = 0
  durationSeconds: number = 0
  challengeCount: number = 0
  successfulChallenges: number = 0
  failedChallenges: number = 0
  eliminationOrder: string[] = []
}

// 公开酒馆事件
export class PublicTavernEvent {
  type: TavernEventType = 'BLACKOUT'
  title: string = ''
  description: string = ''
  roundNumber: number = 0
  turnDurationSeconds: number | null = null
  intensity: string = 'LOW'
}

// 公开自由质疑窗口
export class PublicFreeChallengeWindow {
  challengedId: string = ''
  openedAt: number = 0
  endsAt: number = 0
  challengerId: string | null = null
}

// 私有道具效果
export class PrivateItemEffect {
  itemId: ActiveItemId = 'SPYGLASS'
  type: ItemEffectType = 'SPYGLASS_RISK'
  message: string = ''
  expiresAt: number | null = null
  riskLevel: ItemRiskLevel | null = null
  extraSeconds: number | null = null
}

// 私有角色技能效果
export class PrivateAbilityEffect {
  abilityId: CharacterAbilityId = 'WOLF_TABLE_READ'
  characterId: CharacterId = 'WOLF'
  type: AbilityEffectType = 'ROUND_READ'
  title: string = ''
  message: string = ''
  expiresAt: number | null = null
  riskLevel: ItemRiskLevel | null = null
  extraSeconds: number | null = null
  grantedItem: ActiveItemId | null = null
  roundNumber: number | null = null
}

// 质疑结果
export class ChallengeResult {
  challengerId: string = ''
  failedPlayerId: string = ''
  wasBluff: boolean = false
  revealedCards: CardRank[] = []
}

// 游戏快照 - 服务端推送给客户端的完整状态
export class GameSnapshot {
  sequence: number = 0
  serverNow: number = 0
  phase: GamePhase = 'LOBBY'
  phaseStartedAt: number = 0
  phaseEndsAt: number | null = null

  gameMode: PlayableGameMode = 'CLASSIC'
  turnDurationSeconds: number = 15
  roundNumber: number = 0
  targetRank: TargetRank | null = null
  targetCard: TargetRank = 'A'

  turnPlayerId: string | null = null
  mustChallenge: boolean = false
  minimumPlayCount: number = 1
  turnDirection: TurnDirection = 'CLOCKWISE'

  players: PublicPlayerState[] = []
  hand: CardRank[] = []
  discardCount: number = 0
  lastPlay: PublicLastPlay | null = null
  challenge: PublicChallengeState | null = null
  punishment: PublicPunishmentState | null = null
  winner: PublicWinnerState | null = null
  freeChallenge: PublicFreeChallengeWindow | null = null
  sharedRevolver: PublicSharedRevolverState | null = null

  alivePlayerIds: string[] = []
  winnerId: string | null = null
  summary: GameSummary | null = null

  tavernEvent: PublicTavernEvent | null = null
  items: ActiveItemId[] = []
  itemEffect: PrivateItemEffect | null = null
  abilityEffect: PrivateAbilityEffect | null = null
  challengeResult: ChallengeResult | null = null
}

// 游戏视图 = 游戏快照
export type GameView = GameSnapshot

// 游戏事件提示类型
export type GameCueType =
  | 'ROUND_STARTED'
  | 'CARD_PLAYED'
  | 'CHALLENGE_CALLED'
  | 'PLAYER_ELIMINATED'
  | 'MATCH_FINISHED'

// 游戏事件提示
export class GameCue {
  type: GameCueType = 'ROUND_STARTED'
  sequence: number = 0
  roomCode: string = ''
  playerId: string | null = null
  targetPlayerId: string | null = null
  count: number | null = null
  roundNumber: number | null = null
}

// 会话恢复结果
export class SessionResumeResult {
  room: RoomView = new RoomView()
  playerId: string = ''
  sessionToken: string = ''
  game: GameSnapshot | null = null
}

// 房间玩家事件
export class RoomPlayerEvent {
  roomCode: string = ''
  player: PlayerView = new PlayerView()
}

// ====== Ack 响应（非泛型，ArkTS 兼容） ======

export class AckError {
  code: string = ''
  message: string = ''
}

// 统一的 Ack 响应结构，data 为 ESObject 以兼容任意类型
export class AckResult {
  ok: boolean = false
  data: ESObject = null
  error: AckError = new AckError()
}
