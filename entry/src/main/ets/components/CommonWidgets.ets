/**
 * 通用 UI 组件：加载态 / 空态 / 视频卡片 / 设置行 / 分组标题 / 标签
 */

import { NetImage } from './NetImage';

@Component
export struct LoadingView {
  @Prop tipText: string = '加载中…';

  build() {
    Column({ space: 12 }) {
      LoadingProgress()
        .width(32)
        .height(32)
        .color($r('app.color.color_primary'))
      Text(this.tipText)
        .fontSize(13)
        .fontColor($r('app.color.color_text_secondary'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}

@Component
export struct EmptyView {
  @Prop emptyText: string = '暂无内容';
  @Prop emptyIcon: string = '';

  build() {
    Column({ space: 12 }) {
      if (this.emptyIcon !== '') {
        Image(this.emptyIcon)
          .width(56)
          .height(56)
          .opacity(0.35)
      } else {
        Text('◌')
          .fontSize(48)
          .fontColor($r('app.color.color_text_secondary'))
          .opacity(0.4)
      }
      Text(this.emptyText)
        .fontSize(14)
        .fontColor($r('app.color.color_text_secondary'))
    }
    .width('100%')
    .padding(32)
    .justifyContent(FlexAlign.Center)
  }
}

@Component
export struct SectionHeader {
  @Prop headerText: string = '';
  @Prop headerAction: string = '';
  onActionClick: () => void = () => {};

  build() {
    Row() {
      Text(this.headerText)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.color_text'))
        .layoutWeight(1)
        .textAlign(TextAlign.Start)
      if (this.headerAction !== '') {
        // 字号 13 且没有内边距时，实际可点区域只有文字本身，很容易点空。
        // 用 padding 把触达区撑到 30vp 高，右侧少留 8vp 抵消内边距。
        Text(this.headerAction)
          .fontSize(14)
          .fontColor($r('app.color.color_primary'))
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .onClick(() => {
            this.onActionClick();
          })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 8, top: 4, bottom: 8 })
  }
}

@Component
export struct TagText {
  @State tagText: string = '';
  @State tagColor: ResourceColor = $r('app.color.color_text_secondary');
  @State tagBg: ResourceColor = $r('app.color.color_chip_bg');

  build() {
    Text(this.tagText)
      .fontSize(10)
      .fontColor(this.tagColor)
      .backgroundColor(this.tagBg)
      .borderRadius(4)
      .padding({ left: 5, right: 5, top: 2, bottom: 2 })
      .maxLines(1)
  }
}

/** 视频海报卡片 */
@Component
export struct VodCard {
  @Prop cardTitle: string = '';
  @Prop cardPic: string = '';
  @Prop cardRemarks: string = '';
  /** 评分横幅（「评分： 9.2」贴海报下沿整条铺开）；空串不显示 */
  @Prop cardRating: string = '';
  @Prop cardSource: string = '';
  @Prop cardProgress: string = '';
  /** 紧凑模式：海报、标题条、角标全部按比例缩小，用于首页「继续观看」这类小卡位 */
  @Prop cardCompact: boolean = false;
  onCardClick: () => void = () => {};

  build() {
    // 海报与片名条之间不留缝：
    // 之前是 Column({space:6}) 把两者分开，卡片下半截空着一块，
    // 视觉上像「两张卡」，缩略图一多就散。现在做成一个整体 ——
    // 外层统一圆角 + clip，海报占上半、片名条紧贴下沿并自带底色。
    Column() {
      Stack({ alignContent: Alignment.Bottom }) {
        Stack({ alignContent: Alignment.TopStart }) {
          NetImage({ url: this.cardPic !== undefined ? this.cardPic : '' })
            .width('100%')
            .aspectRatio(0.72)
          if (this.cardRemarks !== '') {
            Text(this.cardRemarks)
              .fontSize(this.cardCompact ? 8 : 10)
              .fontColor(Color.White)
              .backgroundColor('#00000066')
              .borderRadius(3)
              .padding({ left: this.cardCompact ? 3 : 4, right: this.cardCompact ? 3 : 4, top: 1, bottom: 1 })
              .margin(this.cardCompact ? 4 : 6)
              .maxLines(1)
          }
        }
        .width('100%')

        // 评分横幅：必须排在海报 Stack 之后 —— Stack 里后画的子组件在上层，
        // 放在海报前面会被整张海报盖住（评分因此消失过一版）。
        // 评分横幅：贴海报下沿整条铺开，深色半透明衬底 + 白字，任何封面上都清晰可读。
        // 原先浮在海报左上角的半透明小角标会被封面自带的标题字/亮色底吃掉，几乎看不清。
        if (this.cardRating !== '') {
          Row() {
            Text(this.cardRating)
              .fontSize(this.cardCompact ? 9 : 11)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
              .maxLines(1)
          }
          .width('100%')
          .padding({ left: this.cardCompact ? 4 : 6, right: this.cardCompact ? 4 : 6, top: 2, bottom: 2 })
          .backgroundColor('#B3000000')
          .alignItems(VerticalAlign.Center)
        }

        if (this.cardProgress !== '') {
          // 进度条贴海报下沿。外层 Stack 用 Bottom 对齐，
          // 比在 TopStart 里靠 margin 凑位置稳。
          Stack({ alignContent: Alignment.Start }) {
            Row()
              .width('100%')
              .height(3)
              .backgroundColor('#00000055')
            Row()
              .width(this.cardProgress)
              .height(3)
              .backgroundColor($r('app.color.color_primary'))
          }
          .width('100%')
          .height(3)
        }
      }
      .width('100%')

      // 片名条：固定高度 + justifyContent(Center) 才是真正的垂直居中。
      // 之前用 padding(上7/下8) 让内容自己撑高，而 Text 的行高盒子本身带上下留白，
      // 字看起来就比衬底中线偏高一点点 —— 深色主题下尤其明显。
      Column({ space: 1 }) {
        Text(this.cardTitle)
          .fontSize(this.cardCompact ? 10 : 13)
          .fontColor($r('app.color.color_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .width('100%')
        if (this.cardSource !== '') {
          Text(this.cardSource)
            .fontSize(10)
            .fontColor($r('app.color.color_text_secondary'))
            .maxLines(1)
            .textAlign(TextAlign.Center)
            .width('100%')
        }
      }
      .width('100%')
      .height(this.cardCompact ? 24 : (this.cardSource !== '' ? 44 : 34))
      .padding({ left: this.cardCompact ? 4 : 8, right: this.cardCompact ? 4 : 8 })
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.color_caption_bg'))
    }
    .width('100%')
    .borderRadius(this.cardCompact ? 7 : 10)
    .clip(true)
    .backgroundColor($r('app.color.color_card'))
    .onClick(() => {
      this.onCardClick();
    })
  }
}

/** 设置项行：左侧标题，右侧值 + 箭头 */
@Component
export struct SettingsRow {
  @Prop rowTitle: string = '';
  @Prop rowValue: string = '';
  @Prop rowShowArrow: boolean = true;
  rowTitleColor: ResourceColor = $r('app.color.color_text');
  onRowClick: () => void = () => {};

  build() {
    Row({ space: 8 }) {
      Text(this.rowTitle)
        .fontSize(15)
        .fontColor(this.rowTitleColor)
        .layoutWeight(1)
        .textAlign(TextAlign.Start)
      if (this.rowValue !== '') {
        Text(this.rowValue)
          .fontSize(13)
          .fontColor($r('app.color.color_text_secondary'))
          .maxLines(1)
      }
      if (this.rowShowArrow) {
        Image($r('app.media.ic_back'))
          .width(14)
          .height(14)
          .rotate({ angle: 180 })
          .opacity(0.4)
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .backgroundColor($r('app.color.color_card'))
    .onClick(() => {
      this.onRowClick();
    })
  }
}
