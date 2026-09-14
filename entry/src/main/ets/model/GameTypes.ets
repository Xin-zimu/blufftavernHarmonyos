// 游戏类型定义 - 对应 shared/types/index.ts

// 连接状态
export type ConnectionStatus = 'connected' | 'disconnected' | 'connecting'

// 房间状态
export type RoomStatus = 'LOBBY' | 'STARTING' | 'PLAYING' | 'ROUND_RESULT' | 'GAME_OVER' | 'CLOSED'

// 玩家状态
export type PlayerStatus = 'CONNECTED' | 'DISCONNECTED' | 'READY' | 'PLAYING' | 'ELIMINATED' | 'SPECTATING'

// 游戏模式
export type GameMode = 'CLASSIC' | 'QUICK' | 'PARTY' | 'CUSTOM'
export type V6GameMode = 'CLASSIC' | 'QUICK'

// 角色ID
export type CharacterId = 'WOLF' | 'FOX' | 'BEAR' | 'RABBIT' | 'CAT' | 'RACCOON' | 'FROG' | 'PANDA'

// 道具ID
export type ItemId = 'SPYGLASS' | 'SWAP_GLOVE' | 'WAX_SEAL' | 'TAVERN_MUG' | 'POCKET_WATCH'

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
  | 'CHALLENGE_CALLOUT'
  | 'REVEAL'
  | 'VERDICT'
  | 'PUNISHMENT_INTRO'
  | 'PUNISHMENT_TRIGGER'
  | 'PUNISHMENT_RESULT'
  | 'ROUND_END'
  | 'GAME_OVER'

// 房间设置
export class RoomSettings {
  maxPlayers: number = 8
  gameMode: GameMode = 'CLASSIC'
  turnDurationSeconds: number = 15
  eventEnabled: boolean = false
  bulletCount: number | null = null
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

// 左轮手枪状态
export class RevolverState {
  chamberCount: number = 6
  bulletPosition: number = 0
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
  handCount: number = 0
  cardCount: number = 0
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

  gameMode: V6GameMode = 'CLASSIC'
  turnDurationSeconds: number = 15
  roundNumber: number = 0
  targetRank: TargetRank | null = null
  targetCard: TargetRank = 'A'

  turnPlayerId: string | null = null
  mustChallenge: boolean = false

  players: PublicPlayerState[] = []
  hand: CardRank[] = []
  discardCount: number = 0
  lastPlay: PublicLastPlay | null = null
  challenge: PublicChallengeState | null = null
  punishment: PublicPunishmentState | null = null
  winner: PublicWinnerState | null = null

  alivePlayerIds: string[] = []
  winnerId: string | null = null
  summary: GameSummary | null = null

  tavernEvent: null = null
  items: ItemId[] = []
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

// Ack 响应
export class AckSuccess<T> {
  ok: boolean = true
  data: T = null as T
}

export class AckFailure {
  ok: boolean = false
  error: AckError = new AckError()
}

export class AckError {
  code: string = ''
  message: string = ''
}

export type Ack<T> = AckSuccess<T> | AckFailure
