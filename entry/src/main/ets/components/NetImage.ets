/**
 * 网络图片组件
 *
 * 通过 HttpClient 携带 Referer / UA 等请求头下载图片字节，再解码为 PixelMap 显示，并做内存缓存。
 * 用于豆瓣等对 Referer 有校验的图床：ArkUI 的 Image(url) 无法设置请求头，
 * 直接加载豆瓣海报会被返回 HTTP 418（空图），表现为「推荐有标题但封面空白」。
 */

import { image } from '@kit.ImageKit';
import { HttpClient } from '../net/HttpClient';

/** 简单的 PixelMap 内存缓存（按原始 URL 去重） */
class NetImageCache {
  private static readonly map: Map<string, image.PixelMap> = new Map<string, image.PixelMap>();
  private static readonly MAX: number = 240;

  static get(url: string): image.PixelMap | undefined {
    return NetImageCache.map.get(url);
  }

  static put(url: string, pm: image.PixelMap): void {
    if (NetImageCache.map.size >= NetImageCache.MAX) {
      NetImageCache.map.clear();
    }
    NetImageCache.map.set(url, pm);
  }
}

/** 按图片域名推断所需 Referer */
function refererFor(url: string): string {
  if (url.indexOf('doubanio.com') >= 0 || url.indexOf('douban.com') >= 0) {
    return 'https://movie.douban.com/';
  }
  return '';
}

@Component
export struct NetImage {
  @Prop url: string = '';
  @Prop referer: string = '';
  @State pm: image.PixelMap | undefined = undefined;

  aboutToAppear(): void {
    this.loadImage();
  }

  /** 供外部在 URL 变化时刷新（父组件用 key 重建即可） */
  private async loadImage(): Promise<void> {
    const u = this.url;
    if (u === '') {
      return;
    }
    const cached = NetImageCache.get(u);
    if (cached !== undefined) {
      this.pm = cached;
      return;
    }
    const headers: Record<string, string> = { 'User-Agent': HttpClient.UA };
    const ref = this.referer !== '' ? this.referer : refererFor(u);
    if (ref !== '') {
      headers['Referer'] = ref;
    }
    const res = await HttpClient.getBytes(u, headers, 12000);
    if (!res.ok || res.bytes.length === 0) {
      return;
    }
    try {
      const buf: ArrayBuffer = res.bytes.buffer as ArrayBuffer;
      const src = image.createImageSource(buf);
      // DecodingOptions 仅支持 desiredSize（Size{width,height}），无 desiredPixelWidth/Height
      const target: image.Size = { width: 480, height: 720 };
      const opts: image.DecodingOptions = { desiredSize: target };
      const pm = await src.createPixelMap(opts);
      await src.release();
      NetImageCache.put(u, pm);
      this.pm = pm;
    } catch (e) {
      // 解码失败：保持占位底色
    }
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.color_chip_bg'))
      if (this.pm !== undefined) {
        Image(this.pm)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .interpolation(ImageInterpolation.Medium)
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
  }
}
