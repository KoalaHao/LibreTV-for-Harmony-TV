import { fileIo as fs } from '@kit.CoreFileKit';

/** Bounded app-private reports; a failed write must never be presented as a saved mark. */
export class AdReportStorage {
  private static directory: string = '';
  private static serial: number = 0;
  private static readonly MAX_REPORTS: number = 20;

  static init(filesDir: string): void {
    try {
      const directory = filesDir + '/ad-diagnostics';
      if (!fs.accessSync(directory)) fs.mkdirSync(directory, true);
      AdReportStorage.directory = directory;
    } catch (e) { AdReportStorage.directory = ''; }
  }

  private static ids(): string[] {
    try {
      const text = fs.readTextSync(AdReportStorage.directory + '/index.json');
      if (text.length > 4096) return [];
      const data = JSON.parse(text) as Object;
      if (!Array.isArray(data)) return [];
      return (data as string[]).filter((id: string) => typeof id === 'string' && /^ad-[a-z0-9]+-[a-z0-9]+$/.test(id));
    } catch (e) { return []; }
  }

  private static write(path: string, text: string): void {
    let fd = -1;
    try {
      const file = fs.openSync(path + '.new', fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE);
      fd = file.fd;
      fs.writeSync(fd, text); fs.closeSync(fd); fd = -1;
      fs.renameSync(path + '.new', path);
    } finally {
      if (fd >= 0) fs.closeSync(fd);
      try { if (fs.accessSync(path + '.new')) fs.unlinkSync(path + '.new'); } catch (e) { /* Best effort cleanup. */ }
    }
  }

  static save(text: string): string {
    if (AdReportStorage.directory === '' || text.length === 0 || text.length > 524288) return '';
    const id = 'ad-' + Date.now().toString(36) + '-' + (++AdReportStorage.serial).toString(36);
    const path = AdReportStorage.directory + '/' + id + '.json';
    try {
      const old = AdReportStorage.ids();
      AdReportStorage.write(path, text);
      const keep = [id].concat(old).slice(0, AdReportStorage.MAX_REPORTS);
      AdReportStorage.write(AdReportStorage.directory + '/index.json', JSON.stringify(keep));
      for (const expired of old.slice(AdReportStorage.MAX_REPORTS - 1)) {
        try { fs.unlinkSync(AdReportStorage.directory + '/' + expired + '.json'); } catch (e) { /* The new record is safe. */ }
      }
      return id;
    } catch (e) {
      try { if (fs.accessSync(path)) fs.unlinkSync(path); } catch (e) { /* No successful-save indication. */ }
      return '';
    }
  }

  static latest(): string {
    if (AdReportStorage.directory === '') return '';
    for (const id of AdReportStorage.ids()) {
      try {
        const path = AdReportStorage.directory + '/' + id + '.json';
        if (fs.statSync(path).size > 2 * 1024 * 1024) continue;
        const text = fs.readTextSync(path);
        const record = JSON.parse(text) as Record<string, Object>;
        if (record['schema'] === 1 && typeof record['positionMs'] === 'number') return text;
      } catch (e) { /* Try the preceding record. */ }
    }
    return '';
  }
}
