# MirrorLink 0.3.0 更新与分发验证

验证日期：2026-10-01。版本：0.3.0 / Build 3。

## 已确认

- 基础逻辑检查通过；27 项多设备模拟子进程检查通过；18 项更新配置检查通过。模拟子进程不代表真实手机投屏。
- arm64 与 x86_64 Release 构建成功，合并后的应用、ADB、scrcpy 及 Sparkle.framework 均包含双架构。Intel 只完成编译和架构检查，没有 Intel Mac 运行验收。
- Sparkle 固定为 2.10.0；链接使用 `@rpath/Sparkle.framework/Versions/B/Sparkle`，应用包含 `@executable_path/../Frameworks` 搜索路径。
- 应用、嵌入的框架、更新辅助程序及工具按内到外签名；`codesign --verify --deep --strict` 通过。签名是本地 ad-hoc，不是 Developer ID。
- 分享 ZIP 解包后校验通过；更新专用 ZIP 解包后只含应用（没有 Applications 快捷方式），严格签名校验通过。
- DMG 校验和通过；只读挂载后应用严格签名校验通过，随后正常卸载。
- 本机 `/Applications/MirrorLink.app` 已替换为 0.3.0 / Build 3，安装后严格签名校验通过，`open` 启动后可确认对应进程存在。没有改动 UserDefaults 或手机数据。
- 原 0.2.0 保存在 `~/Library/Application Support/MirrorLink/Backups/MirrorLink-0.2.0-before-0.3.0-20261001-1237.app`。
- 私有 GitHub 仓库 `zhaozachary1-cpu/MirrorLink` 已创建，主分支 `main`；初次提交 `1bc4761455bd04305fc283f14bb3e0fb2b23f70e` 已推送并核对远端 SHA。后续校验修正随本文件一起提交。

## 发行产物证据

发行目录：`~/Library/Application Support/MirrorLink/Releases/MirrorLink-0.3.0-20261001-122540/`。清单 `RELEASE-MANIFEST.txt` 记录 `signing=local-adhoc` 和 `notarized=no`。

| 产物 | SHA-256 |
| --- | --- |
| 分享 ZIP | `38858e0c7015ae350935bff5019898f17fbd8d68ee8a0e406c7f39f3690c9d7e` |
| DMG | `94aeefeff639b3ba11600b763b627a5a307c5327212a9c3f9ac33d3e37eb8d27` |
| 更新专用 ZIP | `ad217be5ba3c5a7c809892d7927cfb3df09d9f8b2a1e7adf010eaf3f8bbcced7` |

## 未完成与阻塞

1. **Developer ID / Apple 公证**：`security find-identity -v -p codesigning` 返回 `0 valid identities found`。没有发起 Apple 公证，也没有 Gatekeeper 正式发行接受证据。必须先由发布者在本机配置证书、对应私钥和 notarytool 钥匙串配置。
2. **更新源签名**：以保留域名 `https://updates.example.invalid/mirrorlink/0.3.0/` 进行本地生成测试，没有上传或部署。公钥匹配检查通过后，`generate_appcast` 停在 `SecItemCopyMatching`；系统 SecurityAgent 正在等待钥匙串授权。未绕过授权或导出私钥，已终止本次测试进程。因此不能声称 XML/更新包签名验签或篡改拒绝测试通过。
3. **原生界面验收**：原生 UI 检查工具返回 `Sky Computer Use native pipe closed before response`。只能确认安装版本、签名和运行进程，不能据此声称三个更新入口的交互已验收。
4. **线上更新与真机回归**：尚无公开 HTTPS 更新源，也未完成较低版本发现更新、断网重试、投屏时延后、替换重启、版本提升和设置保留的端到端测试。本次没有两台以上真实手机画面验收。

## 本次修正

- 构建依赖中嵌套 `.xpc/.app` 受到同步目录 FinderInfo 元数据影响；只对本次新构建暂存的 Sparkle.framework 去掉 `com.apple.FinderInfo`，没有删除 quarantine/provenance 或更改 Gatekeeper。
- 修正 framework 的 `lipo -verify_arch` 调用，分别检查两个架构。
- 公证脚本即使提交命令失败也会保留 JSON；有提交 ID 时尝试获取 Apple 日志，非 Accepted 状态始终停止发布。该异常分支不代表完成了真实 Apple 公证测试。
- 更新源脚本在访问私钥前提示发布者在本机处理钥匙串授权。

## 复验入口

```zsh
./script/run_core_checks.sh
./script/run_session_checks.sh
./script/run_update_checks.sh
./script/package_release.sh
```

正式发布条件与人工授权步骤见 [UPDATES.md](UPDATES.md)。不得将源码推送、结构检查或 ad-hoc 完整性校验替代正式签名公证和真实更新验收。
