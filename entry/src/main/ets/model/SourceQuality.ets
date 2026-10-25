/** Labels supplied by a source are useful hints, never a measurement of the video track. */
export class SourceQuality {
  static label(remarks: string | undefined): string {
    if (remarks === undefined) return '';
    const size = remarks.match(/\b(\d{3,4})\s*[x×]\s*(\d{3,4})\b/i);
    if (size !== null) return size[1] + '×' + size[2];
    const height = remarks.match(/\b(2160|1440|1080|720|576|480|360)p\b/i);
    if (height !== null) return height[1] + 'P';
    if (/\b4k\b/i.test(remarks)) return '4K';
    if (/蓝光|blu-?ray|\bBD\b/i.test(remarks)) return '蓝光';
    if (/\bHD\b|HD中字|HD国语/i.test(remarks)) return 'HD';
    if (/超清/.test(remarks)) return '超清';
    if (/高清/.test(remarks)) return '高清';
    if (/\bTC\b/i.test(remarks)) return 'TC';
    if (/\bTS\b/i.test(remarks)) return 'TS';
    if (/抢先/.test(remarks)) return '抢先';
    return '';
  }
}
