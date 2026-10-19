/**
 * 本地回环 HTTP 服务：把沙箱里的离线视频喂给 AVPlayer。
 *
 * 为什么必须这样：
 *  - HLS 播放列表里引用沙箱分片（file:// 与裸绝对路径都试过）→ 5400103 IO Error；
 *  - fd://  交给播放器，没有文件名/扩展名 → 5400106 CONTAINER_ERR 认不出容器；
 *  - file:// 直接给路径 → 连初始化都过不去（播放器进程访问不到应用沙箱）。
 * 播放器唯一稳定能读的就是 http(s)，所以起一个只听 127.0.0.1 的小服务，
 * 把整文件按 Range 请求喂出去。
 */

import { socket } from '@kit.NetworkKit';
import { fileIo as fs } from '@kit.CoreFileKit';

export class LocalHttpServer {
  private static inst: LocalHttpServer | null = null;
  private server: socket.TCPSocketServer | null = null;
  private port: number = 0;
  private file: string = '';

  static shared(): LocalHttpServer {
    if (!LocalHttpServer.inst) {
      LocalHttpServer.inst = new LocalHttpServer();
    }
    return LocalHttpServer.inst;
  }

  /** 启动（或复用）服务，返回可交给播放器的地址；失败返回空串 */
  async mediaUrl(filePath: string): Promise<string> {
    if (this.server !== null && this.file === filePath && this.port > 0) {
      return 'http://127.0.0.1:' + this.port + '/media.ts';
    }
    await this.stop();
    this.file = filePath;
    for (let p = 18211; p <= 18221; p++) {
      const srv = socket.constructTCPSocketServerInstance();
      try {
        await srv.listen({ address: '127.0.0.1', port: p, family: 1 });
      } catch (e) {
        continue;
      }
      this.server = srv;
      this.port = p;
      srv.on('connect', (client: socket.TCPSocketConnection) => {
        this.handle(client);
      });
      return 'http://127.0.0.1:' + p + '/media.ts';
    }
    return '';
  }

  async stop(): Promise<void> {
    const srv = this.server;
    this.server = null;
    this.port = 0;
    if (srv !== null) {
      try {
        srv.close();
      } catch (e) {
        // 忽略
      }
    }
  }

  /** 收到连接后逐块收请求头，凑够 \r\n\r\n 就回响应 */
  private handle(client: socket.TCPSocketConnection): void {
    let buf = new Uint8Array(0);
    let answered = false;
    client.on('message', (info: socket.SocketMessageInfo) => {
      if (answered) {
        return;
      }
      const chunk = new Uint8Array(info.message);
      if (buf.length + chunk.length > 32768) {
        answered = true;
        client.close();
        return;
      }
      const merged = new Uint8Array(buf.length + chunk.length);
      merged.set(buf, 0);
      merged.set(chunk, buf.length);
      buf = merged;
      const head = LocalHttpServer.headText(buf);
      if (head.indexOf('\r\n\r\n') < 0) {
        return;
      }
      answered = true;
      this.respond(client, head);
    });
  }

  /** 只解 ASCII 请求头（不依赖 TextDecoder，够用且没有 API 版本差异） */
  private static headText(buf: Uint8Array): string {
    let out = '';
    for (let i = 0; i < buf.length; i++) {
      const c = buf[i];
      if (c === 0) {
        break;
      }
      out += String.fromCharCode(c);
    }
    return out;
  }

  private async respond(client: socket.TCPSocketConnection, head: string): Promise<void> {
    const lines: string[] = head.split('\r\n');
    let start: number = -1;
    let end: number = -1;
    for (const h of lines) {
      const lower: string = h.toLowerCase();
      if (lower.startsWith('range:')) {
        const v: string = h.substring(6).trim();
        const eq: number = v.indexOf('=');
        const spec: string = eq >= 0 ? v.substring(eq + 1) : v;
        const dash: number = spec.indexOf('-');
        if (dash >= 0) {
          const s: string = spec.substring(0, dash);
          const e: string = spec.substring(dash + 1);
          start = s !== '' ? Number.parseInt(s, 10) : 0;
          end = e !== '' ? Number.parseInt(e, 10) : -1;
        }
      }
    }
    let size: number = 0;
    try {
      size = fs.statSync(this.file).size;
    } catch (e) {
      size = 0;
    }
    if (size <= 0) {
      await this.writeAll(client, LocalHttpServer.ascii(
        'HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n'));
      try {
        client.close();
      } catch (e) {
        // 忽略
      }
      return;
    }
    const from: number = start >= 0 ? start : 0;
    let to: number = end >= 0 ? end : size - 1;
    if (to > size - 1) {
      to = size - 1;
    }
    const len: number = to - from + 1;
    let header: string = '';
    if (start >= 0) {
      header = 'HTTP/1.1 206 Partial Content\r\nContent-Type: video/mp2t\r\nContent-Length: ' +
        len.toString() + '\r\nContent-Range: bytes ' + from.toString() + '-' + to.toString() +
        '/' + size.toString() + '\r\nAccept-Ranges: bytes\r\nConnection: close\r\n\r\n';
    } else {
      header = 'HTTP/1.1 200 OK\r\nContent-Type: video/mp2t\r\nContent-Length: ' +
        len.toString() + '\r\nAccept-Ranges: bytes\r\nConnection: close\r\n\r\n';
    }
    await this.writeAll(client, LocalHttpServer.ascii(header));

    let f: fs.File | null = null;
    try {
      f = fs.openSync(this.file, fs.OpenMode.READ_ONLY);
      const fd: number = f.fd;
      const chunk: number = 256 * 1024;
      let off: number = from;
      while (off <= to) {
        const n: number = Math.min(chunk, to - off + 1);
        const buf: ArrayBuffer = new ArrayBuffer(n);
        const read: number = fs.readSync(fd, buf, { offset: off, length: n });
        if (read <= 0) {
          break;
        }
        await this.writeAll(client, buf);
        off += read;
      }
    } catch (e) {
      // 读失败就让客户端断开
    } finally {
      if (f !== null) {
        fs.closeSync(f);
      }
    }
    try {
      client.close();
    } catch (e) {
      // 忽略
    }
  }

  private writeAll(client: socket.TCPSocketConnection, data: ArrayBuffer): Promise<void> {
    return new Promise<void>((resolve: (value: void) => void) => {
      client.send({ data: data }).then(() => {
        resolve();
      }).catch(() => {
        resolve();
      });
    });
  }

  private static ascii(text: string): ArrayBuffer {
    const buf = new Uint8Array(text.length);
    for (let i = 0; i < text.length; i++) {
      buf[i] = text.charCodeAt(i) & 0xFF;
    }
    return buf.buffer as ArrayBuffer;
  }
}
