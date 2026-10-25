import { image } from '@kit.ImageKit';

interface PixelMapEntry { pixels: image.PixelMap; bytes: number; }

/** Limits retained decoded images by bytes; eviction never invalidates a visible image's reference. */
export class PixelMapCache {
  private static readonly entries: Map<string, PixelMapEntry> = new Map();
  private static readonly pending: Map<string, Promise<image.PixelMap | undefined>> = new Map();
  private static bytes: number = 0;
  private static readonly MAX_BYTES: number = 64 * 1024 * 1024;
  private static readonly MAX_ENTRIES: number = 96;

  static get(key: string): image.PixelMap | undefined {
    const entry = PixelMapCache.entries.get(key);
    if (entry === undefined) return undefined;
    PixelMapCache.entries.delete(key);
    PixelMapCache.entries.set(key, entry);
    return entry.pixels;
  }

  private static put(key: string, pixels: image.PixelMap): void {
    const bytes = pixels.getPixelBytesNumber();
    if (bytes <= 0 || bytes > PixelMapCache.MAX_BYTES) return;
    while (PixelMapCache.entries.size > 0 && (PixelMapCache.bytes + bytes > PixelMapCache.MAX_BYTES ||
      PixelMapCache.entries.size >= PixelMapCache.MAX_ENTRIES)) {
      const oldest: string = PixelMapCache.entries.keys().next().value as string;
      if (oldest === undefined) break;
      const entry = PixelMapCache.entries.get(oldest);
      if (entry !== undefined) PixelMapCache.bytes -= entry.bytes;
      PixelMapCache.entries.delete(oldest);
    }
    PixelMapCache.entries.set(key, { pixels: pixels, bytes: bytes });
    PixelMapCache.bytes += bytes;
  }

  static load(key: string, decode: () => Promise<image.PixelMap | undefined>): Promise<image.PixelMap | undefined> {
    const cached = PixelMapCache.get(key);
    if (cached !== undefined) return Promise.resolve(cached);
    const pending = PixelMapCache.pending.get(key);
    if (pending !== undefined) return pending;
    const task = Promise.resolve().then(decode).then((pixels: image.PixelMap | undefined) => {
      if (pixels !== undefined) PixelMapCache.put(key, pixels);
      return pixels;
    });
    PixelMapCache.pending.set(key, task);
    task.then(() => { PixelMapCache.pending.delete(key); }, () => { PixelMapCache.pending.delete(key); });
    return task;
  }
}
