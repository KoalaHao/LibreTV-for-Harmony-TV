/**
 * 历史页：播放历史（续播）/ 我的收藏
 */

import { PlayRecord, FavoriteItem } from '../model/Types';
import { HistoryStore } from '../data/HistoryStore';
import { Utils } from '../common/Utils';
import { EmptyView } from '../components/CommonWidgets';
import { DetailPageParam } from './DetailPage';
import { PlayerPageParam } from './PlayerPage';
import { latestNavParam } from '../common/NavParam';

export interface HistoryPageParam {
  /** history / favorites */
  mode: string;
}

@Component
export struct HistoryPage {
  navPathStack: NavPathStack = new NavPathStack();
  mode: string = 'history';

  @State records: PlayRecord[] = [];
  @State favorites: FavoriteItem[] = [];

  aboutToAppear(): void {
    this.refresh();
  }

  private refresh(): void {
    this.records = HistoryStore.shared().getHistory();
    this.favorites = HistoryStore.shared().getFavorites();
  }

  private toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 });
  }

  private openDetail(sourceKey: string, vodId: string, title: string): void {
    const p: DetailPageParam = {
      sourceKey: sourceKey,
      vodId: vodId,
      title: title
    };
    this.navPathStack.pushPath({ name: 'Detail', param: p });
  }

  private continuePlay(rec: PlayRecord): void {
    const p: PlayerPageParam = {
      sourceKey: rec.sourceKey,
      vodId: rec.vodId,
      episode: rec.episode,
      episodeName: rec.episodeName !== undefined ? rec.episodeName : '',
      title: rec.name,
      positionMs: rec.positionMs,
      offlineDir: '',
      episodeUrl: rec.playUrl !== undefined ? rec.playUrl : '',
      lineIndex: rec.lineIndex !== undefined ? rec.lineIndex : 0
    };
    this.navPathStack.pushPath({ name: 'Player', param: p });
  }

  private confirmClear(): void {
    this.getUIContext().showAlertDialog({
      message: this.mode === 'history' ? '确定清空播放历史吗？' : '确定清空收藏吗？',
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '确定',
        action: () => {
          if (this.mode === 'history') {
            HistoryStore.shared().clearHistory();
          } else {
            HistoryStore.shared().clearFavorites();
          }
          this.refresh();
          this.toast('已清空');
        }
      }
    });
  }

  build() {
    NavDestination() {
      Column({ space: 0 }) {
        Row({ space: 4 }) {
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
          Text(this.pageTitle())
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.color_text'))
            .layoutWeight(1)
          if (this.mode === 'history' && this.records.length > 0) {
            Text('清空')
              .fontSize(14)
              .fontColor($r('app.color.color_primary'))
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .onClick(() => {
                this.confirmClear();
              })
          }
          if (this.mode === 'favorites' && this.favorites.length > 0) {
            Text('清空')
              .fontSize(14)
              .fontColor($r('app.color.color_primary'))
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .onClick(() => {
                this.confirmClear();
              })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 8 })

        if (this.mode === 'history') {
          if (this.records.length === 0) {
            EmptyView({ emptyText: '还没有播放记录' })
          } else {
            List({ space: 10 }) {
              ForEach(this.records, (rec: PlayRecord) => {
                ListItem() {
                  Row({ space: 10 }) {
                    if (rec.pic !== undefined && rec.pic !== '') {
                      Image(rec.pic)
                        .width(80)
                        .height(110)
                        .objectFit(ImageFit.Cover)
                        .borderRadius(8)
                        .backgroundColor($r('app.color.color_chip_bg'))
                    } else {
                      Column()
                        .width(80)
                        .height(110)
                        .backgroundColor($r('app.color.color_chip_bg'))
                        .borderRadius(8)
                    }
                    Column({ space: 6 }) {
                      Text(rec.name)
                        .fontSize(14)
                        .fontColor($r('app.color.color_text'))
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .textAlign(TextAlign.Start)
                        .width('100%')
                      Text(rec.sourceName + ' · ' + this.episodeLabel(rec))
                        .fontSize(11)
                        .fontColor($r('app.color.color_text_secondary'))
                        .maxLines(1)
                        .width('100%')
                        .textAlign(TextAlign.Start)
                      if (rec.durationMs > 0) {
                        Text('看到 ' + Utils.formatTime(rec.positionMs) + ' / ' + Utils.formatTime(rec.durationMs))
                          .fontSize(11)
                          .fontColor($r('app.color.color_primary'))
                          .width('100%')
                          .textAlign(TextAlign.Start)
                      }
                      Row({ space: 14 }) {
                        Text('继续播放')
                          .fontSize(12)
                          .fontColor($r('app.color.color_primary'))
                          .onClick(() => {
                            this.continuePlay(rec);
                          })
                        Text('删除')
                          .fontSize(12)
                          .fontColor($r('app.color.color_text_secondary'))
                          .onClick(() => {
                            HistoryStore.shared().removeHistory(rec.sourceKey, rec.vodId);
                            this.refresh();
                          })
                      }
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                  }
                  .width('100%')
                  .padding(10)
                  .backgroundColor($r('app.color.color_card'))
                  .borderRadius(10)
                }
              }, (rec: PlayRecord) => rec.sourceKey + '_' + rec.vodId)
            }
            .layoutWeight(1)
            .scrollBar(BarState.Off)
            .padding({ left: 16, right: 16, bottom: 16 })
          }
        } else {
          if (this.favorites.length === 0) {
            EmptyView({ emptyText: '还没有收藏' })
          } else {
            List({ space: 10 }) {
              ForEach(this.favorites, (fav: FavoriteItem) => {
                ListItem() {
                  Row({ space: 10 }) {
                    if (fav.pic !== undefined && fav.pic !== '') {
                      Image(fav.pic)
                        .width(80)
                        .height(110)
                        .objectFit(ImageFit.Cover)
                        .borderRadius(8)
                        .backgroundColor($r('app.color.color_chip_bg'))
                    } else {
                      Column()
                        .width(80)
                        .height(110)
                        .backgroundColor($r('app.color.color_chip_bg'))
                        .borderRadius(8)
                    }
                    Column({ space: 6 }) {
                      Text(fav.name)
                        .fontSize(14)
                        .fontColor($r('app.color.color_text'))
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .textAlign(TextAlign.Start)
                        .width('100%')
                      Text(fav.sourceName)
                        .fontSize(11)
                        .fontColor($r('app.color.color_text_secondary'))
                        .width('100%')
                        .textAlign(TextAlign.Start)
                      Text('取消收藏')
                        .fontSize(12)
                        .fontColor($r('app.color.color_text_secondary'))
                        .onClick(() => {
                          HistoryStore.shared().removeFavorite(fav.sourceKey, fav.vodId);
                          this.refresh();
                        })
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                  }
                  .width('100%')
                  .padding(10)
                  .backgroundColor($r('app.color.color_card'))
                  .borderRadius(10)
                  .onClick(() => {
                    this.openDetail(fav.sourceKey, fav.vodId, fav.name);
                  })
                }
              }, (fav: FavoriteItem) => fav.sourceKey + '_' + fav.vodId)
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
    .onShown(() => {
      // 缓存节点复用后 mode 还停在上一次：从「播放历史」退出再进「我的收藏」，
      // 看到的会是历史列表。参数必须重新取。
      const raw: Object | null = latestNavParam(this.navPathStack, 'History');
      if (raw !== null) {
        const p: HistoryPageParam = raw as HistoryPageParam;
        this.mode = p.mode;
      }
      this.refresh();
    })
  }

  private pageTitle(): string {
    if (this.mode === 'history') {
      return '播放历史';
    }
    return '我的收藏';
  }

  private episodeLabel(rec: PlayRecord): string {
    if (rec.episodeName !== undefined && rec.episodeName !== '') {
      return rec.episodeName;
    }
    return '第' + (rec.episode + 1) + '集';
  }
}
