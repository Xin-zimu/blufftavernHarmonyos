// 美术资源映射工具 - 对应 art.ts
// ArkTS 中 $r() 是编译时宏，不能使用动态字符串拼接
// 必须使用静态映射表，所有资源引用在编译时确定

// 角色头像资源映射 - idle 状态
// 注意：资源文件名为 character_*_idle_final，代码中引用 _idle 别名
export function getCharacterIdleImage(characterId: string): Resource {
  if (characterId === 'WOLF') return $r('app.media.character_wolf_idle_final')
  if (characterId === 'FOX') return $r('app.media.character_fox_idle_final')
  if (characterId === 'BEAR') return $r('app.media.character_bear_idle_final')
  if (characterId === 'RABBIT') return $r('app.media.character_rabbit_idle_final')
  if (characterId === 'CAT') return $r('app.media.character_cat_idle_final')
  if (characterId === 'RACCOON') return $r('app.media.character_raccoon_idle_final')
  if (characterId === 'FROG') return $r('app.media.character_frog_idle_final')
  if (characterId === 'PANDA') return $r('app.media.character_panda_idle_final')
  return $r('app.media.character_wolf_idle_final') // 默认
}

// 角色头像资源映射 - 通用 mood
export function getCharacterImage(characterId: string, mood: string): Resource {
  // idle 状态
  if (mood === 'idle') return getCharacterIdleImage(characterId)

  // suspicious
  if (mood === 'suspicious') {
    if (characterId === 'WOLF') return $r('app.media.character_wolf_suspicious')
    if (characterId === 'FOX') return $r('app.media.character_fox_suspicious')
    if (characterId === 'BEAR') return $r('app.media.character_bear_suspicious')
    if (characterId === 'RABBIT') return $r('app.media.character_rabbit_suspicious')
    if (characterId === 'CAT') return $r('app.media.character_cat_suspicious')
    if (characterId === 'RACCOON') return $r('app.media.character_raccoon_suspicious')
    if (characterId === 'FROG') return $r('app.media.character_frog_suspicious')
    if (characterId === 'PANDA') return $r('app.media.character_panda_suspicious')
  }

  // bluff
  if (mood === 'bluff') {
    if (characterId === 'WOLF') return $r('app.media.character_wolf_bluff')
    if (characterId === 'FOX') return $r('app.media.character_fox_bluff')
    if (characterId === 'BEAR') return $r('app.media.character_bear_bluff')
    if (characterId === 'RABBIT') return $r('app.media.character_rabbit_bluff')
    if (characterId === 'CAT') return $r('app.media.character_cat_bluff')
    if (characterId === 'RACCOON') return $r('app.media.character_raccoon_bluff')
    if (characterId === 'FROG') return $r('app.media.character_frog_bluff')
    if (characterId === 'PANDA') return $r('app.media.character_panda_bluff')
  }

  // shocked
  if (mood === 'shocked') {
    if (characterId === 'WOLF') return $r('app.media.character_wolf_shocked')
    if (characterId === 'FOX') return $r('app.media.character_fox_shocked')
    if (characterId === 'BEAR') return $r('app.media.character_bear_shocked')
    if (characterId === 'RABBIT') return $r('app.media.character_rabbit_shocked')
    if (characterId === 'CAT') return $r('app.media.character_cat_shocked')
    if (characterId === 'RACCOON') return $r('app.media.character_raccoon_shocked')
    if (characterId === 'FROG') return $r('app.media.character_frog_shocked')
    if (characterId === 'PANDA') return $r('app.media.character_panda_shocked')
  }

  // laugh
  if (mood === 'laugh') {
    if (characterId === 'WOLF') return $r('app.media.character_wolf_laugh')
    if (characterId === 'FOX') return $r('app.media.character_fox_laugh')
    if (characterId === 'BEAR') return $r('app.media.character_bear_laugh')
    if (characterId === 'RABBIT') return $r('app.media.character_rabbit_laugh')
    if (characterId === 'CAT') return $r('app.media.character_cat_laugh')
    if (characterId === 'RACCOON') return $r('app.media.character_raccoon_laugh')
    if (characterId === 'FROG') return $r('app.media.character_frog_laugh')
    if (characterId === 'PANDA') return $r('app.media.character_panda_laugh')
  }

  // nervous
  if (mood === 'nervous') {
    if (characterId === 'WOLF') return $r('app.media.character_wolf_nervous')
    if (characterId === 'FOX') return $r('app.media.character_fox_nervous')
    if (characterId === 'BEAR') return $r('app.media.character_bear_nervous')
    if (characterId === 'RABBIT') return $r('app.media.character_rabbit_nervous')
    if (characterId === 'CAT') return $r('app.media.character_cat_nervous')
    if (characterId === 'RACCOON') return $r('app.media.character_raccoon_nervous')
    if (characterId === 'FROG') return $r('app.media.character_frog_nervous')
    if (characterId === 'PANDA') return $r('app.media.character_panda_nervous')
  }

  // eliminated
  if (mood === 'eliminated') {
    if (characterId === 'WOLF') return $r('app.media.character_wolf_eliminated')
    if (characterId === 'FOX') return $r('app.media.character_fox_eliminated')
    if (characterId === 'BEAR') return $r('app.media.character_bear_eliminated')
    if (characterId === 'RABBIT') return $r('app.media.character_rabbit_eliminated')
    if (characterId === 'CAT') return $r('app.media.character_cat_eliminated')
    if (characterId === 'RACCOON') return $r('app.media.character_raccoon_eliminated')
    if (characterId === 'FROG') return $r('app.media.character_frog_eliminated')
    if (characterId === 'PANDA') return $r('app.media.character_panda_eliminated')
  }

  // victory
  if (mood === 'victory') {
    if (characterId === 'WOLF') return $r('app.media.character_wolf_victory')
    if (characterId === 'FOX') return $r('app.media.character_fox_victory')
    if (characterId === 'BEAR') return $r('app.media.character_bear_victory')
    if (characterId === 'RABBIT') return $r('app.media.character_rabbit_victory')
    if (characterId === 'CAT') return $r('app.media.character_cat_victory')
    if (characterId === 'RACCOON') return $r('app.media.character_raccoon_victory')
    if (characterId === 'FROG') return $r('app.media.character_frog_victory')
    if (characterId === 'PANDA') return $r('app.media.character_panda_victory')
  }

  // 默认返回 idle
  return getCharacterIdleImage(characterId)
}

// 卡牌资源映射
export function getCardImage(cardRank: string): Resource {
  if (cardRank === 'A') return $r('app.media.card_card_a_base')
  if (cardRank === 'K') return $r('app.media.card_card_k_base')
  if (cardRank === 'Q') return $r('app.media.card_card_q_base')
  if (cardRank === 'JOKER') return $r('app.media.card_joker')
  return $r('app.media.card_card_back')
}

// 卡牌背面
export function getCardBackImage(): Resource {
  return $r('app.media.card_card_back')
}

// 背景资源映射
export function getBackgroundImage(name: string): Resource {
  if (name === 'bg_01_tavern_v1') return $r('app.media.background_bg_01_tavern_v1')
  if (name === 'bg_lobby') return $r('app.media.background_bg_lobby')
  if (name === 'bg_victory') return $r('app.media.background_bg_victory')
  if (name === 'loading_screen') return $r('app.media.background_loading_screen')
  return $r('app.media.background_bg_lobby')
}

// 道具资源映射
export function getItemImage(itemId: string): Resource {
  if (itemId === 'SPYGLASS') return $r('app.media.item_spyglass')
  if (itemId === 'SWAP_GLOVE') return $r('app.media.item_swap_glove')
  if (itemId === 'WAX_SEAL') return $r('app.media.item_wax_seal')
  if (itemId === 'TAVERN_MUG') return $r('app.media.item_wooden_mug')
  if (itemId === 'POCKET_WATCH') return $r('app.media.item_pocket_watch')
  return $r('app.media.item_wooden_mug')
}
