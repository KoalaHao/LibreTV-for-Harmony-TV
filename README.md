# LibreTV for Harmony TV

面向华为 Mate TV / HarmonyOS TV 的原生点播与直播客户端，基于 ArkTS、ArkUI 和系统 AVPlayer。

这是 [panhaichen-creator/LibreTV-for-HarmonyOS](https://github.com/panhaichen-creator/LibreTV-for-HarmonyOS) 的公开 fork，起点为上游 `354d730`（v1.9.8）。保留上游作者 PANPP、其他贡献者及 [LibreSpark/LibreTV](https://github.com/LibreSpark/LibreTV) 的贡献与归属，沿用 [AGPL-3.0](LICENSE)。本项目是社区电视适配版本。

## 当前版本

`1.10.0-tv.21`，最低 / 目标 API 24（HarmonyOS 6.1.1），使用 API 26 SDK 编译。保留包名 `com.libretv.harmonyos`；覆盖安装仍要求相同签名及有效的设备授权。

当前版已通过 release 构建和 89 项本地逻辑测试。独立影片详情、持久化片源缓存与后台刷新、HTTP 耗时和清单分辨率已有 Mate TV / API 24 实机记录，见 [实机记录](docs/tv-validation.md)。

## 电视改动

- 电视首页采用统一悬浮顶栏，合并导航、内容分类、搜索与个人入口；横向续播卡片显示进度，推荐区每行 6 张圆角海报，片名置于卡片内，直接使用文字投影。手机保留原有界面。
- 卡片左上角显示评分，片名旁按累计短评数展示五档热度。底栏显示纯文字日期、国家 / 地区旗帜、电影片长或剧集总集数；豆瓣资料、评分与热度永久缓存，评分与热度超过 2 天时先显示旧值再后台刷新，失败继续保留旧值，缺失保持未知。见 [卡片与数据说明](docs/poster-cards.md)。
- 点击电视推荐卡片进入独立影片详情：卡片平滑放大至左侧、背景模糊，导演和主演放在卡片下方，中间顶端展示大字简介，右侧每个片源一个紧凑按钮。点击片源直接播放，有同源观看记录则续播；主动搜索仍使用原搜索页。
- 片源搜索结果永久缓存，超过 1 天先显示旧结果再后台更新；刷新时仍可选旧结果，未过期也可手动刷新。可见片源后台探测 HTTP 耗时与视频尺寸，结果一并缓存；清单声明尺寸以 `≤` 标识，源站画质文字标为“源标注”。详见 [影片详情与片源探测](docs/discovery.md)。
- 首页使用单一懒加载列表，按六张一行只创建可视区与邻近行；静态卡片缓存绘制结果，解码图片使用 64 MiB / 96 条 LRU 缓存，避免翻页持续堆积及缓存整批清空。见 [滚动性能记录](docs/tv-scroll-performance.md)。
- 推荐支持类型、地区、年代和排序组合筛选；年代包含近期逐年、十年区间和更早年份，条件传给推荐服务并保留到翻页请求中。
- 返回键先关闭当前选集、倍速、换源或设置面板，再回上一级；首页按返回留在应用内。播放页退出继续保存进度并释放播放器。
- 宽度至少 840 vp 的横向窗口采用两栏详情：左侧影片资料与播放操作，右侧线路与选集，两侧独立滚动。窄屏保留纵向布局。
- 卡片、选集、设置行提供指针悬停反馈；主要点播路径也保留键盘焦点框。电视固定使用深色主题。
- 点播页的灵犀遥控器按官方归一化 PanGesture 通道处理：控制条隐藏时，横向手势完成后快退 / 快进 10 秒，纵向手势唤出控制条；显示面板时交给原有滚动与控件操作。菜单键打开播放操作。传统 DPAD / Enter 逻辑保留给外接键盘等实际发送键值的设备，不能当作灵犀遥控器的输入通道。
- **手机 / 电视应用接续**：播放页“分享 → 跨设备续播”，通过系统接续入口在另一端 LibreTV 恢复当前集、线路、进度、倍速及播放 / 暂停状态。需两端安装相同新版、完成授权与系统配置；双机效果待验证，见 [使用说明](docs/playback-continuation.md)。
- 点播 AVSession 响应播放、暂停、进度跳转、上 / 下一集，并同步片名、分集、进度和速度。这是标准媒体会话能力，语音助手是否下发命令仍待实机确认。
- 播放页显示当前视频轨的原始分辨率、帧率、编码和服务提供的码率；缺失字段不推算，不将视频 Surface 尺寸当成原片分辨率。
- 播放器“鸿鹄画质”按钮对接公开 AVPlayer 视频超分，支持同一视频开关并保存偏好；本机动态重开不回报状态时，自动在原位置重新准备视频，保留进度、倍速与暂停状态，可能短暂缓冲。只有系统状态回调为 true 才显示“生效中”；按钮的名称不表示调用了私有鸿鹄芯片接口。未支持时普通播放可继续。
- 移除本版依赖的 API 26 专属材质调用，电视不强制旋转或修改单窗口亮度。

公开超分接口的目标输出上限为 1080p，不能将其称作已接入鸿鹄 4K。MEMC 使用电视系统的“运动流畅度”设置，目前没有找到普通 HAP 可用的公开控制接口。详见 [Mate TV 能力调查与接入路线](docs/matetv-capabilities.md)。

## 首次使用

在“我的 → 视频源管理”中添加已获得授权的 Apple CMS V10 点播接口、M3U / TXT 直播列表。保留上游的聚合搜索、线路选择、续播、收藏、下载、广告片段过滤等功能。片源内容与可用性由所配置的服务决定。

## 构建

需要 DevEco Studio、HarmonyOS API 26 SDK、其配套 Node / JBR / Hvigor。用 DevEco Studio 打开仓库并同步依赖，执行 `entry:assembleHap`。macOS 默认安装路径下也可执行：

```sh
export NODE_HOME=/Applications/DevEco-Studio.app/Contents/tools/node
export DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk
export JAVA_HOME=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw \
  --mode module -p module=entry@default -p product=default \
  -p buildMode=release assembleHap --no-daemon
```

产物：`entry/build/default/outputs/default/entry-default-unsigned.hap`。仓库的签名配置为空，安装前需在本机用自己的证书及设备授权签名。证书、私钥、profile、设备标识与本地签名配置不得提交。构建不会自动连接或安装到设备。

版本由 `AppScope/app.json5` 维护，构建不自动修改版本或品牌。更新版本时同步两个 `oh-package.json5`。

## 本地测试

Node.js 24（DevEco 配套版本可用），无额外 npm 依赖：

```sh
node --test tests/*.test.mjs
```

测试运行实际 ArkTS 的返回路由、横屏尺寸规则、影片详情状态、缓存与并发、HLS 清单、受限码流采样、直接播放与历史续播、播放器超分逻辑、应用接续协议与 Ability 生命周期；在文件、HTTP、媒体服务等平台边界使用替身。它们不替代电视上的焦点、返回键分发、音视频输出及画质验证。待执行项目见 [实机验收清单](docs/tv-validation.md)。

[上游架构说明](docs/ARCHITECTURE.md) · [上游版本说明](docs/release-notes-v1.9.8.md)
