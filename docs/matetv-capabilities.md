# Mate TV 能力调查与接入路线

调查日期：2026-10-25。依据华为官方文档、OpenHarmony 官方接口说明及本机 HarmonyOS 26.0.0.105 SDK。当前兼容基线为 API 24。已在 Mate TV / OpenHarmony 6.1.1.130 安装本版并检查首页与视频输出；各能力的验收范围见 [实机记录](tv-validation.md)。

## 官方专门指南与结论修正

现已核实有官方智慧屏专门开发指南，之前检索遗漏，不能再表述为“未找到 Mate TV 专门开发文档”。以下三篇作为项目后续适配依据：

- [智慧屏应用开发](https://developer.huawei.com/consumer/cn/doc/doccenter-multi-device/bpta-matetv-guide)：以 Mate TV 为例，说明硬件、灵犀遥控、应用接续及适配差异。
- [沉浸光感](https://developer.huawei.com/consumer/cn/doc/doccenter-advanced-features/bpta-spatiality-immersive)：UI 材质与导航实践，属于通用视觉能力。其组件级 systemMaterial 示例要求 target API 26，并建议检查可用材质后降级，不能直接用于当前 API 24 基线。
- [智慧屏设计](https://developer.huawei.com/consumer/cn/doc/doccenter-ux-design/vision-0000002321377950)：推荐视频 / 音乐等内容应用使用沉浸布局，并分别考虑指针和焦点交互。

专门指南明确灵犀遥控的方向键归一为 PanGesture；OK、返回、Home 等有系统默认行为，不响应 onKeyEvent。onHover / onClick / PanGesture 是主要输入通道。因此原先的“TV 方向键统一作为 DPAD”说明不准确。1.10.0-tv.3 补上视频手势路径、菜单键与悬停反馈；DPAD 仅作为键盘等设备的补充，返回仍走页面返回处理。

指南给出的屏幕规格是固定横屏、1280×720 vp / 3840×2160 px；电视仅支持深色模式。本版使用实际窗口尺寸布局，并固定电视深色主题。无线调试文档中的 5555 示例不替代设备实际报告的调试端口。List 的 fadingEdge 在 TV 上还有裁剪、overlay / blendMode 和截屏限制，涉及列表视觉改造时需单独核对。

系统未成年人模式是另一个可用方向：指南提供 Account Kit 的 minorsProtection 接入路线，本机 SDK 的相关接口也列出 TV API 19 支持。当前应用的成人内容过滤仍是本地设置，尚未接入系统未成年人状态或家长验证，不能宣称已支持系统联动。

这三篇没有提供面向普通应用的鸿鹄芯片 / MEMC 控制接口。公开 AVPlayer 超分的依据仍是 Media Kit 声明与 TV 设备支持矩阵。实机已收到 superResolutionChanged(true)；这能证明系统报告视频超分开启，不能证明采用了哪一条芯片算法链路或测得画质提升幅度。

## 当前可接入的能力

| 能力 | 接入方式 | 本版状态与边界 |
| --- | --- | --- |
| 遥控 / 键盘 / 返回 | 灵犀方向归一化 PanGesture、onClick；键盘 KeyEvent / 焦点；页面返回回调 | 已适配输入路径，实际硬件分发、滚动竞争及返回仍待验证 |
| 灵犀指向遥控 / 悬浮触控 | onHover / onClick / PanGesture 与系统命中测试 | 卡片、选集和设置行补上悬停反馈；未调用私有 UWB 接口，附件效果待验证 |
| 公开视频超分 | PlaybackStrategy.enableSuperResolution + superResolutionChanged | 点播已接入；电视默认请求，可在设置关闭；仅系统回调 true 才显示生效 |
| 系统媒体播控 | AVSession 的 play / pause / seek / playNext / playPrevious | 点播已响应并同步媒体状态；不承诺等同于完整小艺搜片接入 |
| HDR / 设备解码能力 | 保留 AVPlayer → XComponent(SURFACE) 原生视频路径 | 不把帧读回 UI，不强行用仅支持 SDR 的细节增强流程处理 HDR；当前未新增 HDR 状态检测或画质开关 |
| 手机 / 电视应用接续 | AbilityKit onContinue + onCreate / onNewWant / onWindowStageRestore | 1.10.0-tv.2 已适配，需要两端同版本与权限，系统入口及效果待双机验证 |
| 常亮与大屏窗口 | 复用上游播放期间常亮；电视跳过旋转与单窗口亮度 | API 24 兼容代码已落实；需复核系统待机、前后台与返回后的状态 |

## 超分与计算画质

[AVPlayer 官方接口](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-media-kit/arkts-apis-media-AVPlayer.md#setsuperresolution18)和 [PlaybackStrategy](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-media-kit/arkts-apis-media-i.md#playbackstrategy12)提供公开超分路线：

- API 18 起，华为 SDK 设备矩阵标记 TV 从 API 19 支持。设置策略后默认启用，输入 / 帧率是否满足算法要求由系统判断。
- 本机 SDK 说明支持输入 320×320 至 1920×1080，帧率不超过 30 fps；高帧率、超出分辨率范围或倍速超过处理能力时可自动关闭。
- `setVideoWindowSize()` 目标宽度 320–1920、高度 320–1080，默认目标 1920×1080。本版没有硬设 4K 或把视频 Surface 拉伸到 4K。
- `setSuperResolution()` 可动态切换。本版播放器提供“鸿鹄画质”即时开关，实际控制公开 AVPlayer 超分；TV 预先启用超分功能能力，保存为关闭时在 prepare 前关闭处理，以便起播后比较同一片段。若预关闭失败，重新以普通策略准备，避免违反关闭偏好。`superResolutionChanged` 报告系统状态，开启请求的 Promise 完成不等同于“生效中”。 此固件实测动态关后再开时不重复上报，而重新进入播放可立即恢复 true 回调。播放器因此等待 350 ms，仍无新回调时对同一媒体源重新 prepare，并按当前位置精确 seek，保留播放 / 暂停状态；如依然没有确认，则区分成功的开关指令与算法状态，不伪报“生效中”。
- 原片规格通过 `getTrackDescription()` 与 `getSelectedTracks()` 读取当前视频轨；帧率按 SDK 的每 100 秒帧数换算。没有使用显示屏尺寸或超分输出目标冒充输入分辨率。
- 状态区分“等待系统确认”“生效中”“当前未生效”“设备暂不支持”“已关闭”。没有回调时不会声称已生效。
- 注册或源策略不支持时回退普通策略；若服务已进入致命 error，则保留重试入口，之后不再请求超分。普通片源、网络与解码错误不会因画质逻辑被吞掉。

华为还提供[原生视频缩放 / 细节增强](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/generate-super-resolution-video)，需要 native 视频 Surface 处理流水线，支持的颜色和尺寸有约束。本版不为此重写播放器。

[Mate TV 产品页](https://consumer.huawei.com/cn/visions/mate-tv/)宣传鸿鹄 Vivid 独立画质芯片、AI 4K 超分、AI HDR 等能力，但没有证明它们与上述公开超分一一对应。公开 SDK 存在 API 26 的系统画质管理权限 `TV_MANAGE_PICTURE_QUALITY`，标记为系统应用权限，普通调试签名无法据此获得控制能力。

API 24 可查询 HDR 格式能力（包括 VIDEO_AIHDR 枚举），但查询不是开启命令。API 26 的 videoProcessing 状态接口也不能解决 API 24 机型上的全局 AI HDR 开关问题。

## 插帧 / MEMC

[华为官方图像设置说明](https://consumer.huawei.com/cn/support/content/zh-cn15837536/)包含 Mate TV 和 HarmonyOS 6.1，给出的新系统路径为：

**设置 → 显示和亮度 → 高级图像设置 → 清晰度与流畅度 → 运动流畅度。**

该功能提供 MEMC 高 / 中 / 低档，具体菜单随机型和系统变化。本次在公开媒体 API、华为扩展声明与视频处理头文件中没有找到普通第三方应用的 MEMC 控制接口。ArkWeb 的“补帧”属于无白屏加载机制，不能用于视频运动补偿。

本版保留系统原生视频显示链路，供后续对照电视系统设置。不能仅据此断言系统一定对 LibreTV 插帧，也不能把屏幕刷新率、UI 动画帧率或 AVPlayer 解码帧率当成 MEMC 生效证据。

## AI：有价值的方向与当前限制

[Mate TV 产品页](https://consumer.huawei.com/cn/visions/mate-tv/)脚注 21 明确限制 AI 搜片配合华为视频及内置电视端应用使用；不能从产品具备 AI 搜片、识人、声纹功能推导普通 HAP 可直接复用。

本机官方 SDK 的以下能力矩阵未列出 TV（选取的原始记录见 [sdk-capabilities.json](sdk-capabilities.json)）：

| 能力 | 对点播的价值 | 当前判断 |
| --- | --- | --- |
| Intents Kit | “继续看某部剧”、系统内容搜索、小艺推荐 | SDK 未列 TV；先保留标准 AVSession，完整意图接入等待 TV 官方支持或明确合作方案 |
| Core Speech Kit | 应用自行识别语音片名、语音命令 | SDK 未列 TV；不能把手机 API 直接标为电视可用；系统输入法的语音输入可后续实机验证 |
| Speech Kit AI 字幕 | 实时字幕 / 翻译辅助 | SDK 未列 TV；本版不加入无支持保证的字幕按钮 |
| Natural Language Kit | 文本分析与语言处理 | SDK 未列 TV；也不能把这些接口当作任意通用大模型推理服务 |
| Core Vision Kit | 识别封面、图像超分、识人 | SDK 未列 TV；图像能力不等同于实时视频处理，也不自动获得系统身份数据 |

[Intents Kit 官方介绍](https://developer.huawei.com/consumer/cn/sdk/intents-kit)确认其可提供习惯推荐、技能调用及内容直达，但这一通用能力介绍不覆盖具体 TV 支持条件。

建议后续优先级：

1. **先验证标准媒体播控。** 测试系统是否把“暂停、继续、快进、下一集”转为 AVSession 命令；代码接收能力本版已补上。系统是否下发不能靠应用单方面保证。
2. **应用内自然语言选片。** 例如“适合全家看的喜剧”“像某部电影但不恐怖”。可设计成独立、可关闭的模型服务，先做结构化检索条件，再查现有源；需要另行决定模型、成本、数据范围与服务方式，当前未实现，也没有上传观影记录。
3. **手机搜片后电视续播。** 复用现有分享深链与续播字段作为入口，再依据官方接续流程补齐生命周期与跨端状态；1.10.0-tv.2 已接入系统接续生命周期和播放状态迁移，见 [接续说明](playback-continuation.md)；双机验收尚未执行，普通分享链接仍是独立行为。
4. **智能跳片头 / 无剧透简介。** 需要可靠的片头标记或字幕 / 内容分析及模型方案；当前源数据不足，不能用固定时间跳转冒充 AI 识别。

识人后的个人片库、声纹身份和系统 AI 搜片结果没有在本版读取或接入。现阶段不在界面上展示无法兑现的 AI 功能入口。

## 实机验证原则

算法 API 支持、系统回调和屏幕效果分别记录。HDC 截图可能发生在独立画质芯片处理前，不能单独证明面板上的超分或插帧效果。使用相同片源和相同时间段对照，并结合系统状态与真实屏幕观察。待验证项目见 [tv-validation.md](tv-validation.md)。
