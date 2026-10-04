export const ROOM_CODE_LENGTH = 6;
export const APP_VERSION = '7.2.0';
export const ROOM_CODE_ALPHABET = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
export const MIN_NICKNAME_LENGTH = 1;
export const MAX_NICKNAME_LENGTH = 16;
export const MAX_PLAYERS = 8;
export const MIN_PLAYERS = 2;
export const CARDS_PER_RANK_BY_PLAYER_COUNT = [
  { maxPlayers: 4, copiesPerRank: 6, jokers: 2 },
  { maxPlayers: 6, copiesPerRank: 9, jokers: 3 },
  { maxPlayers: 8, copiesPerRank: 12, jokers: 4 },
] as const;
export const REVOLVER_BULLETS_BY_PLAYER_COUNT = [
  { maxPlayers: 4, bullets: 1 },
  { maxPlayers: 6, bullets: 2 },
  { maxPlayers: 8, bullets: 2 },
] as const;
export const MAX_CARDS_PER_PLAY = 3;
export const GAME_MODES = ['CLASSIC', 'QUICK', 'PARTY', 'FREE_CHALLENGE', 'SHARED_REVOLVER', 'ESCALATION', 'CUSTOM'] as const;
export const PLAYABLE_GAME_MODES = ['CLASSIC', 'QUICK', 'PARTY', 'FREE_CHALLENGE', 'SHARED_REVOLVER', 'ESCALATION'] as const;
export const CHARACTER_IDS = ['WOLF', 'FOX', 'BEAR', 'RABBIT', 'CAT', 'RACCOON', 'FROG', 'PANDA'] as const;
export const ITEM_IDS = ['SPYGLASS', 'SWAP_GLOVE', 'WAX_SEAL', 'TAVERN_MUG', 'POCKET_WATCH'] as const;
export const V7_ITEM_IDS = ['SPYGLASS', 'POCKET_WATCH', 'TAVERN_MUG'] as const;
export const V7_TAVERN_EVENT_TYPES = ['RAPID_NIGHT', 'CANDLE_FLICKER'] as const;
export const V7_PARTY_EVENT_TYPES = ['HIDDEN_BET', 'DRUNKEN', 'RAPID_NIGHT', 'DOUBLE_DANGER', 'NO_JOKER', 'FORCED_BET', 'ONE_CARD_ONLY', 'MATCH_BET', 'HEAVY_HAND', 'LAST_CALL'] as const;
export const V7_CHARACTER_ABILITY_IDS = [
  'WOLF_TABLE_READ',
  'FOX_HAND_HINT',
  'BEAR_OPENING_NERVE',
  'RABBIT_QUICK_STEP',
  'CAT_NIGHT_EYE',
  'RACCOON_POCKET_FIND',
  'FROG_STEADY_BREATH',
  'PANDA_REVEAL_MEMORY',
] as const;
export const EMOTE_IDS = ['CHEER', 'SUSPECT', 'BLUFF', 'LAUGH', 'GASP', 'NERVOUS', 'TOAST', 'GOOD_GAME'] as const;
export const DEFAULT_V7_EXTENSION_SETTINGS = {
  itemsEnabled: false,
  tavernEventsEnabled: false,
  characterAbilitiesEnabled: false,
} as const;
