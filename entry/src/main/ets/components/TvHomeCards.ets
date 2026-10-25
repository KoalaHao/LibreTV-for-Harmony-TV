import { NetImage } from './NetImage';
import { TV_FOCUS, TV_POSTER_FOCUS } from '../common/TvFocus';
import { PosterCardData, PosterCardInfo } from '../model/PosterCardData';
import { PosterMetadataService } from '../data/PosterMetadataService';
import { CountryFlags } from './CountryFlags';
import { PosterHeat } from './PosterHeat';

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

/** Poster text sits directly on the artwork with soft dark shadows. */
@Component
export struct TvPosterCard {
  @Prop @Watch('subjectChanged') subjectId: string = '';
  @Prop seriesHint: boolean = false;
  @Prop title: string = '';
  @Prop poster: string = '';
  @Prop rating: string = '';
  onOpen: () => void = () => {};
  @State private hovered: boolean = false;
  @State private focused: boolean = false;
  @State private visible: boolean = false;
  @State private info: PosterCardInfo = PosterCardData.empty();
  @State private infoKnown: boolean = false;
  @State private liveKnown: boolean = false;
  @State private cardWidth: number = 0;
  @State private cardHeight: number = 0;
  private alive: boolean = false;
  private requesting: boolean = false;
  private requestToken: number = 0;
  private loadedVisible: boolean = false;
  private refreshTimer: number = -1;

  aboutToAppear(): void {
    this.alive = true;
    this.subjectChanged();
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.requestToken++;
    this.visible = false;
    this.syncRefreshTimer();
  }

  private subjectChanged(): void {
    this.requestToken++;
    this.requesting = false;
    this.loadedVisible = false;
    this.liveKnown = false;
    const cached = PosterMetadataService.peek(this.subjectId);
    this.info = cached !== null ? cached : PosterCardData.empty(this.subjectId, this.seriesHint);
    this.infoKnown = cached !== null;
    if (this.visible) this.loadDetails();
    this.syncRefreshTimer();
  }

  private async loadDetails(): Promise<void> {
    if (!this.alive || !this.visible || this.subjectId === '' || this.requesting || this.loadedVisible) return;
    const id = this.subjectId;
    const token = ++this.requestToken;
    this.requesting = true;
    this.loadedVisible = true;
    try {
      const result = await PosterMetadataService.request(id, this.seriesHint);
      if (this.alive && this.requestToken === token && this.subjectId === id && result !== null) {
        this.info = result;
        this.infoKnown = true;
        this.liveKnown = result.liveMetadata;
      }
    } finally {
      if (this.requestToken === token) this.requesting = false;
    }
  }

  private syncRefreshTimer(): void {
    if (this.alive && this.visible && this.subjectId !== '' && this.refreshTimer < 0) {
      this.refreshTimer = setInterval(() => {
        this.loadedVisible = false;
        this.loadDetails();
      }, 30000);
    } else if ((!this.alive || !this.visible || this.subjectId === '') && this.refreshTimer >= 0) {
      clearInterval(this.refreshTimer);
      this.refreshTimer = -1;
    }
  }

  private score(): string {
    if (this.info.rating !== '') return this.info.rating;
    if (this.liveKnown) return this.info.rating !== '' ? this.info.rating : '暂无评分';
    const value = Number(this.rating);
    if (Number.isFinite(value) && value > 0 && value <= 10) return value.toFixed(1);
    return '暂无评分';
  }

  private footerRight(): string {
    return this.infoKnown ? PosterCardData.footerRight(this.info) : (this.seriesHint ? '剧集' : '—');
  }

  private accessibleInfo(): string {
    return this.title + '，豆瓣评分' + this.score() + '，' + this.info.countries.join(' / ') + '，' +
      this.info.genres.join(' / ') + '，' + this.info.releaseDate + '，' + this.footerRight() + '，' +
      PosterCardData.heatLabel(this.info.shortComments);
  }

  @Builder
  private cardOutline() {
    Column().width(this.cardWidth).height(this.cardHeight).borderRadius(24)
      .border({ width: this.focused ? 3 : 2,
        color: this.focused ? '#FFD18C' : (this.hovered ? '#F0F2F6' : Color.Transparent) })
      .hitTestBehavior(HitTestMode.None)
  }

  build() {
    Column({ space: 0 }) {
      Stack({ alignContent: Alignment.Bottom }) {
        Stack({ alignContent: Alignment.TopStart }) {
        NetImage({ url: this.poster, boxWidth: 600, boxHeight: 900 }).width('100%').height('100%')
        Text(this.score() === '暂无评分' ? this.score() : '★ ' + this.score())
          .fontSize(this.score() === '暂无评分' ? 10 : 14).fontWeight(FontWeight.Bold)
          .fontColor(this.score() === '暂无评分' ? '#C1C9D5' : '#FFE0A0')
          .padding({ left: 9, right: 9, top: 5, bottom: 5 })
          .backgroundColor('#B81A1E27').borderRadius(14).margin(10)
      }
        .width('100%').height('100%')
        Column({ space: 0 }) {
        Row({ space: 5 }) {
          if (PosterCardData.heatTier(this.info.shortComments) > 0) {
            PosterHeat({ comments: this.info.shortComments, active: this.visible && (this.hovered || this.focused) })
          }
          Text(this.title).fontSize(17).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
            .textShadow([{ radius: 3, color: '#FF000000', offsetX: 0, offsetY: 1 },
              { radius: 10, color: '#FF000000', offsetX: -3, offsetY: 2 },
              { radius: 10, color: '#FF000000', offsetX: 3, offsetY: 2 },
              { radius: 24, color: '#FF000000', offsetX: -4, offsetY: 0 },
              { radius: 24, color: '#FF000000', offsetX: 4, offsetY: 0 },
              { radius: 48, color: '#FF000000', offsetX: 0, offsetY: 4 },
              { radius: 48, color: '#FF000000', offsetX: 0, offsetY: 4 }])
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        }.width('100%').padding({ left: 11, right: 11, top: 13 })
        Text(this.info.genres.length > 0 ? this.info.genres.slice(0, 3).join(' / ') : '类型未提供')
          .fontSize(11).fontColor('#E2E6ED').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .textShadow([{ radius: 2, color: '#FF000000', offsetX: 0, offsetY: 1 },
            { radius: 8, color: '#FF000000', offsetX: -2, offsetY: 1 },
            { radius: 8, color: '#FF000000', offsetX: 2, offsetY: 1 },
            { radius: 20, color: '#FF000000', offsetX: -3, offsetY: 0 },
            { radius: 20, color: '#FF000000', offsetX: 3, offsetY: 0 },
            { radius: 36, color: '#FF000000', offsetX: 0, offsetY: 3 },
            { radius: 36, color: '#FF000000', offsetX: 0, offsetY: 3 }])
          .width('100%').padding({ left: 13, right: 13, top: 6, bottom: 10 })
        }.width('100%')
      }.width('100%').aspectRatio(0.72)
        .borderRadius({ topLeft: 24, topRight: 24 }).clip(true)
      Row({ space: 3 }) {
          Text(this.info.releaseDate !== '' ? this.info.releaseDate : '—')
            .fontSize(this.info.countries.length > 1 ? 9.5 : 10.5).fontColor('#E2E6ED')
            .maxLines(1).layoutWeight(1).textAlign(TextAlign.Start)
          CountryFlags({ countries: this.info.countries, focused: this.focused })
          Text(this.footerRight()).fontSize(11).fontColor('#E2E6ED')
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1).textAlign(TextAlign.End)
        }
        .width('100%').padding({ left: 10, right: 10, top: 7, bottom: 7 })
        .backgroundColor(PosterCardData.footerColor(this.info.countries))
        .border({ width: { top: 0.5 }, color: '#28FFFFFF' })
        .borderRadius({ bottomLeft: 24, bottomRight: 24 }).clip(true)
    }
    .width('100%').borderRadius(24)
    .overlay(this.cardOutline(), { align: Alignment.Center })
    .onAreaChange((oldArea: Area, newArea: Area) => {
      const width = Number(newArea.width);
      const height = Number(newArea.height);
      if (width > 0 && Math.abs(width - this.cardWidth) > 0.1) this.cardWidth = width;
      if (height > 0 && Math.abs(height - this.cardHeight) > 0.1) this.cardHeight = height;
    })
    .focusable(true).focusBox(TV_POSTER_FOCUS)
    .accessibilityText(this.accessibleInfo())
    .onHover((hovered: boolean) => { this.hovered = hovered; })
    .onFocus(() => { this.focused = true; })
    .onBlur(() => { this.focused = false; })
    .onVisibleAreaChange([0.01], (visible: boolean, ratio: number) => {
      this.visible = visible;
      this.syncRefreshTimer();
      if (visible) this.loadDetails();
      else {
        this.loadedVisible = false;
        this.liveKnown = false;
        this.requestToken++;
        this.requesting = false;
      }
    })
    .onClick(() => this.onOpen())
  }
}
