import { fileIo as fs } from '@kit.CoreFileKit';

/** App-private files keep large multi-source results out of Preferences' per-value limit. */
export class SearchCacheStorage {
  private static directory: string = '';

  static init(filesDir: string): void {
    try {
      const directory = filesDir + '/discovery-search';
      if (!fs.accessSync(directory)) fs.mkdirSync(directory, true);
      SearchCacheStorage.directory = directory;
    } catch (e) { SearchCacheStorage.directory = ''; }
  }

  static read(key: string): string {
    if (SearchCacheStorage.directory === '' || !/^[a-z0-9-]{2,40}$/.test(key)) return '';
    try {
      const path = SearchCacheStorage.directory + '/' + key + '.json';
      if (fs.statSync(path).size > 4 * 1024 * 1024) return '';
      return fs.readTextSync(path);
    } catch (e) { return ''; }
  }

  static write(key: string, text: string): void {
    if (SearchCacheStorage.directory === '' || !/^[a-z0-9-]{2,40}$/.test(key) || text.length > 2000000) return;
    let fd = -1;
    try {
      const path = SearchCacheStorage.directory + '/' + key + '.json';
      const file = fs.openSync(path + '.new', fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE);
      fd = file.fd;
      fs.writeSync(fd, text);
      fs.closeSync(fd); fd = -1;
      fs.renameSync(path + '.new', path);
    } catch (e) { /* Existing cache remains available when writing fails. */ }
    finally { if (fd >= 0) fs.closeSync(fd); }
  }
}
