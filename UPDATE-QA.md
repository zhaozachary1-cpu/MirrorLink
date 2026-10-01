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
- GitHub 仓库 `zhaozachary1-cpu/MirrorLink` 最初以私有方式创建，主分支 `main`；初次提交 `1bc4761455bd04305fc283f14bb3e0fb2b23f70e` 已推送并核对远端 SHA。现已按用户要求公开，核验见下节。

## 同日补充：现有仓库公开

- 直接修改现有仓库可见性，没有新建仓库；仓库 ID 仍为 `1399877323`，主分支仍为 `main`。
- GitHub 返回 `private=false`、`visibility=public`；不带登录凭据的 API 请求也成功返回相同仓库及公开状态。
- 公开前检查了全部两次提交中的 53 个去重 Git 文件对象；常见凭据特征只命中更新测试中的示例 URL，经复核不是实际凭据。未发现真实密钥或凭据；这不等于完整安全审计。既有作者姓名、邮箱和提交历史随源码公开，未改写历史。
- 此次公开操作只变更仓库可见性与相关文档，不上传安装包、不生成更新源、不替换本机应用。当时项目级许可证待确认；维护者随后已确认采用 Apache-2.0，后续变更见下节，不以公开状态代替许可证。

## 同日补充：确认 Apache-2.0 与随包许可声明

- 维护者确认 MirrorLink 自有代码和文档采用 Apache-2.0；新增根目录 `LICENSE`、`NOTICE`、`THIRD_PARTY_NOTICES.md`，并同步更新 README、发行说明与项目协作约定。第三方组件保留各自许可证。
- `LICENSE` 与从 Apache 官方获取的标准文本逐字节一致，SHA-256 为 `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30`；scrcpy 原有包含上游版权信息的许可文件没有被替换。
- 验证命令：`./script/build_and_run.sh --debug --verify --no-launch --output-dir "$HOME/Library/Application Support/MirrorLink/Builds/License-Verification"`。SwiftPM 可执行产品 `MirrorLink` 的 arm64、x86_64 Debug 构建成功；许可文件在签名前装入应用包。
- 验证产物为 `~/Library/Application Support/MirrorLink/Builds/License-Verification/MirrorLink-20261001-130729.app`。五份随包许可文件均非空、与构建输入逐字节相同；两个架构的 scrcpy 上游许可文件也一致。暂存包与最终验证包的 `codesign --verify --deep --strict` 均通过，仍仅为 ad-hoc 签名。
- `git diff --check`、新增文本空白检查、`zsh -n script/build_and_run.sh`、基础逻辑检查、27 项模拟多设备检查与 18 项更新配置检查通过。
- 额外尝试 `swift test --scratch-path .build-mirrorlink-arm64 --triple arm64-apple-macos13 --filter MirrorLinkAppTests`，因 `unable to resolve module dependency: 'XCTest'` 失败。本机选中的工具链是 Command Line Tools，未安装 `/Applications/Xcode.app`；没有把独立脚本检查视为 XCTest 已通过。双架构构建同时出现 Command Line Tools 搜索路径及 Intel 兼容库警告，构建退出码仍为 0；没有做 Intel Mac 实际运行验收。
- 本次不变更版本号，不启动或替换本机已安装应用，不重新生成发行 ZIP/DMG，不发布 Release 或更新源。下节旧发行产物的哈希保持原样；本次 Debug 验证不替代原生 UI、真机投屏、正式签名公证或线上更新验收。

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
5. **第三方二进制许可核对**：项目 Apache-2.0 已确认，但当前 ADB 对应的完整上游许可/NOTICE 及 scrcpy 链接库的构建、传递依赖许可义务尚未核对齐全。现状与公开二进制发行前待办见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)，不以新增项目许可证或随包文件校验代替该审查。

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
