/** Small, versioned playback state carried by the OS continuation channel, never a player or sandbox path. */
export interface ContinuedPlayback {
  schema: number;
  transferId: string;
  sourceKey: string;
  vodId: string;
  episode: number;
  episodeName: string;
  title: string;
  pic: string;
  lineIndex: number;
  positionMs: number;
  speed: number;
  playing: boolean;
  episodeUrl: string;
}

export class PlaybackContinuation {
  static readonly KEY: string = 'libretv.playback.v1';
  static readonly MIN_VERSION: number = 1100104;
  private static provider: (() => ContinuedPlayback | null) | null = null;
  private static stop: (() => void) | null = null;
  private static owner: number = 0;
  private static cleanup: (() => void) | null = null;
  private static receiver: ((state: ContinuedPlayback) => void) | null = null;
  private static pending: ContinuedPlayback | null = null;
  private static seenTransfers: string[] = [];
  static availabilityChanged: () => void = () => {};

  static register(provider: () => ContinuedPlayback | null, stop: () => void, cleanup: (() => void) | null = null): number {
    PlaybackContinuation.owner++;
    PlaybackContinuation.provider = provider;
    PlaybackContinuation.stop = stop;
    PlaybackContinuation.cleanup = cleanup;
    PlaybackContinuation.refresh();
    return PlaybackContinuation.owner;
  }

  static unregister(owner: number): void {
    if (owner !== PlaybackContinuation.owner) return;
    PlaybackContinuation.provider = null;
    PlaybackContinuation.stop = null;
    PlaybackContinuation.cleanup = null;
    PlaybackContinuation.refresh();
  }

  static refresh(): void { PlaybackContinuation.availabilityChanged(); }

  static available(): boolean {
    try { return PlaybackContinuation.provider !== null && PlaybackContinuation.provider() !== null; }
    catch (e) { return false; }
  }

  static capture(): string | null {
    if (PlaybackContinuation.provider === null) return null;
    try {
      const state = PlaybackContinuation.provider();
      if (state === null) return null;
      state.transferId = Date.now().toString(36) + '-' + Math.random().toString(36).substring(2);
      const data = JSON.stringify(state);
      return PlaybackContinuation.parse(data) !== null ? data : null;
    } catch (e) { return null; }
  }

  static remoteUrl(url: string): boolean {
    const match = /^https?:\/\/([^/?#\s]+)(?:[/?#]|$)/i.exec(url);
    if (match === null || url.length > 8192 || /\s/.test(url)) return false;
    const host = match[1].toLowerCase().split('@').pop();
    if (host === undefined) return false;
    const name = host.startsWith('[') ? host.substring(0, host.indexOf(']') + 1) : host.split(':')[0];
    return name !== 'localhost' && !name.endsWith('.localhost') && !name.startsWith('127.') &&
      name !== '[::1]' && name !== '0.0.0.0';
  }

  static parse(data: string): ContinuedPlayback | null {
    // <= 24K UTF-16 code units stays below the OS 100KB recommendation even for UTF-8 text.
    if (data.length === 0 || data.length > 24576) return null;
    try {
      const v = JSON.parse(data) as ContinuedPlayback;
      if (v === null || typeof v !== 'object' || v.schema !== 1 ||
        !PlaybackContinuation.text(v.transferId, 128) || !PlaybackContinuation.text(v.sourceKey, 256) ||
        !PlaybackContinuation.text(v.vodId, 256) || !PlaybackContinuation.text(v.title, 512, true) ||
        !PlaybackContinuation.text(v.episodeName, 256, true) || !PlaybackContinuation.text(v.pic, 4096, true) ||
        !PlaybackContinuation.integer(v.episode, 100000) || !PlaybackContinuation.integer(v.lineIndex, 10000) ||
        !PlaybackContinuation.integer(v.positionMs, 604800000) || typeof v.playing !== 'boolean' ||
        [0.5, 0.75, 1, 1.25, 1.5, 2].indexOf(v.speed) < 0 ||
        typeof v.episodeUrl !== 'string' || !PlaybackContinuation.remoteUrl(v.episodeUrl)) return null;
      // Copy only protocol fields; never forward arbitrary Want parameters or user data.
      return { schema: 1, transferId: v.transferId, sourceKey: v.sourceKey, vodId: v.vodId,
        episode: v.episode, episodeName: v.episodeName, title: v.title, pic: v.pic === '' || PlaybackContinuation.remoteUrl(v.pic) ? v.pic : '',
        lineIndex: v.lineIndex, positionMs: v.positionMs, speed: v.speed,
        playing: v.playing, episodeUrl: v.episodeUrl };
    } catch (e) { return null; }
  }

  private static text(value: string, limit: number, empty: boolean = false): boolean {
    return typeof value === 'string' && (empty || value.length > 0) && value.length <= limit;
  }

  private static integer(value: number, max: number): boolean {
    return Number.isSafeInteger(value) && value >= 0 && value <= max;
  }

  static receive(data: string): boolean {
    const state = PlaybackContinuation.parse(data);
    if (state === null) return false;
    if (PlaybackContinuation.seenTransfers.indexOf(state.transferId) >= 0) return true;
    PlaybackContinuation.seenTransfers.push(state.transferId);
    if (PlaybackContinuation.seenTransfers.length > 32) PlaybackContinuation.seenTransfers.shift();
    PlaybackContinuation.pending = state;
    PlaybackContinuation.deliver();
    return true;
  }

  static attach(receiver: (state: ContinuedPlayback) => void): void {
    PlaybackContinuation.receiver = receiver;
    PlaybackContinuation.deliver();
  }

  static detach(): void { PlaybackContinuation.receiver = null; }

  private static deliver(): void {
    const receiver = PlaybackContinuation.receiver;
    const state = PlaybackContinuation.pending;
    if (receiver === null || state === null) return;
    PlaybackContinuation.pending = null;
    receiver(state);
  }

  /** Ability teardown must release native resources without navigating a destroyed window. */
  static shutdown(): void {
    const cleanup = PlaybackContinuation.cleanup;
    PlaybackContinuation.provider = null;
    PlaybackContinuation.stop = null;
    PlaybackContinuation.cleanup = null;
    PlaybackContinuation.receiver = null;
    PlaybackContinuation.pending = null;
    if (cleanup !== null) cleanup();
  }

  /** Close the old local player before replacing it with a newly received task. */
  static stopCurrent(): void {
    if (PlaybackContinuation.stop !== null) PlaybackContinuation.stop();
  }
}
