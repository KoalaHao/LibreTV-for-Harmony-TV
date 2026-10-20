/**
 * 下载管理页：缓存任务进度 / 离线播放 / 删除
 */

import { DownloadTaskRecord } from '../model/Types';
import { DownloadManager } from '../data/DownloadManager';
import { EmptyView } from '../components/CommonWidgets';
import { PlayerPageParam } from './PlayerPage';

@Component
export struct DownloadsPage {
  navPathStack: NavPathStack = new NavPathStack();

  @State tasks: DownloadTaskRecord[] = [];

  /** 进度轮询计时器：下载在后台线程推进，页面不刷新就会一直停在初始数字 */
  private tickTimer: number = -1;

  aboutToAppear(): void {
    this.tasks = DownloadManager.shared().getTasks();
    this.startTick();
  }

  aboutToDisappear(): void {
    this.stopTick();
  }

  /**
   * 开始轮询进度（幂等）。
   * 每 1s 拉一次：下载在后台线程推进，只在进入页面时读一次会让界面停在
   * "2/287" 不动。必须能被重复调用 —— Navigation 复用缓存节点时
   * aboutToAppear 不会再执行，重新进入只有 onShown 会来。
   */
  private startTick(): void {
    if (this.tickTimer >= 0) {
      return;
    }
    this.tickTimer = setInterval(() => {
      const next: DownloadTaskRecord[] = DownloadManager.shared().getTasks();
      if (DownloadManager.progressKey(next) !== DownloadManager.progressKey(this.tasks)) {
        this.tasks = next;
      }
    }, 1000);
  }

  /** 停止轮询（幂等）：离开页面、退到后台都要停 */
  private stopTick(): void {
    if (this.tickTimer >= 0) {
      clearInterval(this.tickTimer);
      this.tickTimer = -1;
    }
  }

  private toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 });
  }

  private playOffline(task: DownloadTaskRecord): void {
    const p: PlayerPageParam = {
      sourceKey: task.sourceKey,
      vodId: task.vodId,
      episode: task.episode,
      episodeName: task.episodeName,
      title: task.name,
      positionMs: 0,
      offlineDir: task.dir
    };
    this.navPathStack.pushPath({ name: 'Player', param: p });
  }

  private statusText(task: DownloadTaskRecord): string {
    if (task.status === 'completed') {
      return '已完成';
    }
    if (task.status === 'downloading') {
      return task.done + '/' + task.total + ' 分片';
    }
    if (task.status === 'pending') {
      return '等待中';
    }
    if (task.status === 'paused') {
      return '已暂停 · ' + task.done + '/' + task.total;
    }
    if (task.status === 'merging') {
      // 分片下完还要拼成一个整文件才能播，这一步在长视频上要几十秒
      return '正在合并…';
    }
    if (task.error !== undefined && task.error !== '') {
      return task.error;
    }
    return '失败';
  }

  private statusColor(task: DownloadTaskRecord): ResourceColor {
    if (task.status === 'completed') {
      return $r('app.color.color_success');
    }
    if (task.status === 'failed') {
      return $r('app.color.color_warning');
    }
    return $r('app.color.color_text_secondary');
  }

  /**
   * 列表项 key 必须带上进度：ForEach 只在 key 变化时重建对应项。
   * 只写 task.id 的话，即便数组被换成新快照，数字变了也不会重绘。
   */
  private taskKey(task: DownloadTaskRecord): string {
    return task.id + '|' + task.status + '|' + task.done + '/' + task.total +
      '|' + (task.error !== undefined ? task.error : '');
  }

  /** 有进度可显示的状态：暂停时进度条留在原处，用户才知道续传从哪接 */
  private showProgress(task: DownloadTaskRecord): boolean {
    if (task.total <= 0) {
      return false;
    }
    return task.status === 'downloading' || task.status === 'pending' || task.status === 'paused';
  }

  private progressPercent(task: DownloadTaskRecord): string {
    if (task.total <= 0) {
      return '0%';
    }
    const pct = Math.floor((task.done / task.total) * 100);
    if (pct < 0) {
      return '0%';
    }
    if (pct > 100) {
      return '100%';
    }
    return pct + '%';
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
          Text('下载管理')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.color_text'))
            .layoutWeight(1)
          if (this.hasCompletedTasks()) {
            Text('清除已完成')
              .fontSize(14)
              .fontColor($r('app.color.color_primary'))
              .padding({ left: 10, right: 10, top: 8, bottom: 8 })
              .onClick(() => {
                DownloadManager.shared().clearCompleted();
                this.tasks = DownloadManager.shared().getTasks();
                this.toast('已清除完成的缓存');
              })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 8 })

        if (this.tasks.length > 0) {
          Text('退出应用后下载会暂停，重新打开会自动从断点续传')
            .fontSize(11)
            .fontColor($r('app.color.color_text_secondary'))
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 8 })
            .textAlign(TextAlign.Start)
        }

        if (this.tasks.length === 0) {
          EmptyView({ emptyText: '还没有下载任务，可在详情页下载' })
        } else {
          List({ space: 10 }) {
            ForEach(this.tasks, (task: DownloadTaskRecord) => {
              ListItem() {
                Column({ space: 8 }) {
                  Row({ space: 8 }) {
                    Text(task.name)
                      .fontSize(14)
                      .fontColor($r('app.color.color_text'))
                      .layoutWeight(1)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(this.statusText(task))
                      .fontSize(11)
                      .fontColor(this.statusColor(task))
                  }
                  .width('100%')
                  Text(task.episodeName + ' · ' + task.sourceName)
                    .fontSize(11)
                    .fontColor($r('app.color.color_text_secondary'))
                    .width('100%')
                    .textAlign(TextAlign.Start)
                  if (this.showProgress(task)) {
                    // 用 Stack 而不是 Column 嵌套：Stack 的 alignContent 是唯一
                    // 能确定「从左边开始长」的写法，Column 受默认交叉轴对齐影响，
                    // 在不同版本上会表现成从中间向两侧填充。
                    Stack({ alignContent: Alignment.Start }) {
                      Row()
                        .width('100%')
                        .height(4)
                        .backgroundColor($r('app.color.color_chip_bg'))
                        .borderRadius(2)
                      Row()
                        .width(this.progressPercent(task))
                        .height(4)
                        .backgroundColor($r('app.color.color_primary'))
                        .borderRadius(2)
                    }
                    .width('100%')
                    .height(4)
                    Text(this.progressPercent(task))
                      .fontSize(11)
                      .fontColor($r('app.color.color_text_secondary'))
                      .width('100%')
                      .textAlign(TextAlign.End)
                  }
                  // 之前这几个动作只有 12fp 纯文字、没有内边距，实测可点区域
                  // 只有 22×13vp（远小于 40vp 的推荐下限），平板上几乎点不中。
                  // 改成带底色的胶囊按钮：高约 36vp、左右各 16vp 内边距。
                  Row({ space: 10 }) {
                    if (task.status === 'completed') {
                      Text('离线播放')
                        .fontSize(13)
                        .fontColor($r('app.color.color_primary'))
                        .padding({ left: 18, right: 18, top: 13, bottom: 13 })
                        .borderRadius(22)
                        .backgroundColor($r('app.color.color_chip_bg'))
                        .onClick(() => {
                          this.playOffline(task);
                        })
                    }
                    if (task.status === 'downloading' || task.status === 'pending') {
                      Text('暂停')
                        .fontSize(13)
                        .fontColor($r('app.color.color_primary'))
                        .padding({ left: 18, right: 18, top: 13, bottom: 13 })
                        .borderRadius(22)
                        .backgroundColor($r('app.color.color_chip_bg'))
                        .onClick(() => {
                          DownloadManager.shared().pause(task.id);
                          this.tasks = DownloadManager.shared().getTasks();
                        })
                    }
                    if (task.status === 'paused' || task.status === 'failed') {
                      Text('继续')
                        .fontSize(13)
                        .fontColor($r('app.color.color_primary'))
                        .padding({ left: 18, right: 18, top: 13, bottom: 13 })
                        .borderRadius(22)
                        .backgroundColor($r('app.color.color_chip_bg'))
                        .onClick(() => {
                          if (DownloadManager.shared().resume(task.id)) {
                            this.toast('将从断点继续下载');
                          }
                          this.tasks = DownloadManager.shared().getTasks();
                        })
                    }
                    Text('删除')
                      .fontSize(13)
                      .fontColor($r('app.color.color_warning'))
                      .padding({ left: 18, right: 18, top: 13, bottom: 13 })
                      .borderRadius(22)
                      .backgroundColor($r('app.color.color_chip_bg'))
                      .onClick(() => {
                        DownloadManager.shared().remove(task.id);
                        this.tasks = DownloadManager.shared().getTasks();
                      })
                  }
                  .width('100%')
                  .justifyContent(FlexAlign.End)
                  .margin({ top: 2 })
                }
                .width('100%')
                .padding(12)
                .backgroundColor($r('app.color.color_card'))
                .borderRadius(10)
              }
            }, (task: DownloadTaskRecord) => this.taskKey(task))
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .padding({ left: 16, right: 16, bottom: 16 })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.color_bg'))
    }
    .hideTitleBar(true)
    .onShown(() => {
      // 缓存节点复用不会重跑 aboutToAppear：重新开闸并立刻拉一次，
      // 免得用户看到上一次留下的旧进度。
      this.tasks = DownloadManager.shared().getTasks();
      this.startTick();
    })
    .onHidden(() => {
      this.stopTick();
    })
  }

  private hasCompletedTasks(): boolean {
    for (const t of this.tasks) {
      if (t.status === 'completed') {
        return true;
      }
    }
    return false;
  }
}
