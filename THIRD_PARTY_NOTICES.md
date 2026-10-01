# 第三方组件与许可说明

MirrorLink 自有代码和文档采用根目录 [LICENSE](LICENSE) 中的 Apache License 2.0；项目声明见 [NOTICE](NOTICE)。第三方源码、二进制、图片和框架保留各自的版权与许可证，不因本项目的许可证选择而改变。

本清单记录当前已核对的来源、声明位置和待办，不是对所有传递依赖及预编译二进制的完整许可审计。源码仓库公开不代表安装包已经具备面向公众发行的全部条件。

## scrcpy 4.1

- 上游：[Genymobile/scrcpy v4.1](https://github.com/Genymobile/scrcpy/tree/v4.1)。
- 本地运行时位于 `vendor/scrcpy/arm64/` 和 `vendor/scrcpy/x86_64/`；scrcpy 自身采用 Apache License 2.0。
- 两个目录中的原始 `LICENSE` 均予以保留，包含 Genymobile 和 Romain Vimont 的版权声明；没有替换为 MirrorLink 的版权信息。
- 构建脚本把该完整文本复制到应用的 `Contents/Resources/NOTICE-scrcpy.txt`。
- 随附的 ADB 及 scrcpy 链接的库并不因此全部成为 Apache-2.0 组件，其许可需要分别核对。

当前 arm64 运行时的 `scrcpy --version` 报告 SDL 3.4.12、libavcodec 62.28.102、libavformat 62.12.102、libavutil 60.26.102 和 libusb 1.0.30。这份运行时输出不是完整的软件物料清单，也不能证明 Intel 构建使用完全相同的依赖或构建选项。

公开分发预编译运行时前，应对照实际构建补齐 SDL、FFmpeg、libusb 及其传递依赖的许可文本、版权声明和适用的源码/重新链接材料。FFmpeg 的具体构建配置尚未完成核对，不能仅凭库名判定整个 scrcpy 二进制的许可义务。上游参考：[SDL 许可](https://www.libsdl.org/license.php)、[FFmpeg 法律与许可说明](https://ffmpeg.org/legal.html)、[libusb](https://github.com/libusb/libusb)。

## Android Debug Bridge（ADB）

- 来源项目：[Android SDK Platform-Tools](https://developer.android.com/tools/releases/platform-tools)。
- 当前内置二进制报告 `Android Debug Bridge version 1.0.41`、`Version 37.0.0-14910828`；文件位于两个架构的 `vendor/scrcpy/` 目录中。
- 两处 ADB 文件哈希相同；记录见 [运行时校验清单](vendor/runtime-manifest.sha256)。哈希用于核对文件身份，不替代许可声明。
- 当前仓库尚未收录与这份预编译 ADB 精确对应的完整 Platform-Tools 许可/NOTICE 集合。公开二进制发行前必须补齐并核对，不将该预编译文件整体标注为仅受 MirrorLink 的 Apache-2.0 许可证约束。

## Sparkle 2.10.0

- 上游：[sparkle-project/Sparkle 2.10.0](https://github.com/sparkle-project/Sparkle/tree/2.10.0)。
- `Package.swift` 固定版本为 2.10.0，`Package.resolved` 记录具体修订；框架由 SwiftPM 获取。
- Sparkle 主体采用 MIT 许可；上游完整 [LICENSE](https://github.com/sparkle-project/Sparkle/blob/2.10.0/LICENSE) 还包含 bsdiff/bspatch、sais-lite、orlp/ed25519、`SUSignatureVerifier.m` 的独立版权和许可声明。
- 构建脚本把依赖产物的整个 `LICENSE` 复制为 `Contents/Resources/NOTICE-Sparkle.txt`，保留 `EXTERNAL LICENSES` 部分，不只摘录首段 MIT 文本。

## 应用包内的声明

从本次修改开始，新构建应用的 `Contents/Resources/` 包含：

- `LICENSE`：MirrorLink 的完整 Apache-2.0 标准文本。
- `NOTICE`：MirrorLink 项目版权与归属说明。
- `THIRD_PARTY_NOTICES.md`：本清单及尚待完成的发行许可核对。
- `NOTICE-scrcpy.txt`：随运行时保留的完整 scrcpy 许可文本。
- `NOTICE-Sparkle.txt`：Sparkle 依赖产物中的完整许可文本及外部组件声明。

`script/build_and_run.sh --verify` 会逐字节比较上述随包文本与构建输入；该检查只证明已列文本没有漏装或被截断，不证明缺失的第三方声明已经补齐。既有安装包和本机已安装版本不会被此源码修改自动更新。
