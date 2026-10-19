/**
 * 搜索结果页：聚合多源结果、跨源同名合并、搜索历史
 */

import { MergedVideo } from '../model/Types';
import { SearchService } from '../model/SearchService';
import { SettingsStore } from '../data/SettingsStore';
import { HistoryStore } from '../data/HistoryStore';
import { Utils } from '../common/Utils';
import { EmptyView, LoadingView } from '../components/CommonWidgets';
import { DetailPageParam } from './DetailPage';

export interface SearchPageParam {
  keyword: string;
}

@Component
export struct SearchResultPage {
  navPathStack: NavPathStack = new NavPathStack();
  keyword: string = '';

  @State searchValue: string = '';
  @State results: MergedVideo[] = [];
  @State loading: boolean = false;
  @State searched: boolean = false;
  @State failedCount: number = 0;
  @State historyWords: string[] = [];

  aboutToAppear(): void {
    this.historyWords = HistoryStore.shared().getSearchHistory();
    if (this.keyword !== '') {
      this.searchValue = this.keyword;
      this.runSearch();
    }
  }

  private toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 });
  }

  private async runSearch(): Promise<void> {
    const wd = this.searchValue.trim();
    if (wd === '') {
      this.toast('请输入搜索关键词');
      return;
    }
    HistoryStore.shared().addSearchHistory(wd);
    this.historyWords = HistoryStore.shared().getSearchHistory();
    this.loading = true;
    this.searched = true;
    const res = await SearchService.aggregate(wd, SettingsStore.shared().get());
    const sorted = res.merged.slice().sort((a: MergedVideo, b: MergedVideo): number => b.items.length - a.items.length);
    this.results = sorted;
    this.failedCount = res.failedCount;
    this.loading = false;
  }

  private openDetail(v: MergedVideo): void {
    const first = v.items[0];
    if (first === undefined) {
      return;
    }
    const p: DetailPageParam = {
      sourceKey: first.sourceKey,
      vodId: first.vodId,
      title: v.name
    };
    this.navPathStack.pushPath({ name: 'Detail', param: p });
  }

  build() {
    NavDestination() {
      Column({ space: 0 }) {
        Row({ space: 8 }) {
          Row() {
            Image($r('app.media.ic_back'))
              .width(20)
              .height(20)
          }
          .width(32)
          .height(40)
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.navPathStack.pop();
          })
          Search({
            placeholder: '搜索电影 / 电视剧',
            value: $$this.searchValue
          })
            .layoutWeight(1)
            .height(36)
            .searchButton('搜索', { fontSize: 14, fontColor: $r('app.color.color_primary') })
            .onSubmit((value: string) => {
              this.runSearch();
            })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })

        if (this.loading) {
          LoadingView()
        } else if (!this.searched) {
          this.historyPanel()
        } else if (this.results.length === 0) {
          Column({ space: 8 }) {
            EmptyView({ emptyText: '没有找到相关视频' })
            if (this.failedCount > 0) {
              Text('有 ' + this.failedCount + ' 个源请求失败，可前往「视频源管理」检查')
                .fontSize(12)
                .fontColor($r('app.color.color_text_secondary'))
            }
          }
        } else {
          Column({ space: 0 }) {
            Row() {
              Text('共 ' + this.results.length + ' 个结果')
                .fontSize(12)
                .fontColor($r('app.color.color_text_secondary'))
                .layoutWeight(1)
              if (this.failedCount > 0) {
                Text(this.failedCount + ' 个源失败')
                  .fontSize(12)
                  .fontColor($r('app.color.color_warning'))
              }
            }
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 6 })

            List({ space: 10 }) {
              ForEach(this.results, (v: MergedVideo) => {
                ListItem() {
                  Row({ space: 10 }) {
                    if (v.pic !== undefined && v.pic !== '') {
                      Image(v.pic)
                        .width(88)
                        .height(120)
                        .objectFit(ImageFit.Cover)
                        .borderRadius(8)
                        .backgroundColor($r('app.color.color_chip_bg'))
                    } else {
                      Column()
                        .width(88)
                        .height(120)
                        .backgroundColor($r('app.color.color_chip_bg'))
                        .borderRadius(8)
                    }
                    Column({ space: 6 }) {
                      Text(v.name)
                        .fontSize(15)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.color_text'))
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .textAlign(TextAlign.Start)
                        .width('100%')
                      Row({ space: 6 }) {
                        if (v.year !== undefined && v.year !== '') {
                          Text(v.year)
                            .fontSize(11)
                            .fontColor($r('app.color.color_text_secondary'))
                        }
                        if (v.typeName !== undefined && v.typeName !== '') {
                          Text(v.typeName)
                            .fontSize(11)
                            .fontColor($r('app.color.color_text_secondary'))
                        }
                        if (v.area !== undefined && v.area !== '') {
                          Text(v.area)
                            .fontSize(11)
                            .fontColor($r('app.color.color_text_secondary'))
                        }
                      }
                      .width('100%')
                      if (v.remarks !== undefined && v.remarks !== '') {
                        Text(v.remarks)
                          .fontSize(11)
                          .fontColor($r('app.color.color_primary'))
                      }
                      Text(v.items.length + ' 个播放源')
                        .fontSize(11)
                        .fontColor($r('app.color.color_text_secondary'))
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                  }
                  .width('100%')
                  .padding(10)
                  .backgroundColor($r('app.color.color_card'))
                  .borderRadius(10)
                  .onClick(() => {
                    this.openDetail(v);
                  })
                }
              }, (v: MergedVideo) => Utils.normalizeTitle(v.name) + '|' + (v.year !== undefined ? v.year : ''))
            }
            .layoutWeight(1)
            .scrollBar(BarState.Off)
            .padding({ left: 16, right: 16, bottom: 16 })
          }
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.color_bg'))
    }
    .hideTitleBar(true)
  }

  @Builder
  historyPanel() {
    Column({ space: 12 }) {
      Row() {
        Text('搜索历史')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.color_text'))
          .layoutWeight(1)
        if (this.historyWords.length > 0) {
          Text('清空')
            .fontSize(13)
            .fontColor($r('app.color.color_text_secondary'))
            .padding({ left: 10, right: 10, top: 8, bottom: 8 })
            .onClick(() => {
              HistoryStore.shared().clearSearchHistory();
              this.historyWords = [];
            })
        }
      }
      .width('100%')

      if (this.historyWords.length === 0) {
        EmptyView({ emptyText: '输入关键词开始搜索' })
      } else {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.historyWords, (w: string) => {
            Text(w)
              .fontSize(13)
              .fontColor($r('app.color.color_text'))
              .backgroundColor($r('app.color.color_chip_bg'))
              .borderRadius(16)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .margin({ right: 8, bottom: 8 })
              .onClick(() => {
                this.searchValue = w;
                this.runSearch();
              })
          }, (w: string) => w)
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
      }
    }
    .layoutWeight(1)
    .padding({ left: 16, right: 16, top: 4 })
  }
}
