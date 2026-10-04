// 音效管理器 - 对应 game-audio-manager.ts + ui-sounds.ts
// 按上游参数离线合成 PCM WAV，使用 HAP rawfile 描述符加载，不依赖磁盘资源路径。

import { media } from '@kit.MediaKit'
import { audio } from '@kit.AudioKit'
import { vibrator } from '@kit.SensorServiceKit'
import { common } from '@kit.AbilityKit'

export class AudioManager {
  private soundPool: media.SoundPool | null = null
  private soundIds: Map<string, number> = new Map()
  private isInitialized: boolean = false
  private enabled: boolean = true
  private context: common.UIAbilityContext | null = null
  private readyIds: Set<number> = new Set<number>()
  private loadedFiles: string[] = []
  private activeStreams: number[] = []
  private generation: number = 0

  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.isInitialized) return
    this.context = context
    const generation: number = ++this.generation

    try {
      const rendererInfo: audio.AudioRendererInfo = {
        usage: audio.StreamUsage.STREAM_USAGE_MUSIC,
        rendererFlags: 0
      }
      const pool: media.SoundPool = await media.createSoundPool(10, rendererInfo)
      if (generation !== this.generation) {
        await pool.release()
        return
      }
      this.soundPool = pool
      pool.on('loadComplete', (soundId: number) => {
        if (generation === this.generation) this.readyIds.add(soundId)
      })
      pool.on('error', () => console.warn('SoundPool playback/load error'))
      pool.on('playFinishedWithStreamId', (streamId: number) => {
        this.activeStreams = this.activeStreams.filter((id: number) => id !== streamId)
      })
      this.isInitialized = true

      // 加载预生成的音效文件
      // 音效文件应放在 resources/base/rawfile/ 目录下
      await this.loadSounds(generation)
    } catch (error) {
      console.error('AudioManager init failed: ' + JSON.stringify(error))
      this.isInitialized = false
    }
  }

  private async loadSounds(generation: number): Promise<void> {
    if (!this.soundPool || !this.context) return
    const pool: media.SoundPool = this.soundPool
    const context: common.UIAbilityContext = this.context

    // 音效文件列表 - 对应原项目的程序化合成音效
    const soundFiles: Map<string, string> = new Map<string, string>([
      ['roundStart', 'round_start.wav'],
      ['challenge', 'challenge.wav'],
      ['reveal', 'reveal.wav'],
      ['verdict', 'verdict.wav'],
      ['verdictBluff', 'verdict_bluff.wav'],
      ['revolverSpin', 'revolver_spin.wav'],
      ['triggerClick', 'trigger_click.wav'],
      ['gunshot', 'gunshot.wav'],
      ['emptyClick', 'empty_click.wav'],
      ['victory', 'victory.wav'],
      ['cardPlay', 'card_play.wav'],
      ['buttonClick', 'button_click.wav'],
    ])

    for (const name of soundFiles.keys()) {
      if (generation !== this.generation) return
      const file: string | undefined = soundFiles.get(name)
      if (file === undefined) {
        continue
      }
      try {
        const descriptor = await context.resourceManager.getRawFd(file)
        if (generation !== this.generation) {
          await context.resourceManager.closeRawFd(file)
          return
        }
        // 解码是异步的，描述符保持有效直到 pool 释放。
        this.loadedFiles.push(file)
        const soundId = await pool.load(descriptor.fd, descriptor.offset, descriptor.length)
        if (generation === this.generation) this.soundIds.set(name, soundId)
      } catch (error) {
        console.warn('Unable to load sound: ' + file)
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

  playVerdict(wasBluff: boolean = false): void {
    this.playSound(wasBluff ? 'verdictBluff' : 'verdict')
  }

  playRevolverSpin(): void {
    this.playSound('revolverSpin')
  }

  playTriggerClick(): void {
    this.playSound('triggerClick')
  }

  playGunshot(): void {
    if (!this.enabled) return
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
    if (soundId !== undefined && this.readyIds.has(soundId)) {
      const pool: media.SoundPool = this.soundPool
      pool.play(soundId).then((streamId: number) => {
        if (!this.enabled || this.soundPool !== pool) {
          pool.stop(streamId).catch(() => {})
        } else {
          this.activeStreams.push(streamId)
        }
      }).catch(() => console.warn('Unable to play sound: ' + name))
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
    if (!enabled && this.soundPool !== null) {
      for (const streamId of this.activeStreams) this.soundPool.stop(streamId).catch(() => {})
      this.activeStreams = []
    }
  }

  isEnabled(): boolean {
    return this.enabled
  }

  // 释放资源
  async release(): Promise<void> {
    this.generation++
    const pool: media.SoundPool | null = this.soundPool
    this.soundPool = null
    this.isInitialized = false
    this.soundIds.clear()
    this.readyIds.clear()
    this.activeStreams = []
    if (pool !== null) await pool.release().catch(() => {})
    const files: string[] = this.loadedFiles
    this.loadedFiles = []
    if (this.context !== null) {
      for (const file of files) await this.context.resourceManager.closeRawFd(file).catch(() => {})
    }
  }
}
