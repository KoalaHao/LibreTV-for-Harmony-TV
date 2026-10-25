/**
 * 应用显示名。
 *
 * 显示名来自 app.string.brand_name；TV fork 的资源默认值为 LibreTV for Harmony TV。
 * hvigor 不自动覆盖资源或递增版本，品牌与版本改动应明确提交。
 *
 * 只有拿不到 UIContext 的地方才需要它（Text($r('app.string.brand_name')) 直接就能用）；
 * 目前用在 AVSession 的兜底标题和源列表导出名这类「必须是字符串」的位置。
 */

import { UIContext } from '@kit.ArkUI';

export class Brand {
  private static cache: string = '';

  static displayName(ui: UIContext): string {
    if (Brand.cache !== '') {
      return Brand.cache;
    }
    try {
      const ctx = ui.getHostContext();
      if (ctx !== undefined) {
        // 按资源名取，不用 $r：$r 只能在声明式 UI 里用
        Brand.cache = ctx.resourceManager.getStringByNameSync('brand_name');
      }
    } catch (e) {
      Brand.cache = '';
    }
    return Brand.cache;
  }

  /** 切换品牌后缓存会过期，构建产物每次都是新的进程，正常用不到这个方法 */
  static reset(): void {
    Brand.cache = '';
  }
}
