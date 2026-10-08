# 镜连 MirrorLink

[![一键下载安装包 — 镜连 macOS DMG](docs/assets/download-macos.svg)](https://github.com/zhaozachary1-cpu/MirrorLink/releases/download/v0.4.2/MirrorLink-0.4.2-macOS-universal.dmg)

**点击上方蓝色按钮，直接下载 0.4.2 安装包，无需进入 Assets 查找。**

下载后：**打开 DMG → 将 MirrorLink.app 拖入“应用程序” → 打开镜连**。按钮只负责下载，不会静默安装；浏览器可能按你的设置询问保存位置。

按钮未显示？[直接下载 DMG](https://github.com/zhaozachary1-cpu/MirrorLink/releases/download/v0.4.2/MirrorLink-0.4.2-macOS-universal.dmg) · [下载完整 ZIP](https://github.com/zhaozachary1-cpu/MirrorLink/releases/download/v0.4.2/MirrorLink-0.4.2-macOS-universal.zip) · [其他版本](https://github.com/zhaozachary1-cpu/MirrorLink/releases)

> 免费社区版未经 Apple 公证。首次打开可能需要手动允许，具体见[首次打开的 macOS 安全提示](#首次打开的-macos-安全提示)；不要关闭系统安全保护。

镜连是一个原生 macOS Android 投屏工具：它把官方 scrcpy v4.1 与 ADB 作为应用内置运行时，并用 SwiftUI 提供 USB / 同 Wi-Fi 无线连接、多设备选择、授权提示、并行投屏、独立开始/停止和诊断日志。当前版本为 0.4.2（Build 7），修复投屏就绪日志缓冲引发的 25 秒误超时，并补充主窗口重开处理。安装包以 [最新公开发行页](https://github.com/zhaozachary1-cpu/MirrorLink/releases/latest) 为准，源码版本不等于安装包已经发布。

## 下载、安装与注意事项（请先阅读）

### 系统与设备要求

- 电脑：macOS 13 或更新版本。Universal 包包含 Apple Silicon 和 Intel 架构，无需自行选择；Intel 真机仍未完成验收。
- 手机：Android；USB 投屏需要允许 USB 调试。无线连接需要 Android 11+、手机提供“无线调试”功能，并与 Mac 在可互通的同一 Wi-Fi 中。
- 不支持将此安装包用于 Windows 或 iPhone 投屏。无需另外安装 Homebrew、ADB 或 scrcpy。

### 选对下载文件

普通用户直接点击本页顶部蓝色按钮下载 DMG 即可；也可选择旁边的完整 ZIP 链接。需要查看全部文件时，再打开 [GitHub Releases 最新版](https://github.com/zhaozachary1-cpu/MirrorLink/releases/latest)，展开 **Assets**。**DMG 与完整 ZIP 任选一个，不需要重复下载**：

| 文件 | 用途 |
| --- | --- |
| `MirrorLink-0.4.2-macOS-universal.dmg` | 推荐给普通 Mac 用户；打开后拖拽安装 |
| `MirrorLink-0.4.2-macOS-universal.zip` | 完整安装包；先解压，再拖拽安装 |
| `MirrorLink-0.4.2-update.zip` / `appcast.xml` | 应用内更新专用；不要当作普通安装包转发 |
| `Source code (zip/tar.gz)` | 本项目源码，不是可双击安装的应用 |
| `MirrorLink-0.4.2-third-party-sources.tar.gz` | 第三方对应源码及许可材料，普通使用不需要下载 |
| `SHA256SUMS.txt` | 下载文件的 SHA-256 校验清单 |

以上文件名对应 0.4.2；将来发布新版时请选择同一 Release 中对应版本的文件。分享时发送官方 Release 链接、DMG 或完整 ZIP，不直接转发裸 `.app` 目录。

### 正常安装 / 手动覆盖旧版

1. 如果已经安装镜连，先停止投屏，并用 **⌘Q** 退出镜连；只关闭窗口不会退出应用。建议先保留旧版副本，以便必要时恢复。
2. 打开 DMG，或解压完整 ZIP，把 **`MirrorLink.app` 拖入“应用程序”（Applications）**。若提示已有同名应用，确认目标确实是镜连后选择替换。
3. 从“应用程序”打开镜连，不要一直在 DMG、下载目录或旧备份中运行。安装完成后可以推出磁盘映像；请保留自己需要的安装包/备份。
4. 连接并解锁 Android 手机，在手机上明确允许这台电脑的 USB 调试，再到镜连中刷新设备、开始投屏。设备显示“未授权”时，先在手机确认授权，不要反复重装应用。

### 首次打开的 macOS 安全提示

**这是免费社区版：只有本地 ad-hoc 完整性签名，没有 Apple Developer ID 身份认证，也没有 Apple 公证。** Sparkle 更新签名不等于 Apple 公证，不能承诺每台 Mac 都能无提示打开。

- 若系统仅提示无法验证开发者或无法检查恶意软件：确认文件来自本仓库并决定信任后，先尝试打开一次，再到 **“系统设置 → 隐私与安全”**，对镜连选择 **“仍要打开”**，按系统提示在本机确认。不要将系统密码发送给他人。
- 若提示 **“包含恶意软件”“将损害电脑”“已损坏”**，请停止安装，重新核对下载来源与文件校验值；不要把这类提示当作普通的未知开发者提示。
- 单位管理的 Mac 可能不允许例外，应联系管理员；不要关闭 Gatekeeper、全局放宽安全策略，或运行清除下载隔离标记的命令。
- 官方流程与适用边界：[Apple：在 Mac 上安全地打开 App](https://support.apple.com/102445)。

### 旧版升级与使用边界

- 0.3.1 及之后版本可主动点击“检查更新…”；安装需本人确认。网络或验签失败时不要跳过验证，可从官方 Release 下载完整包手动安装。
- 0.3.0 需按下方“应用更新”配置一次更新地址；0.2.0 及更早需手动安装。**若本机已经是 0.4.2 / Build 7 的本地预览包，同版本社区包不属于更高 Build，不应期待更新器再次提示；需要时手动安装完整社区包。**
- 无线首次配对必须在手机“开发者选项 → 无线调试”中扫码，不是微信或普通相机。不要转发配对二维码、配对码或含设备标识的诊断日志；同一 Wi-Fi 不代表已经授权。
- 单台 USB 真机短时测试与模拟多设备/无线检查已有记录，但真实无线、多台手机画面、陌生 Mac 首次安装及旧版经应用内覆盖升级仍有未完成的验收。查看 [STABILITY-QA.md](STABILITY-QA.md)、[WIRELESS-QA.md](WIRELESS-QA.md) 和 [UPDATE-QA.md](UPDATE-QA.md)，不要把构建/验签成功理解为所有设备已验收。

## 使用

### USB 投屏

1. 用 USB 线连接 Android 手机。
2. 在手机开发者选项中开启 USB 调试，解锁手机并允许此电脑调试。
3. 打开镜连，点击刷新设备；左侧勾选一台或多台状态为“已连接”的手机。
4. 点击“开始所选投屏”（快捷键 ⌘↩）。每台手机会在独立的 scrcpy 窗口中打开；窗口标题包含型号和完整设备序列号，便于区分同型号手机。某一台启动失败不会影响其他手机。
5. 可以在右侧对单台设备单独重试或停止，也可以使用“停止全部”关闭本次由镜连启动的所有窗口。

取消勾选或“清空选择”只改变下一次批量启动的对象，不会停止已在投屏的手机；这些设备仍保留单独的停止入口。断开后重新连接不会自动启动投屏，需要再次点击开始。退出镜连会停止本应用启动的全部投屏，不会关闭其他软件启动的 scrcpy 窗口。

关闭主窗口不会退出镜连或停止现有投屏。可以点击 Dock 图标，或通过“投屏 → 显示主窗口”（⌘0）重新打开控制窗口；退出应用仍使用 ⌘Q。0.4.2 的故障原因、回归结果与未验收范围见 [STABILITY-QA.md](STABILITY-QA.md)。

### 同 Wi-Fi 无线投屏（0.4.1）

需要 Android 11+ 且手机提供“无线调试”选项。首次配对不需要 USB 线，但仍须在手机上明确授权；仅加入同一 Wi-Fi 不会自动获得投屏权限。

1. Mac 和手机连接同一 Wi-Fi，在手机“开发者选项”中打开“无线调试”，按手机提示允许当前网络。
2. 打开镜连，点击工具栏或侧栏的“无线连接”，也可选择菜单“投屏 → 无线连接…”（⌘⇧W）。
3. 镜连默认显示“扫码配对”。在手机点“使用二维码配对设备”，扫描电脑上的二维码。**使用手机“无线调试”里的扫码入口，不是微信或普通相机。** 无需手填 IP、端口或六位配对码；电脑会主动发现扫码的手机，完成配对后核对身份并请求开始投屏，实际画面以主窗口结果为准。
4. 以后打开“发现手机”，应用会每 4 秒刷新附近开启无线调试的手机。对已授权此 Mac 的手机点击“连接并投屏”即可；主列表中已连接的 Wi-Fi 手机也可以直接选择并开始投屏。发现服务不代表手机已授权，授权被撤销后仍须重新扫码。

手机不提供扫码入口时，使用“手动连接 → 首次配对”：填写手机配对码弹窗中的 IP、配对端口和 6 位配对码。成功后回到手机“无线调试”的**主页面**，将该页 IP 和连接端口填入“连接手机”。**连接端口与配对端口用途不同。** 网络无法自动发现时，已配对的手机也可在这里手填连接地址。切换网络、重开无线调试或重启手机后端口可能变化，以手机当前显示为准。

每台手机单独配对后，可以同时投屏多台无线手机，也可以混用 USB 与 Wi-Fi。能取得硬件序列号时，同一手机的两种连接会合并为一个设备；正在运行的窗口不会被刷新或新连接偷偷切换。如果原窗口仍用 USB，请先停止该手机的投屏再开始，以切换到就绪的 Wi-Fi 连接。

发现不到手机时，可手动填入地址；检查手机是否仍开启无线调试、macOS 是否允许本地网络访问，以及访客 Wi-Fi、路由器设备隔离或 VPN 是否阻止互访。没有无线调试选项的机型继续使用 USB，本版本不会自动打开旧式 5555 端口或修改手机安全设置。

二维码在本机生成，是本次临时授权凭据，请勿分享或截图转发；每次生成都会更换，120 秒内有效，开始配对即隐藏。二维码密码和手动配对码仅在本次操作内存中使用，通过标准输入传给 ADB，不写入参数、日志、设置、剪贴板或 Git，不发送给外部二维码服务。关闭窗口、切换方式或停止操作会取消本次发现及自动连接；ADB 仍会维护已完成的配对授权，不会因此自动撤销，可在手机中忘记此电脑。仅在可信网络使用，用完可在手机关闭无线调试；停止镜连投屏不会擅自断开其他软件的 ADB 连接。

支持 macOS 13+，不包含 iPhone 或 Windows 客户端。不设置固定并行台数上限；实际流畅数量取决于 Mac 性能、Wi-Fi 质量、USB 带宽和手机编码能力。0.4.1 的模拟测试、构建结果与待完成的真机验收分开记录在 [WIRELESS-QA.md](WIRELESS-QA.md)，不能将测试脚本通过等同于无线画面已经验收。

## 应用更新

0.3.0 新增主窗口更新按钮、应用菜单“检查更新…”和“设置 → 应用更新”，使用 Sparkle 2.10.0 验证签名、下载、替换原应用并重启。自动检查需用户主动开启，安装始终需要用户确认；如果仍有手机在投屏，会先确认是否停止。

0.3.1 内置现有仓库的更新地址。应用只信任内置公钥对应的签名，同时验证更新清单和更新包，不接受随下载源替换的公钥，不内置 GitHub 登录凭据。发布及实际覆盖升级验证记录见 [UPDATE-QA.md](UPDATE-QA.md)。

0.3.0 用户在“设置 → 应用更新 → 设置更新地址”保存以下地址一次，即可使用已有更新器；之后版本无需重复输入：

```text
https://github.com/zhaozachary1-cpu/MirrorLink/releases/latest/download/appcast.xml
```

0.2.0 及更早版本没有更新器，需要先安装一次 0.3.0 或后续含更新器的版本。完整上线步骤与验证边界见 [UPDATES.md](UPDATES.md)。

## 构建

```zsh
./script/run_core_checks.sh
./script/run_session_checks.sh
./script/run_wireless_checks.sh
./script/run_update_checks.sh
./script/build_and_run.sh --verify
./script/package_release.sh --community
```

构建脚本会生成 arm64 + x86_64 通用 `.app`，把 ADB、scrcpy、scrcpy-server 及 Sparkle.framework 复制进应用包，对嵌套辅助程序、框架、内置工具和完整应用包依次进行本地 ad-hoc 签名，并通过 macOS `open` 启动应用。`--verify` 会检查包结构、双架构、随包许可声明与完整代码签名。应用包中的官方 scrcpy 运行时来源和哈希见 `vendor/scrcpy/` 与构建日志。仅验证构建且不启动应用时，使用 `./script/build_and_run.sh --debug --verify --no-launch`。

默认构建与发行目录分别为项目内的 `artifacts/Builds/` 和 `artifacts/Releases/`，旧版安装备份集中在 `artifacts/Backups/`，构建、打包及许可整理的临时目录为 `work/tmp/`。脚本按自身所在位置定位项目，可在其他工作目录调用；带空格、中文的路径也须用引号包裹。可用 `--output-dir`（优先）、`MIRRORLINK_OUTPUT_DIR`（构建）或 `MIRRORLINK_RELEASE_DIR`（打包）覆盖默认输出，相对路径按调用时的工作目录解释。

请把项目放在非同步本地目录：启用文件同步的“文稿”或“桌面”可能反复添加破坏裸 `.app` 严格签名校验的 Finder 元数据；分享时只复制 ZIP/DMG。项目文件布局和迁移验证见 [PROJECT-LAYOUT.md](PROJECT-LAYOUT.md)。安装后的应用仍从自身包内读取工具，不依赖开发项目目录；系统偏好、ADB 授权密钥和钥匙串保持标准位置。

`run_session_checks.sh` 使用独立的模拟子进程检查多设备启动、停止、失败、超时、重试及退出清理，还覆盖 C 标准输出缓冲、PTY 断开、后代进程持有日志描述符和快速重试，不连接真实手机，也不产生真实投屏画面。它不依赖 XCTest；不能用这些模拟检查替代两台以上真机同时显示画面的验收。测试中的模拟程序不会打入应用安装包。

`run_wireless_checks.sh` 检查原生 Android 二维码生成与解码、临时凭据保密、GUID 身份匹配、扫码后的自动连接、轮询与取消、二维码过期、附近多设备隔离，以及原有地址校验和手动两步连接。它使用模拟 ADB、CoreImage 与无网络的本地子进程，不修改手机的无线调试设置，也不能代替真实手机扫码和无线画面验收。

普通构建和不带参数的打包仍标记为本地开发版。公开社区发行必须显式传 `--community`，它会验证上游运行时、携带完整许可声明并生成配套第三方源码归档。社区版通过 Sparkle Ed25519 保证更新来源及完整性，不提供 Apple 开发者身份认证；这两种签名作用不同。未来如有 Developer ID，可使用独立严格的公证发行流程。

发行与分享细节见 [`DISTRIBUTION.md`](DISTRIBUTION.md)，内置运行时校验值见 [`vendor/runtime-manifest.sha256`](vendor/runtime-manifest.sha256)。

## 应用图标

图标采用纯蓝底与白色横屏、竖屏轮廓，以两个屏幕的叠放表达手机投屏；不使用文字、屏幕内容、信号线或渐变。原生矢量绘制源为 `script/generate_icon.swift`，构建时生成 1024px PNG，再封装包含 16–1024px 各标准尺寸的 `AppIcon.icns`，无需外部图片或图标字体。

```zsh
swift script/generate_icon.swift --output outputs/branding/MirrorLinkIcon-minimal.png
```

图标必须在应用签名前生成。不要直接覆盖已签名应用包内的图标；需重新构建并验证完整签名，替换本机应用前保留旧版备份。

## GitHub 同步

源码仓库：[zhaozachary1-cpu/MirrorLink](https://github.com/zhaozachary1-cpu/MirrorLink)（公开）。包含应用源码、测试、图标生成器、构建/发行/更新脚本、文档、锁定依赖信息和 vendored scrcpy 运行时。后续源码迭代与经确认的正式发行复用此仓库，不另建发行仓库。

后续迭代完成验证后，可以执行：

```zsh
./script/sync_github.sh "描述本次版本变化"
```

脚本运行四组检查、检查远端冲突及常见凭据特征、提交所有允许的文件变化、推送 main 并核对远端 SHA；不强制推送，不发布 Release。新增文件仍需人工确认是否包含业务敏感信息，自动扫描不是完整的数据安全审计。安装包、构建缓存、临时日志和密钥不纳入 Git；正式安装包应通过单独的发行流程上传。

## 许可证

MirrorLink 自有代码和文档采用 [Apache License 2.0](LICENSE)，项目版权与归属声明见 [NOTICE](NOTICE)。许可证选择已由维护者于 2026-10-01 确认。

第三方组件保留各自的版权与许可证，具体来源、随包声明和核对边界见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。应用携带项目声明、scrcpy/Sparkle 完整许可和 `ThirdPartyLicenses/` 中的上游文本；社区 Release 还需同时提供对应第三方源码归档。项目许可证不替代第三方许可义务，也不代表 Apple 公证。
