import type { PlayableGameMode, TavernEventType } from '@bluff-tavern/shared';

export interface EffectivePlayRange {
  min: number;
  max: number;
}

export type ChallengePolicy = 'NEXT_PLAYER' | 'FREE_WINDOW';
export type RevolverPolicy = 'PERSONAL' | 'SHARED';

export interface ModeRuleContext {
  gameMode: PlayableGameMode;
  eventType: TavernEventType | null;
  lastPlayCount: number | null;
  partyRequiredPlayCount: number | null;
  successfulPlayCountThisRound: number;
  baseTurnDurationSeconds: number;
}

export function getEffectivePlayRange(context: ModeRuleContext): EffectivePlayRange {
  if (context.gameMode === 'PARTY') {
    if (context.eventType === 'ONE_CARD_ONLY') return { min: 1, max: 1 };
    if (context.eventType === 'MATCH_BET' && context.partyRequiredPlayCount !== null) {
      return { min: context.partyRequiredPlayCount, max: context.partyRequiredPlayCount };
    }
    if (context.eventType === 'HEAVY_HAND') return { min: 2, max: 3 };
    if (context.eventType === 'FORCED_BET' && context.lastPlayCount !== null) return { min: 2, max: 3 };
  }

  if (context.gameMode === 'ESCALATION' && context.lastPlayCount !== null) {
    return { min: context.lastPlayCount, max: 3 };
  }

  return { min: 1, max: 3 };
}

export function getEffectiveTurnSeconds(context: ModeRuleContext): number {
  if (context.eventType === 'RAPID_NIGHT') {
    return context.gameMode === 'PARTY' ? 5 : Math.max(5, context.baseTurnDurationSeconds - 5);
  }
  if (context.gameMode === 'PARTY' && context.eventType === 'LAST_CALL') {
    return Math.max(6, 15 - context.successfulPlayCountThisRound * 3);
  }
  return context.baseTurnDurationSeconds;
}

export function isJokerWild(context: Pick<ModeRuleContext, 'eventType'>): boolean {
  return context.eventType !== 'NO_JOKER';
}

export function getPunishmentShotLimit(context: Pick<ModeRuleContext, 'gameMode' | 'eventType'>): number {
  return context.gameMode === 'PARTY' && context.eventType === 'DOUBLE_DANGER' ? 2 : 1;
}

export function getChallengePolicy(gameMode: PlayableGameMode): ChallengePolicy {
  return gameMode === 'FREE_CHALLENGE' ? 'FREE_WINDOW' : 'NEXT_PLAYER';
}

export function getRevolverPolicy(gameMode: PlayableGameMode): RevolverPolicy {
  return gameMode === 'SHARED_REVOLVER' ? 'SHARED' : 'PERSONAL';
}
