import { MergedVideo, SearchItem, RecommendItem, VideoDetail } from './Types';
import { PosterCardData, PosterCardInfo } from './PosterCardData';
import { PosterOrigin } from './DiscoveryLayout';
import { Utils } from '../common/Utils';

export interface SearchDiscoveryEntry {
  item: RecommendItem;
  origin: PosterOrigin;
  openId: number;
  searchResult: MergedVideo;
  searchUpdatedAt: number;
  searchKeyword: string;
}

/** One selected title/year, with source-provided metadata until an explicit Douban ID can enrich it. */
export class SearchDiscovery {
  static key(result: MergedVideo): string {
    const first = result.items[0];
    return JSON.stringify([Utils.normalizeTitle(result.name), result.year || '',
      first !== undefined ? first.sourceKey : '', first !== undefined ? first.vodId : '']);
  }

  static doubanId(result: MergedVideo, detail?: VideoDetail): string {
    const candidates = detail !== undefined ? [detail.info.doubanId || ''] : [];
    for (const source of result.items) candidates.push(source.doubanId || '');
    return candidates.find((id: string) => /^\d{7,10}$/.test(id)) || '';
  }

  private static series(result: MergedVideo): boolean {
    if (/电影|片$/.test(result.typeName || '')) return false;
    return /连续剧|电视剧|国产剧|欧美剧|日韩剧|日剧|韩剧|港剧|台剧|泰剧|短剧|剧集|美剧|英剧|动漫|综艺/.test(result.typeName || '') ||
      /(?:更新至|全)\s*\d+\s*集|已完结/.test(result.remarks || '');
  }

  /** The grid keeps its own stable selection identity, independently of any catalogue subject ID. */
  static card(result: MergedVideo): RecommendItem {
    return { id: SearchDiscovery.key(result), title: result.name, cover: result.pic || '',
      isTv: SearchDiscovery.series(result), metadataProvider: 'cms' };
  }

  static entry(result: MergedVideo, origin: PosterOrigin, updatedAt: number, openId: number,
    keyword: string = result.name): SearchDiscoveryEntry {
    const selection = SearchDiscovery.seed(result);
    const item = SearchDiscovery.card(selection);
    const id = SearchDiscovery.doubanId(selection);
    if (id !== '') { item.id = id; item.metadataProvider = 'douban'; }
    return { item: item, origin: origin, openId: openId, searchResult: selection, searchUpdatedAt: updatedAt,
      searchKeyword: keyword.trim() || result.name };
  }

  /** Route parameters retain catalogue text and source IDs, never episode lists or signed playback URLs. */
  static seed(result: MergedVideo): MergedVideo {
    const items = result.items.map((source: SearchItem): SearchItem => ({ sourceKey: source.sourceKey,
      sourceName: source.sourceName, vodId: source.vodId, name: source.name, pic: source.pic,
      year: source.year, area: source.area, typeName: source.typeName, remarks: source.remarks,
      actor: source.actor, director: source.director, doubanId: source.doubanId,
      content: source.content !== undefined ? Utils.stripHtml(source.content).substring(0, 6000) : '' }));
    return { name: result.name, year: result.year, pic: result.pic, typeName: result.typeName,
      area: result.area, remarks: result.remarks, items: items };
  }

  private static names(value: string | undefined): string[] {
    return (value || '').split(/[,，、/|;；]+/).map((name: string) => name.trim()).filter((name: string) => name !== '').slice(0, 12);
  }

  static info(result: MergedVideo, detail?: VideoDetail): PosterCardInfo {
    const pick = (read: (source: SearchItem) => string | undefined): string => {
      for (const source of result.items) { const text = read(source); if (text !== undefined && text.trim() !== '') return text; }
      return '';
    };
    const data = detail !== undefined ? detail.info : undefined;
    const info = PosterCardData.empty(SearchDiscovery.doubanId(result, detail), SearchDiscovery.series(result));
    info.countries = SearchDiscovery.names(data !== undefined ? data.area : result.area);
    info.genres = SearchDiscovery.names(data !== undefined ? data.typeName : result.typeName);
    info.releaseDate = PosterCardData.dateText((data !== undefined ? data.year : result.year) || '');
    info.description = Utils.stripHtml((data !== undefined ? data.desc : '') || pick((source: SearchItem) => source.content)).substring(0, 6000);
    info.directors = SearchDiscovery.names((data !== undefined ? data.director : '') || pick((source: SearchItem) => source.director));
    info.actors = SearchDiscovery.names((data !== undefined ? data.actor : '') || pick((source: SearchItem) => source.actor));
    if (detail !== undefined) {
      info.isSeries = info.isSeries || (!/电影|片$/.test((data !== undefined ? data.typeName : '') || result.typeName || '') && detail.episodes.length > 1);
      info.totalEpisodes = info.isSeries ? detail.episodes.length : 0;
      info.detailsLoaded = true;
    }
    return info;
  }

  static enrich(primary: PosterCardInfo, fallback: PosterCardInfo): PosterCardInfo {
    const result = PosterCardData.fromStatic(primary);
    result.rating = primary.rating; result.shortComments = primary.shortComments; result.liveMetadata = primary.liveMetadata;
    if (result.countries.length === 0) result.countries = fallback.countries;
    if (result.genres.length === 0) result.genres = fallback.genres;
    if (result.releaseDate === '') result.releaseDate = fallback.releaseDate;
    if (result.directors.length === 0) result.directors = fallback.directors;
    if (result.actors.length === 0) result.actors = fallback.actors;
    if (result.description === '') result.description = fallback.description;
    if (result.totalEpisodes === 0) result.totalEpisodes = fallback.totalEpisodes;
    result.isSeries = primary.isSeries || fallback.isSeries;
    return result;
  }

  /** A refresh cannot mix a different year/remake into the film the user selected. */
  static selected(selection: MergedVideo, results: MergedVideo[]): MergedVideo[] {
    const matching = results.filter((result: MergedVideo) => {
      if (Utils.normalizeTitle(result.name) !== Utils.normalizeTitle(selection.name)) return false;
      const sameSource = result.items.some((source: SearchItem) => selection.items.some((old: SearchItem) =>
        old.sourceKey === source.sourceKey && old.vodId === source.vodId));
      if (selection.year) return result.year ? selection.year === result.year : sameSource;
      return sameSource || !result.year;
    });
    return matching.length > 0 ? matching : [selection];
  }
}
