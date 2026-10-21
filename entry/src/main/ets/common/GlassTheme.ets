/**
 * 页面级视觉主题（方案 A「通透玻璃」的底）
 *
 * 玻璃要「透」，背后必须有东西可透。纯色底上的玻璃只是一块灰板，
 * 所以所有走玻璃的页面统一铺一层三段渐变：
 *   顶部淡蓝 → 中段回到页面底色 → 底部淡青。
 * 色值全部走资源，深浅主题自动跟随。
 */

export function pageBgGradient(): LinearGradientOptions {
  const colors: Array<[ResourceColor, number]> = [
    [$r('app.color.color_bg_top'), 0],
    [$r('app.color.color_bg'), 0.55],
    [$r('app.color.color_bg_bottom'), 1]
  ];
  return {
    direction: GradientDirection.Bottom,
    colors: colors
  };
}
