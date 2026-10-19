/**
 * 应用入口：初始化本地存储、源管理与下载管理器
 */

import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Store } from '../data/Store';
import { SourceManager } from '../data/SourceManager';
import { DownloadManager } from '../data/DownloadManager';
import { SettingsStore } from '../data/SettingsStore';
import { ScreenKeeper } from '../common/ScreenKeeper';
import { DevicePolicy } from '../common/DevicePolicy';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0001, 'LibreTV', 'EntryAbility onCreate');
    Store.shared().init(this.context);
    // 预热各单例，避免首屏读取竞态
    SourceManager.shared().load();
    DownloadManager.shared().init(this.context);
    // 应用主题：跟随系统 / 固定浅色 / 固定深色
    const mode = SettingsStore.shared().get().themeMode;
    try {
      if (mode === 'light') {
        this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
      } else if (mode === 'dark') {
        this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      } else {
        this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      }
    } catch (e) {
      hilog.error(0x0001, 'LibreTV', 'setColorMode failed');
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(0x0001, 'LibreTV', 'onWindowStageCreate');
    // 不开启窗口全屏布局。
    // 实测结论：开全屏后，Navigation 主内容会被框架按安全区下移到 y=133，
    // 但它 push 出来的 NavDestination 页面却从 y=0 开始排布 —— 两者坐标系不一致，
    // 子页面标题栏必然压到状态栏上（实测 TitleBar 高度被算成 196-133=63px）。
    // 关掉全屏后所有页面统一按安全区排布，谁都不用自己算偏移。
    // 底部那一条只需让 tabBar 用 expandSafeArea 铺满（IndexPage 已做）。
    try {
      const win: window.Window = windowStage.getMainWindowSync();
      // 旋转策略：普通手机锁竖屏，平板/折叠机/宽屏跟随系统（播放页可临时接管）
      DevicePolicy.bind(win);
      win.setWindowLayoutFullScreen(false).catch((e: BusinessError) => {
        hilog.error(0x0001, 'LibreTV', 'setWindowLayoutFullScreen failed: %{public}s',
          e.message ?? 'unknown');
      });
      // 下载期间保持常亮：休眠会冻结应用线程，下载链路直接断在半路
      ScreenKeeper.bind((on: boolean) => {
        win.setWindowKeepScreenOn(on).catch(() => {});
      });
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(0x0001, 'LibreTV', 'getMainWindowSync failed: %{public}s', err.message ?? 'unknown');
    }
    windowStage.loadContent('pages/IndexPage', (err) => {
      if (err) {
        hilog.error(0x0001, 'LibreTV', 'loadContent failed: %{public}s', err.message ?? 'unknown');
      }
    });
  }

  onForeground(): void {
    // 回到前台立刻重挂中断的下载。
    // 后台期间系统会冻结应用线程，HttpRequest 的回调可能再也回不来；
    // 只靠 60s 看门狗太慢，用户看到的就是「进度条一直不动」。
    // 已经在跑的任务会被 active 标记挡掉，重复调用无副作用。
    DownloadManager.shared().resumeInterrupted();
  }

  onWindowStageDestroy(): void {
    hilog.info(0x0001, 'LibreTV', 'onWindowStageDestroy');
  }
}
