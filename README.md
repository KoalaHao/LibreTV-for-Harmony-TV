# LibreTV for Harmony TV

面向华为 Mate TV / HarmonyOS TV 的原生点播与直播客户端，基于 ArkTS、ArkUI 和系统 AVPlayer。

这是 [panhaichen-creator/LibreTV-for-HarmonyOS](https://github.com/panhaichen-creator/LibreTV-for-HarmonyOS) 的公开 fork，起点为上游 `354d730`（v1.9.8）。保留上游作者 PANPP、其他贡献者及 [LibreSpark/LibreTV](https://github.com/LibreSpark/LibreTV) 的贡献与归属，沿用 [AGPL-3.0](LICENSE)。本项目是社区电视适配版本。

## 当前版本

`1.10.0-tv.2`，最低 / 目标 API 24（HarmonyOS 6.1.1），使用 API 26 SDK 编译。保留包名 `com.libretv.harmonyos`；覆盖安装仍要求相同签名及有效的设备授权。

本版已通过离线构建和本地逻辑测试，**尚未在电视上验证或部署**。上游手机截图及旧版本实机结果不能作为本版验收证据。

## 电视改动

- 返回键先关闭当前选集、倍速、换源或设置面板，再回上一级；首页按返回留在应用内。播放页退出继续保存进度并释放播放器。
- 宽度至少 840 vp 的横向窗口采用两栏详情：左侧影片资料与播放操作，右侧线路与选集，两侧独立滚动。窄屏保留纵向布局。
- 详情、选集、首页卡片及播放器自绘操作加入方向键焦点和明显的焦点框。
- 电视播放时控制条隐藏后，左右键快退 / 快进 10 秒，确认键播放 / 暂停，上下键唤出控制条。控制条显示时方向键交给原生焦点导航；媒体播放 / 暂停键独立处理。
- **手机 / 电视应用接续**：播放页“分享 → 跨设备续播”，通过系统接续入口在另一端 LibreTV 恢复当前集、线路、进度、倍速及播放 / 暂停状态。需两端安装相同新版、完成授权与系统配置；双机效果待验证，见 [使用说明](docs/playback-continuation.md)。
- 点播 AVSession 响应播放、暂停、进度跳转、上 / 下一集，并同步片名、分集、进度和速度。这是标准媒体会话能力，语音助手是否下发命令仍待实机确认。
- 设置新增“视频超分（支持时启用）”，电视默认请求公开 AVPlayer 超分。播放页只有收到系统状态回调才显示“生效中”；不支持时降级，普通网络 / 解码错误继续保留重试入口。
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

测试运行实际 ArkTS 的返回路由、横屏尺寸规则、播放器超分逻辑、应用接续协议与 Ability 生命周期；仅在媒体服务边界替换原生对象。它们不替代电视上的焦点、返回键分发、音视频输出及画质验证。待执行项目见 [实机验收清单](docs/tv-validation.md)。

[上游架构说明](docs/ARCHITECTURE.md) · [上游版本说明](docs/release-notes-v1.9.8.md)
