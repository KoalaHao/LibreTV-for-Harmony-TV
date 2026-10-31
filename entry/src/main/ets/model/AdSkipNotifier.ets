import { AdFilterTrace } from './AdDiagnostics';

interface SkippedRange { positionMs: number; durationMs: number; }

/** Notices describe cuts in the rewritten VOD timeline, never inferred ads in a playing source. */
export class AdSkipNotifier {
  private cuts: SkippedRange[] = [];
  private lastPositionMs: number = -1;
  private durationMs: number = 0;

  configure(trace: AdFilterTrace): void {
    this.cuts = []; this.lastPositionMs = -1; this.durationMs = 0;
    if (trace.status !== 'rewritten' || trace.live || !trace.timelineUsable || trace.mode === 'off') return;
    let cut: SkippedRange | null = null;
    for (const segment of trace.segments) {
      if (segment.dropped) {
        if (cut === null) cut = { positionMs: segment.startMs, durationMs: 0 };
        cut.durationMs += segment.durationMs;
      } else if (cut !== null) { this.cuts.push(cut); cut = null; }
      this.durationMs = segment.endMs;
    }
    if (cut !== null) this.cuts.push(cut);
  }

  anchor(positionMs: number): void {
    this.lastPositionMs = Number.isFinite(positionMs) && positionMs >= 0 ? positionMs : -1;
  }

  update(positionMs: number, playing: boolean, durationMs: number): number {
    const previous = this.lastPositionMs;
    this.anchor(positionMs);
    if (!playing || previous < 0 || this.lastPositionMs < 0 || positionMs <= previous || positionMs - previous > 3500 ||
      (durationMs > 0 && Math.abs(durationMs - this.durationMs) > Math.max(3000, this.durationMs * 0.01))) return 0;
    return this.cuts.filter((cut: SkippedRange) => cut.positionMs > previous && cut.positionMs <= positionMs)
      .reduce((sum: number, cut: SkippedRange) => sum + cut.durationMs, 0);
  }
}
