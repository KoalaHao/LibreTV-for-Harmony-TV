/**
 * 视频源管理页：点播源（Apple CMS）/ 直播源（M3U）增删改测、订阅导入导出
 */

import { VodSource, LiveSource, ExportVodEntry, ExportLiveEntry, SourceExportPayload } from '../model/Types';
import { SourceManager } from '../data/SourceManager';
import { SubscriptionParser, FlexibleParseResult } from '../model/SubscriptionParser';
import { RECOMMENDED_VOD } from '../model/RecommendedSources';
import { HttpClient } from '../net/HttpClient';
import { pasteboard } from '@kit.BasicServicesKit';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { EmptyView, TagText } from '../components/CommonWidgets';
import { Brand } from '../common/Brand';

@Component
export struct SourcesPage {
  navPathStack: NavPathStack = new NavPathStack();

  @State activeTab: number = 0;
  @State vodSources: VodSource[] = [];
  @State liveSources: LiveSource[] = [];
  @State showAddVod: boolean = false;
  @State showAddLive: boolean = false;
  @State showImport: boolean = false;
  @State newVodName: string = '';
  @State newVodUrl: string = '';
  @State newLiveName: string = '';
  @State newLiveUrl: string = '';
  @State newLiveEpg: string = '';
  @State importUrl: string = '';
  @State importText: string = '';
  @State importBusy: boolean = false;
  /** 剪贴板里识别到的可导入链接（导入面板顶部提供一键导入） */
  @State clipUrl: string = '';
  @State exportJson: string = '';
  @State showExport: boolean = false;

  aboutToAppear(): void {
    this.refresh();
    this.readClipboard();
  }

  /** 预读剪贴板：若是 http(s) 链接则在导入面板里提供一键导入 */
  private async readClipboard(): Promise<void> {
    try {
      const data = await pasteboard.getSystemPasteboard().getData();
      if (data.getRecordCount() <= 0) {
        return;
      }
      const rec = data.getRecord(0);
      const uri = rec.uri;
      if (uri !== '' && (uri.startsWith('http://') || uri.startsWith('https://'))) {
        this.clipUrl = uri;
        return;
      }
      const txt = rec.plainText;
      if (txt !== '' && txt.indexOf('\n') < 0 &&
          (txt.startsWith('http://') || txt.startsWith('https://'))) {
        this.clipUrl = txt;
      }
    } catch (e) {
      // 剪贴板不可用（无权限/为空）时静默跳过
    }
  }

  private refresh(): void {
    this.vodSources = SourceManager.shared().getVodSources();
    this.liveSources = SourceManager.shared().getLiveSources();
  }

  private toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 });
  }

  /**
   * 一键导入推荐源。
   * addVodSource 内部会按归一化后的 URL 去重，也会卡 MAX_VOD 上限，
   * 所以这里不用自己判重，只统计「新增了几个」告诉用户。
   */
  private importRecommended(): void {
    const mgr: SourceManager = SourceManager.shared();
    let added: number = 0;
    for (const r of RECOMMENDED_VOD) {
      if (mgr.addVodSource(r.name, r.api, '') !== null) {
        added++;
      }
    }
    this.refresh();
    if (added === 0) {
      this.toast('推荐源都已在列表里了');
      return;
    }
    const skipped: number = RECOMMENDED_VOD.length - added;
    this.toast(skipped > 0
      ? '已添加 ' + added + ' 个推荐源（' + skipped + ' 个已存在），建议先测速'
      : '已添加 ' + added + ' 个推荐源，建议先测速');
  }

  private addVod(): void {
    const url = this.newVodUrl.trim();
    if (url === '') {
      this.toast('请填写源地址');
      return;
    }
    const added = SourceManager.shared().addVodSource(this.newVodName, url, '');
    if (added === null) {
      this.toast('添加失败：地址无效或已存在');
      return;
    }
    this.newVodName = '';
    this.newVodUrl = '';
    this.showAddVod = false;
    this.refresh();
    this.toast('已添加「' + added.name + '」');
  }

  private addLive(): void {
    const url = this.newLiveUrl.trim();
    if (url === '') {
      this.toast('请填写直播源地址');
      return;
    }
    const added = SourceManager.shared().addLiveSource(this.newLiveName, url, this.newLiveEpg);
    if (added === null) {
      this.toast('添加失败：地址无效或已存在');
      return;
    }
    this.newLiveName = '';
    this.newLiveUrl = '';
    this.newLiveEpg = '';
    this.showAddLive = false;
    this.refresh();
    this.toast('已添加「' + added.name + '」');
  }

  private confirmDeleteVod(source: VodSource): void {
    this.getUIContext().showAlertDialog({
      message: '确定删除点播源「' + source.name + '」吗？',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '删除',
        action: () => {
          SourceManager.shared().removeVodSource(source.key);
          this.refresh();
        }
      }
    });
  }

  private confirmDeleteLive(source: LiveSource): void {
    this.getUIContext().showAlertDialog({
      message: '确定删除直播源「' + source.name + '」吗？',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '删除',
        action: () => {
          SourceManager.shared().removeLiveSource(source.key);
          this.refresh();
        }
      }
    });
  }

  private toggleVod(source: VodSource): void {
    SourceManager.shared().setVodEnabled(source.key, !source.enabled);
    this.refresh();
  }

  private toggleLive(source: LiveSource): void {
    SourceManager.shared().setLiveEnabled(source.key, !source.enabled);
    this.refresh();
  }

  private async testVod(source: VodSource): Promise<void> {
    this.toast('正在探测「' + source.name + '」…');
    const ok = await SourceManager.shared().testVodSource(source);
    if (ok) {
      SourceManager.shared().recordSuccess(source.key);
      this.toast('「' + source.name + '」可用');
    } else {
      SourceManager.shared().recordFailure(source.key);
      this.toast('「' + source.name + '」不可用');
    }
    this.refresh();
  }

  private async testLive(source: LiveSource): Promise<void> {
    this.toast('正在探测「' + source.name + '」…');
    const count = await SourceManager.shared().testLiveSource(source);
    if (count >= 0) {
      SourceManager.shared().recordSuccess(source.key);
      this.toast('「' + source.name + '」可用，共 ' + count + ' 个频道');
    } else {
      SourceManager.shared().recordFailure(source.key);
      this.toast('「' + source.name + '」不可用');
    }
    this.refresh();
  }

  /**
   * 弹性导入：自动识别订阅 JSON / TVBOX 配置 / M3U / TXT 播放列表。
   * 无源地址的播放列表内容（粘贴、本地文件）先存进沙箱，再以 file:// 引用，
   * 离线也能加载。
   */
  private applyFlexibleImport(text: string, originUrl: string, from: string): void {
    let fr: FlexibleParseResult;
    try {
      fr = SubscriptionParser.parseFlexible(text);
    } catch (e) {
      const err = e as Error;
      this.toast('导入失败：' + (err.message !== undefined ? err.message : '内容无法解析'));
      return;
    }
    if (fr.kind === 'json' && fr.sub !== undefined) {
      const sub = fr.sub;
      const vodAdded = SourceManager.shared().addVodSources(sub.vod);
      const liveAdded = SourceManager.shared().addLiveSources(sub.live);
      this.refresh();
      let msg = from + '：新增 ' + vodAdded + ' 个点播源、' + liveAdded + ' 个直播源';
      if (sub.skipped > 0) {
        msg = msg + '，跳过 ' + sub.skipped + ' 个无效项';
      }
      this.toast(msg);
      return;
    }
    if (fr.channels.length === 0) {
      this.toast(from + '：未解析到任何频道');
      return;
    }
    let url = originUrl;
    let name = '';
    if (url === '') {
      const saved = this.saveLocalPlaylist(text);
      if (saved === '') {
        this.toast('本地保存播放列表失败');
        return;
      }
      url = saved;
      name = '本地播放列表';
    }
    const added = SourceManager.shared().addLiveSource(name, url, '');
    this.refresh();
    if (added === null) {
      this.toast(from + '：该直播源已存在或添加失败');
    } else {
      this.toast(from + '：已添加「' + added.name + '」，共 ' + fr.channels.length + ' 个频道');
    }
  }

  /** 把粘贴/本地导入的播放列表内容存进沙箱，返回 file:// 路径 */
  private saveLocalPlaylist(text: string): string {
    try {
      const hostCtx = this.getUIContext().getHostContext();
      if (hostCtx === undefined) {
        return '';
      }
      const dir = hostCtx.filesDir + '/live';
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
      const path = dir + '/pl_' + Date.now() + '.txt';
      const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, text);
      fs.closeSync(file.fd);
      return 'file://' + path;
    } catch (e) {
      return '';
    }
  }

  private async importFromUrl(): Promise<void> {
    const url = this.importUrl.trim();
    if (url === '') {
      this.toast('请填写地址');
      return;
    }
    this.importBusy = true;
    const res = await HttpClient.getTextAny(url, { 'User-Agent': HttpClient.UA }, 12000);
    this.importBusy = false;
    if (!res.ok || res.text === '') {
      this.toast('地址内容拉取失败');
      return;
    }
    this.applyFlexibleImport(res.text, url, '订阅导入');
    this.importUrl = '';
    this.showImport = false;
  }

  private importFromText(): void {
    const text = this.importText.trim();
    if (text === '') {
      this.toast('请粘贴内容');
      return;
    }
    this.applyFlexibleImport(text, '', '粘贴导入');
    this.importText = '';
    this.showImport = false;
  }

  /** 本地文件导入：文件选择器限定 m3u / m3u8 / txt */
  private async importFromLocalFile(): Promise<void> {
    try {
      const doc = new picker.DocumentSelectOptions();
      doc.maxSelectNumber = 1;
      doc.fileSuffixFilters = ['播放列表 (.m3u, .m3u8, .txt)|.m3u,.m3u8,.txt'];
      const picked = await new picker.DocumentViewPicker().select(doc);
      if (picked.length === 0) {
        return;
      }
      this.importBusy = true;
      const text = await HttpClient.readLocalText(picked[0]);
      this.importBusy = false;
      if (text === '') {
        this.toast('文件读取失败');
        return;
      }
      this.applyFlexibleImport(text, '', '本地文件导入');
      this.showImport = false;
    } catch (e) {
      this.importBusy = false;
      // 用户取消选择等场景静默处理
    }
  }

  /** 扫码导入：识别二维码里的订阅 / 播放列表地址 */
  private async importFromScan(): Promise<void> {
    const hostCtx = this.getUIContext().getHostContext();
    if (hostCtx === undefined) {
      return;
    }
    const granted = await this.ensureCameraPermission(hostCtx as common.UIAbilityContext);
    if (!granted) {
      this.toast('未获得相机权限，无法扫码');
      return;
    }
    try {
      const options: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.QR_CODE]
      };
      const result = await scanBarcode.startScanForResult(hostCtx, options);
      const value = result.originalValue;
      if (value !== undefined && value !== '') {
        this.importUrl = value;
        this.toast('已识别，点击「从地址导入」完成');
      }
    } catch (e) {
      // 用户取消扫码静默处理
    }
  }

  private async ensureCameraPermission(ctx: common.UIAbilityContext): Promise<boolean> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const perms: Array<Permissions> = ['ohos.permission.CAMERA'];
      const result = await atManager.requestPermissionsFromUser(ctx, perms);
      let ok = result.authResults.length > 0;
      for (const r of result.authResults) {
        if (r !== 0) {
          ok = false;
        }
      }
      return ok;
    } catch (e) {
      return false;
    }
  }

  /**
   * 导出为「能被本应用直接导入」的订阅 JSON。
   *
   * 两个要点：
   * 1) 键名必须是 sources / liveSources —— SubscriptionParser.parseSourceList 只认这两个，
   *    之前导出的是 {vod, live}，粘回导入页会被解析成空列表，等于导出这件事本身失效。
   * 2) 只导出「启用中、且没被健康度停用」的源，导出的才是一份真能用的有效源清单；
   *    已停用/冷却中的源留在本机，不跟着走。
   */
  private exportSources(): void {
    const now: number = Date.now();
    const sources: ExportVodEntry[] = [];
    const seenVod: Set<string> = new Set();
    for (const s of SourceManager.shared().getVodSources()) {
      if (!s.enabled || s.disabledUntil > now) {
        continue;
      }
      // 同一地址可能以不同名字加过两次，导入端按 URL 去重，这里先自己收一遍
      if (seenVod.has(s.url)) {
        continue;
      }
      seenVod.add(s.url);
      const entry: ExportVodEntry = { name: s.name, api: s.url };
      if (s.isAdult) {
        entry.isAdult = true;
      }
      sources.push(entry);
    }
    const liveSources: ExportLiveEntry[] = [];
    const seenLive: Set<string> = new Set();
    for (const s of SourceManager.shared().getLiveSources()) {
      if (!s.enabled || s.disabledUntil > now) {
        continue;
      }
      if (seenLive.has(s.url)) {
        continue;
      }
      seenLive.add(s.url);
      const entry: ExportLiveEntry = { name: s.name, url: s.url };
      if (s.epg !== undefined && s.epg !== '') {
        entry.epg = s.epg;
      }
      liveSources.push(entry);
    }
    const payload: SourceExportPayload = {
      name: Brand.displayName(this.getUIContext()) + ' 视频源',
      updateTime: new Date().toISOString(),
      sources: sources,
      liveSources: liveSources
    };
    this.exportJson = JSON.stringify(payload, null, 2);
    this.showExport = true;
  }

  private copyExport(): void {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.exportJson);
    const pb = pasteboard.getSystemPasteboard();
    pb.setDataSync(data);
    this.toast('已复制到剪贴板');
  }

  private statusTag(source: VodSource | LiveSource): string {
    const desc = SourceManager.shared().disabledDesc(source.key);
    if (desc !== '') {
      return desc;
    }
    if (!source.enabled) {
      return '已停用';
    }
    return '正常';
  }

  private statusColor(source: VodSource | LiveSource): ResourceColor {
    if (SourceManager.shared().disabledDesc(source.key) !== '') {
      return $r('app.color.color_warning');
    }
    if (!source.enabled) {
      return $r('app.color.color_text_secondary');
    }
    return $r('app.color.color_success');
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        // 主内容
        Column({ space: 0 }) {
          // 顶部操作栏
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
            Text('视频源')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.color_text'))
              .layoutWeight(1)
            Text('导入')
              .fontSize(14)
              .fontColor($r('app.color.color_primary'))
              .padding({ left: 10, right: 10, top: 8, bottom: 8 })
              .onClick(() => {
                this.showImport = !this.showImport;
              })
            Text('导出')
              .fontSize(14)
              .fontColor($r('app.color.color_primary'))
              .padding({ left: 10, right: 10, top: 8, bottom: 8 })
              .onClick(() => {
                this.exportSources();
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 6 })

          Tabs({ index: this.activeTab }) {
            TabContent() {
              this.vodPanel()
            }
            .tabBar('点播源 (' + this.vodSources.length + ')')

            TabContent() {
              this.livePanel()
            }
            .tabBar('直播源 (' + this.liveSources.length + ')')
          }
          .barHeight(44)
          .layoutWeight(1)
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.color_bg'))

        // 添加点播源
        if (this.showAddVod) {
          this.addVodForm()
        }
        // 添加直播源
        if (this.showAddLive) {
          this.addLiveForm()
        }
        // 导入订阅
        if (this.showImport) {
          this.importForm()
        }
        // 导出
        if (this.showExport) {
          this.exportPanel()
        }
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .onShown(() => {
      // 缓存节点复用不会重跑 aboutToAppear：源可能在别处被增删过，重新读一遍
      this.refresh();
    })
  }

  @Builder
  vodPanel() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Button() {
          Text('添加点播源')
            .fontSize(13)
            .fontColor(Color.White)
        }
        .layoutWeight(1)
        .height(38)
        .backgroundColor($r('app.color.color_primary'))
        .borderRadius(19)
        .onClick(() => {
          this.showAddVod = !this.showAddVod;
        })
        Button() {
          Text('一键导入推荐源')
            .fontSize(13)
            .fontColor($r('app.color.color_text'))
        }
        .layoutWeight(1)
        .height(38)
        .backgroundColor($r('app.color.color_chip_bg'))
        .borderRadius(19)
        .onClick(() => {
          this.importRecommended();
        })
        Text('恢复健康度')
          .fontSize(13)
          .fontColor($r('app.color.color_primary'))
          .onClick(() => {
            SourceManager.shared().resetAllHealth();
            this.refresh();
            this.toast('已重置所有源的健康度');
          })
      }
      .width('100%')

      if (this.vodSources.length === 0) {
        EmptyView({ emptyText: '暂无点播源，请添加或导入订阅' })
      } else {
        List({ space: 8 }) {
          ForEach(this.vodSources, (s: VodSource) => {
            ListItem() {
              Column({ space: 8 }) {
                Row({ space: 8 }) {
                  Text(s.name)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.color_text'))
                    .layoutWeight(1)
                    .maxLines(1)
                  TagText({
                    tagText: this.statusTag(s),
                    tagColor: this.statusColor(s)
                  })
                }
                .width('100%')
                Text(s.url)
                  .fontSize(11)
                  .fontColor($r('app.color.color_text_secondary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                Row({ space: 16 }) {
                  Toggle({ type: ToggleType.Switch, isOn: s.enabled })
                    .scale({ x: 0.8, y: 0.8 })
                    .onChange((isOn: boolean) => {
                      this.toggleVod(s);
                    })
                  Text('探测')
                    .fontSize(12)
                    .fontColor($r('app.color.color_primary'))
                    .onClick(() => {
                      this.testVod(s);
                    })
                  Text('删除')
                    .fontSize(12)
                    .fontColor($r('app.color.color_warning'))
                    .onClick(() => {
                      this.confirmDeleteVod(s);
                    })
                }
                .width('100%')
              }
              .width('100%')
              .padding(12)
              .backgroundColor($r('app.color.color_card'))
              .borderRadius(10)
            }
          // key 必须带上开关/健康状态：点停用后对象只是就地改字段、key 不变，
          // ForEach 不重建 item，右侧状态标签与开关都停在旧值（要退出去重进才刷新）
          }, (s: VodSource) => s.key + '_' + (s.enabled ? 'on' : 'off')
            + '_' + (s.disabledUntil > Date.now() ? 'x' : 'ok'))
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 4 })
  }

  @Builder
  livePanel() {
    Column({ space: 10 }) {
      Button() {
        Text('添加直播源')
          .fontSize(13)
          .fontColor(Color.White)
      }
      .width('100%')
      .height(38)
      .backgroundColor($r('app.color.color_primary'))
      .borderRadius(19)
      .onClick(() => {
        this.showAddLive = !this.showAddLive;
      })

      if (this.liveSources.length === 0) {
        EmptyView({ emptyText: '暂无直播源，请添加 M3U 订阅' })
      } else {
        List({ space: 8 }) {
          ForEach(this.liveSources, (s: LiveSource) => {
            ListItem() {
              Column({ space: 8 }) {
                Row({ space: 8 }) {
                  Text(s.name)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.color_text'))
                    .layoutWeight(1)
                    .maxLines(1)
                  TagText({
                    tagText: this.statusTag(s),
                    tagColor: this.statusColor(s)
                  })
                }
                .width('100%')
                Text(s.url)
                  .fontSize(11)
                  .fontColor($r('app.color.color_text_secondary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                if (s.epg !== undefined && s.epg !== '') {
                  Text('EPG：' + s.epg)
                    .fontSize(10)
                    .fontColor($r('app.color.color_text_secondary'))
                    .maxLines(1)
                    .width('100%')
                    .textAlign(TextAlign.Start)
                }
                Row({ space: 16 }) {
                  Toggle({ type: ToggleType.Switch, isOn: s.enabled })
                    .scale({ x: 0.8, y: 0.8 })
                    .onChange((isOn: boolean) => {
                      this.toggleLive(s);
                    })
                  Text('探测')
                    .fontSize(12)
                    .fontColor($r('app.color.color_primary'))
                    .onClick(() => {
                      this.testLive(s);
                    })
                  Text('删除')
                    .fontSize(12)
                    .fontColor($r('app.color.color_warning'))
                    .onClick(() => {
                      this.confirmDeleteLive(s);
                    })
                }
                .width('100%')
              }
              .width('100%')
              .padding(12)
              .backgroundColor($r('app.color.color_card'))
              .borderRadius(10)
            }
          // 同点播源：key 带上状态，开关/状态标签实时跟着变
          }, (s: LiveSource) => s.key + '_' + (s.enabled ? 'on' : 'off')
            + '_' + (s.disabledUntil > Date.now() ? 'x' : 'ok'))
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 4 })
  }

  @Builder
  addVodForm() {
    Column({ space: 10 }) {
      TextInput({ placeholder: '源名称（留空则自动取名）', text: $$this.newVodName })
        .height(38)
        .fontSize(13)
        .backgroundColor($r('app.color.color_chip_bg'))
        .borderRadius(8)
        .padding({ left: 10, right: 10 })
      TextInput({ placeholder: '苹果 CMS V10 地址，如 https://xxx.com/api.php/provide/vod', text: $$this.newVodUrl })
        .height(38)
        .fontSize(13)
        .backgroundColor($r('app.color.color_chip_bg'))
        .borderRadius(8)
        .padding({ left: 10, right: 10 })
      Row({ space: 16 }) {
        Text('取消')
          .fontSize(13)
          .fontColor($r('app.color.color_text_secondary'))
          .layoutWeight(1)
          .onClick(() => {
            this.showAddVod = false;
          })
        Text('确定')
          .fontSize(13)
          .fontColor($r('app.color.color_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.RIGHT)
          .onClick(() => {
            this.addVod();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.color_card'))
    .borderRadius(10)
  }

  @Builder
  addLiveForm() {
    Column({ space: 10 }) {
      TextInput({ placeholder: '直播源名称（留空则自动取名）', text: $$this.newLiveName })
        .height(38)
        .fontSize(13)
        .backgroundColor($r('app.color.color_chip_bg'))
        .borderRadius(8)
        .padding({ left: 10, right: 10 })
      TextInput({ placeholder: 'M3U/M3U8 播放列表地址', text: $$this.newLiveUrl })
        .height(38)
        .fontSize(13)
        .backgroundColor($r('app.color.color_chip_bg'))
        .borderRadius(8)
        .padding({ left: 10, right: 10 })
      TextInput({ placeholder: 'XMLTV 节目单地址（可选，支持 .gz）', text: $$this.newLiveEpg })
        .height(38)
        .fontSize(13)
        .backgroundColor($r('app.color.color_chip_bg'))
        .borderRadius(8)
        .padding({ left: 10, right: 10 })
      Row({ space: 16 }) {
        Text('取消')
          .fontSize(13)
          .fontColor($r('app.color.color_text_secondary'))
          .layoutWeight(1)
          .onClick(() => {
            this.showAddLive = false;
          })
        Text('确定')
          .fontSize(13)
          .fontColor($r('app.color.color_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.RIGHT)
          .onClick(() => {
            this.addLive();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.color_card'))
    .borderRadius(10)
  }

  @Builder
  importForm() {
    Column({ space: 10 }) {
      Text('导入（订阅 JSON / TVBOX 配置 / M3U / TXT 播放列表）')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.color_text'))
        .width('100%')
        .textAlign(TextAlign.Start)
      if (this.clipUrl !== '') {
        Row({ space: 8 }) {
          Text('剪贴板：' + this.clipUrl)
            .fontSize(12)
            .fontColor($r('app.color.color_text_secondary'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('一键导入')
            .fontSize(12)
            .fontColor($r('app.color.color_primary'))
            .onClick(() => {
              this.importUrl = this.clipUrl;
              this.importFromUrl();
            })
        }
        .width('100%')
        .padding(8)
        .backgroundColor($r('app.color.color_chip_bg'))
        .borderRadius(8)
      }
      TextInput({ placeholder: '订阅 / 播放列表地址（http…）', text: $$this.importUrl })
        .height(38)
        .fontSize(13)
        .backgroundColor($r('app.color.color_chip_bg'))
        .borderRadius(8)
        .padding({ left: 10, right: 10 })
      Text('或粘贴内容（订阅 JSON / M3U / TXT 播放列表）：')
        .fontSize(12)
        .fontColor($r('app.color.color_text_secondary'))
        .width('100%')
        .textAlign(TextAlign.Start)
      TextArea({ placeholder: '支持 #EXTM3U 列表、频道名,地址 TXT 或订阅 JSON', text: $$this.importText })
        .height(90)
        .fontSize(12)
        .backgroundColor($r('app.color.color_chip_bg'))
        .borderRadius(8)
        .padding(10)
      Row({ space: 16 }) {
        Text('关闭')
          .fontSize(13)
          .fontColor($r('app.color.color_text_secondary'))
          .onClick(() => {
            this.showImport = false;
          })
        if (this.importBusy) {
          Text('处理中…')
            .fontSize(13)
            .fontColor($r('app.color.color_text_secondary'))
        } else {
          Text('从地址导入')
            .fontSize(13)
            .fontColor($r('app.color.color_primary'))
            .onClick(() => {
              this.importFromUrl();
            })
          Text('扫码导入')
            .fontSize(13)
            .fontColor($r('app.color.color_primary'))
            .onClick(() => {
              this.importFromScan();
            })
          Text('从本地文件导入')
            .fontSize(13)
            .fontColor($r('app.color.color_primary'))
            .onClick(() => {
              this.importFromLocalFile();
            })
          Text('从粘贴内容导入')
            .fontSize(13)
            .fontColor($r('app.color.color_primary'))
            .onClick(() => {
              this.importFromText();
            })
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.color_card'))
    .borderRadius(10)
  }

  @Builder
  exportPanel() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text('导出订阅')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.color_text'))
          .layoutWeight(1)
        Text('关闭')
          .fontSize(13)
          .fontColor($r('app.color.color_primary'))
          .onClick(() => {
            this.showExport = false;
          })
      }
      .width('100%')
      Text('只包含启用中的源。复制后可直接粘贴到「导入订阅」恢复，不会重复添加。')
        .fontSize(11)
        .fontColor($r('app.color.color_text_secondary'))
        .width('100%')
        .textAlign(TextAlign.Start)
      TextArea({ text: this.exportJson })
        .height(180)
        .fontSize(11)
        .backgroundColor($r('app.color.color_chip_bg'))
        .borderRadius(8)
        .padding(10)
      Button('复制到剪贴板')
        .fontSize(14)
        .width('100%')
        .backgroundColor($r('app.color.color_primary'))
        .onClick(() => {
          this.copyExport();
        })
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.color_card'))
    .borderRadius(10)
  }
}
