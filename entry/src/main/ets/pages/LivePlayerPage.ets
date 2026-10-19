/**
 * 直播播放页：M3U/FLV 直播流播放、节目单（EPG）、收藏
 * 直播流由 AVPlayer 原生刷新播放列表，不做本地重写
 */

import { window } from '@kit.ArkUI';
import { DevicePolicy } from '../common/DevicePolicy';
import { ScreenKeeper } from '../common/ScreenKeeper';
import { AvPlayerController } from '../player/AvPlayerController';
import { PlayUrlResolver } from '../player/PlayUrlResolver';
import { VideoSurface } from '../player/VideoSurface';
import { SourceManager } from '../data/SourceManager';
import { HistoryStore } from '../data/HistoryStore';
import { HttpClient } from '../net/HttpClient';
import { XmltvParser } from '../model/XmltvParser';
import { EpgProgramme } from '../model/Types';
import { Utils } from '../common/Utils';
import { LoadingView } from '../components/CommonWidgets';

export interface LivePlayerPageParam {
  channelUrl: string;
  channelName: string;
  sourceKey: string;
  sourceName: string;
  logo: string;
  tvgId: string;
}

@Component
export struct LivePlayerPage {
  navPathStack: NavPathStack = new NavPathStack();
  channelUrl: string = '';
  channelName: string = '';
  sourceKey: string = '';
  sourceName: string = '';
  logo: string = '';
  tvgId: string = '';

  private player: AvPlayerController = new AvPlayerController();
  private hideTimer: number = -1;
  private starting: boolean = false;
  private released: boolean = false;
  /** 加载圈延迟计时器，避免直播流抖动时红圈乱闪 */
  private loadingTimer: number = -1;
  private programmes: EpgProgramme[] = [];
  private channelIds: Map<string, string> = new Map<string, string>();

  @State playing: boolean = false;
  @State errorText: string = '';
  @State favorite: boolean = false;
  @State controlsVisible: boolean = true;
  @State epgNow: string = '';
  @State epgNext: string = '';
  @State landscape: boolean = false;
  /** 直播流真实分辨率（AVPlayer videoSizeChange 上报） */
  @State videoW: number = 0;
  @State videoH: number = 0;
  /** 播放器可视区（vp），随横竖屏变化 */
  @State canvasW: number = 0;
  @State canvasH: number = 0;
  /** 按原始比例算出的画面尺寸（vp），居中显示不拉伸 */
  @State displayW: number = 0;
  @State displayH: number = 0;
  /**
   * 画面铺满（裁切黑边）模式，与点播页同一套语义：
   * 保持比例、取较大的缩放，超出容器的部分出画，不变形。
   * 直播流常见 16:9，在更宽的平板/车机上会有左右黑边，铺满后能去掉。
   */
  @State fitCover: boolean = false;
  @State hasStarted: boolean = false;
  @State showLoading: boolean = true;
  /** 起播后真卡顿（缓冲持续超过 1.2 秒）时屏幕中央的加载圈 */
  @State stallLoading: boolean = false;
  private stallTimer: number = -1;
  /** 直播流播放进度采样：卡顿判定只看「进度是否还在前进」 */
  private lastPosMs: number = 0;
  private lastProgressAt: number = 0;
  /** 是否收到过进度回调；一次都没有的流无法判断卡顿，宁可不弹圈 */
  private progressSeen: boolean = false;

  aboutToAppear(): void {
    // 播放页存活期间保持屏幕常亮：平板全屏播放时系统休眠计时一到会直接黑屏锁屏
    ScreenKeeper.acquirePlayback();
    this.favorite = HistoryStore.shared().isLiveFavorite(this.channelUrl);
    this.loadEpg();
    this.bindCallbacks();
  }

  aboutToDisappear(): void {
    ScreenKeeper.releasePlayback();
    this.clearStall();
    // 不管从哪个入口离开都要把方向交还给系统、复原窗口布局。
    // 不能用 setLandscape(false)：那会把主窗口锁死在 PORTRAIT，
    // 回到首页后整个 APP 不再跟随平板旋转（"偶尔转不动"的根因）。
    this.landscape = false;
    this.restoreRotation();
    this.applyWindowFullScreen(false);
    this.release();
  }

  /**
   * 起播后卡顿判定：只在「播放进度连续 1 秒没有前进」时才弹加载圈。
   *
   * 早期版本判据是 `this.buffering`，直播必然误报：直播是滑动窗口，
   * BUFFERING_PERCENT 几乎永远到不了 100，于是任何一次 bufferingUpdate
   * 都会让 1.2 秒后弹出「缓冲中」；而直播页又没有进度回调去清它、
   * 播放状态也不再变化 —— 加载圈从此一直挂着。
   * 症状正是「画面正常播放，中央却一直转圈」。
   *
   * 改为采样进度后，只要 timeUpdate 还在前进就会立刻收圈（见 onProgress），
   * 真卡住才会留下。
   */
  private scheduleStallCheck(): void {
    if (this.stallTimer >= 0 || this.released) {
      return;
    }
    // 一次进度都没收到过（个别流不报 timeUpdate）：无法判断，不出圈更安全
    if (!this.progressSeen) {
      return;
    }
    this.stallTimer = setTimeout(() => {
      this.stallTimer = -1;
      if (this.released || !this.hasStarted) {
        return;
      }
      // 距离上次进度前进已超过 1 秒 = 真的卡住了
      if (Date.now() - this.lastProgressAt >= 1000) {
        this.stallLoading = true;
      }
    }, 1200);
  }

  private clearStall(): void {
    if (this.stallTimer >= 0) {
      clearTimeout(this.stallTimer);
      this.stallTimer = -1;
    }
    this.stallLoading = false;
  }

  private toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 });
  }

  private bindCallbacks(): void {
    // 直播流同样会上报 timeUpdate。进度在走就说明画面在正常播放，
    // 这是「缓冲中」误显示的唯一可靠解药：只要进度前进，立刻收圈并取消预约检查。
    this.player.onProgress = (positionMs: number) => {
      if (positionMs <= this.lastPosMs) {
        return;
      }
      this.lastPosMs = positionMs;
      this.lastProgressAt = Date.now();
      this.progressSeen = true;
      // 进度都动了，必然已起播：兜住个别机型不发 playing 状态的情况
      this.hasStarted = true;
      if (this.showLoading) {
        this.showLoading = false;
        this.clearLoadingTimer();
      }
      if (this.stallTimer >= 0 || this.stallLoading) {
        this.clearStall();
      }
    };
    this.player.onPlayStateChanged = (playing: boolean) => {
      this.playing = playing;
      this.showLoading = false;
      this.clearLoadingTimer();
      // 播放状态已经明确变化（含用户手动暂停）：旧的卡顿判定作废，
      // 否则「卡顿中按暂停」会让加载圈一直挂着不走。
      this.clearStall();
      if (playing) {
        this.hasStarted = true;
        this.scheduleHideControls();
      }
    };
    this.player.onError = (message: string) => {
      // 播放器内核给出的是通用文案，这里转成直播语境、用户能看懂的说法
      if (message.indexOf('获取失败') >= 0) {
        this.errorText = '直播源数据获取超时，请稍后重试';
      } else if (message.indexOf('格式不支持') >= 0) {
        this.errorText = '该频道的直播流无法播放，请换台';
      } else if (message.indexOf('暂时无法播放') >= 0) {
        this.errorText = '该频道数据暂不可用，请稍后重试';
      } else {
        this.errorText = message;
      }
      this.showLoading = false;
      this.clearLoadingTimer();
      this.clearStall();
    };
    this.player.onBuffering = (percent: number) => {
      if (percent >= 100) {
        this.clearLoadingTimer();
        this.showLoading = false;
        return;
      }
      if (!this.hasStarted) {
        this.showLoading = true;
        return;
      }
      // 直播流水位几乎永远 <100%，绝不能按水位直接弹圈 ——
      // 那正是「画面正常播放，中央一直转圈」的成因。
      // 这里只做「预约」，真正的判据是播放进度是否停摆（见 scheduleStallCheck）。
      if (this.playing) {
        this.scheduleStallCheck();
      }
    };
    // 拿到直播流真实分辨率后重算等比尺寸，避免画面被拉扁
    this.player.onVideoSize = (width: number, height: number) => {
      this.videoW = width;
      this.videoH = height;
      this.updateSurfaceSize();
    };
  }

  private async loadEpg(): Promise<void> {
    const source = SourceManager.shared().getLiveSource(this.sourceKey);
    if (source === null || source.epg === undefined || source.epg === '') {
      return;
    }
    const res = await HttpClient.getBytes(source.epg, { 'User-Agent': HttpClient.UA }, 12000);
    if (!res.ok || res.text === '') {
      return;
    }
    const parsed = XmltvParser.parse(res.text);
    this.programmes = parsed.programmes;
    this.channelIds = parsed.channels;
    this.refreshEpgText();
  }

  private refreshEpgText(): void {
    const id = XmltvParser.matchChannelId(this.channelIds, this.tvgId, this.channelName);
    if (id === '') {
      return;
    }
    const nn = XmltvParser.nowNext(this.programmes, id, Date.now());
    if (nn.current !== undefined) {
      this.epgNow = nn.current.title + '（' + Utils.formatTime(nn.current.start) + ' - ' + Utils.formatTime(nn.current.stop) + '）';
    }
    if (nn.next !== undefined) {
      this.epgNext = '即将播放：' + nn.next.title;
    }
  }

  private onSurfaceReady(surfaceId: string): void {
    // 与点播页一致：先让内容区变成整屏，再切横屏
    this.applyWindowFullScreen(true);
    this.setLandscape(true);
    this.player.create(surfaceId).then((ok: boolean) => {
      if (ok) {
        this.startPlay();
      }
    });
  }

  private async startPlay(): Promise<void> {
    if (this.starting || this.released) {
      return;
    }
    this.starting = true;
    this.errorText = '';
    this.hasStarted = false;
    this.showLoading = true;
    this.clearLoadingTimer();
    // 换台/重试：进度采样归零。否则上一路流已经跑到的较大进度会让新流的
    // 小进度永远不满足「比上次大」，卡顿检测与收圈路径全部失效。
    this.lastPosMs = 0;
    this.lastProgressAt = 0;
    this.progressSeen = false;
    this.clearStall();
    const headers = PlayUrlResolver.headersFor(this.channelUrl);
    await this.player.playUrl(this.channelUrl, headers, 0);
    this.starting = false;
  }

  private togglePlay(): void {
    this.player.toggle();
    this.controlsVisible = true;
    this.scheduleHideControls();
  }

  private toggleFav(): void {
    const now = HistoryStore.shared().toggleLiveFavorite(this.channelUrl);
    this.favorite = now;
    this.toast(now ? '已收藏该频道' : '已取消收藏');
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

  private release(): void {
    if (this.released) {
      return;
    }
    this.released = true;
    this.player.release();
    if (this.hideTimer >= 0) {
      clearTimeout(this.hideTimer);
      this.hideTimer = -1;
    }
  }

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
   * 按直播流原始宽高比，在可视区内算出「最大且不变形」的画面尺寸。
   * AVPlayer 直接把画面渲染到 XComponent 的 Surface 上，Surface 比例和视频不一致就会拉伸，
   * 所以必须由这里控制 Surface 尺寸，再由外层 Stack 居中。
   */
  private updateSurfaceSize(): void {
    if (this.canvasW <= 0 || this.canvasH <= 0) {
      return;
    }
    if (this.videoW <= 0 || this.videoH <= 0) {
      this.displayW = this.canvasW;
      this.displayH = this.canvasH;
      return;
    }
    const videoRatio: number = this.videoW / this.videoH;
    const canvasRatio: number = this.canvasW / this.canvasH;
    if (this.fitCover) {
      // 铺满（裁切）：保持比例取较大缩放，超出容器的部分出画。
      // 画面不变形，只是左右或上下裁掉一点 —— 与点播页 PlayerPage 算法一致。
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
      this.displayW = this.canvasW;
      this.displayH = this.canvasW / videoRatio;
    } else {
      this.displayH = this.canvasH;
      this.displayW = this.canvasH * videoRatio;
    }
  }

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
        win.setPreferredOrientation(window.Orientation.PORTRAIT);
      }
    }).catch(() => {
      // ignore
    });
  }

  /**
   * 离开播放页时把屏幕方向交还给系统。
   * setPreferredOrientation 作用在主窗口上，是全局且跨页面持久的：
   * 只要这里锁了 PORTRAIT，回到首页后整个 APP 就不再跟随平板旋转，
   * 只能杀进程重开 —— 与点播 PlayerPage 同一条纪律。
   */
  private restoreRotation(): void {
    // 交还给「设备策略默认方向」：普通手机回竖屏，平板/折叠机回跟随旋转
    DevicePolicy.suppressed = false;
    DevicePolicy.applyDefault();
  }

  private back(): void {
    // 返回键属于「离开页面」：把方向交还系统，而不是锁竖屏
    this.restoreRotation();
    this.navPathStack.pop();
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Center }) {
        // 画面尺寸由 updateSurfaceSize 按原始宽高比算出，居中的事交给外层 Stack
        VideoSurface({
          surfaceWidth: this.displayW,
          surfaceHeight: this.displayH,
          onSurfaceReady: (surfaceId: string) => {
            this.onSurfaceReady(surfaceId);
          },
          onSurfaceDestroy: () => {}
        })

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

        if ((this.showLoading || this.stallLoading) && this.errorText === '') {
          // 黑底上用白色圈，别用主题红
          Column({ space: 10 }) {
            LoadingProgress()
              .width(40)
              .height(40)
              .color(Color.White)
              .opacity(0.9)
            Text('缓冲中…')
              .fontSize(12)
              .fontColor('#CCCCCC')
          }
        }
        if (this.errorText !== '') {
          Column({ space: 12 }) {
            Text(this.errorText)
              .fontSize(14)
              .fontColor(Color.White)
              .textAlign(TextAlign.Center)
              .maxLines(3)
            // 「返回」让用户能退出重试循环：频道挂了时只给重试会陷入
            // 重试 -> 瞬间失败 -> 再弹窗 的死循环
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

        if (this.controlsVisible && this.errorText === '') {
          Column({ space: 0 }) {
            Row({ space: 10 }) {
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
                Text(this.channelName)
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Color.White)
                  .maxLines(1)
                Text(this.sourceName)
                  .fontSize(11)
                  .fontColor('#CCCCCC')
                  .maxLines(1)
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              Stack({ alignContent: Alignment.Center }) {
                Image(this.favorite ? $r('app.media.ic_player_star_filled') : $r('app.media.ic_player_star'))
                  .width(19)
                  .height(19)
                  .fillColor(this.favorite ? $r('app.color.color_primary') : $r('app.color.color_text'))
              }
              .width(34)
              .height(34)
              .borderRadius(17)
              .backgroundColor($r('app.color.color_player_scrim'))
              .onClick(() => {
                this.toggleFav();
              })
              Stack({ alignContent: Alignment.Center }) {
                Image($r('app.media.ic_player_refresh'))
                  .width(19)
                  .height(19)
                  .fillColor($r('app.color.color_text'))
              }
              .width(34)
              .height(34)
              .borderRadius(17)
              .backgroundColor($r('app.color.color_player_scrim'))
              .onClick(() => {
                this.startPlay();
              })
              // 与点播页一致：横屏下提供「铺满屏 / 适应屏」切换，
              // 16:9 直播流在更宽的平板上会留左右黑边，铺满后能去掉
              if (this.canvasW > this.canvasH) {
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
                this.setLandscape(!this.landscape);
              })
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 14 })

            // 中部按钮：加载阶段不显示三角，只有「起播过且当前暂停」才出现
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

            Column({ space: 4 }) {
              if (this.epgNow !== '') {
                Text('正在播放：' + this.epgNow)
                  .fontSize(12)
                  .fontColor('#EEEEEE')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                  .textAlign(TextAlign.Start)
              }
              if (this.epgNext !== '') {
                Text(this.epgNext)
                  .fontSize(11)
                  .fontColor('#BBBBBB')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                  .textAlign(TextAlign.Start)
              }
              Text(this.favorite ? '已收藏' : '点击 ☆ 收藏频道')
                .fontSize(11)
                .fontColor('#BBBBBB')
                .width('100%')
                .textAlign(TextAlign.Start)
            }
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 20 })
          }
          .width('100%')
          .height('100%')
          .backgroundColor('#00000099')
          .padding({ top: 26, bottom: 22 })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Black)
      // 横竖屏切换会改变可视区，每次都按原始比例重算一次
      .onAreaChange((oldValue: Area, newValue: Area) => {
        const w: number = this.areaNumber(newValue.width);
        const h: number = this.areaNumber(newValue.height);
        if (w > 0 && h > 0 && (w !== this.canvasW || h !== this.canvasH)) {
          this.canvasW = w;
          this.canvasH = h;
          // 切回竖屏必须退出「铺满」：16:9 的流铺进竖屏会被裁到只剩中间一条，
          // 而竖屏下按钮是隐藏的，用户没有退路。
          if (this.fitCover && w <= h) {
            this.fitCover = false;
          }
          this.updateSurfaceSize();
        }
      })
    }
    .hideTitleBar(true)
    .hideBackButton(true)
    .onBackPressed(() => {
      this.back();
      return true;
    })
  }
}
