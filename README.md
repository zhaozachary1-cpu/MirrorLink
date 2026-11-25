# 镜连 MirrorLink

[![一键下载安装包 — 镜连 macOS DMG](docs/assets/download-macos.svg)](https://github.com/zhaozachary1-cpu/MirrorLink/releases/download/v0.5.2/MirrorLink-0.5.2-macOS-universal.dmg)

**点击上方蓝色按钮，直接下载 0.5.2 安装包，无需进入 Assets 查找。**

下载后：**打开 DMG → 将 MirrorLink.app 拖入“应用程序” → 打开镜连**。按钮只负责下载，不会静默安装；浏览器可能按你的设置询问保存位置。

按钮未显示？[直接下载 DMG](https://github.com/zhaozachary1-cpu/MirrorLink/releases/download/v0.5.2/MirrorLink-0.5.2-macOS-universal.dmg) · [下载完整 ZIP](https://github.com/zhaozachary1-cpu/MirrorLink/releases/download/v0.5.2/MirrorLink-0.5.2-macOS-universal.zip) · [其他版本](https://github.com/zhaozachary1-cpu/MirrorLink/releases)

> 免费社区版未经 Apple 公证。首次打开可能需要手动允许，具体见[首次打开的 macOS 安全提示](#首次打开的-macos-安全提示)；不要关闭系统安全保护。

镜连是一个原生 macOS Android 投屏工具：它把官方 scrcpy v4.1 与 ADB 作为应用内置运行时，并用 SwiftUI 提供 USB / 同 Wi-Fi 无线连接、多设备选择、授权提示、并行投屏、独立开始/停止和诊断日志。

公开下载版本为 **0.5.2（Build 12）**：普通操作不再自动弹出进度或成功提示，错误与必要确认保留。将返回桌面、应用列表、截图、录屏、发送文件与安装 APK 移到每台投屏窗口顶部的原生工具栏。保留常用设备与独立设置、截图录屏、连接自检、受控断线恢复、启动时窗口布局、演示模式、文件工具和本地问题反馈包，以及手机“返回桌面 / 打开应用抽屉”快捷操作。保留简体中文与 English、三档画质、无线配对、多设备隔离和签名更新。实际可下载安装的版本以 [最新公开发行页](https://github.com/zhaozachary1-cpu/MirrorLink/releases/latest) 为准；功能与真机证据见 [TOOLS-QA.md](TOOLS-QA.md)，完整发布记录见 [UPDATE-QA.md](UPDATE-QA.md)。

## English Quick Start

> 最新源码为 **0.5.4 / Build 16**：主窗口默认缩至 640 × 420，卡片与侧栏更紧凑，多台设备可滚动查看。无线入口先发现附近手机，新手机再扫码；收到画面后自动关闭主页面，投屏窗口“更多 → 连接其他手机…”可重新打开。配对成功后可免扫码重试连接。无线连接改由当前应用管理专用后台，避免沿用旧后台的异常权限状态。连接后显示手机品牌与型号，并为已实测的 vivo 桌面自动使用上滑打开应用列表。候选版尚未公开，下载按钮仍对应公开版 0.5.2；实际验收边界见 [WIRELESS-QA.md](WIRELESS-QA.md)。Source is at 0.5.4 / Build 16 with a compact 640 × 420 main window, connected phone brands and models, and a verified vivo app-drawer action. Public downloads remain at 0.5.2 until release and upgrade validation is complete.

MirrorLink mirrors Android phones on a Mac over USB or authorized wireless debugging. It includes ADB and scrcpy; no Homebrew or separate tool installation is needed. Requires **macOS 13 or later**. The universal installer includes Apple Silicon and Intel binaries; Intel hardware acceptance testing remains incomplete. It does not support iPhone mirroring or Windows.

1. [Download MirrorLink 0.5.2 for macOS (DMG)](https://github.com/zhaozachary1-cpu/MirrorLink/releases/download/v0.5.2/MirrorLink-0.5.2-macOS-universal.dmg), open it, and drag **MirrorLink.app** to **Applications**. An alternative [complete ZIP](https://github.com/zhaozachary1-cpu/MirrorLink/releases/download/v0.5.2/MirrorLink-0.5.2-macOS-universal.zip) is available. Do not use “Source code” or the update-only ZIP as an installer. Before replacing an existing copy, stop mirroring, quit with **⌘Q**, and keep a backup.
2. Launch MirrorLink from Applications. Open **MirrorLink → Settings…** with **⌘,**, find the bilingual **“语言 / Language”** section at the top, and choose **English**. Chinese users can find the same command as **“镜连 → 设置…”**. The other choices are **简体中文** and **跟随系统 / System**.
3. For USB mirroring, enable **USB debugging** in your Android phone’s Developer options, connect it with a data cable, unlock it, and authorize this Mac on the phone. Click **Refresh Devices**, select the phone, then **Mirror Selected**.
4. For wireless mirroring, use an **Android 11+** phone with Wireless debugging on the same reachable Wi-Fi network. In 0.5.4, open **Wireless Connection**, connect an already paired nearby phone, or click **Add a Phone**. On the phone, open **Developer options → Wireless debugging → Pair device with QR code** and scan there. Manual Connection is under More. Being on the same network does not grant authorization. Public 0.5.2 uses the QR Pairing / Nearby / Manual tabs.

**This is a free community build with an ad-hoc integrity signature, not an Apple Developer ID signature or Apple notarization.** If macOS only says it cannot verify the developer or check the app for malicious software, confirm that you downloaded it from this official repository and choose to trust it, attempt to open it once, then use **System Settings → Privacy & Security → Open Anyway** and confirm locally. If the warning says the app contains malware, will damage your computer, or is damaged, stop and verify the source and file checksums. Keep Gatekeeper enabled and do not remove quarantine attributes. Managed Macs may prohibit installation. See [Apple’s official guidance](https://support.apple.com/102445).

Language changes update MirrorLink’s own interface without stopping active mirroring. Existing scrcpy window titles use the new language when their next session starts. Native window titles, menus, and Sparkle update dialogs may require an app relaunch; macOS and helper-process dialogs can follow the system language. Device names, existing diagnostic logs, and third-party error details remain as reported.

## 界面语言（0.4.4）

打开 **“镜连 → 设置…”（⌘,）→ 顶部“语言 / Language”**，选择 **跟随系统 / System、简体中文或 English**。选择会保存，跟随系统时按系统语言偏好选择已支持的中英文，均不匹配时使用 English。

切换会立即刷新镜连自身的界面文案，保留设备选择、连接输入和正在运行的投屏，不会重启会话。已经打开的 scrcpy 投屏窗口标题在下一次启动该会话时使用新语言。macOS 原生窗口标题、菜单和 Sparkle 更新对话框可能需要下次启动应用后切换；系统及辅助进程对话框可能继续遵循 macOS 的语言设置。

手机/服务名称、序列号、地址、已有诊断日志和第三方返回的原始错误不会被改写。中英文资源分别位于 `Sources/MirrorLinkApp/Resources/Localizations/zh-Hans.lproj/` 与 `en.lproj/`。本地化检查与尚未完成的原生界面验收见 [LOCALIZATION-QA.md](LOCALIZATION-QA.md)。

## 常用设备、演示与设备工具（0.5.2）

每台手机有独立的设置和工具，操作前请确认设备名称。返回桌面、应用列表、截图、开始/结束录屏、发送文件和安装 APK 六个按钮位于每台手机的投屏窗口顶部。按钮只操作该窗口对应的手机，鼠标停留可查看说明；“更多投屏操作”中提供上滑兼容方式、查看结果和打开最近文件。主客户端保留设备设置、自检与反馈，无需来回切换窗口操作。

0.5.4 / Build 15 起，已连接设备和投屏窗口显示手机实际返回的品牌与型号，例如 `vivo V2520`。自定义昵称仍保留，真实品牌型号同时可见；品牌读取失败不阻止投屏，也不会猜测商品名或改变设备身份。连接前的 Bonjour 服务名不能作为已认证的品牌型号。

| 功能 | 使用方式与边界 |
| --- | --- |
| 常用设备 | 设置昵称并收藏，保留每台设备的画质、声音、演示和自动恢复偏好。独立画质可选择继承全局。记忆设置不等于获得新授权，未确认身份的无线地址不能充当永久设备身份。 |
| 返回桌面 / 应用列表 | 对当前手机发送返回桌面或应用列表指令；已在 V2520 验证的 vivo 桌面自动使用上滑方式，按实际默认桌面组件识别，不按手机品牌猜测。其他桌面保留标准指令与显式上滑兜底。部分桌面没有独立抽屉，两种方式都可能无效果。发送成功不等于抽屉已打开；镜连不会更改手机桌面设置，演示只读模式不允许发送控制指令。 |
| 截图 | 从选定手机取得 PNG，保存后可复制或在 Finder 中显示。手机不需要先生成临时截图文件；截图不会自动上传。受系统保护的内容仍可能无法捕获。 |
| 录屏 | 使用手机传来的原视频流保存 MP4。开始或停止录制可能会重新打开该手机的投屏，界面会先说明；其他设备不受影响。正常收尾后才显示完成，异常中断的文件明确区分为未完成。 |
| 连接自检 | 检查本机工具、设备授权/在线状态、Android 版本和屏幕尺寸，结合会话状态查看处理建议。不把目标码率或帧率上限当作实测值。 |
| 自动恢复 | 主动开启后，意外断线时最多检查 3 次；仅当原已授权硬件身份、原连接方式（USB/Wi-Fi）和原 ADB socket 同时匹配，并重新出现在 ready 列表中，才重启投屏。可取消；主动停止、正常关闭投屏窗口或退出应用后不恢复。不会主动重新连接网络、重新配对、切换连接方式或猜测另一台手机。 |
| 窗口布局 | 自动位置、并排排列、网格排列，在下一次开始投屏时生效。现有投屏仍是独立窗口，不申请辅助功能权限来强制移动其他应用窗口。 |
| 演示模式 | 使用昵称或型号代替窗口标题中的设备编号，并禁用手机控制和剪贴板自动同步；可选择置顶或全屏。它不会自动遮挡手机通知、密码或最后一帧敏感内容。 |
| 声音与文件 | 每台设备可单独选择是否转发声音，修改在该台下一次启动时生效。在投屏窗口点击发送文件，选好后直接发送至该手机的 Download/MirrorLink 目录；保留可读文件名并加短编号避免覆盖。选到 APK 会进入一次安装确认，也可直接点击安装 APK 按钮。窗口内显示状态、取消及结果；不会覆盖已安装应用。 |
| 问题反馈包 | 先查看脱敏后的结构化设备、应用和会话信息，再选择是否加入截图/录像，导出本地 ZIP。默认不附带画面或原始日志，不自动发送给任何人。 |

截图和录像的保存位置可在设置中更改，也可打开文件夹查看。发送文件、截图、自检和导出期间会显示状态，并提供取消或明确结果。首次使用建议先连接一台手机确认操作，之后再扩展至多台。

**English:** Device settings now remember nicknames, favorites and individual quality/audio/presentation/reconnect preferences. **Home**, **App Drawer**, **Screenshot**, **Start/Stop Recording**, **Send File**, and **Install APK** now live in the native toolbar at the top of each phone's mirroring window. Each toolbar controls only its own phone. Connection checks and local feedback export remain in the main client. File transfer starts immediately after selection; an APK opens one explicit confirmation. Results and cancellation stay in the phone window. Recording changes may restart only the affected mirroring session after confirmation. Window layouts apply when sessions start. Some launchers have no separate app drawer, so both the standard command and the upward-swipe alternative may have no effect; look for apps on the phone's home screen instead. Sending a command does not prove the drawer opened, and MirrorLink does not change launcher settings. Presentation mode disables device control and clipboard synchronization, but does not conceal phone notifications. Feedback exports contain a previewable, redacted report by default; screenshots and videos are included only when explicitly selected.

Optional recovery checks at most three times after an unexpected disconnect. Mirroring resumes only when the same authorized hardware identity reappears as **ready**, using the original USB/Wi-Fi transport and ADB socket. It does not actively reconnect a network endpoint, re-pair, switch transports, or choose another phone. Canceling recovery, manually stopping, normally closing the mirror window, or quitting the app prevents further recovery.

## 下载、安装与注意事项（请先阅读）

### 系统与设备要求

- 电脑：macOS 13 或更新版本。Universal 包包含 Apple Silicon 和 Intel 架构，无需自行选择；Intel 真机仍未完成验收。
- 手机：Android；USB 投屏需要允许 USB 调试。无线连接需要 Android 11+、手机提供“无线调试”功能，并与 Mac 在可互通的同一 Wi-Fi 中。
- 不支持将此安装包用于 Windows 或 iPhone 投屏。无需另外安装 Homebrew、ADB 或 scrcpy。

### 选对下载文件

普通用户直接点击本页顶部蓝色按钮下载 DMG 即可；也可选择旁边的完整 ZIP 链接。需要查看全部文件时，再打开 [GitHub Releases 最新版](https://github.com/zhaozachary1-cpu/MirrorLink/releases/latest)，展开 **Assets**。**DMG 与完整 ZIP 任选一个，不需要重复下载**：

| 文件 | 用途 |
| --- | --- |
| `MirrorLink-0.5.2-macOS-universal.dmg` | 推荐给普通 Mac 用户；打开后拖拽安装 |
| `MirrorLink-0.5.2-macOS-universal.zip` | 完整安装包；先解压，再拖拽安装 |
| `MirrorLink-0.5.2-update.zip` / `appcast.xml` | 应用内更新专用；不要当作普通安装包转发 |
| `Source code (zip/tar.gz)` | 本项目源码，不是可双击安装的应用 |
| `MirrorLink-0.5.2-third-party-sources.tar.gz` | 第三方对应源码及许可材料，普通使用不需要下载 |
| `SHA256SUMS.txt` | 下载文件的 SHA-256 校验清单 |

以上文件名对应 0.5.2；将来发布新版时请选择同一 Release 中对应版本的文件。分享时发送官方 Release 链接、DMG 或完整 ZIP，不直接转发裸 `.app` 目录。

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
- 0.3.0 需按下方“应用更新”配置一次更新地址；0.2.0 及更早需手动安装。**同 Build 的本地预览包与社区包不构成版本升级**，例如同为 0.5.2 / Build 12 时，不应期待更新器再次提示；需要时手动安装对应的完整社区包。0.5.2 的 Build 12 高于 0.5.1 的 Build 11，但须在安装包与签名清单公开后才能通过更新器获取。更新前先结束录屏并确认保存，停止投屏与等待恢复，再按提示安装。
- 无线首次配对必须在手机“开发者选项 → 无线调试”中扫码，不是微信或普通相机。不要转发配对二维码、配对码或含设备标识的诊断日志；同一 Wi-Fi 不代表已经授权。
- 单台 USB 真机短时测试与模拟多设备/无线检查已有记录，但长时间动态画质、真实无线、多台手机画面、陌生 Mac 首次安装及旧版经应用内覆盖升级仍有未完成的验收。查看 [QUALITY-QA.md](QUALITY-QA.md)、[STABILITY-QA.md](STABILITY-QA.md)、[WIRELESS-QA.md](WIRELESS-QA.md) 和 [UPDATE-QA.md](UPDATE-QA.md)，不要把构建/验签成功理解为所有设备已验收。

## 画质与持续投屏（0.4.3）

在“设置 → 画质与稳定性”选择画质（0.5.4 起主页面不再重复显示配置）。默认使用“原生超清”，以保留手机细节并限制持续编码的帧率负载。三档均使用 H.264：

| 画质档位 | 画面尺寸请求 | 目标码率 | 帧率上限 | 适用场景 |
| --- | --- | --- | --- | --- |
| 原生超清（推荐） | 保留手机原生分辨率，不主动缩小 | 24 Mbps | 30 fps | 文字、工作内容和持续投屏 |
| 原生流畅 | 保留手机原生分辨率，不主动缩小 | 24 Mbps | 60 fps | 滑动和动态内容，手机与网络负载更高 |
| 低负载兼容 | 长边不超过 1920 px | 12 Mbps | 30 fps | 带宽不足、多设备或原生编码失败时，由用户主动选择 |

“超清”指保留手机输出的原生细节；手机源画面不是 4K 时，不会通过放大制造 4K 细节。码率与帧率是编码目标/上限，**不是实测值或持续达到该值的承诺**。静止页面可能少有新帧，低帧率日志本身不等于投屏卡住，仍需结合内容变化判断。

更改画质在下次开始时生效，正在运行的会话保持自己的配置。要立即应用，点击该设备的“重新投屏”；只重启这一台，其他投屏不受影响。设备列表展示本次配置与实际收到的画面尺寸，画面尺寸尚未到达时显示等待；若尺寸比本次初始画面缩小，会给出提示。正常旋转不被当作清晰度下降。

投屏关闭了 scrcpy 因编码失败而自动降低分辨率的回退，不会为了继续启动而悄悄选择低清尺寸。手机编码失败时请查看错误提示，必要时主动切换“低负载兼容”；手机自身显示设置或编码器仍可能影响实际尺寸。

无线连接使用 **80 ms 视频缓冲**平滑短时抖动，代价是少量额外延迟；USB 不增加该视频缓冲（0 ms）。长时间投屏建议优先使用 USB，以减少 Wi-Fi 波动；增加码率不能消除带宽不足或手机发热导致的卡顿。

本轮单台 USB 真机的原生档 180 秒观察期间，日志中的画面尺寸没有缩小；这尚不能替代数小时动态内容、无线链路及多设备的清晰度验收，也未确证此前“越来越模糊”的唯一原因。结果与待验收项见 [QUALITY-QA.md](QUALITY-QA.md)。

## 使用

### USB 投屏

1. 用 USB 线连接 Android 手机。
2. 在手机开发者选项中开启 USB 调试，解锁手机并允许此电脑调试。
3. 打开镜连，点击刷新设备；左侧勾选一台或多台状态为“已连接”的手机。
4. 点击“开始所选投屏”（快捷键 ⌘↩）。每台手机会在独立的 scrcpy 窗口中打开；普通模式的窗口标题使用昵称或型号和设备序列号，便于区分同型号手机，演示模式隐藏序列号。某一台启动失败不会影响其他手机。
5. 可以在右侧对单台设备单独重试或停止，也可以使用“停止全部”关闭本次由镜连启动的所有窗口。

取消勾选或“清空选择”只改变下一次批量启动的对象，不会停止已在投屏的手机；这些设备仍保留单独的停止入口。默认不会在断开重连后自动投屏；主动开启自动恢复后，已有投屏意外断线时最多检查 3 次，只有原已授权硬件身份以原连接方式、原 ADB socket 重新处于 ready 状态才恢复投屏，不主动执行网络重连。无线设备尚未重新就绪时，仍需在“无线连接”中手动连接或配对。退出镜连会取消恢复并停止本应用启动的全部投屏，不会关闭其他软件启动的 scrcpy 窗口。

0.5.4 起，收到手机画面后自动关闭主页面；通过无线入口连接时，也关闭该设备本次的配对页并把投屏窗口置前。启动失败时保留页面。关闭主页面不会退出镜连或停止现有投屏。可以点击投屏窗口“更多 → 连接其他手机…”、Dock 图标，或通过“投屏 → 显示主窗口”（⌘0）重新打开；退出应用仍使用 ⌘Q。

Build 16 主窗口默认 640 × 420，最小内容尺寸 560 × 360；设备侧栏可折叠，多台设备的详情可滚动。首次升级会将主窗口调整为紧凑尺寸一次，之后保留用户的手动调整，不改变手机投屏窗口尺寸。The main window uses a compact layout with a collapsible device sidebar and scrollable details. Its size is adjusted once on upgrade; later manual resizing is preserved.

### 同 Wi-Fi 无线投屏

需要 Android 11+ 且手机提供“无线调试”选项。首次配对不需要 USB 线，但仍须在手机上明确授权；仅加入同一 Wi-Fi 不会自动获得投屏权限。

1. Mac 和手机连接同一 Wi-Fi，在手机“开发者选项”中打开“无线调试”，按手机提示允许当前网络。
2. 打开镜连，点击工具栏的“无线连接”，也可选择菜单“投屏 → 无线连接…”（⌘⇧W）；没有已连接设备时，主页面也有“无线连接手机”按钮。
3. 0.5.4 默认发现附近手机。已配对的手机点“连接并投屏”；首次使用点“连接新手机”，再在手机“无线调试 → 使用二维码配对设备”中扫描电脑二维码。**不是微信或普通相机。** 无需手填 IP、端口或六位配对码；电脑匹配扫码服务与认证身份后请求投屏。公开版 0.5.2 使用“扫码配对 / 发现手机 / 手动连接”标签页。
4. 配对已成功、后续连接未完成时，点“重试连接，无需扫码”。关闭窗口或切换方式会取消本次自动连接；已配对的手机可重新在附近列表连接。附近列表每 4 秒刷新，发现服务不代表手机已授权。

**USB 调试与无线调试是两个独立开关。** 已经配对过的手机应使用“发现手机”，不必反复扫描二维码。0.5.3 起同时使用 macOS 原生 Bonjour 与 ADB 的发现结果，修复 ADB 的 mDNS 列表为空、同一网络中的手机实际存在却无法显示的问题。两条发现通道合并去重；镜连新启动的 ADB 后台使用 `ADB_MDNS=0` 避免本机复现的内置发现模块崩溃，由 Bonjour 继续发现手机。此配置不改变运行中的共享后台，不更改加密配对。配对码和连接端口仍严格分开处理，发现不会自动授权或连接其他手机。

手机不提供扫码入口时，使用“更多 → 手动连接 → 首次配对”：填写手机配对码弹窗中的 IP、配对端口和 6 位配对码。成功后回到手机“无线调试”的**主页面**，将该页 IP 和连接端口填入“连接手机”。**连接端口与配对端口用途不同。** 网络无法自动发现时，已配对的手机也可在这里手填连接地址。切换网络、重开无线调试或重启手机后端口可能变化，以手机当前显示为准。

每台手机单独配对后，可以同时投屏多台无线手机，也可以混用 USB 与 Wi-Fi。能取得硬件序列号时，同一手机的两种连接会合并为一个设备；正在运行的窗口不会被刷新或新连接偷偷切换。如果原窗口仍用 USB，请先停止该手机的投屏再开始，以切换到就绪的 Wi-Fi 连接。

发现不到手机时，可手动填入地址；检查手机是否仍开启无线调试、macOS 是否允许本地网络访问，以及访客 Wi-Fi、路由器设备隔离或 VPN 是否阻止互访。没有无线调试选项的机型继续使用 USB，本版本不会自动打开旧式 5555 端口或修改手机安全设置。

0.5.4 的“更多 → 检查本地网络权限”和扫码失败页提供权限入口。请检查 **系统设置 → 隐私与安全 → 本地网络 → MirrorLink**；部分系统需再点“本地网络”。已发现手机不代表端口可达：VPN、访客网络和设备隔离都可能阻止连接。无线调试使用由应用直接管理的调试进程与权限为 0700 的私有 Unix socket，不接管 USB 手机；正常退出镜连会关闭该进程，不重启共享 ADB。按照 [Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy) 在当前应用内先检查本地网络准备状态，并给初次权限决定留出等待时间；免费 ad-hoc 签名在 macOS 上仍存在身份跟踪限制，不能保证覆盖所有系统权限异常。镜连不会重置网络权限或关闭系统保护。

二维码在本机生成，是本次临时授权凭据，请勿分享或截图转发；每次生成都会更换，120 秒内有效，开始配对即隐藏。二维码密码和手动配对码仅在本次操作内存中使用，通过标准输入传给 ADB，不写入参数、日志、设置、剪贴板或 Git，不发送给外部二维码服务。连接须对应扫码认证的 GUID；部分手机不向调试命令提供 GUID 属性时，仅在其标准 GUID 与实际硬件序列号、唯一当前服务及连接地址全部一致时继续，无法核对仍停止自动投屏。关闭窗口、切换方式或停止操作会取消本次发现及自动连接；ADB 仍会维护已完成的配对授权，不会因此自动撤销，可在手机中忘记此电脑。仅在可信网络使用，用完可在手机关闭无线调试；停止镜连投屏不会擅自断开其他软件的 ADB 连接。

支持 macOS 13+，不包含 iPhone 或 Windows 客户端。不设置固定并行台数上限；实际流畅数量取决于 Mac 性能、Wi-Fi 质量、USB 带宽和手机编码能力。当前单台无线画面证据、模拟测试与尚未完成的首次扫码 / 多台真机验收分开记录在 [WIRELESS-QA.md](WIRELESS-QA.md)，不能将测试脚本通过等同于全部无线场景已经验收。

## 应用更新

通过应用菜单“检查更新…”或“设置 → 应用更新”，使用 Sparkle 2.10.0 验证签名、下载、替换原应用并重启。0.5.4 起移除主窗口重复的更新按钮。自动检查需用户主动开启，安装始终需要用户确认；如果仍有手机在投屏，会先确认是否停止。

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
./script/run_device_tools_checks.sh
./script/run_wireless_checks.sh
zsh ./script/run_wireless_backend_checks.sh
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
