# 镜连 MirrorLink 0.5.4 — 简洁连接与紧凑窗口 / Simpler Connections and Compact Windows（免费社区版）

版本 / Version：**0.5.4 / Build 17**。包含此前尚未公开的 0.5.3 无线发现修复。

- 主窗口默认缩至 640 × 420，压缩卡片留白；设备侧栏可折叠，多台设备可滚动查看。首次升级调整一次主窗口尺寸，之后保留手动调整。
- 无线连接默认发现附近手机。已授权设备点击“连接并投屏”；新手机点击“连接新手机”，再在 Android 的“无线调试 → 使用二维码配对设备”中扫码。“更多”保留手动连接与权限检查。
- 无线调试使用由当前应用管理的独立后台，避免沿用旧后台的异常权限状态。原生 Bonjour 发现配合 Google Platform-Tools 37.0.1，停用本机复现崩溃的 ADB 内置发现模块，不重启共享 ADB。
- 修复 V2520 扫码成功后因厂商未提供 GUID 属性而被误拦截的问题：保留 TLS 授权，并对认证服务标识、硬件身份和当前连接端点做受限核对。连接阶段失败可免重复扫码重试，不按同一 IP 或第一台设备猜测目标。
- 收到手机画面后自动关闭主页面和本次无线连接页。通过投屏窗口“更多 → 连接其他手机…”、Dock 或 ⌘0 可重新打开主页面，现有投屏继续运行。
- 连接后在主页面和投屏标题显示手机实际返回的品牌与型号，保留昵称；读取失败不阻止投屏，不猜测商品名。已实测的 vivo 默认桌面使用一键上滑打开应用列表，其他桌面保留标准指令和手动兜底。

**English:** A compact 640 × 420 main window has a collapsible sidebar and scrollable device details. Wireless Connection starts with nearby phones; connect an authorized phone directly, or choose Add a Phone and scan from Android's Wireless debugging QR-pairing screen. An app-owned wireless backend and native Bonjour discovery avoid the shared-backend problems reproduced on this Mac. Platform-Tools 37.0.1 is bundled; the crash-prone ADB discovery driver is disabled without restarting shared ADB. A narrowly checked identity fallback fixes V2520's missing GUID property after authenticated pairing. Video readiness closes the control pages; More → Connect Another Phone, the Dock, or ⌘0 reopens the main window. Phone brand and model are visible alongside custom names. The verified vivo launcher gets a one-click drawer gesture; other launchers retain the standard action and explicit fallback.

安装：下载本版完整 DMG 或 macOS-universal.zip，将 MirrorLink.app 拖入“应用程序”；不要使用源码或 update.zip 安装。旧版可从“镜连 → 检查更新…”获取，安装前结束录屏并确认保存，按提示停止投屏。Build 17 高于本机候选 Build 16，同一显示版本也可更新。

**免费社区版，没有 Apple Developer ID 签名或 Apple 公证。** 更新包与清单使用原有 Sparkle Ed25519 密钥签名。首次打开若仅提示无法验证开发者或检查恶意软件，确认官方来源并选择信任后，到“系统设置 → 隐私与安全 → 仍要打开”完成本机确认；若提示恶意软件、会损害电脑或已损坏，停止并核对来源与校验值。不要关闭 Gatekeeper 或移除隔离标记，受管理的 Mac 可能限制安装。

**Installation:** Use the complete DMG or macOS-universal.zip, then move MirrorLink.app to Applications. Existing users can choose Check for Updates. Finish and save recordings before installation. Build 17 also updates the local Build 16 candidate. This free community build is ad-hoc signed and is not Apple-notarized. Updates retain the existing Sparkle trust key. See README for Apple's first-open procedure; keep system security protections enabled.

已验证 V2520 单台真实无线连接、持续变化的桌面、Home 和抽屉操作，以及中英紧凑列表；未完成两台无线并行、长时间稳定性、Intel/macOS 13 真机或陌生 Mac 首次打开验收。无线与工具证据见 WIRELESS-QA.md、TOOLS-QA.md；发行及实际覆盖更新结果见 UPDATE-QA.md。

**Validation limits:** Single-phone wireless video and navigation, brand/model display, and the compact bilingual device list were verified. Two simultaneous wireless phones, long-duration stability, Intel/macOS 13 hardware, and first installation on another Mac remain unverified.

---

# 镜连 MirrorLink 0.5.3 — 原生无线发现 / Native Wireless Discovery

版本 / Version：**0.5.3 / Build 13**。

- 使用 macOS 原生 Bonjour 发现无线调试服务，并与 ADB 发现结果合并去重；ADB mDNS 后台为空或报错时仍能显示原生发现的手机。只解析手机主动广播的调试服务，不扫描 IP 网段。
- 内置 ADB 升级为 Google 官方 Platform-Tools 37.0.1，并固定官方归档与通用二进制哈希。实测 37.0.0 和 37.0.1 的内置 mDNS 线程均可能在本机崩溃，因此镜连新启动的 ADB 后台使用 `ADB_MDNS=0`，由原生 Bonjour 承担发现；不自动重启或修改已有共享后台。原有 scrcpy 运行时归档保留不变，新 ADB 的来源与许可单独核对。
- 统一用于“发现手机”、手动地址选择及扫码服务发现；关闭窗口或切换方式后停止本次浏览，取消后不发布旧结果。双栈服务优先使用 IPv4，IPv6 保留接口范围。
- 明确区分 USB 调试、无线调试和首次配对；发现页提供扫码、手动地址与本地网络权限设置入口。连接中的空列表不再误报未发现手机。
- 无法访问端口时提示检查本地网络权限及网络环境，不再统一误导为连接端口填写错误。已有手机授权、目标 GUID 校验、USB、多设备与安静工具栏保持原有流程。

**English:** Native macOS Bonjour discovery is merged with ADB results, so phones can appear even when the shared ADB mDNS cache is empty or fails. Bundled Platform-Tools 37.0.1 is pinned to Google's archive. Newly started ADB daemons use native discovery instead of ADB's crash-prone mDNS driver (`ADB_MDNS=0`); existing shared daemons are never restarted or reconfigured automatically. Discovery remains limited to advertised wireless debugging services. Recovery actions clarify first-time pairing and Local Network permission. No network permission reset or legacy TCP/5555 enablement is performed.

真机证据与剩余连接限制见 WIRELESS-QA.md。此版本号本身不代表已公开发布，公开安装包以 GitHub Releases 为准。

---

# 镜连 MirrorLink 0.5.2 — 安静的操作反馈 / Quiet Toolbar Feedback（免费社区版）

版本 / Version：**0.5.2 / Build 12**。

- 返回桌面、应用列表、截图、发送文件等普通操作不再自动弹出进度或成功提示，投屏画面保持无遮挡。
- 操作状态仍可在投屏窗口“更多 → 查看操作结果”主动查看；处理中保留忙碌图标和取消入口。已打开的状态面板继续更新。
- 修复错误提示关闭动画期间继续点击按钮，旧气泡被新操作状态重新打开的问题。
- 新的失败仍显示具体原因；APK 安装和录屏启停的必要确认保持不变。

**English:** Routine toolbar progress and successful results no longer open popovers automatically. Inspect status or cancel an operation from More. An already-open status panel continues to update. New failures still show their explanation; APK installation and recording confirmations are retained.

免费社区版，ad-hoc 签名，未经 Apple 公证；更新继续使用原有 Sparkle Ed25519 签名。

---

# 镜连 MirrorLink 0.5.1 — 投屏窗口工具栏 / Phone Window Toolbar（免费社区版）

版本 / Version：**0.5.1 / Build 11**。

- 返回桌面、应用列表、截图、录屏、发送文件与安装 APK 统一移到每台投屏窗口顶部；各窗口始终绑定自己的手机，主客户端保留设备设置、自检和反馈。
- 发送文件：选择后直接发送到该手机的 `Download/MirrorLink`。保留安全可读的文件名并加短编号防止覆盖；选择 APK 会转入安装确认，无需退出重选。
- 安装 APK：选包后仅需一次确认，明确显示文件名和目标手机；不覆盖已安装应用。演示模式禁用发送与安装。处理中可在窗口内查看状态及取消，完成或失败时显示结果。
- 录屏选择与确认在手机窗口中完成；启停仍会短暂重启本台投屏，录制时图标变为红色停止按钮。截图/录屏完成后可从“更多投屏操作”打开最近文件。
- 原生 Cocoa 工具栏直接编译进锁定版本 scrcpy；不依赖悬浮窗或辅助功能权限，不改变视频画质参数。自有按钮提示和状态支持中英文切换。

**English:** Home, App Drawer, Screenshot, Recording, Send File, and Install APK are now in each phone window's native toolbar. File selection sends directly to that phone; APK selection opens one explicit installation confirmation. Readable filenames include a unique prefix to avoid overwrites. Status, cancellation and results stay in the phone window. Presentation mode blocks navigation and device writes. Recording confirmation/save sheets belong to the phone window; starting/stopping recording still restarts only that phone's session briefly.

This remains a free, ad-hoc signed community build, not Apple notarized. Appcast and update archives use the existing Sparkle signing key. See README for installation and TOOLS-QA.md / UPDATE-QA.md for verified evidence and limitations. Some phone launchers do not provide an app drawer; sending the command is not proof that it opened.

---

# 镜连 MirrorLink 0.5.0 — 设备偏好与实用工具 / Device Preferences and Tools（免费社区版）

版本 / Version：**0.5.0 / Build 10**。新增每台设备的设置与工具，保留中英文界面、原生画质档位、无线配对、多设备独立会话和签名更新。

## 本次新增

- **设备偏好与常用设备**：保存昵称、收藏、独立画质或跟随全局、声音、自动恢复、演示模式、全屏与置顶。离线收藏仍可查看和编辑。只有已确认的硬件身份可以持久记忆；未确认身份的无线地址不能收藏或自动恢复。重置/忘记只清除镜连偏好，不撤销 ADB 配对或删除手机数据。
- **截图与录屏**：截图保存原始 PNG，随后可复制或在访达中查看；录屏保存手机传来的视频流为 MP4。有音频的录屏使用 AAC，普通投屏保留默认音频编码，静音录屏不启动音频编码器。开始录屏会启动或重启该台投屏，结束录屏会保存并重新打开普通投屏，操作前需要确认，其他设备不受影响。只有收到完成信号并验证封装后才显示已保存；异常文件不会冒充完整录屏。
- **手机导航**：每台设备提供“返回桌面”和“应用列表”，也可明确选择上滑兼容操作。部分 Android 桌面没有独立应用抽屉，标准指令与上滑都可能无效果，可直接在手机桌面查找应用。指令发送成功不等于已验证手机打开了抽屉，镜连不会更改手机桌面设置。
- **连接自检与自动恢复**：自检检查内置工具、所选设备连接/授权、Android 版本、型号与屏幕尺寸，并显示处理建议。主动开启自动恢复后，意外断线时最多检查 3 次；只有原已授权硬件身份以原连接方式（USB/Wi-Fi）、原 ADB socket 重新出现在 ready 列表中，才重启投屏。可以取消；手动停止、正常关闭投屏窗口和退出应用会取消恢复。不会主动重新连接网络、重新配对、切换连接方式或猜测另一台手机。
- **演示与窗口**：演示模式禁用手机控制、导航、文件写入和剪贴板自动同步，并隐藏界面及窗口标题中的设备序列号。关闭偏好后，正在运行的只读会话仍需重启才恢复控制。全屏、置顶及自动/并排/网格排列在下次启动相应窗口时应用，不移动现有窗口。
- **文件工具**：显式选择文件后发送至该手机的 `Download/MirrorLink` 文件夹，单个文件最大 2 GB。APK 使用独立选择与确认入口，不覆盖已安装应用，冲突时安装失败。取消传输可能在手机留下部分文件；取消安装只是停止等待，不承诺撤销手机已执行的安装。
- **本地反馈导出**：先预览受限、脱敏的版本/设备/会话信息，再保存 ZIP。默认没有原始日志或屏幕附件，不自动发送。附件只能由用户明确选择：最多 8 个普通图片/视频，单个不超过 512 MB、总计不超过 1 GB，不接受符号链接；附件画面和元数据不会自动脱敏。
- **保存位置与语言**：设置中可选择并打开保存目录。截图直接保存到此处，录屏和反馈导出默认从此目录开始选择；更改设置不会移动已有文件。新增界面支持简体中文与 English。

演示模式不会遮挡手机上的通知、密码或私人内容，截图和录屏也不绕过系统保护。连接自检不是实时画质监控，不测量实际码率、帧率或温度。本版保留原生超清/原生流畅/低负载兼容三档及分辨率下降提示，不承诺所有手机和网络都能长期达到目标码率、帧率或稳定超清。

## What's new in 0.5.0

- **Device preferences and favorites:** Save a nickname, favorite, individual or global quality, audio, reconnect, presentation, full-screen, and always-on-top settings. Offline favorites remain editable. Persistent settings require a verified hardware identity; an unidentified wireless address cannot become a favorite or recovery target. Resetting or forgetting settings does not revoke ADB pairing or delete phone data.
- **Screenshots and recordings:** Save original PNG screenshots, copy them, or reveal them in Finder. Record the incoming video stream as MP4. Recordings with audio use AAC; ordinary mirroring keeps its default audio codec, and silent recordings do not start an audio encoder. Starting recording starts or restarts only that device; stopping recording saves it and reopens ordinary mirroring, after confirmation. Other devices are unaffected. A recording is shown as saved only after completion and container checks; interrupted files are not reported as complete.
- **Phone navigation:** Each device has Home and App Drawer controls, plus an explicit upward-swipe alternative. Some Android launchers have no separate app drawer, so both methods may have no effect; look for apps on the phone's home screen instead. Sending a command does not prove the drawer appeared, and MirrorLink does not change launcher settings.
- **Connection checks and recovery:** Inspect local tools, device connection/authorization, Android version, model, and screen size. Optional recovery checks at most three times after an unexpected disconnect. It resumes mirroring only when the same authorized hardware identity reappears as ready, using the original USB/Wi-Fi transport and ADB socket. Manual stop, normal mirror-window closure, and app exit cancel recovery. It does not actively reconnect network endpoints, re-pair, switch transports, or guess another phone.
- **Presentation and windows:** Presentation mode disables phone control, navigation, file writes, and automatic clipboard sync, and hides device serial numbers in the interface and titles. Turning the preference off does not unlock an existing read-only session until it restarts. Full-screen, always-on-top, and automatic/side-by-side/grid layouts apply when sessions start; existing windows are not rearranged.
- **File tools:** Explicitly selected files go to the phone's `Download/MirrorLink` folder, with a 2 GB limit per file. APK installation has its own selection and confirmation and does not overwrite installed apps. Canceling a transfer may leave a partial file; canceling installation stops waiting and does not promise to undo phone-side work.
- **Local feedback export:** Preview redacted, limited version/device/session information before saving a ZIP. Raw logs and screen attachments are excluded by default; nothing is sent automatically. Explicitly selected attachments are limited to eight regular images/videos, 512 MB each and 1 GB total, with no symbolic links. Attachment images and metadata are not redacted.
- **Save location and language:** Choose and open a save folder in Settings. Screenshots save there; recording and feedback dialogs start there and allow another location. Existing files are not moved. New controls support English and Simplified Chinese.

Presentation mode does not conceal phone notifications or private content, and capture tools do not bypass protected content. Connection checks do not measure live bitrate, frame rate, or temperature. The existing native-resolution quality profiles and resolution warnings remain; target bitrate/frame rate and sustained clarity are not guaranteed on every device or network.

## 0.5.0 安装与更新 / Installation and updates

完整安装包命名为 `MirrorLink-0.5.0-macOS-universal.dmg` 和 `MirrorLink-0.5.0-macOS-universal.zip`，二选一，打开或解压后将 `MirrorLink.app` 拖入“应用程序”。不要用 Source code 或更新专用 ZIP 安装。覆盖旧版前停止投屏、取消等待恢复，确认录屏已保存，⌘Q 退出并保留旧版备份。需要 macOS 13+；Universal 包包含 Apple Silicon 与 Intel 架构，手机需为已授权 Android，无线配对需要 Android 11+。不支持 iPhone 或 Windows。

Use either the complete DMG or ZIP named above, then move **MirrorLink.app** to **Applications**. Do not use source archives or the update-only ZIP as an installer. Before replacing an existing app, stop mirroring/recovery, confirm recordings are saved, quit with **⌘Q**, and keep a backup. Requires **macOS 13+** and an authorized Android phone; wireless pairing requires **Android 11+**. Universal binaries include Apple Silicon and Intel. This is not an iPhone or Windows client.

**免费社区版没有 Apple Developer ID 签名或 Apple 公证。** 应用使用 ad-hoc 完整性签名，更新包和清单继续使用原有 Sparkle Ed25519 密钥验证。首次打开流程与系统警告的区别见 [README 安装说明](README.md#首次打开的-macos-安全提示)。不要关闭系统安全检查或移除下载隔离标记；受管理 Mac 可能无法安装。

**This community build is not Developer ID signed or notarized by Apple.** It uses an ad-hoc integrity signature and the existing Sparkle Ed25519 key for signed updates. Follow the [README installation guidance](README.md#english-quick-start) for first-launch security messages. Keep system security checks enabled and do not remove quarantine attributes. Managed Macs may prohibit installation.

Build 10 高于 0.4.4 的 Build 9，但只有公开了完整安装包、更新包与签名清单后，已有更新器才能获取本版。相同 Build 10 的本地预览包不触发同版本升级，需要时手动安装完整社区包。源码版本号不等于已发布，公开资产及更新验证状态以 [UPDATE-QA.md](UPDATE-QA.md) 为准。

Build 10 is newer than 0.4.4 / Build 9, but in-app delivery requires the release assets and signed feed to be published. A local preview already on Build 10 does not receive a same-build update; install the complete community package manually if needed. Source version numbers are not proof of publication. See [UPDATE-QA.md](UPDATE-QA.md) for release and upgrade evidence.

## 0.5.0 验证边界 / Validation scope

设备工具、偏好、恢复、录屏与 UI 的检查结果和本次真机证据分别记录在 [TOOLS-QA.md](TOOLS-QA.md)、[QUALITY-QA.md](QUALITY-QA.md)、[LOCALIZATION-QA.md](LOCALIZATION-QA.md) 与 [UPDATE-QA.md](UPDATE-QA.md)。模拟子进程只能证明相应逻辑路径；构建、截图文件或验签也不能替代多台真机实际画面、长时间无线/动态画质、陌生 Mac、Intel 真机或完整应用内升级验收。本节不沿用旧版测试数量作为本次复验结果。

See the linked QA records for this version's device tools, preferences, recovery, recording, UI, and real-device evidence. Simulated processes establish only the exercised logic paths. Builds, screenshot files, and signature checks do not substitute for multi-phone visual checks, prolonged wireless/dynamic-content tests, unfamiliar Macs, Intel hardware, or a complete in-app upgrade. Historical test counts below are not current-version results.

## 历史：0.4.4 — 中英文界面 / English and Chinese（免费社区版）

版本 / Version：**0.4.4 / Build 9**。本次新增应用界面本地化，保留现有画质、无线配对、多设备会话和更新安全机制。

- 支持简体中文与 English，默认跟随系统；在 **“镜连 → 设置…”（⌘,）→“语言 / Language”** 选择“跟随系统 / System”、“简体中文”或“English”，选择会保存。
- 覆盖主窗口、设备状态、画质控制、设置、无线扫码/发现/手动连接、帮助提示和应用自身更新文案。切换时即时刷新应用界面，保留设备选择、输入内容和活动投屏，不通过重建界面或重启会话实现语言切换。
- 已有 scrcpy 窗口标题在下次启动对应会话时使用新语言。macOS 原生窗口标题、菜单和 Sparkle 更新弹窗可能需要应用下次启动后切换；系统及辅助进程弹窗可能遵循 macOS 语言。
- 手机名称、序列号、发现服务、地址、历史日志和第三方原始错误保持原文，便于排查；不将外部文本强制翻译。
- 将中英文文案分别收纳到 `zh-Hans.lproj` 和 `en.lproj` 资源目录，并在 README 增加 English Quick Start 与语言切换说明。

### 0.4.4 English summary

MirrorLink now supports **English and Simplified Chinese**. Open **MirrorLink → Settings…** (**⌘,**), find **“语言 / Language”**, and choose **English**, **简体中文**, or **跟随系统 / System**. The choice is saved. MirrorLink’s interface updates immediately without interrupting active sessions or clearing device selections and connection fields.

Existing scrcpy window titles switch when their next session starts. Native window titles, menus, and Sparkle update dialogs may need an app relaunch; macOS and helper dialogs can follow the system language. Device names, existing logs, and third-party error details remain unchanged. The existing video quality profiles, wireless pairing, multi-device isolation, and signed-update verification are preserved.

### 0.4.4 下载与安装 / Installation

完整安装文件为 `MirrorLink-0.4.4-macOS-universal.dmg` 或 `MirrorLink-0.4.4-macOS-universal.zip`，二选一，打开或解压后将 `MirrorLink.app` 拖入“应用程序”。覆盖旧版前停止投屏、⌘Q 退出并保留备份；不要使用 Source code 或更新专用 ZIP 作为安装包。需要 macOS 13+；支持 Android USB 调试与 Android 11+ 无线调试配对，不支持 iPhone 或 Windows。

Download the complete DMG or ZIP, open it, and move **MirrorLink.app** to **Applications**. Quit the existing app with **⌘Q** and keep a backup before replacing it. Requires **macOS 13+** and an authorized Android phone; wireless pairing requires **Android 11+** with Wireless debugging. This installer is not for Windows or iPhone mirroring.

**免费社区版仍未经 Apple Developer ID 签名或 Apple 公证。** 只有 ad-hoc 完整性签名，更新包与清单继续使用镜连原有 Sparkle Ed25519 签名。首次打开若仅提示无法验证开发者/无法检查恶意软件，确认官方来源并决定信任后，先尝试打开，再到“系统设置 → 隐私与安全 → 仍要打开”在本机确认。若提示包含恶意软件、将损害电脑或已损坏，请停止并核对来源与文件校验值。不要关闭 Gatekeeper 或移除隔离标记；受管理 Mac 可能禁止安装。

**This community build is not Developer ID signed or notarized by Apple.** It uses an ad-hoc integrity signature and MirrorLink’s existing signed-update verification. If macOS only reports an unverified developer or inability to check for malicious software, verify the official source, choose to trust it, attempt to open it once, then use **System Settings → Privacy & Security → Open Anyway**. Stop if macOS reports malware, damage to your computer, or a damaged app, and verify the download. Keep system security checks enabled; do not remove quarantine attributes. Managed Macs may not allow installation.

0.4.4 的 Build 9 高于 0.4.3 的 Build 8，安装包与签名清单公开后可由已有更新器检查获取。同为 Build 9 的本地预览包不构成版本升级，需要时手动安装完整社区包。

### 0.4.4 验证边界 / Validation

本次核心检查、**74 项会话检查、137 项无线检查、28 项更新策略检查及 1,434 项本地化断言**通过，双架构构建与完整签名校验通过。本机原生窗口已验证中英文切换、设置持久化、主窗口与设置排版、手动表单保留和已有无线发现提示更新；修复了英文侧栏说明截断。活动投屏期间的切换由模拟会话覆盖，未作为新增真机验收。记录见 [LOCALIZATION-QA.md](LOCALIZATION-QA.md) 与 [UPDATE-QA.md](UPDATE-QA.md)。此前画质、无线与发行验收限制继续适用。

Core checks, **74 session checks, 137 wireless checks, 28 update-policy checks, and 1,434 localization assertions** passed, as did universal builds and strict code-signature verification. Native-window checks verified language switching, saved preferences after relaunch, English layout, retained manual form input, and existing discovery messages. Active-session preservation was tested with simulated processes; this is not new real-device or full in-app upgrade acceptance.

## 历史：0.4.3 — 原生画质与持续投屏优化（免费社区版）

版本：0.4.3 / Build 8。相较 0.4.2：

- 新增三个可保存的画质档位：默认“原生超清”（原生尺寸、目标 24 Mbps、最高 30 fps）；“原生流畅”（原生尺寸、目标 24 Mbps、最高 60 fps）；“低负载兼容”（长边最高 1920 px、目标 12 Mbps、最高 30 fps）。均使用 H.264。
- 关闭因编码失败而自动降低分辨率的回退，避免隐藏的降清晰度启动。若手机无法完成请求，可查看错误后主动选择兼容档。
- 无线投屏增加 80 ms 视频缓冲平滑短时抖动，USB 使用 0 ms；无线缓冲会带来少量额外延迟，长时间使用仍建议 USB。
- 每台活动设备显示实际收到的画面尺寸与本次配置快照；尺寸减少时显示提示，正常旋转不会被误报。码率/帧率显示的是目标与上限，不是实测监控值。
- 在主窗口和设置中选择画质；新选择在下次开始时生效，也可对单台点击“重新投屏”立即应用，保留其他设备的独立会话。
- 保留 0.4.2 的误超时修复、主窗口重开、无线配对、多设备隔离和原有更新签名验证。

“超清”保留手机原生细节，不将低分辨率源画面放大冒充 4K，也不承诺所有设备在任何网络、温度和并行负载下持续达到目标码率/帧率。静止内容少有新帧并不等于程序卡住。

### 0.4.3 下载与安装

本版完整安装文件为 `MirrorLink-0.4.3-macOS-universal.dmg` 与 `MirrorLink-0.4.3-macOS-universal.zip`，二选一，打开或解压后将 `MirrorLink.app` 拖入“应用程序”。覆盖旧版前先停止投屏、⌘Q 退出并保留备份。不要将 Source code 或更新专用 ZIP 当作安装包。

本版需要 macOS 13+，包含 Apple Silicon 与 Intel 架构；USB 需要手机明确允许调试，无线需要 Android 11+ 无线调试配对。不支持 iPhone 或 Windows。

**这是未经 Apple Developer ID 签名或 Apple 公证的免费社区版。** 若首次打开仅提示无法验证开发者/无法检查恶意软件，确认官方来源且决定信任后，先尝试打开一次，再到“系统设置 → 隐私与安全 → 仍要打开”在本机确认。若提示恶意软件、会损害电脑或已损坏，应停止安装并核对来源。不要关闭 Gatekeeper 或移除隔离标记；受管理 Mac 可能禁止安装。

更新仍使用原有 Sparkle Ed25519 密钥。0.3.1 及之后版本可主动检查更新；0.4.2 / Build 7 低于本版 Build 8。同为 0.4.3 / Build 8 的本地预览包不构成版本升级，需要时手动安装本版完整社区包。安装包和签名清单公开后更新器才能提供本版。

### 0.4.3 验证边界

核心与会话回归检查已覆盖档位参数、配置保存、会话快照、分辨率提示和单设备重新投屏。各组最终检查数量、构建及发布验证状态以 [QUALITY-QA.md](QUALITY-QA.md) 和 [UPDATE-QA.md](UPDATE-QA.md) 为准，不沿用旧版数字充当本次复验结果。

单台 OnePlus PGZ110 / Android 15 的 USB 测试中，原生超清档持续 180 秒，接收尺寸日志保持 1080 × 2412；原生流畅档 15 秒保持相同尺寸，兼容档 15 秒为 858 × 1920，结束后所属子进程正常回收。这些是日志和会话生命周期证据，原生画面与点击验收因界面检查工具连接失败尚未完成；也未完成数小时动态内容、无线、多设备、陌生 Mac、Intel 真机与旧版完整应用内升级验收。观察期间热状态变化不能单独证明模糊的原因，本次并未复现和确证“越来越模糊”的唯一根因，也不宣称彻底消除了所有画质下降。

## 历史：0.4.2 — 投屏稳定性修复与无线连接（免费社区版）

版本：0.4.2 / Build 7。相较公开版 0.3.1，本次包含无线连接、扫码配对、极简图标以及以下修复：

- 修复 scrcpy 就绪日志缓冲引发的 25 秒误超时，避免正常投屏被镜连主动关闭。
- 改善退出日志排空和会话回收，避免残留状态影响重试；保留多设备独立启动、停止与隔离。
- 补充 Dock 重开主窗口处理，增加“投屏 → 显示主窗口”（⌘0）；关闭主控制窗口不结束投屏，退出应用请用 ⌘Q。
- Android 11+ 无线调试扫码配对、已授权手机发现和手动连接兜底；同 Wi-Fi 不是授权，不会静默接管手机。
- README 新增醒目的安装注意事项、文件选择表、旧版覆盖步骤和社区版安全提示。

### 0.4.2 下载与安装

普通用户下载 `MirrorLink-0.4.2-macOS-universal.dmg` 或 `MirrorLink-0.4.2-macOS-universal.zip`，将 `MirrorLink.app` 拖入“应用程序”。不要下载 Source code 或更新专用 ZIP 来安装。覆盖旧版前先停止投屏、⌘Q 退出并保留备份。

**本版本没有 Apple Developer ID 签名或 Apple 公证。** 若首次打开仅提示无法验证开发者/无法检查恶意软件，确认官方来源且决定信任后，先尝试打开一次，再到“系统设置 → 隐私与安全 → 仍要打开”，在本机确认。若提示恶意软件、会损害电脑或已损坏，应停止安装并核对来源。不要关闭 Gatekeeper 或移除隔离标记。受管理 Mac 可能禁止安装。

需要 macOS 13+；包含 Apple Silicon 和 Intel 架构。USB 需要 Android 手机明确允许调试；无线需要 Android 11+ 无线调试，同网首次扫码必须使用手机开发者选项里的入口，不是微信/普通相机。不支持 iPhone 或 Windows。

更新清单与更新包使用原有 Sparkle Ed25519 密钥签名。0.3.1 用户可主动检查更新；与本版同为 Build 7 的本地预览包不会触发同版本升级，需要时手动安装完整包。详细安装说明见仓库 README。

### 0.4.2 验证边界

0.4.2 修复已通过核心检查、40 项会话模拟、127 项无线模拟、28 项更新策略检查及单台 USB 真机 75 秒观察和两次重启。Dock 点击、无线真机、多设备真实画面、陌生 Mac、Intel 真机和旧版完整应用内升级尚未全部验收。签名/哈希验证不是实际安装成功的替代；发布验证记录见仓库 UPDATE-QA.md。

## 历史：0.4.1 — 扫码配对与自动发现（未单独发行，已合入 0.4.2）

- 首次连接默认使用 Android 原生无线调试二维码，无需手填 IP、端口和六位配对码。
- 电脑主动发现扫码的手机，配对后自动找到其连接服务，并核对配对返回的 GUID 与目标手机身份，再请求开始投屏；不会按同 IP 或第一台就绪手机猜测目标。
- 新增“发现手机”入口，每 4 秒刷新；对已授权的手机一键连接并投屏，自动刷新时保持列表稳定。
- 保留“手动连接”的原有两步流程，适配没有扫码入口或网络发现不可用的情况。
- 二维码本机生成、120 秒有效、一次性使用。临时密码不写入进程参数、日志、设置或剪贴板。关闭、切换方式和停止均取消待执行的自动投屏；已完成的 ADB 授权不会被擅自撤销。
- 保留现有图标、双架构、macOS 13 最低版本、多设备会话与安全更新逻辑。

同一 Wi-Fi 不等于授权：首次仍需在手机“无线调试”中扫码，不支持静默接管手机。真实手机扫码、原生 UI 和无线画面的证据边界见仓库 WIRELESS-QA.md。

## 历史：0.4.0 — 同 Wi-Fi 无线投屏（未单独发行，已合入 0.4.2）

- 新增“无线连接”独立窗口、主窗口入口与 ⌘⇧W 快捷键。
- 支持 Android 11+ 无线调试的配对码授权、mDNS 服务发现与手动 IP:端口连接；配对、连接明确分为两步。
- 无线手机加入原有多设备会话，支持 USB / Wi-Fi 混用、独立开始和停止，单台失败不影响其他会话。
- 按硬件序列号合并同一手机的连接；临时身份读取失败不会丢失已经识别的会话。正在运行的投屏不会被自动切换路线。
- 配对码不落盘、不写日志、不放入可见的进程参数。不会启用旧式 5555 端口、全局重启 ADB 或修改系统安全策略。
- 保留现有图标、macOS 13 最低版本、Sparkle 更新验证及多设备窗口。

无线端到端、原生界面与真实覆盖升级的验收状态见仓库 WIRELESS-QA.md；不能以模拟测试或构建通过替代这些验收。下方保留历史 0.3.1 说明。

## 镜连 0.3.1 — 免费社区版

- 接入现有 GitHub 仓库的签名更新源，可在应用内检查、下载、确认安装并重新启动。
- 设置中展示更新来源与社区版安全说明，保留多设备独立投屏和原有设置。
- 补齐 ADB 及内置库的完整许可声明，同版本提供对应的第三方源码包。

本版本为 ad-hoc 签名的免费社区版，**未经过 Apple Developer ID 签名或 Apple 公证**。Sparkle 更新包与更新清单仍必须通过镜连原有 Ed25519 公钥验证。

首次安装：解压 ZIP（或打开 DMG），将 MirrorLink.app 拖入“应用程序”。若系统提示无法验证开发者，先尝试打开一次，再到“系统设置 → 隐私与安全”找到该应用并选择“仍要打开”，按系统提示确认。只对你信任且从本项目官方 Releases 下载的副本执行此操作；若提示应用会损害电脑或含恶意软件，请停止安装，不要忽略告警。受单位管理的 Mac 可能不允许此操作。不要关闭 Gatekeeper 或删除隔离标记。

0.3.0 用户：在“设置 → 应用更新 → 设置更新地址”保存以下地址一次，然后检查更新。0.3.1 已内置此地址，无需重复配置。

```text
https://github.com/zhaozachary1-cpu/MirrorLink/releases/latest/download/appcast.xml
```

0.2.0 及更早版本需要手动安装一次含更新器的版本。需要 macOS 13+；包含 Apple Silicon 与 Intel 架构。Intel 真机、陌生 Mac 首次安装、投屏时延后安装的验证状态见仓库 UPDATE-QA.md，不以双架构构建替代实机验收。
