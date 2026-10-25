export interface PosterOrigin { x: number; y: number; width: number; height: number; }
export interface DiscoveryColumns {
  poster: PosterOrigin;
  metadataX: number;
  metadataWidth: number;
  resultsX: number;
  resultsWidth: number;
  bodyY: number;
  bodyHeight: number;
}

export class DiscoveryLayout {
  static columns(width: number, height: number): DiscoveryColumns {
    const w = Number.isFinite(width) && width > 0 ? Math.max(960, width) : 1280;
    const h = Number.isFinite(height) && height > 0 ? Math.max(600, height) : 720;
    const posterWidth = Math.min(280, w * 0.21);
    const resultWidth = Math.max(360, w * 0.38);
    const middleWidth = w - 140 - posterWidth - resultWidth;
    return { poster: { x: 40, y: 24, width: posterWidth, height: posterWidth / 0.72 + 36 },
      metadataX: 70 + posterWidth, metadataWidth: middleWidth,
      resultsX: w - 40 - resultWidth, resultsWidth: resultWidth, bodyY: 24, bodyHeight: h - 48 };
  }
}
