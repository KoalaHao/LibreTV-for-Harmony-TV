import { appTasks } from '@ohos/hvigor-ohos-plugin';

declare const require: (id: string) => any;
declare const process: any;

/**
 * 版本号自动更迭 —— 必须在 hvigor **读取 AppScope/app.json5 之前** 完成。
 *
 * 踩过的坑：最早把它做成一个排在 PreBuild 之前的任务，日志里明明打印
 * 「1.0.6 -> 1.0.7」，磁盘上的 app.json5 也确实是 1.0.7，
 * 但打出来的 HAP 里还是 1.0.6 —— 因为 hvigor 启动阶段就把配置读进内存了，
 * 任务执行时再改文件已经来不及，改的只是一份没人再读的磁盘副本。
 *
 * 所以这里放在模块顶层同步执行：hvigor 一加载本文件就先把版本号改好，
 * 后面所有读 app.json5 的流程（含打包写 module.json）拿到的都是新值。
 *
 * 具体逻辑见 scripts/version.js：
 *   - 对比 entry/src/main 的内容哈希，源码没变就不递增（重复构建不会虚增）
 *   - 同步改 app.json5 的 versionName/versionCode 与两个 oh-package.json5
 */
function bumpVersionBeforeConfigLoad(): void {
  try {
    const fs = require('fs');
    const path = require('path');
    const childProcess = require('child_process');
    const script = path.join(process.cwd(), 'scripts', 'version.js');
    if (!fs.existsSync(script)) {
      console.warn('[version] 未找到 scripts/version.js，跳过自动递增');
      return;
    }
    const output = childProcess.execFileSync(process.execPath, [script], {
      cwd: process.cwd(),
      encoding: 'utf8'
    });
    if (output && output.trim().length > 0) {
      console.log(output.trim());
    }
  } catch (err) {
    // 版本号递增失败只提示，绝不能让整个打包失败
    console.warn('[version] auto bump skipped: ' + (err && err.message ? err.message : err));
  }
}

bumpVersionBeforeConfigLoad();

export default {
  system: appTasks, /* Built-in plugin of Hvigor. The value cannot be changed. */
  plugins: []
}
