// JSON 解析/验证器 - 将服务端 JSON 反序列化为严格类型实例
// ArkTS 不支持 Zod；JSON.parse 结果视为不透明数据，经此处校验后拷贝进类型化模型

import {
  RoomView, RoomSettings, RoomMembership, PlayerView, SessionResumeResult,
  GameSnapshot, GameCue, GameSummary, ChallengeResult,
  PublicPlayerState, PublicLastPlay, PublicChallengeState, PublicPunishmentState,
  PublicWinnerState, PublicSharedRevolverState, PublicTavernEvent,
  PublicPartyEventHistoryEntry, PublicFreeChallengeWindow, PrivateItemEffect, PrivateAbilityEffect,
  V7ExtensionSettings,
  GamePhase, PlayableGameMode, TargetRank, CardRank, GameCueType, TurnDirection,
  CharacterId, PlayerStatus, RoomStatus, GameMode, TavernEventType, PartyEventCategory,
  ItemEffectType, ItemRiskLevel, AbilityEffectType, CharacterAbilityId, ActiveItemId
} from './GameTypes'

// ====== 基础取值辅助 ======

function asRecord(value: ESObject): Record<string, ESObject> | null {
  if (typeof value === 'object' && value !== null && !Array.isArray(value)) {
    return value as Record<string, ESObject>
  }
  return null
}

function recStr(rec: Record<string, ESObject>, key: string, def: string): string {
  const value: ESObject = rec[key]
  return typeof value === 'string' ? value : def
}

function recNum(rec: Record<string, ESObject>, key: string, def: number): number {
  const value: ESObject = rec[key]
  return typeof value === 'number' ? value : def
}

function recBool(rec: Record<string, ESObject>, key: string, def: boolean): boolean {
  const value: ESObject = rec[key]
  return typeof value === 'boolean' ? value : def
}

function recStrOrNull(rec: Record<string, ESObject>, key: string): string | null {
  const value: ESObject = rec[key]
  return typeof value === 'string' ? value : null
}

function recNumOrNull(rec: Record<string, ESObject>, key: string): number | null {
  const value: ESObject = rec[key]
  return typeof value === 'number' ? value : null
}

function recArr(rec: Record<string, ESObject>, key: string): ESObject[] | null {
  const value: ESObject = rec[key]
  if (Array.isArray(value)) {
    return value as ESObject[]
  }
  return null
}

function recStringArray(rec: Record<string, ESObject>, key: string): string[] {
  const result: string[] = []
  const raw: ESObject[] | null = recArr(rec, key)
  if (raw === null) return result
  for (let i: number = 0; i < raw.length; i++) {
    const item: ESObject = raw[i]
    if (typeof item === 'string') {
      result.push(item)
    }
  }
  return result
}

// ====== 房间相关 ======

function parseV7Settings(raw: ESObject): V7ExtensionSettings {
  const settings: V7ExtensionSettings = new V7ExtensionSettings()
  const rec: Record<string, ESObject> | null = asRecord(raw)
  if (rec === null) return settings
  settings.itemsEnabled = recBool(rec, 'itemsEnabled', false)
  settings.tavernEventsEnabled = recBool(rec, 'tavernEventsEnabled', false)
  settings.characterAbilitiesEnabled = recBool(rec, 'characterAbilitiesEnabled', false)
  return settings
}

export function parseRoomSettings(raw: ESObject): RoomSettings {
  const settings: RoomSettings = new RoomSettings()
  const rec: Record<string, ESObject> | null = asRecord(raw)
  if (rec === null) return settings
  settings.maxPlayers = recNum(rec, 'maxPlayers', 8)
  settings.gameMode = recStr(rec, 'gameMode', 'CLASSIC') as GameMode
  settings.turnDurationSeconds = recNum(rec, 'turnDurationSeconds', 15)
  settings.eventEnabled = recBool(rec, 'eventEnabled', false)
  settings.bulletCount = recNumOrNull(rec, 'bulletCount')
  settings.v7 = parseV7Settings(rec['v7'])
  return settings
}

function parsePlayerView(raw: ESObject): PlayerView | null {
  const rec: Record<string, ESObject> | null = asRecord(raw)
  if (rec === null) return null
  const player: PlayerView = new PlayerView()
  player.id = recStr(rec, 'id', '')
  player.nickname = recStr(rec, 'nickname', '')
  player.status = recStr(rec, 'status', 'CONNECTED') as PlayerStatus
  player.joinedAt = recNum(rec, 'joinedAt', 0)
  player.isConnected = recBool(rec, 'isConnected', true)
  const characterId: string | null = recStrOrNull(rec, 'characterId')
  player.characterId = characterId === null ? null : (characterId as CharacterId)
  return player
}

export function parseRoomView(raw: ESObject): RoomView | null {
  const rec: Record<string, ESObject> | null = asRecord(raw)
  if (rec === null) return null
  const room: RoomView = new RoomView()
  room.id = recStr(rec, 'id', '')
  room.code = recStr(rec, 'code', '')
  room.hostPlayerId = recStr(rec, 'hostPlayerId', '')
  room.status = recStr(rec, 'status', 'LOBBY') as RoomStatus
  room.maxPlayers = recNum(rec, 'maxPlayers', 8)
  room.settings = parseRoomSettings(rec['settings'])
  const playersRaw: ESObject[] | null = recArr(rec, 'players')
  if (playersRaw !== null) {
    for (let i: number = 0; i < playersRaw.length; i++) {
      const playerRaw: ESObject = playersRaw[i]
      const player: PlayerView | null = parsePlayerView(playerRaw)
      if (player !== null) {
        room.players.push(player)
      }
    }
  }
  room.createdAt = recNum(rec, 'createdAt', 0)
  return room
}

export function parseRoomMembership(raw: ESObject): RoomMembership | null {
  const rec: Record<string, ESObject> | null = asRecord(raw)
  if (rec === null) return null
  const membership: RoomMembership = new RoomMembership()
  const room: RoomView | null = parseRoomView(rec['room'])
  if (room === null) return null
  membership.room = room
  membership.playerId = recStr(rec, 'playerId', '')
  membership.sessionToken = recStr(rec, 'sessionToken', '')
  return membership
}

export function parseSessionResumeResult(raw: ESObject): SessionResumeResult | null {
  const rec: Record<string, ESObject> | null = asRecord(raw)
  if (rec === null) return null
  const result: SessionResumeResult = new SessionResumeResult()
  const room: RoomView | null = parseRoomView(rec['room'])
  if (room === null) return null
  result.room = room
  result.playerId = recStr(rec, 'playerId', '')
  result.sessionToken = recStr(rec, 'sessionToken', '')
  result.game = parseGameSnapshot(rec['game'])
  return result
}

// ====== 游戏快照相关 ======

function parsePublicPlayerState(raw: ESObject): PublicPlayerState | null {
  const rec: Record<string, ESObject> | null = asRecord(raw)
  if (rec === null) return null
  const player: PublicPlayerState = new PublicPlayerState()
  player.playerId = recStr(rec, 'playerId', '')
  player.name = recStr(rec, 'name', '')
  player.seatIndex = recNum(rec, 'seatIndex', 0)
  player.connected = recBool(rec, 'connected', true)
  player.alive = recBool(rec, 'alive', true)
  player.handCount = recNumOrNull(rec, 'handCount')
  player.cardCount = recNumOrNull(rec, 'cardCount')
  return player
}

function parsePublicLastPlay(raw: ESObject): PublicLastPlay | null {
  const rec: Record<string, ESObject> | null = asRecord(raw)
  if (rec === null) return null
  const play: PublicLastPlay = new PublicLastPlay()
  play.playerId = recStr(rec, 'playerId', '')
  play.count = recNumOrNull(rec, 'count')
  play.claimedRank = recStr(rec, 'claimedRank', 'A') as TargetRank
  return play
}

function parsePublicChallengeState(raw: ESObject): PublicChallengeState | null {
  const rec: Record<string, ESObject> | null = asRecord(raw)
  if (rec === null) return null
  const challenge: PublicChallengeState = new PublicChallengeState()
  challenge.challengerId = recStr(rec, 'challengerId', '')
  challenge.challengedId = recStr(rec, 'challengedId', '')
  const revealedRaw: ESObject[] | null = recArr(rec, 'revealedCards')
  if (revealedRaw !== null) {
    const revealed: CardRank[] = []
    for (let i: number = 0; i < revealedRaw.length; i++) {
      const cardRaw: ESObject = revealedRaw[i]
      if (typeof cardRaw === 'string') {
        revealed.push(cardRaw as CardRank)
      }
    }
    challenge.revealedCards = revealed
  }
  challenge.wasBluff = recBool(rec, 'wasBluff', false)
  const wasBluffRaw: ESObject = rec['wasBluff']
  if (typeof wasBluffRaw !== 'boolean') {
    challenge.wasBluff = null
  }
  challenge.punishedPlayerId = recStrOrNull(rec, 'punishedPlayerId')
  return challenge
}

function parsePublicPunishmentState(raw: ESObject): PublicPunishmentState | null {
  const rec: Record<string, ESObject> | null = asRecord(raw)
  if (rec === null) return null
  const punishment: PublicPunishmentState = new PublicPunishmentState()
  punishment.punishedPlayerId = recStr(rec, 'punishedPlayerId', '')
  punishment.playerId = recStr(rec, 'playerId', '')
  punishment.chamber = recNum(rec, 'chamber', 0)
  punishment.hit = recBool(rec, 'hit', false)
  punishment.eliminatedPlayerId = recStrOrNull(rec, 'eliminatedPlayerId')
  punishment.shotNumber = recNum(rec, 'shotNumber', 0)
  punishment.totalShots = recNum(rec, 'totalShots', 1)
  return punishment
}

function parsePublicWinnerState(raw: ESObject): PublicWinnerState | null {
  const rec: Record<string, ESObject> | null = asRecord(raw)
  if (rec === null) return null
  const winner: PublicWinnerState = new PublicWinnerState()
  winner.winnerId = recStr(rec, 'winnerId', '')
  return winner
}

function parsePublicSharedRevolverState(raw: ESObject): PublicSharedRevolverState | null {
  const rec: Record<string, ESObject> | null = asRecord(raw)
  if (rec === null) return null
  const revolver: PublicSharedRevolverState = new PublicSharedRevolverState()
  revolver.chamberCount = recNum(rec, 'chamberCount', 6)
  revolver.currentChamber = recNum(rec, 'currentChamber', 0)
  revolver.shotsTaken = recNum(rec, 'shotsTaken', 0)
  return revolver
}

function parsePublicTavernEvent(raw: ESObject): PublicTavernEvent | null {
  const rec: Record<string, ESObject> | null = asRecord(raw)
  if (rec === null) return null
  const event: PublicTavernEvent = new PublicTavernEvent()
  event.type = recStr(rec, 'type', 'HIDDEN_BET') as TavernEventType
  event.title = recStr(rec, 'title', '')
  event.description = recStr(rec, 'description', '')
  const category: string | null = recStrOrNull(rec, 'category')
  event.category = category === null ? null : (category as PartyEventCategory)
  event.roundNumber = recNum(rec, 'roundNumber', 0)
  event.turnDurationSeconds = recNumOrNull(rec, 'turnDurationSeconds')
  event.intensity = recStr(rec, 'intensity', 'LOW')
  return event
}

function parsePartyEventHistoryEntry(raw: ESObject): PublicPartyEventHistoryEntry | null {
  const rec: Record<string, ESObject> | null = asRecord(raw)
  if (rec === null) return null
  const entry: PublicPartyEventHistoryEntry = new PublicPartyEventHistoryEntry()
  entry.roundNumber = recNum(rec, 'roundNumber', 0)
  entry.type = recStr(rec, 'type', 'HIDDEN_BET') as TavernEventType
  entry.title = recStr(rec, 'title', '')
  return entry
}

function parsePublicFreeChallengeWindow(raw: ESObject): PublicFreeChallengeWindow | null {
  const rec: Record<string, ESObject> | null = asRecord(raw)
  if (rec === null) return null
  const window: PublicFreeChallengeWindow = new PublicFreeChallengeWindow()
  window.challengedId = recStr(rec, 'challengedId', '')
  window.openedAt = recNum(rec, 'openedAt', 0)
  window.endsAt = recNum(rec, 'endsAt', 0)
  window.challengerId = recStrOrNull(rec, 'challengerId')
  return window
}

function parsePrivateItemEffect(raw: ESObject): PrivateItemEffect | null {
  const rec: Record<string, ESObject> | null = asRecord(raw)
  if (rec === null) return null
  const effect: PrivateItemEffect = new PrivateItemEffect()
  effect.itemId = recStr(rec, 'itemId', 'SPYGLASS') as ActiveItemId
  effect.type = recStr(rec, 'type', 'SPYGLASS_RISK') as ItemEffectType
  effect.message = recStr(rec, 'message', '')
  effect.expiresAt = recNumOrNull(rec, 'expiresAt')
  const riskLevel: string | null = recStrOrNull(rec, 'riskLevel')
  effect.riskLevel = riskLevel === null ? null : (riskLevel as ItemRiskLevel)
  effect.extraSeconds = recNumOrNull(rec, 'extraSeconds')
  return effect
}

function parsePrivateAbilityEffect(raw: ESObject): PrivateAbilityEffect | null {
  const rec: Record<string, ESObject> | null = asRecord(raw)
  if (rec === null) return null
  const effect: PrivateAbilityEffect = new PrivateAbilityEffect()
  effect.abilityId = recStr(rec, 'abilityId', 'WOLF_TABLE_READ') as CharacterAbilityId
  effect.characterId = recStr(rec, 'characterId', 'WOLF') as CharacterId
  effect.type = recStr(rec, 'type', 'ROUND_READ') as AbilityEffectType
  effect.title = recStr(rec, 'title', '')
  effect.message = recStr(rec, 'message', '')
  effect.expiresAt = recNumOrNull(rec, 'expiresAt')
  const riskLevel: string | null = recStrOrNull(rec, 'riskLevel')
  effect.riskLevel = riskLevel === null ? null : (riskLevel as ItemRiskLevel)
  effect.extraSeconds = recNumOrNull(rec, 'extraSeconds')
  const grantedItem: string | null = recStrOrNull(rec, 'grantedItem')
  effect.grantedItem = grantedItem === null ? null : (grantedItem as ActiveItemId)
  effect.roundNumber = recNumOrNull(rec, 'roundNumber')
  return effect
}

function parseGameSummary(raw: ESObject): GameSummary | null {
  const rec: Record<string, ESObject> | null = asRecord(raw)
  if (rec === null) return null
  const summary: GameSummary = new GameSummary()
  summary.winnerId = recStr(rec, 'winnerId', '')
  summary.playerCount = recNum(rec, 'playerCount', 0)
  summary.durationSeconds = recNum(rec, 'durationSeconds', 0)
  summary.challengeCount = recNum(rec, 'challengeCount', 0)
  summary.successfulChallenges = recNum(rec, 'successfulChallenges', 0)
  summary.failedChallenges = recNum(rec, 'failedChallenges', 0)
  summary.eliminationOrder = recStringArray(rec, 'eliminationOrder')
  return summary
}

function parseChallengeResult(raw: ESObject): ChallengeResult | null {
  const rec: Record<string, ESObject> | null = asRecord(raw)
  if (rec === null) return null
  const result: ChallengeResult = new ChallengeResult()
  result.challengerId = recStr(rec, 'challengerId', '')
  result.failedPlayerId = recStr(rec, 'failedPlayerId', '')
  result.wasBluff = recBool(rec, 'wasBluff', false)
  const revealedRaw: ESObject[] | null = recArr(rec, 'revealedCards')
  if (revealedRaw !== null) {
    for (let i: number = 0; i < revealedRaw.length; i++) {
      const cardRaw: ESObject = revealedRaw[i]
      if (typeof cardRaw === 'string') {
        result.revealedCards.push(cardRaw as CardRank)
      }
    }
  }
  return result
}

export function parseGameSnapshot(raw: ESObject): GameSnapshot | null {
  const rec: Record<string, ESObject> | null = asRecord(raw)
  if (rec === null) return null
  const snapshot: GameSnapshot = new GameSnapshot()
  snapshot.matchId = recStr(rec, 'matchId', '')
  snapshot.sequence = recNum(rec, 'sequence', 0)
  snapshot.serverNow = recNum(rec, 'serverNow', 0)
  snapshot.phase = recStr(rec, 'phase', 'LOBBY') as GamePhase
  snapshot.phaseStartedAt = recNum(rec, 'phaseStartedAt', 0)
  snapshot.phaseEndsAt = recNumOrNull(rec, 'phaseEndsAt')
  snapshot.gameMode = recStr(rec, 'gameMode', 'CLASSIC') as PlayableGameMode
  snapshot.turnDurationSeconds = recNum(rec, 'turnDurationSeconds', 15)
  snapshot.roundNumber = recNum(rec, 'roundNumber', 0)
  const targetRank: string | null = recStrOrNull(rec, 'targetRank')
  snapshot.targetRank = targetRank === null ? null : (targetRank as TargetRank)
  snapshot.targetCard = recStr(rec, 'targetCard', 'A') as TargetRank
  snapshot.turnPlayerId = recStrOrNull(rec, 'turnPlayerId')
  snapshot.mustChallenge = recBool(rec, 'mustChallenge', false)
  snapshot.minimumPlayCount = recNum(rec, 'minimumPlayCount', 1)
  snapshot.maximumPlayCount = recNum(rec, 'maximumPlayCount', 3)
  snapshot.turnDirection = recStr(rec, 'turnDirection', 'CLOCKWISE') as TurnDirection

  const playersRaw: ESObject[] | null = recArr(rec, 'players')
  if (playersRaw !== null) {
    for (let i: number = 0; i < playersRaw.length; i++) {
      const playerRaw: ESObject = playersRaw[i]
      const player: PublicPlayerState | null = parsePublicPlayerState(playerRaw)
      if (player !== null) {
        snapshot.players.push(player)
      }
    }
  }
  const handRaw: ESObject[] | null = recArr(rec, 'hand')
  if (handRaw !== null) {
    for (let i: number = 0; i < handRaw.length; i++) {
      const cardRaw: ESObject = handRaw[i]
      if (typeof cardRaw === 'string') {
        snapshot.hand.push(cardRaw as CardRank)
      }
    }
  }
  snapshot.discardCount = recNumOrNull(rec, 'discardCount')
  snapshot.lastPlay = parsePublicLastPlay(rec['lastPlay'])
  snapshot.challenge = parsePublicChallengeState(rec['challenge'])
  snapshot.punishment = parsePublicPunishmentState(rec['punishment'])
  snapshot.winner = parsePublicWinnerState(rec['winner'])
  snapshot.freeChallenge = parsePublicFreeChallengeWindow(rec['freeChallenge'])
  snapshot.sharedRevolver = parsePublicSharedRevolverState(rec['sharedRevolver'])

  snapshot.alivePlayerIds = recStringArray(rec, 'alivePlayerIds')
  snapshot.winnerId = recStrOrNull(rec, 'winnerId')
  snapshot.summary = parseGameSummary(rec['summary'])

  snapshot.tavernEvent = parsePublicTavernEvent(rec['tavernEvent'])
  const historyRaw: ESObject[] | null = recArr(rec, 'partyEventHistory')
  if (historyRaw !== null) {
    for (let i: number = 0; i < historyRaw.length; i++) {
      const entryRaw: ESObject = historyRaw[i]
      const entry: PublicPartyEventHistoryEntry | null = parsePartyEventHistoryEntry(entryRaw)
      if (entry !== null) {
        snapshot.partyEventHistory.push(entry)
      }
    }
  }
  const itemsRaw: ESObject[] | null = recArr(rec, 'items')
  if (itemsRaw !== null) {
    for (let i: number = 0; i < itemsRaw.length; i++) {
      const itemRaw: ESObject = itemsRaw[i]
      if (typeof itemRaw === 'string') {
        snapshot.items.push(itemRaw as ActiveItemId)
      }
    }
  }
  snapshot.itemEffect = parsePrivateItemEffect(rec['itemEffect'])
  snapshot.abilityEffect = parsePrivateAbilityEffect(rec['abilityEffect'])
  snapshot.challengeResult = parseChallengeResult(rec['challengeResult'])
  return snapshot
}

export function parseGameCue(raw: ESObject): GameCue | null {
  const rec: Record<string, ESObject> | null = asRecord(raw)
  if (rec === null) return null
  const cue: GameCue = new GameCue()
  cue.type = recStr(rec, 'type', 'ROUND_STARTED') as GameCueType
  cue.sequence = recNum(rec, 'sequence', 0)
  cue.roomCode = recStr(rec, 'roomCode', '')
  cue.playerId = recStrOrNull(rec, 'playerId')
  cue.targetPlayerId = recStrOrNull(rec, 'targetPlayerId')
  cue.count = recNumOrNull(rec, 'count')
  cue.roundNumber = recNumOrNull(rec, 'roundNumber')
  return cue
}
