/**
 * 系统栏占位尺寸（vp）。
 *
 * 为什么要有这个东西：
 * 应用要让内容「铺满整屏 + 顶部/底部安全区用模糊过渡」，状态栏和手势条那两条
 * 就必须由页面自己让位 —— 框架只保证窗口本身是全屏的，具体让多少得问系统。
 * EntryAbility 在窗口创建后把实测值写进来，页面读它来做内边距，
 * 避免每个页面各写一个魔数（换机器/换分辨率立刻错位）。
 *
 * 注意：这是普通静态字段而不是 @State —— 它在首帧之前就已经写好，
 * 页面读取时不需要响应式更新；写成状态反而会在启动阶段触发一次无谓重排。
 */
export class SystemInsets {
  /** 状态栏高度（vp）。取不到时给一个保守值，宁可多留一点也不压字 */
  private static topVp: number = 38;
  /** 底部手势条高度（vp）。默认按常见值给 28，量不到时也不至于把胶囊压进手势区 */
  private static bottomVp: number = 28;

  /**
   * 写入实测值。只接受「合理区间」内的数字：
   * 窗口刚创建时 avoidArea 可能返回 0 或半个值（实测出现过 8vp），
   * 照单全收会把搜索栏顶进状态栏里，比不更新更糟。
   */
  static set(topVp: number, bottomVp: number): void {
    if (topVp >= 20 && topVp <= 80) {
      SystemInsets.topVp = topVp;
    }
    if (bottomVp >= 8 && bottomVp <= 60) {
      SystemInsets.bottomVp = bottomVp;
    }
  }

  static top(): number {
    return SystemInsets.topVp;
  }

  static bottom(): number {
    return SystemInsets.bottomVp;
  }
}
