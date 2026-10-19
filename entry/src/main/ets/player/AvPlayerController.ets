/**
 * AVPlayer 封装 —— 对应 LibreTV Web 版的 ArtPlayer 播放内核
 *
 * 关键能力：
 * - 网络直链播放（createMediaSourceWithUrl 携带 UA / Referer / Cookie 防盗链头）
 * - 本地重写后的 m3u8 经 fd:// 播放（广告过滤，见 M3u8Rewriter）
 * - 倍速、seek、进度回调、缓冲回调、播完回调（自动连播）
 * - 续播定位：PREPARED 后执行挂起的 seek
 */

import { media } from '@kit.MediaKit';
import { BusinessError } from '@kit.BasicServicesKit';

export interface PlaybackSpeedOption {
  label: string;
  value: number;
}

export class AvPlayerController {
  private player: media.AVPlayer | null = null;
  private surfaceId: string = '';
  /** 准备完成后要跳转到的位置（续播） */
  private pendingSeekMs: number = 0;
  private prepared: boolean = false;
  private wantPlay: boolean = false;
  private lastDurationMs: number = 0;
  /**
   * 播放音量（0~1）。
   * AVPlayer 的 setVolume 只能在 prepared 之后的态调用（idle/initialized 下会抛错），
   * 所以自己存一份：滑屏调音量时若还没起播，先记住，prepared 时再补上。
   */
  private volume: number = 1.0;

  /** UI 回调（由页面赋值） */
  onPrepared: (durationMs: number) => void = () => {};
  onProgress: (positionMs: number, durationMs: number) => void = () => {};
  onPlayStateChanged: (playing: boolean) => void = () => {};
  onCompleted: () => void = () => {};
  onError: (message: string) => void = () => {};
  onBuffering: (percent: number) => void = () => {};
  /** 视频真实分辨率（宽, 高），用于按原始比例显示，避免画面被拉伸 */
  onVideoSize: (width: number, height: number) => void = () => {};

  /** 倍速档位（与 LibreTV 播放器一致） */
  static readonly SPEEDS: PlaybackSpeedOption[] = [
    { label: '0.5x', value: 0.5 },
    { label: '0.75x', value: 0.75 },
    { label: '1.0x', value: 1.0 },
    { label: '1.25x', value: 1.25 },
    { label: '1.5x', value: 1.5 },
    { label: '2.0x', value: 2.0 }
  ];

  static speedToEnum(speed: number): media.PlaybackSpeed {
    switch (speed) {
      case 0.5:
        return media.PlaybackSpeed.SPEED_FORWARD_0_50_X;
      case 0.75:
        return media.PlaybackSpeed.SPEED_FORWARD_0_75_X;
      case 1.25:
        return media.PlaybackSpeed.SPEED_FORWARD_1_25_X;
      case 1.5:
        return media.PlaybackSpeed.SPEED_FORWARD_1_50_X;
      case 2.0:
        return media.PlaybackSpeed.SPEED_FORWARD_2_00_X;
      default:
        return media.PlaybackSpeed.SPEED_FORWARD_1_00_X;
    }
  }

  /** 把 AVPlayer 的错误码翻译成普通用户能看懂的中文（避免直出英文技术串） */
  static friendlyError(code: number): string {
    if (code === 5400103) {
      // IO 错误：网络超时 / m3u8 拉取失败等
      return '视频数据获取失败，请检查网络后重试';
    }
    if (code === 5400105 || code === 5400106) {
      return '视频格式不支持或源已失效，请换一个视频源';
    }
    if (code === 5400107) {
      return '音频设备异常，请重试';
    }
    return '该视频暂时无法播放，请重试或更换视频源';
  }

  /** 创建播放器并记录 Surface（真正的 surfaceId 绑定要等到 initialized 状态） */
  async create(surfaceId: string): Promise<boolean> {
    if (surfaceId === '') {
      this.onError('视频画面初始化失败');
      return false;
    }
    try {
      this.releasePlayer();
      this.surfaceId = surfaceId;
      this.prepared = false;
      this.pendingSeekMs = 0;
      this.lastDurationMs = 0;
      const player: media.AVPlayer = await media.createAVPlayer();
      this.player = player;
      // 事件必须先注册：后续任何状态变化都要能被收到
      this.registerEvents(player);
      // 注意：此处不能设 surfaceId —— AVPlayer 处于 idle 态时系统会报
      // 5400102「SurfaceID can only be set in the initialized state」，
      // 且后续 prepare() 会与异步 SetSurface 抢状态，导致播放器卡死无画面。
      return true;
    } catch (e) {
      const err = e as BusinessError;
      this.onError('播放器初始化失败，请重试');
      return false;
    }
  }

  /** 在合法的状态里绑定 Surface */
  private bindSurface(player: media.AVPlayer): void {
    if (this.surfaceId === '') {
      return;
    }
    try {
      const st: string = player.state;
      if (st === 'initialized' || st === 'prepared') {
        player.surfaceId = this.surfaceId;
      }
    } catch (e) {
      // 状态尚未就绪时忽略，后续 initialized 回调会再试
    }
  }

  /** 轮询等待播放器进入指定状态 */
  private async waitForState(player: media.AVPlayer, target: string, timeoutMs: number): Promise<boolean> {
    const start: number = Date.now();
    while (Date.now() - start < timeoutMs) {
      let st: string = '';
      try {
        st = player.state;
      } catch (e) {
        return false;
      }
      if (st === target) {
        return true;
      }
      if (st === 'error') {
        return false;
      }
      await new Promise<void>((resolve: (value: void) => void) => {
        setTimeout(() => {
          resolve();
        }, 30);
      });
    }
    return false;
  }

  /** 设置媒体源 → 等 initialized → 绑 Surface → prepare（顺序错会导致卡死无画面） */
  private async startSource(player: media.AVPlayer, source: media.MediaSource, seekMs: number): Promise<boolean> {
    await this.ensureIdle(player);
    if (player.state !== 'idle') {
      // reset 没有按时回到 idle（兜底超时走完）：强行 setMediaSource 会被拒绝，
      // 与其静默卡住加载圈，不如明确报错让用户重试。
      this.onError('播放器状态异常，请重试');
      return false;
    }
    this.prepared = false;
    this.wantPlay = true;
    this.pendingSeekMs = seekMs > 0 ? seekMs : 0;
    const strategy: media.PlaybackStrategy = { preferredBufferDuration: 20 };
    player.setMediaSource(source, strategy);
    const ready: boolean = await this.waitForState(player, 'initialized', 8000);
    if (!ready) {
      this.onError('视频源初始化超时，请重试或换源');
      return false;
    }
    this.bindSurface(player);
    player.prepare();
    return true;
  }

  private eventsBound: boolean = false;

  private registerEvents(player: media.AVPlayer): void {
    if (this.eventsBound && this.player === player) {
      return;
    }
    this.eventsBound = true;
    player.on('stateChange', (state: media.AVPlayerState) => {
      switch (state) {
        case 'initialized':
          // reset / 换源后会重新回到 initialized，此时补绑 Surface
          this.bindSurface(player);
          break;
        case 'prepared':
          this.prepared = true;
          this.lastDurationMs = player.duration > 0 ? player.duration : 0;
          this.bindSurface(player);
          try {
            // 起播时补上页面里调过的音量（换源/重连后也不会被冲回 1.0）
            player.setVolume(this.volume);
          } catch (e) {
            // ignore
          }
          this.onPrepared(this.lastDurationMs);
          if (this.pendingSeekMs > 0) {
            const target = this.pendingSeekMs;
            this.pendingSeekMs = 0;
            try {
              player.seek(target, media.SeekMode.SEEK_PREV_SYNC);
            } catch (e) {
              // seek 失败不阻塞播放
            }
          }
          if (this.wantPlay) {
            this.play();
          }
          break;
        case 'playing':
          this.onPlayStateChanged(true);
          break;
        case 'paused':
          this.onPlayStateChanged(false);
          break;
        case 'completed':
          this.onPlayStateChanged(false);
          this.onCompleted();
          break;
        case 'error':
        case 'idle':
          break;
        default:
          break;
      }
    });
    player.on('error', (err: BusinessError) => {
      this.onError(AvPlayerController.friendlyError(err.code));
    });
    player.on('durationUpdate', (duration: number) => {
      if (duration > 0) {
        this.lastDurationMs = duration;
        this.onPrepared(duration);
      }
    });
    player.on('timeUpdate', (time: number) => {
      this.onProgress(time, this.lastDurationMs);
    });
    player.on('videoSizeChange', (width: number, height: number) => {
      if (width > 0 && height > 0) {
        this.onVideoSize(width, height);
      }
    });
    player.on('bufferingUpdate', (infoType: media.BufferingInfoType, value: number) => {
      if (infoType === media.BufferingInfoType.BUFFERING_PERCENT) {
        this.onBuffering(value);
      }
    });
  }

  /**
   * 媒体源只允许在 idle 状态设置。
   * 换集 / 换源 / 重试前当前可能处于 completed/playing 等状态，需先 reset 并等待回到 idle。
   */
  private async ensureIdle(player: media.AVPlayer): Promise<void> {
    // 轮询等 idle，**不注册临时 stateChange 监听**：
    // off(临时回调) 会连带卸掉主回调，而 registerEvents 的防重复守卫
    // 又会跳过重新挂载 —— 换源后 prepared/playing 事件从此收不到，
    // play() 永远不会被调用，表现就是加载圈一直转（换源卡死 bug 根因）。
    // 换源后紧接着换集时，AVPlayer 可能还在 prepare/缓冲过渡，一次 reset
    // 未必立刻回到 idle —— 给最多 3 次机会，避免偶发「播放器状态异常」弹窗。
    for (let attempt = 0; attempt < 3; attempt++) {
      let st = '';
      try {
        st = player.state;
      } catch (e) {
        return;
      }
      if (st === 'idle') {
        return;
      }
      if (st === 'error' || st === 'released') {
        return;
      }
      try {
        player.reset();
      } catch (e) {
        return;
      }
      const ok = await this.waitForState(player, 'idle', 1200);
      if (ok) {
        return;
      }
    }
  }

  /** 播放网络直链（mp4 / m3u8 / flv 等） */
  async playUrl(url: string, headers: Record<string, string>, seekMs: number = 0): Promise<boolean> {
    const player = this.player;
    if (player === null) {
      this.onError('播放器未初始化');
      return false;
    }
    try {
      const source: media.MediaSource = media.createMediaSourceWithUrl(url, headers);
      return await this.startSource(player, source, seekMs);
    } catch (e) {
      const err = e as BusinessError;
      this.onError(AvPlayerController.friendlyError(err.code));
      return false;
    }
  }

  /**
   * 播放本地重写后的 m3u8（fd://）。
   * headers 用于列表内 .ts 分片的防盗链请求。
   */
  async playFd(fdUrl: string, headers: Record<string, string>, seekMs: number = 0): Promise<boolean> {
    const player = this.player;
    if (player === null) {
      this.onError('播放器未初始化');
      return false;
    }
    try {
      const source: media.MediaSource = media.createMediaSourceWithUrl(fdUrl, headers);
      source.setMimeType(media.AVMimeTypes.APPLICATION_M3U8);
      return await this.startSource(player, source, seekMs);
    } catch (e) {
      const err = e as BusinessError;
      this.onError(AvPlayerController.friendlyError(err.code));
      return false;
    }
  }

  /**
   * 播放本地整文件（下载合并出来的 video.ts）。
   *
   * 注意：这里**不能** setMimeType。SDK 的 AVMimeTypes 只有一个取值
   * APPLICATION_M3U8，设上去播放器就按 HLS 解析，直接报
   * 「Invalid M3U8 file」。不设 mime 时它按内容自己嗅探 MPEG-TS。
   */
  async playLocalFile(fdUrl: string, seekMs: number = 0): Promise<boolean> {
    const player = this.player;
    if (player === null) {
      this.onError('播放器未初始化');
      return false;
    }
    try {
      const source: media.MediaSource = media.createMediaSourceWithUrl(fdUrl, {});
      return await this.startSource(player, source, seekMs);
    } catch (e) {
      const err = e as BusinessError;
      this.onError(AvPlayerController.friendlyError(err.code));
      return false;
    }
  }

  play(): void {
    const player = this.player;
    if (player === null) {
      return;
    }
    this.wantPlay = true;
    try {
      player.play();
    } catch (e) {
      // 状态不允许时忽略
    }
  }

  pause(): void {
    const player = this.player;
    if (player === null) {
      return;
    }
    this.wantPlay = false;
    try {
      player.pause();
    } catch (e) {
      // ignore
    }
  }

  toggle(): void {
    const player = this.player;
    if (player === null) {
      return;
    }
    // currentTime 推进说明仍在播放
    if (this.isPlaying()) {
      this.pause();
    } else {
      this.play();
    }
  }

  isPlaying(): boolean {
    const player = this.player;
    if (player === null) {
      return false;
    }
    return player.state === 'playing';
  }

  /** 当前进度（ms） */
  currentTime(): number {
    const player = this.player;
    if (player === null) {
      return 0;
    }
    try {
      return player.currentTime > 0 ? player.currentTime : 0;
    } catch (e) {
      return 0;
    }
  }

  /** 总时长（ms）；直播返回 0 */
  duration(): number {
    return this.lastDurationMs;
  }

  seekTo(ms: number): void {
    const player = this.player;
    if (player === null || !this.prepared) {
      this.pendingSeekMs = ms;
      return;
    }
    try {
      player.seek(ms, media.SeekMode.SEEK_PREV_SYNC);
    } catch (e) {
      // ignore
    }
  }

  setSpeed(speed: number): void {
    const player = this.player;
    if (player === null) {
      return;
    }
    try {
      player.setSpeed(AvPlayerController.speedToEnum(speed));
    } catch (e) {
      // ignore
    }
  }

  /**
   * 设置播放音量（0~1）。
   * 只改当前播放器的音量，不动系统音量 —— 既不需要权限，也不会把用户在
   * 控制中心里设的铃声音量一起改掉。
   */
  setVolume(v: number): void {
    const value: number = v < 0 ? 0 : (v > 1 ? 1 : v);
    this.volume = value;
    const player = this.player;
    if (player === null || !this.prepared) {
      return;
    }
    try {
      player.setVolume(value);
    } catch (e) {
      // 非 prepared/playing 等态调用会抛错，忽略即可
    }
  }

  /** 当前播放音量（0~1） */
  getVolume(): number {
    return this.volume;
  }

  /** 释放播放器（页面销毁时调用） */
  release(): void {
    const player = this.player;
    this.player = null;
    this.prepared = false;
    this.wantPlay = false;
    this.eventsBound = false;
    if (player === null) {
      return;
    }
    try {
      player.stop();
    } catch (e) {
      // ignore
    }
    try {
      player.release();
    } catch (e) {
      // ignore
    }
  }

  private releasePlayer(): void {
    const old = this.player;
    this.player = null;
    this.prepared = false;
    this.eventsBound = false;
    if (old === null) {
      return;
    }
    try {
      old.stop();
    } catch (e) {
      // ignore
    }
    try {
      old.release();
    } catch (e) {
      // ignore
    }
  }
}
