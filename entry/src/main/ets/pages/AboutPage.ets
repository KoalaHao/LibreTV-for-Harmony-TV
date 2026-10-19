/**
 * 关于页：使用说明 / 关于 / 法律免责声明
 *
 * 这三块原先都堆在设置页底部，越加越长，把真正的设置项挤到上面找不到。
 * 现在独立成页，入口挂在「我的」一级页面的「关于」菜单里。
 */

@Component
export struct AboutPage {
  navPathStack: NavPathStack = new NavPathStack();

  private static readonly VERSION: string = '1.0.0';

  /**
   * 使用说明：新用户最容易卡在「没加源就什么都搜不到」，
   * 这一段必须讲明白，减少无谓的差评。
   */
  private static readonly GUIDE_LINES: string[] = [
    '· 首次使用请前往「我的 → 视频源管理」添加点播源（Apple CMS V10 接口）与直播源（M3U / TXT 订阅）。',
    '· 本应用不内置任何片源。未添加源时，首页推荐、搜索、列表均为空，属正常现象。',
    '· 直播源频道较多时，展开后列表底部会出现「收起频道列表」，点一下即可收起并回到该源标题。',
    '· 播放页支持切换片源；下载完成的剧集保存在本机，可在「我的 → 下载管理」查看与离线播放。'
  ];

  /**
   * 免责声明：聚合类播放器的合规核心是三条——
   * ① 自身不提供、不存储内容；② 片源由用户自行添加、责任在用户；
   * ③ 权利人救济路径指向第三方接口而非本应用。
   * 必须逐条写清，不能只写一句「仅供学习」。
   */
  private static readonly DISCLAIMER_LINES: string[] = [
    '一、本应用是一款本地播放与资源聚合工具，自身不提供、不存储、不上传、不转码任何音视频内容，也不内置任何影片、剧集或直播频道。',
    '二、应用内展示的片名、海报、简介、播放地址等信息，均来自用户自行添加的第三方数据接口，相关版权归原权利人所有。',
    '三、用户应确保其添加的片源已取得合法授权，并仅在法律法规允许的范围内使用本应用。因添加、传播或观看行为产生的任何法律责任，由用户自行承担。',
    '四、本应用对第三方接口的可用性、准确性、合法性、安全性不作任何明示或暗示的保证。第三方接口可能随时失效、变更或停止服务，由此导致的无法播放、内容错误等情况与本应用无关。',
    '五、本应用不含任何内置片源，无法删除或修改第三方内容。若权利人认为相关接口侵犯其合法权益，请直接向该接口的提供者主张权利。',
    '六、严禁将本应用用于商业用途、二次分发，或用于任何违反所在地法律法规的行为。',
    '七、下载内容仅保存在本机应用沙箱内，卸载应用会一并清除，请自行做好备份。',
    '八、使用本应用即表示你已阅读、理解并同意本声明的全部内容；如不同意，请立即停止使用并卸载本应用。'
  ];

  build() {
    NavDestination() {
      Column({ space: 0 }) {
        Row({ space: 8 }) {
          Row() {
            Image($r('app.media.ic_back'))
              .width(20)
              .height(20)
          }
          .width(36)
          .height(40)
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.navPathStack.pop();
          })
          Text('关于')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.color_text'))
            .layoutWeight(1)
            .textAlign(TextAlign.Start)
        }
        .width('100%')
        .height(48)
        .padding({ left: 8, right: 16 })

        Scroll() {
          Column({ space: 10 }) {
            // ---------- 使用说明 ----------
            Column({ space: 8 }) {
              Text('使用说明')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.color_text'))
                .width('100%')
                .textAlign(TextAlign.Start)
              ForEach(AboutPage.GUIDE_LINES, (line: string) => {
                Text(line)
                  .fontSize(12)
                  .lineHeight(19)
                  .fontColor($r('app.color.color_text_secondary'))
                  .width('100%')
                  .textAlign(TextAlign.Start)
              }, (line: string) => line)
            }
            .width('100%')
            .padding(14)
            .backgroundColor($r('app.color.color_card'))
            .borderRadius(10)
            .margin({ left: 16, right: 16, top: 8 })

            // ---------- 关于 ----------
            Column({ space: 6 }) {
              Row({ space: 6 }) {
                Text('LibreTV 鸿蒙原生客户端')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.color_text'))
                Text('by PANPP')
                  .fontSize(12)
                  .fontColor($r('app.color.color_primary'))
              }
              .width('100%')
              .justifyContent(FlexAlign.Start)

              Text('版本 ' + AboutPage.VERSION + ' · 多源聚合 · 点播 / 直播 / 离线下载')
                .fontSize(12)
                .fontColor($r('app.color.color_text_secondary'))
                .width('100%')
                .textAlign(TextAlign.Start)
              Text('本应用为个人学习研究作品，与任何电视台、影视平台或同名品牌均无关联，亦未获其授权或认可。')
                .fontSize(12)
                .lineHeight(18)
                .fontColor($r('app.color.color_text_secondary'))
                .width('100%')
                .textAlign(TextAlign.Start)
              Text('开源协议：AGPL-3.0 · 部分实现参考 LibreTV（LibreSpark）开源项目')
                .fontSize(12)
                .lineHeight(18)
                .fontColor($r('app.color.color_text_secondary'))
                .width('100%')
                .textAlign(TextAlign.Start)
            }
            .width('100%')
            .padding(14)
            .backgroundColor($r('app.color.color_card'))
            .borderRadius(10)
            .margin({ left: 16, right: 16 })

            // ---------- 法律免责声明 ----------
            Column({ space: 8 }) {
              Text('法律免责声明')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.color_text'))
                .width('100%')
                .textAlign(TextAlign.Start)
              ForEach(AboutPage.DISCLAIMER_LINES, (line: string) => {
                Text(line)
                  .fontSize(12)
                  .lineHeight(19)
                  .fontColor($r('app.color.color_text_secondary'))
                  .width('100%')
                  .textAlign(TextAlign.Start)
              }, (line: string) => line)
            }
            .width('100%')
            .padding(14)
            .backgroundColor($r('app.color.color_card'))
            .borderRadius(10)
            .margin({ left: 16, right: 16 })
          }
          .width('100%')
          .padding({ bottom: 32 })
        }
        .scrollBar(BarState.Off)
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.color_bg'))
    }
    .hideTitleBar(true)
  }
}
