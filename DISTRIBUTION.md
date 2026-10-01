# 镜连发行与分享说明

## 免费社区版

0.3.1 支持 `--community` 发行模式：应用为 ad-hoc 完整性签名，**没有 Developer ID 身份认证，也没有 Apple 公证**。应用内更新的清单和更新 ZIP 另以 Sparkle Ed25519 签名；私钥保留在发布机钥匙串，客户端只含原有公钥。

这解决“不购买 Apple 开发者会员也能分享和安全校验应用更新”的需求，但不承诺“任何 Mac 都能无提示打开”。首次打开需要用户判断是否信任来源；企业管理策略可能禁止例外。若将来需要更顺畅的公众首次安装体验，可再使用下方公证流程。

## 接收者安装

1. 从 [本项目 Releases](https://github.com/zhaozachary1-cpu/MirrorLink/releases) 下载完整 `macOS-universal.zip` 或 DMG；不要下载用于开发的源码 ZIP 或更新专用 ZIP。
2. 解压 ZIP 或打开 DMG，将 `MirrorLink.app` 拖入“应用程序”。内置 ADB、scrcpy 和服务器文件，无需安装 Homebrew。
3. 尝试打开镜连。如果系统仅提示无法验证开发者或无法检查恶意软件，确认副本来自本项目后，前往“系统设置 → 隐私与安全”，对镜连选择“仍要打开”，按系统要求完成确认。
4. 如提示应用含恶意软件、会损害电脑或已损坏，请停止安装、重新核对来源及校验值，不将此提示自动当作普通首次打开确认。受管理 Mac 没有允许按钮时，请联系其管理员。
5. USB 连接 Android 手机、开启并允许 USB 调试后，在镜连选择设备并投屏。后续使用菜单或设置中的“检查更新…”；仍需用户确认安装。

Apple 官方说明：[在 Mac 上安全地打开 App](https://support.apple.com/102445)。不要要求用户关闭 Gatekeeper、全局放宽安全设置或移除 quarantine。

## 发布者打包

```zsh
./script/run_core_checks.sh
./script/run_session_checks.sh
./script/run_update_checks.sh
./script/package_release.sh --community
```

显式社区模式会校验固定的上游归档哈希、比对内置运行时、补齐许可文件，构建 arm64 + x86_64 通用应用并依次签署嵌套代码，生成：

- `MirrorLink-<version>-macOS-universal.zip` / `.dmg`：完整分享包。
- `updates/MirrorLink-<version>-update.zip`：Sparkle 专用单应用包。
- `MirrorLink-<version>-third-party-sources.tar.gz`：scrcpy 及静态链接库的源码、许可证、上游版本/哈希和重新编译说明；须与二进制在同一 Release 提供。
- `SHA256SUMS.txt`：可公开的文件校验清单。生成 appcast 后脚本追加其校验值。
- `RELEASE-MANIFEST.txt`：含本机路径的本地构建记录，**不要原样上传**。

默认目录为 `~/Library/Application Support/MirrorLink/Releases/`。裸 `.app` 不放入 Documents/Desktop 的同步目录，以免同步服务附加 FinderInfo 破坏封装；可复制 ZIP/DMG 分享。只清理本次暂存副本的 FinderInfo，不删除下载隔离或其他安全属性。

不带 `--community` 的普通打包仍是 `local-preview`，不能误当社区发行。`--community` 与 `--sign` / `--notarize` 互斥；不使用 `--allow-local-test` 替代社区发布。完整更新源生成、上传和验收流程见 [UPDATES.md](UPDATES.md)。

## 可选：Developer ID 与 Apple 公证版

这是独立路线，不是免费社区版的前置条件。需要发布者自行取得有效 Developer ID Application 证书及对应私钥和公证凭据。不得借用第三方证书，不把私钥/密码写入仓库。

```zsh
xcrun notarytool store-credentials mirrorlink-notary
./script/package_release.sh \
  --sign "Developer ID Application: 你的公司名 (TEAMID)" \
  --notary-profile mirrorlink-notary --notarize
```

脚本验证身份、嵌套签名、提交公证并保存结果；只有 Accepted 才附加和验证票据，DMG 也独立公证。不将 `codesign` 完整性通过等同于 `spctl` 接受或 Apple 公证。

## 许可与验证边界

应用包含项目的 Apache-2.0 文本、NOTICE、第三方清单、scrcpy/Sparkle 原始许可及完整的 `ThirdPartyLicenses/`。构建验证会核对这些文本；对应源码材料的版本和重新链接说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 与 [vendor/licenses/README.md](vendor/licenses/README.md)。源码随包材料不等于每一项第三方依赖都已在本机重新编译，也不是外部法律审计。

实际构建、签名、线上下载、旧版替换和 UI 的验收结果分别记录在 [UPDATE-QA.md](UPDATE-QA.md)，未实测的项目不标记为通过。
