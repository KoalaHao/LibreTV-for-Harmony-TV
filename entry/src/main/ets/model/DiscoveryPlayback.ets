import { Episode, PlayRecord, VideoDetail } from './Types';

export interface DiscoveryPlaybackChoice {
  episode: Episode;
  episodeIndex: number;
  lineIndex: number;
  positionMs: number;
}

export class DiscoveryPlayback {
  static choose(detail: VideoDetail, record?: PlayRecord): DiscoveryPlaybackChoice | null {
    const lines = detail.info.lines || [];
    let lineIndex = 0;
    if (lines.length > 0) {
      const hls = lines.findIndex((line) => line.episodes.some((episode) => /^https?:\/\/.*\.m3u8(?:[?#]|$)/i.test(episode.url)));
      const saved = record !== undefined && record.lineIndex !== undefined ? record.lineIndex : -1;
      if (saved >= 0 && saved < lines.length && lines[saved].episodes.some((episode) => /\.m3u8(?:[?#]|$)/i.test(episode.url))) lineIndex = saved;
      else if (hls >= 0) lineIndex = hls;
      else if (saved >= 0 && saved < lines.length) lineIndex = saved;
    }
    const episodes = lines.length > 0 ? lines[lineIndex].episodes : detail.episodes;
    if (episodes.length === 0) return null;
    const savedEpisode = record !== undefined ? record.episode : -1;
    const resume = Number.isInteger(savedEpisode) && savedEpisode >= 0 && savedEpisode < episodes.length;
    const index = resume ? savedEpisode : 0;
    const position = resume && record !== undefined && Number.isFinite(record.positionMs) ? Math.max(0, record.positionMs) : 0;
    return { episode: episodes[index], episodeIndex: index, lineIndex: lineIndex, positionMs: position };
  }
}
