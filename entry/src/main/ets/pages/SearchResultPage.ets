/**
 * 搜索结果页：聚合多源结果、跨源同名合并、搜索历史
 */

import { TV_FOCUS } from '../common/TvFocus';
import { BackNavigation } from '../common/BackNavigation';
import { MergedVideo, RecommendItem } from '../model/Types';
import { SearchService } from '../model/SearchService';
import { SettingsStore } from '../data/SettingsStore';
import { HistoryStore } from '../data/HistoryStore';
import { Utils } from '../common/Utils';
import { pageBgGradient } from '../common/GlassTheme';
import { EmptyView, LoadingView } from '../components/CommonWidgets';
import { DetailPageParam } from './DetailPage';
import { latestNavParam } from '../common/NavParam';
import { SystemInsets } from '../common/SystemInsets';
import { BlurFade } from '../common/BlurFade';
import { DevicePolicy } from '../common/DevicePolicy';
import { TvPosterCard } from '../components/TvHomeCards';
import { TvFeedDataSource, TvFeedRow } from '../model/TvFeedDataSource';
import { SearchDiscovery } from '../model/SearchDiscovery';
import { PosterOrigin } from '../model/DiscoveryLayout';
import { PosterCardInfo, PosterCardData } from '../model/PosterCardData';
import { DiscoverySearchService } from '../data/DiscoverySearchService';

export interface SearchPageParam {
  keyword: string;
}

@Component
export struct SearchResultPage {
  navPathStack: NavPathStack = new NavPathStack();
  keyword: string = '';

  @State searchValue: string = '';
  @State results: MergedVideo[] = [];
  @State loading: boolean = false;
  @State searched: boolean = false;
  @State failedCount: number = 0;
  @State historyWords: string[] = [];
  private readonly tvResults: TvFeedDataSource = new TvFeedDataSource();
  private readonly selections: Map<string, MergedVideo> = new Map();
  private searchedAt: number = 0;
  private searchedKeyword: string = '';
  private searchGeneration: number = 0;
  private alive: boolean = false;

  /** 已经处理过的路由参数：缓存节点复用后靠它判断「这次是不是换了个关键词」 */
  private appliedKeyword: string = '';

  aboutToAppear(): void {
    this.alive = true;
    this.historyWords = HistoryStore.shared().getSearchHistory();
    if (this.keyword !== '') {
      this.appliedKeyword = this.keyword;
      this.searchValue = this.keyword;
      this.runSearch();
    }
  }

  aboutToDisappear(): void { this.alive = false; this.searchGeneration++; }

  private toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 });
  }

  private async runSearch(): Promise<void> {
    const wd = this.searchValue.trim();
    if (wd === '') {
      this.toast('请输入搜索关键词');
      return;
    }
    HistoryStore.shared().addSearchHistory(wd);
    this.historyWords = HistoryStore.shared().getSearchHistory();
    this.loading = true;
    this.searched = true;
    const request = ++this.searchGeneration;
    try {
      const res = await SearchService.aggregate(wd, SettingsStore.shared().get());
      if (!this.alive || request !== this.searchGeneration) return;
      this.results = res.merged.slice().sort((a: MergedVideo, b: MergedVideo): number => b.items.length - a.items.length);
      this.failedCount = res.failedCount;
      this.searchedAt = Date.now();
      this.searchedKeyword = wd;
      if (this.results.length > 0 || res.failedCount === 0) {
        DiscoverySearchService.remember(wd, SettingsStore.shared().get(), this.results, this.searchedAt);
      }
      this.selections.clear();
      for (const result of this.results) this.selections.set(SearchDiscovery.key(result), result);
      this.tvResults.setItems(this.results.map((result: MergedVideo) => SearchDiscovery.card(result)));
    } catch (e) {
      if (this.alive && request === this.searchGeneration) this.toast('搜索暂时失败，请重试');
    } finally {
      if (this.alive && request === this.searchGeneration) this.loading = false;
    }
  }

  private openDetail(v: MergedVideo, origin?: PosterOrigin): void {
    const first = v.items[0];
    if (first === undefined) {
      return;
    }
    if (DevicePolicy.isTV()) {
      this.navPathStack.pushPath({ name: 'Discovery', param: SearchDiscovery.entry(v,
        origin || { x: 40, y: 110, width: 185, height: 293 }, this.searchedAt, Date.now(), this.searchedKeyword) });
      return;
    }
    const p: DetailPageParam = {
      sourceKey: first.sourceKey,
      vodId: first.vodId,
      title: v.name
    };
    this.navPathStack.pushPath({ name: 'Detail', param: p });
  }

  private handleBack(): void {
    this.navPathStack.pop();
  }

  private posterInfo(key: string): PosterCardInfo {
    const result = this.selections.get(key);
    return result !== undefined ? SearchDiscovery.info(result) : PosterCardData.empty();
  }

  private subjectId(key: string): string {
    const result = this.selections.get(key);
    return result !== undefined ? SearchDiscovery.doubanId(result) : '';
  }

  @Builder
  private tvResultRow(row: TvFeedRow) {
    Row({ space: 18 }) {
      ForEach(row.items, (item: RecommendItem) => {
        Column({ space: 9 }) {
          TvPosterCard({ title: item.title, poster: item.cover, seriesHint: item.isTv,
            subjectId: this.subjectId(item.id), catalogueInfo: this.posterInfo(item.id),
            onOpen: (origin: PosterOrigin) => {
              const result = this.selections.get(item.id);
              if (result !== undefined) this.openDetail(result, origin);
            } })
          Text((this.selections.get(item.id)?.items.length || 0) + ' 个片源')
            .fontSize(12).fontColor('#A9B6C8').width('100%').padding({ left: 10 })
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }, (item: RecommendItem) => item.id)
      ForEach([0, 1, 2, 3, 4, 5].slice(row.items.length), (index: number) => { Blank().layoutWeight(1) })
    }.width('100%').alignItems(VerticalAlign.Top)
  }

  @Builder
  private tvSearch() {
    Column({ space: 0 }) {
      Row({ space: 16 }) {
        Stack() { Image($r('app.media.ic_back')).width(22).height(22) }
          .width(42).height(42).focusable(true).focusBox(TV_FOCUS).onClick(() => this.handleBack())
        Search({ placeholder: '搜索电影 / 电视剧', value: $$this.searchValue })
          .layoutWeight(1).height(42)
          .searchButton('搜索', { fontSize: 15, fontColor: '#F1D49A' })
          .onSubmit(() => { this.runSearch(); })
      }.width('100%').padding({ left: 30, right: 40, top: 24, bottom: 18 })
      if (this.loading) {
        Column() { LoadingView() }.width('100%').layoutWeight(1)
      } else if (!this.searched) {
        this.historyPanel()
      } else if (this.results.length === 0) {
        Column({ space: 12 }) {
          EmptyView({ emptyText: '没有找到相关视频' })
          if (this.failedCount > 0) Text(this.failedCount + ' 个源请求失败，可在视频源管理中检查')
            .fontSize(13).fontColor('#A9B6C8')
        }.width('100%').layoutWeight(1)
      } else {
        List({ space: 22 }) {
          LazyForEach(this.tvResults, (row: TvFeedRow) => {
            ListItem() {
              if (row.kind === 'header') {
                Row({ space: 16 }) {
                  Text('找到 ' + this.results.length + ' 部影片').fontSize(17).fontWeight(FontWeight.Medium).fontColor('#E8EDF6')
                  Text('选择影片查看介绍与播放资源').fontSize(13).fontColor('#93A2B8').layoutWeight(1)
                  if (this.failedCount > 0) Text(this.failedCount + ' 个源未响应').fontSize(12).fontColor('#D5B98B')
                }.width('100%')
              } else if (row.kind === 'posters') {
                this.tvResultRow(row)
              } else { Column().height(8) }
            }
          }, (row: TvFeedRow) => row.key)
        }.width('100%').layoutWeight(1).cachedCount(1).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Fade)
          .padding({ left: 40, right: 40, bottom: 24 })
      }
    }.width('100%').height('100%').backgroundColor('#0C111A')
  }

  build() {
    NavDestination() {
      if (DevicePolicy.isTV()) {
        this.tvSearch()
      } else {
      Stack({ alignContent: Alignment.Top }) {
        // 内容层铺满整屏：滚动内容会从下方玻璃导航条背后穿过
        Column({ space: 0 }) {

          if (this.loading) {
            LoadingView()
          } else if (!this.searched) {
            this.historyPanel()
          } else if (this.results.length === 0) {
            Column({ space: 8 }) {
              EmptyView({ emptyText: '没有找到相关视频' })
              if (this.failedCount > 0) {
                Text('有 ' + this.failedCount + ' 个源请求失败，可前往「视频源管理」检查')
                  .fontSize(12)
                  .fontColor($r('app.color.color_text_secondary'))
              }
            }
          } else {
            List({ space: 10 }) {
              ListItem() {
                Row() {
                  Text('共 ' + this.results.length + ' 个结果')
                    .fontSize(12)
                    .fontColor($r('app.color.color_text_secondary'))
                    .layoutWeight(1)
                  if (this.failedCount > 0) {
                    Text(this.failedCount + ' 个源失败')
                      .fontSize(12)
                      .fontColor($r('app.color.color_warning'))
                  }
                }
                .width('100%')
                .padding({ left: 0, right: 0, bottom: 6 })
              }
            // 顶部占位：随内容滚走，让列表能从玻璃导航条背后滑过
            ListItem() {
              Column()
                .width('100%')
                .height(56 + SystemInsets.top())
            }
                ForEach(this.results, (v: MergedVideo) => {
                  ListItem() {
                    Row({ space: 10 }) {
                      if (v.pic !== undefined && v.pic !== '') {
                        Image(v.pic)
                          .width(88)
                          .height(120)
                          .objectFit(ImageFit.Cover)
                          .borderRadius(8)
                          .backgroundColor($r('app.color.color_chip_bg'))
                      } else {
                        Column()
                          .width(88)
                          .height(120)
                          .backgroundColor($r('app.color.color_chip_bg'))
                          .borderRadius(8)
                      }
                      Column({ space: 6 }) {
                        Text(v.name)
                          .fontSize(15)
                          .fontWeight(FontWeight.Medium)
                          .fontColor($r('app.color.color_text'))
                          .maxLines(2)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .textAlign(TextAlign.Start)
                          .width('100%')
                        Row({ space: 6 }) {
                          if (v.year !== undefined && v.year !== '') {
                            Text(v.year)
                              .fontSize(11)
                              .fontColor($r('app.color.color_text_secondary'))
                          }
                          if (v.typeName !== undefined && v.typeName !== '') {
                            Text(v.typeName)
                              .fontSize(11)
                              .fontColor($r('app.color.color_text_secondary'))
                          }
                          if (v.area !== undefined && v.area !== '') {
                            Text(v.area)
                              .fontSize(11)
                              .fontColor($r('app.color.color_text_secondary'))
                          }
                        }
                        .width('100%')
                        if (v.remarks !== undefined && v.remarks !== '') {
                          Text(v.remarks)
                            .fontSize(11)
                            .fontColor($r('app.color.color_primary'))
                        }
                        Text(v.items.length + ' 个播放源')
                          .fontSize(11)
                          .fontColor($r('app.color.color_text_secondary'))
                      }
                      .layoutWeight(1)
                      .alignItems(HorizontalAlign.Start)
                    }
                    .width('100%')
                    .padding(10)
                    .backgroundColor($r('app.color.color_glass'))
                    .borderRadius(10)
                    .focusable(true)
                    .focusBox(TV_FOCUS)
                    .onClick(() => {
                      this.openDetail(v);
                    })
                  }
                }, (v: MergedVideo) => Utils.normalizeTitle(v.name) + '|' + (v.year !== undefined ? v.year : ''))
              }
              .layoutWeight(1)
              .scrollBar(BarState.Off)
              .padding({ left: 16, right: 16, bottom: 16 })
          }
        }
        .width('100%')
        .height('100%')
        .linearGradient(pageBgGradient())
        // 底色必须铺进状态栏/手势条：二级页面的内容让出了安全区，
        // 这一层不扩的话，状态栏里透出的是窗口默认底色，
        // 和页面渐变叠成两层，状态栏文字直接看不清。
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        // 顶部磨砂渐隐：内容从状态栏下面滚过时被这一段虚化，

        // 并且往下越来越清，看不到过渡区的边缘。

        BlurFade({ edge: 'top', band: SystemInsets.top() + 58, fade: 34, radius: 26 })


        // 玻璃导航条（方案 A）：浮在内容之上，可隐约看到背后滚动内容
          Row({ space: 8 }) {
            Row() {
              Image($r('app.media.ic_back'))
                .width(20)
                .height(20)
            }
            .width(32)
            .height(40)
            .justifyContent(FlexAlign.Center)
            .focusable(true)
            .focusBox(TV_FOCUS)
            .onClick(() => {
              this.handleBack();
            })
            Search({
              placeholder: '搜索电影 / 电视剧',
              value: $$this.searchValue
            })
              .layoutWeight(1)
              .height(36)
              .searchButton('搜索', { fontSize: 14, fontColor: $r('app.color.color_primary') })
              .onSubmit((value: string) => {
                this.runSearch();
              })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8 + SystemInsets.top(), bottom: 8 })
          .backgroundColor($r('app.color.color_nav_glass'))
          .backgroundEffect({ radius: 18, saturation: 1.6 })
          .border({ width: { bottom: 1 }, color: $r('app.color.color_nav_border') })
      }
      .width('100%')
      .height('100%')
      }
    }
    .hideTitleBar(true)
    .onBackPressed(() => {
      this.handleBack();
      return true;
    })
    .onShown(() => {
      this.alive = true;
      BackNavigation.register('Search', () => this.handleBack());
      this.historyWords = HistoryStore.shared().getSearchHistory();
      // Navigation 会复用缓存的 NavDestination 节点：换个关键词再搜时页面不会重建，
      // 必须自己取最新参数，否则看到的还是上一次的结果。
      const raw: Object | null = latestNavParam(this.navPathStack, 'Search');
      if (raw === null) {
        return;
      }
      const p: SearchPageParam = raw as SearchPageParam;
      if (p.keyword === '' || p.keyword === this.appliedKeyword) {
        return;
      }
      this.appliedKeyword = p.keyword;
      this.keyword = p.keyword;
      this.searchValue = p.keyword;
      this.results = [];
      this.failedCount = 0;
      this.searched = false;
      this.runSearch();
    })
  }

  @Builder
  historyPanel() {
    Column({ space: 12 }) {
      Row() {
        Text('搜索历史')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.color_text'))
          .layoutWeight(1)
        if (this.historyWords.length > 0) {
          Text('清空')
            .fontSize(13)
            .fontColor($r('app.color.color_text_secondary'))
            .padding({ left: 10, right: 10, top: 8, bottom: 8 })
            .focusable(true)
            .focusBox(TV_FOCUS)
            .onClick(() => {
              HistoryStore.shared().clearSearchHistory();
              this.historyWords = [];
            })
        }
      }
      .width('100%')

      if (this.historyWords.length === 0) {
        EmptyView({ emptyText: '输入关键词开始搜索' })
      } else {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.historyWords, (w: string) => {
            Text(w)
              .fontSize(13)
              .fontColor($r('app.color.color_text'))
              .backgroundColor($r('app.color.color_chip_bg'))
              .borderRadius(16)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .margin({ right: 8, bottom: 8 })
              .focusable(true)
              .focusBox(TV_FOCUS)
              .onClick(() => {
                this.searchValue = w;
                this.runSearch();
              })
          }, (w: string) => w)
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
      }
    }
    .layoutWeight(1)
    .padding({ left: 16, right: 16, top: 4 })
  }
}
