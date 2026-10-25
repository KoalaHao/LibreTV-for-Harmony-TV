import { ColorMetrics, LengthMetrics } from '@kit.ArkUI';

/** Inset outline stays visible inside clipped poster cards and scroll containers. */
export const TV_FOCUS: FocusBoxStyle = {
  margin: LengthMetrics.vp(-3),
  strokeWidth: LengthMetrics.vp(3),
  strokeColor: ColorMetrics.numeric(0xFFFFC857)
};
