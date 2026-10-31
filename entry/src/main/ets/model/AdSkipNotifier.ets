import { AdFilterTrace } from './AdDiagnostics';

interface SkippedRange { positionMs: number; durationMs: number; rules: string[]; }

/** Notices describe cuts in the rewritten VOD timeline, never inferred ads in a playing source. */
export class AdSkipNotifier {
  private cuts: SkippedRange[] = [];
  private lastPositionMs: number = -1;
  private durationMs: number = 0;
  private activeRule: string = '';

  configure(trace: AdFilterTrace): void {
    this.cuts = []; this.lastPositionMs = -1; this.durationMs = 0; this.activeRule = '';
    if (trace.status !== 'rewritten' || trace.live || !trace.timelineUsable || trace.mode === 'off') return;
    let cut: SkippedRange | null = null;
    for (const segment of trace.segments) {
      if (segment.dropped) {
        if (cut === null) cut = { positionMs: segment.startMs, durationMs: 0, rules: [] };
        cut.durationMs += segment.durationMs;
        const label = AdSkipNotifier.ruleLabelFor(segment.reason);
        if (cut.rules.indexOf(label) < 0) cut.rules.push(label);
      } else if (cut !== null) { this.cuts.push(cut); cut = null; }
      this.durationMs = segment.endMs;
    }
    if (cut !== null) this.cuts.push(cut);
  }

  private static ruleLabelFor(reason: string = ''): string {
    if (reason.includes('异采样率')) {
      const rates = reason.match(/(\d+) Hz → (\d+) Hz/);
      return rates !== null ? '音轨采样率 ' + Number(rates[1]) / 1000 + ' → ' + Number(rates[2]) / 1000 +
        ' kHz，前后恢复' : '音轨采样率突变，前后恢复';
    }
    if (reason.includes('异分辨率')) {
      const sizes = reason.match(/主样本 (\d+×\d+) → (\d+×\d+)/);
      return sizes !== null ? '分辨率 ' + sizes[1] + ' → ' + sizes[2] + '，前后恢复' : '分辨率突变，前后恢复';
    }
    if (reason.includes('广告路径关键词')) return '广告路径匹配';
    if (reason.includes('分组全部来自其他域名')) return '整组来自其他域名';
    if (reason.includes('全部分片不足 5 秒')) return '整组短分片（宽松）';
    if (reason.includes('不足 1 秒')) return '不足 1 秒分片（宽松）';
    return '播放清单过滤';
  }

  ruleLabel(): string { return this.activeRule; }

  anchor(positionMs: number): void {
    this.lastPositionMs = Number.isFinite(positionMs) && positionMs >= 0 ? positionMs : -1;
  }

  update(positionMs: number, playing: boolean, durationMs: number): number {
    const previous = this.lastPositionMs;
    this.activeRule = '';
    this.anchor(positionMs);
    if (!playing || previous < 0 || this.lastPositionMs < 0 || positionMs <= previous || positionMs - previous > 3500 ||
      (durationMs > 0 && Math.abs(durationMs - this.durationMs) > Math.max(3000, this.durationMs * 0.01))) return 0;
    const crossed = this.cuts.filter((cut: SkippedRange) => cut.positionMs > previous && cut.positionMs <= positionMs);
    const rules: string[] = [];
    for (const cut of crossed) for (const label of cut.rules) if (rules.indexOf(label) < 0) rules.push(label);
    this.activeRule = rules.join('；');
    return crossed.reduce((sum: number, cut: SkippedRange) => sum + cut.durationMs, 0);
  }
}
