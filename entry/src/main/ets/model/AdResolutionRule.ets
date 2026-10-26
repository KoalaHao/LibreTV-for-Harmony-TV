import { HttpClient } from '../net/HttpClient';
import { Utils } from '../common/Utils';
import { TsVideoDimensions, EncodedDimensions } from './TsVideoDimensions';

interface ResolutionSegment { url: string; durationMs: number; discontinuity: boolean; }
interface ResolutionRun { start: number; end: number; priority: number; }
export interface ResolutionAdMatch {
  /** Zero-based, end exclusive, always referring to the original media playlist. */
  start: number;
  end: number;
  width: number;
  height: number;
  mainWidth: number;
  mainHeight: number;
}
export interface ResolutionAdResult { matches: ResolutionAdMatch[]; note: string; }

/** Optional strict-mode evidence. Unknown, unsupported and unexamined intervals are retained. */
export class AdResolutionRule {
  private static readonly MAX_REQUESTS: number = 160;
  private static readonly BUDGET_MS: number = 8000;
  private static readonly MAX_INSERT_MS: number = 60000;
  private static readonly MAX_INSERT_SEGMENTS: number = 16;
  // Only dimensions, never video prefixes. Full URLs stay in memory and are not written to reports.
  private static readonly cache: Map<string, EncodedDimensions> = new Map();
  // A reprepare (including an SR toggle) must not discover more cuts and shift the same playback timeline.
  private static readonly analyses: Map<string, ResolutionAdResult> = new Map();
  private static analysisCharacters: number = 0;

  private static parse(content: string, base: string): ResolutionSegment[] {
    if (content.length > 2097152 || !content.trim().startsWith('#EXTM3U') || !content.includes('#EXT-X-ENDLIST') ||
      /#EXT-X-(?:MAP|BYTERANGE|I-FRAMES-ONLY)[:\r\n]/.test(content) ||
      content.split(/\r?\n/).some((line: string) => line.startsWith('#EXT-X-KEY:') && !/(?:[:,])METHOD=NONE(?:,|$)/.test(line))) return [];
    const segments: ResolutionSegment[] = [];
    let duration = 0; let discontinuity = false;
    for (const raw of content.split(/\r?\n/)) {
      const line = raw.trim();
      if (line.startsWith('#EXTINF:')) duration = Number(line.substring(8).split(',')[0]) * 1000;
      else if (line === '#EXT-X-DISCONTINUITY') discontinuity = true;
      else if (line !== '' && !line.startsWith('#')) {
        const url = Utils.resolveUrl(base, line);
        if (!Number.isFinite(duration) || duration <= 0 || duration > 60000 || !/^https?:\/\//i.test(url) ||
          !/\.ts(?:[?#]|$)/i.test(url)) return [];
        segments.push({ url: url, durationMs: Math.round(duration), discontinuity: discontinuity });
        duration = 0; discontinuity = false;
        if (segments.length > 20000) return [];
      }
    }
    return segments.length >= 24 && segments.reduce((sum: number, item: ResolutionSegment) => sum + item.durationMs, 0) >= 120000 ? segments : [];
  }

  private static candidates(segments: ResolutionSegment[]): ResolutionRun[] {
    const counts: Map<number, number> = new Map();
    let modal = 0; let peak = 0;
    for (const segment of segments) {
      const bucket = Math.round(segment.durationMs / 20);
      const count = (counts.get(bucket) || 0) + 1; counts.set(bucket, count);
      if (count > peak) { peak = count; modal = bucket; }
    }
    const runs: ResolutionRun[] = [];
    let start = 0;
    for (let end = 1; end <= segments.length; end++) {
      if (end < segments.length && !segments[end].discontinuity) continue;
      const items = segments.slice(start, end);
      const duration = items.reduce((sum: number, item: ResolutionSegment) => sum + item.durationMs, 0);
      if (start >= 2 && end < segments.length - 1 && items.length <= AdResolutionRule.MAX_INSERT_SEGMENTS &&
        duration <= AdResolutionRule.MAX_INSERT_MS) {
        // Duration chooses probe order only. It never makes a removal decision.
        const uncommon = peak >= segments.length * 0.3 && items.every((item: ResolutionSegment) => Math.abs(item.durationMs - modal * 20) > 25);
        runs.push({ start: start, end: end, priority: uncommon ? 0 : 1 });
      }
      start = end;
    }
    return runs.sort((a: ResolutionRun, b: ResolutionRun) => a.priority - b.priority ||
      (a.end - a.start) - (b.end - b.start) || a.start - b.start);
  }

  private static equal(a: EncodedDimensions, b: EncodedDimensions): boolean {
    return a.width > 0 && a.width === b.width && a.height === b.height;
  }

  static async inspect(content: string, base: string, headers: Record<string, string>,
    wanted: () => boolean = () => true): Promise<ResolutionAdResult> {
    const result: ResolutionAdResult = { matches: [], note: '严格分辨率检查：清单不适用，未增加删片。' };
    const key = base + '\n' + content;
    const cached = AdResolutionRule.analyses.get(key);
    if (cached !== undefined && wanted()) return cached;
    const finish = (): ResolutionAdResult => {
      if (wanted()) {
        if (AdResolutionRule.analyses.delete(key)) AdResolutionRule.analysisCharacters -= key.length;
        AdResolutionRule.analyses.set(key, result);
        AdResolutionRule.analysisCharacters += key.length;
        while (AdResolutionRule.analyses.size > 16 ||
          (AdResolutionRule.analyses.size > 1 && AdResolutionRule.analysisCharacters > 2097152)) {
          const first = AdResolutionRule.analyses.keys().next().value as string | undefined;
          if (first === undefined) break;
          AdResolutionRule.analyses.delete(first);
          AdResolutionRule.analysisCharacters -= first.length;
        }
      }
      return result;
    };
    const segments = AdResolutionRule.parse(content, base);
    const candidates = AdResolutionRule.candidates(segments);
    if (segments.length === 0 || candidates.length === 0 || !wanted()) return result;
    const deadline = Date.now() + AdResolutionRule.BUDGET_MS;
    const pending: Map<number, Promise<EncodedDimensions>> = new Map();
    let requests = 0; let sampled = 0;
    const active = (): boolean => wanted() && Date.now() < deadline && requests < AdResolutionRule.MAX_REQUESTS;
    const probe = (index: number): Promise<EncodedDimensions> => {
      const old = pending.get(index); if (old !== undefined) return old;
      const task = (async (): Promise<EncodedDimensions> => {
        if (!wanted() || index < 0 || index >= segments.length) return TsVideoDimensions.empty();
        const url = segments[index].url;
        const cached = AdResolutionRule.cache.get(url);
        if (cached !== undefined) { sampled++; return cached; }
        if (!active()) return TsVideoDimensions.empty();
        requests++;
        try {
          const response = await HttpClient.getVideoPrefix(url, headers, Math.max(1, Math.min(2000, deadline - Date.now())));
          if (!wanted() || !response.ok || response.bytes.length > 16384) return TsVideoDimensions.empty();
          const dimensions = TsVideoDimensions.read(response.bytes);
          if (dimensions.width > 0) {
            sampled++;
            AdResolutionRule.cache.delete(url); AdResolutionRule.cache.set(url, dimensions);
            while (AdResolutionRule.cache.size > 512) {
              const first = AdResolutionRule.cache.keys().next().value as string | undefined;
              if (first === undefined) break;
              AdResolutionRule.cache.delete(first);
            }
          }
          return dimensions;
        } catch (e) { return TsVideoDimensions.empty(); }
      })();
      pending.set(index, task); return task;
    };
    // Nine evenly spread actual SPS samples, not RESOLUTION advertised by a master playlist.
    const anchors: EncodedDimensions[] = [];
    for (let batch = 0; batch < 3 && active(); batch++) {
      const tasks: Promise<EncodedDimensions>[] = [];
      for (let i = batch * 3; i < batch * 3 + 3; i++) tasks.push(probe(Math.floor((i + 0.5) * segments.length / 9)));
      anchors.push(...await Promise.all(tasks));
    }
    let main = TsVideoDimensions.empty(); let votes = 0;
    for (const dimensions of anchors) {
      if (dimensions.width === 0) continue;
      const count = anchors.filter((item: EncodedDimensions) => AdResolutionRule.equal(item, dimensions)).length;
      if (count > votes) { votes = count; main = dimensions; }
    }
    if (votes < 7 || !wanted()) {
      result.note = '严格分辨率检查：九个分布样本未取得至少七个一致尺寸，未增加删片。'; return finish();
    }
    const check = async (seed: number): Promise<void> => {
      if (!active() || result.matches.some((match: ResolutionAdMatch) => seed >= match.start && seed < match.end)) return;
      const alternative = await probe(seed);
      if (alternative.width === 0 || AdResolutionRule.equal(main, alternative)) return;
      let left = seed; let right = seed + 1; let duration = segments[seed].durationMs;
      while (left >= 2 && right - left <= AdResolutionRule.MAX_INSERT_SEGMENTS && duration <= AdResolutionRule.MAX_INSERT_MS) {
        const before = await probe(left - 1);
        if (AdResolutionRule.equal(before, main)) break;
        if (!AdResolutionRule.equal(before, alternative)) return;
        left--; duration += segments[left].durationMs;
      }
      while (right < segments.length - 1 && right - left <= AdResolutionRule.MAX_INSERT_SEGMENTS && duration <= AdResolutionRule.MAX_INSERT_MS) {
        const after = await probe(right);
        if (AdResolutionRule.equal(after, main)) break;
        if (!AdResolutionRule.equal(after, alternative)) return;
        duration += segments[right].durationMs; right++;
      }
      if (!wanted() || left < 2 || right >= segments.length - 1 || right - left < 2 ||
        right - left > AdResolutionRule.MAX_INSERT_SEGMENTS || duration < 3000 || duration > AdResolutionRule.MAX_INSERT_MS ||
        !segments[left].discontinuity || !segments[right].discontinuity) return;
      const brackets: EncodedDimensions[] = [];
      for (const index of [left - 2, left - 1, right, right + 1]) brackets.push(await probe(index));
      if (!wanted() || !brackets.every((item: EncodedDimensions) => AdResolutionRule.equal(item, main))) return;
      if (result.matches.some((match: ResolutionAdMatch) => left < match.end && right > match.start)) return;
      result.matches.push({ start: left, end: right, width: alternative.width, height: alternative.height,
        mainWidth: main.width, mainHeight: main.height });
    };
    let cursor = 0;
    const worker = async (): Promise<void> => {
      while (cursor < candidates.length && active()) { const candidate = candidates[cursor++]; await check(candidate.start); }
    };
    await Promise.all([worker(), worker(), worker()]);
    if (!wanted()) { result.matches = []; result.note = '严格分辨率检查已取消，未增加删片。'; return result; }
    result.matches.sort((a: ResolutionAdMatch, b: ResolutionAdMatch) => a.start - b.start);
    result.note = '严格分辨率检查：主样本 ' + main.width + '×' + main.height + '（' + votes + '/9），取得 ' + sampled +
      ' 个尺寸，匹配 ' + result.matches.length + ' 个疑似插播区间。' +
      (cursor < candidates.length ? '采样预算已用完，剩余区间保留。' : '未知或证据不足的区间保留。');
    return finish();
  }
}
