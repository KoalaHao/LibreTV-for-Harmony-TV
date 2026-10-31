/**
 * M3U8 播放列表重写器 —— LibreTV 自定义 HLS Loader（广告过滤）的鸿蒙原生等价实现
 *
 * Web 版通过 hls.js 自定义 loader 在内存里改写 m3u8；
 * 原生端没有等价注入点，改为：自行拉取播放列表 → 过滤广告分片 → 相对地址绝对化
 *   → 写入应用沙箱 → AVPlayer 通过 fd:// + APPLICATION_M3U8 播放本地列表。
 *
 * 广告判定（与 LibreTV「严格 / 宽松」两档对齐）：
 * - loose：丢弃被 #EXT-X-DISCONTINUITY 包裹、且整组均为短分片(<5s)的区间（典型广告插槽）；
 *          无 DISCONTINUITY 时退化为丢弃 <1s 的极小分片
 * - strict：短片段 / 路径 / 异域规则，另检查有完整证据的短时异分辨率插播
 */

import { HttpClient } from '../net/HttpClient';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { Utils } from '../common/Utils';
import { AdDiagnostics, AdFilterTrace, AdSegmentDecision } from './AdDiagnostics';
import { AdResolutionRule, ResolutionAdResult } from './AdResolutionRule';

export interface MediaPlaylistResult {
  content: string;
  segmentCount: number;
  filteredCount: number;
  trace: AdFilterTrace;
}

export interface RewriteOutcome {
  ok: boolean;
  localPath: string;
  /** 必须持有不关闭，供 fd:// 播放使用 */
  file: fs.File | null;
  segmentCount: number;
  filteredCount: number;
  error: string;
  trace: AdFilterTrace;
}

interface Segment {
  tags: string[];
  uri: string;
  dur: number;
}

export class M3u8Rewriter {
  /** 整组短分片视为广告组的阈值（秒） */
  static readonly AD_RUN_MAX_DUR = 5.0;
  /** strict 模式单分片阈值（秒） */
  static readonly AD_SEG_MAX_DUR = 3.0;
  /** 无 DISCONTINUITY 时的极小分片阈值（秒） */
  static readonly TINY_SEG_DUR = 1.0;
  /**
   * 广告 URI 关键词：命中即判广告。大量采集站把广告插成与正片同长的分片，
   * 时长启发式判不出来，但地址特征很明显（独立广告路径 / 广告联盟域名）。
   */
  static readonly AD_URI_KEYWORDS: string[] = [
    '/ads/', '/ad/', '/adv/', '/ad-', 'advert', 'adshow', 'adplayer',
    'adcreative', 'admaster', 'doubleclick', '/guanggao', '/gg/'
  ];

  static async rewrite(url: string, headers: Record<string, string>, mode: string, outDir: string,
    wanted: () => boolean = () => true): Promise<RewriteOutcome> {
    let trace = AdDiagnostics.empty(mode, 'pending', url);
    let opened: fs.File | null = null;
    let stage = '读取播放清单';
    try {
      // 1) 逐级解析主播放列表，选最高码率变体
      let currentUrl = url;
      let text = '';
      for (let depth = 0; depth < 4; depth++) {
        if (!wanted()) return M3u8Rewriter.fail('播放解析已取消', trace);
        // 与下载链路保持一致：按 Referer 逐级放宽，避免 CDN 防盗链直接 403
        trace.playlistUrl = AdDiagnostics.safeUrl(currentUrl);
        const res = await HttpClient.getTextResilient(currentUrl, 12000);
        if (!res.ok || res.text === '') {
          return M3u8Rewriter.fail('播放列表请求失败: ' + res.error, trace,
            res.status > 0 ? '清单请求 HTTP ' + res.status + '；已回退原地址播放。' : '清单请求失败；已回退原地址播放。');
        }
        text = res.text;
        if (!text.trim().startsWith('#EXTM3U')) {
          const mediaUrl = Utils.mediaUrlFromPage(text, currentUrl);
          if (mediaUrl !== '' && mediaUrl !== currentUrl && /\.m3u8(?:[?#]|$)/i.test(mediaUrl)) {
            currentUrl = mediaUrl;
            continue;
          }
          return M3u8Rewriter.fail('片源返回的内容不是 M3U8 播放清单', trace);
        }
        if (text.indexOf('#EXT-X-STREAM-INF') < 0) {
          break;
        }
        const variant = M3u8Rewriter.pickVariant(text, currentUrl);
        if (variant === '') {
          break;
        }
        currentUrl = variant;
      }
      if (text === '') {
        return M3u8Rewriter.fail('播放列表为空', trace);
      }
      if (!text.trim().startsWith('#EXTM3U') || text.indexOf('#EXT-X-STREAM-INF') >= 0) {
        return M3u8Rewriter.fail('播放清单跳转层级过多', trace);
      }
      // 2) 重写媒体播放列表
      stage = '分析播放分片';
      const rewritten = await M3u8Rewriter.analyzeMediaPlaylist(text, currentUrl, mode, headers, wanted);
      trace = rewritten.trace;
      if (!wanted()) return M3u8Rewriter.fail('播放解析已取消', trace);
      if (rewritten.segmentCount === 0) {
        return M3u8Rewriter.fail('播放列表中没有可分片的播放地址', trace);
      }
      // 3) 写入沙箱（文件句柄保持打开，供 fd:// 播放）
      stage = '创建播放目录';
      if (!fs.accessSync(outDir)) fs.mkdirSync(outDir, true);
      const localPath = outDir + '/index.m3u8';
      stage = '写入播放清单';
      const file = fs.openSync(localPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      opened = file;
      const encoder = util.TextEncoder.create('utf-8');
      const bytes = encoder.encodeInto(rewritten.content);
      fs.writeSync(file.fd, bytes.buffer as ArrayBuffer);
      return {
        ok: true,
        localPath: localPath,
        file: file,
        segmentCount: rewritten.segmentCount,
        filteredCount: rewritten.filteredCount,
        error: '',
        trace: trace
      };
    } catch (e) {
      if (opened !== null) { try { fs.closeSync(opened.fd); } catch (e) { /* Preserve direct-play fallback. */ } }
      const code = (e as BusinessError).code;
      return M3u8Rewriter.fail('重写播放列表失败: ' + e, trace,
        stage + '失败（错误码 ' + (typeof code === 'number' ? code.toString() : '未知') + '）；已回退原地址播放。');
    }
  }

  private static fail(msg: string, trace: AdFilterTrace, note: string = ''): RewriteOutcome {
    trace.status = 'fallback';
    trace.note = note !== '' ? note : '清单解析或重写未成功，当前使用原地址；未应用任何剔除结果。';
    return { ok: false, localPath: '', file: null, segmentCount: 0, filteredCount: 0, error: msg, trace: trace };
  }

  /** 主播放列表：选 BANDWIDTH 最大的变体 */
  static pickVariant(content: string, baseUrl: string): string {
    const lines = content.split(/\r?\n/);
    let bestUrl = '';
    let bestBw = -1;
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      if (line.startsWith('#EXT-X-STREAM-INF:')) {
        const m = line.match(/BANDWIDTH=(\d+)/);
        const bw = m !== null ? Number(m[1]) : 0;
        for (let j = i + 1; j < lines.length; j++) {
          const u = lines[j].trim();
          if (u !== '' && !u.startsWith('#')) {
            if (bw > bestBw) {
              bestBw = bw;
              bestUrl = Utils.resolveUrl(baseUrl, u);
            }
            break;
          }
        }
      }
    }
    return bestUrl;
  }

  static async analyzeMediaPlaylist(content: string, baseUrl: string, mode: string, headers: Record<string, string>,
    wanted: () => boolean = () => true): Promise<MediaPlaylistResult> {
    let resolution: ResolutionAdResult = { matches: [], note: '' };
    if (mode === 'strict' && wanted()) {
      try { resolution = await AdResolutionRule.inspect(content, baseUrl, headers, wanted); }
      catch (e) { resolution.note = '严格分辨率检查未完成，未增加删片。'; }
    }
    return M3u8Rewriter.rewriteMediaPlaylist(content, baseUrl, mode, resolution);
  }

  static rewriteMediaPlaylist(content: string, baseUrl: string, mode: string,
    resolution: ResolutionAdResult = { matches: [], note: '' }): MediaPlaylistResult {
    const lines = content.split(/\r?\n/);
    const header: string[] = [];
    const segs: Segment[] = [];
    let pending: string[] = [];
    let pendingDur = 0;
    let sawSegment = false;
    let hadEndList = false;
    for (const rawLine of lines) {
      const line = rawLine.trim();
      if (line === '') {
        continue;
      }
      if (line === '#EXTM3U') {
        if (!sawSegment) {
          header.push(line);
        }
        continue;
      }
      if (line.startsWith('#')) {
        if (line.startsWith('#EXTINF:')) {
          const m = line.match(/#EXTINF:\s*([\d.]+)/);
          pendingDur = m !== null ? Number(m[1]) : 0;
          pending.push(line);
        } else if (line.startsWith('#EXT-X-ENDLIST')) {
          hadEndList = true;
        } else if (!sawSegment) {
          header.push(line);
        } else {
          pending.push(line);
        }
        continue;
      }
      segs.push({ tags: pending, uri: line, dur: pendingDur });
      pending = [];
      pendingDur = 0;
      sawSegment = true;
    }

    // 广告过滤
    const dropFlags: boolean[] = [];
    const reasons: string[] = [];
    for (let i = 0; i < segs.length; i++) {
      dropFlags.push(false);
      reasons.push(mode === 'off' ? '过滤已关闭' : '未命中广告路径和当前时长 / 分组规则');
    }
    let filtered = 0;
    if (mode === 'loose' || mode === 'strict') {
      // 分片归属统计：出现最多的 host 视为正片源。不少采集站把广告插成
      // 与正片同长的分片，时长启发式判不出来，但广告分片几乎总是来自
      // 不同的 host 或带广告特征路径 —— 整组 DISCONTINUITY 区间全部
      // 外源 / 命中广告关键词时按广告组丢弃。
      const segHosts: string[] = [];
      const hostCount: Record<string, number> = {};
      for (const s of segs) {
        const h = Utils.hostnameOf(s.uri);
        segHosts.push(h);
        const c = hostCount[h];
        hostCount[h] = (c !== undefined ? c : 0) + 1;
      }
      let mainHost = '';
      let mainCount = 0;
      const hostKeys = Object.keys(hostCount);
      for (const h of hostKeys) {
        if (hostCount[h] > mainCount) {
          mainCount = hostCount[h];
          mainHost = h;
        }
      }
      const isAdUri = (uri: string): boolean => {
        const low = uri.toLowerCase();
        for (const k of M3u8Rewriter.AD_URI_KEYWORDS) {
          if (low.indexOf(k) >= 0) {
            return true;
          }
        }
        return false;
      };

      // 按 DISCONTINUITY 切 run
      const runRanges: number[][] = [];
      let runStart = 0;
      for (let i = 1; i < segs.length; i++) {
        let hasDisc = false;
        for (const t of segs[i].tags) {
          if (t.startsWith('#EXT-X-DISCONTINUITY')) {
            hasDisc = true;
            break;
          }
        }
        if (hasDisc) {
          runRanges.push([runStart, i]);
          runStart = i;
        }
      }
      runRanges.push([runStart, segs.length]);

      if (mode === 'loose') {
        if (runRanges.length > 1) {
          for (const r of runRanges) {
            let allShort = true;
            // host 多样性足够（mainCount>=3）时才启用外源判定，
            // 避免只有两三个分片的小列表误杀正片
            let allForeign = mainCount >= 3;
            let hasAdUri = false;
            for (let i = r[0]; i < r[1]; i++) {
              if (segs[i].dur >= M3u8Rewriter.AD_RUN_MAX_DUR) {
                allShort = false;
              }
              if (segHosts[i] === mainHost) {
                allForeign = false;
              }
              if (isAdUri(segs[i].uri)) {
                hasAdUri = true;
              }
            }
            for (let i = r[0]; i < r[1]; i++) reasons[i] = '未命中广告路径，分组并非全短片段或全异域' +
              (mainCount < 3 ? '；样本不足，未启用异域分组判定' : '');
            if (allShort || allForeign || hasAdUri) {
              const matched: string[] = [];
              if (allShort) matched.push('分组内全部分片不足 5 秒');
              if (allForeign) matched.push('分组全部来自其他域名');
              if (hasAdUri) matched.push('分组含广告路径关键词');
              for (let i = r[0]; i < r[1]; i++) {
                dropFlags[i] = true;
                reasons[i] = matched.join('；');
              }
            }
          }
        } else {
          for (let i = 0; i < segs.length; i++) {
            if (segs[i].dur < M3u8Rewriter.TINY_SEG_DUR || isAdUri(segs[i].uri)) {
              dropFlags[i] = true;
              reasons[i] = isAdUri(segs[i].uri) ? '命中广告路径关键词' : '无分组且时长不足 1 秒';
            } else reasons[i] = '未命中广告路径，且时长不少于 1 秒';
          }
        }
      } else {
        for (let i = 0; i < segs.length; i++) {
          if (segs[i].dur < M3u8Rewriter.AD_SEG_MAX_DUR || isAdUri(segs[i].uri)) {
            dropFlags[i] = true;
            reasons[i] = isAdUri(segs[i].uri) ? '命中广告路径关键词' : '严格规则：时长不足 3 秒';
          } else reasons[i] = '时长不少于 3 秒，未命中广告路径或整组异域规则';
        }
        // strict：整组外源的 DIS 区间也丢
        if (runRanges.length > 1 && mainCount >= 3) {
          for (const r of runRanges) {
            let allForeign = true;
            for (let i = r[0]; i < r[1]; i++) {
              if (segHosts[i] === mainHost) {
                allForeign = false;
                break;
              }
            }
            if (allForeign) {
              for (let i = r[0]; i < r[1]; i++) {
                dropFlags[i] = true;
                reasons[i] = '分组全部来自其他域名';
              }
            }
          }
        }
      }
      if (mode === 'strict') {
        for (const match of resolution.matches) {
          if (!Number.isInteger(match.start) || !Number.isInteger(match.end) || match.start < 0 || match.end > segs.length || match.start >= match.end) continue;
          for (let i = match.start; i < match.end; i++) {
            dropFlags[i] = true;
            reasons[i] = (match.mainSampleRate || 0) > 0 ?
              '严格规则：短时异采样率插播（疑似），主音轨 ' + match.mainSampleRate + ' Hz → ' + match.sampleRate +
                ' Hz，双侧清单边界、异常分片时长、前后各两片恢复主音轨；整个区间已逐片采样确认' :
              '严格规则：短时异分辨率插播（疑似），主样本 ' + match.mainWidth + '×' + match.mainHeight +
                ' → ' + match.width + '×' + match.height + '，前后各两片恢复主尺寸；整个区间已逐片采样确认';
          }
        }
      }
      // 兜底：全丢时保留全部
      let keptCount = 0;
      for (const d of dropFlags) {
        if (!d) {
          keptCount++;
        }
      }
      if (keptCount === 0) {
        for (let i = 0; i < dropFlags.length; i++) {
          dropFlags[i] = false;
          reasons[i] = '保护回退：规则会删光全部分片，已全部保留（' + reasons[i] + '）';
        }
      }
      for (const d of dropFlags) {
        if (d) {
          filtered++;
        }
      }
    }

    // 输出
    const out: string[] = header.slice();
    let lastKey = '';
    let lastMap = '';
    let kept = 0;
    let pendingDiscontinuity = false;
    let skippedSinceKept = false;
    for (let i = 0; i < segs.length; i++) {
      const s = segs[i];
      // 更新加密状态（即使分片被丢弃，后续分片仍沿用其 KEY/MAP）
      for (const t of s.tags) {
        if (t.startsWith('#EXT-X-KEY')) {
          lastKey = t;
        } else if (t.startsWith('#EXT-X-MAP')) {
          lastMap = t;
        }
        if (t === '#EXT-X-DISCONTINUITY') pendingDiscontinuity = true;
      }
      if (dropFlags[i]) {
        if (kept > 0) skippedSinceKept = true;
        continue;
      }
      // Removed media leaves a timestamp gap. Retain an explicit clock boundary even if its tag was dropped.
      if ((pendingDiscontinuity || skippedSinceKept) && s.tags.indexOf('#EXT-X-DISCONTINUITY') < 0) {
        out.push('#EXT-X-DISCONTINUITY');
      }
      let keyEmitted = false;
      let mapEmitted = false;
      for (const t of s.tags) {
        if (t.startsWith('#EXT-X-KEY')) {
          out.push(M3u8Rewriter.rewriteUriAttr(t, baseUrl));
          keyEmitted = true;
        } else if (t.startsWith('#EXT-X-MAP')) {
          out.push(M3u8Rewriter.rewriteUriAttr(t, baseUrl));
          mapEmitted = true;
        } else if (t.startsWith('#EXT-X-DISCONTINUITY')) {
          // Source discontinuities are required for clock changes in every mode, including filtering Off.
          out.push(t);
        } else {
          out.push(t);
        }
      }
      if (!keyEmitted && lastKey !== '') {
        out.push(M3u8Rewriter.rewriteUriAttr(lastKey, baseUrl));
      }
      if (!mapEmitted && lastMap !== '') {
        out.push(M3u8Rewriter.rewriteUriAttr(lastMap, baseUrl));
      }
      out.push(Utils.resolveUrl(baseUrl, s.uri));
      kept++;
      pendingDiscontinuity = false;
      skippedSinceKept = false;
    }
    if (hadEndList) {
      out.push('#EXT-X-ENDLIST');
    }
    const trace = AdDiagnostics.empty(mode, 'rewritten', baseUrl);
    trace.note = mode === 'strict' ? resolution.note : '';
    trace.originalCount = segs.length;
    trace.filteredCount = filtered;
    trace.live = !hadEndList;
    trace.timelineUsable = segs.length > 0 && segs.length <= 20000;
    let sourceMs = 0; let outputMs = 0; let group = 1;
    for (let i = 0; i < Math.min(segs.length, 20000); i++) {
      const segment = segs[i];
      const discontinuity = segment.tags.some((tag: string) => tag === '#EXT-X-DISCONTINUITY');
      if (i > 0 && discontinuity) group++;
      const duration = Number.isFinite(segment.dur) && segment.dur > 0 ? Math.round(segment.dur * 1000) : 0;
      if (duration <= 0) trace.timelineUsable = false;
      const url = AdDiagnostics.safeUrl(Utils.resolveUrl(baseUrl, segment.uri));
      const decision: AdSegmentDecision = { index: i + 1, group: group, durationMs: duration,
        sourceStartMs: sourceMs, startMs: outputMs, endMs: outputMs + (dropFlags[i] ? 0 : duration),
        url: url, host: Utils.hostnameOf(url), discontinuity: discontinuity, dropped: dropFlags[i], reason: reasons[i] };
      trace.segments.push(decision);
      sourceMs += duration;
      if (dropFlags[i]) trace.filteredMs += duration;
      else outputMs += duration;
    }
    return { content: out.join('\n'), segmentCount: kept, filteredCount: filtered, trace: trace };
  }

  /** 重写标签中的 URI="..." 为绝对地址 */
  static rewriteUriAttr(line: string, baseUrl: string): string {
    const marker = 'URI="';
    let result = line;
    let searchFrom = 0;
    for (;;) {
      const idx = result.indexOf(marker, searchFrom);
      if (idx < 0) {
        break;
      }
      const start = idx + marker.length;
      const end = result.indexOf('"', start);
      if (end < 0) {
        break;
      }
      const uri = result.substring(start, end);
      const abs = Utils.resolveUrl(baseUrl, uri);
      result = result.substring(0, start) + abs + result.substring(end);
      searchFrom = start + abs.length;
    }
    return result;
  }
}
