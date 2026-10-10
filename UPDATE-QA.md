# MirrorLink 更新与分发验证

## 0.4.3 社区版：2026-10-10 发布验证

- 已于 **2026-10-10 15:47:23（Asia/Shanghai；UTC 07:47:23）** 公开发布 [v0.4.3](https://github.com/zhaozachary1-cpu/MirrorLink/releases/tag/v0.4.3) 并设为 latest，非草稿、非预发布；版本 0.4.3 / Build 8。发行标签对应源码 `73ce216fdb0282d951c6fac1b9647d5875969694`。
- 核心、67 项会话、127 项无线模拟、28 项更新策略检查通过。单台 USB 真机原生档 180 秒及两次画质切换的日志/尺寸证据和限制见 [QUALITY-QA.md](QUALITY-QA.md)。本轮未把尺寸不变当成实际画质永不下降的证明。
- `package_release.sh --community` 成功生成双架构应用、完整 ZIP/DMG、更新 ZIP 和第三方对应源码。分享 ZIP/更新 ZIP 解包、DMG 只读挂载后的严格嵌套签名通过；许可、六份源码归档、版本、社区渠道和原有公钥均核对通过；挂载已卸载。
- 打包时发现首次候选 README 与最终说明的两行差异，已重新运行完整打包生成最终候选。正式发布仅使用 `artifacts/Releases/MirrorLink-0.4.3-20261010-073920/`；此包内嵌 README、ZIP 与 DMG 中的 README 与发行提交逐字节一致。
- 原有 Sparkle Ed25519 密钥签署 XML/ZIP，官方验签通过；独立工具核对版本/Build、固定版本 URL、长度，并拒绝清单、ZIP、签名和签名尾部的内存篡改。没有导出/轮换私钥，也没有申请 Developer ID 或 Apple 公证。
- 草稿上传六项资产后逐一比对 GitHub 的上传状态、字节长度及 SHA-256；全部一致后才公开为 latest。未覆盖旧版资产，未上传本机路径清单、设备日志或临时 QA 内容。
- 匿名 HTTPS 读回 latest appcast 与另外五项固定版本资产。首次出现 TLS 超时及更新 ZIP 传输截断，未将 HTTP 200 单独计为完整下载；重新匿名下载后，全部六项文件取得完整结果，公开校验清单与可信本地一致，五项资产哈希及 XML/ZIP 验签、篡改拒绝检查再次通过。
- 匿名 GitHub API 确认 latest 为 v0.4.3，远端标签 SHA 与发行源码一致；README 顶部按钮/备用链接已经指向 v0.4.3 完整包，GitHub README 已回读比对。
- 本机 0.4.2 已备份后手动替换为该已验证社区包，安装后为 0.4.3 / Build 8，严格签名、主二进制/Info.plist 比对与启动进程检查通过。共享 ADB 保留。**此操作不代表 Sparkle 实际覆盖升级验收。**

| 公开资产 | SHA-256 |
| --- | --- |
| 完整 ZIP | `8f38760b1cdd0a0414f0b41aad09389c33a8b2fdf3c4d31ceabad8f1783cb643` |
| DMG | `d04fcbb10bbf1ae37e875deb9f2845917944276bb63ab7e9806ab029e5e353c1` |
| 更新 ZIP | `e0042a00f657b420024c3fa2e60baf8042fbc3cbb175691792daba8a8e4bbfa2` |
| 第三方源码 | `b3d3b94b2433c228676ce2ee0c5b05f79062f9f778dc249cc44c6c2e5e08e88e` |
| appcast.xml | `6add014ddcb89118ab94655fea3405a1cf5ba37e937343c3b5357dad8582138b` |
| SHA256SUMS.txt | `8f296d7d8f51b19b87c6710241adaddc77b901502488105dd9e3eecb922adcb1` |

原生界面工具仍返回 `Sky Computer Use native pipe closed before response`；画质选择器/重新投屏按钮的点击、长期动态清晰度、无线真机、多设备真实画面、Intel/陌生 Mac 及 Sparkle 确认安装/重启仍未完整验收，不以发布成功代替。

## 0.4.2 社区版：2026-10-08 发布验证

- 已于 **2026-10-08 19:51:09（Asia/Shanghai；UTC 11:51:09）** 公开发布 [v0.4.2](https://github.com/zhaozachary1-cpu/MirrorLink/releases/tag/v0.4.2) 并设为 latest，非草稿、非预发布。版本为 0.4.2 / Build 7；发行标签对应源码 `f7aa677f3c3f1ea35c382fddeb005c03468c5fa9`。
- README 在打包前已新增醒目的系统要求、Assets 文件选择表、正常安装与旧版覆盖步骤、Apple 安全提示、Android 调试授权、无线扫码入口和已知验收边界。完整 ZIP、DMG 根目录及应用内嵌 README 与该发行提交逐字节一致。
- 本次重新通过核心检查、40 项会话模拟、127 项无线模拟、28 项更新策略检查。`package_release.sh --community` 完成双架构构建、完整嵌套 ad-hoc 签名与六项发行文件生成；没有使用 Developer ID 或 Apple 公证，没有更改 Gatekeeper/quarantine。
- 分享 ZIP、更新 ZIP 的解压应用通过 `codesign --verify --deep --strict`。DMG 校验和通过，只读挂载后的应用签名与 README 校验通过，测试结束已卸载。
- 社区渠道、版本/Build、原有更新公钥检查通过。六份第三方源码归档的 SHA-256 与固定清单一致，内置运行时通过上游逐字节比对；完整许可声明随包携带。
- `generate_update_feed.sh --community` 使用原有钥匙串账户签署 XML 与更新 ZIP；未导出、替换或轮换私钥。Sparkle 官方验签通过，独立验证工具的清单/ZIP 验签、固定版本 URL、长度以及四项内存篡改拒绝检查均通过。
- 先上传草稿，核对六项资产的 uploaded 状态、长度和 GitHub SHA-256 与本地一致后公开。上传范围仅为完整 ZIP、DMG、更新 ZIP、签名 appcast、第三方源码包和 SHA256SUMS；没有上传含本机路径的 RELEASE-MANIFEST、原始日志、密钥或 QA 副本。
- 发布后禁用用户 curl 配置、使用不带认证头的匿名 HTTPS 请求，从 `latest/download/appcast.xml` 下载清单，并从 `v0.4.2` 固定地址下载其余五项资产，均为 HTTP 200。公开校验清单与可信本地清单一致，五项哈希全部通过；公开下载的 XML/ZIP 再次通过全部独立验签与篡改拒绝检查。
- 匿名 GitHub API 再次确认 latest 为 v0.4.2；远端标签 SHA 与发行源码一致。更新清单为 Build 7，最低 macOS 13.0，更新 ZIP URL 固定到 v0.4.2，旧 v0.3.1 资产未覆盖。

| 公开资产 | SHA-256 |
| --- | --- |
| 完整 ZIP | `98a588f4ab1432d77e4143b24aeeb3259f83c9055e297257bf29e71bdafaf1bd` |
| DMG | `685545e9050d1f13a901fc1fa4c9b817e944a0e2f08f10bd24264bcb63e4dc1e` |
| 更新 ZIP | `18a44a23d51612c5d2f6288ca31a4b7f26488e7519b69d3f868e031efa3e04c0` |
| 第三方源码 | `44c2fdab315fd86b096c190a2ac2a837ec74cc83af6e004ec8c346c551c9fa46` |
| appcast.xml | `79d1a2b9181156b13c4daee268eac7249453a2dd14720974ce5f8bd1543e8e8d` |
| SHA256SUMS.txt | `4a74b8ee53c14ea098db25ad67b71ef3c4d0b19f2c80cf726781cc08bc774182` |

本地发行目录：项目内 `artifacts/Releases/MirrorLink-0.4.2-20261008-114546/`，匿名回读与验证副本只保留在忽略的 work 目录。

### 未完成的验收（不计为通过）

- 本次原生界面工具启动失败，诊断为旧工作区写入根路径含符号链接，工具运行内核退出；未修改 Codex 安全配置或绕过工具限制。未完成 Dock 点击、旧版通过 Sparkle 的实际发现/确认/安装/覆盖/重启和设置保留验收。签名更新源已经上线，但不能宣称实际覆盖升级已验收。
- 没有替换本机已安装应用来冒充自动更新成功。同为 0.4.2 / Build 7 的本地预览版需要时应手动安装社区包，不能期待同 Build 更新提示。
- 无线真机、两台以上真机画面、陌生 Mac 首次打开、Intel 真机、断网重试和投屏时延后安装仍待实测。此前单台 USB 的 75 秒/重启证据见 STABILITY-QA.md，不扩大为所有环境验收。
- 构建仍出现 Command Line Tools 可选搜索路径/Intel 兼容库警告，但构建与签名校验通过；XCTest 的工具链限制未在本轮解决。配套许可材料不等于外部法律审计。

## 历史：0.3.1 社区版验证状态

验证时间：本机 Asia/Shanghai 2026-10-02；对应 UTC 构建日期 2026-10-01。版本：0.3.1 / Build 4。用户已确认免费社区路线，不申请 Developer ID 或 Apple 公证，仍保留原有 Sparkle Ed25519 密钥与双重验签。

### 已通过

- 基础逻辑检查、27 项模拟多设备会话检查、28 项更新策略检查；新增检查覆盖默认更新源、原有公钥、清单签名要求、解包前验签、用户确认与本地预览渠道。模拟会话不代表真机视频验收。
- `package_release.sh --community` 成功调用既有构建入口完成 arm64、x86_64 Release 构建，生成完整 ZIP、DMG、更新专用 ZIP 和对应第三方源码包。
- 封装后的应用及分享 ZIP / 更新 ZIP 解压副本均通过 `codesign --verify --deep --strict`；DMG 校验和通过，只读挂载后的应用校验通过并已卸载。签名是 ad-hoc，不是 Apple 身份认证。
- 源码包中的六份固定版本归档与 `vendor/third-party-sources.tsv` 的 SHA-256 一致；两个架构的六项内置运行时资源与上游官方发行包逐字节一致，ADB 与 Google Platform-Tools 37.0.0 归档一致；八份完整许可/来源文件的哈希在构建与封装时验证通过。
- 独立临时副本的缺少源码包测试被公开发行门禁拒绝；修改临时应用 Info.plist 后严格签名校验失败。原始发行包未改动。
- `--community --notarize`、`--community --sign` 均以退出码 2 拒绝；不带社区参数的正式更新源流程拒绝 ad-hoc 社区包。修复了 `grep -q` 提前退出引发的 SIGPIPE，以及 zsh 对以 `--` 开头错误文案的选项误解析。
- `zsh -n` 与 `git diff --check` 通过。
- 发布者在本机确认钥匙串授权后，`generate_appcast` 成功使用原有密钥签署更新 XML 与 ZIP，Sparkle 官方 `sign_update --verify` 验证通过。未导出或轮换私钥。
- 新增只使用可信本地应用公钥的 `script/verify_update_artifacts.swift`；验证签名后才解析 XML，禁止外部实体与 DTD，核对版本、Build、版本固定的 ZIP URL 和字节数。六项检查通过：清单及 ZIP 验签、URL/长度核对、清单单字节篡改拒绝、ZIP 单字节篡改拒绝、ZIP 签名篡改拒绝、截断的清单签名尾部拒绝。篡改仅发生在内存副本中；这是独立 QA 工具，不替代应用内 Sparkle 安装验收。
- `v0.3.1` 已于 2026-10-02 08:47:02（Asia/Shanghai；UTC 00:47:02）公开发布并设为 latest，发行源码提交为 `079d594dbec4ac515cfd2676bedc1e81beb06c1e`。草稿上传期间核对了完整六项资产的状态、长度和 GitHub 返回的 SHA-256；没有上传含本机绝对路径的 `RELEASE-MANIFEST.txt`。
- 使用不含认证头、禁用用户 curl 配置的匿名 HTTPS 请求，从 latest 地址下载 appcast，并从 `v0.3.1` 固定地址下载其余五项资产，全部返回 HTTP 200。公开 `SHA256SUMS.txt` 与本地产物一致，五项资产逐一校验通过；公开下载的清单和 ZIP 再次通过上述六项验签/篡改检查。匿名 GitHub API 确认 latest 是非草稿、非预发布的 `v0.3.1`。
- 已将本机已安装的 0.3.0 / Build 3 及偏好设置备份到 `~/Library/Application Support/MirrorLink/Backups/Before-0.3.1-update.K6osi7/`；备份应用严格签名校验和偏好 plist 校验通过。确认无 scrcpy 进程后正常终止旧进程，仅将 `MirrorLinkCustomUpdateFeed` 设置为 canonical HTTPS 地址并重新启动旧应用；未手动替换应用，也未修改自动检查选择。旧版与发布版公钥相同。

### 未完成与明确边界

- 已安装 `/Applications/MirrorLink.app` 仍为 0.3.0 / Build 3；备份、更新地址配置与旧版重启已完成，但尚未从旧版真实执行发现更新、下载、确认安装、替换重启、版本提升、设置保留和再次检查无更新的完整验收。没有手动替换旧应用来冒充更新成功。
- 原生界面工具此前选择应用超时；本次正常重启应用及重建工具会话后仍返回 `Sky Computer Use native pipe closed before response`，无法获得更新窗口状态或点击安装。进程存在不等于 UI 验收通过；需用户操作“检查更新…”后补验。断网重试、陌生 Mac 的首次安装、Intel 真机、投屏期间延后安装和多台真机画面均未验收。
- Command Line Tools 的搜索路径与 Intel 兼容库警告仍出现，但两次构建退出码为 0。此前 XCTest 模块缺失问题本轮未解决，未宣称 XCTest 通过。
- 完整来源及许可材料已随包整理，不等于全部第三方依赖已经本机重建或外部法律审计。未进行 Apple 公证，也未更改 Gatekeeper、quarantine 或电脑全局安全设置。

发行目录：`~/Library/Application Support/MirrorLink/Releases/MirrorLink-0.3.1-20261001-160931/`。公开版本：[v0.3.1 Release](https://github.com/zhaozachary1-cpu/MirrorLink/releases/tag/v0.3.1)；以下哈希已与公开下载文件核对一致。

| 产物 | SHA-256 |
| --- | --- |
| 分享 ZIP | `d6586b916e4660344b21f645f1a072e7bbf7bdd8461f244fe0bd6a112f0d73d2` |
| DMG | `8600d1afde111f70cb77ec9d473bd2aee3db01d7546845e953353fd745c4d063` |
| 更新专用 ZIP | `08c52ca2b71aaf3f19a496c73d8e7c81d882941c0df05066c80869c5456293f2` |
| 第三方源码包 | `8b209e37168cf8fd3077e5e8f6ec88adc4173cb9621d0d4ef272ce1fd672f951` |
| 签名 appcast | `4426c0b4c4bcec254f1052b9d5373289857b1842a7144d16a5800f9f7fea9d10` |
| SHA256SUMS.txt | `1a466d9112d2c7cbb54eb55ed01879f64c2b55412cd25bac6e63a74f71bf0980` |

## 历史记录：0.3.0

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
