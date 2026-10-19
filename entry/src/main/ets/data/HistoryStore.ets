/**
 * 播放历史 / 收藏 / 搜索历史 / 直播收藏
 */

import { Store } from './Store';
import { PlayRecord, FavoriteItem } from '../model/Types';
import { EventBus, Events } from '../common/EventBus';

export class HistoryStore {
  static readonly MAX_HISTORY = 100;
  static readonly MAX_SEARCH_HISTORY = 20;

  private static readonly KEY_HISTORY = 'play_history';
  private static readonly KEY_FAVORITES = 'favorites';
  private static readonly KEY_SEARCH = 'search_history';
  private static readonly KEY_LIVE_FAV = 'live_favorites';

  private static inst: HistoryStore | null = null;

  static shared(): HistoryStore {
    if (!HistoryStore.inst) {
      HistoryStore.inst = new HistoryStore();
    }
    return HistoryStore.inst;
  }

  // ---------- 播放历史 ----------

  getHistory(): PlayRecord[] {
    const list = HistoryStore.parseRecords(Store.shared().getJson(HistoryStore.KEY_HISTORY));
    list.sort((a, b) => b.updatedAt - a.updatedAt);
    return list;
  }

  getProgress(sourceKey: string, vodId: string): PlayRecord | null {
    const list = HistoryStore.parseRecords(Store.shared().getJson(HistoryStore.KEY_HISTORY));
    for (const r of list) {
      if (r.sourceKey === sourceKey && r.vodId === vodId) {
        return r;
      }
    }
    return null;
  }

  saveProgress(record: PlayRecord): void {
    let list = HistoryStore.parseRecords(Store.shared().getJson(HistoryStore.KEY_HISTORY));
    let found = false;
    for (let i = 0; i < list.length; i++) {
      if (list[i].sourceKey === record.sourceKey && list[i].vodId === record.vodId) {
        // 新记录没带封面时沿用旧封面。
        // 否则某些入口（未命中详情缓存、旧版本传入 undefined）会把已拿到的海报抹掉，
        // 首页「继续观看」就变成空白灰块。
        const newPic: string | undefined = record.pic;
        const oldPic: string | undefined = list[i].pic;
        if ((newPic === undefined || newPic === '') && oldPic !== undefined && oldPic !== '') {
          record.pic = oldPic;
        }
        list[i] = record;
        found = true;
        break;
      }
    }
    if (!found) {
      list.push(record);
    }
    list.sort((a, b) => b.updatedAt - a.updatedAt);
    if (list.length > HistoryStore.MAX_HISTORY) {
      list = list.slice(0, HistoryStore.MAX_HISTORY);
    }
    Store.shared().putJson(HistoryStore.KEY_HISTORY, JSON.stringify(list));
    EventBus.emit(Events.HISTORY_CHANGED);
  }

  /**
   * 仅当该记录缺少封面时写入（用于补历史封面）。
   * 返回是否发生改动。不调整 updatedAt，避免补封面把播放顺序打乱。
   */
  setPicIfEmpty(sourceKey: string, vodId: string, pic: string): boolean {
    if (pic === '') {
      return false;
    }
    const list = HistoryStore.parseRecords(Store.shared().getJson(HistoryStore.KEY_HISTORY));
    let changed = false;
    for (let i = 0; i < list.length; i++) {
      if (list[i].sourceKey === sourceKey && list[i].vodId === vodId) {
        const cur: string | undefined = list[i].pic;
        if (cur === undefined || cur === '') {
          list[i].pic = pic;
          changed = true;
        }
        break;
      }
    }
    if (changed) {
      Store.shared().putJson(HistoryStore.KEY_HISTORY, JSON.stringify(list));
      EventBus.emit(Events.HISTORY_CHANGED);
    }
    return changed;
  }

  removeHistory(sourceKey: string, vodId: string): void {
    const list = HistoryStore.parseRecords(Store.shared().getJson(HistoryStore.KEY_HISTORY));
    const next: PlayRecord[] = [];
    for (const r of list) {
      if (!(r.sourceKey === sourceKey && r.vodId === vodId)) {
        next.push(r);
      }
    }
    Store.shared().putJson(HistoryStore.KEY_HISTORY, JSON.stringify(next));
    EventBus.emit(Events.HISTORY_CHANGED);
  }

  clearHistory(): void {
    Store.shared().putJson(HistoryStore.KEY_HISTORY, '[]');
    EventBus.emit(Events.HISTORY_CHANGED);
  }

  // ---------- 收藏 ----------

  getFavorites(): FavoriteItem[] {
    return HistoryStore.parseFavorites(Store.shared().getJson(HistoryStore.KEY_FAVORITES));
  }

  isFavorite(sourceKey: string, vodId: string): boolean {
    const list = HistoryStore.parseFavorites(Store.shared().getJson(HistoryStore.KEY_FAVORITES));
    for (const f of list) {
      if (f.sourceKey === sourceKey && f.vodId === vodId) {
        return true;
      }
    }
    return false;
  }

  /** 切换收藏，返回切换后是否为已收藏 */
  toggleFavorite(item: FavoriteItem): boolean {
    let list = HistoryStore.parseFavorites(Store.shared().getJson(HistoryStore.KEY_FAVORITES));
    let exists = false;
    const next: FavoriteItem[] = [];
    for (const f of list) {
      if (f.sourceKey === item.sourceKey && f.vodId === item.vodId) {
        exists = true;
      } else {
        next.push(f);
      }
    }
    if (!exists) {
      next.unshift(item);
    }
    list = next;
    Store.shared().putJson(HistoryStore.KEY_FAVORITES, JSON.stringify(list));
    EventBus.emit(Events.HISTORY_CHANGED);
    return !exists;
  }

  removeFavorite(sourceKey: string, vodId: string): void {
    const list = HistoryStore.parseFavorites(Store.shared().getJson(HistoryStore.KEY_FAVORITES));
    const next: FavoriteItem[] = [];
    for (const f of list) {
      if (!(f.sourceKey === sourceKey && f.vodId === vodId)) {
        next.push(f);
      }
    }
    Store.shared().putJson(HistoryStore.KEY_FAVORITES, JSON.stringify(next));
    EventBus.emit(Events.HISTORY_CHANGED);
  }

  clearFavorites(): void {
    Store.shared().putJson(HistoryStore.KEY_FAVORITES, '[]');
    EventBus.emit(Events.HISTORY_CHANGED);
  }

  // ---------- 搜索历史 ----------

  getSearchHistory(): string[] {
    const json = Store.shared().getJson(HistoryStore.KEY_SEARCH);
    const out: string[] = [];
    if (json === '') {
      return out;
    }
    try {
      const arr = JSON.parse(json) as object[];
      if (!Array.isArray(arr)) {
        return out;
      }
      for (const v of arr) {
        if (typeof v === 'string' && (v as string) !== '') {
          out.push(v as string);
        }
      }
    } catch (e) {
      // ignore
    }
    return out;
  }

  addSearchHistory(wd: string): void {
    const kw = wd.trim();
    if (kw === '') {
      return;
    }
    let list = this.getSearchHistory();
    const next: string[] = [kw];
    for (const v of list) {
      if (v !== kw) {
        next.push(v);
      }
    }
    if (next.length > HistoryStore.MAX_SEARCH_HISTORY) {
      next.splice(HistoryStore.MAX_SEARCH_HISTORY);
    }
    Store.shared().putJson(HistoryStore.KEY_SEARCH, JSON.stringify(next));
  }

  removeSearchHistory(wd: string): void {
    const list = this.getSearchHistory();
    const next: string[] = [];
    for (const v of list) {
      if (v !== wd) {
        next.push(v);
      }
    }
    Store.shared().putJson(HistoryStore.KEY_SEARCH, JSON.stringify(next));
  }

  clearSearchHistory(): void {
    Store.shared().putJson(HistoryStore.KEY_SEARCH, '[]');
  }

  // ---------- 直播收藏 ----------

  getLiveFavorites(): string[] {
    const json = Store.shared().getJson(HistoryStore.KEY_LIVE_FAV);
    const out: string[] = [];
    if (json === '') {
      return out;
    }
    try {
      const arr = JSON.parse(json) as object[];
      if (!Array.isArray(arr)) {
        return out;
      }
      for (const v of arr) {
        if (typeof v === 'string' && (v as string) !== '') {
          out.push(v as string);
        }
      }
    } catch (e) {
      // ignore
    }
    return out;
  }

  isLiveFavorite(url: string): boolean {
    const list = this.getLiveFavorites();
    for (const v of list) {
      if (v === url) {
        return true;
      }
    }
    return false;
  }

  toggleLiveFavorite(url: string): boolean {
    const list = this.getLiveFavorites();
    let exists = false;
    const next: string[] = [];
    for (const v of list) {
      if (v === url) {
        exists = true;
      } else {
        next.push(v);
      }
    }
    if (!exists) {
      next.unshift(url);
    }
    Store.shared().putJson(HistoryStore.KEY_LIVE_FAV, JSON.stringify(next));
    EventBus.emit(Events.LIVE_FAV_CHANGED);
    return !exists;
  }

  // ---------- 解析 ----------

  private static parseRecords(json: string): PlayRecord[] {
    const out: PlayRecord[] = [];
    if (json === '') {
      return out;
    }
    try {
      const arr = JSON.parse(json) as object[];
      if (!Array.isArray(arr)) {
        return out;
      }
      for (const item of arr) {
        const rec = item as Record<string, object>;
        out.push({
          sourceKey: HistoryStore.str(rec['sourceKey']),
          vodId: HistoryStore.str(rec['vodId']),
          name: HistoryStore.str(rec['name']),
          pic: HistoryStore.optStr(rec['pic']),
          sourceName: HistoryStore.str(rec['sourceName']),
          episode: HistoryStore.num(rec['episode'], 0),
          episodeName: HistoryStore.optStr(rec['episodeName']),
          playUrl: HistoryStore.optStr(rec['playUrl']),
          positionMs: HistoryStore.num(rec['positionMs'], 0),
          durationMs: HistoryStore.num(rec['durationMs'], 0),
          updatedAt: HistoryStore.num(rec['updatedAt'], 0)
        });
      }
    } catch (e) {
      // ignore
    }
    return out;
  }

  private static parseFavorites(json: string): FavoriteItem[] {
    const out: FavoriteItem[] = [];
    if (json === '') {
      return out;
    }
    try {
      const arr = JSON.parse(json) as object[];
      if (!Array.isArray(arr)) {
        return out;
      }
      for (const item of arr) {
        const rec = item as Record<string, object>;
        out.push({
          sourceKey: HistoryStore.str(rec['sourceKey']),
          vodId: HistoryStore.str(rec['vodId']),
          name: HistoryStore.str(rec['name']),
          pic: HistoryStore.optStr(rec['pic']),
          sourceName: HistoryStore.str(rec['sourceName']),
          createdAt: HistoryStore.num(rec['createdAt'], 0)
        });
      }
    } catch (e) {
      // ignore
    }
    return out;
  }

  private static str(v: object): string {
    return typeof v === 'string' ? (v as string) : '';
  }

  private static optStr(v: object): string | undefined {
    return typeof v === 'string' && (v as string) !== '' ? (v as string) : undefined;
  }

  private static num(v: object, def: number): number {
    return typeof v === 'number' ? (v as number) : def;
  }
}
