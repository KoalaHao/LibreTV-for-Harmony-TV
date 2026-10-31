import { RecommendItem, MergedVideo, SearchItem } from '../model/Types';
import { curves } from '@kit.ArkUI';
import { SourceQuality } from '../model/SourceQuality';
import { PosterCardData, PosterCardInfo } from '../model/PosterCardData';
import { DiscoveryLayout, DiscoveryColumns, PosterOrigin } from '../model/DiscoveryLayout';
import { DiscoverySearchSession, DiscoverySearchState } from '../model/DiscoverySearchSession';
import { PosterMetadataService } from '../data/PosterMetadataService';
import { SettingsStore } from '../data/SettingsStore';
import { TvPosterCard } from '../components/TvHomeCards';
import { TV_FOCUS } from '../common/TvFocus';
import { BackNavigation } from '../common/BackNavigation';
import { latestNavParam } from '../common/NavParam';
import { PlayerPageParam } from './PlayerPage';
import { DetailCache } from '../model/DetailCache';
import { DiscoveryPlayback } from '../model/DiscoveryPlayback';
import { CmsClient } from '../model/CmsClient';
import { SourceManager } from '../data/SourceManager';
import { HistoryStore } from '../data/HistoryStore';
import { SourceProbeService } from '../data/SourceProbeService';
import { SourceProbeResult } from '../model/SourceProbe';
import { SearchDiscovery } from '../model/SearchDiscovery';

export interface DiscoveryPageParam {
  item: RecommendItem;
  origin: PosterOrigin;
  openId: number;
  searchResult?: MergedVideo;
  searchUpdatedAt?: number;
  searchKeyword?: string;
}

/** A full-screen destination: hero motion, catalogue metadata and source lookup never gate one another. */
@Component
export struct DiscoveryPage {
  navPathStack: NavPathStack = new NavPathStack();
  param: DiscoveryPageParam = { item: { id: '', title: '', cover: '', isTv: false },
    origin: { x: 40, y: 130, width: 185, height: 293 }, openId: 0 };
  @State private item: RecommendItem = { id: '', title: '', cover: '', isTv: false };
  @State private info: PosterCardInfo = PosterCardData.empty();
  @State private infoLoading: boolean = false;
  @State private results: DiscoverySearchState = { results: [], refreshing: false, updatedAt: 0, failedCount: 0, error: '' };
  @State private hero: PosterOrigin = { x: 40, y: 130, width: 185, height: 293 };
  @State private widthVp: number = 1280;
  @State private heightVp: number = 720;
  @State private panelsOpacity: number = 0;
  @State private backdropOpacity: number = 0;
  @State private hoveredResult: string = '';
  @State private probes: SourceProbeResult[] = [];
  @State private probePending: string[] = [];
  @State private startingSource: string = '';
  private playRequest: number = 0;
  private readonly visibleSources: Map<string, SearchItem> = new Map();
  private activeProbes: Set<string> = new Set();
  private probeTimer: number = -1;
  private probeReady: boolean = false;
  private showing: boolean = false;
  private readonly session: DiscoverySearchSession = new DiscoverySearchSession();
  private appliedOpenId: number = -1;
  private generation: number = 0;
  private alive: boolean = false;
  private entered: boolean = false;
  private closing: boolean = false;
  private entranceTimer: number = -1;

  aboutToAppear(): void {
    this.alive = true;
    this.session.onChange = (state: DiscoverySearchState) => { if (this.alive) this.results = state; };
    this.apply(this.param);
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.generation++;
    this.playRequest++;
    this.session.close();
    this.stopProbes();
    if (this.entranceTimer >= 0) clearTimeout(this.entranceTimer);
  }

  private columns(): DiscoveryColumns {
    const columns = DiscoveryLayout.columns(this.widthVp, this.heightVp);
    const origin = this.param.origin;
    if (origin.width > 0 && origin.height > 0) columns.poster.height = origin.height * columns.poster.width / origin.width;
    return columns;
  }

  private apply(param: DiscoveryPageParam): void {
    if (param.openId === this.appliedOpenId) return;
    this.stopProbes();
    this.appliedOpenId = param.openId;
    this.playRequest++;
    this.startingSource = '';
    this.param = param;
    this.item = param.item;
    this.entered = false;
    this.closing = false;
    this.panelsOpacity = 0;
    this.backdropOpacity = 0;
    const origin = param.origin;
    this.hero = Number.isFinite(origin.x) && Number.isFinite(origin.y) && Number.isFinite(origin.width) &&
      Number.isFinite(origin.height) && origin.width > 0 && origin.height > 0 ?
      origin : { x: 40, y: 132, width: 185, height: 293 };
    const id = param.item.metadataProvider === 'douban' ? param.item.id : '';
    const catalogue = param.searchResult !== undefined ? SearchDiscovery.info(param.searchResult) : PosterCardData.empty(id, param.item.isTv);
    const cached = PosterMetadataService.peek(id);
    this.info = cached !== null ? SearchDiscovery.enrich(cached, catalogue) : catalogue;
    this.param = { item: param.item, origin: this.hero, openId: param.openId,
      searchResult: param.searchResult, searchUpdatedAt: param.searchUpdatedAt, searchKeyword: param.searchKeyword };
    this.generation++;
    this.session.close();
    this.results = { results: [], refreshing: false, updatedAt: 0, failedCount: 0, error: '' };
    this.probes = [];
    this.probePending = [];
    this.visibleSources.clear();
    this.activeProbes = new Set();
  }

  private loadMetadata(): void {
    if (this.param.searchResult !== undefined) {
      this.loadSearchMetadata(this.param.searchResult, ++this.generation);
      return;
    }
    const id = this.item.metadataProvider === 'douban' ? this.item.id : '';
    const cached = PosterMetadataService.peek(id);
    if (cached !== null) this.info = cached;
    const token = ++this.generation;
    this.infoLoading = id !== '';
    // Neither request is awaited by entrance motion or the other panel.
    if (id !== '') PosterMetadataService.request(id, this.item.isTv, true).then((info: PosterCardInfo | null) => {
      if (!this.alive || token !== this.generation) return;
      if (info !== null) this.info = info;
      this.infoLoading = false;
    });
  }

  private async loadSearchMetadata(selection: MergedVideo, token: number): Promise<void> {
    this.infoLoading = true;
    let catalogue = SearchDiscovery.info(selection);
    let id = SearchDiscovery.doubanId(selection);
    try {
      const first = this.sourceRows()[0]?.items[0];
      const config = first !== undefined ? SourceManager.shared().getVodSource(first.sourceKey) : null;
      if (first !== undefined && config !== null) {
        const detail = await DetailCache.load(first.sourceKey, first.vodId, () => CmsClient.detail(config, first.vodId));
        if (!this.alive || !this.showing || token !== this.generation) return;
        catalogue = SearchDiscovery.enrich(SearchDiscovery.info(selection, detail), catalogue);
        id = SearchDiscovery.doubanId(selection, detail);
      }
    } catch (e) { /* Search text and resource choices remain available if catalogue enrichment fails. */ }
    if (!this.alive || !this.showing || token !== this.generation) return;
    const cached = PosterMetadataService.peek(id);
    this.info = cached !== null ? SearchDiscovery.enrich(cached, catalogue) : catalogue;
    if (id !== '') {
      this.item = { id: id, title: this.item.title, cover: this.item.cover, isTv: catalogue.isSeries, metadataProvider: 'douban' };
      const info = await PosterMetadataService.request(id, catalogue.isSeries, true);
      if (!this.alive || !this.showing || token !== this.generation) return;
      if (info !== null) this.info = SearchDiscovery.enrich(info, catalogue);
    }
    this.infoLoading = false;
  }

  private sourceRows(): MergedVideo[] {
    const selection = this.param.searchResult;
    if (selection === undefined) return this.results.results;
    const settings = SettingsStore.shared().get();
    return SearchDiscovery.selected(selection, this.results.results).map((result: MergedVideo): MergedVideo => ({
      name: result.name, year: result.year, pic: result.pic, typeName: result.typeName, area: result.area, remarks: result.remarks,
      items: result.items.filter((item: SearchItem) => {
        const source = SourceManager.shared().getVodSource(item.sourceKey);
        return source !== null && source.enabled && (!settings.adultFilter || !source.isAdult);
      })
    })).filter((result: MergedVideo) => result.items.length > 0);
  }

  private enter(): void {
    if (this.entered || this.closing) return;
    this.entered = true;
    this.entranceTimer = setTimeout(() => {
      if (!this.alive || this.closing) return;
      this.getUIContext().animateTo({ duration: 580, curve: curves.cubicBezierCurve(0.2, 0, 0.2, 1),
        expectedFrameRateRange: { min: 30, max: 60, expected: 60 } }, () => {
        this.hero = this.columns().poster;
      });
      this.getUIContext().animateTo({ duration: 280, delay: 80, curve: Curve.EaseOut }, () => {
        this.panelsOpacity = 1;
      });
      this.getUIContext().animateTo({ duration: 260, curve: Curve.EaseOut }, () => { this.backdropOpacity = 1; });
    }, 16);
  }

  private back(): void {
    if (this.closing) return;
    this.closing = true;
    this.playRequest++;
    this.session.close();
    this.stopProbes();
    this.generation++;
    this.getUIContext().animateTo({ duration: 360, curve: curves.cubicBezierCurve(0.4, 0, 0.2, 1) }, () => {
      this.hero = this.param.origin;
      this.panelsOpacity = 0;
      this.backdropOpacity = 0;
    });
    setTimeout(() => { if (this.alive) this.navPathStack.pop(); }, 360);
  }

  private score(): string { return this.info.rating !== '' ? this.info.rating : (this.item.rating || '暂无评分'); }

  private async openSource(result: MergedVideo, source: SearchItem): Promise<void> {
    const request = ++this.playRequest;
    this.startingSource = this.probeKey(source);
    this.stopProbes();
    try {
      const config = SourceManager.shared().getVodSource(source.sourceKey);
      if (config === null) throw new Error('片源已移除，请选择其他源');
      let detail = DetailCache.get(source.sourceKey, source.vodId);
      if (detail === null) detail = await DetailCache.load(source.sourceKey, source.vodId, () => CmsClient.detail(config, source.vodId));
      if (detail.episodes.length === 0) detail = await CmsClient.detailFromPage(config, source.vodId);
      if (!this.alive || !this.showing || this.closing || request !== this.playRequest) return;
      const history = HistoryStore.shared().getHistory().find((entry) => entry.sourceKey === source.sourceKey && entry.vodId === source.vodId);
      const choice = DiscoveryPlayback.choose(detail, history);
      if (choice === null) throw new Error('这个源暂时没有可播放的内容，请换一个');
      DetailCache.put(source.sourceKey, source.vodId, detail);
      const param: PlayerPageParam = { sourceKey: source.sourceKey, vodId: source.vodId,
        title: detail.info.title || result.name, episode: choice.episodeIndex, episodeName: choice.episode.name,
        episodeUrl: choice.episode.url, lineIndex: choice.lineIndex, positionMs: choice.positionMs,
        offlineDir: '', pic: detail.info.cover || this.item.cover, playWhenReady: true };
      this.navPathStack.pushPath({ name: 'Player', param: param });
    } catch (e) {
      if (this.alive && this.showing && request === this.playRequest) {
        this.getUIContext().getPromptAction().showToast({ message: '该资源暂时无法打开，请选择其他片源', duration: 2000 });
        this.startProbes(32);
      }
    } finally {
      if (request === this.playRequest) this.startingSource = '';
    }
  }

  private resultKey(result: MergedVideo): string {
    const first = result.items[0];
    return result.name + '|' + (result.year || '') + '|' + (first !== undefined ? first.sourceKey + first.vodId : '');
  }

  private probeOwner(): string { return 'discovery-' + this.appliedOpenId; }
  private probeKey(source: SearchItem): string { return source.sourceKey + '|' + source.vodId; }
  private probeFor(source: SearchItem): SourceProbeResult | undefined {
    return this.probes.find((result: SourceProbeResult) => result.sourceKey === source.sourceKey && result.vodId === source.vodId);
  }
  private setProbe(result: SourceProbeResult): void {
    this.probes = this.probes.filter((entry: SourceProbeResult) => entry.sourceKey !== result.sourceKey || entry.vodId !== result.vodId).concat([result]);
  }

  private startProbes(delay: number): void {
    if (this.probeTimer >= 0) clearTimeout(this.probeTimer);
    this.probeReady = false;
    this.activeProbes = new Set();
    this.probePending = [];
    this.probeTimer = setTimeout(() => {
      if (!this.alive || !this.showing || this.closing) return;
      this.probeReady = true;
      for (const source of this.visibleSources.values()) this.requestProbe(source);
    }, delay);
  }

  private stopProbes(): void {
    this.probeReady = false;
    if (this.probeTimer >= 0) { clearTimeout(this.probeTimer); this.probeTimer = -1; }
    SourceProbeService.cancel(this.probeOwner());
  }

  private requestProbe(source: SearchItem, force: boolean = false): void {
    const cached = SourceProbeService.peek(source);
    if (cached !== null) this.setProbe(cached);
    if ((!force && cached !== null && SourceProbeService.fresh(cached)) || !this.alive || !this.showing) return;
    const key = this.probeKey(source);
    const active = this.activeProbes;
    if (active.has(key)) return;
    active.add(key);
    this.probePending = this.probePending.concat([key]);
    const token = this.generation;
    SourceProbeService.request(source, this.probeOwner(), force).then((result: SourceProbeResult | null) => {
      if (this.alive && this.showing && token === this.generation && result !== null) this.setProbe(result);
    }).finally(() => {
      active.delete(key);
      if (this.alive && this.showing && token === this.generation) this.probePending = this.probePending.filter((value: string) => value !== key);
    });
  }

  private probeResolution(source: SearchItem): string {
    const result = this.probeFor(source);
    if (result !== undefined && result.width > 0) {
      return (result.resolutionAt < result.checkedAt ? '上次 ' : '') +
        (result.resolutionSource === 'manifest' ? '≤' : '') + result.width + '×' + result.height;
    }
    const label = SourceQuality.label(source.remarks);
    return label !== '' ? '源标注 ' + label : '尺寸未提供';
  }

  private probeLatency(source: SearchItem): string {
    const result = this.probeFor(source);
    if (result !== undefined) return result.status === 'ok' ? result.latencyMs + 'ms' : (result.httpStatus > 0 ? 'HTTP ' + result.httpStatus : '探测失败');
    return this.probePending.indexOf(this.probeKey(source)) >= 0 ? '探测中' : '待探测';
  }

  private refreshSources(): void {
    this.session.refresh();
    for (const source of this.visibleSources.values()) this.requestProbe(source, true);
  }

  private cacheLabel(): string {
    if (this.results.fromSeed) return '已找到 · 来自搜索结果';
    if (this.results.updatedAt === 0) return this.results.refreshing ? '正在查找可用片源' : '尚无缓存';
    const hours = Math.max(0, Math.floor((Date.now() - this.results.updatedAt) / 3600000));
    return '已缓存 · ' + (hours === 0 ? '刚刚更新' : (hours < 24 ? hours + ' 小时前更新' : Math.floor(hours / 24) + ' 天前更新'));
  }

  @Builder
  private field(label: string) {
    Row({ space: 12 }) {
      Text(label).fontSize(13).fontColor('#A1ACBE').width(44)
      Text((label === '导演' ? this.info.directors : this.info.actors).join(' / ') || '暂未提供').fontSize(14).fontColor('#E7ECF5').layoutWeight(1)
        .maxLines(label === '主演' ? 3 : 2).textOverflow({ overflow: TextOverflow.Ellipsis })
    }.width('100%').alignItems(VerticalAlign.Top)
  }

  @Builder
  private metadata() {
    Scroll() {
      Column({ space: 17 }) {
        Text(this.item.title).fontSize(31).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
          .width('100%').maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.info.originalTitle !== '') Text(this.info.originalTitle).fontSize(14).fontColor('#ACB6C7').width('100%')
        Row({ space: 12 }) {
          Text(this.score() === '暂无评分' ? this.score() : '★ ' + this.score()).fontSize(21).fontWeight(FontWeight.Bold).fontColor('#FFDB91')
          Text(PosterCardData.heatLabel(this.info.shortComments)).fontSize(12).fontColor('#C5CEDD').layoutWeight(1)
        }.width('100%')
        Text(this.info.genres.length > 0 ? this.info.genres.join(' / ') : '类型暂未提供')
          .fontSize(14).fontColor('#D1D9E8').width('100%')
        Divider().color('#30FFFFFF')
        Text('剧情简介').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#F0F3FA').width('100%').margin({ top: 4 })
        Text(this.info.description !== '' ? this.info.description : (this.infoLoading ? '正在补充影片资料…' : '简介暂未提供'))
          .fontSize(17).fontColor('#CBD5E5').lineHeight(29).width('100%')
      }.width('100%').constraintSize({ minHeight: this.columns().bodyHeight })
        .justifyContent(FlexAlign.Start).alignItems(HorizontalAlign.Start).padding({ right: 8, bottom: 20 })
    }.scrollBar(BarState.Off).edgeEffect(EdgeEffect.Fade).align(Alignment.TopStart)
      .width(this.columns().metadataWidth).height(this.columns().bodyHeight)
  }

  @Builder
  private credits() {
    Column({ space: 12 }) {
      this.field('导演')
      this.field('主演')
    }.width(this.columns().poster.width).alignItems(HorizontalAlign.Start)
  }

  @Builder
  private sourceResults() {
    Column({ space: 10 }) {
      Row() {
        Text('播放资源').fontSize(20).fontWeight(FontWeight.Bold).fontColor('#F4F6FC').layoutWeight(1)
        Text(this.results.refreshing ? '刷新中…' : '刷新').fontSize(13).fontColor('#F1F4FA')
          .padding({ left: 15, right: 15, top: 10, bottom: 10 }).borderRadius(20).backgroundColor('#25FFFFFF')
          .enabled(!this.results.refreshing).focusable(true).focusBox(TV_FOCUS).onClick(() => { this.refreshSources(); })
      }.width('100%')
      Row({ space: 10 }) {
        Text(this.cacheLabel()).fontSize(12).fontColor('#A9B6CA').layoutWeight(1)
        if (this.results.refreshing && this.results.results.length > 0) Text('更新中，仍可选择').fontSize(12).fontColor('#D0DAE9')
      }.width('100%')
      Text('HTTP 耗时 · 码流采样 / 清单上限 ≤ / 源标注').fontSize(10).fontColor('#8F9EB3').width('100%')
      if (this.results.error !== '') Text(this.results.error).fontSize(12).fontColor('#E1BE8B').width('100%')
      if (this.results.failedCount > 0) Text(this.results.failedCount + ' 个片源未能更新').fontSize(12).fontColor('#B3BDD0').width('100%')
      if (this.sourceRows().length > 0) {
        List({ space: 10 }) {
          ForEach(this.sourceRows(), (result: MergedVideo) => {
            ListItem() {
              Column({ space: 8 }) {
                Row({ space: 8 }) {
                  Text(result.name).fontSize(14).fontWeight(FontWeight.Medium).fontColor('#EEF2FA')
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                  if (result.year) Text(result.year).fontSize(11).fontColor('#AAB7CA')
                }.width('100%')
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(result.items, (source: SearchItem) => {
                    Column({ space: 5 }) {
                      Text(source.sourceName).fontSize(13).fontColor('#F4F7FC').width('100%')
                        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                      Row({ space: 4 }) {
                        Text(this.probeResolution(source)).fontSize(10).fontColor('#E6CE9D').layoutWeight(1)
                          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(this.startingSource === this.probeKey(source) ? '正在打开' : this.probeLatency(source)).fontSize(10)
                          .fontColor(this.probeFor(source)?.status === 'failed' ? '#E1A89C' : '#A9CBBF')
                      }.width('100%')
                    }.width((this.columns().resultsWidth - 48) / 3).height(52).justifyContent(FlexAlign.Center)
                      .padding({ left: 10, right: 10 }).margin({ right: 8, bottom: 6 }).borderRadius(11)
                      .backgroundColor(this.hoveredResult === this.resultKey(result) + source.sourceKey + source.vodId ? '#48576C' : '#303B4C')
                      .border({ width: 1, color: this.hoveredResult === this.resultKey(result) + source.sourceKey + source.vodId ? '#D9E4F5' : '#25FFFFFF' })
                      .focusable(true).focusBox(TV_FOCUS)
                      .onHover((hovered: boolean) => { this.hoveredResult = hovered ? this.resultKey(result) + source.sourceKey + source.vodId : ''; })
                      .onClick(() => this.openSource(result, source))
                      .onVisibleAreaChange([0.01], (visible: boolean) => {
                        const key = this.probeKey(source);
                        if (visible) {
                          this.visibleSources.set(key, source);
                          const cached = SourceProbeService.peek(source);
                          if (cached !== null) this.setProbe(cached);
                          if (this.probeReady && this.showing) this.requestProbe(source);
                        } else this.visibleSources.delete(key);
                      })
                  }, (source: SearchItem) => source.sourceKey + '|' + source.vodId)
                }.width('100%')
              }.width('100%').padding({ left: 12, right: 4, top: 11, bottom: 5 })
                .backgroundColor('#80202936').borderRadius(14)

            }
          }, (result: MergedVideo) => this.resultKey(result))
        }.width('100%').layoutWeight(1).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Fade)
      } else {
        Column({ space: 16 }) {
          if (this.results.refreshing) LoadingProgress().width(26).height(26).color('#CDD8E9')
          Text(this.results.refreshing ? '正在查找片源…' : '暂未找到可用资源').fontSize(16).fontColor('#CDD7E7')
          Text('影片资料可以先看，找到资源后会显示在这里').fontSize(12).fontColor('#96A4B9').textAlign(TextAlign.Center)
          Text('管理片源').fontSize(13).fontColor('#F0F4FA').padding(12).borderRadius(16).backgroundColor('#25FFFFFF')
            .focusable(true).focusBox(TV_FOCUS).onClick(() => this.navPathStack.pushPath({ name: 'Sources' }))
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      }
    }.width(this.columns().resultsWidth).height(this.columns().bodyHeight)
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        Column().width('100%').height('100%').backgroundColor('#C2080D15')
          .backgroundEffect({ radius: 30, saturation: 0.75 })
          .opacity(this.backdropOpacity)
        Column() { this.credits() }.position({ x: this.columns().poster.x,
          y: this.columns().poster.y + this.columns().poster.height + 20 }).opacity(this.panelsOpacity)
        Column() { this.metadata() }.position({ x: this.columns().metadataX, y: this.columns().bodyY }).opacity(this.panelsOpacity)
        Column() { this.sourceResults() }.position({ x: this.columns().resultsX, y: this.columns().bodyY }).opacity(this.panelsOpacity)
        ForEach([this.item], (item: RecommendItem) => {
          TvPosterCard({ title: item.title, poster: item.cover, rating: item.rating || '',
            subjectId: item.metadataProvider === 'douban' ? item.id : '', seriesHint: item.isTv,
            catalogueInfo: this.info })
            .width(this.param.origin.width).height(this.param.origin.height)
            .position({ x: this.param.origin.x, y: this.param.origin.y })
            .scale({ x: this.hero.width / this.param.origin.width, y: this.hero.height / this.param.origin.height,
              centerX: '0%', centerY: '0%' })
            .translate({ x: this.hero.x - this.param.origin.x, y: this.hero.y - this.param.origin.y })
            .renderGroup(true)
        }, (item: RecommendItem) => item.id + '|' + item.title + '|' + item.cover)
      }.width('100%').height('100%')
        .onAreaChange((oldArea: Area, area: Area) => {
          const width = Number(area.width); const height = Number(area.height);
          if (width > 0) this.widthVp = width;
          if (height > 0) this.heightVp = height;
        })
    }.hideTitleBar(true).mode(NavDestinationMode.DIALOG).systemTransition(NavigationSystemTransitionType.NONE)
      .onBackPressed(() => { this.back(); return true; })
      .onShown(() => {
        this.alive = true;
        this.showing = true;
        this.startingSource = '';
        const latest = latestNavParam(this.navPathStack, 'Discovery');
        if (latest !== null) this.apply(latest as DiscoveryPageParam);
        BackNavigation.register('Discovery', () => this.back());
        this.loadMetadata();
        const selection = this.param.searchResult;
        this.session.open(this.param.searchKeyword || this.item.title, SettingsStore.shared().get(), selection !== undefined ?
          { results: [selection], updatedAt: this.param.searchUpdatedAt || 0 } : undefined);
        const opening = !this.entered;
        this.enter();
        this.startProbes(opening ? 700 : 32);
      })
      .onHidden(() => { this.showing = false; this.generation++; this.playRequest++; this.session.close(); this.stopProbes(); })
  }
}
