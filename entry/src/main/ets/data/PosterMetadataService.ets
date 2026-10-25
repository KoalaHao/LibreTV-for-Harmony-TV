import { HttpClient } from '../net/HttpClient';
import { Store } from './Store';
import { PosterCardData, PosterCardInfo, PosterStaticInfo } from '../model/PosterCardData';

interface PosterMetrics { rating: string; shortComments: number; updatedAt: number; }
interface PosterCacheEntry { info: PosterStaticInfo; metrics?: PosterMetrics; }
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
  private static readonly METRICS_TTL: number = 2 * 24 * 60 * 60 * 1000;
  private static legacyRemoved: boolean = false;

  static peek(subjectId: string): PosterCardInfo | null {
    if (!/^\d{7,10}$/.test(subjectId)) return null;
    PosterMetadataService.removeLegacyCache();
    const memory = PosterMetadataService.cache.get(subjectId);
    if (memory !== undefined) {
      PosterMetadataService.remember(subjectId, memory);
      return PosterMetadataService.toInfo(memory);
    }
    try {
      const text = Store.shared().getJson(PosterMetadataService.PREFIX + subjectId);
      if (text === '' || text.length > 8000) return null;
      const entry = JSON.parse(text) as Record<string, Object>;
      const info = PosterCardData.restore(JSON.stringify(entry['info']), subjectId);
      if (info === null) return null;
      const cached: PosterCacheEntry = { info: PosterCardData.stable(info),
        metrics: PosterMetadataService.readMetrics(entry['metrics']) };
      PosterMetadataService.remember(subjectId, cached);
      return PosterMetadataService.toInfo(cached);
    } catch (e) { return null; }
  }

  static request(subjectId: string, seriesHint: boolean, extended: boolean = false): Promise<PosterCardInfo | null> {
    if (!/^\d{7,10}$/.test(subjectId)) return Promise.resolve(null);
    const previous = PosterMetadataService.peek(subjectId);
    const now = Date.now();
    const cached = PosterMetadataService.cache.get(subjectId);
    if (cached !== undefined && cached.metrics !== undefined && now - cached.metrics.updatedAt < PosterMetadataService.METRICS_TTL &&
      (!extended || cached.info.detailsLoaded)) {
      return Promise.resolve(previous);
    }
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
    let refreshed: boolean = false;
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
              refreshed = true;
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
      result = PosterMetadataService.peek(job.subjectId);
    } finally {
      if (!refreshed) {
        PosterMetadataService.retryAfter.set(job.subjectId,
          Math.max(Date.now() + 60000, PosterMetadataService.blockedUntil));
      } else PosterMetadataService.retryAfter.delete(job.subjectId);
      PosterMetadataService.pending.delete(job.subjectId);
      PosterMetadataService.active--;
      job.resolve(result);
      PosterMetadataService.pump();
    }
  }

  private static save(info: PosterCardInfo): void {
    const previous = PosterMetadataService.cache.get(info.subjectId);
    const entry: PosterCacheEntry = { info: PosterCardData.stable(info), metrics: info.liveMetadata ? {
      rating: info.rating, shortComments: info.shortComments, updatedAt: Date.now()
    } : (previous !== undefined ? previous.metrics : undefined) };
    PosterMetadataService.remember(info.subjectId, entry);
    const store = Store.shared();
    store.putJson(PosterMetadataService.PREFIX + info.subjectId, JSON.stringify(entry));
  }

  private static remember(subjectId: string, entry: PosterCacheEntry): void {
    PosterMetadataService.cache.delete(subjectId);
    PosterMetadataService.cache.set(subjectId, entry);
    if (PosterMetadataService.cache.size > 200) {
      for (const id of PosterMetadataService.cache.keys()) {
        PosterMetadataService.cache.delete(id);
        break;
      }
    }
    // Only the in-memory working set is bounded. Disk entries are never evicted.
  }

  private static toInfo(entry: PosterCacheEntry): PosterCardInfo {
    const info = PosterCardData.fromStatic(entry.info);
    if (entry.metrics !== undefined) {
      info.rating = entry.metrics.rating;
      info.shortComments = entry.metrics.shortComments;
    }
    return info;
  }

  private static readMetrics(value: Object): PosterMetrics | undefined {
    if (value === null || typeof value !== 'object' || Array.isArray(value)) return undefined;
    const data = value as Record<string, Object>;
    const updatedAt = data['updatedAt'];
    const rating = data['rating'];
    const count = data['shortComments'];
    if (typeof updatedAt !== 'number' || !Number.isFinite(updatedAt) || updatedAt <= 0 || updatedAt > Date.now() + 60000 ||
      typeof rating !== 'string' || (rating !== '' && (!Number.isFinite(Number(rating)) || Number(rating) <= 0 || Number(rating) > 10)) ||
      typeof count !== 'number' || !Number.isInteger(count) || count < -1 || count > 1000000000) return undefined;
    return { rating: rating === '' ? '' : Number(rating).toFixed(1), shortComments: count, updatedAt: updatedAt };
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
