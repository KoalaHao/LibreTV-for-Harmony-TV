/** Window-based layout rules shared by TV detail and episode selection. Units are vp. */
export class TvLayout {
  static isLandscape(width: number, height: number): boolean {
    return width >= 840 && width > height && height > 0;
  }

  static sidebarWidth(width: number): number {
    return Math.max(360, Math.min(460, Math.round(width * 0.34)));
  }

  static columns(width: number, minimum: number, maximum: number): string {
    const count = Math.max(1, Math.min(maximum, Math.floor((width + 8) / (minimum + 8))));
    return new Array<string>(count).fill('1fr').join(' ');
  }
}
