/** Lingxi directional input is normalized to PanGesture, not DPAD key events. */
export class TvPlaybackGesture {
  private enabled: boolean = false;
  private action: string = 'none';
  private menuStarted: number = -1;
  private menuRepeated: boolean = false;

  menuDown(timeMs: number): void {
    if (this.menuStarted < 0) this.menuStarted = timeMs;
    else this.menuRepeated = true;
  }

  menuUp(timeMs: number): boolean {
    const short = this.menuStarted >= 0 && !this.menuRepeated &&
      timeMs >= this.menuStarted && timeMs - this.menuStarted < 500;
    this.menuStarted = -1;
    this.menuRepeated = false;
    return short;
  }

  reset(): void {
    this.cancel();
    this.menuStarted = -1;
    this.menuRepeated = false;
  }

  begin(enabled: boolean): void {
    this.enabled = enabled;
    this.action = 'none';
  }

  update(x: number, y: number): void {
    if (!this.enabled || !Number.isFinite(x) || !Number.isFinite(y)) return;
    if (Math.max(Math.abs(x), Math.abs(y)) < 24) this.action = 'none';
    else if (Math.abs(x) > Math.abs(y)) this.action = x > 0 ? 'forward' : 'backward';
    else this.action = 'controls';
  }

  end(): string {
    const action = this.enabled ? this.action : 'none';
    this.cancel();
    return action;
  }

  cancel(): void {
    this.enabled = false;
    this.action = 'none';
  }
}
