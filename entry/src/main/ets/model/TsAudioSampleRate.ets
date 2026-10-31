/** Bounded, clear MPEG-TS / AAC ADTS header inspection. Unknown formats return zero. */
export class TsAudioSampleRate {
  private static readonly RATES: number[] = [96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350];

  static read(bytes: Uint8Array): number {
    if (bytes.length < 564 || bytes.length > 16384) return 0;
    let sync = -1;
    for (let i = 0; i < 188 && i + 376 < bytes.length; i++) {
      if (bytes[i] === 0x47 && bytes[i + 188] === 0x47 && bytes[i + 376] === 0x47) { sync = i; break; }
    }
    if (sync < 0) return 0;
    let pid = -1; let counter = -1;
    const payload: number[] = [];
    for (let p = sync; p + 188 <= bytes.length; p += 188) {
      if (bytes[p] !== 0x47) return 0;
      const packetPid = ((bytes[p + 1] & 31) << 8) | bytes[p + 2];
      const start = (bytes[p + 1] & 64) !== 0;
      const control = (bytes[p + 3] >> 4) & 3;
      if (control === 0 || control === 2) continue;
      let offset = p + 4;
      if (control === 3) offset += 1 + bytes[offset];
      if (offset >= p + 188) continue;
      if (start) {
        if (offset + 9 > p + 188 || bytes[offset] !== 0 || bytes[offset + 1] !== 0 || bytes[offset + 2] !== 1 ||
          bytes[offset + 3] < 0xc0 || bytes[offset + 3] > 0xdf) continue;
        if (pid >= 0 && packetPid !== pid) return 0;
        pid = packetPid;
        offset += 9 + bytes[offset + 8];
      }
      if (packetPid !== pid) continue;
      if ((bytes[p + 1] & 0x80) !== 0 || (bytes[p + 3] & 0xc0) !== 0 || offset > p + 188) return 0;
      const current = bytes[p + 3] & 15;
      if (counter >= 0 && current !== (counter + 1) % 16) return 0;
      counter = current;
      for (let i = offset; i < p + 188; i++) payload.push(bytes[i]);
    }
    let rate = 0; let frames = 0; let next = -1;
    for (let i = 0; i + 7 <= payload.length; i++) {
      if (payload[i] !== 0xff || (payload[i + 1] & 0xf6) !== 0xf0) continue;
      const sampleIndex = (payload[i + 2] >> 2) & 15;
      const channels = ((payload[i + 2] & 1) << 2) | (payload[i + 3] >> 6);
      const length = ((payload[i + 3] & 3) << 11) | (payload[i + 4] << 3) | (payload[i + 5] >> 5);
      const header = (payload[i + 1] & 1) !== 0 ? 7 : 9;
      if (sampleIndex >= TsAudioSampleRate.RATES.length || channels === 0 || length < header || i + length > payload.length) continue;
      const value = TsAudioSampleRate.RATES[sampleIndex];
      if (rate > 0 && value !== rate) return 0;
      if (next === i) frames++;
      rate = value;
      next = i + length;
      i += length - 1;
    }
    return frames > 0 ? rate : 0;
  }
}
