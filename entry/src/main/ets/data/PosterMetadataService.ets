import { HttpClient } from '../net/HttpClient';
import { Store } from './Store';
import { PosterCardData, PosterCardInfo, PosterStaticInfo } from '../model/PosterCardData';

interface PosterCacheEntry { info: PosterStaticInfo; }
interface PosterMetadataJob {
  subjectId: string;
  seriesHint: boolean;
  resolve: (info: PosterCardInfo | null) => void;
}

/** Visible cards share a small, deduplicated queue. A failed detail endpoint never blocks the feed. */
export class PosterMetadataService {
  private static readonly cache: Map<string, PosterCacheEntry> = new Map();
  private static readonly pending: Map<string, Promise<PosterCardInfo | null>> = new Map();
  private static readonly retryAfter: Map<string, number> = new Map();
  private static readonly queue: PosterMetadataJob[] = [];
  private static active: number = 0;
  private static blockedUntil: number = 0;
  private static nextDetailAt: number = 0;
  private static readonly PREFIX: string = 'poster_static_v2_';
  private static readonly INDEX: string = 'poster_static_index_v2';
  private static legacyRemoved: boolean = false;

  static peek(subjectId: string): PosterCardInfo | null {
    if (!/^\d{7,10}$/.test(subjectId)) return null;
    PosterMetadataService.removeLegacyCache();
    const memory = PosterMetadataService.cache.get(subjectId);
    if (memory !== undefined) return PosterCardData.fromStatic(memory.info);
    try {
      const text = Store.shared().getJson(PosterMetadataService.PREFIX + subjectId);
      if (text === '' || text.length > 8000) return null;
      const entry = JSON.parse(text) as Record<string, Object>;
      const info = PosterCardData.restore(JSON.stringify(entry['info']), subjectId);
      if (info === null) return null;
      PosterMetadataService.cache.set(subjectId, { info: PosterCardData.stable(info) });
      return info;
    } catch (e) { return null; }
  }

  static request(subjectId: string, seriesHint: boolean): Promise<PosterCardInfo | null> {
    if (!/^\d{7,10}$/.test(subjectId)) return Promise.resolve(null);
    const previous = PosterMetadataService.peek(subjectId);
    const now = Date.now();
    if ((PosterMetadataService.blockedUntil > now && previous !== null) ||
      (PosterMetadataService.retryAfter.get(subjectId) || 0) > now) {
      return Promise.resolve(previous);
    }
    const pending = PosterMetadataService.pending.get(subjectId);
    if (pending !== undefined) return pending;
    const promise = new Promise<PosterCardInfo | null>((resolve: (info: PosterCardInfo | null) => void) => {
      PosterMetadataService.queue.push({ subjectId: subjectId, seriesHint: seriesHint, resolve: resolve });
    });
    PosterMetadataService.pending.set(subjectId, promise);
    PosterMetadataService.pump();
    return promise;
  }

  private static pump(): void {
    while (PosterMetadataService.active < 2 && PosterMetadataService.queue.length > 0) {
      const job = PosterMetadataService.queue.shift();
      if (job === undefined) return;
      PosterMetadataService.active++;
      PosterMetadataService.run(job);
    }
  }

  private static async run(job: PosterMetadataJob): Promise<void> {
    let result: PosterCardInfo | null = null;
    try {
      if (Date.now() >= PosterMetadataService.blockedUntil) {
        const kinds: string[] = job.seriesHint ? ['tv', 'movie'] : ['movie', 'tv'];
        for (const kind of kinds) {
          const slot = Math.max(Date.now(), PosterMetadataService.nextDetailAt);
          PosterMetadataService.nextDetailAt = slot + 750;
          if (slot > Date.now()) await new Promise<void>((resolve: () => void) => setTimeout(resolve, slot - Date.now()));
          if (Date.now() < PosterMetadataService.blockedUntil) break;
          const response = await HttpClient.getText('https://m.douban.com/rexxar/api/v2/' + kind + '/' + job.subjectId, {
            'User-Agent': HttpClient.UA,
            'Referer': 'https://m.douban.com/movie/subject/' + job.subjectId + '/',
            'Accept': 'application/json'
          }, 6000, false);
          if (PosterCardData.isRateLimited(response.status, response.text) ||
            (response.ok && !response.text.trim().startsWith('{'))) {
            PosterMetadataService.blockedUntil = Date.now() + 5 * 60 * 1000;
            Store.shared().putJson('poster_detail_block_until_v1', PosterMetadataService.blockedUntil.toString());
            console.warn('[PosterMetadata] Detail service limited; keeping stable metadata and pausing detail requests.');
            break;
          }
          if (response.ok) {
            const info = PosterCardData.parse(response.text, job.subjectId, job.seriesHint);
            if (info !== null) {
              result = info;
              PosterMetadataService.save(info);
            }
            break;
          }
          if (response.status !== 400 && response.status !== 404) break;
        }
      }
      if (result === null) {
        result = PosterMetadataService.peek(job.subjectId);
        if (result === null) {
          const response = await HttpClient.getText('https://movie.douban.com/j/subject_abstract?subject_id=' + job.subjectId, {
            'User-Agent': HttpClient.UA, 'Referer': 'https://movie.douban.com/', 'Accept': 'application/json'
          }, 6000, false);
          if (response.ok) {
            result = PosterCardData.parseAbstract(response.text, job.subjectId);
            if (result !== null) PosterMetadataService.save(result);
          }
        }
      }
    } catch (e) {
      // Keep usable cached fields and the original feed on offline/timeout errors.
    } finally {
      if (result === null || !result.liveMetadata) {
        PosterMetadataService.retryAfter.set(job.subjectId, Date.now() + 15 * 60 * 1000);
      } else PosterMetadataService.retryAfter.delete(job.subjectId);
      PosterMetadataService.pending.delete(job.subjectId);
      PosterMetadataService.active--;
      job.resolve(result);
      PosterMetadataService.pump();
    }
  }

  private static save(info: PosterCardInfo): void {
    const entry: PosterCacheEntry = { info: PosterCardData.stable(info) };
    PosterMetadataService.cache.set(info.subjectId, entry);
    const store = Store.shared();
    store.putJson(PosterMetadataService.PREFIX + info.subjectId, JSON.stringify(entry));
    let ids: string[] = [];
    try {
      const value = JSON.parse(store.getJson(PosterMetadataService.INDEX)) as Object;
      if (Array.isArray(value)) {
        for (const id of value as Object[]) {
          if (typeof id === 'string' && /^\d{7,10}$/.test(id) && id !== info.subjectId && ids.indexOf(id) < 0) ids.push(id);
        }
      }
    } catch (e) { /* Empty cache index. */ }
    ids.push(info.subjectId);
    while (ids.length > 200) {
      const id = ids.shift();
      if (id !== undefined) {
        store.remove(PosterMetadataService.PREFIX + id);
        PosterMetadataService.cache.delete(id);
        PosterMetadataService.retryAfter.delete(id);
      }
    }
    store.putJson(PosterMetadataService.INDEX, JSON.stringify(ids));
  }

  private static removeLegacyCache(): void {
    if (PosterMetadataService.legacyRemoved) return;
    PosterMetadataService.legacyRemoved = true;
    const store = Store.shared();
    const blocked = Number(store.getJson('poster_detail_block_until_v1'));
    if (Number.isFinite(blocked) && blocked > Date.now() && blocked <= Date.now() + 30 * 60 * 1000) {
      PosterMetadataService.blockedUntil = blocked;
    }
    try {
      const ids = JSON.parse(store.getJson('poster_meta_index_v1')) as Object;
      if (Array.isArray(ids)) {
        for (const id of ids as Object[]) {
          if (typeof id === 'string' && /^\d{7,10}$/.test(id)) {
            const text = store.getJson('poster_meta_v1_' + id);
            try {
              const old = JSON.parse(text) as Record<string, Object>;
              const info = PosterCardData.restore(JSON.stringify(old['info']), id);
              if (info !== null && store.getJson(PosterMetadataService.PREFIX + id) === '') PosterMetadataService.save(info);
            } catch (e) { /* Ignore malformed legacy entry. */ }
            store.remove('poster_meta_v1_' + id);
          }
        }
      }
    } catch (e) { /* No legacy index. */ }
    store.remove('poster_meta_index_v1');
  }
}
