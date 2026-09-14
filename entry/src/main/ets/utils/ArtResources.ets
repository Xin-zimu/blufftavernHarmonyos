// 美术资源映射工具 - 对应 art.ts
// 在鸿蒙中通过 $r('app.media.xxx') 引用资源

import { CharacterId, CharacterMood } from '../model/Constants'

// 角色资源映射
export function getCharacterImage(characterId: string, mood: string = 'idle'): Resource {
  // 鸿蒙资源命名规则：character_wolf_idle, character_fox_bluff 等
  // 资源文件放在 resources/base/media/ 目录下
  const resourceName = `character_${characterId.toLowerCase()}_${mood}`
  return $r(`app.media.${resourceName}`)
}

// 卡牌资源映射
export function getCardImage(cardRank: string): Resource {
  return $r(`app.media.card_${cardRank.toLowerCase()}`)
}

// 背景资源映射
export function getBackgroundImage(name: string): Resource {
  return $r(`app.media.background_${name}`)
}

// UI 元素资源映射
export function getUIElement(name: string): Resource {
  return $r(`app.media.ui_${name}`)
}

// 道具资源映射
export function getItemImage(itemId: string): Resource {
  return $r(`app.media.item_${itemId.toLowerCase()}`)
}

// 表情资源映射
export function getEmoteImage(emoteId: string): Resource {
  return $r(`app.media.emote_${emoteId.toLowerCase()}`)
}

// 演出资源映射
export function getCinematicImage(name: string): Resource {
  return $r(`app.media.cinematic_${name}`)
}
