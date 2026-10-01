# 第三方组件与许可说明

MirrorLink 自有代码和文档采用根目录 [LICENSE](LICENSE) 中的 Apache License 2.0，归属见 [NOTICE](NOTICE)。第三方源码、二进制、图片和框架保留各自版权与许可证，不被项目许可证重新许可。

## 固定运行时与证据

本项目使用 [Genymobile/scrcpy v4.1](https://github.com/Genymobile/scrcpy/tree/v4.1) 的原始 macOS arm64/x86_64 运行时。对应上游归档、两套内置文件及 Google Platform-Tools 37.0.0 的 ADB 已逐字节核对匹配。完整下载地址与 SHA-256 见 [vendor/third-party-sources.tsv](vendor/third-party-sources.tsv)，运行时文件清单见 [vendor/runtime-manifest.sha256](vendor/runtime-manifest.sha256)。构建封装会合并架构并重新签名，不改变上游源代码。

scrcpy 4.1 对应上游提交 `2926c06c5dc3064ae6d8db706f1a98a37cfcf3f0`。其 `release/build_macos.sh` 与 `app/deps/*.sh` 指明以下依赖、版本和静态构建选项；macOS FFmpeg 脚本未启用 GPL 或 nonfree。arm64 的 zlib 版本另通过实际二进制字符串核对，x86_64 动态使用 macOS 系统 zlib。

| 组件 | 版本 | 主要许可证与随附文本 |
| --- | --- | --- |
| scrcpy / server / 上游图像 | 4.1 | Apache-2.0，保留原始 LICENSE，随应用为 NOTICE-scrcpy.txt |
| ADB | 1.0.41 / 37.0.0-14910828 | Android 与各内置组件独立声明，完整 NOTICE-Android-Platform-Tools-37.0.0.txt |
| FFmpeg | 8.1.2 | LGPL-2.1-or-later（本构建配置），FFmpeg-COPYING.LGPLv2.1 与完整 LICENSE.md |
| SDL | 3.4.12 | zlib，SDL-LICENSE.txt |
| libusb | 1.0.30 | LGPL-2.1-or-later，libusb-COPYING |
| dav1d | 1.5.3 | BSD-2-Clause，dav1d-COPYING |
| zlib（arm64 静态依赖） | 1.3.2 | zlib，zlib-LICENSE |
| Sparkle | 2.10.0 | MIT 及 EXTERNAL LICENSES，完整 NOTICE-Sparkle.txt |

Platform-Tools 的原始完整 NOTICE 约 1.15 MB，涵盖 adb 以及 SDK 工具中的其他组件。保留全部内容，不能把整个文件只概括成 Apache-2.0；MirrorLink 只分发其中的 adb，不分发 fastboot 等其余工具。`Android-Platform-Tools-source.properties` 保留原始版本信息。

Sparkle 的 `Package.swift` 和 `Package.resolved` 锁定版本/提交；其完整许可证同时包括 bsdiff/bspatch、sais-lite、orlp/ed25519 和 SUSignatureVerifier.m 等外部声明。Apple 系统库/框架由 macOS 提供，不装入本应用。

## 对应源码与重新链接

公开社区 Release 必须与安装包一起提供 `MirrorLink-<version>-third-party-sources.tar.gz`，包含未修改的 scrcpy 完整源码、FFmpeg、SDL、libusb、dav1d、zlib 对应源码，以及许可、来源/哈希清单和构建说明。源码也包含静态链接应用的完整源和上游构建脚本，供修改库后重新编译/链接使用。详见 [vendor/licenses/README.md](vendor/licenses/README.md)。

本项目不对修改 LGPL 库或为调试此类修改进行逆向工程施加额外限制。修改应用内容将破坏原签名，应构建并本地签署自己的副本；自建版本不使用官方更新信任链。本机没有实际重新编译全部第三方依赖，不声称可逐字节复现上游二进制，也不把材料整理称作完整外部法律审计。重新配置/替换依赖时必须重新核查许可证和源码义务。

## 应用包内声明与可复核入口

`Contents/Resources/` 包含项目 LICENSE/NOTICE、本清单、NOTICE-scrcpy.txt、NOTICE-Sparkle.txt，及 `ThirdPartyLicenses/` 中的完整上游许可、版本信息、哈希与来源清单。`script/build_and_run.sh --verify` 检查随包文件；`script/prepare_third_party.sh` 验证下载材料并比对原始运行时。新社区包必须通过这些检查后才能生成公开更新源。

上游补充说明：[FFmpeg licensing](https://ffmpeg.org/legal.html)、[SDL license](https://www.libsdl.org/license.php)、[libusb](https://github.com/libusb/libusb)、[Android Platform-Tools](https://developer.android.com/tools/releases/platform-tools)。已安装旧版不会仅因本文件更新自动获得新声明，需要安装/更新至新构建。
