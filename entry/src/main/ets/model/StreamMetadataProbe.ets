import { media } from '@kit.MediaKit';

export interface ProbeDimensions { width: number; height: number; }

/** API-11 metadata extraction from a bounded, already downloaded prefix; never starts a player or sound. */
export class StreamMetadataProbe {
  static async dimensions(bytes: Uint8Array): Promise<ProbeDimensions> {
    const empty: ProbeDimensions = { width: 0, height: 0 };
    let extractor: media.AVMetadataExtractor | null = null;
    let timer = -1;
    let cursor = 0;
    try {
      extractor = await media.createAVMetadataExtractor();
      extractor.dataSrc = { fileSize: bytes.byteLength,
        callback: (buffer: ArrayBuffer, length: number, position?: number): number => {
          const offset = position !== undefined ? position : cursor;
          if (offset < 0 || offset >= bytes.byteLength) return -1;
          const count = Math.min(length, buffer.byteLength, bytes.byteLength - offset);
          new Uint8Array(buffer).set(bytes.subarray(offset, offset + count));
          cursor = offset + count;
          return count;
        }
      };
      const timeout = new Promise<media.AVMetadata | null>((resolve) => { timer = setTimeout(() => resolve(null), 1500); });
      const metadata = await Promise.race([extractor.fetchMetadata(), timeout]);
      if (metadata === null) return empty;
      const width = Number(metadata.videoWidth); const height = Number(metadata.videoHeight);
      if (Number.isInteger(width) && Number.isInteger(height) && width >= 16 && height >= 16 && width <= 16384 && height <= 16384) {
        return { width: width, height: height };
      }
    } catch (e) { /* Unsupported or encrypted prefixes remain unknown. */ }
    finally {
      if (timer >= 0) clearTimeout(timer);
      if (extractor !== null) { try { await extractor.release(); } catch (e) { /* Already released. */ } }
    }
    return empty;
  }
}
