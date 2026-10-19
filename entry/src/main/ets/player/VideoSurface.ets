/**
 * 视频画面容器：XComponent(SURFACE) → surfaceId → AVPlayer
 * 对应 LibreTV Web 版 <video> 元素的角色
 */

@Component
export struct VideoSurface {
  private xController: XComponentController = new XComponentController();
  /**
   * 画面宽高（vp）。AVPlayer 会把视频直接渲染到 Surface 上，
   * 若 Surface 尺寸与视频原始比例不一致，画面就会被拉伸 —— 这正是「视频比例被拉扁」的根因。
   * 因此由页面按视频真实宽高比算出显示尺寸后传入；0 表示暂未知，退回铺满。
   */
  @Prop surfaceWidth: number = 0;
  @Prop surfaceHeight: number = 0;
  /** Surface 就绪回调（创建 AVPlayer 后调用） */
  onSurfaceReady: (surfaceId: string) => void = () => {};
  /** 画面被销毁回调（释放 AVPlayer） */
  onSurfaceDestroy: () => void = () => {};

  build() {
    XComponent({
      type: XComponentType.SURFACE,
      controller: this.xController
    })
      .width(this.surfaceWidth > 0 ? this.surfaceWidth : '100%')
      .height(this.surfaceHeight > 0 ? this.surfaceHeight : '100%')
      .backgroundColor(Color.Black)
      .onLoad(() => {
        const surfaceId: string = this.xController.getXComponentSurfaceId();
        this.onSurfaceReady(surfaceId);
      })
      .onDestroy(() => {
        this.onSurfaceDestroy();
      })
  }
}
