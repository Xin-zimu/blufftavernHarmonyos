// 音效管理器 - 对应 game-audio-manager.ts + ui-sounds.ts
// 原项目用 Web Audio API 程序化合成音效，鸿蒙中使用 SoundPool 播放预生成音频文件
// 或使用系统振动反馈作为替代方案

import { media } from '@kit.MediaKit'
import { vibrator } from '@kit.SensorServiceKit'
import { common } from '@kit.AbilityKit'

export class AudioManager {
  private soundPool: media.SoundPool | null = null
  private soundIds: Map<string, number> = new Map()
  private isInitialized: boolean = false
  private enabled: boolean = true
  private context: common.UIAbilityContext | null = null

  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.isInitialized) return
    this.context = context

    try {
      this.soundPool = await media.createSoundPool(10, media.SoundPoolType.STREAM_MUSIC)
      this.isInitialized = true

      // 加载预生成的音效文件
      // 音效文件应放在 resources/base/rawfile/ 目录下
      await this.loadSounds()
    } catch (error) {
      console.error('AudioManager init failed: ' + JSON.stringify(error))
      this.isInitialized = false
    }
  }

  private async loadSounds(): Promise<void> {
    if (!this.soundPool || !this.context) return

    // 音效文件列表 - 对应原项目的程序化合成音效
    const soundFiles: Map<string, string> = new Map<string, string>([
      ['roundStart', 'round_start.mp3'],
      ['challenge', 'challenge.mp3'],
      ['reveal', 'reveal.mp3'],
      ['verdict', 'verdict.mp3'],
      ['revolverSpin', 'revolver_spin.mp3'],
      ['gunshot', 'gunshot.mp3'],
      ['emptyClick', 'empty_click.mp3'],
      ['victory', 'victory.mp3'],
      ['cardPlay', 'card_play.mp3'],
      ['buttonClick', 'button_click.mp3'],
    ])

    const rawFileDir = this.context.resourceDir + '/rawfile'

    for (const [name, file] of soundFiles) {
      try {
        const filePath = rawFileDir + '/' + file
        const soundId = await this.soundPool.load(filePath)
        this.soundIds.set(name, soundId)
      } catch (error) {
        // 音效文件可能尚未生成，忽略错误
        console.warn('Sound file ' + file + ' not found')
      }
    }
  }

  // ====== 游戏阶段音效 ======

  playRoundStart(): void {
    this.playSound('roundStart')
  }

  playChallenge(): void {
    this.playSound('challenge')
  }

  playReveal(): void {
    this.playSound('reveal')
  }

  playVerdict(): void {
    this.playSound('verdict')
  }

  playRevolverSpin(): void {
    this.playSound('revolverSpin')
  }

  playGunshot(): void {
    this.playSound('gunshot')
    // 中弹时触发振动反馈
    this.vibrate(100)
  }

  playEmptyClick(): void {
    this.playSound('emptyClick')
  }

  playVictory(): void {
    this.playSound('victory')
  }

  // ====== UI 交互音效 ======

  playCardPlay(): void {
    this.playSound('cardPlay')
  }

  playButtonClick(): void {
    this.playSound('buttonClick')
  }

  // ====== 内部方法 ======

  private playSound(name: string): void {
    if (!this.enabled || !this.soundPool) return

    const soundId = this.soundIds.get(name)
    if (soundId !== undefined) {
      this.soundPool.play(soundId)
    }
  }

  // 振动反馈
  private vibrate(duration: number): void {
    try {
      vibrator.startVibration({
        type: 'time',
        duration: duration
      }, {
        id: 0,
        usage: 'notification'
      })
    } catch (error) {
      // 振动不可用时忽略
    }
  }

  // 启用/禁用音效
  setEnabled(enabled: boolean): void {
    this.enabled = enabled
  }

  // 释放资源
  release(): void {
    if (this.soundPool) {
      this.soundPool.release()
      this.soundPool = null
    }
    this.isInitialized = false
    this.soundIds.clear()
  }
}
