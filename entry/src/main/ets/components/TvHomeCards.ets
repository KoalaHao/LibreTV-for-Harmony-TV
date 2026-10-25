import { NetImage } from './NetImage';
import { TV_FOCUS } from '../common/TvFocus';

/** Living-room controls share a visible hover/focus ring without moving adjacent content. */
@Component
export struct TvNavButton {
  @Prop label: string = '';
  @Prop selected: boolean = false;
  onSelect: () => void = () => {};
  @State private hovered: boolean = false;

  build() {
    Text(this.label)
      .fontSize(17)
      .fontWeight(this.selected ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.selected ? '#14171D' : '#E0E3EA')
      .padding({ left: 16, right: 16 })
      .height(40)
      .textAlign(TextAlign.Center)
      .backgroundColor(this.selected ? '#F0F2F6' : (this.hovered ? '#30FFFFFF' : Color.Transparent))
      .borderRadius(20)
      .focusable(true)
      .focusBox(TV_FOCUS)
      .onHover((hovered: boolean) => { this.hovered = hovered; })
      .onClick(() => this.onSelect())
  }
}

@Component
export struct TvContinueCard {
  @Prop title: string = '';
  @Prop poster: string = '';
  @Prop episode: string = '';
  @Prop positionLabel: string = '';
  @Prop progress: string = '0%';
  onPlay: () => void = () => {};
  @State private hovered: boolean = false;

  build() {
    Row({ space: 14 }) {
      NetImage({ url: this.poster, boxWidth: 180, boxHeight: 270 })
        .width(56).height(80).borderRadius(7).clip(true)
      Column({ space: 7 }) {
        Text(this.title).fontSize(17).fontWeight(FontWeight.Medium).fontColor('#F1F3F8')
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        Text(this.episode + ' · ' + this.positionLabel).fontSize(13).fontColor('#A3ABBA')
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        Stack({ alignContent: Alignment.Start }) {
          Column().width('100%').height(3).backgroundColor('#363C48')
          Column().width(this.progress).height(3).backgroundColor('#FF686B')
        }.width('100%').height(3).borderRadius(2).clip(true).margin({ top: 7 })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }
    .width(274).height(100).padding(10)
    .backgroundColor(this.hovered ? '#303744' : '#1D232E')
    .borderRadius(20).border({ width: 2, color: this.hovered ? '#E5E9F1' : Color.Transparent })
    .focusable(true).focusBox(TV_FOCUS)
    .accessibilityText('继续观看 ' + this.title + ' ' + this.episode)
    .onHover((hovered: boolean) => { this.hovered = hovered; })
    .onClick(() => this.onPlay())
  }
}

/** Round poster tiles keep the title inside a soft glass scrim over the artwork. */
@Component
export struct TvPosterCard {
  @Prop title: string = '';
  @Prop poster: string = '';
  @Prop rating: string = '';
  onOpen: () => void = () => {};
  @State private hovered: boolean = false;

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        NetImage({ url: this.poster, boxWidth: 600, boxHeight: 900 }).width('100%').height('100%')
        if (this.rating !== '' && this.rating !== '0') {
          Text(this.rating).fontSize(14).fontWeight(FontWeight.Bold).fontColor('#FFE0A0')
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor('#CC11151D').borderRadius(7).margin(9)
        }
      }
      .width('100%').height('100%')
      Column() {
        Text(this.title).fontSize(17).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
          .textShadow({ radius: 8, color: '#E6000000', offsetX: 0, offsetY: 2 })
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      }
      .width('100%').padding({ left: 13, right: 13, top: 14, bottom: 14 })
      .backgroundEffect({ radius: 12, saturation: 1.1 })
      .linearGradient({ direction: GradientDirection.Bottom, colors: [['#4810151C', 0], ['#E610151C', 1]] })
    }
    .width('100%').aspectRatio(0.72).borderRadius(22).clip(true)
    .border({ width: 2, color: this.hovered ? '#F0F2F6' : Color.Transparent })
    .focusable(true).focusBox(TV_FOCUS)
    .accessibilityText(this.title)
    .onHover((hovered: boolean) => { this.hovered = hovered; })
    .onClick(() => this.onOpen())
  }
}
