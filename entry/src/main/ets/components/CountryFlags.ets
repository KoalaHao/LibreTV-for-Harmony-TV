import { PosterCardData } from '../model/PosterCardData';

const FLAG_RESOURCES: Record<string, Resource> = {
  'ar': $r('app.media.flag_ar'),
  'at': $r('app.media.flag_at'),
  'au': $r('app.media.flag_au'),
  'be': $r('app.media.flag_be'),
  'br': $r('app.media.flag_br'),
  'ca': $r('app.media.flag_ca'),
  'ch': $r('app.media.flag_ch'),
  'cn': $r('app.media.flag_cn'),
  'de': $r('app.media.flag_de'),
  'dk': $r('app.media.flag_dk'),
  'es': $r('app.media.flag_es'),
  'fi': $r('app.media.flag_fi'),
  'fr': $r('app.media.flag_fr'),
  'gb': $r('app.media.flag_gb'),
  'hk': $r('app.media.flag_hk'),
  'id': $r('app.media.flag_id'),
  'in': $r('app.media.flag_in'),
  'ir': $r('app.media.flag_ir'),
  'it': $r('app.media.flag_it'),
  'jp': $r('app.media.flag_jp'),
  'kr': $r('app.media.flag_kr'),
  'mo': $r('app.media.flag_mo'),
  'mx': $r('app.media.flag_mx'),
  'my': $r('app.media.flag_my'),
  'nl': $r('app.media.flag_nl'),
  'no': $r('app.media.flag_no'),
  'nz': $r('app.media.flag_nz'),
  'ph': $r('app.media.flag_ph'),
  'ru': $r('app.media.flag_ru'),
  'se': $r('app.media.flag_se'),
  'sg': $r('app.media.flag_sg'),
  'th': $r('app.media.flag_th'),
  'tr': $r('app.media.flag_tr'),
  'tw': $r('app.media.flag_tw'),
  'us': $r('app.media.flag_us'),
  'vn': $r('app.media.flag_vn'),
  'za': $r('app.media.flag_za')
};

@Component
export struct CountryFlags {
  @Prop countries: string[] = [];
  @Prop focused: boolean = false;
  @State private hovered: boolean = false;

  private resource(country: string): Resource {
    const code = PosterCardData.regionCode(country);
    return FLAG_RESOURCES[code] !== undefined ? FLAG_RESOURCES[code] : $r('app.media.ic_region_globe');
  }

  build() {
    Row({ space: 3 }) {
      if (this.countries.length === 0) {
        Image($r('app.media.ic_region_globe')).width(18).height(15)
      } else {
        ForEach(this.countries.slice(0, 2), (country: string) => {
          Image(this.resource(country)).width(this.countries.length > 1 ? 16 : 20).height(15)
            .objectFit(ImageFit.Contain).accessibilityText(country)
        }, (country: string) => country)
        if (this.countries.length > 2) {
          Text('+' + (this.countries.length - 2).toString()).fontSize(9).fontColor('#D7DDE6')
        }
      }
    }
    .constraintSize({ minWidth: 24, maxWidth: 50 }).height(22).justifyContent(FlexAlign.Center)
    .accessibilityText(this.countries.length > 0 ? this.countries.join(' / ') : '地区未提供')
    .onHover((hovered: boolean) => { this.hovered = hovered; })
    .bindPopup((this.hovered || this.focused) && this.countries.length > 0, {
      message: this.countries.join(' / '), placement: Placement.Top, showInSubWindow: false
    })
  }
}
