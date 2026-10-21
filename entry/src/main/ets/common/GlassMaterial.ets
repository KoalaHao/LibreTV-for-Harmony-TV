/**
 * HarmonyOS 7「沉浸光感」系统材质
 *
 * 系统把"材质"当成一种独立的界面物质：它自己决定背景色、边框、模糊与阴影，
 * 还能在按压时给出形变和光感反馈。我们只需要把材质挂到组件上
 * （CommonMethod.systemMaterial），不用自己调毛玻璃参数。
 *
 * 用法（见首页搜索栏 / 底部导航）：
 *   .systemMaterial(GlassMaterial.supported ? GlassMaterial.thin : undefined)
 *
 * 注意：
 *   1. 设备不支持时（低算力机型、或系统还不是 HarmonyOS 7），material 挂了也不生效，
 *      所以调用方仍要自己给一层半透明底 + 背景模糊作为兜底，视觉上才不会是"裸底"。
 *   2. 应用级开关在 entry/src/main/module.json5 的 metadata：
 *      ohos.arkui.UIMaterial.state = default / enable / disable，
 *      组件级设置优先于应用级开关。
 */

import { uiMaterial } from '@kit.ArkUI';

/** 查询设备是否支持沉浸材质；查询本身失败时按"不支持"处理，避免拖垮页面渲染 */
function checkSupport(): boolean {
  try {
    return uiMaterial.isImmersiveMaterialSupported();
  } catch (e) {
    return false;
  }
}

/**
 * 造一块沉浸材质。
 * - style 决定"厚度"：越薄越透，ULTRA_THIN 几乎只有一层光
 * - interactive 开启按压形变（按下时轻微内凹）
 * - lightEffect 开启光随指动：触点周围泛出一圈光
 * - colorInvert 让材质自动取背景互补色（只有薄到 THIN / ULTRA_THIN 才生效）
 */
function makeMaterial(style: uiMaterial.ImmersiveStyle, interactive: boolean, colorInvert: boolean = false): uiMaterial.Material {
  const light: uiMaterial.LightEffectOptions = { color: Color.White };
  const opt: uiMaterial.ImmersiveOptions = {
    style: style,
    interactive: interactive,
    lightEffect: light,
    applyShadow: true
  };
  if (colorInvert) {
    opt.colorInvert = true;
  }
  return new uiMaterial.ImmersiveMaterial(opt);
}

export class GlassMaterial {
  /** 当前设备是否支持沉浸材质 */
  static readonly supported: boolean = checkSupport();
  /** 薄材质：搜索栏这种小面积悬浮件 */
  static readonly thin: uiMaterial.Material = makeMaterial(uiMaterial.ImmersiveStyle.THIN, true);
  /** 厚材质：底部导航这类大块底板，太薄会被内容干扰、字看不清 */
  static readonly thick: uiMaterial.Material = makeMaterial(uiMaterial.ImmersiveStyle.THICK, false);
  /**
   * 液态玻璃（方案 D）：薄材质 + 自动互补色 + 按压形变 + 光随指动。
   *
   * colorInvert 只在材质薄到 THIN / ULTRA_THIN 时才生效，
   * 所以这里必须用 THIN，不能用 THICK（THICK 下这层效果会被忽略）。
   * 折射边（渐变描边）要自己画，材质本身不提供。
   *
   * 适用范围严格限定在：弹窗、播放页控制条。
   */
  static readonly liquid: uiMaterial.Material = makeMaterial(uiMaterial.ImmersiveStyle.THIN, true, true);
}
