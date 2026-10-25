import { PosterCardData } from '../model/PosterCardData';

@Component
export struct PosterHeat {
  @Prop comments: number = -1;
  @Prop active: boolean = false;
  @State private hovered: boolean = false;

  private tier(): number { return PosterCardData.heatTier(this.comments); }
  private flameSize(): number { return [0, 14, 16, 18, 20][Math.max(0, this.tier())]; }
  private animated(): boolean { return this.active && this.tier() >= 3; }
  private icon(): Resource {
    if (this.tier() === 1) return $r('app.media.heat_attention');
    if (this.tier() === 2) return $r('app.media.heat_popular');
    if (this.tier() === 3) return $r('app.media.heat_hot');
    return $r('app.media.heat_phenomenal');
  }

  build() {
    Stack() {
      if (this.tier() > 0) {
        Image(this.icon()).width(this.flameSize()).height(this.flameSize() + 3)
          .objectFit(ImageFit.Contain)
          .shadow({ radius: this.tier() >= 3 ? 5 : 0,
            color: this.tier() === 4 ? '#B0FFB44E' : '#80FF573B', offsetX: 0, offsetY: 0 })
          .scale({ x: this.animated() ? 1.07 : 1, y: this.animated() ? 1.07 : 1 })
          .opacity(this.animated() ? 1 : 0.86)
          .animation({ duration: this.animated() ? 1500 : 150, iterations: this.animated() ? -1 : 1,
            playMode: PlayMode.Alternate, curve: Curve.EaseInOut })
      }
    }
    .width(22).height(25)
    .accessibilityText(PosterCardData.heatLabel(this.comments))
    .onHover((hovered: boolean) => { this.hovered = hovered; })
    .bindPopup(this.hovered && this.tier() > 0, {
      message: PosterCardData.heatLabel(this.comments), placement: Placement.Top, showInSubWindow: false
    })
  }
}
