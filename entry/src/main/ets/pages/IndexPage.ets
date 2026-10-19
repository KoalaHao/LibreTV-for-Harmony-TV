/**
 * 主页面：底部三 Tab（首页 / 直播 / 我的）+ 顶部搜索
 * 作为 Navigation 根页面承载全部子页面路由
 */

import { display } from '@kit.ArkUI';
import { RecommendItem, PlayRecord, LiveChannel, EpgProgramme, VideoDetail } from '../model/Types';
import { HistoryStore } from '../data/HistoryStore';
import { SourceManager } from '../data/SourceManager';
import { SettingsStore } from '../data/SettingsStore';
import { DownloadManager } from '../data/DownloadManager';
import { EventBus, Events } from '../common/EventBus';
import { DoubanClient } from '../model/DoubanClient';
import { BangumiClient } from '../model/BangumiClient';
import { HttpClient } from '../net/HttpClient';
import { M3uParser } from '../model/M3uParser';
import { CmsClient } from '../model/CmsClient';
import { BootstrapSources } from '../model/BootstrapSources';
import { DetailCache } from '../model/DetailCache';
import { NetImage } from '../components/NetImage';
import { XmltvParser } from '../model/XmltvParser';
import { Utils } from '../common/Utils';
import { AppVersion } from '../common/AppVersion';
import { EmptyView, LoadingView, SectionHeader, VodCard, SettingsRow } from '../components/CommonWidgets';
import { SearchResultPage } from './SearchResultPage';
import { SearchPageParam } from './SearchResultPage';
import { DetailPage } from './DetailPage';
import { DetailPageParam } from './DetailPage';
import { PlayerPage } from './PlayerPage';
import { PlayerPageParam } from './PlayerPage';
import { LivePlayerPage } from './LivePlayerPage';
import { LivePlayerPageParam } from './LivePlayerPage';
import { HistoryPage } from './HistoryPage';
import { HistoryPageParam } from './HistoryPage';
import { SourcesPage } from './SourcesPage';
import { DownloadsPage } from './DownloadsPage';
import { SettingsPage } from './SettingsPage';
import { AboutPage } from './AboutPage';

@Observed
class LiveGroupState {
  sourceKey: string = '';
  sourceName: string = '';
  epgUrl: string = '';
  channels: LiveChannel[] = [];
  expanded: boolean = false;
  loading: boolean = false;
  loaded: boolean = false;
  error: string = '';
  epgProgrammes: EpgProgramme[] = [];
  epgChannelIds: Map<string, string> = new Map<string, string>();
  epgLoaded: boolean = false;
  epgTextMap: Map<string, string> = new Map<string, string>();
}

interface RecCat {
  key: string;
  label: string;
  type: string;
  tag: string;
  /** 豆瓣 new_search_subjects 的 tags 取值，组合筛选时用它限定分类 */
  tags: string;
}

const REC_CATS: RecCat[] = [
  { key: 'movie', label: '电影', type: 'movie', tag: '热门', tags: '电影' },
  { key: 'tv', label: '剧集', type: 'tv', tag: '热门', tags: '电视剧' },
  { key: 'variety', label: '综艺', type: 'tv', tag: '综艺', tags: '综艺' },
  { key: 'doc', label: '纪录片', type: 'tv', tag: '纪录片', tags: '纪录片' },
  { key: 'anime', label: '动漫', type: 'tv', tag: '日本动画', tags: '动漫' }
];

/** 排序方式：key 是豆瓣的 sort 参数，label 给用户看 */
interface RecSort {
  key: string;
  label: string;
}

const REC_SORTS: RecSort[] = [
  { key: 'R', label: '最新' },
  { key: 'T', label: '综合推荐' },
  { key: 'S', label: '评分最高' }
];

/**
 * 默认排序 = REC_SORTS 首项「最新」。
 * 不做持久化：每次重新打开 APP，首页推荐都从最新发行的内容开始。
 */
const REC_SORT_DEFAULT: string = 'R';

/** 豆瓣每页固定返回 20 条，瀑布流据此判断是否还有下一页 */
const REC_PAGE_SIZE: number = 20;
/** 瀑布流累加到这个起点就收手：再往后服务端基本只返回空 */
const REC_PAGE_MAX_START: number = 380;

/**
 * 悬浮「返回顶部」的出现阈值（屏）。
 * 最初按「50 行卡片」实现，但一行 ≈ 220vp（海报 172 + 标题 34 + 行距 14），
 * 50 行 ≈ 11000vp ≈ 15 屏 —— 手指要划十几屏按钮才冒出来，等于没有。
 * 改成按屏数计：滚过 2 屏（约 6-7 行）就出现。
 */
const BACK_TOP_SCREENS: number = 2;
/** 拉到顶时的小提示 */
const PULL_TOP_HINT: string = '别拉了，我到顶了！';

/** 影片类型（豆瓣 genres 取值，逐个实测可用）；首项表示不限 */
const REC_GENRE_OPTS: string[] = [
  '全部', '剧情', '喜剧', '动作', '爱情', '科幻', '动画', '悬疑',
  '惊悚', '犯罪', '恐怖', '战争', '奇幻', '冒险', '历史'
];

/** 发行地区（豆瓣 countries 取值，逐个实测可用）；首项表示不限 */
const REC_COUNTRY_OPTS: string[] = [
  '全部', '中国大陆', '美国', '中国香港', '中国台湾', '日本', '韩国',
  '英国', '法国', '德国', '印度', '泰国', '意大利', '西班牙',
  '加拿大', '澳大利亚'
];

/** 「不限」的显示文案，同时作为筛选状态的哨兵值 */
const REC_FILTER_ALL: string = '全部';

/**
 * 直播频道展开超过多少行就认为「超过两屏」。
 * 一行约 46vp（台标 30 + 上下 padding 10 + 行间距 6），
 * 手机可用高度约 890vp，两屏 ≈ 38 行，取 36 作为阈值。
 */
const LIVE_COLLAPSE_ROWS: number = 36;

@Entry
@Component
struct IndexPage {
  private navStack: NavPathStack = new NavPathStack();
  /** 推荐翻页起点：豆瓣按 page_start 分页，固定传 0 就会永远返回同一批「换一换」内容 */
  private recPageStart: number = 0;
  /** 历史封面回填是否已跑过，避免每次刷新重复请求 */
  private backfillStarted: boolean = false;
  private historyCb: () => void = () => {};
  private sourcesCb: () => void = () => {};
  private downloadsCb: () => void = () => {};

  @State activeTab: number = 0;
  @State searchValue: string = '';
  @State homeHistory: PlayRecord[] = [];
  @State recommendItems: RecommendItem[] = [];
  @State recommendLoading: boolean = false;
  /**
   * 分类切换 / 换一换期间的轻量提示开关。
   * 只用来降 Grid 的不透明度 —— 千万不要在这个过程中把内容换成 LoadingView：
   * 30 条卡片的网格高度有几千 vp，换成 260vp 的加载占位后内容高度骤降，
   * 外层 Scroll 的偏移量会被夹回 0，表现就是「点一下分类，页面自己弹回顶部」。
   */
  @State recSwitching: boolean = false;
  /** 瀑布流：还有下一页可加载 */
  @State recHasMore: boolean = true;
  /** 瀑布流：正在追加下一页（底部转圈） */
  @State recLoadingMore: boolean = false;
  /**
   * 首页可用宽度（vp），由 homeContent 上的 onAreaChange 实测。
   * 不在启动时一次性取 display：分屏、横竖屏旋转、折叠屏展开都会改变实际可用宽度，
   * 只有实测值能跟着变。
   */
  @State homeWidth: number = 0;
  @State recCatKey: string = 'movie';
  /** 豆瓣排行（Top250）模式：推荐来源选 douban_rank 时生效，分类/筛选条不适用 */
  @State recRank: boolean = false;
  /** 影片类型筛选，空串表示不限 */
  @State recGenre: string = '';
  /** 发行地区筛选，空串表示不限 */
  @State recCountry: string = '';
  /** 排序方式：R=最新(按发行时间从近到远) T=综合推荐 S=评分最高 */
  @State recSort: string = REC_SORT_DEFAULT;
  /** 当前展开的筛选面板：'' 收起 / sort / genre / country */
  @State filterPanel: string = '';
  /**
   * 请求序号。快速连点筛选时只让最后一次生效 ——
   * 否则慢的那个请求后到，会把界面刷回上一组筛选结果。
   */
  private recSeq: number = 0;
  /** 瀑布流翻页闸门，用普通字段而非 @State */
  private recPaging: boolean = false;
  @State liveGroups: LiveGroupState[] = [];
  /** 直播列表的滚动控制器：收起长频道列表后要滚回该源的分组标题 */
  private liveScroller: Scroller = new Scroller();
  /** 首页主滚动容器：内容上方区块高度变化时用它补偿偏移 */
  private homeScroller: Scroller = new Scroller();
  /** 「继续观看」区块当前高度（vp），用于算增量 */
  private historyBlockH: number = 0;
  /** 用户最后一次滚动到的位置：播放页会把屏幕转横再转回，
   *  首页在后台经历重排，滚动偏移会被布局夹掉 —— 回来时用这个值恢复 */
  private homeOffset: number = 0;
  /** 上滑超过 BACK_TOP_ROWS 行后浮现的「返回顶部」 */
  @State showBackTop: boolean = false;
  /** 拉到顶时的小提示，1.4 秒后自动消失 */
  @State pullTopHint: boolean = false;
  /** 提示消隐定时器句柄，-1 表示没有在跑 */
  private pullHintTimer: number = -1;
  /** 本次手势按下的纵坐标（windowY），用来区分「下拉」与「上滑」 */
  private touchStartY: number = 0;
  /** 本次手势里提示是否已经弹过，避免一个手势反复弹 */
  private pullHintFired: boolean = false;
  /**
   * 频道数预取令牌。刷新/重进时自增，正在跑的那一轮看到令牌变了就自己退出，
   * 避免两次预取叠加在一起互相覆盖 group 状态。
   */
  private countToken: number = 0;
  @State liveLoading: boolean = false;
  @State vodCount: number = 0;
  @State liveCount: number = 0;
  @State favCount: number = 0;
  @State downloadCount: number = 0;

  aboutToAppear(): void {
    // 先用屏幕宽度给个初值，避免首帧按手机 3 列画完再跳成 8 列的闪烁；
    // 真正的值由 homeContent 上的 onAreaChange 实测覆盖。
    try {
      this.homeWidth = px2vp(display.getDefaultDisplaySync().width);
    } catch (e) {
      this.homeWidth = 0;
    }
    this.refreshHome();
    this.refreshCounts();
    this.initRecCat();
    // 源健康度定期自动探测：失败源按退避自动停用（= 自动关闭），坏源不再拖慢搜索
    SourceManager.shared().startAutoRefresh();
    // 自动发现源（设置开关默认关）：延迟 3 秒后台拉取聚合订阅并验活入库
    BootstrapSources.maybeRunOnLaunch();
    this.loadRecommend();
    this.refreshLiveGroups();
    this.historyCb = () => {
      this.refreshHome();
      this.refreshCounts();
      // 播放页退出会保存进度并触发本回调；此时屏幕刚从横屏转回竖屏，
      // 首页布局被重排过 —— 在这里恢复用户原来的滚动位置
      this.restoreHomeOffset();
    };
    this.sourcesCb = () => {
      this.refreshCounts();
      this.refreshLiveGroups();
    };
    this.downloadsCb = () => {
      this.refreshCounts();
    };
    EventBus.on(Events.HISTORY_CHANGED, this.historyCb);
    EventBus.on(Events.SOURCES_CHANGED, this.sourcesCb);
    EventBus.on(Events.DOWNLOADS_CHANGED, this.downloadsCb);
  }

  aboutToDisappear(): void {
    if (this.pullHintTimer !== -1) {
      clearTimeout(this.pullHintTimer);
      this.pullHintTimer = -1;
    }
    EventBus.off(Events.HISTORY_CHANGED, this.historyCb);
    EventBus.off(Events.SOURCES_CHANGED, this.sourcesCb);
    EventBus.off(Events.DOWNLOADS_CHANGED, this.downloadsCb);
  }

  onPageShow(): void {
    this.refreshHome();
    this.refreshCounts();
    this.restoreHomeOffset();
  }

  /**
   * 恢复首页滚动位置。
   * 播放页一进入就强制横屏，返回时再转回竖屏：首页在后台经历横→竖重排，
   * 瀑布流列数变化、内容高度变化，滚动偏移会被布局夹掉（表现就是「位置跳变」）。
   * 旋转后的布局要一两帧才稳定，所以两次校正。
   */
  private restoreHomeOffset(): void {
    const target: number = this.homeOffset;
    if (target <= 0) {
      return;
    }
    const apply = (): void => {
      try {
        this.homeScroller.scrollTo({ xOffset: 0, yOffset: target, animation: false });
        // scrollTo 不一定会触发 onDidScroll，这里手动对齐一次悬浮按钮状态
        this.syncBackTop(target);
      } catch (e) {
        // Scroller 未绑定时忽略
      }
    };
    setTimeout(apply, 80);
    setTimeout(apply, 350);
  }

  /** 「滚过 BACK_TOP_SCREENS 屏」换算成具体滚动距离（vp） */
  private backTopThreshold(): number {
    let screenH: number = 760;
    try {
      // 物理屏高换成 vp；横屏/分屏时它不会变，但首页本身也只会滚动这一个方向，
      // 这里只用来给「滚了多远」定个量级，不必精确到视口高度。
      screenH = px2vp(display.getDefaultDisplaySync().height);
    } catch (e) {
      // 取不到就用兜底值
    }
    if (screenH <= 0) {
      screenH = 760;
    }
    return screenH * BACK_TOP_SCREENS;
  }

  /** 滚动位置变化时决定悬浮按钮显隐，状态没变就不写，避免每帧触发重绘 */
  private syncBackTop(y: number): void {
    const show: boolean = y >= this.backTopThreshold();
    if (show !== this.showBackTop) {
      this.showBackTop = show;
    }
  }

  /** 是否已经贴在最顶上（留 2vp 容差，避免亚像素误差） */
  private homeAtTop(): boolean {
    try {
      return this.homeScroller.currentOffset().yOffset <= 2;
    } catch (e) {
      return false;
    }
  }

  /** 拉到顶：弹小提示，1.4 秒后自动收（连续拉会重新计时，不会闪一下就没） */
  private flashPullHint(): void {
    this.pullTopHint = true;
    if (this.pullHintTimer !== -1) {
      clearTimeout(this.pullHintTimer);
    }
    // 这个定时器只管提示文案，页面销毁时在 aboutToDisappear 里清掉
    this.pullHintTimer = setTimeout(() => {
      this.pullTopHint = false;
      this.pullHintTimer = -1;
    }, 1400);
  }

  /** 点悬浮按钮回顶：带一段缓动，不要瞬移 */
  private backToTop(): void {
    this.homeOffset = 0;
    this.showBackTop = false;
    try {
      this.homeScroller.scrollTo({
        xOffset: 0,
        yOffset: 0,
        animation: { duration: 320, curve: Curve.EaseOut }
      });
    } catch (e) {
      // Scroller 未绑定
    }
  }

  private refreshHome(): void {
    this.homeHistory = HistoryStore.shared().getHistory().slice(0, 12);
    this.backfillHistoryPics();
  }

  private refreshCounts(): void {
    this.vodCount = SourceManager.shared().getVodSources().length;
    this.liveCount = SourceManager.shared().getLiveSources().length;
    this.favCount = HistoryStore.shared().getFavorites().length;
    this.downloadCount = DownloadManager.shared().getTasks().length;
  }

  private initRecCat(): void {
    const src = SettingsStore.shared().get().recommendSource;
    this.recRank = src === 'douban_rank';
    if (src === 'douban_tv') {
      this.recCatKey = 'tv';
    } else if (src === 'bangumi') {
      this.recCatKey = 'anime';
    } else {
      this.recCatKey = 'movie';
    }
  }

  /** 首次加载 / 换一批 / 改筛选：整页替换 */
  private async loadRecommend(): Promise<void> {
    await this.fetchRecommend(false);
  }

  /**
   * 瀑布流：滑到底时追加下一页。
   * recPaging 是普通字段而不是 @State —— 状态写入是异步的，拿它当闸门挡不住
   * 边沿事件在同一帧里的连击，结果就是同一页被请求两次、列表里冒出重复卡片。
   */
  private loadMoreRecommend(): void {
    if (this.recPaging || this.recommendLoading || this.recSwitching) {
      return;
    }
    if (!this.recHasMore || this.recommendItems.length === 0) {
      return;
    }
    this.fetchRecommend(true);
  }

  /**
   * 拉推荐数据。
   *   append=false 整页替换（首次加载 / 换一批 / 改筛选）
   *   append=true  在现有列表后面追加下一页（瀑布流）
   */
  private async fetchRecommend(append: boolean): Promise<void> {
    if (append) {
      this.recPaging = true;
      this.recLoadingMore = true;
    } else {
      // 已有内容时走「原地替换」：保留旧列表、只降不透明度，
      // 新数据回来再整体换掉。这样内容高度不会塌陷，Scroll 偏移量得以保留，
      // 用户滚到哪儿就还停在哪儿。只有首次加载（列表为空）才显示 LoadingView。
      this.recLoadingMore = false;
      this.recHasMore = true;
      if (this.recommendItems.length > 0) {
        this.recSwitching = true;
      } else {
        this.recommendLoading = true;
      }
    }
    this.recSeq++;
    const seq: number = this.recSeq;
    // Top250 榜单页每页固定 25 条，其余接口每页 20 条
    const pageSize: number = this.recRank ? 25 : REC_PAGE_SIZE;
    let start: number = this.recPageStart;
    if (append) {
      start = this.recPageStart + pageSize;
    }
    let fallback: boolean = false;
    try {
      let items: RecommendItem[] = [];
      if (this.recRank) {
        // 豆瓣排行：Top250 HTML 榜单页，分类/筛选条不适用
        items = await DoubanClient.top250(start);
        if (items.length === 0 && start > 0 && !append) {
          start = 0;
          this.recPageStart = 0;
          items = await DoubanClient.top250(0);
        }
        if (items.length === 0) {
          // 榜单页被反爬拦截时退回「评分最高」浏览接口兜底
          items = await DoubanClient.browse('电影', '', '', 'S', 0);
          fallback = true;
        }
      } else {
        const cat: RecCat = this.currentCat();
        // 统一走 new_search_subjects：它同时支持分类(tags) + 类型(genres)
        // + 地区(countries) + 排序(sort)，一条链路就能覆盖「默认浏览」和「组合筛选」，
        // 不必为筛选再造一套分页逻辑。
        items =
          await DoubanClient.browse(cat.tags, this.recGenre, this.recCountry, this.recSort, start);
        if (items.length === 0 && start > 0 && !append) {
          // 翻页翻过头了（或筛选后总量不足一页），回到第一页再取一次
          start = 0;
          this.recPageStart = 0;
          items = await DoubanClient.browse(cat.tags, this.recGenre, this.recCountry, this.recSort, 0);
        }
        if (items.length === 0 && !append && this.recGenre === '' && this.recCountry === '') {
          // 浏览接口偶发返回空 data（疑似频控）。没加筛选时回退到老接口，
          // 至少首页不至于整块空白；加了筛选就老实显示空态 —— 拿不相关的片
          // 去冒充「筛选结果」比空白更糟。
          items = await DoubanClient.recommend(cat.type, cat.tag, 0, 30);
          fallback = true;
        }
        if (items.length === 0 && !append && cat.key === 'anime') {
          items = await BangumiClient.calendar();
          fallback = true;
        }
      }
      // 一次取两页：单页只有 5-7 行，首屏和每次触底都显得太少。
      // 第二页失败就只用第一页，不影响可用性。
      let fetchedPages: number = 1;
      if (!fallback && items.length >= pageSize) {
        try {
          let more: RecommendItem[] = [];
          if (this.recRank) {
            more = await DoubanClient.top250(start + pageSize);
          } else {
            const cat2: RecCat = this.currentCat();
            more = await DoubanClient.browse(cat2.tags, this.recGenre, this.recCountry, this.recSort, start + pageSize);
          }
          if (more.length > 0) {
            items = items.concat(more);
            fetchedPages = 2;
          }
        } catch (e2) {
          // 第二页失败忽略，保留第一页
        }
      }

      if (seq !== this.recSeq) {
        // 期间又点了别的筛选，这批结果已经过时，直接丢弃
        return;
      }
      if (append) {
        const before: number = this.recommendItems.length;
        // 新一页单独过一遍排序（综合推荐要洗牌），已经滑过的卡片位置不动 ——
        // 整体重排会让用户觉得界面自己跳了一下。
        const merged: RecommendItem[] = this.mergeItems(this.recommendItems, this.orderItems(items));
        this.recommendItems = merged;
        if (items.length === 0) {
          this.recHasMore = false;
        } else {
          const lastStart: number = start + (fetchedPages - 1) * pageSize;
          this.recPageStart = lastStart;
          // 服务端给了整页、去重后却一条都没多 —— 说明后面全是重复的，
          // 再往下翻只会空转，直接判到底。
          this.recHasMore = items.length >= pageSize && merged.length > before
            && lastStart + pageSize <= (this.recRank ? 250 : REC_PAGE_MAX_START);
        }
      } else {
        this.recommendItems = this.orderItems(items);
        if (!fallback) {
          // 记成「已取到的最后一页起点」，append 时从它的下一页开始
          this.recPageStart = start + (fetchedPages - 1) * pageSize;
        }
        // 走了兜底接口就没有可续的分页了，别让瀑布流接着翻出另一套数据
        this.recHasMore = !fallback && items.length >= pageSize;
      }
    } catch (e) {
      // 网络异常时保留旧列表，不要让页面变成空白。
    } finally {
      // 异常也要复位，否则加载态会永远卡住。
      if (append) {
        // recPaging 必须无条件放开：这次请求被打断时也要把闸门打开，
        // 否则「加载更多」会永久失效。
        this.recPaging = false;
        if (seq === this.recSeq) {
          this.recLoadingMore = false;
        }
      } else if (seq === this.recSeq) {
        // 只有「最后一次请求」才有资格收尾，否则会把新一轮的转场态提前关掉。
        this.recommendLoading = false;
        this.recSwitching = false;
      }
    }
  }

  /** 去重合并：翻页时服务端偶尔重复给同一条，id 撞了 ForEach 会出问题 */
  private mergeItems(base: RecommendItem[], add: RecommendItem[]): RecommendItem[] {
    const seen: Set<string> = new Set<string>();
    for (const it of base) {
      seen.add(it.id);
    }
    const out: RecommendItem[] = base.slice();
    for (const it of add) {
      if (!seen.has(it.id)) {
        seen.add(it.id);
        out.push(it);
      }
    }
    return out;
  }

  /** 换一批：推进分页起点后重新加载（浏览接口每页 20 条，Top250 每页 25 条） */
  private nextRecommend(): void {
    const pageSize: number = this.recRank ? 25 : REC_PAGE_SIZE;
    const wrapAt: number = this.recRank ? 225 : 180;
    this.recPageStart = this.recPageStart >= wrapAt ? 0 : this.recPageStart + pageSize;
    this.loadRecommend();
  }

  /**
   * 排序整理。
   * 「评分最高」「最新」必须保持服务端给的降序 —— 再洗牌就把「按评分/按时间排序」
   * 这个承诺毁了；「综合推荐」则洗牌，保证每次「换一批」看到的顺序不一样。
   */
  private orderItems(src: RecommendItem[]): RecommendItem[] {
    const arr: RecommendItem[] = src.slice();
    if (this.recRank) {
      // Top250 是榜单排名，顺序就是承诺，不洗牌
      return arr;
    }
    if (this.recSort === 'S') {
      arr.sort((a: RecommendItem, b: RecommendItem): number => {
        return this.rateOf(b) - this.rateOf(a);
      });
      return arr;
    }
    if (this.recSort === 'R') {
      // 服务端已是按上映时间倒序返回，本地再洗牌就把「最新」这个承诺毁了
      return arr;
    }
    for (let i = arr.length - 1; i > 0; i--) {
      const j: number = Math.floor(Math.random() * (i + 1));
      const tmp: RecommendItem = arr[i];
      arr[i] = arr[j];
      arr[j] = tmp;
    }
    return arr;
  }

  /** 把 "9.4" 这样的字符串评分转成数字；缺失或非法按 0 处理 */
  private rateOf(item: RecommendItem): number {
    const s: string = item.rating !== undefined ? item.rating : '';
    if (s === '') {
      return 0;
    }
    const v: number = Number.parseFloat(s);
    return Number.isNaN(v) ? 0 : v;
  }

  private currentCat(): RecCat {
    for (const c of REC_CATS) {
      if (c.key === this.recCatKey) {
        return c;
      }
    }
    return REC_CATS[0];
  }

  /** 是否有任何非默认的筛选/排序生效（决定要不要显示「重置」） */
  private hasFilter(): boolean {
    return this.recGenre !== '' || this.recCountry !== '' || this.recSort !== REC_SORT_DEFAULT;
  }

  /** 当前排序的中文名 */
  private currentSortLabel(): string {
    for (const s of REC_SORTS) {
      if (s.key === this.recSort) {
        return s.label;
      }
    }
    return REC_SORTS[0].label;
  }

  /** 筛选条上那一枚 chip 显示什么 */
  private filterLabel(kind: string): string {
    if (kind === 'sort') {
      return this.currentSortLabel();
    }
    if (kind === 'genre') {
      return this.recGenre === '' ? '类型' : this.recGenre;
    }
    return this.recCountry === '' ? '地区' : this.recCountry;
  }

  /** chip 是否处于「已设置」状态（用主色高亮） */
  private filterActive(kind: string): boolean {
    if (kind === 'sort') {
      return this.recSort !== REC_SORT_DEFAULT;
    }
    if (kind === 'genre') {
      return this.recGenre !== '';
    }
    return this.recCountry !== '';
  }

  private filterPanelTitle(): string {
    if (this.filterPanel === 'sort') {
      return '排序方式';
    }
    if (this.filterPanel === 'genre') {
      return '影片类型';
    }
    return '发行地区';
  }

  /** 当前面板的可选项 */
  private filterOptions(): string[] {
    if (this.filterPanel === 'sort') {
      const labels: string[] = [];
      for (const s of REC_SORTS) {
        labels.push(s.label);
      }
      return labels;
    }
    if (this.filterPanel === 'genre') {
      return REC_GENRE_OPTS;
    }
    return REC_COUNTRY_OPTS;
  }

  private isOptionSelected(opt: string): boolean {
    if (this.filterPanel === 'sort') {
      return opt === this.currentSortLabel();
    }
    if (this.filterPanel === 'genre') {
      const curGenre: string = this.recGenre === '' ? REC_FILTER_ALL : this.recGenre;
      return opt === curGenre;
    }
    const curCountry: string = this.recCountry === '' ? REC_FILTER_ALL : this.recCountry;
    return opt === curCountry;
  }

  /** 选中某个选项：写回状态、收起面板、回到第一页重新拉取 */
  private pickOption(opt: string): void {
    let changed: boolean = false;
    if (this.filterPanel === 'sort') {
      let key: string = this.recSort;
      for (const s of REC_SORTS) {
        if (s.label === opt) {
          key = s.key;
          break;
        }
      }
      if (key !== this.recSort) {
        this.recSort = key;
        changed = true;
      }
    } else if (this.filterPanel === 'genre') {
      const gv: string = opt === REC_FILTER_ALL ? '' : opt;
      if (gv !== this.recGenre) {
        this.recGenre = gv;
        changed = true;
      }
    } else {
      const cv: string = opt === REC_FILTER_ALL ? '' : opt;
      if (cv !== this.recCountry) {
        this.recCountry = cv;
        changed = true;
      }
    }
    this.filterPanel = '';
    if (changed) {
      this.recPageStart = 0;
      this.loadRecommend();
    }
  }

  /** 一键清空所有筛选与排序 */
  private clearFilter(): void {
    this.filterPanel = '';
    if (!this.hasFilter()) {
      return;
    }
    this.recGenre = '';
    this.recCountry = '';
    this.recSort = REC_SORT_DEFAULT;
    this.recPageStart = 0;
    this.loadRecommend();
  }

  /**
   * 回填历史记录的封面。
   * 早期版本保存播放记录时没写 pic，导致首页「继续观看」全是空白灰块。
   * 这里对缺封面的记录按需补一次（最多 8 条、串行+间隔，避免打爆采集站）。
   */
  private async backfillHistoryPics(): Promise<void> {
    if (this.backfillStarted) {
      return;
    }
    this.backfillStarted = true;
    const missing: PlayRecord[] = [];
    for (const r of this.homeHistory) {
      if (r.pic === undefined || r.pic === '') {
        missing.push(r);
      }
    }
    let done: number = 0;
    for (const r of missing) {
      if (done >= 8) {
        break;
      }
      const cached: VideoDetail | null = DetailCache.get(r.sourceKey, r.vodId);
      if (cached !== null && cached.info.cover !== undefined && cached.info.cover !== '') {
        HistoryStore.shared().setPicIfEmpty(r.sourceKey, r.vodId, cached.info.cover);
        done++;
        continue;
      }
      const src = SourceManager.shared().getVodSource(r.sourceKey);
      if (src === null) {
        continue;
      }
      try {
        const detail: VideoDetail | null = await CmsClient.detail(src, r.vodId);
        if (detail !== null && detail.info.cover !== undefined && detail.info.cover !== '') {
          DetailCache.put(r.sourceKey, r.vodId, detail);
          HistoryStore.shared().setPicIfEmpty(r.sourceKey, r.vodId, detail.info.cover);
          done++;
        }
      } catch (e) {
        // 单条失败不影响其它记录
      }
    }
    // homeHistory 是 getHistory() 的快照副本，store 内部改了它并不知道，
    // 这里重新取一次把补好的封面同步到界面上。
    if (done > 0) {
      this.homeHistory = HistoryStore.shared().getHistory().slice(0, 12);
    }
  }

  private refreshLiveGroups(): void {
    const sources = SourceManager.shared().enabledLiveSources();
    const groups: LiveGroupState[] = [];
    for (const s of sources) {
      const existing = this.findGroup(s.key);
      const g: LiveGroupState = new LiveGroupState();
      g.sourceKey = s.key;
      g.sourceName = s.name;
      g.epgUrl = s.epg !== undefined ? s.epg : '';
      g.channels = existing !== null ? existing.channels : [];
      g.expanded = existing !== null ? existing.expanded : false;
      g.loaded = existing !== null ? existing.loaded : false;
      g.epgProgrammes = existing !== null ? existing.epgProgrammes : [];
      g.epgChannelIds = existing !== null ? existing.epgChannelIds : new Map<string, string>();
      g.epgLoaded = existing !== null ? existing.epgLoaded : false;
      g.epgTextMap = existing !== null ? existing.epgTextMap : new Map<string, string>();
      groups.push(g);
    }
    this.liveGroups = groups;
  }

  /**
   * 依次拉取每个直播源，把频道数直接显示在分组标题上。
   *
   * 为什么串行：订阅里有 1000+ 频道的源，十几个并发下载会互相抢带宽，
   * 解析上万条 #EXTINF 还会把主线程顶住；串行时数字一个个冒出来，
   * 观感就是「正在统计」，也不会让首页推荐请求被挤掉。
   *
   * force=false：只补还没统计过的源（进入直播页时用，省流量）；
   * force=true ：全部重拉（点刷新时用），旧数字会一直留着直到新数字到位。
   */
  private async prefetchLiveCounts(force: boolean): Promise<void> {
    this.countToken++;
    const token: number = this.countToken;
    for (const g of this.liveGroups) {
      if (token !== this.countToken) {
        return;
      }
      if (g.loading) {
        continue;
      }
      if (g.loaded && !force) {
        continue;
      }
      await this.loadLiveGroup(g.sourceKey);
    }
  }

  private findGroup(key: string): LiveGroupState | null {
    for (const g of this.liveGroups) {
      if (g.sourceKey === key) {
        return g;
      }
    }
    return null;
  }

  private toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 });
  }

  private onSearchSubmit(): void {
    const wd = this.searchValue.trim();
    if (wd === '') {
      this.toast('请输入搜索关键词');
      return;
    }
    const p: SearchPageParam = { keyword: wd };
    this.navStack.pushPath({ name: 'Search', param: p });
  }

  private openRecommend(item: RecommendItem): void {
    const p: SearchPageParam = { keyword: item.title };
    this.navStack.pushPath({ name: 'Search', param: p });
  }

  private openDetail(sourceKey: string, vodId: string, name: string): void {
    const p: DetailPageParam = {
      sourceKey: sourceKey,
      vodId: vodId,
      title: name
    };
    this.navStack.pushPath({ name: 'Detail', param: p });
  }

  private continuePlay(rec: PlayRecord): void {
    const p: PlayerPageParam = {
      sourceKey: rec.sourceKey,
      vodId: rec.vodId,
      episode: rec.episode,
      episodeName: rec.episodeName !== undefined ? rec.episodeName : '',
      title: rec.name,
      positionMs: rec.positionMs,
      offlineDir: '',
      // 历史记录里存有上次的播放地址，直接复用，避免播放页再次请求详情被限流
      episodeUrl: rec.playUrl !== undefined ? rec.playUrl : '',
      pic: rec.pic !== undefined ? rec.pic : '',
      lineIndex: rec.lineIndex !== undefined ? rec.lineIndex : 0
    };
    this.navStack.pushPath({ name: 'Player', param: p });
  }

  private progressWidth(rec: PlayRecord): string {
    if (rec.durationMs <= 0) {
      return '0%';
    }
    const pct = Math.floor((rec.positionMs / rec.durationMs) * 100);
    if (pct <= 0) {
      return '0%';
    }
    if (pct > 100) {
      return '100%';
    }
    return pct + '%';
  }

  /**
   * 直播分组项的 ForEach key。
   * 只用 sourceKey 作 key 时，展开/加载等内部字段变化不会让 ForEach 重建该项，
   * UI 永远停在初始状态 —— 表现为「点直播源毫无反应」。
   * 把影响展示的状态拼进 key，任一状态变化即触发重建。
   */
  private liveGroupKey(group: LiveGroupState): string {
    return group.sourceKey + '|' + (group.expanded ? '1' : '0') + '|' + (group.loaded ? '1' : '0')
      + '|' + (group.loading ? '1' : '0') + '|' + group.channels.length + '|' + group.error;
  }

  private toggleLiveGroup(key: string): void {
    for (let i = 0; i < this.liveGroups.length; i++) {
      if (this.liveGroups[i].sourceKey === key) {
        const expanded = !this.liveGroups[i].expanded;
        this.liveGroups[i].expanded = expanded;
        this.liveGroups = this.liveGroups.slice();
        if (expanded && !this.liveGroups[i].loaded && !this.liveGroups[i].loading) {
          this.loadLiveGroup(key);
        }
        return;
      }
    }
  }

  /**
   * 当前展开着、且频道数超过约两屏的源。
   * 有它才需要底部那个「收起频道列表」入口；短列表本来就一屏看完，不必打扰。
   */
  private longExpandedGroup(): LiveGroupState | null {
    for (const g of this.liveGroups) {
      if (g.expanded && g.channels.length > LIVE_COLLAPSE_ROWS) {
        return g;
      }
    }
    return null;
  }

  /** 收起所有「长频道」分组，并把列表滚回第一个被收起源的分组标题 */
  private collapseLongGroups(): void {
    let target: string = '';
    let changed: boolean = false;
    for (const g of this.liveGroups) {
      if (g.expanded && g.channels.length > LIVE_COLLAPSE_ROWS) {
        g.expanded = false;
        changed = true;
        if (target === '') {
          target = g.sourceKey;
        }
      }
    }
    if (!changed) {
      return;
    }
    this.liveGroups = this.liveGroups.slice();
    // 收起后每项高度骤降，必须等这一帧布局生效再滚，
    // 立刻调 scrollToIndex 会按旧布局算偏移量，落点会偏。
    setTimeout(() => {
      for (let i = 0; i < this.liveGroups.length; i++) {
        if (this.liveGroups[i].sourceKey === target) {
          this.liveScroller.scrollToIndex(i, true, ScrollAlign.START);
          break;
        }
      }
    }, 80);
  }

  private async loadLiveGroup(key: string): Promise<void> {
    let idx = -1;
    for (let i = 0; i < this.liveGroups.length; i++) {
      if (this.liveGroups[i].sourceKey === key) {
        idx = i;
        break;
      }
    }
    if (idx < 0) {
      return;
    }
    this.liveGroups[idx].loading = true;
    this.liveGroups[idx].error = '';
    this.liveGroups = this.liveGroups.slice();
    const source = SourceManager.shared().getLiveSource(key);
    if (source === null) {
      this.liveGroups[idx].loading = false;
      this.liveGroups[idx].error = '源已被删除';
      this.liveGroups = this.liveGroups.slice();
      return;
    }
    const res = await HttpClient.getTextAny(source.url, { 'User-Agent': HttpClient.UA }, 10000);
    if (res.ok && res.text !== '') {
      this.liveGroups[idx].channels = M3uParser.parse(res.text, source.url);
      this.liveGroups[idx].loaded = true;
      this.liveGroups[idx].error = this.liveGroups[idx].channels.length === 0
        ? (M3uParser.looksLikeHtml(res.text)
          ? '该源返回的是网页，不是 M3U 播放列表，请在「视频源管理」替换订阅地址'
          : '未解析到频道，请检查订阅地址')
        : '';
      SourceManager.shared().recordSuccess(key);
      if (source.epg !== undefined && source.epg !== '') {
        const epgRes = await HttpClient.getBytes(source.epg, { 'User-Agent': HttpClient.UA }, 12000);
        if (epgRes.ok && epgRes.text !== '') {
          const parsed = XmltvParser.parse(epgRes.text);
          this.liveGroups[idx].epgProgrammes = parsed.programmes;
          this.liveGroups[idx].epgChannelIds = parsed.channels;
          this.liveGroups[idx].epgLoaded = true;
          this.buildEpgTextMap(idx);
        }
      }
    } else {
      this.liveGroups[idx].error = '播放列表拉取失败';
      SourceManager.shared().recordFailure(key);
    }
    this.liveGroups[idx].loading = false;
    this.liveGroups = this.liveGroups.slice();
  }

  private buildEpgTextMap(idx: number): void {
    const group = this.liveGroups[idx];
    const map = new Map<string, string>();
    const now = Date.now();
    for (const ch of group.channels) {
      const id = XmltvParser.matchChannelId(group.epgChannelIds, ch.tvgId !== undefined ? ch.tvgId : '', ch.name);
      if (id === '') {
        continue;
      }
      const nn = XmltvParser.nowNext(group.epgProgrammes, id, now);
      let text = '';
      if (nn.current !== undefined) {
        text = nn.current.title;
      }
      if (nn.next !== undefined) {
        if (text !== '') {
          text = text + ' / ';
        }
        text = text + '接下来：' + nn.next.title;
      }
      if (text !== '') {
        map.set(ch.id, text);
      }
    }
    this.liveGroups[idx].epgTextMap = map;
  }

  private epgTextFor(group: LiveGroupState, ch: LiveChannel): string {
    const text = group.epgTextMap.get(ch.id);
    if (text === undefined) {
      return '';
    }
    return text;
  }

  private arrowAngle(group: LiveGroupState): number {
    if (group.expanded) {
      return 270;
    }
    return 180;
  }

  private openLive(group: LiveGroupState, ch: LiveChannel): void {
    const p: LivePlayerPageParam = {
      channelUrl: ch.url,
      channelName: ch.name,
      sourceKey: group.sourceKey,
      sourceName: group.sourceName,
      logo: ch.logo !== undefined ? ch.logo : '',
      tvgId: ch.tvgId !== undefined ? ch.tvgId : ''
    };
    this.navStack.pushPath({ name: 'LivePlayer', param: p });
  }

  private pushHistory(): void {
    const p: HistoryPageParam = { mode: 'history' };
    this.navStack.pushPath({ name: 'History', param: p });
  }

  private pushFavorites(): void {
    const p: HistoryPageParam = { mode: 'favorites' };
    this.navStack.pushPath({ name: 'History', param: p });
  }

  private pushSources(): void {
    this.navStack.pushPath({ name: 'Sources' });
  }

  private pushDownloads(): void {
    this.navStack.pushPath({ name: 'Downloads' });
  }

  private pushSettings(): void {
    this.navStack.pushPath({ name: 'Settings' });
  }

  private pushAbout(): void {
    this.navStack.pushPath({ name: 'About' });
  }

  build() {
    Navigation(this.navStack) {
      Stack({ alignContent: Alignment.TopStart }) {
        // 背景铺满全屏（含状态栏与底部导航条）
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.color_bg'))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        Column({ space: 0 }) {
        // 顶部搜索栏
        Row({ space: 8 }) {
          Search({
            placeholder: '搜索电影 / 电视剧 / 主播',
            value: $$this.searchValue
          })
            .layoutWeight(1)
            .height(this.wide() ? 44 : 36)
            .searchButton('搜索', { fontSize: 14, fontColor: $r('app.color.color_primary') })
            .onSubmit((value: string) => {
              this.onSearchSubmit();
            })
        }
        .width('100%')
        // 页面根节点已被框架放在状态栏下方（实测平板状态栏 45vp），
        // 所以这里的 top 是「状态栏之外再多留多少」——手机上 10vp 刚好，
        // 平板再留 10vp 就显空了，压到 4vp。
        .padding({
          left: this.wide() ? 16 : 12,
          right: this.wide() ? 16 : 12,
          top: this.wide() ? 4 : 10,
          bottom: this.wide() ? 6 : 4
        })

        // Tabs 保留原生 tabBar。
        // 血的教训 —— 以下任一作法都会让 Tabs 内容区整块塌陷（页面只剩搜索栏 + 纯黑底）：
        //   · .ignoreLayoutSafeArea(...)
        //   · .expandSafeArea([], [])
        //   · .barHeight(0)
        //   · barHeight 用任何依赖 @State 的表达式（会触发 Tabs 重算失败）
        // 因此 barHeight 必须是纯常量；底部留白在窗口层用 setWindowLayoutFullScreen 根治。
        Tabs({ barPosition: BarPosition.End, index: this.activeTab }) {
          TabContent() {
            this.homeContent()
          }
          .tabBar(this.homeTabBar())

          TabContent() {
            this.liveContent()
          }
          .tabBar(this.liveTabBar())

          TabContent() {
            this.mineContent()
          }
          .tabBar(this.mineTabBar())
        }
        .barHeight(58)
        .barBackgroundColor($r('app.color.color_bg'))
        .animationDuration(0)
        .onChange((index: number) => {
          this.activeTab = index;
          if (index === 1) {
            // 进直播页就把各源的频道数补上，省得用户以为「列表里没有频道」
            this.prefetchLiveCounts(false);
          }
        })
        .layoutWeight(1)
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.color_bg'))
        // 页面根被框架让出了底部安全区（平板实测 26vp），导航条因此浮在屏幕底部之上，
        // 底下一整条空白 —— 这就是「导航离屏幕底太远」的真正原因。
        // 把这一层延伸到安全区里，Tabs 才会真正落到物理底边。
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    // 实测：页面根与 Navigation 都是 [0,133][1276,2848]（已全屏），
    // 但内部 NavBarContent 只到 2456，差的 392px 正是「底部悬空」。
    // 那是 Navigation 为自带标题栏/工具栏预留的空间，必须全部关掉。
    .hideTitleBar(true)
    .hideToolBar(true)
    .hideBackButton(true)
    .mode(NavigationMode.Stack)
    .navDestination(this.pageMap)
  }



  // ---------- 路由表 ----------

  @Builder
  pageMap(name: string, param: Object) {
    if (name === 'Search') {
      SearchResultPage({
        navPathStack: this.navStack,
        keyword: (param as SearchPageParam).keyword
      })
    } else if (name === 'Detail') {
      DetailPage({
        navPathStack: this.navStack,
        sourceKey: (param as DetailPageParam).sourceKey,
        vodId: (param as DetailPageParam).vodId,
        title: (param as DetailPageParam).title
      })
    } else if (name === 'Player') {
      PlayerPage({
        navPathStack: this.navStack,
        sourceKey: (param as PlayerPageParam).sourceKey,
        vodId: (param as PlayerPageParam).vodId,
        episode: (param as PlayerPageParam).episode,
        episodeName: (param as PlayerPageParam).episodeName,
        title: (param as PlayerPageParam).title,
        positionMs: (param as PlayerPageParam).positionMs,
        offlineDir: (param as PlayerPageParam).offlineDir,
        episodeUrl: (param as PlayerPageParam).episodeUrl !== undefined ? (param as PlayerPageParam).episodeUrl : '',
        pic: (param as PlayerPageParam).pic !== undefined ? (param as PlayerPageParam).pic : '',
        lineIndex: (param as PlayerPageParam).lineIndex !== undefined ? (param as PlayerPageParam).lineIndex : 0
      })
    } else if (name === 'LivePlayer') {
      LivePlayerPage({
        navPathStack: this.navStack,
        channelUrl: (param as LivePlayerPageParam).channelUrl,
        channelName: (param as LivePlayerPageParam).channelName,
        sourceKey: (param as LivePlayerPageParam).sourceKey,
        sourceName: (param as LivePlayerPageParam).sourceName,
        logo: (param as LivePlayerPageParam).logo,
        tvgId: (param as LivePlayerPageParam).tvgId
      })
    } else if (name === 'History') {
      HistoryPage({
        navPathStack: this.navStack,
        mode: (param as HistoryPageParam).mode
      })
    } else if (name === 'Sources') {
      SourcesPage({ navPathStack: this.navStack })
    } else if (name === 'Downloads') {
      DownloadsPage({ navPathStack: this.navStack })
    } else if (name === 'Settings') {
      SettingsPage({ navPathStack: this.navStack })
    } else if (name === 'About') {
      AboutPage({ navPathStack: this.navStack })
    }
  }

  // ---------- Tab 栏 ----------

  @Builder
  homeTabBar() {
    this.tabBarItem($r('app.media.ic_home'), '首页', 0)
  }

  @Builder
  liveTabBar() {
    this.tabBarItem($r('app.media.ic_live'), '直播', 1)
  }

  @Builder
  mineTabBar() {
    this.tabBarItem($r('app.media.ic_star'), '我的', 2)
  }

  /**
   * 单个 tab 项。
   *
   * 高亮判断必须写在函数体里直接读 this.activeTab，不能靠入参传布尔值。
   * 原因：@Builder 的参数是「按值传递」——即使传进来的是状态变量，
   * 状态变化也不会触发 @Builder 内部 UI 刷新。之前传的 active: boolean
   * 被永久固定在首次渲染那一刻（activeTab=0），于是无论切到直播还是我的，
   * 都只有「首页」保持标红。改成传恒定的 tabIndex，让判断发生在渲染期。
   *
   * 另外：Column 自带背景色 + expandSafeArea(BOTTOM)，
   * 让导航栏底色一直铺到屏幕物理底边（覆盖系统手势条那条黑带），
   * 图标仍按 barHeight 内部居中，不会被手势条压住。
   */
  @Builder
  tabBarItem(icon: Resource, label: string, tabIndex: number) {
    Column({ space: this.wide() ? 4 : 2 }) {
      Image(icon)
        .width(this.tabIconSize())
        .height(this.tabIconSize())
        .opacity(this.activeTab === tabIndex ? 1 : 0.45)
      Text(label)
        .fontSize(this.wide() ? 13 : 10)
        .fontColor(this.activeTab === tabIndex ? $r('app.color.color_primary') : $r('app.color.color_text_secondary'))
    }
    .width('100%')
    .height('100%')
    .padding({ bottom: 2 })
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.color_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  // ---------- 首页 ----------

  /**
   * 推荐网格的卡片目标宽度（vp）。
   * 手机 3 列时约 120vp；平板沿用同一密度，否则列数一多封面又被拉大，
   * 「一屏看到更多片」就没有意义了。
   */
  private static readonly REC_CARD_W: number = 120;
  /** 网格左右内边距合计（16 + 16） */
  private static readonly REC_SIDE_PAD: number = 32;
  /** 网格列间距 */
  private static readonly REC_COL_GAP: number = 10;

  /** 宽屏判定：≥600vp 视为平板 / 折叠展开 / 2in1 */
  private wide(): boolean {
    return this.homeWidth >= 600;
  }

  /**
   * 底部导航图标尺寸。平板上一律 24vp 会显得又小又空，
   * 放大到 32vp（配合文字 13fp，总高约 53vp）仍然塞得进 58vp 的 barHeight。
   * 注意 barHeight 必须保持纯常量 —— 它一旦依赖状态，Tabs 内容区会整块塌陷。
   */
  private tabIconSize(): number {
    return this.wide() ? 32 : 24;
  }

  /** 推荐网格列数：按可用宽度推算，手机 3 列、平板最多 8 列 */
  private recColumns(): number {
    const w: number = this.homeWidth > 0 ? this.homeWidth : 411;
    const span: number = IndexPage.REC_CARD_W + IndexPage.REC_COL_GAP;
    let n: number = Math.round((w - IndexPage.REC_SIDE_PAD + IndexPage.REC_COL_GAP) / span);
    if (n < 3) {
      n = 3;
    }
    if (n > 8) {
      n = 8;
    }
    return n;
  }

  /** Grid 的 columnsTemplate，形如 "1fr 1fr 1fr …" */
  private recColumnsTemplate(): string {
    const n: number = this.recColumns();
    let tpl: string = '1fr';
    for (let i = 1; i < n; i++) {
      tpl += ' 1fr';
    }
    return tpl;
  }

  // 分类标签在平板上按比例放大，手机上保持原样。
  private chipFont(): number {
    return this.wide() ? 16 : 13;
  }

  private chipPadH(): number {
    return this.wide() ? 18 : 14;
  }

  private chipPadV(): number {
    return this.wide() ? 9 : 6;
  }

  private chipRadius(): number {
    return this.wide() ? 18 : 14;
  }

  private chipGap(): number {
    return this.wide() ? 10 : 8;
  }

  /** 横向标签行的固定高度：文字 13fp + 上下 padding 12vp ≈ 30vp，留余量 */
  private chipRowH(): number {
    return this.wide() ? 44 : 36;
  }

  /**
   * 筛选条是「二级」控件，字号和留白都比分类标签收一档。
   * 两排用同样尺寸时，「综合推荐」这种四字标签会把视觉重量压过「电影/剧集」，
   * 一眼看过去像是分类按钮变小了。
   */
  private filterFont(): number {
    // 平板 16→14；手机 13→12（再小就难认了）
    return this.wide() ? this.chipFont() - 2 : this.chipFont() - 1;
  }

  private filterPadH(): number {
    return this.chipPadH() - 4;
  }

  private filterPadV(): number {
    // 平板 9→7；手机保持 6，别把可点高度压到 22vp 以下
    return this.wide() ? this.chipPadV() - 2 : this.chipPadV();
  }

  @Builder
  homeContent() {
    // 外层 Stack 只为了叠两个浮层（顶部提示 / 返回顶部按钮）。
    // 不用 layoutWeight 之外的技巧包 Scroll：Tabs 内容区一旦塌陷整页就只剩搜索栏。
    Stack({ alignContent: Alignment.BottomEnd }) {
      Scroll(this.homeScroller) {
      Column({ space: 12 }) {
        // 继续观看（外层 Column 恒定存在，只为量这块高度：
        // 播放后会凭空多出这一块，把下面的推荐整体顶下去 —— 用高度增量补偿滚动偏移）
        Column() {
        if (this.homeHistory.length > 0) {
          SectionHeader({
            headerText: '继续观看',
            headerAction: '查看全部',
            onActionClick: () => {
              this.pushHistory();
            }
          })
          Scroll() {
            Row({ space: 8 }) {
              ForEach(this.homeHistory, (rec: PlayRecord) => {
                VodCard({
                  cardTitle: rec.name,
                  cardPic: rec.pic !== undefined ? rec.pic : '',
                  cardRemarks: rec.episodeName !== undefined ? rec.episodeName : '',
                  cardSource: '',
                  cardProgress: this.progressWidth(rec),
                  cardCompact: true,
                  onCardClick: () => {
                    this.continuePlay(rec);
                  }
                })
                // 封面只要推荐卡的一半大：原来 134vp 宽的海报连标题条要占 220vp，
                // 一条「继续观看」就把首屏压掉了近三分之一。
                .width(this.wide() ? 68 : 60)
              // key 必须拼上 pic：封面是后来回填的，key 不变 ArkUI 就不会重建这一项，
                // 表现就是数据已写好、界面仍是一块灰底。
              }, (rec: PlayRecord) => rec.sourceKey + '_' + rec.vodId + '_'
                + (rec.pic !== undefined ? rec.pic : ''))
            }
            .padding({ left: 16, right: 16 })
            // 横向 Scroll 里的内容比视口窄时会被居中，看起来像整排"漂"在屏幕中间。
            // minWidth 100% 让 Row 至少撑满视口（从左边开始排），
            // 内容更宽时又允许它自然增长，滚动不受影响。
            .constraintSize({ minWidth: '100%' })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
        }
        }
        .width('100%')
        .onAreaChange((oldArea: Area, newArea: Area) => {
          const h: number = newArea.height as number;
          const delta: number = h - this.historyBlockH;
          this.historyBlockH = h;
          // 高度变化（继续观看出现/消失）时把滚动偏移加回同样的量，
          // 视口内容就不会被顶动 —— 否则表现为「播放后返回首页位置变了」。
          if (Math.abs(delta) > 1 && Math.abs(delta) < 400) {
            try {
              const off: number = this.homeScroller.currentOffset().yOffset;
              const target: number = off + delta;
              this.homeScroller.scrollTo({ xOffset: 0, yOffset: target > 0 ? target : 0, animation: false });
            } catch (e) {
              // Scroller 尚未绑定（首帧）时忽略
            }
          }
        })

        // 推荐
        SectionHeader({
          headerText: '推荐',
          // 原来是「换一换」，但它实际是翻到下一页（每页 20 条），
          // 叫「换一批」才对得上，用户不会以为只是把当前这批重新排个序。
          headerAction: '换一批',
          onActionClick: () => {
            this.nextRecommend();
          }
        })

        // 内容分类标签（豆瓣排行是榜单，没有分类/筛选概念，两排 chip 一起隐藏）
        if (!this.recRank) {
        Scroll() {
          Row({ space: this.chipGap() }) {
            ForEach(REC_CATS, (cat: RecCat) => {
              this.recChip(cat)
            }, (cat: RecCat) => cat.key)
          }
          .padding({ left: 16, right: 16 })
          .constraintSize({ minWidth: '100%' })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        // 横向 Scroll 不给高度时高度靠内容撑，嵌在纵向 Scroll 里容易算出 0
        // （上一版在平板上「推荐」标题和这排标签会整行不显示）。
        // 显式给高度，任何屏宽下都稳定占位。
        .height(this.chipRowH())
        }

        // 筛选 / 排序：在分类之下再做一层「排序 · 类型 · 地区」细分
        // 左侧固定「快速筛选：」说明标签（不随横向滚动移出视野），
        // 颜色走 color_text_secondary，base/dark 两套资源自动适配深浅主题。
        if (!this.recRank) {
        Row({ space: this.chipGap() }) {
          Text('快速筛选：')
            .fontSize(this.filterFont())
            .fontColor($r('app.color.color_text_secondary'))
            .maxLines(1)
          Scroll() {
            Row({ space: this.chipGap() }) {
              this.filterChip('sort')
              this.filterChip('genre')
              this.filterChip('country')
              if (this.hasFilter()) {
                this.resetFilterChip()
              }
            }
            .padding({ right: 16 })
            .constraintSize({ minWidth: '100%' })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .layoutWeight(1)
        }
        .padding({ left: 16 })
        .width('100%')
        .height(this.chipRowH())
        .alignItems(VerticalAlign.Center)
        }

        if (this.filterPanel !== '') {
          this.filterPanelView()
        }

        if (this.recommendItems.length === 0) {
          if (this.recommendLoading) {
            LoadingView().height(260)
          } else {
            EmptyView({
              emptyText: this.hasFilter()
                ? '当前筛选没有结果，试试放宽条件或点「重置」'
                : '暂无推荐，请检查网络或切换推荐来源'
            })
          }
        } else {
          Grid() {
            ForEach(this.recommendItems, (item: RecommendItem) => {
              GridItem() {
                VodCard({
                  cardTitle: item.title,
                  cardPic: item.cover,
                  // 评分走海报下沿横幅样式；无评分（空/0）不显示，免得满屏「评分： 0」
                  cardRemarks: '',
                  cardRating: item.rating !== undefined && item.rating !== '' && item.rating !== '0'
                    ? '评分： ' + item.rating : '',
                  cardSource: '',
                  onCardClick: () => {
                    this.openRecommend(item);
                  }
                })
              }
            }, (item: RecommendItem) => item.id)
          }
          .columnsTemplate(this.recColumnsTemplate())
          .columnsGap(IndexPage.REC_COL_GAP)
          .rowsGap(this.wide() ? 16 : 14)
          .padding({ left: 16, right: 16 })
          .width('100%')
          .opacity(this.recSwitching ? 0.45 : 1)
        }

        if (this.recommendItems.length > 0) {
          this.loadMoreFooter()
        }
      }
      .width('100%')
      .padding({ bottom: 20 })
      // 实测首页可用宽度：旋转、分屏、折叠展开都会改变它，所以不能只在启动时取一次。
      // 阈值 1vp 防止亚像素抖动引发无谓重排。
      .onAreaChange((oldArea: Area, newArea: Area) => {
        const w: number = newArea.width as number;
        if (w > 0 && Math.abs(w - this.homeWidth) > 1) {
          this.homeWidth = w;
        }
      })
      }
      .scrollBar(BarState.Off)
      .width('100%')
      .height('100%')
      // 拉到顶/底都有一手回弹；alwaysEnabled 让内容不满一屏时也能拉出弹簧
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      // 只在「用户滚动结束」时记录位置：横竖屏重排引起的偏移夹取不会触发 onScrollStop，
      // 不会把被夹后的错误偏移当成用户的真实位置
      .onScrollStop(() => {
        try {
          this.homeOffset = this.homeScroller.currentOffset().yOffset;
        } catch (e) {
          // Scroller 未绑定
        }
      })
      // 瀑布流：滑到底自动追加下一页
      .onScrollEdge((side: Edge) => {
        if (side === Edge.Bottom) {
          this.loadMoreRecommend();
        }
      })
      // 惯性滚动不会逐帧回调 onScroll，onDidScroll 才是全程都有的；
      // 偏移量直接问 Scroller 要绝对值，比累加回调里的增量稳妥。
      .onDidScroll(() => {
        try {
          this.syncBackTop(this.homeScroller.currentOffset().yOffset);
        } catch (e) {
          // Scroller 未绑定
        }
      })
      // 弹簧效果本身是系统行为，这里只在「已经贴顶还继续往下拽」时弹提示。
      // 用 touch 而不是 onScrollEdge：后者在贴顶时再拉不会重复触发。
      .onTouch((e: TouchEvent) => {
        if (e.type === TouchType.Down) {
          this.touchStartY = e.touches.length > 0 ? e.touches[0].windowY : 0;
          this.pullHintFired = false;
        } else if (e.type === TouchType.Move) {
          if (!this.pullHintFired && e.touches.length > 0) {
            const dy: number = e.touches[0].windowY - this.touchStartY;
            if (dy > 44 && this.homeAtTop()) {
              this.pullHintFired = true;
              this.flashPullHint();
            }
          }
        } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
          this.pullHintFired = false;
        }
      })

      // 顶部提示层：整屏透明、不吃触摸，只在最上方居中挂一条小胶囊
      Column() {
        if (this.pullTopHint) {
          Row() {
            Text(PULL_TOP_HINT)
              .fontSize(this.wide() ? 14 : 12)
              .fontColor($r('app.color.color_text'))
              .maxLines(1)
          }
          .padding({ left: 14, right: 14, top: 7, bottom: 7 })
          .backgroundColor($r('app.color.color_chip_bg'))
          .borderRadius(16)
          .border({ width: 1, color: $r('app.color.color_divider') })
          .shadow({ radius: 12, color: '#26000000', offsetX: 0, offsetY: 2 })
          .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -12 }))
            .animation({ duration: 180, curve: Curve.EaseOut }))
        }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Center)
      .padding({ top: 10 })
      .hitTestBehavior(HitTestMode.None)

      // 返回顶部：滚过 50 行才出现，浮在右下角（TabBar 之上）
      if (this.showBackTop) {
        Column() {
          Image($r('app.media.ic_back_top'))
            .width(22)
            .height(22)
            // SVG 才能染色，两套主题共用一份资源
            .fillColor($r('app.color.color_text'))
        }
        .width(46)
        .height(46)
        .borderRadius(23)
        .backgroundColor($r('app.color.color_card'))
        .border({ width: 1, color: $r('app.color.color_divider') })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .shadow({ radius: 14, color: '#33000000', offsetX: 0, offsetY: 3 })
        .margin({ right: 16, bottom: 20 })
        .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.85, y: 0.85 }))
          .animation({ duration: 180, curve: Curve.EaseOut }))
        .onClick(() => {
          this.backToTop();
        })
      }
    }
    .width('100%')
    .height('100%')
    .layoutWeight(1)
  }

  @Builder
  recChip(cat: RecCat) {
    Text(cat.label)
      .fontSize(this.chipFont())
      .fontColor(this.recCatKey === cat.key ? Color.White : $r('app.color.color_text'))
      .backgroundColor(this.recCatKey === cat.key ? $r('app.color.color_primary') : $r('app.color.color_chip_bg'))
      .borderRadius(this.chipRadius())
      .padding({ left: this.chipPadH(), right: this.chipPadH(), top: this.chipPadV(), bottom: this.chipPadV() })
      .onClick(() => {
        if (this.recCatKey !== cat.key) {
          this.recCatKey = cat.key;
          this.recPageStart = 0;
          this.loadRecommend();
        }
      })
  }

  /**
   * 瀑布流底部提示，三态互斥：正在加载 / 还有更多 / 到底了。
   * 「还有更多」做成可点 —— 部分机型上 onScrollEdge 不触发，
   * 留一个手动入口才不会把用户卡在这儿。
   */
  @Builder
  loadMoreFooter() {
    Row() {
      if (this.recLoadingMore) {
        LoadingView({ tipText: '正在加载更多…' })
      } else if (this.recHasMore) {
        Text('上滑或点击加载更多')
          .fontSize(13)
          .fontColor($r('app.color.color_text_secondary'))
      } else {
        Text('已经到底了')
          .fontSize(13)
          .fontColor($r('app.color.color_text_secondary'))
          .opacity(0.7)
      }
    }
    .width('100%')
    .height(this.recLoadingMore ? 84 : 56)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.loadMoreRecommend();
    })
  }

  /**
   * 筛选 chip。
   * 只传恒定的 kind，文案与高亮都在函数体里读 this.xxx ——
   * @Builder 的参数是按值传的，把 label / active 当参数传进来会被固定在首帧，
   * 点选后界面不会变（底部导航踩过同一个坑）。
   */
  @Builder
  filterChip(kind: string) {
    Text(this.filterLabel(kind))
      .fontSize(this.filterFont())
      .fontColor(this.filterActive(kind) ? Color.White : $r('app.color.color_text_secondary'))
      .backgroundColor(this.filterActive(kind) ? $r('app.color.color_primary') : $r('app.color.color_chip_bg'))
      .borderRadius(this.filterPadV() + this.filterFont())
      .padding({ left: this.filterPadH(), right: this.filterPadH(), top: this.filterPadV(), bottom: this.filterPadV() })
      .onClick(() => {
        this.filterPanel = this.filterPanel === kind ? '' : kind;
      })
  }

  @Builder
  resetFilterChip() {
    Text('重置')
      .fontSize(this.filterFont())
      .fontColor($r('app.color.color_text_secondary'))
      .backgroundColor($r('app.color.color_chip_bg'))
      .borderRadius(this.filterPadV() + this.filterFont())
      .padding({ left: this.filterPadH(), right: this.filterPadH(), top: this.filterPadV(), bottom: this.filterPadV() })
      .onClick(() => {
        this.clearFilter();
      })
  }

  /** 展开的筛选面板：标题 + 自动换行的选项 chip */
  @Builder
  filterPanelView() {
    // 左右留白放在外层 Column 的 padding 上，而不是给卡片加 margin ——
    // 卡片本身 .width('100%')，再叠横向 margin 会撑出屏外 32vp。
    Column() {
      Column({ space: 10 }) {
        Row() {
          Text(this.filterPanelTitle())
            .fontSize(12)
            .fontColor($r('app.color.color_text_secondary'))
            .layoutWeight(1)
            .textAlign(TextAlign.Start)
          Text('收起')
            .fontSize(12)
            .fontColor($r('app.color.color_primary'))
            .padding({ left: 10, right: 2, top: 2, bottom: 2 })
            .onClick(() => {
              this.filterPanel = '';
            })
        }
        .width('100%')

        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.filterOptions(), (opt: string) => {
            this.filterOptionChip(opt)
          }, (opt: string) => this.filterPanel + '|' + opt + '|' + (this.isOptionSelected(opt) ? '1' : '0'))
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 4 })
      .backgroundColor($r('app.color.color_card'))
      .borderRadius(10)
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
  }

  @Builder
  filterOptionChip(opt: string) {
    Text(opt)
      .fontSize(this.chipFont() - 1)
      .fontColor(this.isOptionSelected(opt) ? Color.White : $r('app.color.color_text'))
      .backgroundColor(this.isOptionSelected(opt) ? $r('app.color.color_primary') : $r('app.color.color_chip_bg'))
      .borderRadius(this.chipRadius() - 2)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        this.pickOption(opt);
      })
  }

  // ---------- 直播 ----------

  @Builder
  liveContent() {
    // 外层 Stack 只为了在底部叠一个「收起」入口：
    // 频道多的源展开后能滚出两屏以上，分组标题早被顶出视野，
    // 想换源就得一路滑回去 —— 给个常驻底部的收起按钮省掉这段路。
    Stack({ alignContent: Alignment.Bottom }) {
      Column({ space: 0 }) {
        Row({ space: 8 }) {
          Text('直播')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.color_text'))
            .layoutWeight(1)
          Text('刷新')
            .fontSize(14)
            .fontColor($r('app.color.color_primary'))
            .padding({ left: 10, right: 10, top: 8, bottom: 8 })
            .onClick(() => {
              this.refreshLiveGroups();
              // 刷新后立刻开始统计各源频道数，不用等用户逐个展开才看得到
              this.prefetchLiveCounts(true);
              this.toast('正在刷新各直播源的频道数');
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 8 })

        if (this.liveGroups.length === 0) {
          EmptyView({ emptyText: '暂无直播源，请前往「我的 → 视频源管理」添加' })
        } else {
          List({ space: 10, scroller: this.liveScroller }) {
            ForEach(this.liveGroups, (group: LiveGroupState) => {
              ListItem() {
                Column({ space: 8 }) {
                  Row({ space: 8 }) {
                    Image($r('app.media.ic_live'))
                      .width(20)
                      .height(20)
                    Text(group.sourceName)
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.color_text'))
                      .layoutWeight(1)
                      .maxLines(1)
                    if (group.loaded) {
                      Text(group.channels.length + ' 个频道')
                        .fontSize(11)
                        .fontColor($r('app.color.color_text_secondary'))
                    } else if (group.loading) {
                      Text('统计中…')
                        .fontSize(11)
                        .fontColor($r('app.color.color_text_secondary'))
                    }
                    Image($r('app.media.ic_back'))
                      .width(16)
                      .height(16)
                      .rotate({ angle: this.arrowAngle(group) })
                      .opacity(0.4)
                  }
                  .width('100%')
                  .onClick(() => {
                    this.toggleLiveGroup(group.sourceKey);
                  })

                  if (group.expanded) {
                    if (group.loading) {
                      LoadingView({ tipText: '加载频道…' }).height(90)
                    } else if (group.error !== '') {
                      Text(group.error)
                        .fontSize(12)
                        .fontColor($r('app.color.color_warning'))
                        .width('100%')
                        .textAlign(TextAlign.Start)
                    } else if (group.channels.length === 0) {
                      Text('未获取到频道')
                        .fontSize(12)
                        .fontColor($r('app.color.color_text_secondary'))
                        .width('100%')
                        .textAlign(TextAlign.Start)
                    } else {
                      Column({ space: 6 }) {
                        ForEach(group.channels.slice(0, 300), (ch: LiveChannel) => {
                          // 频道行以「台标」为主视觉：左台标 + 右侧小字频道名/节目单。
                          // 纯文字列表很难一眼认出是哪个台，台标才是 IPTV 的正确形态。
                          Row({ space: 10 }) {
                            Stack({ alignContent: Alignment.Center }) {
                              if (ch.logo !== undefined && ch.logo !== '') {
                                NetImage({ url: ch.logo })
                                  .width(46)
                                  .height(30)
                                  .borderRadius(4)
                              } else {
                                Text(ch.name.length > 0 ? ch.name.substring(0, 1) : '?')
                                  .fontSize(14)
                                  .fontColor($r('app.color.color_text_secondary'))
                              }
                            }
                            .width(46)
                            .height(30)
                            .backgroundColor($r('app.color.color_chip_bg'))
                            .borderRadius(4)
                            .clip(true)

                            Column({ space: 2 }) {
                              Text(ch.name)
                                .fontSize(12)
                                .fontColor($r('app.color.color_text'))
                                .maxLines(1)
                                .textOverflow({ overflow: TextOverflow.Ellipsis })
                                .width('100%')
                                .textAlign(TextAlign.Start)
                              if (this.epgTextFor(group, ch) !== '') {
                                Text(this.epgTextFor(group, ch))
                                  .fontSize(10)
                                  .fontColor($r('app.color.color_text_secondary'))
                                  .maxLines(1)
                                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                                  .width('100%')
                                  .textAlign(TextAlign.Start)
                              }
                            }
                            .layoutWeight(1)
                            .alignItems(HorizontalAlign.Start)
                          }
                          .width('100%')
                          .padding({ left: 8, right: 4, top: 5, bottom: 5 })
                          .onClick(() => {
                            this.openLive(group, ch);
                          })
                        }, (ch: LiveChannel) => ch.id)
                      }
                      .width('100%')
                    }
                  }
                }
                .width('100%')
                .padding(12)
                .backgroundColor($r('app.color.color_card'))
                .borderRadius(10)
              }
            }, (group: LiveGroupState) => this.liveGroupKey(group))
          }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        // 底部有「收起」浮层时多留 72vp，否则最后一条频道会被浮层压住点不到
        .padding({ left: 16, right: 16, bottom: this.longExpandedGroup() !== null ? 72 : 16 })
      }
      }
      .width('100%')
      .height('100%')

      if (this.longExpandedGroup() !== null) {
        Row({ space: 8 }) {
          Text('收起频道列表')
            .fontSize(13)
            .fontColor(Color.White)
          // 按钮底色固定深色，箭头必须恒白：ic_back 是主题色 PNG（浅色主题下深黑、
          // 和底色融在一起），换专用的白色箭头图，不随主题变。
          Image($r('app.media.ic_arrow_up_white'))
            .width(14)
            .height(14)
            .rotate({ angle: 90 })
        }
        .padding({ left: 18, right: 18, top: 10, bottom: 10 })
        .backgroundColor('#E61A1A1E')
        .borderRadius(22)
        .margin({ bottom: 22 })
        .onClick(() => {
          this.collapseLongGroups();
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  // ---------- 我的 ----------

  @Builder
  mineContent() {
    Scroll() {
      Column({ space: 10 }) {
        Column({ space: 4 }) {
          Text('LibreTV')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.color_text'))
            .width('100%')
            .textAlign(TextAlign.Start)
          Text('多源聚合影视播放器 · 点播 / 直播 / 离线下载')
            .fontSize(12)
            .fontColor($r('app.color.color_text_secondary'))
            .width('100%')
            .textAlign(TextAlign.Start)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 8 })

        Column({ space: 0 }) {
          SettingsRow({
            rowTitle: '播放历史',
            rowValue: this.homeHistory.length > 0 ? this.homeHistory.length + ' 条' : '',
            onRowClick: () => {
              this.pushHistory();
            }
          })
          SettingsRow({
            rowTitle: '我的收藏',
            rowValue: this.favCount > 0 ? this.favCount + ' 个' : '',
            onRowClick: () => {
              this.pushFavorites();
            }
          })
          SettingsRow({
            rowTitle: '视频源管理',
            rowValue: this.vodCount + ' 点播 / ' + this.liveCount + ' 直播',
            onRowClick: () => {
              this.pushSources();
            }
          })
          SettingsRow({
            rowTitle: '下载管理',
            rowValue: this.downloadCount > 0 ? this.downloadCount + ' 个任务' : '',
            onRowClick: () => {
              this.pushDownloads();
            }
          })
          SettingsRow({
            rowTitle: '设置',
            rowValue: '',
            onRowClick: () => {
              this.pushSettings();
            }
          })
          // 版本号运行时读取（common/AppVersion），不要再写死字面量：
          // 写死过 'v1.0.0'，结果「关于」页改了、这一行忘了改
          SettingsRow({
            rowTitle: '关于',
            rowValue: AppVersion.display(),
            onRowClick: () => {
              this.pushAbout();
            }
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })

        Text('仅供个人学习研究使用 · 详见上方「关于」')
          .fontSize(11)
          .fontColor($r('app.color.color_text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 16, bottom: 24 })
      }
      .width('100%')
      // 同详情页：内容不满一屏时 Scroll 会把子内容垂直居中，顶部凭空多出大片空白。
      // 用 minHeight 撑满视口强制顶对齐。
      .constraintSize({ minHeight: '100%' })
    }
    .scrollBar(BarState.Off)
    .layoutWeight(1)
  }
}
