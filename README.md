# 镜连 MirrorLink

镜连是一个原生 macOS Android USB 投屏工具：它把官方 scrcpy v4.1 与 ADB 作为应用内置运行时，并用 SwiftUI 提供多设备选择、授权提示、并行投屏、独立开始/停止和诊断日志。

## 使用

1. 用 USB 线连接 Android 手机。
2. 在手机开发者选项中开启 USB 调试，解锁手机并允许此电脑调试。
3. 打开镜连，点击刷新设备；左侧勾选一台或多台状态为“已连接”的手机。
4. 点击“开始所选投屏”（快捷键 ⌘↩）。每台手机会在独立的 scrcpy 窗口中打开；窗口标题包含型号和完整设备序列号，便于区分同型号手机。某一台启动失败不会影响其他手机。
5. 可以在右侧对单台设备单独重试或停止，也可以使用“停止全部”关闭本次由镜连启动的所有窗口。

取消勾选或“清空选择”只改变下一次批量启动的对象，不会停止已在投屏的手机；这些设备仍保留单独的停止入口。断开后重新连接不会自动启动投屏，需要再次点击开始。退出镜连会停止本应用启动的全部投屏，不会关闭其他软件启动的 scrcpy 窗口。

0.3.0 支持 macOS 13+ 与 Android USB 多设备投屏，不包含 iPhone、无线投屏配置或 Windows 客户端。本版本不设置固定的并行台数上限；实际可流畅投屏的数量取决于 Mac 性能、USB 带宽、数据线和扩展坞供电，需按实际设备验证。

## 应用更新

0.3.0 新增主窗口更新按钮、应用菜单“检查更新…”和“设置 → 应用更新”，使用 Sparkle 2.10.0 验证签名、下载、替换原应用并重启。自动检查需用户主动开启，安装始终需要用户确认；如果仍有手机在投屏，会先确认是否停止。

当前没有上线公开更新下载地址，界面会明确提示“更新服务尚未发布”。发布者部署 HTTPS 更新源后，可在设置中保存其地址。应用只信任内置公钥对应的签名，不接受随下载源替换的公钥，不内置 GitHub 登录凭据。源码仓库已公开，但公开源码不等于已经发布安装包或签名更新源。

0.2.0 及更早版本没有更新器，需要先安装一次 0.3.0 或后续含更新器的版本。完整上线步骤与验证边界见 [UPDATES.md](UPDATES.md)。

## 构建

```zsh
./script/run_core_checks.sh
./script/run_session_checks.sh
./script/run_update_checks.sh
./script/build_and_run.sh --verify
./script/package_release.sh
```

构建脚本会生成 arm64 + x86_64 通用 `.app`，把 ADB、scrcpy、scrcpy-server 及 Sparkle.framework 复制进应用包，对嵌套辅助程序、框架、内置工具和完整应用包依次进行本地 ad-hoc 签名，并通过 macOS `open` 启动应用。`--verify` 会检查包结构、双架构和完整代码签名。应用包中的官方 scrcpy 运行时来源和哈希见 `vendor/scrcpy/` 与构建日志。

默认构建与发行目录分别为 `~/Library/Application Support/MirrorLink/Builds/` 和 `~/Library/Application Support/MirrorLink/Releases/`。已签名的裸 `.app` 不放在启用文件同步的“文稿”或“桌面”中，避免同步服务反复添加破坏严格签名校验的 Finder 元数据；分享时复制 ZIP/DMG 即可。可用 `--output-dir` 指定其他非同步目录。

`run_session_checks.sh` 使用独立的模拟子进程检查多设备启动、停止、失败、超时、重试及退出清理，不连接真实手机，也不产生真实投屏画面。它不依赖 XCTest；不能用这些模拟检查替代两台以上真机同时显示画面的验收。测试中的模拟程序不会打入应用安装包。

当前构建没有 Apple Developer ID 签名和公证，仅有本地 ad-hoc 代码签名。要面向不熟悉终端的用户分发，应使用 Apple Developer ID、Hardened Runtime 和公证服务完成正式发布；本地签名完整性校验通过不代表通过 Gatekeeper。

发行与分享细节见 [`DISTRIBUTION.md`](DISTRIBUTION.md)，内置运行时校验值见 [`vendor/runtime-manifest.sha256`](vendor/runtime-manifest.sha256)。

## GitHub 同步

源码仓库：[zhaozachary1-cpu/MirrorLink](https://github.com/zhaozachary1-cpu/MirrorLink)（公开）。包含应用源码、测试、图标生成器、构建/发行/更新脚本、文档、锁定依赖信息和 vendored scrcpy 运行时。后续源码迭代与经确认的正式发行复用此仓库，不另建发行仓库。

后续迭代完成验证后，可以执行：

```zsh
./script/sync_github.sh "描述本次版本变化"
```

脚本运行三组检查、检查远端冲突及常见凭据特征、提交所有允许的文件变化、推送 main 并核对远端 SHA；不强制推送，不发布 Release。新增文件仍需人工确认是否包含业务敏感信息，自动扫描不是完整的数据安全审计。安装包、构建缓存、临时日志和密钥不纳入 Git；正式安装包应通过单独的发行流程上传。

## 许可证状态

源码已公开，MirrorLink 自身的项目级开源许可证尚待维护者确认，目前根目录没有 `LICENSE`。不能将“可以查看源码”与“已选定开源许可证”混为一谈。

第三方组件保留各自许可证：内置 scrcpy 的 Apache License 2.0 文本位于 `vendor/scrcpy/<架构>/LICENSE`，Sparkle 的许可证随依赖提供并由构建脚本复制进应用。第三方许可证不自动覆盖本项目自身代码；正式发行时仍须保留并核对各组件的许可声明。
