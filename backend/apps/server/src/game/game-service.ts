import {
  MAX_CARDS_PER_PLAY,
  V7_ITEM_IDS,
  V7_PARTY_EVENT_TYPES,
  V7_TAVERN_EVENT_TYPES,
  type ActiveItemId,
  type CardRank,
  type CharacterAbilityId,
  type CharacterId,
  type GameCue,
  type GameMode,
  type GamePhase,
  type GameSnapshot,
  type PlayableGameMode,
  type PrivateAbilityEffect,
  type PrivateItemEffect,
  type PublicChallengeState,
  type PublicPartyEventHistoryEntry,
  type PublicPunishmentState,
  type PublicSharedRevolverState,
  type PublicTavernEvent,
  type RevolverState,
  type RoomView,
  type TavernEventType,
  type TargetRank,
  type V7ExtensionSettings,
} from '@bluff-tavern/shared';
import { RoomError } from '../rooms/room-store.js';
import type { RandomService } from './random.js';
import {
  getChallengePolicy,
  getEffectivePlayRange,
  getEffectiveTurnSeconds,
  getPunishmentShotLimit,
  getRevolverPolicy,
  isJokerWild,
  type EffectivePlayRange,
} from './mode-rules.js';

interface InternalPlay {
  playerId: string;
  cards: CardRank[];
  count: number;
}

interface PendingChallenge {
  challengerId: string;
  challengedId: string;
  revealedCards: CardRank[];
  wasBluff: boolean;
  punishedPlayerId: string;
  shots: Array<{ chamber: number; hit: boolean }>;
  maxShots: number;
  publishedShotCount: number;
  resultPublished: boolean;
}

interface InternalGame {
  matchId: string;
  roomCode: string;
  phase: GamePhase;
  phaseSequence: number;
  phaseStartedAt: number;
  phaseEndsAt: number | null;
  roundNumber: number;
  playerOrder: string[];
  playerNames: Map<string, string>;
  playerCharacters: Map<string, CharacterId | null>;
  connectedPlayerIds: Set<string>;
  alivePlayerIds: Set<string>;
  hands: Map<string, CardRank[]>;
  targetRank: TargetRank;
  turnPlayerId: string | null;
  nextRoundStarterId: string | null;
  lastPlay: InternalPlay | null;
  mustChallenge: boolean;
  pendingChallenge: PendingChallenge | null;
  punishment: PublicPunishmentState | null;
  revolvers: Map<string, RevolverState>;
  sharedRevolver: RevolverState | null;
  winnerId: string | null;
  gameMode: PlayableGameMode;
  turnDurationSeconds: number;
  roundTurnDurationSeconds: number;
  v7: V7ExtensionSettings;
  itemInventories: Map<string, ActiveItemId[]>;
  itemEffects: Map<string, PrivateItemEffect>;
  abilityEffects: Map<string, PrivateAbilityEffect>;
  abilityUsedKeys: Set<string>;
  tavernEvent: PublicTavernEvent | null;
  recentPartyEventTypes: TavernEventType[];
  partyEventHistory: PublicPartyEventHistoryEntry[];
  partyRequiredPlayCount: number | null;
  successfulPlayCountThisRound: number;
  turnDirection: 'CLOCKWISE' | 'COUNTERCLOCKWISE';
  freeChallengeWindow: { challengedId: string; openedAt: number; endsAt: number; challengerId: string | null } | null;
  discardCount: number;
  startedAt: number;
  challengeCount: number;
  successfulChallenges: number;
  failedChallenges: number;
  eliminationOrder: string[];
}

export interface PlayCardsResult {
  state: GameSnapshot;
  cue: GameCue;
}

export interface ChallengeResult {
  state: GameSnapshot;
  cue: GameCue;
}

export interface PhaseAdvanceResult {
  state: GameSnapshot;
  cues: GameCue[];
  eliminatedPlayerId: string | null;
  gameOver: boolean;
}

const targets = ['A', 'K', 'Q'] as const;
const activeItemPool = V7_ITEM_IDS;
const tavernEventPool = V7_TAVERN_EVENT_TYPES;
const partyEventPool = V7_PARTY_EVENT_TYPES;
const TAVERN_EVENT_CHANCE_PERCENT = 25;
const FREE_CHALLENGE_WINDOW_MS = 3_000;
const POCKET_WATCH_EXTENSION_SECONDS = 7;
const ITEM_EFFECT_DURATION_MS = 18_000;
const ABILITY_EFFECT_DURATION_MS = 20_000;
const BEAR_OPENING_EXTENSION_SECONDS = 2;
const RABBIT_EXTENSION_SECONDS = 3;
const FROG_CHALLENGE_EXTENSION_SECONDS = 4;

const partyEventWeights: Record<(typeof partyEventPool)[number], number> = {
  HIDDEN_BET: 12,
  DRUNKEN: 10,
  RAPID_NIGHT: 8,
  DOUBLE_DANGER: 5,
  NO_JOKER: 8,
  FORCED_BET: 9,
  ONE_CARD_ONLY: 11,
  MATCH_BET: 9,
  HEAVY_HAND: 7,
  LAST_CALL: 7,
};

const partyEventMeta: Record<TavernEventType, Omit<PublicTavernEvent, 'roundNumber' | 'turnDurationSeconds'>> = {
  HIDDEN_BET: {
    type: 'HIDDEN_BET',
    title: '暗注夜',
    description: '本轮其他玩家的剩余手牌数量与每次出牌数量都会隐藏，只有质疑翻牌时才公开被质疑那一手的真实数量。',
    category: 'INFORMATION',
    intensity: 'HIGH',
  },
  DRUNKEN: {
    type: 'DRUNKEN',
    title: '醉酒之夜',
    description: '本轮行动方向反转。',
    category: 'TURN_ORDER',
    intensity: 'MEDIUM',
  },
  RAPID_NIGHT: {
    type: 'RAPID_NIGHT',
    title: '快速夜',
    description: '本轮行动时间缩短。',
    category: 'TEMPO',
    intensity: 'HIGH',
  },
  CANDLE_FLICKER: {
    type: 'CANDLE_FLICKER',
    title: '烛火摇曳',
    description: '本轮质疑演出更紧张，规则判定不变。',
    category: null,
    intensity: 'MEDIUM',
  },
  DOUBLE_DANGER: {
    type: 'DOUBLE_DANGER',
    title: '双倍危机',
    description: '本轮受罚者最多连续开两枪；第一枪命中时第二枪取消。',
    category: 'PUNISHMENT',
    intensity: 'HIGH',
  },
  NO_JOKER: {
    type: 'NO_JOKER',
    title: '禁忌小丑',
    description: '本轮 Joker 不再是万能牌。',
    category: 'CARD_RULE',
    intensity: 'HIGH',
  },
  FORCED_BET: {
    type: 'FORCED_BET',
    title: '强制豪赌',
    description: '第一手正常，从第二手开始每次至少出 2 张。',
    category: 'CARD_RULE',
    intensity: 'HIGH',
  },
  ONE_CARD_ONLY: {
    type: 'ONE_CARD_ONLY',
    title: '单张夜',
    description: '本轮每次只能出 1 张牌。',
    category: 'CARD_RULE',
    intensity: 'LOW',
  },
  MATCH_BET: {
    type: 'MATCH_BET',
    title: '跟注夜',
    description: '第一手决定张数，之后所有人必须出相同数量。',
    category: 'CARD_RULE',
    intensity: 'MEDIUM',
  },
  HEAVY_HAND: {
    type: 'HEAVY_HAND',
    title: '豪饮之夜',
    description: '本轮每次至少出 2 张牌。',
    category: 'CARD_RULE',
    intensity: 'MEDIUM',
  },
  LAST_CALL: {
    type: 'LAST_CALL',
    title: '最后点单',
    description: '每完成一次出牌，下一位玩家的行动时间都会缩短。',
    category: 'TEMPO',
    intensity: 'HIGH',
  },
};

const characterAbilities: Record<CharacterId, CharacterAbilityId> = {
  WOLF: 'WOLF_TABLE_READ',
  FOX: 'FOX_HAND_HINT',
  BEAR: 'BEAR_OPENING_NERVE',
  RABBIT: 'RABBIT_QUICK_STEP',
  CAT: 'CAT_NIGHT_EYE',
  RACCOON: 'RACCOON_POCKET_FIND',
  FROG: 'FROG_STEADY_BREATH',
  PANDA: 'PANDA_REVEAL_MEMORY',
};

const cinematicTiming = {
  ROUND_START: 2_700,
  CHALLENGE_CALLOUT: 1_800,
  VERDICT: 1_300,
  PUNISHMENT_INTRO: 1_050,
  PUNISHMENT_TRIGGER: 700,
  ROUND_END: 900,
  REVEAL_INTRO: 500,
  REVEAL_PER_CARD: 750,
  REVEAL_FINAL_HOLD: 1_000,
} as const;

export class GameService {
  private readonly games = new Map<string, InternalGame>();

  constructor(private readonly random: RandomService) {}

  start(room: RoomView): GameSnapshot {
    const gameMode = this.requirePlayableMode(room.settings.gameMode);
    const playerOrder = room.players.map((player) => player.id);
    const turnDurationSeconds = gameMode === 'QUICK' ? 7 : 15;
    const v7 = { ...room.settings.v7 };
    const game: InternalGame = {
      matchId: `${room.code}-${Date.now()}-${this.random.nextInt(1_000_000)}`,
      roomCode: room.code,
      phase: 'MATCH_START',
      phaseSequence: 0,
      phaseStartedAt: Date.now(),
      phaseEndsAt: null,
      roundNumber: 0,
      playerOrder,
      playerNames: new Map(room.players.map((player) => [player.id, player.nickname])),
      playerCharacters: new Map(room.players.map((player) => [player.id, player.characterId])),
      connectedPlayerIds: new Set(room.players.filter((player) => player.isConnected).map((player) => player.id)),
      alivePlayerIds: new Set(playerOrder),
      hands: new Map(playerOrder.map((playerId) => [playerId, []])),
      targetRank: 'A',
      turnPlayerId: null,
      nextRoundStarterId: playerOrder[0] ?? null,
      lastPlay: null,
      mustChallenge: false,
      pendingChallenge: null,
      punishment: null,
      revolvers: new Map(playerOrder.map((playerId) => [playerId, this.createRevolver()])),
      sharedRevolver: gameMode === 'SHARED_REVOLVER' ? this.createRevolver() : null,
      winnerId: null,
      gameMode,
      turnDurationSeconds,
      roundTurnDurationSeconds: turnDurationSeconds,
      v7,
      itemInventories: new Map(playerOrder.map((playerId) => [playerId, v7.itemsEnabled ? [this.dealItem()] : []])),
      itemEffects: new Map(),
      abilityEffects: new Map(),
      abilityUsedKeys: new Set(),
      tavernEvent: null,
      recentPartyEventTypes: [],
      partyEventHistory: [],
      partyRequiredPlayCount: null,
      successfulPlayCountThisRound: 0,
      turnDirection: 'CLOCKWISE',
      freeChallengeWindow: null,
      discardCount: 0,
      startedAt: Date.now(),
      challengeCount: 0,
      successfulChallenges: 0,
      failedChallenges: 0,
      eliminationOrder: [],
    };
    this.games.set(room.code, game);
    this.startRound(game, game.nextRoundStarterId);
    return this.getView(room.code, playerOrder[0]!);
  }

  restart(room: RoomView): GameSnapshot {
    return this.start(room);
  }

  end(roomCode: string): void {
    this.games.delete(roomCode);
  }

  getStats(): { matches: number } {
    return { matches: this.games.size };
  }

  playCards(roomCode: string, playerId: string, cardIndexes: number[]): PlayCardsResult {
    const game = this.requireGame(roomCode);
    this.requireTurn(game, playerId);
    if (game.mustChallenge) throw new RoomError('MUST_CHALLENGE', '当前必须质疑上一手');
    if (cardIndexes.length < 1 || cardIndexes.length > MAX_CARDS_PER_PLAY) throw new RoomError('INVALID_CARD_SELECTION', '请选择 1 到 3 张牌');
    if (new Set(cardIndexes).size !== cardIndexes.length) throw new RoomError('INVALID_CARD_SELECTION', '不能重复选择同一张牌');
    const hand = game.hands.get(playerId);
    if (!hand) throw new RoomError('PLAYER_NOT_IN_GAME', '你不在本局游戏中');
    if (cardIndexes.some((index) => index < 0 || index >= hand.length)) throw new RoomError('INVALID_CARD_SELECTION', '选择了不存在的手牌');
    const playRange = this.playRange(game);
    if (cardIndexes.length < playRange.min) throw new RoomError('INVALID_CARD_SELECTION', `本模式至少选择 ${playRange.min} 张牌`);
    if (cardIndexes.length > playRange.max) throw new RoomError('INVALID_CARD_SELECTION', playRange.min === playRange.max ? `本模式必须选择 ${playRange.max} 张牌` : `本模式最多选择 ${playRange.max} 张牌`);

    const cards = cardIndexes.map((index) => hand[index]!);
    [...cardIndexes].sort((a, b) => b - a).forEach((index) => hand.splice(index, 1));
    game.lastPlay = { playerId, cards, count: cards.length };
    game.discardCount += cards.length;
    if (game.gameMode === 'PARTY' && game.tavernEvent?.type === 'MATCH_BET' && game.partyRequiredPlayCount === null) {
      game.partyRequiredPlayCount = cards.length;
    }
    game.successfulPlayCountThisRound += 1;
    const nextPlayerId = this.nextAlivePlayerId(game, playerId);
    game.freeChallengeWindow = null;
    if (getChallengePolicy(game.gameMode) === 'FREE_WINDOW') {
      game.turnPlayerId = null;
      game.mustChallenge = false;
      this.openFreeChallengeWindow(game, playerId);
    } else {
      game.turnPlayerId = nextPlayerId;
      game.mustChallenge = hand.length === 0 || this.shouldForceChallengeNextTurn(game, nextPlayerId);
      this.enterPhase(game, 'TURN', this.turnDurationMs(game));
    }

    const state = this.getView(roomCode, playerId);
    return {
      state,
      cue: {
        type: 'CARD_PLAYED',
        sequence: game.phaseSequence,
        roomCode,
        playerId,
        count: cards.length,
        roundNumber: game.roundNumber,
      },
    };
  }

  challenge(roomCode: string, challengerId: string): ChallengeResult {
    const game = this.requireGame(roomCode);
    if (getChallengePolicy(game.gameMode) === 'FREE_WINDOW' && game.pendingChallenge && game.pendingChallenge.challengedId === game.lastPlay?.playerId) {
      throw new RoomError('CHALLENGE_ALREADY_TAKEN', '已经有玩家抢先质疑');
    }
    if (getChallengePolicy(game.gameMode) === 'FREE_WINDOW') {
      if (game.phase !== 'CHALLENGE_WINDOW') throw new RoomError('CHALLENGE_WINDOW_CLOSED', '质疑窗口已经关闭');
      this.requireFreeChallenge(game, challengerId);
    } else {
      this.requireTurn(game, challengerId);
    }
    return this.acceptChallenge(game, roomCode, challengerId);
  }

  private acceptChallenge(game: InternalGame, roomCode: string, challengerId: string): ChallengeResult {
    if (!game.lastPlay) throw new RoomError('NO_PLAY_TO_CHALLENGE', '当前没有可质疑的上一手');
    if (game.freeChallengeWindow) game.freeChallengeWindow.challengerId = challengerId;
    const wasBluff = game.lastPlay.cards.some((card) => !this.isTruthCard(game, card));
    const punishedPlayerId = wasBluff ? game.lastPlay.playerId : challengerId;
    game.pendingChallenge = {
      challengerId,
      challengedId: game.lastPlay.playerId,
      revealedCards: [...game.lastPlay.cards],
      wasBluff,
      punishedPlayerId,
      shots: [],
      maxShots: this.maxPunishmentShots(game),
      publishedShotCount: 0,
      resultPublished: false,
    };
    game.challengeCount += 1;
    if (wasBluff) game.successfulChallenges += 1;
    else game.failedChallenges += 1;
    game.mustChallenge = false;
    game.turnPlayerId = null;
    game.freeChallengeWindow = null;
    this.enterPhase(game, 'CHALLENGE_CALLOUT', cinematicTiming.CHALLENGE_CALLOUT);

    const state = this.getView(roomCode, challengerId);
    return {
      state,
      cue: {
        type: 'CHALLENGE_CALLED',
        sequence: game.phaseSequence,
        roomCode,
        playerId: challengerId,
        targetPlayerId: game.lastPlay.playerId,
        roundNumber: game.roundNumber,
      },
    };
  }

  autoAct(roomCode: string): PlayCardsResult | ChallengeResult {
    const game = this.requireGame(roomCode);
    if (game.phase !== 'TURN' || !game.turnPlayerId) throw new RoomError('PHASE_LOCKED', '当前阶段无法自动操作');
    if (game.mustChallenge) return this.challenge(roomCode, game.turnPlayerId);
    const hand = game.hands.get(game.turnPlayerId) ?? [];
    if (hand.length === 0) return this.challenge(roomCode, game.turnPlayerId);
    const playRange = this.playRange(game);
    if (hand.length < playRange.min) return this.challenge(roomCode, game.turnPlayerId);
    return this.playCards(roomCode, game.turnPlayerId, this.pickAutoCardIndexes(hand.length, playRange.min));
  }

  private resolveFreeChallengeTimeout(roomCode: string): ChallengeResult | null {
    const game = this.requireGame(roomCode);
    const lastPlay = game.lastPlay;
    if (!lastPlay) throw new RoomError('NO_PLAY_TO_CHALLENGE', '当前没有可质疑的上一手');
    if ((game.hands.get(lastPlay.playerId)?.length ?? 0) === 0) {
      const challengerId = this.nextAlivePlayerId(game, lastPlay.playerId);
      if (!challengerId) throw new RoomError('NO_CHALLENGER_AVAILABLE', '当前没有可质疑的玩家');
      return this.acceptChallenge(game, roomCode, challengerId);
    }
    game.freeChallengeWindow = null;
    const nextPlayerId = this.nextAlivePlayerId(game, lastPlay.playerId);
    game.turnPlayerId = nextPlayerId;
    game.mustChallenge = this.shouldForceChallengeNextTurn(game, nextPlayerId);
    this.enterPhase(game, 'TURN', this.turnDurationMs(game));
    return null;
  }

  useItem(roomCode: string, playerId: string, itemId: ActiveItemId): GameSnapshot {
    const game = this.requireGame(roomCode);
    if (!game.v7.itemsEnabled) throw new RoomError('FEATURE_DISABLED', 'V7 道具未开启');
    this.requireAlivePlayer(game, playerId);
    const inventory = game.itemInventories.get(playerId) ?? [];
    if (!inventory.includes(itemId)) throw new RoomError('ITEM_NOT_AVAILABLE', '你没有这个道具');

    const effect = this.resolveItemEffect(game, playerId, itemId);
    this.consumeItem(inventory, itemId);
    game.itemEffects.set(playerId, effect);
    this.touch(game);
    return this.getView(roomCode, playerId);
  }

  advancePhase(roomCode: string): PhaseAdvanceResult {
    const game = this.requireGame(roomCode);
    const cues: GameCue[] = [];
    let eliminatedPlayerId: string | null = null;
    let gameOver = false;

    switch (game.phase) {
      case 'TURN': {
        const result = this.autoAct(roomCode);
        return { state: result.state, cues: [result.cue], eliminatedPlayerId, gameOver };
      }
      case 'CHALLENGE_WINDOW': {
        const result = this.resolveFreeChallengeTimeout(roomCode);
        if (result) return { state: result.state, cues: [result.cue], eliminatedPlayerId, gameOver };
        break;
      }
      case 'ROUND_START':
        this.enterPhase(game, 'TURN', this.turnDurationMs(game));
        break;
      case 'CHALLENGE_CALLOUT':
        this.enterPhase(game, 'REVEAL', this.revealDurationMs(game));
        break;
      case 'REVEAL':
        this.enterPhase(game, 'VERDICT', cinematicTiming.VERDICT);
        break;
      case 'VERDICT':
        this.enterPhase(game, 'PUNISHMENT_INTRO', cinematicTiming.PUNISHMENT_INTRO);
        break;
      case 'PUNISHMENT_INTRO':
        this.enterPhase(game, 'PUNISHMENT_TRIGGER', this.punishmentTriggerDurationMs(game));
        break;
      case 'PUNISHMENT_TRIGGER':
        ({ eliminatedPlayerId } = this.publishPunishmentResult(game));
        if (eliminatedPlayerId) {
          cues.push({
            type: 'PLAYER_ELIMINATED',
            sequence: game.phaseSequence + 1,
            roomCode,
            playerId: eliminatedPlayerId,
            roundNumber: game.roundNumber,
          });
        }
        this.enterPhase(game, 'PUNISHMENT_RESULT', game.punishment?.hit ? 1_650 : 1_250);
        break;
      case 'PUNISHMENT_RESULT':
        if (this.hasPendingPunishmentShot(game)) this.enterPhase(game, 'PUNISHMENT_TRIGGER', this.punishmentTriggerDurationMs(game));
        else {
          this.finalizeChallengeRound(game);
          this.enterPhase(game, 'ROUND_END', cinematicTiming.ROUND_END);
        }
        break;
      case 'ROUND_END':
        if (game.alivePlayerIds.size <= 1) {
          game.winnerId = [...game.alivePlayerIds][0] ?? null;
          this.enterPhase(game, 'GAME_OVER', null);
          gameOver = true;
          cues.push(game.winnerId
            ? { type: 'MATCH_FINISHED', sequence: game.phaseSequence, roomCode, playerId: game.winnerId }
            : { type: 'MATCH_FINISHED', sequence: game.phaseSequence, roomCode });
        } else {
          this.startRound(game, game.nextRoundStarterId);
          cues.push({ type: 'ROUND_STARTED', sequence: game.phaseSequence, roomCode, roundNumber: game.roundNumber });
        }
        break;
      default:
        throw new RoomError('PHASE_LOCKED', '当前阶段不能自动推进');
    }

    return { state: this.getView(roomCode, game.playerOrder[0]!), cues, eliminatedPlayerId, gameOver };
  }

  getView(roomCode: string, viewerId: string): GameSnapshot {
    const game = this.requireGame(roomCode);
    const now = Date.now();
    const hand = game.hands.get(viewerId) ?? [];
    const challenge = this.getPublicChallenge(game);
    const challengeResult = challenge && challenge.wasBluff !== null && challenge.punishedPlayerId !== null && challenge.revealedCards !== null
      ? {
        challengerId: challenge.challengerId,
        failedPlayerId: challenge.punishedPlayerId,
        wasBluff: challenge.wasBluff,
        revealedCards: [...challenge.revealedCards],
      }
      : null;
    const summary = game.winnerId
      ? {
          winnerId: game.winnerId,
          playerCount: game.playerOrder.length,
          durationSeconds: Math.max(0, Math.floor((now - game.startedAt) / 1_000)),
          challengeCount: game.challengeCount,
          successfulChallenges: game.successfulChallenges,
          failedChallenges: game.failedChallenges,
          eliminationOrder: [...game.eliminationOrder],
        }
      : null;

    return {
      matchId: game.matchId,
      sequence: game.phaseSequence,
      serverNow: now,
      phase: game.phase,
      phaseStartedAt: game.phaseStartedAt,
      phaseEndsAt: game.phaseEndsAt,
      gameMode: game.gameMode,
      turnDurationSeconds: this.turnDurationSeconds(game),
      roundNumber: game.roundNumber,
      targetRank: game.targetRank,
      targetCard: game.targetRank,
      turnPlayerId: game.turnPlayerId,
      mustChallenge: game.mustChallenge,
      minimumPlayCount: this.minimumPlayCount(game),
      maximumPlayCount: this.maximumPlayCount(game),
      turnDirection: game.turnDirection,
      players: game.playerOrder.map((playerId, seatIndex) => {
        const handCount = game.hands.get(playerId)?.length ?? 0;
        const publicHandCount = this.shouldHideHandCount(game, viewerId, playerId) ? null : handCount;
        return {
          playerId,
          name: game.playerNames.get(playerId) ?? playerId,
          seatIndex,
          connected: game.connectedPlayerIds.has(playerId),
          alive: game.alivePlayerIds.has(playerId),
          handCount: publicHandCount,
          cardCount: publicHandCount,
        };
      }),
      hand: [...hand],
      discardCount: this.publicDiscardCount(game),
      lastPlay: game.lastPlay ? { playerId: game.lastPlay.playerId, count: this.publicLastPlayCount(game, viewerId), claimedRank: game.targetRank } : null,
      challenge,
      punishment: game.punishment ? { ...game.punishment } : null,
      winner: game.winnerId ? { winnerId: game.winnerId } : null,
      freeChallenge: game.freeChallengeWindow ? { ...game.freeChallengeWindow } : null,
      sharedRevolver: this.getPublicSharedRevolver(game),
      alivePlayerIds: [...game.alivePlayerIds],
      winnerId: game.winnerId,
      summary,
      tavernEvent: this.shouldPublishTavernEvent(game) && game.tavernEvent ? { ...game.tavernEvent } : null,
      partyEventHistory: game.gameMode === 'PARTY' ? game.partyEventHistory.map((entry) => ({ ...entry })) : [],
      items: game.v7.itemsEnabled ? [...(game.itemInventories.get(viewerId) ?? [])] : [],
      itemEffect: game.v7.itemsEnabled ? this.getItemEffect(game, viewerId, now) : null,
      abilityEffect: game.v7.characterAbilitiesEnabled ? this.getAbilityEffect(game, viewerId, now) : null,
      challengeResult,
    };
  }

  getViews(roomCode: string): Map<string, GameSnapshot> {
    const game = this.requireGame(roomCode);
    return new Map(game.playerOrder.map((playerId) => [playerId, this.getView(roomCode, playerId)]));
  }

  getPhaseEndsAt(roomCode: string): number | null {
    return this.requireGame(roomCode).phaseEndsAt;
  }

  updateConnections(room: RoomView): void {
    const game = this.games.get(room.code);
    if (!game) return;
    game.connectedPlayerIds = new Set(room.players.filter((player) => player.isConnected).map((player) => player.id));
  }

  debugSetHand(roomCode: string, playerId: string, hand: CardRank[]): void {
    const game = this.requireGame(roomCode);
    game.hands.set(playerId, [...hand]);
  }

  debugSetRevolver(roomCode: string, playerId: string, revolver: RevolverState): void {
    const game = this.requireGame(roomCode);
    game.revolvers.set(playerId, { ...revolver });
  }

  debugSetSharedRevolver(roomCode: string, revolver: RevolverState): void {
    const game = this.requireGame(roomCode);
    game.sharedRevolver = { ...revolver };
  }

  debugSetItems(roomCode: string, playerId: string, items: ActiveItemId[]): void {
    const game = this.requireGame(roomCode);
    game.itemInventories.set(playerId, [...items]);
  }

  debugSetTavernEvent(roomCode: string, type: PublicTavernEvent['type'] | null): void {
    const game = this.requireGame(roomCode);
    game.tavernEvent = type ? this.createTavernEvent(type, game.roundNumber, this.eventTurnDurationSeconds(game, type)) : null;
    game.roundTurnDurationSeconds = this.turnDurationSeconds(game);
    game.turnDirection = game.tavernEvent?.type === 'DRUNKEN' ? 'COUNTERCLOCKWISE' : 'CLOCKWISE';
    game.partyRequiredPlayCount = null;
    game.successfulPlayCountThisRound = 0;
  }

  private startRound(game: InternalGame, starterId: string | null): void {
    game.roundNumber += 1;
    game.hands = new Map(game.playerOrder.map((playerId) => [playerId, []]));
    const alivePlayers = game.playerOrder.filter((playerId) => game.alivePlayerIds.has(playerId));
    const deck = this.createDeck(alivePlayers.length * 5);
    this.shuffle(deck);
    for (const [seatIndex, playerId] of alivePlayers.entries()) {
      game.hands.set(playerId, deck.slice(seatIndex * 5, seatIndex * 5 + 5));
    }
    game.targetRank = targets[this.random.nextInt(targets.length)]!;
    game.partyRequiredPlayCount = null;
    game.successfulPlayCountThisRound = 0;
    game.tavernEvent = game.gameMode === 'PARTY'
      ? this.drawPartyEvent(game)
      : this.drawTavernEvent(game.roundNumber, game.turnDurationSeconds, this.supportsLegacyTavernEvents(game) && game.v7.tavernEventsEnabled);
    game.roundTurnDurationSeconds = this.turnDurationSeconds(game);
    game.turnDirection = game.tavernEvent?.type === 'DRUNKEN' ? 'COUNTERCLOCKWISE' : 'CLOCKWISE';
    if (game.gameMode === 'PARTY' && game.tavernEvent) {
      game.partyEventHistory = [...game.partyEventHistory, {
        roundNumber: game.roundNumber,
        type: game.tavernEvent.type,
        title: game.tavernEvent.title,
      }].slice(-3);
      game.recentPartyEventTypes = [...game.recentPartyEventTypes, game.tavernEvent.type].slice(-2);
      if (process.env.NODE_ENV !== 'test') {
        console.info('party_event_selected', { roomCode: game.roomCode, roundNumber: game.roundNumber, eventType: game.tavernEvent.type });
      }
    }
    game.turnPlayerId = starterId && game.alivePlayerIds.has(starterId) ? starterId : alivePlayers[0] ?? null;
    game.nextRoundStarterId = game.turnPlayerId;
    game.lastPlay = null;
    game.mustChallenge = false;
    game.pendingChallenge = null;
    game.punishment = null;
    game.freeChallengeWindow = null;
    game.discardCount = 0;
    this.enterPhase(game, 'ROUND_START', cinematicTiming.ROUND_START);
  }

  private publishPunishmentResult(game: InternalGame): { eliminatedPlayerId: string | null } {
    const pending = game.pendingChallenge;
    if (!pending) throw new RoomError('PUNISHMENT_NOT_ALLOWED', '当前没有惩罚结果');
    if (pending.resultPublished) return { eliminatedPlayerId: game.punishment?.eliminatedPlayerId ?? null };

    const shot = this.commitPunishmentShot(game, pending);
    pending.publishedShotCount += 1;
    const totalShots = shot.hit ? pending.publishedShotCount : pending.maxShots;
    const eliminatedPlayerId = shot.hit ? pending.punishedPlayerId : null;
    if (eliminatedPlayerId) {
      game.alivePlayerIds.delete(eliminatedPlayerId);
      game.hands.set(eliminatedPlayerId, []);
      game.itemInventories.set(eliminatedPlayerId, []);
      game.itemEffects.delete(eliminatedPlayerId);
      game.abilityEffects.delete(eliminatedPlayerId);
      game.eliminationOrder.push(eliminatedPlayerId);
      if (game.alivePlayerIds.size === 1) game.winnerId = [...game.alivePlayerIds][0]!;
    }
    game.turnPlayerId = null;
    game.punishment = {
      punishedPlayerId: pending.punishedPlayerId,
      playerId: pending.punishedPlayerId,
      chamber: shot.chamber,
      hit: shot.hit,
      eliminatedPlayerId,
      shotNumber: pending.publishedShotCount,
      totalShots,
    };
    if (shot.hit || pending.publishedShotCount >= totalShots) pending.resultPublished = true;
    return { eliminatedPlayerId };
  }

  private finalizeChallengeRound(game: InternalGame): void {
    const pending = game.pendingChallenge;
    if (!pending) return;
    game.nextRoundStarterId = game.punishment?.hit
      ? this.nextAlivePlayerId(game, pending.punishedPlayerId)
      : pending.punishedPlayerId;
  }

  private hasPendingPunishmentShot(game: InternalGame): boolean {
    const pending = game.pendingChallenge;
    if (!pending || pending.resultPublished) return false;
    if (game.punishment?.hit) return false;
    return pending.publishedShotCount < pending.maxShots;
  }

  private enterPhase(game: InternalGame, phase: GamePhase, durationMs: number | null): void {
    const now = Date.now();
    game.phase = phase;
    game.phaseSequence += 1;
    game.phaseStartedAt = now;
    game.phaseEndsAt = durationMs === null ? null : now + durationMs;
    this.applyPhaseAbilities(game, now);
  }

  private openFreeChallengeWindow(game: InternalGame, challengedId: string): void {
    const now = Date.now();
    game.freeChallengeWindow = {
      challengedId,
      openedAt: now,
      endsAt: now + FREE_CHALLENGE_WINDOW_MS,
      challengerId: null,
    };
    this.enterPhase(game, 'CHALLENGE_WINDOW', FREE_CHALLENGE_WINDOW_MS);
  }

  private getPublicChallenge(game: InternalGame): PublicChallengeState | null {
    const pending = game.pendingChallenge;
    if (!pending) return null;
    if (game.phase === 'CHALLENGE_CALLOUT') {
      return {
        challengerId: pending.challengerId,
        challengedId: pending.challengedId,
        revealedCards: null,
        wasBluff: null,
        punishedPlayerId: null,
      };
    }
    if (game.phase === 'REVEAL') {
      return {
        challengerId: pending.challengerId,
        challengedId: pending.challengedId,
        revealedCards: [...pending.revealedCards],
        wasBluff: null,
        punishedPlayerId: null,
      };
    }
    return {
      challengerId: pending.challengerId,
      challengedId: pending.challengedId,
      revealedCards: [...pending.revealedCards],
      wasBluff: pending.wasBluff,
      punishedPlayerId: pending.punishedPlayerId,
    };
  }

  private applyPhaseAbilities(game: InternalGame, now: number): void {
    if (!game.v7.characterAbilitiesEnabled) return;
    if (game.phase === 'ROUND_START') {
      for (const playerId of game.playerOrder) {
        if (game.alivePlayerIds.has(playerId)) this.applyRoundStartAbility(game, playerId, now);
      }
      return;
    }
    if (game.phase === 'TURN' && game.turnPlayerId) {
      this.applyTurnStartAbility(game, game.turnPlayerId, now);
      return;
    }
    if (game.phase === 'VERDICT') {
      this.applyVerdictAbility(game, now);
    }
  }

  private applyRoundStartAbility(game: InternalGame, playerId: string, now: number): void {
    const characterId = game.playerCharacters.get(playerId);
    if (!characterId) return;
    const abilityId = characterAbilities[characterId];
    if (abilityId === 'CAT_NIGHT_EYE' && this.takeAbilityUse(game, playerId, abilityId, `round:${game.roundNumber}`)) {
      const riskLevel = this.revolverRiskLevel(game, playerId);
      this.setAbilityEffect(game, playerId, {
        abilityId,
        characterId,
        type: 'RISK_HINT',
        title: '黑猫 · 夜眼',
        riskLevel,
        roundNumber: game.roundNumber,
        expiresAt: now + ABILITY_EFFECT_DURATION_MS,
        message: riskLevel === 'HIGH'
          ? '夜眼：下一次轮到你受罚时风险偏高。'
          : '夜眼：下一次轮到你受罚时风险偏低。',
      });
      return;
    }
    if (abilityId === 'RACCOON_POCKET_FIND' && this.takeAbilityUse(game, playerId, abilityId, 'match')) {
      if (!game.v7.itemsEnabled) {
        this.setAbilityEffect(game, playerId, {
          abilityId,
          characterId,
          type: 'ITEM_SKIPPED',
          title: '浣熊 · 摸袋',
          roundNumber: game.roundNumber,
          expiresAt: now + ABILITY_EFFECT_DURATION_MS,
          message: '摸袋：本局未启用道具，不会额外生成道具。',
        });
        return;
      }
      const item = this.dealItem();
      const inventory = game.itemInventories.get(playerId) ?? [];
      inventory.push(item);
      game.itemInventories.set(playerId, inventory);
      this.setAbilityEffect(game, playerId, {
        abilityId,
        characterId,
        type: 'ITEM_GRANTED',
        title: '浣熊 · 摸袋',
        grantedItem: item,
        roundNumber: game.roundNumber,
        expiresAt: now + ABILITY_EFFECT_DURATION_MS,
        message: `摸袋：你额外摸到 ${this.itemName(item)}。`,
      });
    }
  }

  private applyTurnStartAbility(game: InternalGame, playerId: string, now: number): void {
    const characterId = game.playerCharacters.get(playerId);
    if (!characterId) return;
    const abilityId = characterAbilities[characterId];
    if (abilityId === 'WOLF_TABLE_READ' && this.takeAbilityUse(game, playerId, abilityId, `round:${game.roundNumber}`)) {
      const safeCards = this.safeHandCount(game, playerId);
      const previous = game.lastPlay
        ? `${this.playerName(game, game.lastPlay.playerId)} 刚声明 ${game.lastPlay.count} 张 ${game.targetRank}`
        : '你是本轮先手';
      this.setAbilityEffect(game, playerId, {
        abilityId,
        characterId,
        type: 'ROUND_READ',
        title: '灰狼 · 牌桌嗅觉',
        roundNumber: game.roundNumber,
        expiresAt: now + ABILITY_EFFECT_DURATION_MS,
        message: `牌桌嗅觉：${previous}；你手里有 ${safeCards} 张${this.truthCardHintLabel(game)}。`,
      });
      return;
    }
    if (abilityId === 'FOX_HAND_HINT' && this.takeAbilityUse(game, playerId, abilityId, 'match')) {
      const safeCards = this.safeHandCount(game, playerId);
      this.setAbilityEffect(game, playerId, {
        abilityId,
        characterId,
        type: 'HAND_HINT',
        title: '赤狐 · 花言',
        roundNumber: game.roundNumber,
        expiresAt: now + ABILITY_EFFECT_DURATION_MS,
        message: `花言：${this.foxAdvice(safeCards)} 当前手里有 ${safeCards} 张${this.truthCardHintLabel(game)}。`,
      });
      return;
    }
    if (abilityId === 'BEAR_OPENING_NERVE' && !game.lastPlay && this.takeAbilityUse(game, playerId, abilityId, `round:${game.roundNumber}`)) {
      this.extendCurrentPhase(game, now, BEAR_OPENING_EXTENSION_SECONDS);
      this.setAbilityEffect(game, playerId, {
        abilityId,
        characterId,
        type: 'TURN_TIME_EXTENDED',
        title: '棕熊 · 稳坐',
        extraSeconds: BEAR_OPENING_EXTENSION_SECONDS,
        roundNumber: game.roundNumber,
        expiresAt: now + ABILITY_EFFECT_DURATION_MS,
        message: `稳坐：本轮先手回合延长 ${BEAR_OPENING_EXTENSION_SECONDS} 秒。`,
      });
      return;
    }
    if (abilityId === 'RABBIT_QUICK_STEP' && this.takeAbilityUse(game, playerId, abilityId, 'match')) {
      this.extendCurrentPhase(game, now, RABBIT_EXTENSION_SECONDS);
      this.setAbilityEffect(game, playerId, {
        abilityId,
        characterId,
        type: 'TURN_TIME_EXTENDED',
        title: '白兔 · 抢秒',
        extraSeconds: RABBIT_EXTENSION_SECONDS,
        roundNumber: game.roundNumber,
        expiresAt: now + ABILITY_EFFECT_DURATION_MS,
        message: `抢秒：本局第一次自己的回合延长 ${RABBIT_EXTENSION_SECONDS} 秒。`,
      });
      return;
    }
    if (abilityId === 'FROG_STEADY_BREATH' && game.mustChallenge && this.takeAbilityUse(game, playerId, abilityId, 'match')) {
      this.extendCurrentPhase(game, now, FROG_CHALLENGE_EXTENSION_SECONDS);
      this.setAbilityEffect(game, playerId, {
        abilityId,
        characterId,
        type: 'FORCED_CHALLENGE_TIME',
        title: '青蛙 · 沉息',
        extraSeconds: FROG_CHALLENGE_EXTENSION_SECONDS,
        roundNumber: game.roundNumber,
        expiresAt: now + ABILITY_EFFECT_DURATION_MS,
        message: `沉息：被迫质疑时额外获得 ${FROG_CHALLENGE_EXTENSION_SECONDS} 秒。`,
      });
    }
  }

  private applyVerdictAbility(game: InternalGame, now: number): void {
    const pending = game.pendingChallenge;
    if (!pending) return;
    for (const playerId of game.playerOrder) {
      if (!game.alivePlayerIds.has(playerId)) continue;
      const characterId = game.playerCharacters.get(playerId);
      if (!characterId || characterAbilities[characterId] !== 'PANDA_REVEAL_MEMORY') continue;
      const honestCards = pending.revealedCards.filter((card) => this.isTruthCard(game, card)).length;
      const bluffCards = pending.revealedCards.length - honestCards;
      this.setAbilityEffect(game, playerId, {
        abilityId: 'PANDA_REVEAL_MEMORY',
        characterId,
        type: 'REVEAL_MEMORY',
        title: '熊猫 · 记牌',
        roundNumber: game.roundNumber,
        expiresAt: now + ABILITY_EFFECT_DURATION_MS,
        message: `记牌：本次揭示 ${pending.revealedCards.length} 张，${this.truthCardMemoryLabel(game)} ${honestCards} 张，非目标 ${bluffCards} 张。`,
      });
    }
  }

  private resolveItemEffect(game: InternalGame, playerId: string, itemId: ActiveItemId): PrivateItemEffect {
    if (game.phase !== 'TURN') throw new RoomError('PHASE_LOCKED', '当前阶段无法使用道具');
    const now = Date.now();
    switch (itemId) {
      case 'SPYGLASS': {
        const revolver = getRevolverPolicy(game.gameMode) === 'SHARED' ? game.sharedRevolver : game.revolvers.get(playerId);
        if (!revolver) throw new RoomError('PLAYER_NOT_IN_GAME', '你不在本局游戏中');
        const riskLevel = revolver.currentChamber === revolver.bulletPosition ? 'HIGH' : 'LOW';
        return {
          itemId,
          type: 'SPYGLASS_RISK',
          riskLevel,
          expiresAt: now + ITEM_EFFECT_DURATION_MS,
          message: riskLevel === 'HIGH'
            ? '望远镜：下一次轮到你受罚时风险偏高。'
            : '望远镜：下一次轮到你受罚时风险偏低。',
        };
      }
      case 'POCKET_WATCH': {
        if (game.turnPlayerId !== playerId) throw new RoomError('NOT_YOUR_TURN', '怀表只能在自己的回合使用');
        if (game.phaseEndsAt === null) throw new RoomError('PHASE_LOCKED', '当前阶段没有可延长的倒计时');
        game.phaseEndsAt = Math.max(game.phaseEndsAt, now) + POCKET_WATCH_EXTENSION_SECONDS * 1_000;
        return {
          itemId,
          type: 'POCKET_WATCH_EXTENDED',
          expiresAt: now + ITEM_EFFECT_DURATION_MS,
          extraSeconds: POCKET_WATCH_EXTENSION_SECONDS,
          message: `旧怀表：本回合时间延长 ${POCKET_WATCH_EXTENSION_SECONDS} 秒。`,
        };
      }
      case 'TAVERN_MUG':
        return {
          itemId,
          type: 'TAVERN_MUG_TIPSY',
          expiresAt: now + ITEM_EFFECT_DURATION_MS,
          message: '酒杯：提示短暂晃动，但牌局判定不变。',
        };
      default: {
        const neverItem: never = itemId;
        return neverItem;
      }
    }
  }

  private consumeItem(inventory: ActiveItemId[], itemId: ActiveItemId): void {
    const index = inventory.indexOf(itemId);
    if (index >= 0) inventory.splice(index, 1);
  }

  private getItemEffect(game: InternalGame, playerId: string, now: number): PrivateItemEffect | null {
    const effect = game.itemEffects.get(playerId);
    if (!effect) return null;
    if (effect.expiresAt !== null && effect.expiresAt <= now) {
      game.itemEffects.delete(playerId);
      return null;
    }
    return { ...effect };
  }

  private getAbilityEffect(game: InternalGame, playerId: string, now: number): PrivateAbilityEffect | null {
    const effect = game.abilityEffects.get(playerId);
    if (!effect) return null;
    if (effect.expiresAt !== null && effect.expiresAt <= now) {
      game.abilityEffects.delete(playerId);
      return null;
    }
    return { ...effect };
  }

  private setAbilityEffect(game: InternalGame, playerId: string, effect: PrivateAbilityEffect): void {
    game.abilityEffects.set(playerId, effect);
  }

  private takeAbilityUse(game: InternalGame, playerId: string, abilityId: CharacterAbilityId, scope: string): boolean {
    const key = `${playerId}:${abilityId}:${scope}`;
    if (game.abilityUsedKeys.has(key)) return false;
    game.abilityUsedKeys.add(key);
    return true;
  }

  private extendCurrentPhase(game: InternalGame, now: number, seconds: number): void {
    if (game.phaseEndsAt === null) return;
    game.phaseEndsAt = Math.max(game.phaseEndsAt, now) + seconds * 1_000;
  }

  private safeHandCount(game: InternalGame, playerId: string): number {
    const hand = game.hands.get(playerId) ?? [];
    return hand.filter((card) => this.isTruthCard(game, card)).length;
  }

  private revolverRiskLevel(game: InternalGame, playerId: string): 'LOW' | 'HIGH' {
    const revolver = getRevolverPolicy(game.gameMode) === 'SHARED' ? game.sharedRevolver : game.revolvers.get(playerId);
    if (!revolver) throw new RoomError('PLAYER_NOT_IN_GAME', '你不在本局游戏中');
    return revolver.currentChamber === revolver.bulletPosition ? 'HIGH' : 'LOW';
  }

  private playerName(game: InternalGame, playerId: string): string {
    return game.playerNames.get(playerId) ?? playerId;
  }

  private foxAdvice(safeCards: number): string {
    if (safeCards >= 3) return '目标牌充足，可以考虑较大胆的声明。';
    if (safeCards >= 1) return '手里有少量目标牌，适合小手数观察。';
    return '目标牌不足，保守出牌或寻找质疑窗口更稳。';
  }

  private truthCardHintLabel(game: InternalGame): string {
    return game.tavernEvent?.type === 'NO_JOKER' ? '目标牌' : '目标牌或 Joker';
  }

  private truthCardMemoryLabel(game: InternalGame): string {
    return game.tavernEvent?.type === 'NO_JOKER' ? '目标牌' : '目标/Joker';
  }

  private itemName(itemId: ActiveItemId): string {
    if (itemId === 'SPYGLASS') return '望远镜';
    if (itemId === 'POCKET_WATCH') return '旧怀表';
    return '酒杯';
  }

  private drawTavernEvent(roundNumber: number, baseTurnDurationSeconds: number, enabled: boolean): PublicTavernEvent | null {
    if (!enabled) return null;
    if (this.random.nextInt(100) >= TAVERN_EVENT_CHANCE_PERCENT) return null;
    const type = tavernEventPool[this.random.nextInt(tavernEventPool.length)]!;
    return this.createTavernEvent(type, roundNumber, this.eventTurnDurationSecondsFor('CLASSIC', type, baseTurnDurationSeconds, 0));
  }

  private drawPartyEvent(game: InternalGame): PublicTavernEvent {
    const recentSet = new Set(game.recentPartyEventTypes);
    let choices = partyEventPool.filter((eventType) => !recentSet.has(eventType));
    if (choices.length === 0 && game.recentPartyEventTypes.length > 0) {
      const previous = game.recentPartyEventTypes.at(-1);
      choices = partyEventPool.filter((eventType) => eventType !== previous);
    }
    if (choices.length === 0) choices = [...partyEventPool];
    const type = this.weightedPartyEvent(choices);
    return this.createTavernEvent(type, game.roundNumber, this.eventTurnDurationSeconds(game, type));
  }

  private createTavernEvent(type: PublicTavernEvent['type'], roundNumber: number, baseTurnDurationSeconds: number): PublicTavernEvent {
    const meta = partyEventMeta[type];
    return {
      ...meta,
      description: type === 'RAPID_NIGHT' ? `本轮每名玩家只有 ${baseTurnDurationSeconds} 秒行动时间。` : meta.description,
      roundNumber,
      turnDurationSeconds: type === 'RAPID_NIGHT' ? baseTurnDurationSeconds : null,
    };
  }

  private requireTurn(game: InternalGame, playerId: string): void {
    if (game.phase !== 'TURN') throw new RoomError('PHASE_LOCKED', '当前阶段无法操作');
    if (!game.alivePlayerIds.has(playerId)) throw new RoomError('PLAYER_ELIMINATED', '已淘汰玩家不能操作');
    if (game.turnPlayerId !== playerId) throw new RoomError('NOT_YOUR_TURN', '现在不是你的回合');
  }

  private requireFreeChallenge(game: InternalGame, playerId: string): void {
    if (!game.lastPlay || !game.freeChallengeWindow) throw new RoomError('NO_PLAY_TO_CHALLENGE', '当前没有可质疑的上一手');
    if (Date.now() >= game.freeChallengeWindow.endsAt) throw new RoomError('CHALLENGE_WINDOW_CLOSED', '质疑窗口已经关闭');
    if (game.freeChallengeWindow.challengerId) throw new RoomError('CHALLENGE_ALREADY_TAKEN', '已经有玩家抢先质疑');
    if (!game.alivePlayerIds.has(playerId)) throw new RoomError('PLAYER_ELIMINATED', '已淘汰玩家不能质疑');
    if (!game.connectedPlayerIds.has(playerId)) throw new RoomError('PLAYER_DISCONNECTED', '离线玩家不能质疑');
    if (game.lastPlay.playerId === playerId) throw new RoomError('CANNOT_CHALLENGE_SELF', '不能质疑自己的出牌');
  }

  private requireAlivePlayer(game: InternalGame, playerId: string): void {
    if (!game.playerOrder.includes(playerId)) throw new RoomError('PLAYER_NOT_IN_GAME', '你不在本局游戏中');
    if (!game.alivePlayerIds.has(playerId)) throw new RoomError('PLAYER_ELIMINATED', '已淘汰玩家不能使用道具');
  }

  private nextAlivePlayerId(game: InternalGame, playerId: string): string | null {
    if (game.alivePlayerIds.size === 0) return null;
    const start = game.playerOrder.indexOf(playerId);
    const step = game.turnDirection === 'COUNTERCLOCKWISE' ? -1 : 1;
    for (let offset = 1; offset <= game.playerOrder.length; offset += 1) {
      const candidate = game.playerOrder[(start + offset * step + game.playerOrder.length * 2) % game.playerOrder.length]!;
      if (game.alivePlayerIds.has(candidate)) return candidate;
    }
    return null;
  }

  private createDeck(cardCount: number): CardRank[] {
    const cycle: CardRank[] = ['A', 'K', 'Q', 'JOKER'];
    return Array.from({ length: cardCount }, (_, index) => cycle[index % cycle.length]!);
  }

  private shuffle(deck: CardRank[]): void {
    for (let index = deck.length - 1; index > 0; index -= 1) {
      const swapIndex = this.random.nextInt(index + 1);
      [deck[index], deck[swapIndex]] = [deck[swapIndex]!, deck[index]!];
    }
  }

  private revealDurationMs(game: InternalGame): number {
    return cinematicTiming.REVEAL_INTRO
      + (game.pendingChallenge?.revealedCards.length ?? 0) * cinematicTiming.REVEAL_PER_CARD
      + cinematicTiming.REVEAL_FINAL_HOLD
      + (game.tavernEvent?.type === 'CANDLE_FLICKER' ? 500 : 0);
  }

  private punishmentTriggerDurationMs(game: InternalGame): number {
    return cinematicTiming.PUNISHMENT_TRIGGER + (game.tavernEvent?.type === 'DOUBLE_DANGER' ? 450 : 0);
  }

  private turnDurationMs(game: InternalGame): number {
    return this.turnDurationSeconds(game) * 1_000;
  }

  private minimumPlayCount(game: InternalGame): number {
    return this.playRange(game).min;
  }

  private maximumPlayCount(game: InternalGame): number {
    return this.playRange(game).max;
  }

  private playRange(game: InternalGame): EffectivePlayRange {
    return getEffectivePlayRange(this.modeRuleContext(game));
  }

  private turnDurationSeconds(game: InternalGame): number {
    return getEffectiveTurnSeconds(this.modeRuleContext(game));
  }

  private modeRuleContext(game: InternalGame) {
    return {
      gameMode: game.gameMode,
      eventType: game.tavernEvent?.type ?? null,
      lastPlayCount: game.lastPlay?.count ?? null,
      partyRequiredPlayCount: game.partyRequiredPlayCount,
      successfulPlayCountThisRound: game.successfulPlayCountThisRound,
      baseTurnDurationSeconds: game.turnDurationSeconds,
    };
  }

  private shouldForceChallengeNextTurn(game: InternalGame, playerId: string | null): boolean {
    if (!game.lastPlay || !playerId) return false;
    const hand = game.hands.get(playerId) ?? [];
    return hand.length < this.minimumPlayCount(game);
  }

  private pickAutoCardIndexes(handLength: number, count: number): number[] {
    const available = Array.from({ length: handLength }, (_, index) => index);
    const picked: number[] = [];
    while (picked.length < count && available.length > 0) {
      const index = this.random.nextInt(available.length);
      picked.push(available.splice(index, 1)[0]!);
    }
    return picked.sort((a, b) => a - b);
  }

  private eventTurnDurationSeconds(game: InternalGame, type: TavernEventType): number {
    return this.eventTurnDurationSecondsFor(game.gameMode, type, game.turnDurationSeconds, game.successfulPlayCountThisRound);
  }

  private eventTurnDurationSecondsFor(gameMode: PlayableGameMode, type: TavernEventType, baseTurnDurationSeconds: number, successfulPlayCountThisRound: number): number {
    return getEffectiveTurnSeconds({
      gameMode,
      eventType: type,
      lastPlayCount: null,
      partyRequiredPlayCount: null,
      successfulPlayCountThisRound,
      baseTurnDurationSeconds,
    });
  }

  private weightedPartyEvent(choices: readonly (typeof partyEventPool)[number][]): (typeof partyEventPool)[number] {
    const totalWeight = choices.reduce((sum, eventType) => sum + partyEventWeights[eventType], 0);
    let roll = this.random.nextInt(totalWeight);
    for (const eventType of choices) {
      roll -= partyEventWeights[eventType];
      if (roll < 0) return eventType;
    }
    return choices[choices.length - 1]!;
  }

  private dealItem(): ActiveItemId {
    return activeItemPool[this.random.nextInt(activeItemPool.length)]!;
  }

  private touch(game: InternalGame): void {
    game.phaseSequence += 1;
  }

  private resolveRevolverShot(game: InternalGame, playerId: string): { chamber: number; hit: boolean } {
    const revolver = getRevolverPolicy(game.gameMode) === 'SHARED' ? game.sharedRevolver : game.revolvers.get(playerId);
    if (!revolver) throw new RoomError('PLAYER_NOT_IN_GAME', '你不在本局游戏中');
    const chamber = revolver.currentChamber;
    const hit = chamber === revolver.bulletPosition;
    revolver.currentChamber = (revolver.currentChamber + 1) % revolver.chamberCount;
    revolver.shotsTaken += 1;
    if (hit && getRevolverPolicy(game.gameMode) === 'SHARED') game.sharedRevolver = this.createRevolver();
    return { chamber, hit };
  }

  private commitPunishmentShot(game: InternalGame, pending: PendingChallenge): { chamber: number; hit: boolean } {
    const shot = this.resolveRevolverShot(game, pending.punishedPlayerId);
    pending.shots.push(shot);
    return shot;
  }

  private maxPunishmentShots(game: InternalGame): number {
    return getPunishmentShotLimit({ gameMode: game.gameMode, eventType: game.tavernEvent?.type ?? null });
  }

  private isTruthCard(game: InternalGame, card: CardRank): boolean {
    if (card === game.targetRank) return true;
    if (card === 'JOKER') return isJokerWild({ eventType: game.tavernEvent?.type ?? null });
    return false;
  }

  private publicLastPlayCount(game: InternalGame, viewerId: string): number | null {
    if (!game.lastPlay) return null;
    if (game.gameMode !== 'PARTY' || game.tavernEvent?.type !== 'HIDDEN_BET') return game.lastPlay.count;
    if (viewerId === game.lastPlay.playerId) return game.lastPlay.count;
    if (!['TURN', 'CHALLENGE_WINDOW', 'CHALLENGE_CALLOUT'].includes(game.phase)) return game.lastPlay.count;
    return null;
  }

  private shouldHideHandCount(game: InternalGame, viewerId: string, playerId: string): boolean {
    return game.gameMode === 'PARTY'
      && game.tavernEvent?.type === 'HIDDEN_BET'
      && viewerId !== playerId;
  }

  private publicDiscardCount(game: InternalGame): number | null {
    // A cumulative total can expose earlier, unchallenged plays even to the current play owner.
    return game.gameMode === 'PARTY' && game.tavernEvent?.type === 'HIDDEN_BET'
      ? null
      : game.discardCount;
  }

  private shouldPublishTavernEvent(game: InternalGame): boolean {
    return game.gameMode === 'PARTY' || game.v7.tavernEventsEnabled;
  }

  private supportsLegacyTavernEvents(game: InternalGame): boolean {
    return game.gameMode === 'CLASSIC' || game.gameMode === 'QUICK';
  }

  private getPublicSharedRevolver(game: InternalGame): PublicSharedRevolverState | null {
    if (game.gameMode !== 'SHARED_REVOLVER' || !game.sharedRevolver) return null;
    return {
      chamberCount: game.sharedRevolver.chamberCount,
      currentChamber: game.sharedRevolver.currentChamber,
      shotsTaken: game.sharedRevolver.shotsTaken,
    };
  }

  private createRevolver(): RevolverState {
    return {
      chamberCount: 6,
      bulletPosition: this.random.nextInt(6),
      currentChamber: 0,
      shotsTaken: 0,
    };
  }

  private requirePlayableMode(gameMode: GameMode): PlayableGameMode {
    if (gameMode === 'CUSTOM') throw new RoomError('FEATURE_DISABLED', '自定义模式尚未开放');
    return gameMode;
  }

  private requireGame(roomCode: string): InternalGame {
    const game = this.games.get(roomCode);
    if (!game) throw new RoomError('GAME_NOT_FOUND', '牌局尚未开始');
    return game;
  }
}
