export interface EncodedDimensions { width: number; height: number; }

class SpsBits {
  private offset: number = 0;
  private bytes: Uint8Array;
  constructor(bytes: Uint8Array) { this.bytes = bytes; }
  read(count: number): number {
    if (count < 0 || count > 24 || this.offset + count > this.bytes.length * 8) throw new Error('Truncated SPS');
    let value = 0;
    for (let i = 0; i < count; i++, this.offset++) {
      value = value * 2 + ((this.bytes[this.offset >> 3] >> (7 - (this.offset & 7))) & 1);
    }
    return value;
  }
  ue(): number {
    let zeros = 0;
    while (this.read(1) === 0) { if (++zeros > 20) throw new Error('Invalid Golomb code'); }
    return Math.pow(2, zeros) - 1 + this.read(zeros);
  }
  se(): number { const value = this.ue(); return value % 2 === 1 ? (value + 1) / 2 : -value / 2; }
}

/** Reads only unencrypted H.264 SPS headers from a bounded MPEG-TS prefix. Never decodes a frame. */
export class TsVideoDimensions {
  static empty(): EncodedDimensions { return { width: 0, height: 0 }; }

  static sps(nal: Uint8Array): EncodedDimensions {
    try {
      if (nal.length < 5 || (nal[0] & 0x9f) !== 7 || nal.length > 4096) return TsVideoDimensions.empty();
      const rbsp: number[] = [];
      for (let i = 1; i < nal.length; i++) {
        if (i >= 3 && nal[i] === 3 && nal[i - 1] === 0 && nal[i - 2] === 0) continue;
        rbsp.push(nal[i]);
      }
      const bits = new SpsBits(new Uint8Array(rbsp));
      const profile = bits.read(8); bits.read(8); bits.read(8);
      if (bits.ue() > 31) return TsVideoDimensions.empty();
      let chroma = 1; let separate = 0;
      if ([100, 110, 122, 244, 44, 83, 86, 118, 128, 138, 139, 134, 135].indexOf(profile) >= 0) {
        chroma = bits.ue();
        if (chroma > 3) return TsVideoDimensions.empty();
        if (chroma === 3) separate = bits.read(1);
        if (bits.ue() > 6 || bits.ue() > 6) return TsVideoDimensions.empty();
        bits.read(1);
        if (bits.read(1) !== 0) {
          for (let i = 0; i < (chroma === 3 ? 12 : 8); i++) {
            if (bits.read(1) === 0) continue;
            let last = 8; let next = 8;
            for (let j = 0; j < (i < 6 ? 16 : 64); j++) {
              if (next !== 0) next = (last + bits.se() + 256) % 256;
              if (next !== 0) last = next;
            }
          }
        }
      } else if ([66, 77, 88].indexOf(profile) < 0) return TsVideoDimensions.empty();
      if (bits.ue() > 12) return TsVideoDimensions.empty();
      const order = bits.ue();
      if (order === 0) { if (bits.ue() > 12) return TsVideoDimensions.empty(); }
      else if (order === 1) {
        bits.read(1); bits.se(); bits.se();
        const cycle = bits.ue(); if (cycle > 255) return TsVideoDimensions.empty();
        for (let i = 0; i < cycle; i++) bits.se();
      } else if (order !== 2) return TsVideoDimensions.empty();
      if (bits.ue() > 32) return TsVideoDimensions.empty();
      bits.read(1);
      const columns = bits.ue() + 1; const rows = bits.ue() + 1;
      const frameOnly = bits.read(1);
      if (frameOnly === 0) bits.read(1);
      bits.read(1);
      let left = 0; let right = 0; let top = 0; let bottom = 0;
      if (bits.read(1) !== 0) { left = bits.ue(); right = bits.ue(); top = bits.ue(); bottom = bits.ue(); }
      const format = separate !== 0 ? 0 : chroma;
      const cropX = format === 1 || format === 2 ? 2 : 1;
      const cropY = (format === 1 ? 2 : 1) * (2 - frameOnly);
      const width = columns * 16 - (left + right) * cropX;
      const height = rows * 16 * (2 - frameOnly) - (top + bottom) * cropY;
      if (width < 16 || height < 16 || width > 8192 || height > 8192) return TsVideoDimensions.empty();
      return { width: width, height: height };
    } catch (e) { return TsVideoDimensions.empty(); }
  }

  static read(bytes: Uint8Array): EncodedDimensions {
    if (bytes.length < 564 || bytes.length > 16384) return TsVideoDimensions.empty();
    let sync = -1;
    for (let i = 0; i < 188 && i + 376 < bytes.length; i++) {
      if (bytes[i] === 0x47 && bytes[i + 188] === 0x47 && bytes[i + 376] === 0x47) { sync = i; break; }
    }
    if (sync < 0) return TsVideoDimensions.empty();
    let pid = -1; let counter = -1;
    const video: number[] = [];
    for (let p = sync; p + 188 <= bytes.length; p += 188) {
      if (bytes[p] !== 0x47) return TsVideoDimensions.empty();
      const packetPid = ((bytes[p + 1] & 31) << 8) | bytes[p + 2];
      const start = (bytes[p + 1] & 64) !== 0;
      const control = (bytes[p + 3] >> 4) & 3;
      if (control === 0 || control === 2) continue;
      let offset = p + 4;
      if (control === 3) offset += 1 + bytes[offset];
      if (offset >= p + 188) continue;
      if (start) {
        if (offset + 9 > p + 188 || bytes[offset] !== 0 || bytes[offset + 1] !== 0 || bytes[offset + 2] !== 1 ||
          bytes[offset + 3] < 0xe0 || bytes[offset + 3] > 0xef) continue;
        if (pid >= 0 && pid !== packetPid) return TsVideoDimensions.empty();
        pid = packetPid;
        offset += 9 + bytes[offset + 8];
      }
      if (packetPid !== pid) continue;
      if ((bytes[p + 1] & 0x80) !== 0 || (bytes[p + 3] & 0xc0) !== 0 || offset > p + 188) return TsVideoDimensions.empty();
      const current = bytes[p + 3] & 15;
      if (counter >= 0 && current !== (counter + 1) % 16) return TsVideoDimensions.empty();
      counter = current;
      for (let i = offset; i < p + 188; i++) video.push(bytes[i]);
    }
    let result = TsVideoDimensions.empty();
    for (let i = 0; i + 4 < video.length; i++) {
      if (video[i] !== 0 || video[i + 1] !== 0 || video[i + 2] !== 1 || (video[i + 3] & 0x9f) !== 7) continue;
      const start = i + 3; let end = start + 1;
      while (end + 2 < video.length && !(video[end] === 0 && video[end + 1] === 0 && video[end + 2] === 1)) end++;
      const dimensions = TsVideoDimensions.sps(new Uint8Array(video.slice(start, end)));
      if (dimensions.width === 0) continue;
      if (result.width > 0 && (result.width !== dimensions.width || result.height !== dimensions.height)) return TsVideoDimensions.empty();
      result = dimensions;
    }
    return result;
  }
}
