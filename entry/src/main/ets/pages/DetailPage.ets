/**
 * 视频详情页：简介 / 选集 / 播放 / 收藏 / 换源测速 / 下载
 */

import { CmsClient } from '../model/CmsClient';
import { DetailCache } from '../model/DetailCache';
import { SearchService } from '../model/SearchService';
import { SourceManager } from '../data/SourceManager';
import { HistoryStore } from '../data/HistoryStore';
import { SettingsStore } from '../data/SettingsStore';
import { DownloadManager } from '../data/DownloadManager';
import { VideoDetail, Episode, SpeedTestItem, PlayRecord, PlayLine } from '../model/Types';
import { Utils } from '../common/Utils';
import { LoadingView, TagText } from '../components/CommonWidgets';
import { NetImage } from '../components/NetImage';
import { PlayerPageParam } from './PlayerPage';

export interface DetailPageParam {
  sourceKey: string;
  vodId: string;
  title: string;
}

@Component
export struct DetailPage {
  navPathStack: NavPathStack = new NavPathStack();
  sourceKey: string = '';
  vodId: string = '';
  title: string = '';

  @State loading: boolean = true;
  @State errorText: string = '';
  @State ready: boolean = false;
  @State infoTitle: string = '';
  @State infoCover: string = '';
  @State infoDesc: string = '';
  @State infoYear: string = '';
  @State infoArea: string = '';
  @State infoType: string = '';
  @State infoDirector: string = '';
  @State infoActor: string = '';
  @State infoRemarks: string = '';
  @State infoSourceName: string = '';
  @State episodes: Episode[] = [];
  /** 多线路（vod_play_from 按 $$$ 分组）；只有 1 条线路时不显示选择区 */
  @State lines: PlayLine[] = [];
  @State currentLine: number = 0;
  @State currentEp: number = 0;
  @State favorite: boolean = false;
  @State descExpanded: boolean = false;
  @State progress: PlayRecord | null = null;
  @State speedItems: SpeedTestItem[] = [];
  @State speedTesting: boolean = false;
  @State showSpeedPanel: boolean = false;

  aboutToAppear(): void {
    this.favorite = HistoryStore.shared().isFavorite(this.sourceKey, this.vodId);
    this.loadDetail(this.sourceKey, this.vodId);
  }

  private toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 });
  }

  private applyDetail(detail: VideoDetail): void {
    this.ready = true;
    this.errorText = '';
    // 写入缓存供播放页复用，避免播放页重复请求被源站限流
    DetailCache.put(this.sourceKey, this.vodId, detail);
    this.infoTitle = detail.info.title;
    this.infoCover = detail.info.cover !== undefined ? detail.info.cover : '';
    // 顺手给历史记录补封面：用户从「继续观看」进来或直接搜进来都能覆盖到
    if (this.infoCover !== '') {
      HistoryStore.shared().setPicIfEmpty(this.sourceKey, this.vodId, this.infoCover);
    }
    // 源站简介是富文本（<p>&nbsp;…），直接显示会出现一堆非中文符号，必须清洗
    const desc = Utils.stripHtml(detail.info.desc !== undefined ? detail.info.desc : '');
    this.infoDesc = Utils.hasMeaningfulText(desc) ? desc : '';
    this.infoYear = detail.info.year !== undefined ? detail.info.year : '';
    this.infoArea = detail.info.area !== undefined ? detail.info.area : '';
    this.infoType = detail.info.typeName !== undefined ? detail.info.typeName : '';
    this.infoDirector = Utils.stripHtml(detail.info.director !== undefined ? detail.info.director : '');
    this.infoActor = Utils.stripHtml(detail.info.actor !== undefined ? detail.info.actor : '');
    this.infoRemarks = Utils.stripHtml(detail.info.remarks !== undefined ? detail.info.remarks : '');
    this.infoSourceName = detail.info.sourceName;
    this.episodes = detail.episodes;
    this.lines = detail.info.lines !== undefined ? detail.info.lines : [];
    this.currentLine = 0;
  }

  private async loadDetail(sourceKey: string, vodId: string): Promise<void> {
    const source = SourceManager.shared().getVodSource(sourceKey);
    if (source === null) {
      this.errorText = '视频源不存在，可能已被删除';
      this.loading = false;
      return;
    }
    this.loading = true;
    this.errorText = '';
    let detail: VideoDetail | null = null;
    try {
      detail = await CmsClient.detail(source, vodId);
    } catch (e) {
      detail = null;
    }
    if (detail === null || detail.episodes.length === 0) {
      // 接口无播放地址时爬详情页 HTML 兜底
      try {
        detail = await CmsClient.detailFromPage(source, vodId);
      } catch (e2) {
        detail = null;
      }
    }
    this.loading = false;
    if (detail === null || detail.episodes.length === 0) {
      this.ready = false;
      this.errorText = '获取详情失败，该源可能暂时不可用';
      return;
    }
    this.sourceKey = sourceKey;
    this.vodId = vodId;
    this.applyDetail(detail);
    const rec = HistoryStore.shared().getProgress(sourceKey, vodId);
    this.progress = rec;
    // 记忆了播放线路且该线路的集数仍有效：切换到该线路再恢复集数
    if (rec !== null && rec.lineIndex !== undefined && rec.lineIndex > 0 &&
        rec.lineIndex < this.lines.length && rec.episode >= 0 &&
        rec.episode < this.lines[rec.lineIndex].episodes.length) {
      this.currentLine = rec.lineIndex;
      this.episodes = this.lines[rec.lineIndex].episodes;
      this.currentEp = rec.episode;
    } else if (rec !== null && rec.episode >= 0 && rec.episode < this.episodes.length) {
      this.currentEp = rec.episode;
    } else {
      this.currentEp = 0;
    }
    SourceManager.shared().recordSuccess(sourceKey);
  }

  /** 切换播放线路：只换分集列表，不自动起播 */
  private selectLine(idx: number): void {
    if (idx < 0 || idx >= this.lines.length || idx === this.currentLine) {
      return;
    }
    this.currentLine = idx;
    this.episodes = this.lines[idx].episodes;
    this.currentEp = 0;
  }

  private playEpisode(idx: number): void {
    if (idx < 0 || idx >= this.episodes.length) {
      return;
    }
    let position = 0;
    if (this.progress !== null && this.progress.episode === idx) {
      position = this.progress.positionMs;
    }
    const p: PlayerPageParam = {
      sourceKey: this.sourceKey,
      vodId: this.vodId,
      episode: idx,
      episodeName: this.episodes[idx].name,
      title: this.infoTitle,
      positionMs: position,
      offlineDir: '',
      // 直接带上播放地址，播放器无需再次请求详情（避免被源站限流）
      episodeUrl: this.episodes[idx].url,
      lineIndex: this.currentLine,
      // 带上封面，播放页写历史记录时可直接用，首页「继续观看」才有图
      pic: this.infoCover
    };
    this.navPathStack.pushPath({ name: 'Player', param: p });
  }

  private toggleFav(): void {
    const now = HistoryStore.shared().toggleFavorite({
      sourceKey: this.sourceKey,
      vodId: this.vodId,
      name: this.infoTitle,
      pic: this.infoCover !== '' ? this.infoCover : undefined,
      sourceName: this.infoSourceName,
      createdAt: Date.now()
    });
    this.favorite = now;
    this.toast(now ? '已收藏' : '已取消收藏');
  }

  private async runSpeedTest(): Promise<void> {
    if (this.infoTitle === '') {
      return;
    }
    this.speedTesting = true;
    this.showSpeedPanel = true;
    const items = await SearchService.speedTest(this.infoTitle, this.sourceKey, SettingsStore.shared().get());
    this.speedItems = items;
    this.speedTesting = false;
  }

  private async switchSource(item: SpeedTestItem): Promise<void> {
    if (!item.ok) {
      this.toast('该源当前不可用');
      return;
    }
    if (item.vodId === undefined || item.vodId === '') {
      this.toast('无法获取该源的视频信息');
      return;
    }
    this.showSpeedPanel = false;
    this.toast('正在切换到「' + item.sourceName + '」');
    await this.loadDetail(item.sourceKey, item.vodId);
  }

  private downloadCurrent(): void {
    if (this.currentEp < 0 || this.currentEp >= this.episodes.length) {
      return;
    }
    const id = DownloadManager.shared().start(
      this.sourceKey,
      this.vodId,
      this.infoTitle,
      this.infoCover !== '' ? this.infoCover : undefined,
      this.infoSourceName,
      this.currentEp,
      this.episodes[this.currentEp].name,
      this.episodes[this.currentEp].url
    );
    if (id === '') {
      this.toast('该集已在下载列表中');
    } else {
      this.toast('已加入下载：' + this.episodes[this.currentEp].name);
    }
  }

  private progressPercent(): string {
    const rec = this.progress;
    if (rec === null || rec.durationMs <= 0 || rec.episode !== this.currentEp) {
      return '';
    }
    const pct = Math.floor((rec.positionMs / rec.durationMs) * 100);
    if (pct <= 0 || pct >= 100) {
      return '';
    }
    return pct + '%';
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

  private descMaxLines(): number {
    if (this.descExpanded) {
      return 100;
    }
    return 3;
  }

  private descToggleLabel(): string {
    if (this.descExpanded) {
      return '收起';
    }
    return '展开';
  }

  private errorLabel(): string {
    if (this.errorText !== '') {
      return this.errorText;
    }
    return '加载失败';
  }

  private navTitle(): string {
    if (this.infoTitle !== '') {
      return this.infoTitle;
    }
    return '详情';
  }

  private playLabel(): string {
    const rec = this.progress;
    if (rec !== null && rec.episode === this.currentEp && rec.positionMs > 5000) {
      return '续播 ' + Utils.formatTime(rec.positionMs);
    }
    return '播放';
  }

  build() {
    NavDestination() {
      Column({ space: 0 }) {
        // 自绘标题栏：不能在 NavDestination 上用 .title()。窗口开启全屏布局后，
        // 框架把状态栏高度从标题栏高度里扣掉，实测 TitleBar 只剩 63px（196-133），
        // 文字与返回键被压扁并与状态栏重叠。故统一隐藏内置栏、自己画一条。
        Row({ space: 8 }) {
          Row() {
            Image($r('app.media.ic_back'))
              .width(20)
              .height(20)
          }
          .width(36)
          .height(40)
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.navPathStack.pop();
          })
          Text(this.navTitle())
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.color_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .textAlign(TextAlign.Start)
        }
        .width('100%')
        .height(48)
        .padding({ left: 8, right: 16 })

      Stack({ alignContent: Alignment.Bottom }) {
        if (this.loading) {
          LoadingView()
        } else if (!this.ready) {
          Column({ space: 12 }) {
            Text(this.errorLabel())
              .fontSize(14)
              .fontColor($r('app.color.color_text_secondary'))
            Button('重试')
              .fontSize(14)
              .backgroundColor($r('app.color.color_primary'))
              .onClick(() => {
                this.loadDetail(this.sourceKey, this.vodId);
              })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          this.detailBody()
        }

        // 换源面板
        if (this.showSpeedPanel) {
          Column({ space: 10 }) {
            Row({ space: 8 }) {
              Text('选择播放源')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.color_text'))
                .layoutWeight(1)
              Text('关闭')
                .fontSize(13)
                .fontColor($r('app.color.color_primary'))
                .onClick(() => {
                  this.showSpeedPanel = false;
                })
            }
            .width('100%')

            if (this.speedTesting) {
              LoadingView({ tipText: '正在测速…' }).height(120)
            } else if (this.speedItems.length === 0) {
              Text('没有其他可用源')
                .fontSize(13)
                .fontColor($r('app.color.color_text_secondary'))
            } else {
              List({ space: 8 }) {
                ForEach(this.speedItems, (item: SpeedTestItem) => {
                  ListItem() {
                    Row({ space: 8 }) {
                      Text(item.sourceName)
                        .fontSize(14)
                        .fontColor($r('app.color.color_text'))
                        .layoutWeight(1)
                        .maxLines(1)
                      if (item.ok) {
                        Text(item.latencyMs + ' ms')
                          .fontSize(12)
                          .fontColor($r('app.color.color_success'))
                        Text(item.episodeCount + ' 集')
                          .fontSize(12)
                          .fontColor($r('app.color.color_text_secondary'))
                      } else {
                        Text('不可用')
                          .fontSize(12)
                          .fontColor($r('app.color.color_warning'))
                      }
                    }
                    .width('100%')
                    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
                    .backgroundColor($r('app.color.color_chip_bg'))
                    .borderRadius(8)
                    .onClick(() => {
                      this.switchSource(item);
                    })
                  }
                }, (item: SpeedTestItem) => item.sourceKey)
              }
              .height(220)
              .scrollBar(BarState.Off)
            }
          }
          .width('100%')
          .padding(16)
          .backgroundColor($r('app.color.color_card'))
          .borderRadius({ topLeft: 16, topRight: 16 })
        }
      }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor($r('app.color.color_bg'))
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .onShown(() => {
      // 从播放页返回时刷新进度与收藏态
      this.favorite = HistoryStore.shared().isFavorite(this.sourceKey, this.vodId);
      this.progress = HistoryStore.shared().getProgress(this.sourceKey, this.vodId);
    })
  }

  @Builder
  detailBody() {
    Scroll() {
      Column({ space: 12 }) {
        // 头部：海报 + 信息
        Row({ space: 12 }) {
          if (this.infoCover !== '') {
            Stack({ alignContent: Alignment.BottomStart }) {
              NetImage({ url: this.infoCover })
                .width(112)
                .height(158)
                .borderRadius(10)
              if (this.progressPercent() !== '') {
                Column()
                  .width(this.progressPercent())
                  .height(3)
                  .backgroundColor($r('app.color.color_primary'))
              }
            }
          } else {
            Column()
              .width(112)
              .height(158)
              .backgroundColor($r('app.color.color_chip_bg'))
              .borderRadius(10)
          }
          Column({ space: 6 }) {
            Text(this.infoTitle)
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.color_text'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.Start)
              .width('100%')
            Row({ space: 6 }) {
              if (this.infoYear !== '') {
                TagText({ tagText: this.infoYear })
              }
              if (this.infoArea !== '') {
                TagText({ tagText: this.infoArea })
              }
              if (this.infoType !== '') {
                TagText({ tagText: this.infoType })
              }
            }
            if (this.infoRemarks !== '') {
              Text(this.infoRemarks)
                .fontSize(12)
                .fontColor($r('app.color.color_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
                .textAlign(TextAlign.Start)
            }
            Text('来源：' + this.infoSourceName)
              .fontSize(12)
              .fontColor($r('app.color.color_text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .textAlign(TextAlign.Start)
            if (this.infoDirector !== '') {
              Text('导演：' + this.infoDirector)
                .fontSize(12)
                .fontColor($r('app.color.color_text_secondary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
                .textAlign(TextAlign.Start)
            }
            if (this.infoActor !== '') {
              Text('主演：' + this.infoActor)
                .fontSize(12)
                .fontColor($r('app.color.color_text_secondary'))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
                .textAlign(TextAlign.Start)
            }
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding({ left: 16, right: 16 })

        // 操作栏
        Row({ space: 8 }) {
          Button() {
            Row({ space: 6 }) {
              Image($r('app.media.ic_play'))
                .width(18)
                .height(18)
              Text(this.playLabel())
                .fontSize(15)
                .fontColor(Color.White)
            }
            .justifyContent(FlexAlign.Center)
          }
          .layoutWeight(1)
          .height(42)
          .backgroundColor($r('app.color.color_primary'))
          .borderRadius(21)
          .onClick(() => {
            this.playEpisode(this.currentEp);
          })

          Button() {
            if (this.favorite) {
              Image($r('app.media.ic_star_filled'))
                .width(20)
                .height(20)
            } else {
              Image($r('app.media.ic_star'))
                .width(20)
                .height(20)
            }
          }
          .width(42)
          .height(42)
          .backgroundColor($r('app.color.color_card'))
          .borderRadius(21)
          .onClick(() => {
            this.toggleFav();
          })

          Button() {
            Image($r('app.media.ic_refresh'))
              .width(20)
              .height(20)
          }
          .width(42)
          .height(42)
          .backgroundColor($r('app.color.color_card'))
          .borderRadius(21)
          .onClick(() => {
            this.runSpeedTest();
          })

          Button() {
            // 这张资源实际是「箭头朝上 + 底线」的上传图形，
            // 下载按钮需要箭头朝下，直接旋转 180° 即可（同一份资源镜像成立）。
            Image($r('app.media.ic_download'))
              .width(20)
              .height(20)
              .rotate({ angle: 180 })
          }
          .width(42)
          .height(42)
          .backgroundColor($r('app.color.color_card'))
          .borderRadius(21)
          .onClick(() => {
            this.downloadCurrent();
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })

        // 简介
        if (this.infoDesc !== '') {
          Column({ space: 4 }) {
            Text(this.infoDesc)
              .fontSize(13)
              .fontColor($r('app.color.color_text_secondary'))
              .maxLines(this.descMaxLines())
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.Start)
              .width('100%')
              .copyOption(CopyOptions.LocalDevice)
            Text(this.descToggleLabel())
              .fontSize(12)
              .fontColor($r('app.color.color_primary'))
              .width('100%')
              .textAlign(TextAlign.RIGHT)
              .onClick(() => {
                this.descExpanded = !this.descExpanded;
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .alignItems(HorizontalAlign.Start)
        }

        // 播放线路（源站返回多条线路时才显示）
        if (this.lines.length > 1) {
          Column({ space: 8 }) {
            Text('播放线路')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.color_text'))
              .textAlign(TextAlign.Start)
              .width('100%')
            Scroll() {
              Row({ space: 8 }) {
                ForEach(this.lines, (line: PlayLine, idx: number) => {
                  Text(line.name + '（' + line.episodes.length + '集）')
                    .fontSize(13)
                    .fontColor(idx === this.currentLine ? Color.White : $r('app.color.color_text'))
                    .backgroundColor(idx === this.currentLine
                      ? $r('app.color.color_primary')
                      : $r('app.color.color_chip_bg'))
                    .borderRadius(14)
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .onClick(() => {
                      this.selectLine(idx);
                    })
                }, (line: PlayLine, idx: number) => idx.toString() + '_' + line.name)
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .alignItems(HorizontalAlign.Start)
        }

        // 选集
        Column({ space: 8 }) {
          Text('选集（共 ' + this.episodes.length + ' 集）')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.color_text'))
            .textAlign(TextAlign.Start)
            .width('100%')

          Grid() {
            ForEach(this.episodes, (ep: Episode) => {
              GridItem() {
                Text(ep.name)
                  .fontSize(13)
                  .fontColor(this.epTextColor(ep))
                  .backgroundColor(this.epBgColor(ep))
                  .borderRadius(8)
                  .width('100%')
                  .height(36)
                  .textAlign(TextAlign.Center)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .onClick(() => {
                    this.currentEp = ep.index;
                    this.playEpisode(ep.index);
                  })
              }
            }, (ep: Episode) => ep.index.toString())
          }
          .columnsTemplate('1fr 1fr 1fr 1fr')
          .columnsGap(8)
          .rowsGap(8)
          .width('100%')
        }
        .padding({ left: 16, right: 16, bottom: 24 })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ top: 8 })
      // 关键：内容不满一屏时 Scroll 会把子内容垂直居中（实测 Column 落在 y=834，
      // 而 Scroll 视口顶部是 y=196，正好等于 (2652-1376)/2），表现为「顶部大片空白」。
      // minHeight 撑满视口即可强制顶对齐；内容超长时照常滚动。
      .constraintSize({ minHeight: '100%' })
    }
    .scrollBar(BarState.Off)
    // Scroll 直接嵌在 Stack 里：Stack 的子组件不支持 layoutWeight，
    // 必须显式给宽高，否则高度塌陷为内容高度，顶部留出大片空白。
    .width('100%')
    .height('100%')
  }
}
