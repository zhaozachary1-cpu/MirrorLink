# MirrorLink 0.2.0 多设备投屏交付记录

验证日期：2026-10-01（Asia/Shanghai）  
版本：0.2.0 / Build 2  
结论：功能实现、本地构建、打包和安装已完成；真实多手机画面验收尚未完成。

## 本次功能

- 设备列表使用复选框，可选择多台已授权的 Android 手机，一次启动所选投屏。
- 每台手机有独立的 scrcpy 进程、设备序列号与 ADB 服务地址；窗口标题包含完整序列号。
- 可单独开始、停止和重试，也可停止本应用启动的全部投屏。
- 单台失败或退出不会主动结束其他会话；重复启动同一设备不会新增窗口。
- 取消勾选或断开连接后，已启动设备仍保留独立控制入口。
- 重新连接记住本次运行中的选择，但不会自动重新投屏。
- 退出应用只清理本应用拥有的会话，不会结束其他软件的 ADB 服务或 scrcpy。
- 不新增无线连接配置、iPhone 支持或 Windows 客户端；不承诺未经实测的最大并行台数。

## 已验证的内容

| 检查 | 结果与证据边界 |
| --- | --- |
| 基础解析与命令检查 | `./script/run_core_checks.sh` 通过。 |
| 多会话生命周期 | `./script/run_session_checks.sh` 的 27 项检查全部通过；使用模拟子进程，不连接手机、不生成真实视频。 |
| 双架构构建 | SwiftPM release arm64、x86_64 均构建成功；主程序、ADB、scrcpy 均通过双架构检查。未在 Intel Mac 上运行验收。 |
| 完整本地签名 | 内置工具逐一签名，再签应用包；`codesign --verify --deep --strict` 通过。签名类型为 ad-hoc，不是 Developer ID。 |
| ZIP | 实际解压后通过完整签名检查；应用文件与发行原件逐项比较一致。 |
| DMG | 镜像校验通过；只读挂载后应用签名有效，应用文件与发行原件逐项比较一致；完成后已卸载镜像。 |
| 本机安装 | `/Applications/MirrorLink.app` 已更新为 0.2.0，通过签名及文件一致性校验。使用 macOS `open` 启动，确认主进程持续运行。 |
| 图标 | 沿用项目中已有的“手机 → 电脑”图标，与本次前一个构建的图标字节一致；未修改 `script/generate_icon.swift`。已安装的旧 0.1.0 仍是 scrcpy 原图，故不以旧安装包图标作为一致性基准。 |
| 子进程清理 | 生命周期检查结束后没有残留模拟 scrcpy 进程；已有 ADB 服务仍在运行。 |

27 项检查涵盖：首次单机默认选择、清空选择后的刷新、并行启动、防重复、服务地址与序列号隔离、工具路径、同型号窗口区分、设备身份稳定、断开后的控制入口、单机停止、未授权设备跳过、故障隔离、重试、用户关闭、停止全部、重连、首帧等待超时、旧超时/强制停止回调不干扰新会话、UTF-8/尾部日志完整性、无响应进程回收、退出不影响无关进程，以及进程启动失败清理。

## 验证限制

1. 最终检查时，仅发现已有的本地 ADB 5037 监听；设备列表为空。没有完成两台以上真实手机同时出现画面、音频、控制、USB 带宽和稳定性的验证。
2. 原生界面检查工具返回 `Sky Computer Use native pipe closed before response`，包括对已安装应用的重试；未完成截图及真实界面点击检查。进程启动成功不等于界面交互或视频验收通过。
3. 本机仅有 Command Line Tools，`swift test` 无法解析 XCTest，未完成 XCTest 测试运行。上述 27 项检查使用独立 Swift 测试运行器执行，不把它描述为 XCTest 通过。
4. 发行包未进行 Developer ID 签名与 Apple 公证，不承诺其他 Mac 下载后无系统信任提示。未关闭 Gatekeeper，也未清除下载隔离标记。

## 打包排查与修复

旧构建脚本只留下主程序链接器签名，没有对完整应用包封装签名。本次增加内置工具到外层应用的签名顺序，以及构建、发行、解包各阶段的校验。

本机项目所在的同步目录会给裸 `.app` 反复添加 `com.apple.FinderInfo`，造成严格签名校验失败。默认构建和发行位置改到本地 `~/Library/Application Support/MirrorLink/`；只将 ZIP/DMG 复制回项目方便分享。对于生成应用根目录上的 Finder 元数据做了限定清理，未修改隔离标记或系统安全策略。

## 交付物与备份

- 已安装应用：`/Applications/MirrorLink.app`
- 原始发行目录：`/Users/zachary/Library/Application Support/MirrorLink/Releases/MirrorLink-0.2.0-20261001-105847/`
- 项目内分享包：`outputs/releases/MirrorLink-0.2.0-20261001-105847/`，包含 ZIP、DMG 与 SHA-256 发行清单。
- 旧版备份：`/Users/zachary/Library/Application Support/MirrorLink/Backups/MirrorLink-0.1.0-before-0.2.0-20261001.app`
- 测试日志：`outputs/qa/multidevice-20261001/checks.log`
- 最终打包日志：`outputs/qa/multidevice-20261001/package-local-release.log`
- 解包验证日志：`outputs/qa/multidevice-20261001/package-integrity.log`
- 安装记录：`outputs/qa/multidevice-20261001/install.log`
- 最后一次成功检查：`outputs/qa/multidevice-20261001/final-success.log`

## 连接真机后的待验收步骤

1. 连接至少两台 Android 手机，分别开启 USB 调试并允许此电脑。
2. 勾选两台，点击“开始所选投屏”，确认两个独立窗口都显示持续变化的真实画面，且窗口序列号分别对应设备。
3. 单独停止第一台，确认第二台仍显示画面并可操作；重新开始第一台，确认只增加一个窗口。
4. 取消勾选正在投屏的设备，确认其窗口继续显示且仍可在右侧停止。
5. 拔掉一台手机，确认另一台继续投屏；重新连接后应手动开始，不应自动新增窗口。
6. 检查未授权、离线和启动失败提示；故障恢复后用该设备的“重试”恢复。
7. 点击“停止全部”，再分别开始设备；最后退出镜连，确认所有自有会话关闭、无关软件的会话不受影响。
