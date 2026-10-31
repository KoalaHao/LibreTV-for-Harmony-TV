import { AdDiagnostics, AdFilterTrace } from './AdDiagnostics';

/** Approximate VOD content anchors when the user changes playlist filtering. */
export class AdFilterTimeline {
  static toSource(trace: AdFilterTrace, positionMs: number, durationMs: number = 0): number {
    const index = AdDiagnostics.locate(trace, positionMs, durationMs);
    if (index < 0) return Math.max(0, positionMs);
    const segment = trace.segments[index];
    return segment.sourceStartMs + positionMs - segment.startMs;
  }

  static fromSource(trace: AdFilterTrace, sourceMs: number): number {
    if (trace.status !== 'rewritten' || trace.live || !trace.timelineUsable) return Math.max(0, sourceMs);
    for (const segment of trace.segments) {
      if (segment.dropped || sourceMs >= segment.sourceStartMs + segment.durationMs) continue;
      return segment.startMs + Math.max(0, sourceMs - segment.sourceStartMs);
    }
    return trace.segments.length > 0 ? trace.segments[trace.segments.length - 1].endMs : Math.max(0, sourceMs);
  }
}
