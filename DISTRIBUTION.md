# 镜连发行与分享说明

## 当前可交付状态

0.3.0 新增 Sparkle 更新器，构建及签名会覆盖其内置 XPC/辅助程序/框架。`updates/` 中会额外生成用于覆盖安装的单应用 ZIP；完整更新发布流程见 [UPDATES.md](UPDATES.md)。

`script/package_release.sh` 会构建一个包含 arm64 + x86_64 的通用 macOS 应用，并生成 ZIP 与 DMG。应用内置官方 scrcpy v4.1、ADB 和 scrcpy-server，不依赖用户先安装 Homebrew。

直接执行：

```zsh
./script/package_release.sh
```

默认产物位于 `~/Library/Application Support/MirrorLink/Releases/`，可用 `--output-dir` 指定其他非同步目录。裸 `.app` 应保留在本地非同步目录，ZIP/DMG 可复制到“文稿”或“桌面”分享；这样可以避免文件同步服务反复添加导致严格签名校验失败的 Finder 元数据。

如果没有提供 Developer ID，脚本会在所有资源组装完成后，依次对内置工具和整个 `.app` 做本地 ad-hoc 签名，并用 `codesign --verify --deep --strict` 检查完整性。产物会被明确标记为 `signing=local-adhoc`。它适合本机或开发环境验证，但完整性校验通过不代表 Apple 信任，也不能承诺其他用户下载后无 Gatekeeper 拦截。

## 面向他人分发的正式流程

要让陌生用户双击下载包后获得正常的 macOS 信任体验，需要 Apple Developer Program 账号，以及 Developer ID Application 签名和 Apple 公证：

```zsh
./script/package_release.sh \
  --sign "Developer ID Application: 你的公司名 (TEAMID)" \
  --notary-profile mirrorlink-notary \
  --notarize
```

先用 `xcrun notarytool store-credentials mirrorlink-notary` 将公证凭据保存到钥匙串，再把配置名称传给脚本。脚本只接受钥匙串 profile，不把 Apple 密码、应用专用密码或证书私钥写入命令行或仓库。

公证完成后，脚本会把票据 stapler 到 `.app`，再重新生成 ZIP/DMG，并写入 `RELEASE-MANIFEST.txt`。应额外验证：

```zsh
codesign -dvvv --entitlements :- "$HOME/Library/Application Support/MirrorLink/Releases/.../MirrorLink.app"
spctl -a -vv --type execute "$HOME/Library/Application Support/MirrorLink/Releases/.../MirrorLink.app"
```

## 为什么微信下载的文件容易被 macOS 拦截

微信、浏览器和其他下载渠道通常会给文件写入 macOS 的 `com.apple.quarantine` 下载隔离标记。这个标记本身不代表文件非法，而是告诉 Gatekeeper：文件来自外部来源，需要检查开发者签名、公证和用户意图。

因此，用户侧删除隔离标记只能作为本机排障手段，不能替代发布修复；也不应要求用户关闭 Gatekeeper。真正面向公众的修复是使用 Developer ID + Hardened Runtime + Apple 公证，并把公证后的 ZIP/DMG 作为分享文件。

## 许可证

发行包包含 `NOTICE-scrcpy.txt`，对应内置 scrcpy 的 Apache License 2.0。请在公开分发前一并保留该许可证和其他第三方组件的声明。
