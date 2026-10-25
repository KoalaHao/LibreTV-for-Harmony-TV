/**
 * 豆瓣推荐（电影 / 电视剧分类浏览）
 * 与 LibreTV douban.ts 使用同一接口
 */

import { HttpClient } from '../net/HttpClient';
import { RecommendItem } from './Types';

export class DoubanClient {
  static async recommend(type: string, tag: string, pageStart: number, pageSize: number): Promise<RecommendItem[]> {
    const url = 'https://movie.douban.com/j/search_subjects?type=' + type +
      '&tag=' + encodeURIComponent(tag) +
      '&sort=recommend&page_limit=' + pageSize + '&page_start=' + pageStart;
    const res = await HttpClient.getText(url, {
      'User-Agent': HttpClient.UA,
      'Referer': 'https://movie.douban.com/',
      'Accept': 'application/json'
    }, 8000);
    if (!res.ok) {
      return [];
    }
    try {
      const data = JSON.parse(res.text) as Record<string, object>;
      const subjects = data['subjects'];
      if (!Array.isArray(subjects)) {
        return [];
      }
      const items: RecommendItem[] = [];
      for (const entry of subjects as object[]) {
        const s = entry as Record<string, object>;
        const title = DoubanClient.str(s['title']);
        const cover = DoubanClient.str(s['cover']);
        if (title === '' || cover === '') {
          continue;
        }
        const rate = DoubanClient.str(s['rate']);
        items.push({
          id: DoubanClient.str(s['id']),
          title: title,
          cover: cover,
          rating: rate !== '' && rate !== '0' ? rate : undefined,
          isTv: type === 'tv'
        });
      }
      return items;
    } catch (e) {
      return [];
    }
  }

  /**
   * 按「分类 + 类型 + 地区 + 排序」浏览。
   *
   * 与 recommend() 走的是两个不同接口：
   *   · recommend  -> j/search_subjects    只支持 tag 白名单，无法组合筛选
   *   · browse     -> j/new_search_subjects 支持 tags / genres / countries / sort
   *
   * 参数含义（均已实测）：
   *   tags     电影 / 电视剧 / 综艺 / 纪录片 / 动漫
   *   genres   剧情 / 喜剧 / 动作 / 爱情 / 科幻 / 动画 / 悬疑 …  空串表示不限
   *   countries 中国大陆 / 美国 / 中国香港 / 日本 / 韩国 …        空串表示不限
   *   sort     T=标记最多(综合)  R=最近上映(发行时间从近到远)  S=评分从高到低
   *   range    评分区间，'0,10' 表示不限；带下限会滤掉无评分条目
   *   start    偏移量，每页固定返回 20 条
   *
   * 注意 1：sort=R 的头部是一批「刚建条目、还没人打分」的新片 —— 占位标题、
   *   网络短剧、维密秀录像之类，rate 为空。直接展示会让人以为接口坏了，
   *   所以 R 先按 range=5,10 取；若过滤后一条不剩再退回 range=0,10 兜底，
   *   保证「最新」永远有内容可显示。
   * 注意 2：该接口偶发返回空 data（疑似频控），调用方必须准备回退方案。
   */
  static async browse(tags: string, genre: string, country: string, sort: string,
    start: number, yearRange: string = ''): Promise<RecommendItem[]> {
    const ranges: string[] = sort === 'R' ? ['5,10', '0,10'] : ['0,10'];
    for (const range of ranges) {
      const got: RecommendItem[] =
        await DoubanClient.browseOnce(tags, genre, country, sort, range, start, yearRange);
      if (got.length > 0) {
        return got;
      }
    }
    return [];
  }

  /** browse() 的单次请求实现，range 由调用方决定 */
  private static async browseOnce(tags: string, genre: string, country: string, sort: string,
    range: string, start: number, yearRange: string): Promise<RecommendItem[]> {
    let url: string = 'https://movie.douban.com/j/new_search_subjects?sort=' + sort +
      '&range=' + range + '&start=' + start + '&tags=' + encodeURIComponent(tags);
    if (genre !== '') {
      url += '&genres=' + encodeURIComponent(genre);
    }
    if (country !== '') {
      url += '&countries=' + encodeURIComponent(country);
    }
    if (yearRange !== '') {
      url += '&year_range=' + encodeURIComponent(yearRange);
    }
    const res = await HttpClient.getText(url, {
      'User-Agent': HttpClient.UA,
      'Referer': 'https://movie.douban.com/',
      'Accept': 'application/json'
    }, 8000);
    if (!res.ok) {
      return [];
    }
    try {
      const data = JSON.parse(res.text) as Record<string, object>;
      const subjects = data['data'];
      if (!Array.isArray(subjects)) {
        return [];
      }
      const items: RecommendItem[] = [];
      for (const entry of subjects as object[]) {
        const s = entry as Record<string, object>;
        const title = DoubanClient.str(s['title']);
        const cover = DoubanClient.str(s['cover']);
        if (title === '' || cover === '') {
          continue;
        }
        const rate = DoubanClient.str(s['rate']);
        items.push({
          id: DoubanClient.str(s['id']),
          title: title,
          cover: cover,
          rating: rate !== '' && rate !== '0' ? rate : undefined,
          isTv: tags === '电视剧'
        });
      }
      return items;
    } catch (e) {
      return [];
    }
  }

  /**
   * 豆瓣电影 Top 250 排行榜。
   * 榜单没有官方 JSON 接口，解析 HTML 榜单页；每页固定 25 条，start 为 25 的倍数。
   * 页面被反爬拦截时返回空数组，由调用方兜底。
   */
  static async top250(start: number): Promise<RecommendItem[]> {
    const url = 'https://movie.douban.com/top250?start=' + start;
    const res = await HttpClient.getText(url, {
      'User-Agent': HttpClient.UA,
      'Referer': 'https://movie.douban.com/',
      'Accept': 'text/html,application/xhtml+xml'
    }, 10000);
    if (!res.ok || res.text === '') {
      return [];
    }
    const html = res.text;
    const items: RecommendItem[] = [];
    const chunks = html.split('<div class="item">');
    for (let i = 1; i < chunks.length; i++) {
      const block = chunks[i];
      const idM = block.match(/subject\/(\d+)\//);
      const titleM = block.match(/<span property="v:itemreviewed">([^<]+)<\/span>/);
      const imgM = block.match(/<img src="([^"]+)"/);
      const rateM = block.match(/<span class="rating_num"[^>]*>([\d.]+)<\/span>/);
      if (titleM === null || imgM === null) {
        continue;
      }
      const rate = rateM !== null ? rateM[1] : '';
      items.push({
        id: idM !== null ? idM[1] : 'top250_' + (start + i),
        title: titleM[1].trim(),
        cover: imgM[1],
        rating: rate !== '' && rate !== '0' ? rate : undefined,
        isTv: false
      });
    }
    return items;
  }

  private static str(v: object): string {
    return typeof v === 'string' ? v : '';
  }
}
