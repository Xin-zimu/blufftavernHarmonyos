// 常量定义 - 对应 shared/constants/index.ts
// ArkTS 严格类型版本

import { CharacterId, ItemId, EmoteId, CharacterMood } from './GameTypes'

export const ROOM_CODE_LENGTH: number = 6
export const APP_VERSION: string = '6.7.0'
export const ROOM_CODE_ALPHABET: string = '23456789ABCDEFGHJKMNPQRSTUVWXYZ'
export const MIN_NICKNAME_LENGTH: number = 1
export const MAX_NICKNAME_LENGTH: number = 16
export const MAX_PLAYERS: number = 8
export const MIN_PLAYERS: number = 2
export const MAX_CARDS_PER_PLAY: number = 3

// 按人数的牌量配置
export class CardsPerRankConfig {
  maxPlayers: number = 0
  copiesPerRank: number = 0
  jokers: number = 0
}

export function makeCardsPerRankConfig(max: number, copies: number, jokers: number): CardsPerRankConfig {
  const c = new CardsPerRankConfig()
  c.maxPlayers = max
  c.copiesPerRank = copies
  c.jokers = jokers
  return c
}

export const CARDS_PER_RANK_BY_PLAYER_COUNT: CardsPerRankConfig[] = [
  makeCardsPerRankConfig(4, 6, 2),
  makeCardsPerRankConfig(6, 9, 3),
  makeCardsPerRankConfig(8, 12, 4),
]

// 按人数的子弹配置
export class RevolverBulletsConfig {
  maxPlayers: number = 0
  bullets: number = 0
}

export function makeRevolverBulletsConfig(max: number, bullets: number): RevolverBulletsConfig {
  const c = new RevolverBulletsConfig()
  c.maxPlayers = max
  c.bullets = bullets
  return c
}

export const REVOLVER_BULLETS_BY_PLAYER_COUNT: RevolverBulletsConfig[] = [
  makeRevolverBulletsConfig(4, 1),
  makeRevolverBulletsConfig(6, 2),
  makeRevolverBulletsConfig(8, 2),
]

// 角色ID列表
export const CHARACTER_IDS: CharacterId[] = ['WOLF', 'FOX', 'BEAR', 'RABBIT', 'CAT', 'RACCOON', 'FROG', 'PANDA']

// 道具ID列表
export const ITEM_IDS: ItemId[] = ['SPYGLASS', 'SWAP_GLOVE', 'WAX_SEAL', 'TAVERN_MUG', 'POCKET_WATCH']

// 表情ID列表
export const EMOTE_IDS: EmoteId[] = ['CHEER', 'SUSPECT', 'BLUFF', 'LAUGH', 'GASP', 'NERVOUS', 'TOAST', 'GOOD_GAME']

// 演出时间控制 (毫秒) - 对应服务端 cinematicTiming
export class CinematicTiming {
  ROUND_START: number = 2700
  CHALLENGE_CALLOUT: number = 1800
  VERDICT: number = 1300
  PUNISHMENT_INTRO: number = 1050
  PUNISHMENT_TRIGGER: number = 700
  ROUND_END: number = 900
  REVEAL_INTRO: number = 500
  REVEAL_PER_CARD: number = 750
  REVEAL_FINAL_HOLD: number = 1000
}

export const CINEMATIC_TIMING: CinematicTiming = new CinematicTiming()

// 角色中文名映射 - 使用 Map 代替 Record
export const CHARACTER_NAMES: Map<string, string> = new Map<string, string>([
  ['WOLF', '灰狼'],
  ['FOX', '赤狐'],
  ['BEAR', '棕熊'],
  ['RABBIT', '白兔'],
  ['CAT', '黑猫'],
  ['RACCOON', '浣熊'],
  ['FROG', '青蛙'],
  ['PANDA', '熊猫'],
])

// 道具中文名映射
export const ITEM_NAMES: Map<string, string> = new Map<string, string>([
  ['SPYGLASS', '窥牌镜'],
  ['SWAP_GLOVE', '换牌手套'],
  ['WAX_SEAL', '封口蜡印'],
  ['TAVERN_MUG', '酒馆木杯'],
  ['POCKET_WATCH', '旧怀表'],
])
