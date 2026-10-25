import { SearchItem, VodSource } from '../model/Types';
import { SourceProbe, SourceProbeResult } from '../model/SourceProbe';
import { SourceManager } from './SourceManager';
import { SearchCacheStorage } from './SearchCacheStorage';
import { Utils } from '../common/Utils';

interface ProbeDescriptor { identity: string; key: string; source: VodSource; }
interface ProbeJob {
  descriptor: ProbeDescriptor;
  item: SearchItem;
  owners: Set<string>;
  active: boolean;
  resolve: (result: SourceProbeResult | null) => void;
}
interface PendingProbe { job: ProbeJob; promise: Promise<SourceProbeResult | null>; }

/** Only visible source buttons enqueue work. Successful records live for a day; failed checks retry after five minutes. */
export class SourceProbeService {
  private static readonly pending: Map<string, PendingProbe> = new Map();
  private static queue: ProbeJob[] = [];
  private static active: number = 0;

  private static descriptor(item: SearchItem): ProbeDescriptor | null {
    const source = SourceManager.shared().getVodSource(item.sourceKey);
    if (source === null) return null;
    const identity = JSON.stringify([source.key, source.url, source.detail || '', item.vodId]);
    return { identity: identity, key: 'probe-' + Utils.stableId(identity) + '-' + Utils.stableId('spec-v1' + identity),
      source: { key: source.key, name: source.name, url: source.url, detail: source.detail,
        enabled: source.enabled, isAdult: source.isAdult, failStreak: source.failStreak, disabledUntil: source.disabledUntil } };
  }

  static fresh(result: SourceProbeResult): boolean {
    return Date.now() - result.checkedAt < (result.status === 'failed' ? 5 * 60000 : 24 * 3600000);
  }

  static peek(item: SearchItem): SourceProbeResult | null {
    const descriptor = SourceProbeService.descriptor(item);
    if (descriptor === null) return null;
    try {
      const text = SearchCacheStorage.read(descriptor.key);
      if (text === '' || text.length > 8000) return null;
      const data = JSON.parse(text) as Record<string, Object>;
      const result = data['result'] as SourceProbeResult;
      if (data['identity'] !== descriptor.identity || result === null || typeof result !== 'object' ||
        result.sourceKey !== item.sourceKey || result.vodId !== item.vodId ||
        !Number.isFinite(result.checkedAt) || result.checkedAt <= 0 || result.checkedAt > Date.now() + 60000 ||
        !Number.isFinite(result.latencyMs) || result.latencyMs < 0 || result.latencyMs > 120000 ||
        !Number.isInteger(result.width) || !Number.isInteger(result.height) || result.width < 0 || result.height < 0 ||
        result.width > 16384 || result.height > 16384 || ((result.width === 0) !== (result.height === 0)) ||
        (result.width > 0 && (result.width < 16 || result.height < 16)) ||
        !Number.isFinite(result.resolutionAt) || result.resolutionAt < 0 || result.resolutionAt > Date.now() + 60000 ||
        ['none', 'stream', 'manifest'].indexOf(result.resolutionSource) < 0 ||
        (result.status !== 'ok' && result.status !== 'failed')) return null;
      return result;
    } catch (e) { return null; }
  }

  static request(item: SearchItem, owner: string, force: boolean = false): Promise<SourceProbeResult | null> {
    const descriptor = SourceProbeService.descriptor(item);
    if (descriptor === null) return Promise.resolve(null);
    const cached = SourceProbeService.peek(item);
    if (!force && cached !== null && SourceProbeService.fresh(cached)) return Promise.resolve(cached);
    const pending = SourceProbeService.pending.get(descriptor.identity);
    if (pending !== undefined) { pending.job.owners.add(owner); return pending.promise; }
    let resolveResult: (result: SourceProbeResult | null) => void = () => {};
    const promise = new Promise<SourceProbeResult | null>((resolve) => { resolveResult = resolve; });
    const job: ProbeJob = { descriptor: descriptor, item: item, active: false, owners: new Set([owner]), resolve: resolveResult };
    SourceProbeService.pending.set(descriptor.identity, { job: job, promise: promise });
    SourceProbeService.queue.push(job);
    SourceProbeService.pump();
    return promise;
  }

  static cancel(owner: string): void {
    for (const entry of SourceProbeService.pending.values()) {
      entry.job.owners.delete(owner);
      if (!entry.job.active && entry.job.owners.size === 0) {
        SourceProbeService.pending.delete(entry.job.descriptor.identity);
        entry.job.resolve(SourceProbeService.peek(entry.job.item));
      }
    }
    SourceProbeService.queue = SourceProbeService.queue.filter((job) => job.owners.size > 0);
  }

  private static pump(): void {
    while (SourceProbeService.active < 2 && SourceProbeService.queue.length > 0) {
      const job = SourceProbeService.queue.shift();
      if (job === undefined) return;
      job.active = true;
      SourceProbeService.active++;
      SourceProbeService.run(job);
    }
  }

  private static async run(job: ProbeJob): Promise<void> {
    let result: SourceProbeResult | null = null;
    try {
      const old = SourceProbeService.peek(job.item);
      result = await SourceProbe.run(job.item, job.descriptor.source, () => job.owners.size > 0);
      if (result !== null) {
        if (result.width === 0 && old !== null && old.width > 0) {
          result.width = old.width; result.height = old.height;
          result.resolutionAt = old.resolutionAt; result.resolutionSource = old.resolutionSource;
        }
        SearchCacheStorage.write(job.descriptor.key, JSON.stringify({ identity: job.descriptor.identity, result: result }));
      }
    } catch (e) { result = SourceProbeService.peek(job.item); }
    finally {
      SourceProbeService.pending.delete(job.descriptor.identity);
      SourceProbeService.active--;
      job.resolve(result);
      SourceProbeService.pump();
    }
  }
}
