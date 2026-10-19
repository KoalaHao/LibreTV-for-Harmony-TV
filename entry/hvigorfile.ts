import { hapTasks } from '@ohos/hvigor-ohos-plugin';

declare const require: (id: string) => any;
declare const process: any;

/**
 * 打包前自动更迭版本号。
 *
 * 逻辑全在 scripts/version.js：源码（entry/src/main）有改动才 +0.01，
 * 没改就保持原版本，避免反复构建把版本号刷上去。
 *
 * 这里只负责「在 PreBuild 之前跑一下那个脚本」，并且**任何异常都吞掉**：
 * 版本号递增失败顶多是版本没变，绝不能让整个打包失败。
 */
function versionBumpPlugin(): any {
  return {
    pluginId: 'libretv-version-bump',
    apply(node: any) {
      try {
        node.registerTask({
          name: 'BumpVersion',
          // 本模块的任务名形如 default@PreBuild（日志里显示为 :entry:default@PreBuild）
          postDependencies: ['default@PreBuild'],
          run() {
            try {
              const path = require('path');
              const childProcess = require('child_process');
              const root = path.resolve(node.getNodePath(), '..');
              const script = path.join(root, 'scripts', 'version.js');
              const output = childProcess.execFileSync(process.execPath, [script], {
                cwd: root,
                encoding: 'utf8',
              });
              if (output && output.trim().length > 0) {
                console.log(output.trim());
              }
            } catch (err) {
              console.warn('[version] auto bump skipped: ' + (err && err.message ? err.message : err));
            }
          },
        });
      } catch (e) {
        console.warn('[version] cannot register bump task: ' + (e && e.message ? e.message : e));
      }
    },
  };
}

export default {
  system: hapTasks, /* Built-in plugin of Hvigor. It cannot be modified. */
  plugins: [versionBumpPlugin()] /* 打包前自动 +0.01，见 scripts/version.js */
}
