import { MergedVideo, SearchItem, Settings } from '../model/Types';
import { SearchService } from '../model/SearchService';
import { SourceManager } from './SourceManager';
import { SearchCacheStorage } from './SearchCacheStorage';
import { Utils } from '../common/Utils';

export interface DiscoverySearchCache {
  keyword: string;
  context: string;
  updatedAt: number;
  results: MergedVideo[];
}
export interface DiscoverySearchReply {
  cache: DiscoverySearchCache | null;
  failedCount: number;
  error: string;
}

/** Cache identity includes the user's configured sources and adult-filter policy. */
export class DiscoverySearchService {
  private static readonly pending: Map<string, Promise<DiscoverySearchReply>> = new Map();
  static readonly TTL: number = 24 * 60 * 60 * 1000;

  private static context(settings: Settings): string {
    return JSON.stringify(SourceManager.shared().getVodSources()
      .filter((source) => source.enabled && (!settings.adultFilter || !source.isAdult))
      .map((source) => source.key + '|' + source.name + '|' + source.url + '|' + (source.detail || ''))
      .sort()) + '|' + settings.adultFilter.toString();
  }

  private static key(keyword: string, context: string): string {
    const identity = keyword.trim() + '\n' + context;
    return Utils.stableId(identity) + '-' + Utils.stableId('discovery-v1\n' + identity);
  }

  static stale(cache: DiscoverySearchCache): boolean {
    return Date.now() - cache.updatedAt >= DiscoverySearchService.TTL;
  }

  static inFlight(keyword: string, settings: Settings): boolean {
    return DiscoverySearchService.pending.has(keyword.trim() + '\n' + DiscoverySearchService.context(settings));
  }

  static peek(keyword: string, settings: Settings): DiscoverySearchCache | null {
    const context = DiscoverySearchService.context(settings);
    try {
      const text = SearchCacheStorage.read(DiscoverySearchService.key(keyword, context));
      if (text === '' || text.length > 2000000) return null;
      const entry = JSON.parse(text) as DiscoverySearchCache;
      if (entry.keyword !== keyword.trim() || entry.context !== context || !Number.isFinite(entry.updatedAt) ||
        entry.updatedAt <= 0 || entry.updatedAt > Date.now() + 60000 || !Array.isArray(entry.results)) return null;
      const results = DiscoverySearchService.clean(entry.results);
      if (results.length !== entry.results.length) return null;
      return { keyword: entry.keyword, context: context, updatedAt: entry.updatedAt, results: results };
    } catch (e) { return null; }
  }

  static refresh(keyword: string, settings: Settings): Promise<DiscoverySearchReply> {
    const wd = keyword.trim();
    const context = DiscoverySearchService.context(settings);
    const key = wd + '\n' + context;
    const previous = DiscoverySearchService.peek(wd, settings);
    const pending = DiscoverySearchService.pending.get(key);
    if (pending !== undefined) return pending;
    const request = DiscoverySearchService.fetch(wd, context, settings, previous);
    DiscoverySearchService.pending.set(key, request);
    request.finally(() => DiscoverySearchService.pending.delete(key));
    return request;
  }

  /** A completed explicit search is already a fresh aggregate; persist it without fetching it again. */
  static remember(keyword: string, settings: Settings, results: MergedVideo[], updatedAt: number): void {
    const context = DiscoverySearchService.context(settings);
    const cache: DiscoverySearchCache = { keyword: keyword.trim(), context: context, updatedAt: updatedAt,
      results: DiscoverySearchService.clean(results) };
    SearchCacheStorage.write(DiscoverySearchService.key(keyword, context), JSON.stringify(cache));
  }

  private static async fetch(keyword: string, context: string, settings: Settings,
    previous: DiscoverySearchCache | null): Promise<DiscoverySearchReply> {
    try {
      const count = SourceManager.shared().searchableVodSources(settings.adultFilter).length;
      if (count === 0) return { cache: previous, failedCount: 0, error: '当前没有可用片源，已有缓存仍可选择' };
      const response = await SearchService.aggregate(keyword, settings);
      if (response.failedCount >= count || (response.merged.length === 0 && response.failedCount > 0)) {
        return { cache: previous, failedCount: response.failedCount, error: '片源暂时无法更新，保留已有结果' };
      }
      const results = DiscoverySearchService.clean(response.merged)
        .sort((a: MergedVideo, b: MergedVideo) => b.items.length - a.items.length);
      const cache: DiscoverySearchCache = { keyword: keyword, context: context, updatedAt: Date.now(), results: results };
      SearchCacheStorage.write(DiscoverySearchService.key(keyword, context), JSON.stringify(cache));
      return { cache: cache, failedCount: response.failedCount, error: '' };
    } catch (e) { return { cache: previous, failedCount: 0, error: '更新失败，已有结果仍可选择' }; }
  }

  /** Keep only display/selection data, never cache expiring playback URLs or full CMS bodies. */
  private static clean(values: MergedVideo[]): MergedVideo[] {
    const results: MergedVideo[] = [];
    for (const value of values.slice(0, 200)) {
      if (value === null || typeof value !== 'object' || typeof value.name !== 'string' || !Array.isArray(value.items)) continue;
      const items: SearchItem[] = [];
      for (const item of value.items.slice(0, 50)) {
        if (item === null || typeof item !== 'object' || typeof item.sourceKey !== 'string' || item.sourceKey === '' ||
          typeof item.vodId !== 'string' || item.vodId === '' || typeof item.name !== 'string') continue;
        items.push({ sourceKey: item.sourceKey, sourceName: typeof item.sourceName === 'string' ? item.sourceName : '',
          vodId: item.vodId, name: item.name.substring(0, 200),
          remarks: typeof item.remarks === 'string' ? item.remarks.substring(0, 200) : '' });
      }
      if (items.length === 0) continue;
      results.push({ name: value.name.substring(0, 200), items: items,
        year: typeof value.year === 'string' ? value.year.substring(0, 20) : '',
        pic: typeof value.pic === 'string' ? value.pic.substring(0, 2000) : '',
        typeName: typeof value.typeName === 'string' ? value.typeName.substring(0, 100) : '',
        area: typeof value.area === 'string' ? value.area.substring(0, 100) : '',
        remarks: typeof value.remarks === 'string' ? value.remarks.substring(0, 200) : '' });
    }
    return results;
  }
}
