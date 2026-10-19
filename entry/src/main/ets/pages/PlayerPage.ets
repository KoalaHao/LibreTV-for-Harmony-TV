/**
 * 播放页：全屏播放（点播 / 离线缓存）、进度续播、倍速、选集、换源、自动连播
 */

import { fileIo as fs } from '@kit.CoreFileKit';
import { window } from '@kit.ArkUI';
import { AvPlayerController, PlaybackSpeedOption } from '../player/AvPlayerController';
import { DevicePolicy } from '../common/DevicePolicy';
import { audio, AVVolumePanel } from '@kit.AudioKit';
import { AVCastPicker, AVCastPickerStyle, AVCastPickerColorMode, avSession } from '@kit.AVSessionKit';
import { ScreenKeeper } from '../common/ScreenKeeper';
import { PlayUrlResolver } from '../player/PlayUrlResolver';
import { VideoSurface } from '../player/VideoSurface';
import { CmsClient } from '../model/CmsClient';
import { DetailCache } from '../model/DetailCache';
import { SearchService } from '../model/SearchService';
import { SourceManager } from '../data/SourceManager';
import { HistoryStore } from '../data/HistoryStore';
import { SettingsStore } from '../data/SettingsStore';
import { DownloadManager } from '../data/DownloadManager';
import { Episode, SpeedTestItem, Settings, VideoDetail, PlayRecord } from '../model/Types';
import { Utils } from '../common/Utils';
import { LocalHttpServer } from '../common/LocalHttpServer';

export interface PlayerPageParam {
  sourceKey: string;
  vodId: string;
  episode: number;
  episodeName: string;
  title: string;
  positionMs: number;
  /** 离线播放时传入下载目录；在线播放为空串 */
  offlineDir: string;
  /** 调用方已知的当前集播放地址；为空则由播放页自行加载分集 */
  episodeUrl?: string;
  /** 调用方已知的海报地址；用于给首页「继续观看」补封面 */
  pic?: string;
  /** 播放线路下标；详情页选了非默认线路时传入 */
  lineIndex?: number;
}

@Component
export struct PlayerPage {
  navPathStack: NavPathStack = new NavPathStack();
  sourceKey: string = '';
  vodId: string = '';
  episode: number = 0;
  episodeName: string = '';
  title: string = '';
  positionMs: number = 0;
  offlineDir: string = '';
  /** 调用方已知的当前集播放地址；优先使用，避免再次请求详情被源站限流 */
  episodeUrl: string = '';
  /** 调用方已知的海报地址；用于给「继续观看」补封面 */
  pic: string = '';
  /** 播放线路下标：优先取该线路的分集 */
  lineIndex: number = 0;

  private player: AvPlayerController = new AvPlayerController();
  private holderFile: fs.File | null = null;
  private cacheDir: string = '';
  private surfaceId: string = '';
  private lastSaveAt: number = 0;
  private hideTimer: number = -1;
  /** 加载圈延迟计时器：只有真的卡住才提示，避免正常播放时红圈乱闪 */
  private loadingTimer: number = -1;
  private settings: Settings = SettingsStore.shared().get();
  private starting: boolean = false;
  private released: boolean = false;
  /** 分集加载任务：startPlay 必须等它完成，否则 episodes 还是空数组 */
  private loadTask: Promise<void> | null = null;
  /** 倍速是否已应用：只能在真正进入 playing 后再调 setSpeed，提前调会报 5400102 */
  private speedApplied: boolean = false;
  /** startPlay 全流程进行中（含等待分集），避免重复触发 */
  private playPending: boolean = false;
  /** 起播进行中又收到换集/换源请求：本轮完成后自动重起一次 */
  private restartQueued: boolean = false;

  @State episodes: Episode[] = [];
  @State currentEp: number = 0;
  @State playing: boolean = false;
  @State buffering: boolean = false;
  @State errorText: string = '';
  @State durationMs: number = 0;
  @State positionText: string = '00:00';
  @State durationText: string = '00:00';
  @State sliderValue: number = 0;
  @State sliderMax: number = 100;
  @State controlsVisible: boolean = true;
  @State showEpisodes: boolean = false;
  @State showSpeeds: boolean = false;
  @State showSources: boolean = false;
  @State speedItems: SpeedTestItem[] = [];
  @State speedTesting: boolean = false;
  @State speedValue: number = 1.0;
  @State landscape: boolean = false;
  /** 视频真实分辨率（由 AVPlayer 的 videoSizeChange 上报） */
  @State videoW: number = 0;
  @State videoH: number = 0;
  /** 播放器可视区域（vp），由根容器 onAreaChange 实测得到 */
  @State canvasW: number = 0;
  @State canvasH: number = 0;
  /** 按原始比例算出的画面尺寸（vp）；居中显示，永不拉伸 */
  @State displayW: number = 0;
  @State displayH: number = 0;
  /** 画面铺满（裁切黑边）模式：车机/大屏上最大化利用屏幕，比例不变、仅裁掉超出部分 */
  @State fitCover: boolean = false;
  /** 系统媒体音量档位（由 AVVolumePanel 写入设备音量，不是播放器内部音量） */
  @State volumeLevel: number = 0;
  private volumeMaxLevel: number = 15;
  /** 投屏用的媒体会话：系统投屏列表只认有 AVSession 的应用 */
  private castSession: avSession.AVSession | null = null;
  /** 是否已经真正起播过（用于区分「首次加载」和「播放中抖动」） */
  @State hasStarted: boolean = false;
  /** 真正控制加载圈显隐，和 buffering 解耦，防止闪一下就没 */
  @State showLoading: boolean = false;
  /** 起播后真卡顿（进度停摆）时屏幕中央的加载圈 */
  @State stallLoading: boolean = false;
  private lastPosMs: number = 0;
  private lastPosAt: number = 0;
  private stallTimer: number = -1;
  /** 滑屏调节：'' 未激活 / 'volume' 音量 / 'brightness' 亮度 */
  @State adjustKind: string = '';
  /** 滑屏调节的当前值（0~1），浮层据此画进度条与百分比 */
  @State adjustValue: number = 0;
  /** 本次滑动开始时的基准值：整段手势都以它为原点，避免逐帧累积漂移 */
  private adjustBase: number = 0;
  /** 主窗口句柄：调亮度要用，提前取好，别在滑动过程里反复 getLastWindow */
  private win: window.Window | null = null;
  /** 浮层延迟消失的定时器 */
  private adjustTimer: number = -1;

  // ---------- 自动换源（加载超时 / 反复卡顿）----------
  /** 起播看门狗：起播后 12 秒仍没进入 playing，判定这一路加载失败 */
  private loadWatchdog: number = -1;
  /** 本次起播累计的真卡顿次数，达到阈值自动换源 */
  private stallCount: number = 0;
  /** 自动换源流程进行中：防止看门狗与卡顿判定同时触发导致连切 */
  private autoSwitching: boolean = false;
  /** 已经自动试过的源：避免在几个坏源之间来回跳 */
  private autoTried: string[] = [];
  /** 起播超时阈值（毫秒）。8 秒太激进：弱网下起播常要 10 秒左右，
   *  看门狗先触发、测速期间画面又起来了，就出现「刚播起来又跳走」 */
  private static readonly LOAD_TIMEOUT_MS: number = 12000;
  /** 最近一次「进度真正前进」的时间：判断播放是否已经恢复，比 playing 可靠
   *  （卡顿时 playing 仍是 true，只有进度停了） */
  private lastProgressAt: number = 0;
  /** 最近一次真卡顿的时间：用于「平稳播放 60 秒后把卡顿账清零」 */
  private lastStallAt: number = 0;
  /** 同一集卡顿多少次后自动换源 */
  private static readonly STALL_LIMIT: number = 3;
  /** 一次播放最多自动换几次源，超了就交回给用户 */
  private static readonly AUTO_SWITCH_MAX: number = 3;

  aboutToAppear(): void {
    // 播放页存活期间保持屏幕常亮：平板全屏播放时系统休眠计时一到会直接黑屏锁屏
    ScreenKeeper.acquirePlayback();
    this.syncSystemVolume();
    this.initCastSession();
    const hostCtx = this.getUIContext().getHostContext();
    if (hostCtx !== undefined) {
      this.cacheDir = hostCtx.filesDir + '/play';
    }
    this.currentEp = this.episode;
    this.speedValue = this.settings.defaultSpeed;
    this.positionText = Utils.formatTime(this.positionMs);
    this.bindCallbacks();
    if (hostCtx !== undefined) {
      window.getLastWindow(hostCtx).then((win: window.Window) => {
        this.win = win;
      }).catch(() => {
        // ignore
      });
    }
    if (this.offlineDir === '') {
      this.loadTask = this.loadEpisodes();
    }
  }

  aboutToDisappear(): void {
    ScreenKeeper.releasePlayback();
    this.releaseCastSession();
    this.clearStall();
    this.clearWatchdog();
    this.saveProgress();
    // 不管从哪个入口离开（返回键 / 系统返回手势 / 自动连播结束），都要把屏幕方向
    // 交还系统（不是锁竖屏！）、并把窗口布局全屏复原，否则主界面会转不动 / 被裁掉底部。
    this.restoreRotation();
    this.applyWindowFullScreen(false);
    // 窗口亮度是「霸占式」的：不还原的话，控制中心里调系统亮度会一直失效
    this.restoreBrightness();
    this.clearAdjustTimer();
    this.release();
    // 离线播放用的本地服务只在这一页需要，离开就关掉，别一直占着端口
    if (this.offlineDir !== '') {
      LocalHttpServer.shared().stop();
    }
  }

  private toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 });
  }

  private bindCallbacks(): void {
    this.player.onPrepared = (durationMs: number) => {
      this.durationMs = durationMs;
      this.durationText = Utils.formatTime(durationMs);
      this.sliderMax = durationMs > 0 ? Math.floor(durationMs / 1000) : 100;
      // 不要在这里 setSpeed：prepared 瞬间原生侧可能还没就绪，
      // 会异步抛 5400102「unsupport speed operation」，try/catch 拦不住，直接弹错误界面。
      // 真正的应用时机放到第一次 playing（见 onPlayStateChanged）。
      this.speedApplied = false;
    };
    this.player.onProgress = (positionMs: number, durationMs: number) => {
      // 进度在推进 = 没有卡顿：取消预约的检查并收掉加载圈
      if (positionMs > this.lastPosMs) {
        this.lastPosMs = positionMs;
        this.lastProgressAt = Date.now();
        // 距上次卡顿已平稳播放 60 秒：旧账清零。
        // 否则一小时里零散卡三次也会被判成「反复卡顿」而换源。
        if (this.stallCount > 0 && this.lastStallAt > 0 && this.lastProgressAt - this.lastStallAt > 60000) {
          this.stallCount = 0;
        }
        if (this.stallTimer >= 0 || this.stallLoading) {
          this.clearStall();
        }
      }
      this.positionText = Utils.formatTime(positionMs);
      if (durationMs > 0) {
        this.sliderValue = Math.floor(positionMs / 1000);
      }
      this.maybeSaveProgress(positionMs, durationMs);
    };
    this.player.onPlayStateChanged = (playing: boolean) => {
      this.playing = playing;
      this.syncCastPlayback(playing);
      this.buffering = false;
      // 一旦进入 playing，立刻收掉加载圈并标记已起播
      this.showLoading = false;
      this.clearLoadingTimer();
      if (playing) {
        this.hasStarted = true;
        this.clearStall();
        this.clearWatchdog();
        this.scheduleHideControls();
        // 只有真正进入 playing 才应用倍速；1.0 倍速是默认值，不必调用，避免无谓报错
        if (!this.speedApplied) {
          this.speedApplied = true;
          if (this.speedValue !== 1) {
            this.player.setSpeed(this.speedValue);
          }
        }
      }
    };
    this.player.onCompleted = () => {
      this.saveProgress();
      if (this.settings.autoNext && this.currentEp + 1 < this.episodes.length) {
        this.currentEp = this.currentEp + 1;
        this.positionMs = 0;
        this.positionText = '00:00';
        this.sliderValue = 0;
        this.startPlay();
      } else {
        this.controlsVisible = true;
      }
    };
    this.player.onError = (message: string) => {
      this.errorText = message;
      this.buffering = false;
      this.clearStall();
      this.clearWatchdog();
    };
    this.player.onBuffering = (percent: number) => {
      this.buffering = percent < 100;
      if (percent >= 100) {
        this.clearLoadingTimer();
        this.showLoading = false;
        return;
      }
      if (!this.hasStarted) {
        this.showLoading = true;
        return;
      }
      // 起播后的卡顿检测：缓冲事件只做「预约」，进度真的停住 ~1 秒才弹加载圈。
      // bufferingUpdate 在正常播放时也会频繁 <100%，直接弹会疯狂闪烁
      // （这是之前「起播后一律不弹」的原因 —— 改用进度停摆判定后可以安全恢复）。
      if (this.playing) {
        this.scheduleStallCheck();
      }
    };
    this.player.onVideoSize = (width: number, height: number) => {
      this.videoW = width;
      this.videoH = height;
      this.updateSurfaceSize();
    };
  }

  /** 起播后卡顿：预约 1 秒后检查进度是否停摆，停摆才弹加载圈（只预约一次） */
  private scheduleStallCheck(): void {
    if (this.stallTimer >= 0 || this.released) {
      return;
    }
    this.lastPosAt = Date.now();
    this.stallTimer = setTimeout(() => {
      this.stallTimer = -1;
      if (this.released || !this.hasStarted) {
        return;
      }
      if (Date.now() - this.lastPosAt >= 900) {
        this.stallLoading = true;
        this.stallCount++;
        this.lastStallAt = Date.now();
        // 同一集反复卡 3 次以上：别让用户一直盯着转圈，换延时最小的源
        if (this.stallCount >= PlayerPage.STALL_LIMIT) {
          this.onPlaybackHang();
        }
      }
    }, 1000);
  }

  private clearStall(): void {
    if (this.stallTimer >= 0) {
      clearTimeout(this.stallTimer);
      this.stallTimer = -1;
    }
    this.stallLoading = false;
  }

  private async loadEpisodes(): Promise<void> {
    // 调用方已带来播放地址（如详情页点播放、历史记录续播）：
    // 直接用它拼成一集，跳过网络请求 —— 采集站对同一 id 的连续请求常有限流，
    // 重复请求失败会退化成空 URL，最终误报「没有可用的播放地址」。
    if (this.episodeUrl !== '') {
      this.episodes = [{
        index: this.currentEp,
        name: this.episodeName !== '' ? this.episodeName : '第1集',
        url: this.episodeUrl
      }];
      // 只有一集时选集/下一集按钮不显示；后台补拉完整分集列表（不打断当前播放）
      this.loadFullEpisodeListInBackground();
      return;
    }
    // 优先复用详情页已加载的集数
    const cached: VideoDetail | null = DetailCache.get(this.sourceKey, this.vodId);
    if (cached !== null && cached.episodes.length > 0) {
      // 指定了播放线路时取该线路的分集（详情页选了线路 2/3 等）
      if (this.lineIndex > 0 && cached.info.lines !== undefined && this.lineIndex < cached.info.lines.length) {
        this.episodes = cached.info.lines[this.lineIndex].episodes;
      } else {
        this.episodes = cached.episodes;
      }
      if (this.currentEp >= this.episodes.length) {
        this.currentEp = this.episodes.length - 1;
      }
      if (this.currentEp < 0) {
        this.currentEp = 0;
      }
      return;
    }
    const source = SourceManager.shared().getVodSource(this.sourceKey);
    if (source === null) {
      this.errorText = '视频源不存在';
      return;
    }
    let detail: VideoDetail | null = null;
    try {
      detail = await CmsClient.detail(source, this.vodId);
    } catch (e) {
      detail = null;
    }
    if (detail === null || detail.episodes.length === 0) {
      try {
        detail = await CmsClient.detailFromPage(source, this.vodId);
      } catch (e2) {
        detail = null;
      }
    }
    if (detail === null || detail.episodes.length === 0) {
      // 不要塞入 url 为空的占位集：那样 episodes.length > 0 会让上层误判「已加载完成」，
      // 最终仍然拿不到可播放地址。保持空数组，让调用方能识别失败并重试/换源。
      this.errorText = '获取分集列表失败，请重试或换源';
      this.episodes = [];
      return;
    }
    // 丢弃解析出空地址的分集，避免它们挤占列表并让选集面板出现不可点的项
    const valid: Episode[] = [];
    for (const ep of detail.episodes) {
      if (ep.url !== '') {
        valid.push(ep);
      }
    }
    if (valid.length === 0) {
      this.errorText = '该影片没有可播放的分集地址';
      this.episodes = [];
      return;
    }
    // 网络加载时同样尊重指定的播放线路
    if (this.lineIndex > 0 && detail.info.lines !== undefined && this.lineIndex < detail.info.lines.length) {
      const lineEps: Episode[] = [];
      for (const ep of detail.info.lines[this.lineIndex].episodes) {
        if (ep.url !== '') {
          lineEps.push(ep);
        }
      }
      if (lineEps.length > 0) {
        this.episodes = lineEps;
      } else {
        this.episodes = valid;
      }
    } else {
      this.episodes = valid;
    }
    DetailCache.put(this.sourceKey, this.vodId, detail);
    if (this.currentEp >= this.episodes.length) {
      this.currentEp = this.episodes.length - 1;
    }
    if (this.currentEp < 0) {
      this.currentEp = 0;
    }
  }

  /**
   * 详情页点播放会带 episodeUrl 直接起播（跳过网络请求，起播快），
   * 但 episodes 只有 1 条合成记录，选集/下一集按钮因此消失。
   * 起播后后台补拉完整分集列表：优先 DetailCache，未命中再走网络；
   * 拉到后原位替换，正在播的集按 URL 对位，不中断播放。
   */
  private async loadFullEpisodeListInBackground(): Promise<void> {
    let list: Episode[] = [];
    const cached: VideoDetail | null = DetailCache.get(this.sourceKey, this.vodId);
    if (cached !== null && cached.episodes.length > 0) {
      list = (this.lineIndex > 0 && cached.info.lines !== undefined && this.lineIndex < cached.info.lines.length)
        ? cached.info.lines[this.lineIndex].episodes : cached.episodes;
    } else {
      const source = SourceManager.shared().getVodSource(this.sourceKey);
      if (source === null) {
        return;
      }
      let detail: VideoDetail | null = null;
      try {
        detail = await CmsClient.detail(source, this.vodId);
      } catch (e) {
        detail = null;
      }
      if (detail === null || detail.episodes.length === 0) {
        try {
          detail = await CmsClient.detailFromPage(source, this.vodId);
        } catch (e2) {
          detail = null;
        }
      }
      if (detail === null) {
        return;
      }
      list = (this.lineIndex > 0 && detail.info.lines !== undefined && this.lineIndex < detail.info.lines.length)
        ? detail.info.lines[this.lineIndex].episodes : detail.episodes;
      DetailCache.put(this.sourceKey, this.vodId, detail);
    }
    const valid: Episode[] = [];
    for (const ep of list) {
      if (ep.url !== '') {
        const item: Episode = { index: valid.length, name: ep.name, url: ep.url };
        valid.push(item);
      }
    }
    if (this.released || valid.length <= 1) {
      return;
    }
    // 保持正在播的分集对位：优先按 URL 匹配；匹配不到保持原 currentEp
    let cur = this.currentEp;
    if (cur < 0 || cur >= valid.length || valid[cur].url !== this.episodeUrl) {
      let found = -1;
      for (let i = 0; i < valid.length; i++) {
        if (valid[i].url === this.episodeUrl) {
          found = i;
          break;
        }
      }
      if (found >= 0) {
        cur = found;
      }
    }
    if (cur >= valid.length) {
      cur = valid.length - 1;
    }
    this.currentEp = cur;
    this.episodes = valid;
  }

  private currentEpisode(): Episode | null {
    if (this.episodes.length === 0) {
      return null;
    }
    for (const ep of this.episodes) {
      if (ep.index === this.currentEp) {
        return ep;
      }
    }
    // 部分源的 Episode.index 并非从 0 连续递增（如直接用片源 id），
    // 按 index 匹配会落空；此时退化为按数组下标取值，避免误报「没有可用的播放地址」。
    if (this.currentEp >= 0 && this.currentEp < this.episodes.length) {
      return this.episodes[this.currentEp];
    }
    return this.episodes[0];
  }

  /** 取实际可播放的分集：当前集地址为空时回退到第一个非空地址的分集 */
  private playableEpisode(): Episode | null {
    const ep = this.currentEpisode();
    if (ep !== null && ep.url !== '') {
      return ep;
    }
    for (const item of this.episodes) {
      if (item.url !== '') {
        this.currentEp = item.index;
        return item;
      }
    }
    return ep;
  }

  private async startPlay(): Promise<void> {
    if (this.starting || this.playPending || this.released) {
      // 起播进行中又来了换集/换源请求：记入队列，本轮完成后自动重起。
      // 静默丢弃会让用户以为「点了没反应」，还可能诱发交错起播的竞态。
      if (!this.released) {
        this.restartQueued = true;
      }
      return;
    }
    this.playPending = true;
    try {
      await this.doStartPlay();
    } finally {
      this.starting = false;
      this.playPending = false;
      if (this.restartQueued && !this.released) {
        this.restartQueued = false;
        this.startPlay();
      }
    }
  }

  private async doStartPlay(): Promise<void> {
    this.errorText = '';
    // 换集/换源/重试都是「重新起播」：回到未起播状态，加载圈立即出现，
    // 同时把旧的延迟计时清掉，避免上一次的计时器误触发。
    this.hasStarted = false;
    this.showLoading = true;
    this.clearLoadingTimer();
    this.clearStall();
    this.lastPosMs = 0;
    this.lastProgressAt = 0;
    this.stallCount = 0;
    this.lastStallAt = 0;
    this.clearWatchdog();
    // 离线播放只有本地一份文件，没有别的源可换，不必起表
    if (this.offlineDir === '') {
      this.startWatchdog();
    }
    if (this.offlineDir !== '') {
      this.starting = true;
      // 离线缓存交付的是合并好的整文件 video.ts。
      // 播放器读不到沙箱文件，必须经本地回环 HTTP 喂给它。
      const media = DownloadManager.mediaPath(this.offlineDir);
      try {
        // 仅用于确认文件存在；关掉句柄，播放走本地 HTTP
        const probe = fs.openSync(media, fs.OpenMode.READ_ONLY);
        fs.closeSync(probe);
      } catch (e) {
        this.errorText = '离线文件缺失，请重新下载';
        return;
      }
      const url: string = await LocalHttpServer.shared().mediaUrl(media);
      if (url === '') {
        this.errorText = '本地播放服务启动失败';
        return;
      }
      await this.player.playUrl(url, {}, this.positionMs);
      return;
    }
    // 关键：VideoSurface 的 onSurfaceReady 可能早于 aboutToAppear 里发起的分集请求返回，
    // 此时 episodes 仍为空数组，直接取集会误判成「没有可用的播放地址」。
    // 因此必须等分集加载任务结束再取播放地址。
    await this.ensureEpisodesLoaded();
    if (this.released) {
      return;
    }
    const ep = this.playableEpisode();
    if (ep === null || ep.url === '') {
      this.errorText = this.episodes.length === 0 ? '获取分集列表失败，请重试或换源' : '没有可用的播放地址';
      return;
    }
    this.starting = true;
    this.buffering = true;
    const resolved = await PlayUrlResolver.resolve(ep.url, this.settings.adFilter, this.cacheDir);
    this.holderFile = resolved.file;
    // 让用户看得见广告过滤在工作；为 0 时不打扰（该源本来就没插广告）
    if (resolved.filteredCount > 0) {
      this.toast('已过滤 ' + resolved.filteredCount + ' 个广告分片');
    }
    if (resolved.kind === 'fd') {
      await this.player.playFd(resolved.url, resolved.headers, this.positionMs);
    } else {
      await this.player.playUrl(resolved.url, resolved.headers, this.positionMs);
    }
  }

  /** 等待分集加载完成；失败后允许重新拉取一次（源站限流时第二次往往能成功） */
  private async ensureEpisodesLoaded(): Promise<void> {
    if (this.offlineDir !== '') {
      return;
    }
    if (this.episodes.length > 0) {
      return;
    }
    if (this.loadTask === null) {
      this.loadTask = this.loadEpisodes();
    }
    try {
      await this.loadTask;
    } catch (e) {
      // 忽略，走下面的重试
    }
    this.loadTask = null;
    if (this.episodes.length > 0 || this.released) {
      return;
    }
    DetailCache.invalidate(this.sourceKey, this.vodId);
    this.loadTask = this.loadEpisodes();
    try {
      await this.loadTask;
    } catch (e) {
      // ignore
    }
    this.loadTask = null;
  }

  private maybeSaveProgress(positionMs: number, durationMs: number): void {
    const now = Date.now();
    if (now - this.lastSaveAt < 5000) {
      return;
    }
    this.lastSaveAt = now;
    this.saveProgress(positionMs, durationMs);
  }

  /**
   * 历史记录封面。
   * 之前这里写死 undefined，导致首页「继续观看」永远是空白灰块。
   * 优先取详情缓存（从详情页进播放页时一定有），其次沿用已有记录（从继续观看直接进播放页时）。
   */
  private resolvePic(): string | undefined {
    if (this.pic !== '') {
      return this.pic;
    }
    const cached: VideoDetail | null = DetailCache.get(this.sourceKey, this.vodId);
    if (cached !== null && cached.info.cover !== undefined && cached.info.cover !== '') {
      return cached.info.cover;
    }
    const old: PlayRecord | null = HistoryStore.shared().getProgress(this.sourceKey, this.vodId);
    const oldPic: string | undefined = old !== null ? old.pic : undefined;
    if (oldPic !== undefined && oldPic !== '') {
      return oldPic;
    }
    return undefined;
  }

  private saveProgress(positionMs: number = -1, durationMs: number = -1): void {
    if (this.offlineDir !== '' || !this.settings.playHistoryEnabled) {
      return;
    }
    const pos = positionMs >= 0 ? positionMs : this.player.currentTime();
    const dur = durationMs >= 0 ? durationMs : this.player.duration();
    const ep = this.playableEpisode();
    HistoryStore.shared().saveProgress({
      sourceKey: this.sourceKey,
      vodId: this.vodId,
      name: this.title !== '' ? this.title : '未知视频',
      pic: this.resolvePic(),
      sourceName: SourceManager.shared().getVodSource(this.sourceKey)?.name ?? this.sourceKey,
      episode: this.currentEp,
      episodeName: ep !== null ? ep.name : this.episodeName,
      playUrl: ep !== null ? ep.url : undefined,
      lineIndex: this.lineIndex,
      positionMs: pos,
      durationMs: dur,
      updatedAt: Date.now()
    });
  }

  private release(): void {
    if (this.released) {
      return;
    }
    this.released = true;
    this.player.release();
    if (this.holderFile !== null) {
      try {
        fs.closeSync(this.holderFile.fd);
      } catch (e) {
        // ignore
      }
      this.holderFile = null;
    }
    if (this.hideTimer >= 0) {
      clearTimeout(this.hideTimer);
      this.hideTimer = -1;
    }
  }

  private clearLoadingTimer(): void {
    if (this.loadingTimer >= 0) {
      clearTimeout(this.loadingTimer);
      this.loadingTimer = -1;
    }
  }

  private scheduleHideControls(): void {
    if (this.hideTimer >= 0) {
      clearTimeout(this.hideTimer);
    }
    this.hideTimer = setTimeout(() => {
      if (this.playing) {
        this.controlsVisible = false;
      }
    }, 4000);
  }

  private onSurfaceReady(surfaceId: string): void {
    this.surfaceId = surfaceId;
    // 先让内容区变成整屏，再切横屏：顺序反了会先按竖屏安全区算一次尺寸
    this.applyWindowFullScreen(true);
    // 一进入播放页就切横屏（视频类应用的标准行为），退出全屏再切回竖屏
    this.setLandscape(true);
    this.player.create(surfaceId).then((ok: boolean) => {
      if (ok) {
        this.startPlay();
      }
    });
  }

  private onSurfaceDestroy(): void {
    // 画面销毁时不释放播放器（页面生命周期统一管理）
  }

  private togglePlay(): void {
    this.player.toggle();
    this.controlsVisible = true;
    this.scheduleHideControls();
  }

  private onSliderChange(value: number, mode: SliderChangeMode): void {
    if (mode === SliderChangeMode.End) {
      this.player.seekTo(value * 1000);
      this.positionText = Utils.formatTime(value * 1000);
    }
  }

  private selectEpisode(idx: number): void {
    if (idx === this.currentEp) {
      this.showEpisodes = false;
      return;
    }
    this.currentEp = idx;
    this.positionMs = 0;
    this.positionText = '00:00';
    this.sliderValue = 0;
    this.showEpisodes = false;
    this.startPlay();
  }

  private selectSpeed(speed: number): void {
    this.speedValue = speed;
    this.player.setSpeed(speed);
    this.showSpeeds = false;
  }

  private async runSpeedTest(): Promise<void> {
    if (this.title === '') {
      return;
    }
    this.speedTesting = true;
    this.showSources = true;
    const items = await SearchService.speedTest(this.title, this.sourceKey, this.settings);
    this.speedItems = items;
    this.speedTesting = false;
  }

  private async switchSource(item: SpeedTestItem): Promise<void> {
    const done: boolean = await this.applySource(item, false);
    if (done) {
      // 手动换源是用户的主动选择：给自动换源重新记一份预算
      this.autoTried = [];
      this.stallCount = 0;
    }
  }

  /** 真正执行换源；fromAuto=true 时失败不弹 toast，由自动流程自己给文案 */
  private async applySource(item: SpeedTestItem, fromAuto: boolean): Promise<boolean> {
    if (!item.ok || item.vodId === undefined || item.vodId === '') {
      if (!fromAuto) {
        this.toast('该源当前不可用');
      }
      return false;
    }
    const source = SourceManager.shared().getVodSource(item.sourceKey);
    if (source === null) {
      if (!fromAuto) {
        this.toast('该源已被删除');
      }
      return false;
    }
    let detail: VideoDetail | null = null;
    try {
      detail = await CmsClient.detail(source, item.vodId);
    } catch (e) {
      detail = null;
    }
    if (detail === null || detail.episodes.length === 0) {
      if (!fromAuto) {
        this.toast('切换失败：该源没有分集信息');
      }
      return false;
    }
    this.showSources = false;
    this.sourceKey = item.sourceKey;
    this.vodId = item.vodId;
    this.episodes = detail.episodes;
    DetailCache.put(this.sourceKey, this.vodId, detail);
    if (this.currentEp >= this.episodes.length) {
      this.currentEp = this.episodes.length - 1;
    }
    // 换源后从当前进度继续播放：把现在的播放位置带入新源，
    // AvPlayerController 会在新源 prepared 后自动 seek 过去
    const pos = this.player.currentTime();
    this.positionMs = pos > 0 ? pos : 0;
    this.positionText = Utils.formatTime(this.positionMs);
    this.sliderValue = Math.floor(this.positionMs / 1000);
    this.startPlay();
    return true;
  }

  /** 起播看门狗：12 秒还没出画面，就当这一路加载失败 */
  private startWatchdog(): void {
    this.clearWatchdog();
    this.loadWatchdog = setTimeout(() => {
      this.loadWatchdog = -1;
      if (this.released || this.hasStarted || this.errorText !== '') {
        return;
      }
      this.onPlaybackHang();
    }, PlayerPage.LOAD_TIMEOUT_MS);
  }

  private clearWatchdog(): void {
    if (this.loadWatchdog >= 0) {
      clearTimeout(this.loadWatchdog);
      this.loadWatchdog = -1;
    }
  }

  /**
   * 播放不畅的统一入口：加载超时（12 秒没画面）或同一集真卡顿 3 次。
   * 处理方式是自动换到「延时最小的其他点播源」，并从当前进度续播。
   */
  private onPlaybackHang(): void {
    if (this.released || this.autoSwitching) {
      return;
    }
    // 近 1.5 秒内进度还在走 = 播放正常，别换源。
    // 判据用「进度」而不是 playing：卡顿时 playing 依然为 true。
    if (this.lastProgressAt > 0 && Date.now() - this.lastProgressAt < 1500) {
      return;
    }
    this.showLoading = false;
    this.clearStall();
    if (this.offlineDir !== '') {
      // 离线只有本地一份文件，换不了源
      if (this.errorText === '') {
        this.errorText = '本地文件播放失败，请重新下载';
      }
      return;
    }
    this.autoSwitchSource();
  }

  private async autoSwitchSource(): Promise<void> {
    if (this.autoSwitching || this.released) {
      return;
    }
    if (this.title === '') {
      this.errorText = '播放失败，请稍后重试';
      return;
    }
    if (this.autoTried.length >= PlayerPage.AUTO_SWITCH_MAX) {
      this.errorText = '已自动尝试多个片源仍无法播放，请手动换源';
      return;
    }
    this.autoSwitching = true;
    this.clearWatchdog();
    this.showLoading = true;
    this.toast('播放不畅，正在自动切换片源…');
    try {
      // 返回结果已按延迟升序排列：第一个可用的就是延时最小的
      const items: SpeedTestItem[] = await SearchService.speedTest(this.title, this.sourceKey, this.settings);
      // 关键：测速要花几秒，这段时间画面可能已经恢复正常。
      // 不复查就切，用户看到的就是「刚播起来又被换走」。
      if (this.released) {
        return;
      }
      if (this.lastProgressAt > 0 && Date.now() - this.lastProgressAt < 2000) {
        this.showLoading = false;
        return;
      }
      let picked: SpeedTestItem | null = null;
      for (const it of items) {
        if (!it.ok || it.vodId === undefined || it.vodId === '') {
          continue;
        }
        if (it.sourceKey === this.sourceKey || this.autoTried.indexOf(it.sourceKey) >= 0) {
          continue;
        }
        picked = it;
        break;
      }
      if (picked === null) {
        this.showLoading = false;
        this.errorText = '没有找到可用的备用片源，请手动换源';
        return;
      }
      const pickedName: string = picked.sourceName;
      this.autoTried.push(picked.sourceKey);
      const done: boolean = await this.applySource(picked, true);
      if (done) {
        this.toast('已切换到「' + pickedName + '」');
      } else {
        this.showLoading = false;
        this.errorText = '备用片源也无法播放，请手动换源';
      }
    } catch (e) {
      this.showLoading = false;
      this.errorText = '自动换源失败，请手动换源';
    } finally {
      this.autoSwitching = false;
    }
  }

  /** Area 里的 Length 可能是 number 也可能是字符串，统一取数值（vp） */
  private areaNumber(v: Length): number {
    if (typeof v === 'number') {
      return v;
    }
    if (typeof v === 'string') {
      const n: number = parseFloat(v);
      return isNaN(n) ? 0 : n;
    }
    return 0;
  }

  /**
   * 一次「划过约 60% 屏高」覆盖 0→100%。
   * 屏幕越大越难一划到底，所以按实测高度取比例，而不是写死一个 vp 值。
   */
  private adjustRange(): number {
    const h: number = this.canvasH > 0 ? this.canvasH : 640;
    return h * 0.6;
  }

  private clearAdjustTimer(): void {
    if (this.adjustTimer >= 0) {
      clearTimeout(this.adjustTimer);
      this.adjustTimer = -1;
    }
  }

  /** 建立投屏会话：AVCastPicker 只对创建了 AVSession 的应用展示可投设备 */
  private async initCastSession(): Promise<void> {
    if (this.castSession !== null) {
      return;
    }
    const ctx = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return;
    }
    try {
      const s = await avSession.createAVSession(ctx, 'libretv_player', 'video');
      this.castSession = s;
      await s.activate();
      const md: avSession.AVMetadata = {
        assetId: this.vodId !== '' ? this.vodId : 'unknown',
        title: this.title !== '' ? this.title : 'LibreTV'
      };
      await s.setAVMetadata(md);
      // 关键：声明需要「url 投播」能力，投播列表才会出现智慧屏 / DLNA 等设备；
      // 不声明时系统按普通音频会话处理，列表只剩音频输出设备（本次反馈的现象）
      const extras: Record<string, Object> = { 'requireAbilityList': ['url-cast'] };
      await s.setExtras(extras);
    } catch (e) {
      this.castSession = null;
    }
  }

  private releaseCastSession(): void {
    const s = this.castSession;
    this.castSession = null;
    if (s !== null) {
      s.destroy().catch(() => {
        // 忽略
      });
    }
  }

  /** 把播放状态同步给投播会话：播控中心/远端设备靠它显示与控制 */
  private syncCastPlayback(playing: boolean): void {
    const s = this.castSession;
    if (s === null) {
      return;
    }
    try {
      const pos: avSession.PlaybackPosition = { elapsedTime: this.positionMs, updateTime: Date.now() };
      const st: avSession.AVPlaybackState = {
        state: playing ? avSession.PlaybackState.PLAYBACK_STATE_PLAY
          : avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
        position: pos
      };
      s.setAVPlaybackState(st).catch(() => {
        // 忽略
      });
    } catch (e) {
      // 忽略
    }
  }

  /**
   * 读取当前系统媒体音量（0..max）。
   * 注意：第三方应用没有系统音量写权限，唯一的合法通道是系统提供的
   * AVVolumePanel 组件（它的 volumeLevel 会写到设备音量），见 build 里的音量浮层。
   */
  private syncSystemVolume(): void {
    try {
      const vm = audio.getAudioManager().getVolumeManager();
      const max: number = vm.getMaxVolumeByStream(audio.StreamUsage.STREAM_USAGE_MOVIE);
      if (max > 0) {
        this.volumeMaxLevel = max;
      }
      this.volumeLevel = vm.getVolumeByStream(audio.StreamUsage.STREAM_USAGE_MOVIE);
    } catch (e) {
      // 个别设备/版本取不到，沿用上次值
    }
  }

  /** 开始滑动：按落点左右分出调音量还是调亮度，并记下基准值 */
  private beginAdjust(x: number): void {
    const half: number = this.canvasW > 0 ? this.canvasW / 2 : 0;
    const kind: string = x > half ? 'brightness' : 'volume';
    this.clearAdjustTimer();
    // 右半屏 = 亮度，左半屏 = 音量
    if (kind === 'volume') {
      // 音量基准取系统当前值：之前调的是播放器内部音量，
      // 上限被手机预先设定的系统音量卡死，怎么滑都不会更响。
      this.syncSystemVolume();
      this.adjustBase = this.volumeMaxLevel > 0 ? this.volumeLevel / this.volumeMaxLevel : 0;
    } else {
      this.adjustBase = this.currentBrightness();
    }
    this.adjustKind = kind;
    this.adjustValue = this.adjustBase;
  }

  /** 滑动中：offsetY 往上滑是负的，取反后「往上」= 变大 */
  private updateAdjust(offsetY: number): void {
    if (this.adjustKind === '') {
      return;
    }
    const range: number = this.adjustRange();
    if (range <= 0) {
      return;
    }
    let v: number = this.adjustBase + (-offsetY / range);
    if (v < 0) {
      v = 0;
    }
    if (v > 1) {
      v = 1;
    }
    this.adjustValue = v;
    if (this.adjustKind === 'volume') {
      // 写系统音量档位（AVVolumePanel 的 volumeLevel 会落到设备音量）
      const lv: number = Math.round(v * this.volumeMaxLevel);
      if (lv !== this.volumeLevel) {
        this.volumeLevel = lv;
      }
    } else {
      this.applyBrightness(v);
    }
  }

  /** 抬手：浮层再留 500ms 让人看清最终值 */
  private endAdjust(): void {
    this.clearAdjustTimer();
    this.adjustTimer = setTimeout(() => {
      this.adjustKind = '';
    }, 500);
  }

  /**
   * 当前窗口亮度（0~1）。
   * getWindowProperties().brightness 返回 -1 表示「跟随系统」，此时拿不到真实值，
   * 只能给个中位起点 —— 第一次滑动会跳一下，之后都由我们自己写死，不再依赖系统。
   */
  private currentBrightness(): number {
    const win = this.win;
    if (win !== null) {
      const b: number = win.getWindowProperties().brightness;
      if (b >= 0) {
        return b > 1 ? 1 : b;
      }
    }
    return 0.5;
  }

  private applyBrightness(v: number): void {
    const win = this.win;
    if (win === null) {
      return;
    }
    win.setWindowBrightness(v).catch(() => {
      // 分屏、投屏等场景可能被拒绝，忽略即可
    });
  }

  /** -1 = 交还系统亮度 */
  private restoreBrightness(): void {
    const win = this.win;
    if (win === null) {
      return;
    }
    win.setWindowBrightness(-1).catch(() => {
      // ignore
    });
  }

  /**
   * 按「视频原始宽高比」算显示尺寸：
   * 取可视区与视频比例中更受限制的一边，等比缩放后居中，多余部分留黑边。
   * 绝不让 Surface 铺满容器 —— 那样等于把画面拉扁。
   */
  private updateSurfaceSize(): void {
    if (this.canvasW <= 0 || this.canvasH <= 0) {
      return;
    }
    if (this.videoW <= 0 || this.videoH <= 0) {
      // 尺寸未知（刚起播）先铺满，拿到 videoSizeChange 后会立刻纠正
      this.displayW = this.canvasW;
      this.displayH = this.canvasH;
      return;
    }
    const videoRatio: number = this.videoW / this.videoH;
    const canvasRatio: number = this.canvasW / this.canvasH;
    if (this.fitCover) {
      // 铺满（裁切）：保持比例取较大缩放，超出的部分被窗口裁掉。
      // 画面不变形，只是左右或上下有少量内容出画 —— 车机等大屏上用这个最大化画面。
      if (videoRatio > canvasRatio) {
        this.displayH = this.canvasH;
        this.displayW = this.canvasH * videoRatio;
      } else {
        this.displayW = this.canvasW;
        this.displayH = this.canvasW / videoRatio;
      }
      return;
    }
    if (videoRatio > canvasRatio) {
      // 视频更宽：以宽为准，上下留黑边
      this.displayW = this.canvasW;
      this.displayH = this.canvasW / videoRatio;
    } else {
      // 视频更高：以高为准，左右留黑边
      this.displayH = this.canvasH;
      this.displayW = this.canvasH * videoRatio;
    }
  }

  /**
   * 切换横竖屏（真实屏幕方向，不是旋转画面）。
   * 横屏用 AUTO_ROTATION_LANDSCAPE，允许左右两个横屏方向，横屏时用手机左右翻转都能正立。
   */
  /**
   * 播放页专用：把窗口切成「布局全屏」，内容区才真正等于整屏（含状态栏/导航条区域）。
   * 只在本页开启，离开立刻复原 —— 首页/其它页仍走系统默认安全区，不受影响。
   */
  private applyWindowFullScreen(on: boolean): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    window.getLastWindow(context).then((win: window.Window) => {
      win.setWindowLayoutFullScreen(on).catch(() => {
        // 个别系统版本/分屏场景会拒绝，忽略即可，不影响播放
      });
    }).catch(() => {
      // ignore
    });
  }

  private setLandscape(on: boolean): void {
    this.landscape = on;
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    window.getLastWindow(context).then((win: window.Window) => {
      if (on) {
        // 播放页显式接管方向：挂起 DevicePolicy 的窗口尺寸自动纠正，避免互抢
        DevicePolicy.suppressed = true;
        win.setPreferredOrientation(window.Orientation.AUTO_ROTATION_LANDSCAPE);
      } else {
        // 退出全屏必须**强制竖屏**，不能交给系统自动判断：
        // 平板横着拿的时候，AUTO_ROTATION 的目标方向仍然是横屏，
        // 点下去画面一点变化都没有，按钮看起来就像失效了。
        win.setPreferredOrientation(window.Orientation.PORTRAIT);
      }
    }).catch(() => {
      // 忽略窗口操作失败
    });
  }

  /**
   * 离开播放页时把屏幕方向交还给系统。
   * setPreferredOrientation 作用在**主窗口**上，是全局且跨页面持久的：
   * 只要这里锁了 PORTRAIT，回到首页后整个 APP 就不再跟随平板旋转，
   * 只能杀进程重开 —— 之前"退出全屏后转不动"的根因就在这里。
   */
  private restoreRotation(): void {
    // 交还给「设备策略默认方向」：普通手机回竖屏，平板/折叠机回跟随旋转
    DevicePolicy.suppressed = false;
    DevicePolicy.applyDefault();
  }

  private back(): void {
    this.saveProgress();
    this.restoreRotation();
    this.navPathStack.pop();
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Center }) {
        // 视频画面：尺寸由 updateSurfaceSize 按原始宽高比算出，Stack 负责居中
        VideoSurface({
          surfaceWidth: this.displayW,
          surfaceHeight: this.displayH,
          onSurfaceReady: (surfaceId: string) => {
            this.onSurfaceReady(surfaceId);
          },
          onSurfaceDestroy: () => {
            this.onSurfaceDestroy();
          }
        })

        // 点击层：轻点画面显示/隐藏控制条（置于控制层之下，避免事件冒泡误触）
        Column()
          .width('100%')
          .height('100%')
          .onClick(() => {
            if (!this.controlsVisible) {
              this.controlsVisible = true;
              this.scheduleHideControls();
            } else {
              this.controlsVisible = false;
            }
          })

        // 加载 / 错误态
        if ((this.showLoading || this.stallLoading) && this.errorText === '') {
          // 播放器背景是黑的，用白色圈；用主题红在暗背景上非常扎眼
          LoadingProgress()
            .width(44)
            .height(44)
            .color(Color.White)
            .opacity(0.9)
        }
        if (this.errorText !== '') {
          Column({ space: 12 }) {
            Text(this.errorText)
              .fontSize(14)
              .fontColor(Color.White)
              .textAlign(TextAlign.Center)
              .maxLines(3)
            // 「返回」让用户能退出重试循环：源坏了时只给重试会陷入
            // 重试 -> 瞬间失败 -> 再弹窗 的死循环，回详情页才能换源/换集
            Row({ space: 12 }) {
              Button('返回')
                .fontSize(14)
                .fontColor(Color.White)
                .backgroundColor('#40FFFFFF')
                .onClick(() => {
                  this.back();
                })
              Button('重试')
                .fontSize(14)
                .backgroundColor($r('app.color.color_primary'))
                .onClick(() => {
                  this.errorText = '';
                  this.startPlay();
                })
            }
          }
          .alignItems(HorizontalAlign.Center)
          .constraintSize({ maxWidth: '82%' })
          .padding({ left: 20, right: 20, top: 16, bottom: 16 })
          .borderRadius(14)
          .backgroundColor('#B3000000')
        }

        // 控制层
        if (this.controlsVisible && this.errorText === '') {
          Column({ space: 0 }) {
            // 顶部栏
            Row({ space: 10 }) {
              // 这些图标原来是纯黑 PNG，深色主题下贴在黑背景上等于隐形。
              // 换成可染色的 SVG，统一取 color_text（与主题相反的明暗），
              // 再垫一层同色系半透明圆底，压在亮画面上也不会糊。
              Stack({ alignContent: Alignment.Center }) {
                Image($r('app.media.ic_player_back'))
                  .width(20)
                  .height(20)
                  .fillColor($r('app.color.color_text'))
              }
              .width(34)
              .height(34)
              .borderRadius(17)
              .backgroundColor($r('app.color.color_player_scrim'))
              .onClick(() => {
                this.back();
              })
              Column({ space: 2 }) {
                Text(this.titleLabel())
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Color.White)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (this.offlineDir !== '') {
                  Text('离线缓存 · ' + this.episodeName)
                    .fontSize(11)
                    .fontColor('#CCCCCC')
                } else {
                  Text(this.episodeName + ' · ' + this.infoSourceName())
                    .fontSize(11)
                    .fontColor('#CCCCCC')
                    .maxLines(1)
                }
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              Stack({ alignContent: Alignment.Center }) {
                Image($r('app.media.ic_player_fullscreen'))
                  .width(18)
                  .height(18)
                  .fillColor($r('app.color.color_text'))
                  .opacity(this.landscape ? 1 : 0.85)
              }
              .width(34)
              .height(34)
              .borderRadius(17)
              .backgroundColor($r('app.color.color_player_scrim'))
              .onClick(() => {
                // 横屏 -> 竖屏（退出全屏）；竖屏 -> 横屏（重新全屏）
                // 画面会随容器尺寸重新等比计算并居中，不会拉伸
                this.setLandscape(!this.landscape);
              })
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 14 })

            // 中部播放按钮：只在「已经起播过、现在处于暂停」时出现。
            // 起播前的加载阶段画面中央不该有三角，否则看着像没自动播放。
            Row() {
              if (this.playing) {
                Stack({ alignContent: Alignment.Center }) {
                  Image($r('app.media.ic_player_pause'))
                    .width(30)
                    .height(30)
                    .fillColor($r('app.color.color_text'))
                }
                .width(62)
                .height(62)
                .borderRadius(31)
                .backgroundColor($r('app.color.color_player_scrim'))
                .onClick(() => {
                  this.togglePlay();
                })
              } else if (this.hasStarted && this.errorText === '') {
                Stack({ alignContent: Alignment.Center }) {
                  Image($r('app.media.ic_player_play'))
                    .width(30)
                    .height(30)
                    .fillColor($r('app.color.color_text'))
                    .margin({ left: 4 })
                }
                .width(62)
                .height(62)
                .borderRadius(31)
                .backgroundColor($r('app.color.color_player_scrim'))
                .onClick(() => {
                  this.togglePlay();
                })
              }
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)

            // 底部控制条
            Column({ space: 8 }) {
              Slider({
                value: this.sliderValue,
                min: 0,
                max: this.sliderMaxValue(),
                style: SliderStyle.OutSet
              })
                .width('100%')
                .blockColor($r('app.color.color_primary'))
                .selectedColor($r('app.color.color_primary'))
                .trackColor('#333333')
                .onChange((value: number, mode: SliderChangeMode) => {
                  this.onSliderChange(value, mode);
                })

              Row({ space: 8 }) {
                // 时间合成一条，把宽度留给右侧按钮（竖屏可用宽度只有 392vp）
                Text(this.timeLabel())
                  .fontSize(11)
                  .fontColor('#CCCCCC')
                  .maxLines(1)
                  .layoutWeight(1)
                Row({ space: 6 }) {
                  // 原来是无内边距的 12sp 纯文字，手指很难点中；
                  // 改成 34vp 高的胶囊按钮，点选区域和视觉层次都更清楚。
                  Text(this.speedLabel())
                    .fontSize(13)
                    .fontColor('#FFFFFF')
                    .backgroundColor('#26FFFFFF')
                    .borderRadius(17)
                    .height(34)
                    .padding({ left: 13, right: 13 })
                    .textAlign(TextAlign.Center)
                    .maxLines(1)
                    .onClick(() => {
                      this.showSpeeds = !this.showSpeeds;
                    })
                  if (this.episodes.length > 1) {
                    Text('选集')
                      .fontSize(13)
                      .fontColor('#FFFFFF')
                      .backgroundColor('#26FFFFFF')
                      .borderRadius(17)
                      .height(34)
                      .padding({ left: 13, right: 13 })
                      .textAlign(TextAlign.Center)
                      .maxLines(1)
                      .onClick(() => {
                        this.showEpisodes = !this.showEpisodes;
                      })
                  }
                  if (this.currentEp + 1 < this.episodes.length) {
                    Text('下一集')
                      .fontSize(13)
                      .fontColor('#FFFFFF')
                      .backgroundColor('#26FFFFFF')
                      .borderRadius(17)
                      .height(34)
                      .padding({ left: 13, right: 13 })
                      .textAlign(TextAlign.Center)
                      .maxLines(1)
                      .onClick(() => {
                        this.selectEpisode(this.currentEp + 1);
                      })
                  }
                  // 投屏：系统提供的投屏图标，点按拉起系统投屏设备列表
                  Row() {
                    AVCastPicker({
                      normalColor: '#FFFFFF',
                      activeColor: Color.White,
                      pickerStyle: AVCastPickerStyle.STYLE_MENU,
                      colorMode: AVCastPickerColorMode.AUTO,
                      sessionType: 'video'
                    })
                      .width(24)
                      .height(24)
                  }
                  .height(34)
                  .padding({ left: 5, right: 5 })
                  .backgroundColor('#26FFFFFF')
                  .borderRadius(17)
                  .justifyContent(FlexAlign.Center)

                  // 横屏/大屏下补一个「铺满屏/适应屏」切换：车机等大屏可去掉黑边最大化画面
                  if (this.canvasW > this.canvasH && this.offlineDir === '') {
                    Text(this.fitCover ? '适应屏' : '铺满屏')
                      .fontSize(13)
                      .fontColor('#FFFFFF')
                      .backgroundColor('#26FFFFFF')
                      .borderRadius(17)
                      .height(34)
                      .padding({ left: 13, right: 13 })
                      .textAlign(TextAlign.Center)
                      .maxLines(1)
                      .onClick(() => {
                        this.fitCover = !this.fitCover;
                        this.updateSurfaceSize();
                      })
                  }
                  if (this.offlineDir === '') {
                    Text('换源')
                      .fontSize(13)
                      .fontColor('#FFFFFF')
                      .backgroundColor('#26FFFFFF')
                      .borderRadius(17)
                      .height(34)
                      .padding({ left: 13, right: 13 })
                      .textAlign(TextAlign.Center)
                      .maxLines(1)
                      .onClick(() => {
                        this.runSpeedTest();
                      })
                  }
                }
                .justifyContent(FlexAlign.End)
              }
              .width('100%')
            }
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 18 })
          }
          .width('100%')
          .height('100%')
          .backgroundColor('#00000099')
          // 画面已延伸进安全区，控制条要反向留白，否则标题贴着状态栏
          .padding({ top: 26, bottom: 22 })
        }

        // 滑屏调节的浮层提示（音量改由系统音量面板呈现，这里只留亮度）
        if (this.adjustKind === 'brightness') {
          Column({ space: 10 }) {
            Text('亮度')
              .fontSize(14)
              .fontColor(Color.White)
            Stack({ alignContent: Alignment.Start }) {
              Row()
                .width('100%')
                .height(4)
                .borderRadius(2)
                .backgroundColor('#4DFFFFFF')
              Row()
                .width(this.adjustValue * 140)
                .height(4)
                .borderRadius(2)
                .backgroundColor(Color.White)
            }
            .width(140)
            .height(4)
            Text(Math.round(this.adjustValue * 100).toString() + '%')
              .fontSize(13)
              .fontColor('#DDDDDD')
          }
          .padding({ left: 22, right: 22, top: 16, bottom: 16 })
          .borderRadius(14)
          .backgroundColor('#B3000000')
          // 浮层绝不参与命中测试：滑动时手指很可能压在它正上方，
          // 一旦吃掉事件，手势会当场中断 —— 表现为「动一下就停」。
          .hitTestBehavior(HitTestMode.None)
        }

        // 音量调节浮层：用系统 AVVolumePanel 才有权限改设备音量，
        // 只显示不拦截触摸（滑动手指还在屏幕上）
        if (this.adjustKind === 'volume') {
          Stack({ alignContent: Alignment.End }) {
            AVVolumePanel({ volumeLevel: this.volumeLevel })
          }
          .width('100%')
          .height('100%')
          .padding({ right: 12 })
          .hitTestBehavior(HitTestMode.None)
        }

        // 选集面板：贴底弹出，避免挡住画面中心
        if (this.showEpisodes) {
          Column() {
            Column({ space: 8 }) {
            Row() {
              Text('选集')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.color_text'))
                .layoutWeight(1)
              Text('关闭')
                .fontSize(13)
                .fontColor($r('app.color.color_primary'))
                .onClick(() => {
                  this.showEpisodes = false;
                })
            }
            .width('100%')
            Grid() {
              ForEach(this.episodes, (ep: Episode) => {
                GridItem() {
                  Text(ep.name)
                    .fontSize(13)
                    .fontColor(this.epTextColor(ep))
                    .backgroundColor(this.epBgColor(ep))
                    .borderRadius(8)
                    .height(36)
                    .width('100%')
                    .textAlign(TextAlign.Center)
                    .maxLines(1)
                    .onClick(() => {
                      this.selectEpisode(ep.index);
                    })
                }
              }, (ep: Episode) => 'ep_' + ep.index.toString())
            }
            .columnsTemplate('1fr 1fr 1fr 1fr')
            .columnsGap(8)
            .rowsGap(8)
          }
            .width('100%')
            .height(260)
            .padding(16)
            .backgroundColor($r('app.color.color_card'))
            .borderRadius({ topLeft: 16, topRight: 16 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.End)
          // 自身不参与命中测试，视频的「点击唤出控制条」不会被挡住
          .hitTestBehavior(HitTestMode.None)
          .padding({ bottom: 18 })
        }

        // 倍速面板：贴底弹出
        if (this.showSpeeds) {
          Column() {
            Row({ space: 10 }) {
            ForEach(AvPlayerController.SPEEDS, (opt: PlaybackSpeedOption) => {
              Text(opt.label)
                .fontSize(13)
                .fontColor(this.speedTextColor(opt))
                .backgroundColor(this.speedBgColor(opt))
                .borderRadius(16)
                .padding({ left: 14, right: 14, top: 6, bottom: 6 })
                .onClick(() => {
                  this.selectSpeed(opt.value);
                })
            }, (opt: PlaybackSpeedOption) => opt.label)
          }
              .padding(10)
              .backgroundColor($r('app.color.color_card'))
              .borderRadius(20)
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.End)
            .hitTestBehavior(HitTestMode.None)
            .padding({ bottom: 18 })
        }

        // 换源面板：右下角小浮层。
        // 横屏时面板若铺满整宽、水平居中，会把整部片子挡住；
        // 这里固定 264vp 宽、列表最多约 3 行滚动，贴在右下角，
        // 既能完成换源，又几乎不影响看画面。
        if (this.showSources) {
          Column() {
            Column({ space: 6 }) {
              Row({ space: 8 }) {
                Text('选择播放源')
                  .fontSize(12)
                  .fontColor($r('app.color.color_text_secondary'))
                  .layoutWeight(1)
                  .maxLines(1)
                Text('关闭')
                  .fontSize(11)
                  .fontColor($r('app.color.color_primary'))
                  .onClick(() => {
                    this.showSources = false;
                  })
              }
              .width('100%')

              if (this.speedTesting) {
                Row({ space: 8 }) {
                  LoadingProgress()
                    .width(18)
                    .height(18)
                    .color($r('app.color.color_primary'))
                  Text('正在测速…')
                    .fontSize(12)
                    .fontColor($r('app.color.color_text_secondary'))
                }
                .width('100%')
                .height(44)
                .justifyContent(FlexAlign.Center)
              } else if (this.speedItems.length === 0) {
                Text('没有其他可用源')
                  .fontSize(12)
                  .fontColor($r('app.color.color_text_secondary'))
                  .width('100%')
                  .height(34)
                  .textAlign(TextAlign.Center)
              } else {
                List({ space: 4 }) {
                  ForEach(this.speedItems, (item: SpeedTestItem) => {
                    ListItem() {
                      Row({ space: 8 }) {
                        Text(item.sourceName)
                          .fontSize(12)
                          .fontColor($r('app.color.color_text'))
                          .layoutWeight(1)
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        if (item.ok) {
                          Text(item.latencyMs + 'ms')
                            .fontSize(11)
                            .fontColor($r('app.color.color_success'))
                        } else {
                          Text('不可用')
                            .fontSize(11)
                            .fontColor($r('app.color.color_warning'))
                        }
                      }
                      .width('100%')
                      .padding({ left: 8, right: 8, top: 7, bottom: 7 })
                      .backgroundColor($r('app.color.color_chip_bg'))
                      .borderRadius(6)
                      .onClick(() => {
                        this.switchSource(item);
                      })
                    }
                  }, (item: SpeedTestItem) => item.sourceKey)
                }
                .width('100%')
                // 最多约 3 条，再多就滚动 —— 面板要保持"小"
                .constraintSize({ maxHeight: 150 })
                .scrollBar(BarState.Off)
              }
            }
            .width(264)
            .padding(10)
            .backgroundColor($r('app.color.color_card'))
            .borderRadius(12)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.End)
          .alignItems(HorizontalAlign.End)
          // 自身不参与命中测试，别挡住视频的「点击唤出控制条」
          .hitTestBehavior(HitTestMode.None)
          .padding({ right: 16, bottom: 16 })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Black)
      // 记录播放器可视区尺寸：横竖屏切换、分屏、折叠屏都会触发，
      // 每次变化都按视频原始比例重新算一次画面尺寸，保证始终等比且居中。
      .onAreaChange((oldValue: Area, newValue: Area) => {
        const w: number = this.areaNumber(newValue.width);
        const h: number = this.areaNumber(newValue.height);
        if (w > 0 && h > 0 && (w !== this.canvasW || h !== this.canvasH)) {
          this.canvasW = w;
          this.canvasH = h;
          // 切回竖屏必须退出「铺满」：16:9 的流铺进竖屏会被裁到只剩中间一条，
          // 而竖屏下「铺满屏」按钮是隐藏的，用户没有退路。
          if (this.fitCover && w <= h) {
            this.fitCover = false;
          }
          this.updateSurfaceSize();
        }
      })
      // 上下滑调音量 / 亮度：左半屏音量、右半屏亮度，往上滑变大。
      // 挂在根容器上而不是点击层：控制条显示时它铺满全屏，
      // 挂在点击层会被它挡住（Slider / 按钮自己有手势，仍然优先响应）。
      .gesture(
        PanGesture({ fingers: 1, direction: PanDirection.Vertical })
          .onActionStart((event: GestureEvent) => {
            const fingers = event.fingerList;
            if (fingers.length > 0) {
              // globalX 是相对窗口的，最贴近「屏幕左右半边」的直觉；
              // 取不到（贴左边 = 0）时退回 localX。
              const x: number = fingers[0].globalX > 0 ? fingers[0].globalX : fingers[0].localX;
              this.beginAdjust(x);
            }
          })
          .onActionUpdate((event: GestureEvent) => {
            this.updateAdjust(event.offsetY);
          })
          .onActionEnd(() => {
            this.endAdjust();
          })
      )
    }
    .hideTitleBar(true)
    .hideBackButton(true)
    .onBackPressed(() => {
      this.back();
      return true;
    })
  }

  private infoSourceName(): string {
    const source = SourceManager.shared().getVodSource(this.sourceKey);
    if (source === null) {
      return '';
    }
    return source.name;
  }

  private titleLabel(): string {
    if (this.title !== '') {
      return this.title;
    }
    return '播放中';
  }

  private sliderMaxValue(): number {
    if (this.sliderMax > 0) {
      return this.sliderMax;
    }
    return 100;
  }

  private epTextColor(ep: Episode): ResourceColor {
    if (ep.index === this.currentEp) {
      return Color.White;
    }
    return $r('app.color.color_text');
  }

  private epBgColor(ep: Episode): ResourceColor {
    if (ep.index === this.currentEp) {
      return $r('app.color.color_primary');
    }
    return $r('app.color.color_chip_bg');
  }

  private speedTextColor(opt: PlaybackSpeedOption): ResourceColor {
    if (opt.value === this.speedValue) {
      return Color.White;
    }
    return $r('app.color.color_text');
  }

  private speedBgColor(opt: PlaybackSpeedOption): ResourceColor {
    if (opt.value === this.speedValue) {
      return $r('app.color.color_primary');
    }
    return $r('app.color.color_chip_bg');
  }

  private timeLabel(): string {
    // 这个页面只放点播；时长要等 AVPlayer 报上来才准，那之前显示占位符，
    // 不要写「直播」——起播瞬间看到「01:07 / 直播」很容易误判成播错了源。
    const total: string = this.durationMs > 0 ? this.durationText : '--:--';
    return this.positionText + ' / ' + total;
  }

  private speedLabel(): string {
    for (const opt of AvPlayerController.SPEEDS) {
      if (opt.value === this.speedValue) {
        return '倍速 ' + opt.label;
      }
    }
    return '倍速 1.0x';
  }
}
