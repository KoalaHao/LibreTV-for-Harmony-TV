import { SearchItem, VodSource, VideoDetail } from './Types';
import { CmsClient } from './CmsClient';
import { DetailCache } from './DetailCache';
import { HttpClient } from '../net/HttpClient';
import { HlsProbe } from './HlsProbe';
import { StreamMetadataProbe } from './StreamMetadataProbe';

export interface SourceProbeResult {
  sourceKey: string;
  vodId: string;
  checkedAt: number;
  status: string;
  latencyMs: number;
  width: number;
  height: number;
  resolutionAt: number;
  resolutionSource: string;
  httpStatus: number;
  note: string;
}

export class SourceProbe {
  static result(item: SearchItem, status: string, latency: number = 0, width: number = 0, height: number = 0,
    origin: string = 'none', code: number = 0, note: string = ''): SourceProbeResult {
    const now = Date.now();
    return { sourceKey: item.sourceKey, vodId: item.vodId, checkedAt: now, status: status, latencyMs: latency,
      width: width, height: height, resolutionAt: width > 0 && height > 0 ? now : 0,
      resolutionSource: origin, httpStatus: code, note: note };
  }

  private static mediaUrl(detail: VideoDetail): string {
    const urls = detail.episodes.map((episode) => episode.url);
    if (detail.info.lines !== undefined) {
      for (const line of detail.info.lines) for (const episode of line.episodes) urls.push(episode.url);
    }
    const http = urls.filter((value: string) => /^https?:\/\//i.test(value));
    const hls = http.find((value: string) => /\.m3u8(?:[?#]|$)/i.test(value));
    return hls !== undefined ? hls : (http[0] || '');
  }

  static async run(item: SearchItem, source: VodSource, wanted: () => boolean): Promise<SourceProbeResult | null> {
    let detail: VideoDetail;
    try { detail = await DetailCache.load(source.key, item.vodId, () => CmsClient.detail(source, item.vodId)); }
    catch (e) { return SourceProbe.result(item, 'failed', 0, 0, 0, 'none', 0, '详情暂时无法访问'); }
    if (!wanted()) return null;
    let target = SourceProbe.mediaUrl(detail);
    if (target === '') return SourceProbe.result(item, 'failed', 0, 0, 0, 'none', 0, '没有可探测的播放地址');
    const deadline = Date.now() + 14000;
    let latency = 0;
    let code = 0;
    if (!/\.m3u8(?:[?#]|$)/i.test(target)) {
      const begin = Date.now(); const response = await HttpClient.head(target);
      latency = Date.now() - begin;
      if (!response.ok) return SourceProbe.result(item, 'failed', latency, 0, 0, 'none', response.status, 'HTTP 探测未通过');
      if (wanted() && /\.(mp4|mkv|ts|m4s)(?:[?#]|$)/i.test(target)) {
        const sample = await HttpClient.getProbeBytes(target);
        if (sample.ok && sample.bytes.byteLength > 0) {
          const dimensions = await StreamMetadataProbe.dimensions(sample.bytes);
          return SourceProbe.result(item, 'ok', latency, dimensions.width, dimensions.height,
            dimensions.width > 0 ? 'stream' : 'none', response.status);
        }
      }
      return SourceProbe.result(item, 'ok', latency, 0, 0, 'none', response.status, '未读取到视频尺寸');
    }
    for (let depth = 0; depth < 3 && Date.now() < deadline; depth++) {
      if (!wanted()) return null;
      const timeout = Math.max(500, Math.min(4000, deadline - Date.now()));
      const begin = Date.now();
      let response = await HttpClient.getTextLimited(target, { 'User-Agent': HttpClient.UA,
        'Referer': HttpClient.originOf(target) }, timeout);
      if ((response.status === 403 || response.status === 418) && Date.now() < deadline && wanted()) {
        response = await HttpClient.getTextLimited(target, { 'User-Agent': HttpClient.UA },
          Math.max(500, Math.min(4000, deadline - Date.now())));
      }
      latency = Date.now() - begin; code = response.status;
      if (!response.ok) return SourceProbe.result(item, 'failed', latency, 0, 0, 'none', code, '播放清单暂时无法访问');
      const info = HlsProbe.parse(response.text, target);
      if (!info.valid) return SourceProbe.result(item, 'failed', latency, 0, 0, 'none', code, '响应不是播放清单');
      if (info.width > 0) return SourceProbe.result(item, 'ok', latency, info.width, info.height, 'manifest', code);
      if (info.variant !== '' && info.variant !== target && /^https?:\/\//i.test(info.variant)) {
        target = info.variant; continue;
      }
      if (info.sample !== '' && !info.encrypted && wanted() && Date.now() < deadline && /^https?:\/\//i.test(info.sample)) {
        const sample = await HttpClient.getProbeBytes(info.sample, Math.max(500, Math.min(4000, deadline - Date.now())));
        if (sample.ok && sample.bytes.byteLength > 0) {
          const dimensions = await StreamMetadataProbe.dimensions(sample.bytes);
          return SourceProbe.result(item, 'ok', latency, dimensions.width, dimensions.height,
            dimensions.width > 0 ? 'stream' : 'none', code);
        }
      }
      return SourceProbe.result(item, 'ok', latency, 0, 0, 'none', code,
        info.encrypted ? '加密流，尺寸待播放时确认' : '未读取到视频尺寸');
    }
    return SourceProbe.result(item, 'ok', latency, 0, 0, 'none', code, '未读取到视频尺寸');
  }
}
