# 开源发布全流程

从一台装着源码的 Windows 电脑，到 GitHub 上一个别人能看懂、敢下载、能跑起来的仓库。

全程约 **40 分钟**，分 7 步。命令都按顺序给全，可直接复制。

> 本文档假设你已经完成了应用开发，现在要把 `LibreTV-HarmonyOS/` 这个目录推上 GitHub。

---

## 0. 全局视图

```
①发布前体检 ──→ ②git init ──→ ③建 GitHub 仓库 ──→ ④push
                                                        │
                    ⑦持续维护 ←── ⑥打 Release ←── ⑤仓库设置
```

**最容易出事的是第 ① 步**：签名密码、本机绝对路径一旦进了第一个 commit，
就算后面删掉，历史里也永远查得到（GitHub 的提交历史是不可变的）。
**所以：git init 之前，先把体检做完。**

---

## ① 发布前体检

### 1.1 敏感信息扫描（最重要，别跳过）

#### (a) 找签名密钥

HarmonyOS 项目最典型的泄露点是 `build-profile.json5` 里的 `signingConfigs`：

```json5
"signingConfigs": [{
  "material": {
    "certpath":      "C:\\Users\\你的用户名\\.ohos\\config\\xxx.cer",   // ← 泄露用户名
    "keyPassword":   "0000001B2411...",                                  // ← 泄露密码
    "profile":       "C:\\Users\\...\\xxx.p7b",
    "storeFile":     "C:\\Users\\...\\xxx.p12",
    "storePassword": "0000001B6324..."                                   // ← 泄露密码
  }
}]
```

**处理方式**：把整个 `signingConfigs` 数组清空，同时删掉 product 里的 `"signingConfig": "default"` 引用。

```json5
// build-profile.json5
{
  "app": {
    "signingConfigs": [],          // ← 留空
    "products": [{
      "name": "default",
      // 注意：这里不要留 "signingConfig": "default"，否则会报
      //       "signingConfig default not found"
      "compileSdkVersion": "26.0.0",
      ...
    }]
  }
}
```

代价：命令行构建只能产出 `entry-default-unsigned.hap`（未签名，装不上机）。
这没关系——使用者在 DevEco Studio 里勾一下 **Automatically generate signature**，
IDE 会自动把这一段填回去。README 里写清楚就行。

#### (b) 扫一遍全仓库

```powershell
Set-Location "C:\Users\75148\WorkBuddy\2026-10-16-15-38-25\LibreTV-HarmonyOS"

# 1) 绝对路径 / 用户名泄露
Get-ChildItem -Recurse -File -Include *.ets,*.ts,*.json5,*.json,*.md,*.ps1,*.py |
  Where-Object { $_.FullName -notmatch '\\build\\|\\\.hvigor\\|\\oh_modules\\' } |
  Select-String -Pattern 'C:\\\\Users|C:/Users' |
  Select-Object Path, LineNumber, Line

# 2) 密钥类字段
Get-ChildItem -Recurse -File -Include *.ets,*.ts,*.json5,*.json,*.md |
  Where-Object { $_.FullName -notmatch '\\build\\|\\\.hvigor\\' } |
  Select-String -Pattern 'storePassword|keyPassword|apiKey|api_key|secret|token|password' |
  Select-Object Path, LineNumber, Line

# 3) 证书文件本身
Get-ChildItem -Recurse -File -Include *.p12,*.cer,*.p7b,*.jks,*.keystore
```

三条命令都应该是**空的**（或者只剩文档里的 `******` 脱敏示例）。

#### (c) 如果已经提交过了才想起来

```bash
# 只改了文件还没提交
git add -A && git commit --amend

# 已经提交了（未推送）
git reset --soft HEAD~1
# 改完文件再重新提交

# 已经推送到 GitHub 了 —— 必须当作密码已泄露处理：
#   1) 立刻去华为 AGC 重新生成证书，作废旧证书
#   2) 用 git filter-repo 或 BFG 清洗历史后 force push
#   3) 联系 GitHub Support 清理缓存（fork 和缓存副本无法彻底清除）
```

**结论：能重签证书的，就重签。历史清洗永远不如"这个密钥从来没用过"干净。**

---

### 1.2 品牌与商标

如果你的代码是从别的项目改的，或者界面上残留了别人的品牌名，**开源前必须换掉** ——
这不是洁癖，是避免商标纠纷。本项目早期界面上残留了 `PPTV` 字样（8 处：`app.json5` 的
`vendor`、两处 `string.json`、三个页面里的文案、两个 `oh-package.json5` 的 `description`），
已经统一改为 `LibreTV`。

自查：

```powershell
Get-ChildItem -Recurse -File -Include *.ets,*.ts,*.json5,*.json |
  Where-Object { $_.FullName -notmatch '\\build\\|\\\.hvigor\\' } |
  Select-String -Pattern '旧的品牌名' |
  Select-Object Path, LineNumber, Line
```

同时确认：
- 应用图标是你自己画的，或来自可商用的图标库（本项目图标为自制）
- `AppScope/app.json5` 的 `bundleName` 用的是你自己的域名倒序（本项目 `com.libretv.harmonyos`
  是示例包名，**建议你改成自己的**，避免和已上架应用撞包名）

---

### 1.3 许可证

影视聚合类项目通常沿用上游协议。本项目上游 LibreTV 是 **AGPL-3.0**，所以本项目也必须 AGPL-3.0。

检查：

```powershell
# 1) LICENSE 文件存在且是全文（不是几行摘要）
(Get-Content LICENSE | Measure-Object -Line).Lines     # AGPL-3.0 全文约 660 行

# 2) 各处声明一致
Select-String -Path oh-package.json5 -Pattern 'license'   # 应为 "AGPL-3.0"
```

**如果你的项目是从 AGPL 项目 fork 的，你不能改用 MIT。** 这是硬性要求。

---

### 1.4 目录清洁

进仓库的只应该是**源码 + 文档 + 必要资源**。开发过程中的日志、一次性补丁脚本、
调试截图都不要进。

本项目的清理结果（对应 `.gitignore`）：

| 类别 | 处理 |
|---|---|
| `build/`、`entry/build/`、`.hvigor/`、`oh_modules/` | gitignore（构建产物） |
| `dev/` | gitignore（开发过程截图、临时脚本、局部签名备份） |
| `*.log`、`patch_*.py`、`_patch_*.py` | gitignore |
| `.ohos/`、`*.p12`、`*.cer`、`*.p7b` | gitignore（**证书绝不入库**） |
| `.idea/`、`.codegenie/` | gitignore（IDE 缓存） |
| `local.properties` | gitignore（IDE 自动生成，含本机路径） |
| `docs/screenshots/` | **入库**（README 要用） |

`.gitignore` 关键片段：

```gitignore
# 构建产物
/build/
/entry/build/
.hvigor/
oh_modules/
*.hap
*.app
*.hsp

# 签名材料（绝对不能提交）
.ohos/
*.p12
*.cer
*.p7b
*.jks
*.keystore

# IDE
.idea/
.codegenie/
.vscode/

# 本地配置
local.properties

# 开发过程杂物
dev/
*.log
patch_*.py
_patch_*.py
```

> ⚠️ **`dev/` 里有截图不代表能直接删** —— 先用 `Bash`/`Python` 把 README 需要的那几张
> 复制到 `docs/screenshots/` 再忽略 `dev/`。

---

### 1.5 构建验证（改完配置后必须重跑）

清空签名配置后，一定要**重新构建一次**，确认不是"删配置删出了编译错误"。

```powershell
$env:DEVECO_SDK_HOME = "D:\Program Files\Huawei\DevEco Studio\sdk"
$env:JAVA_HOME       = "D:\Program Files\Huawei\DevEco Studio\jbr"
$env:PATH            = "D:\Program Files\Huawei\DevEco Studio\jbr\bin;" + $env:PATH

Set-Location "路径\LibreTV-HarmonyOS"
node "D:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js" `
     assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
```

判据（两条都要满足）：

1. 日志末尾出现 `BUILD SUCCESSFUL`
2. 产物 `entry/build/default/outputs/default/entry-default-unsigned.hap` 存在且是新生成的

> ❗ **不要用退出码判断成败**。命令末尾接了 `| Select-String ...` 或 `| Out-File` 时，
> PowerShell 退出码恒为 1，即使构建成功。
>
> ❗ **不要把 hvigor 输出接到 `| Select-String` 上**。hvigor 往 stderr 写进度，
> PowerShell 5.1 会把它包装成 `NativeCommandError`，在 `$ErrorActionPreference='Stop'`
> 下会**中断管道**，表现为构建跑一半莫名其妙失败。用 `*>&1 | Out-File` 更稳。

---

### 1.6 文档就位

开源仓库至少要有这四份东西：

| 文件 | 作用 | 本项目 |
|---|---|---|
| `README.md` | 首页。**面向使用者**，不是面向你自己 | ✅ 下载/安装/首次使用/FAQ |
| `LICENSE` | 许可证全文 | ✅ AGPL-3.0 |
| `.gitignore` | 别把垃圾传上去 | ✅ |
| `docs/ARCHITECTURE.md` | 面向贡献者的技术文档 | ✅ |

README 的**常见错误**是按开发者的思路写："本工程采用 MVVM 分层、Navigation 路由……"
—— 下载的人第一句话想问的是"**这玩意装哪儿？怎么用？为什么搜不到东西？**"

正确的顺序：**它是什么 → 截图 → 怎么装 → 装完怎么配 → 出问题怎么办 → 技术细节（链接走）**。

---

## ② 初始化本地 Git 仓库

### 2.1 确认身份

```powershell
git config --global user.name
git config --global user.email
# 空的就设一下
git config --global user.name "你的名字"
git config --global user.email "你的邮箱"
```

> 邮箱会公开在每次提交里。不想暴露真实邮箱，去 GitHub
> `Settings → Emails → Keep my email addresses private`，然后用
> `12345678+用户名@users.noreply.github.com` 作为 `user.email`。

#### ⚠️ 本仓库已经用占位身份提交过一次

为了让你拿到手就是"可直接 push"的状态，仓库里已经有一个提交，
作者被临时设成了 `LibreTV Developer <libretv@users.noreply.github.com>`。

**推之前请改成你自己的身份**（只有一条命令，历史会被重写但还没推送，无副作用）：

```powershell
Set-Location "路径\LibreTV-HarmonyOS"

git config --local user.name  "你的名字"
git config --local user.email "你的邮箱"
git commit --amend --reset-author --no-edit

# 核对
git log -1 --format="%an <%ae>  %s"
```

### 2.2 确认换行符策略

Windows 上不加 `.gitattributes` 会出现"我只改了一个字，diff 显示整个文件都变了"。
本项目已带 `.gitattributes`（`* text=auto eol=lf`），无需额外操作。

### 2.3 初始化并首次提交

```powershell
Set-Location "路径\LibreTV-HarmonyOS"

git init -b main
git add -A

# ★ 关键一步：提交前检查将要入库的文件清单
git status --short
```

**逐行看这个清单**，确认：

- [ ] 没有 `*.p12` / `*.cer` / `*.p7b`
- [ ] 没有 `build/` / `.hvigor/` / `oh_modules/`
- [ ] 没有 `dev/`
- [ ] 没有 `*.log`
- [ ] `build-profile.json5` 在列表里（**这是对的**，它现在是脱敏版）
- [ ] `docs/screenshots/*.png` 在列表里（**这是对的**）
- [ ] 文件数量级合理（本项目约 90 个文件；如果显示 3000+，说明漏了 .gitignore）

```powershell
# 再确认一下签名配置确实是空的
Select-String -Path build-profile.json5 -Pattern 'signingConfigs'

git commit -m "feat: LibreTV 鸿蒙原生客户端首个开源版本

- ArkTS + ArkUI 从零实现，无 WebView
- 多源聚合搜索 / 跨源同名合并 / 换源测速
- AVPlayer HLS 播放，广告分片过滤、倍速、自动连播、进度续播
- 直播 M3U + XMLTV 节目单
- 分片下载 + 沙箱离线播放
- 深浅主题 / 多设备形态适配"
```

---

## ③ 创建 GitHub 仓库

### 方式 A：网页创建（推荐给第一次用的人）

1. 打开 <https://github.com/new>
2. **Repository name**：`LibreTV-HarmonyOS`（或你喜欢的名字）
3. **Description**：一句话说清是什么
   > LibreTV 的鸿蒙原生客户端 · ArkTS + ArkUI · HarmonyOS NEXT
4. **Public**（开源就选公开）
5. ❗ **不要**勾 `Add a README file`、`Add .gitignore`、`Choose a license`
   —— 你本地已经有了，勾了会产生一次无关的初始提交，push 时会冲突
6. 点 `Create repository`

### 方式 B：gh CLI 一条命令

```powershell
gh auth login          # 首次需要
gh repo create LibreTV-HarmonyOS --public --source=. --remote=origin --push
```

（`--push` 会直接把当前分支推上去，可以跳过第 ④ 步）

---

## ④ 推送

```powershell
Set-Location "路径\LibreTV-HarmonyOS"

git remote add origin https://github.com/<你的用户名>/LibreTV-HarmonyOS.git
git push -u origin main
```

### 推不上去的三种常见情况

| 报错 | 原因 | 解决 |
|---|---|---|
| `remote: Support for password authentication was removed` | 用了账号密码 | 改用 **Personal Access Token** 或 SSH |
| `error: src refspec main does not match any` | 本地分支叫 `master` | `git branch -M main` 后重推 |
| `Updates were rejected because the remote contains work...` | 建仓时勾了 README | `git pull --rebase origin main` 再推 |

### 配置 SSH（一次配置，以后免密）

```powershell
ssh-keygen -t ed25519 -C "你的邮箱"        # 一路回车
Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub" | Set-Clipboard
# 粘贴到 https://github.com/settings/keys → New SSH key
ssh -T git@github.com                      # 出现 "Hi xxx!" 即成功

git remote set-url origin git@github.com:<用户名>/LibreTV-HarmonyOS.git
```

---

## ⑤ 仓库设置（决定别人能不能找到、敢不敢用）

推上去只是"存在"，这一步才决定"有没有人用"。

### 5.1 About 区（首屏左上角）

点仓库首页右侧齿轮 `⚙ Edit repository details`：

- **Description**：一句话 + 关键词
  > LibreTV 的鸿蒙原生客户端｜ArkTS 多源影视聚合播放器｜HarmonyOS NEXT
- **Website**：有文档站就填
- **Topics**（最重要，决定能不能被搜到）：
  ```
  harmonyos  harmonyos-next  arkts  arkui  libretv  video-player
  hls  iptv  m3u8  avplayer  cms-v10  tvbox
  ```

### 5.2 分支保护（防止自己手滑 force push）

`Settings → Branches → Add branch protection rule`：

- Branch name pattern: `main`
- ✅ Require a pull request before merging（如果你接受 PR）
- ✅ Do not allow force pushes

### 5.3 Issue / PR 模板（可选但强烈建议）

新建 `.github/ISSUE_TEMPLATE/bug_report.md`：

```markdown
---
name: Bug 反馈
about: 报告一个问题，帮助改进项目
title: '[Bug] '
labels: bug
---

**设备信息**
- 设备型号：
- HarmonyOS 版本：
- 应用版本：

**问题描述**
（发生了什么）

**复现步骤**
1.
2.

**期望行为**

**日志 / 截图**
（`hdc hilog | findstr LibreTV` 的输出，或截图）
```

新建 `.github/pull_request_template.md`：

```markdown
## 改动内容

## 测试情况
- [ ] `hvigorw assembleHap` 通过，0 编译错误
- [ ] 真机验证通过（设备型号：      ）
- [ ] 未提交签名信息（`git diff build-profile.json5` 自查）
- [ ] 新增图标同时放入 base/media 与 dark/media
```

### 5.4 SECURITY.md（如果在意安全形象）

```markdown
# 安全策略

## 报告漏洞
请**不要**通过公开 Issue 报告安全问题。
发送邮件至 <你的邮箱>，或在 GitHub 上用 "Report a vulnerability" 私密报告。

我们会在 7 天内响应。
```

---

## ⑥ 发布第一个 Release

Release 是给"只想下载、不想编译"的人准备的入口。

### 6.1 准备产物

```powershell
Set-Location "路径\LibreTV-HarmonyOS"

# 产物在（注意：脱敏配置下是 unsigned）
entry\build\default\outputs\default\entry-default-unsigned.hap

# 重命名成带版本号的名字，方便识别
Copy-Item "entry\build\default\outputs\default\entry-default-unsigned.hap" `
          "LibreTV-HarmonyOS-v1.1.0-unsigned.hap"

# 生成校验和（下载者可以核对完整性）
Get-FileHash "LibreTV-HarmonyOS-v1.1.0-unsigned.hap" -Algorithm SHA256 |
  ForEach-Object { "$($_.Hash.ToLower())  LibreTV-HarmonyOS-v1.1.0-unsigned.hap" } |
  Out-File -Encoding ascii "LibreTV-HarmonyOS-v1.1.0-unsigned.hap.sha256"
```

### 6.2 打 tag 并推送

```powershell
git tag -a v1.1.0 -m "v1.1.0 - 首个开源版本"
git push origin v1.1.0
```

版本号建议遵循 [语义化版本](https://semver.org/lang/zh-CN/)：

| 场景 | 版本变化 | 例子 |
|---|---|---|
| 修 bug、调文案 | PATCH | 1.1.0 → 1.1.1 |
| 加功能、兼容旧版 | MINOR | 1.1.0 → 1.2.0 |
| 破坏性改动（改数据格式、改配置） | MAJOR | 1.1.0 → 2.0.0 |

### 6.3 建 Release

网页操作：仓库首页右侧 `Releases → Draft a new release`

- **Choose a tag**：选 `v1.1.0`
- **Release title**：`v1.1.0 — 首个开源版本`
- **Describe this release**：（见下方模板）
- **Attach binaries**：拖入 `.hap` 和 `.sha256`
- 如果是预览版，勾 `Set as a pre-release`

Release 说明模板：

```markdown
## 下载

| 文件 | 说明 |
|---|---|
| `LibreTV-HarmonyOS-v1.1.0-unsigned.hap` | **未签名**，需用你自己的证书重签后安装，见 README「安装」章节 |
| `LibreTV-HarmonyOS-v1.1.0-unsigned.hap.sha256` | SHA256 校验和 |

> 为什么没有"直接能装"的包：HarmonyOS 侧载要求调试证书的 profile 里登记设备 UDID，
> 作者无法为所有人的设备预先签名。详见 README。

## 新增

- 首页下拉弹簧回弹 + 顶部提示
- 上滑超过两屏出现「返回顶部」悬浮按钮
- 「一键导入 8 个推荐源」按钮
- 首页推荐分页翻倍（每批 40 条）

## 修复

- 修复返回顶部按钮阈值按"50 行"计算导致几乎不出现的问题（改为按屏高计算）
- 修复 `BootstrapSources` 把来源标签误当 detail 模板传入的问题

## 已知问题

- spider 源（TVBox `type:3`）不支持，HarmonyOS 无 JVM
- 主题切换需重启应用完全生效

## 完整变更

https://github.com/<用户名>/LibreTV-HarmonyOS/compare/v1.0.0...v1.1.0
```

### 6.4 用 gh CLI 发（可选）

```powershell
gh release create v1.1.0 `
  "LibreTV-HarmonyOS-v1.1.0-unsigned.hap" `
  "LibreTV-HarmonyOS-v1.1.0-unsigned.hap.sha256" `
  --title "v1.1.0 - 首个开源版本" `
  --notes-file RELEASE_NOTES.md
```

---

## ⑦ 发布后

### 7.1 自查清单

打开一个**无痕窗口**，用没登录 GitHub 的状态看看你的仓库：

- [ ] README 能正常渲染，截图能显示（相对路径 `docs/screenshots/xxx.png` 大小写敏感）
- [ ] 表格、代码块、折叠块（`<details>`）都正常
- [ ] 页面右上角识别出 `AGPL-3.0 license`
- [ ] 语言占比显示 TypeScript / ArkTS（而不是被当成"其他"）
- [ ] Release 页能下到 HAP，文件大小合理
- [ ] 从零 clone 一遍，用 DevEco 打开能构建

```powershell
# 验证"从零 clone 能构建"
cd $env:TEMP
git clone https://github.com/<用户名>/LibreTV-HarmonyOS.git test-clone
# 用 DevEco 打开 test-clone，勾自动签名，Run
```

### 7.2 宣传

| 渠道 | 注意 |
|---|---|
| 掘金 / 少数派 / V2EX | 讲**技术实现**（AVPlayer 状态机、HLS 重写、离线回环 HTTP），不要只发下载链接 |
| 鸿蒙开发者社区 | 打 `HarmonyOS` 标签 |
| 相关 TG / QQ 群 | 先看群规，很多群禁发链接 |

**宣传文案的重点是"我踩了什么坑、怎么解决的"**，而不是"快来下载"。前者有人看，后者被当广告。

### 7.3 维护节奏

- Issue 有人提，**48 小时内至少回一句**（哪怕"我看看"）。没人理的仓库不会有人贡献。
- 采集站失效是常态，建议每 2-3 个月跑一次源可用性检查，更新推荐源列表。
- 用 `CHANGELOG.md` 或 Release Notes 记录变更，别让使用者猜。

---

## ⑧ 合规红线（影视聚合类项目必读）

这个品类的开源项目有额外风险，发布前请确认：

### 8.1 绝不内置内容源

代码里**不能有**任何默认的采集站地址作为"开箱即用"的源。

本项目的做法：
- `SourceManager` 首次启动时源列表为空
- 推荐源以 `RECOMMENDED_VOD` 常量数组的形式存在，**必须由用户主动点击「一键导入」**才写入
- README 明确写出"不内置任何内容"

**为什么这条重要**：仓库里预置源 = 你在分发侵权内容的入口。用户主动添加 = 工具中立。

### 8.2 免责声明要具体

不要只写"本项目仅供学习"。要写清楚：

- 不提供、不托管、不分发任何内容
- 内容合法性由源方与使用者负责
- 不构成对任何内容的推荐或授权
- 收到侵权通知会处理

### 8.3 不要提供"破解/去广告/绕过会员"

"过滤 HLS 里的广告分片"是技术特性（提升播放体验），
但**不能**宣传成"破解 VIP 内容"或"去除平台贴片广告"。
本项目只处理自己添加的采集源，不涉及任何正版平台。

### 8.4 遵守平台规则

- GitHub 的 [Acceptable Use Policies](https://docs.github.com/site-policy/acceptable-use-policies)
- 不要在仓库里放 DRM 绕过工具、密钥、抓包教程

### 8.5 保留上游署名

本项目是 LibreTV 的移植实现，README 首段即注明来源，`LICENSE` 保留 AGPL-3.0。
**AGPL 要求你保留原始版权声明**，删掉它本身就是违规。

---

## ⑨ 故障排查

| 现象 | 原因 | 解决 |
|---|---|---|
| `git status` 列出 3000+ 文件 | `.gitignore` 没生效 | 确认文件在仓库根目录、编码为 UTF-8 无 BOM；已 add 的用 `git rm -r --cached . && git add -A` |
| push 后 GitHub 显示"全文件已修改" | 换行符差异 | 加 `.gitattributes`（`* text=auto eol=lf`），然后 `git add --renormalize .` |
| README 里图片裂开 | 路径大小写 / 相对路径错误 | Linux 服务器区分大小写，`docs/screenshots/Home.png` ≠ `home.png` |
| 别人 clone 后构建失败 `spawn java ENOENT` | 没配 `PATH` | 见 README FAQ |
| 别人 clone 后构建失败 `signingConfig default not found` | products 里还引用着已删除的签名配置 | 删掉 `"signingConfig": "default"` 这一行 |
| Release 附件上传失败 | 单文件 > 2GB | 分卷压缩，或用 Git LFS |
| 中文文件名在网页上变 `%E5%8F%AF...` | URL 编码 | 文档文件名改用 ASCII（本项目已把中文文档改名为 `FEASIBILITY.md`） |

---

## 附：一页速查

```powershell
# ===== 一次跑完（确认 1.1 体检已通过后再执行）=====
Set-Location "路径\LibreTV-HarmonyOS"

# 1. 入库前检查
Select-String -Path build-profile.json5 -Pattern 'signingConfigs'   # 必须是 []

# 2. 初始化
git init -b main
git add -A
git status --short          # ★ 人工核对清单

# 3. 首次提交
git commit -m "feat: LibreTV 鸿蒙原生客户端首个开源版本"

# 4. 关联远程并推送
git remote add origin https://github.com/<用户名>/LibreTV-HarmonyOS.git
git push -u origin main

# 5. 打 tag 与 Release
git tag -a v1.1.0 -m "v1.1.0 - 首个开源版本"
git push origin v1.1.0
# 然后去网页 Releases → Draft a new release 上传 HAP
```
