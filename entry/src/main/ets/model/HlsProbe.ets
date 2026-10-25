import { Utils } from '../common/Utils';

export interface HlsProbeInfo {
  valid: boolean;
  width: number;
  height: number;
  variant: string;
  sample: string;
  encrypted: boolean;
}

export class HlsProbe {
  private static resolve(base: string, value: string): string {
    if (value.startsWith('//')) return base.substring(0, base.indexOf(':')) + ':' + value;
    return Utils.resolveUrl(base, value);
  }

  static parse(text: string, base: string): HlsProbeInfo {
    const result: HlsProbeInfo = { valid: false, width: 0, height: 0, variant: '', sample: '', encrypted: false };
    const value = text.replace(/^\uFEFF/, '').trim();
    if (!value.startsWith('#EXTM3U') || value.length > 131072) return result;
    result.valid = true;
    const lines = value.split(/\r?\n/).map((line: string) => line.trim());
    let stream = '';
    let bestPixels = -1;
    let bestBandwidth = -1;
    let firstSegment = '';
    let init = '';
    for (const line of lines) {
      if (line.startsWith('#EXT-X-KEY:')) {
        const method = line.match(/(?:^|[,:])METHOD=([^,]+)/);
        if (method !== null && method[1] !== 'NONE') result.encrypted = true;
      }
      if (line.startsWith('#EXT-X-MAP:')) {
        const uri = line.match(/URI="([^"]+)"/);
        if (uri !== null) init = HlsProbe.resolve(base, uri[1]);
      }
      if (line.startsWith('#EXT-X-STREAM-INF:')) { stream = line; continue; }
      if (line === '' || line.startsWith('#')) continue;
      if (stream !== '') {
        const dimensions = stream.match(/(?:^|[,:])RESOLUTION=(\d+)x(\d+)/i);
        const bandwidth = stream.match(/(?:^|[,:])BANDWIDTH=(\d+)/);
        const width = dimensions !== null ? Number(dimensions[1]) : 0;
        const height = dimensions !== null ? Number(dimensions[2]) : 0;
        const pixels = width >= 16 && height >= 16 && width <= 16384 && height <= 16384 ? width * height : 0;
        const rate = bandwidth !== null ? Number(bandwidth[1]) : 0;
        if (pixels > bestPixels || (pixels === bestPixels && rate > bestBandwidth)) {
          bestPixels = pixels; bestBandwidth = rate;
          result.width = pixels > 0 ? width : 0; result.height = pixels > 0 ? height : 0;
          result.variant = HlsProbe.resolve(base, line);
        }
        stream = '';
      } else if (firstSegment === '') firstSegment = HlsProbe.resolve(base, line);
    }
    result.sample = init !== '' ? init : firstSegment;
    return result;
  }
}
