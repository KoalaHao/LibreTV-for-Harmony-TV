export interface PosterStaticInfo {
  subjectId: string;
  isSeries: boolean;
  countries: string[];
  genres: string[];
  releaseDate: string;
  durationMinutes: number;
  totalEpisodes: number;
  directors: string[];
  actors: string[];
  description: string;
  originalTitle: string;
  detailsLoaded: boolean;
}

export interface PosterCardInfo extends PosterStaticInfo {
  /** True only for a fresh full-detail response, never for cache/abstract data. */
  liveMetadata: boolean;
  /** -1 means unavailable; zero is a known count, never a missing-data fallback. */
  shortComments: number;
  rating: string;
}

export class PosterCardData {
  /** Persist only stable catalogue fields, never scores or short-comment counts. */
  static stable(info: PosterStaticInfo): PosterStaticInfo {
    return { subjectId: info.subjectId, isSeries: info.isSeries, countries: info.countries.slice(),
      genres: info.genres.slice(), releaseDate: info.releaseDate, durationMinutes: info.durationMinutes,
      totalEpisodes: info.totalEpisodes, directors: info.directors.slice(), actors: info.actors.slice(),
      description: info.description, originalTitle: info.originalTitle, detailsLoaded: info.detailsLoaded };
  }

  static fromStatic(info: PosterStaticInfo): PosterCardInfo {
    return { subjectId: info.subjectId, isSeries: info.isSeries, countries: info.countries.slice(),
      genres: info.genres.slice(), releaseDate: info.releaseDate, durationMinutes: info.durationMinutes,
      totalEpisodes: info.totalEpisodes, directors: info.directors.slice(), actors: info.actors.slice(),
      description: info.description, originalTitle: info.originalTitle, detailsLoaded: info.detailsLoaded,
      liveMetadata: false, shortComments: -1, rating: '' };
  }

  static empty(subjectId: string = '', isSeries: boolean = false): PosterCardInfo {
    return { subjectId: subjectId, isSeries: isSeries, countries: [], genres: [], releaseDate: '',
      durationMinutes: 0, totalEpisodes: 0, directors: [], actors: [], description: '', originalTitle: '',
      detailsLoaded: false, liveMetadata: false, shortComments: -1, rating: '' };
  }

  private static text(value: Object): string {
    return typeof value === 'string' ? value.trim().substring(0, 100) : '';
  }

  private static texts(value: Object): string[] {
    if (!Array.isArray(value)) return [];
    const values: string[] = [];
    for (const entry of value as Object[]) {
      const text = PosterCardData.text(entry);
      if (text !== '' && values.indexOf(text) < 0) values.push(text);
      if (values.length >= 12) break;
    }
    return values;
  }

  private static integer(value: Object, unknown: number = 0, maximum: number = 1000000000): number {
    let number = -1;
    if (typeof value === 'number') number = value;
    else if (typeof value === 'string' && /^\d+$/.test(value)) number = Number(value);
    return Number.isFinite(number) && Number.isInteger(number) && number >= 0 && number <= maximum ? number : unknown;
  }

  private static people(value: Object): string[] {
    if (!Array.isArray(value)) return [];
    const names: string[] = [];
    for (const person of value as Object[]) {
      if (person === null || typeof person !== 'object') continue;
      const name = PosterCardData.text((person as Record<string, Object>)['name']);
      if (name !== '' && names.indexOf(name) < 0) names.push(name);
      if (names.length >= 12) break;
    }
    return names;
  }

  static dateText(value: string): string {
    const match = value.match(/\b((?:18|19|20|21)\d{2})-(\d{2})-(\d{2})/);
    if (match !== null) {
      const year = Number(match[1]); const month = Number(match[2]); const day = Number(match[3]);
      const date = new Date(Date.UTC(year, month - 1, day));
      if (date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day) {
        return match[1] + '.' + match[2] + '.' + match[3];
      }
      return '';
    }
    return /^(?:18|19|20|21)\d{2}$/.test(value) ? value : '';
  }

  static duration(value: string): number {
    const hours = value.match(/(\d+)\s*小时/);
    const minutes = value.match(/(\d+)\s*(?:分钟|分|minutes?|mins?)/i);
    const total = (hours !== null ? Number(hours[1]) * 60 : 0) + (minutes !== null ? Number(minutes[1]) : 0);
    return total > 0 && total <= 24000 ? total : 0;
  }

  static parse(text: string, subjectId: string, seriesHint: boolean = false): PosterCardInfo | null {
    if (!/^\d{7,10}$/.test(subjectId) || text.length > 200000) return null;
    try {
      const data = JSON.parse(text) as Record<string, Object>;
      if (PosterCardData.text(data['id']) !== subjectId) return null;
      const result = PosterCardData.empty(subjectId, seriesHint);
      result.liveMetadata = true;
      result.detailsLoaded = true;
      result.directors = PosterCardData.people(data['directors']);
      result.actors = PosterCardData.people(data['actors']);
      result.description = typeof data['intro'] === 'string' ? (data['intro'] as string).trim().substring(0, 2400) : '';
      result.originalTitle = PosterCardData.text(data['original_title']);
      if (typeof data['is_tv'] === 'boolean') result.isSeries = data['is_tv'] as boolean;
      else if (data['type'] === 'tv' || data['subtype'] === 'TV' || data['subtype'] === 'tv') result.isSeries = true;
      else if (data['type'] === 'movie' || data['subtype'] === 'movie') result.isSeries = false;
      result.countries = PosterCardData.texts(data['countries']);
      result.genres = PosterCardData.texts(data['genres']);
      const dates = PosterCardData.texts(data['pubdate']);
      const domestic = dates.find((date: string) => date.indexOf('中国大陆') >= 0);
      if (domestic !== undefined) result.releaseDate = PosterCardData.dateText(domestic);
      for (const date of dates) {
        if (result.releaseDate === '') result.releaseDate = PosterCardData.dateText(date);
      }
      if (result.releaseDate === '') result.releaseDate = PosterCardData.dateText(PosterCardData.text(data['year']));
      const durations = PosterCardData.texts(data['durations']);
      if (durations.length > 0) result.durationMinutes = PosterCardData.duration(durations[0]);
      result.totalEpisodes = PosterCardData.integer(data['episodes_count'], 0, 10000);
      // rating.count and review_count are different counters. Neither substitutes for short comments.
      result.shortComments = PosterCardData.integer(data['comment_count'], -1);
      const rating = data['rating'];
      if (rating !== null && typeof rating === 'object' && !Array.isArray(rating)) {
        const value = (rating as Record<string, Object>)['value'];
        if (typeof value === 'number' && Number.isFinite(value) && value > 0 && value <= 10) result.rating = value.toFixed(1);
      }
      return result;
    } catch (e) { return null; }
  }

  static parseAbstract(text: string, subjectId: string): PosterCardInfo | null {
    if (!/^\d{7,10}$/.test(subjectId) || text.length > 200000) return null;
    try {
      const data = JSON.parse(text) as Record<string, Object>;
      if (data['r'] !== 0 || data['subject'] === null || typeof data['subject'] !== 'object') return null;
      const subject = data['subject'] as Record<string, Object>;
      if (subject['id'] !== subjectId) return null;
      const info = PosterCardData.empty(subjectId, subject['is_tv'] === true);
      info.countries = PosterCardData.text(subject['region']).split('/').map((s: string) => s.trim()).filter((s: string) => s !== '');
      info.genres = PosterCardData.texts(subject['types']);
      info.releaseDate = PosterCardData.dateText(PosterCardData.text(subject['release_year']));
      info.durationMinutes = PosterCardData.duration(PosterCardData.text(subject['duration']));
      info.totalEpisodes = PosterCardData.integer(subject['episodes_count'], 0, 10000);
      // The abstract's rate and star are deliberately ignored; it has no short-comment total.
      return info;
    } catch (e) { return null; }
  }

  static isRateLimited(status: number, text: string): boolean {
    if (status === 401 || status === 403 || status === 429) return true;
    if (status !== 400 || text.length > 8000) return false;
    try {
      const data = JSON.parse(text) as Record<string, Object>;
      return data['code'] === 1309 || data['msg'] === 'subject_ip_rate_limit';
    } catch (e) { return false; }
  }

  static restore(text: string, subjectId: string): PosterCardInfo | null {
    try {
      const data = JSON.parse(text) as Record<string, Object>;
      if (data['subjectId'] !== subjectId) return null;
      const info = PosterCardData.empty(subjectId, data['isSeries'] === true);
      info.countries = PosterCardData.texts(data['countries']);
      info.genres = PosterCardData.texts(data['genres']);
      info.releaseDate = PosterCardData.dateText(PosterCardData.text(data['releaseDate']).replace(/\./g, '-'));
      info.durationMinutes = PosterCardData.integer(data['durationMinutes'], 0, 24000);
      info.totalEpisodes = PosterCardData.integer(data['totalEpisodes'], 0, 10000);
      info.directors = PosterCardData.texts(data['directors']);
      info.actors = PosterCardData.texts(data['actors']);
      info.description = typeof data['description'] === 'string' ? (data['description'] as string).substring(0, 2400) : '';
      info.originalTitle = PosterCardData.text(data['originalTitle']);
      info.detailsLoaded = data['detailsLoaded'] === true;
      return info;
    } catch (e) { return null; }
  }

  static footerRight(info: PosterCardInfo): string {
    if (info.isSeries) return info.totalEpisodes > 0 ? info.totalEpisodes.toString() + '集' : '剧集';
    return info.durationMinutes > 0 ? info.durationMinutes.toString() + '分钟' : '电影';
  }

  static heatTier(count: number): number {
    if (!Number.isInteger(count) || count < 0) return -1;
    if (count < 1000) return 0;
    if (count < 10000) return 1;
    if (count < 50000) return 2;
    if (count < 200000) return 3;
    return 4;
  }

  static heatLabel(count: number): string {
    const tier = PosterCardData.heatTier(count);
    return tier < 0 ? '热度未评级' : ['冷门', '关注', '热门', '大热', '现象级'][tier] + '，' + count.toString() + '条短评';
  }

  /** The first listed production region tints the separate footer with a quiet dark colour. */
  static footerColor(countries: string[]): string {
    const colors: Record<string, string> = {
      'cn': '#61383B', 'hk': '#61383B', 'mo': '#61383B', 'tw': '#554767',
      'kr': '#3C5964', 'jp': '#695265', 'us': '#385267', 'gb': '#51446A',
      'fr': '#3F4F69', 'de': '#5D523E', 'it': '#3D5B4D', 'es': '#64503D',
      'ca': '#63444B', 'au': '#3B5661', 'in': '#65513D', 'th': '#51435F',
      'ru': '#444F66', 'se': '#3E5863', 'no': '#61464F', 'dk': '#61434A',
      'fi': '#405969', 'nl': '#664C3D', 'be': '#5F553E', 'ch': '#65434B',
      'at': '#60474C', 'nz': '#3B5860', 'br': '#4A5D3F', 'mx': '#3F5E4E',
      'ar': '#45616A', 'za': '#405D50', 'ir': '#505C43', 'tr': '#62414C',
      'sg': '#62494E', 'my': '#59533D', 'id': '#63494B', 'ph': '#484F68',
      'vn': '#63523D'
    };
    const code = countries.length > 0 ? PosterCardData.regionCode(countries[0]) : '';
    return colors[code] !== undefined ? colors[code] : '#363940';
  }

  static regionCode(region: string): string {
    const codes: Record<string, string> = {
      '中国大陆': 'cn', '中国': 'cn', '中国香港': 'hk', '香港': 'hk', '中国澳门': 'mo', '澳门': 'mo',
      '中国台湾': 'tw', '台湾': 'tw', '美国': 'us', '英国': 'gb', '日本': 'jp', '韩国': 'kr',
      '法国': 'fr', '德国': 'de', '意大利': 'it', '西班牙': 'es', '加拿大': 'ca', '澳大利亚': 'au',
      '印度': 'in', '泰国': 'th', '俄罗斯': 'ru', '瑞典': 'se', '挪威': 'no', '丹麦': 'dk',
      '芬兰': 'fi', '荷兰': 'nl', '比利时': 'be', '瑞士': 'ch', '奥地利': 'at', '新西兰': 'nz',
      '巴西': 'br', '墨西哥': 'mx', '阿根廷': 'ar', '南非': 'za', '伊朗': 'ir', '土耳其': 'tr',
      '新加坡': 'sg', '马来西亚': 'my', '印度尼西亚': 'id', '菲律宾': 'ph', '越南': 'vn'
    };
    return codes[region] !== undefined ? codes[region] : '';
  }
}
