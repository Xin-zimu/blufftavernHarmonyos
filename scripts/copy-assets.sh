#!/bin/bash
# 将原项目的美术资源复制到鸿蒙项目的 resources/base/media/ 目录
# 并按照鸿蒙资源命名规则重命名

SOURCE_DIR="/workspace/bluff-tavern/assets"
TARGET_DIR="/workspace/bluff-tavern-harmony/entry/src/main/resources/base/media"

mkdir -p "$TARGET_DIR"

# ====== 角色资源 ======
# 原路径: assets/characters/wolf/idle.png
# 鸿蒙路径: resources/base/media/character_wolf_idle.png
for char_dir in "$SOURCE_DIR"/characters/*/; do
  char_name=$(basename "$char_dir")
  for mood_file in "$char_dir"*.png; do
    if [ -f "$mood_file" ]; then
      mood=$(basename "$mood_file" .png)
      cp "$mood_file" "$TARGET_DIR/character_${char_name}_${mood}.png"
    fi
  done
done

# ====== 卡牌资源 ======
for card_file in "$SOURCE_DIR"/cards/*.png; do
  if [ -f "$card_file" ]; then
    card_name=$(basename "$card_file" .png)
    cp "$card_file" "$TARGET_DIR/card_${card_name}.png"
  fi
done

# ====== 背景资源 ======
for bg_file in "$SOURCE_DIR"/backgrounds/*.png; do
  if [ -f "$bg_file" ]; then
    bg_name=$(basename "$bg_file" .png)
    cp "$bg_file" "$TARGET_DIR/background_${bg_name}.png"
  fi
done

# ====== UI 元素 ======
for ui_file in "$SOURCE_DIR"/ui/*.png; do
  if [ -f "$ui_file" ]; then
    ui_name=$(basename "$ui_file" .png)
    cp "$ui_file" "$TARGET_DIR/ui_${ui_name}.png"
  fi
done

# ====== 道具图标 ======
for item_file in "$SOURCE_DIR"/items/*.png; do
  if [ -f "$item_file" ]; then
    item_name=$(basename "$item_file" .png)
    cp "$item_file" "$TARGET_DIR/item_${item_name}.png"
  done
done

# ====== 表情图标 ======
for emote_file in "$SOURCE_DIR"/emotes/*.png; do
  if [ -f "$emote_file" ]; then
    emote_name=$(basename "$emote_file" .png)
    cp "$emote_file" "$TARGET_DIR/emote_${emote_name}.png"
  done
done

# ====== 演出资源 (左轮手枪等) ======
if [ -d "$SOURCE_DIR/cinematics" ]; then
  for cinematic_file in "$SOURCE_DIR"/cinematics/*.png; do
    if [ -f "$cinematic_file" ]; then
      cinematic_name=$(basename "$cinematic_file" .png)
      cp "$cinematic_file" "$TARGET_DIR/cinematic_${cinematic_name}.png"
    fi
  done
fi

# ====== 特效资源 ======
for effect_file in "$SOURCE_DIR"/effects/*.png; do
  if [ -f "$effect_file" ]; then
    effect_name=$(basename "$effect_file" .png)
    cp "$effect_file" "$TARGET_DIR/effect_${effect_name}.png"
  done
done

# ====== 应用图标 ======
if [ -f "$SOURCE_DIR/icons/app_icon.png" ]; then
  cp "$SOURCE_DIR/icons/app_icon.png" "$TARGET_DIR/app_icon.png"
fi

echo "Asset copy complete. Files in target directory:"
ls "$TARGET_DIR" | wc -l
echo "files copied."
