export type ConnectionStatus = 'connected' | 'disconnected' | 'connecting';
export type RoomStatus = 'LOBBY' | 'STARTING' | 'PLAYING' | 'ROUND_RESULT' | 'GAME_OVER' | 'CLOSED';
export type PlayerStatus = 'CONNECTED' | 'DISCONNECTED' | 'READY' | 'PLAYING' | 'ELIMINATED' | 'SPECTATING';
export type GameMode = 'CLASSIC' | 'QUICK' | 'PARTY' | 'FREE_CHALLENGE' | 'SHARED_REVOLVER' | 'ESCALATION' | 'CUSTOM';
export type V6GameMode = Extract<GameMode, 'CLASSIC' | 'QUICK'>;
export type PlayableGameMode = Exclude<GameMode, 'CUSTOM'>;
export type TavernEventType = 'BLACKOUT' | 'DRUNKEN' | 'RAPID_NIGHT' | 'CANDLE_FLICKER' | 'DOUBLE_DANGER' | 'NO_JOKER' | 'FORCED_BET';
export type CharacterId = 'WOLF' | 'FOX' | 'BEAR' | 'RABBIT' | 'CAT' | 'RACCOON' | 'FROG' | 'PANDA';
export type ItemId = 'SPYGLASS' | 'SWAP_GLOVE' | 'WAX_SEAL' | 'TAVERN_MUG' | 'POCKET_WATCH';
export type ActiveItemId = Extract<ItemId, 'SPYGLASS' | 'TAVERN_MUG' | 'POCKET_WATCH'>;
export type ItemEffectType = 'SPYGLASS_RISK' | 'POCKET_WATCH_EXTENDED' | 'TAVERN_MUG_TIPSY';
export type ItemRiskLevel = 'LOW' | 'HIGH';
export type CharacterAbilityId =
  | 'WOLF_TABLE_READ'
  | 'FOX_HAND_HINT'
  | 'BEAR_OPENING_NERVE'
  | 'RABBIT_QUICK_STEP'
  | 'CAT_NIGHT_EYE'
  | 'RACCOON_POCKET_FIND'
  | 'FROG_STEADY_BREATH'
  | 'PANDA_REVEAL_MEMORY';
export type AbilityEffectType =
  | 'ROUND_READ'
  | 'HAND_HINT'
  | 'TURN_TIME_EXTENDED'
  | 'RISK_HINT'
  | 'ITEM_GRANTED'
  | 'ITEM_SKIPPED'
  | 'FORCED_CHALLENGE_TIME'
  | 'REVEAL_MEMORY';
export type EmoteId = 'CHEER' | 'SUSPECT' | 'BLUFF' | 'LAUGH' | 'GASP' | 'NERVOUS' | 'TOAST' | 'GOOD_GAME';

export interface V7ExtensionSettings {
  itemsEnabled: boolean;
  tavernEventsEnabled: boolean;
  characterAbilitiesEnabled: boolean;
}

export interface RoomSettings {
  maxPlayers: number;
  gameMode: GameMode;
  turnDurationSeconds: number;
  eventEnabled: boolean;
  bulletCount: number | null;
  v7: V7ExtensionSettings;
}

export interface PlayerView {
  id: string;
  nickname: string;
  status: PlayerStatus;
  joinedAt: number;
  isConnected: boolean;
  characterId: CharacterId | null;
}

export interface RoomView {
  id: string;
  code: string;
  hostPlayerId: string;
  status: RoomStatus;
  maxPlayers: number;
  settings: RoomSettings;
  players: PlayerView[];
  createdAt: number;
}

export interface RoomMembership {
  room: RoomView;
  playerId: string;
  sessionToken: string;
}

export interface SessionResumeResult extends RoomMembership {
  game: GameView | null;
}

export interface RoomPlayerEvent {
  roomCode: string;
  player: PlayerView;
}

export type CardRank = 'A' | 'K' | 'Q' | 'JOKER';
export type TargetRank = Exclude<CardRank, 'JOKER'>;

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
  | 'GAME_OVER';

export interface RevolverState {
  chamberCount: 6;
  bulletPosition: number;
  currentChamber: number;
  shotsTaken: number;
}

export interface PublicSharedRevolverState {
  chamberCount: 6;
  currentChamber: number;
  shotsTaken: number;
}

export interface PublicPlayerState {
  playerId: string;
  name: string;
  seatIndex: number;
  connected: boolean;
  alive: boolean;
  handCount: number | null;
  cardCount: number | null;
}

export interface PublicLastPlay {
  playerId: string;
  count: number;
  claimedRank: TargetRank;
}

export interface PublicChallengeState {
  challengerId: string;
  challengedId: string;
  revealedCards: CardRank[] | null;
  wasBluff: boolean | null;
  punishedPlayerId: string | null;
}

export interface PublicPunishmentState {
  punishedPlayerId: string;
  playerId: string;
  chamber: number;
  hit: boolean;
  eliminatedPlayerId: string | null;
  shotNumber: number;
  totalShots: number;
}

export interface PublicWinnerState {
  winnerId: string;
}

export interface GameSummary {
  winnerId: string;
  playerCount: number;
  durationSeconds: number;
  challengeCount: number;
  successfulChallenges: number;
  failedChallenges: number;
  eliminationOrder: string[];
}

export interface PublicTavernEvent {
  type: TavernEventType;
  title: string;
  description: string;
  roundNumber: number;
  turnDurationSeconds: number | null;
  intensity: 'LOW' | 'MEDIUM' | 'HIGH';
}

export interface PublicFreeChallengeWindow {
  challengedId: string;
  openedAt: number;
  endsAt: number;
  challengerId: string | null;
}

export interface PrivateItemEffect {
  itemId: ActiveItemId;
  type: ItemEffectType;
  message: string;
  expiresAt: number | null;
  riskLevel?: ItemRiskLevel;
  extraSeconds?: number;
}

export interface PrivateAbilityEffect {
  abilityId: CharacterAbilityId;
  characterId: CharacterId;
  type: AbilityEffectType;
  title: string;
  message: string;
  expiresAt: number | null;
  riskLevel?: ItemRiskLevel;
  extraSeconds?: number;
  grantedItem?: ActiveItemId;
  roundNumber?: number;
}

export interface GameSnapshot {
  sequence: number;
  serverNow: number;
  phase: GamePhase;
  phaseStartedAt: number;
  phaseEndsAt: number | null;

  gameMode: PlayableGameMode;
  turnDurationSeconds: number;
  roundNumber: number;
  targetRank: TargetRank | null;
  targetCard: TargetRank;

  turnPlayerId: string | null;
  mustChallenge: boolean;
  minimumPlayCount: number;
  turnDirection: 'CLOCKWISE' | 'COUNTERCLOCKWISE';

  players: PublicPlayerState[];
  hand: CardRank[];
  discardCount: number;
  lastPlay: PublicLastPlay | null;
  challenge: PublicChallengeState | null;
  punishment: PublicPunishmentState | null;
  winner: PublicWinnerState | null;
  freeChallenge: PublicFreeChallengeWindow | null;
  sharedRevolver: PublicSharedRevolverState | null;

  alivePlayerIds: string[];
  winnerId: string | null;
  summary: GameSummary | null;

  tavernEvent: PublicTavernEvent | null;
  items: ActiveItemId[];
  itemEffect: PrivateItemEffect | null;
  abilityEffect: PrivateAbilityEffect | null;
  challengeResult: {
    challengerId: string;
    failedPlayerId: string;
    wasBluff: boolean;
    revealedCards: CardRank[];
  } | null;
}

export type GameView = GameSnapshot;

export type GameCueType =
  | 'ROUND_STARTED'
  | 'CARD_PLAYED'
  | 'CHALLENGE_CALLED'
  | 'PLAYER_ELIMINATED'
  | 'MATCH_FINISHED';

export interface GameCue {
  type: GameCueType;
  sequence: number;
  roomCode: string;
  playerId?: string;
  targetPlayerId?: string;
  count?: number;
  roundNumber?: number;
}

export interface AckSuccess<T> { ok: true; data: T }
export interface AckFailure { ok: false; error: { code: string; message: string } }
export type Ack<T> = AckSuccess<T> | AckFailure;
