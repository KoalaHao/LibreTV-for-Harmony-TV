import { Utils } from '../common/Utils';

export interface AdSegmentDecision {
  index: number;
  group: number;
  durationMs: number;
  sourceStartMs: number;
  startMs: number;
  endMs: number;
  url: string;
  host: string;
  discontinuity: boolean;
  dropped: boolean;
  reason: string;
}

export interface AdFilterTrace {
  mode: string;
  status: string;
  playlistUrl: string;
  note: string;
  originalCount: number;
  filteredCount: number;
  filteredMs: number;
  live: boolean;
  timelineUsable: boolean;
  segments: AdSegmentDecision[];
}

export interface AdDiagnosticView {
  state: string;
  summary: string;
  current: string;
  location: string;
  changes: string;
  reason: string;
  note: string;
  nearby: string[];
}

export interface AdReportContext {
  sourceKey: string;
  vodId: string;
  title: string;
  episode: number;
  episodeName: string;
  lineIndex: number;
}

export interface AdDiagnosticReport {
  schema: number;
  createdAt: number;
  context: AdReportContext;
  positionMs: number;
  playerDurationMs: number;
  view: AdDiagnosticView;
  playlistUrl: string;
  estimatedSegment: number;
  nearby: AdSegmentDecision[];
  playlistSnapshot: string;
  snapshotTruncated: boolean;
}

/** Diagnostic observations only; no rule changes, media requests, seeking or content classification. */
export class AdDiagnostics {
  static empty(mode: string = 'loose', status: string = 'pending', url: string = '', note: string = ''): AdFilterTrace {
    return { mode: mode, status: status, playlistUrl: AdDiagnostics.safeUrl(url), note: note,
      originalCount: 0, filteredCount: 0, filteredMs: 0, live: false, timelineUsable: false, segments: [] };
  }

  /** Tokens, fragments and URL credentials are never shown or persisted in diagnostic records. */
  static safeUrl(url: string): string {
    return url.split(/[?#]/)[0].replace(/^(https?:\/\/)[^/@]+@/i, '$1').substring(0, 1024);
  }

  static modeLabel(mode: string): string { return mode === 'off' ? '关闭' : (mode === 'strict' ? '严格' : '宽松'); }

  private static durationMismatch(trace: AdFilterTrace, durationMs: number): boolean {
    if (!Number.isFinite(durationMs) || durationMs <= 0 || trace.segments.length === 0) return false;
    const end = trace.segments[trace.segments.length - 1].endMs;
    return Math.abs(durationMs - end) > Math.max(3000, end * 0.01);
  }

  static locate(trace: AdFilterTrace, positionMs: number, durationMs: number = 0): number {
    if (trace.status !== 'rewritten' || trace.live || !trace.timelineUsable || !Number.isFinite(positionMs) || positionMs < 0) return -1;
    if (AdDiagnostics.durationMismatch(trace, durationMs)) return -1;
    let low = 0; let high = trace.segments.length;
    // Removed segments occupy zero output time. End times remain monotonic even after ad removal.
    while (low < high) {
      const middle = Math.floor((low + high) / 2);
      if (trace.segments[middle].endMs <= positionMs) low = middle + 1;
      else high = middle;
    }
    const segment = trace.segments[low];
    return segment !== undefined && !segment.dropped && positionMs >= segment.startMs ? low : -1;
  }

  static view(trace: AdFilterTrace, positionMs: number, durationMs: number = 0): AdDiagnosticView {
    let state = '正在读取播放清单';
    if (trace.status === 'rewritten') state = '清单已重写';
    else if (trace.status === 'off') state = '过滤已关闭 · 直链播放';
    else if (trace.status === 'direct') state = '非 M3U8 · 未执行分片过滤';
    else if (trace.status === 'fallback') state = '过滤失败 · 已回退直链';
    else if (trace.status === 'offline') state = '离线文件 · 无原始分片清单';
    const result: AdDiagnosticView = { state: AdDiagnostics.modeLabel(trace.mode) + ' · ' + state,
      summary: trace.status === 'rewritten' ? ('原清单 ' + trace.originalCount + ' 片，剔除 ' + trace.filteredCount +
        ' 个疑似广告分片' + (trace.segments.length === trace.originalCount ? ' / ' + (trace.filteredMs / 1000).toFixed(1) + ' 秒' : '（时长未完整统计）')) : '本次没有应用分片过滤',
      current: '当前分片不可定位', location: trace.playlistUrl || '清单地址暂未取得',
      changes: '暂无可比较的分片', reason: '未取得可用的分片映射',
      note: trace.note, nearby: [] };
    if (trace.status === 'rewritten') {
      result.note = trace.live ? '动态清单会更新，不估算当前分片。' :
        (trace.timelineUsable ? '按过滤后清单时长估算，非播放器请求回调；时间戳、续播及 seek 可能产生偏差。' :
          '清单时长缺失或超出诊断上限，无法可靠估算。');
      if (trace.note !== '') result.note = trace.note + '\n' + result.note;
    }
    if (trace.status === 'rewritten' && !trace.live && trace.timelineUsable && AdDiagnostics.durationMismatch(trace, durationMs)) {
      result.note = '播放器时长与过滤后清单明显不一致，暂不估算当前分片。';
    }
    const index = AdDiagnostics.locate(trace, positionMs, durationMs);
    if (index < 0) return result;
    const current = trace.segments[index];
    result.current = '估算原清单 #' + current.index + ' · ' + (current.durationMs / 1000).toFixed(2) + ' 秒 · 分组 ' + current.group +
      '\n输出时间 ' + Utils.formatTime(current.startMs) + '–' + Utils.formatTime(current.endMs);
    result.location = current.url;
    result.reason = current.reason;
    let previous = index - 1;
    while (previous >= 0 && trace.segments[previous].dropped) previous--;
    if (previous >= 0) {
      const old = trace.segments[previous];
      result.changes = '相较前一保留分片：' + (old.host !== current.host ? '域名变化' : '同一域名') +
        ' · ' + (old.group !== current.group ? '分组切换' : '同一分组') +
        (index - previous > 1 ? ' · 中间有已过滤分片' : '');
    } else result.changes = '第一段保留分片';
    for (let i = Math.max(0, index - 2); i <= Math.min(trace.segments.length - 1, index + 2); i++) {
      const segment = trace.segments[i];
      result.nearby.push((i === index ? '≈ ' : '') + '#' + segment.index + ' · ' +
        (segment.dropped ? '已剔除' : '保留') + ' · ' + (segment.durationMs / 1000).toFixed(2) + ' 秒 · ' + segment.host +
        '\n' + segment.reason);
    }
    return result;
  }

  static report(trace: AdFilterTrace, positionMs: number, context: AdReportContext, durationMs: number = 0): AdDiagnosticReport {
    const index = AdDiagnostics.locate(trace, positionMs, durationMs);
    const start = index < 0 ? 0 : Math.max(0, index - 120);
    const end = Math.min(trace.segments.length, start + 241);
    const lines: string[] = ['#EXTM3U', '#DIAGNOSTIC-SNAPSHOT:已去除URL参数与密钥标签，非可播放清单',
      '#SOURCE:' + trace.playlistUrl, '#STATUS:' + trace.status];
    let length = 0;
    let actualEnd = start;
    for (let i = start; i < end; i++) {
      const segment = trace.segments[i];
      const line = '#SEGMENT:' + segment.index + ',GROUP:' + segment.group + ',' + (segment.dropped ? 'DROP:' : 'KEEP:') + segment.reason +
        '\n' + (segment.discontinuity ? '#EXT-X-DISCONTINUITY\n' : '') + '#EXTINF:' + (segment.durationMs / 1000).toFixed(3) + ',\n' + segment.url;
      if (length + line.length > 131072) break;
      lines.push(line); length += line.length; actualEnd = i + 1;
    }
    return { schema: 1, createdAt: Date.now(), context: context,
      positionMs: Number.isFinite(positionMs) ? Math.max(0, Math.floor(positionMs)) : 0,
      playerDurationMs: Number.isFinite(durationMs) ? Math.max(0, Math.floor(durationMs)) : 0,
      view: AdDiagnostics.view(trace, positionMs, durationMs), playlistUrl: trace.playlistUrl,
      estimatedSegment: index >= 0 ? trace.segments[index].index : -1,
      nearby: index >= 0 ? trace.segments.slice(Math.max(0, index - 4), index + 5) : [],
      playlistSnapshot: lines.join('\n'), snapshotTruncated: start > 0 || actualEnd < trace.originalCount };
  }
}

/** A late resolver response cannot attach a previous source's diagnostics to a newly selected episode. */
export class AdDiagnosticSession {
  private generation: number = 0;
  private trace: AdFilterTrace = AdDiagnostics.empty();
  begin(mode: string, status: string = 'pending', url: string = ''): number {
    this.generation++; this.trace = AdDiagnostics.empty(mode, status, url); return this.generation;
  }
  update(generation: number, trace: AdFilterTrace): boolean {
    if (generation !== this.generation) return false;
    this.trace = trace; return true;
  }
  current(): AdFilterTrace { return this.trace; }
  close(): void { this.generation++; this.trace = AdDiagnostics.empty(); }
}
