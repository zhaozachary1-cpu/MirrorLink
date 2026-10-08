# 应用内更新与 GitHub 发布

## 0.4.2 社区版配置

- 源码、公开安装包、签名更新清单使用现有 `zhaozachary1-cpu/MirrorLink`，不另建仓库。
- `CFBundleVersion=7`，高于公开 0.3.1 的 Build 4；Sparkle 固定为 2.10.0。同为 Build 7 的本地预览包不视为更低版本，需要时手动安装社区包。
- 默认源：`https://github.com/zhaozachary1-cpu/MirrorLink/releases/latest/download/appcast.xml`。
- `SURequireSignedFeed` 与 `SUVerifyUpdateBeforeExtraction` 均为 true，原有 Ed25519 公钥不变。更新来源不能替换信任公钥。
- 不静默下载或安装、不发送系统配置；自动检查默认关闭，用户可主动开启。
- 免费社区版没有 Apple 公证，首次打开可能需要用户在系统设置中手动允许。不是 Apple 验证的开发者发行。
- 真实发布与旧版覆盖验证状态见 [UPDATE-QA.md](UPDATE-QA.md)。配置地址、源码 push 与“已发布并可安装”是三件事，分别核验。

## 用户使用

0.3.1 起直接点击主窗口更新按钮、应用菜单“检查更新…”或“设置 → 应用更新”即可。0.3.0 需在设置中展开“设置更新地址”，保存上述完整 HTTPS 地址一次；0.2.0 及更早没有更新器，需要手动安装一次新版。

发现新版后由用户确认下载、安装，更新器验证签名再替换原应用并重启。投屏进行中会询问是否延后；设置仍使用同一应用标识下的 UserDefaults。网络或签名错误必须失败，不降级为未验证的安装。

## 发布者：免费社区路线

### 1. 构建与配套材料

递增 Info.plist 中显示版本与单调递增的 Build，更新 RELEASE-NOTES.md，然后运行：

```zsh
./script/run_core_checks.sh
./script/run_session_checks.sh
./script/run_wireless_checks.sh
./script/run_update_checks.sh
./script/package_release.sh --community
```

该模式先运行 `prepare_third_party.sh` 校验上游运行时和许可，构建通用应用、ad-hoc 签名，生成完整 ZIP/DMG、更新专用 ZIP、配套第三方源码包和公开校验清单。第一次准备源码可能需要下载较大的归档；缓存位于不入库的 `work/community-sources/`。本地 RELEASE-MANIFEST 含绝对路径，不原样公开。

### 2. 生成签名更新清单

把 RELEASE-NOTES.md 复制到发行目录的 `updates/MirrorLink-<version>-update.md`，再按真实版本 URL 生成：

```zsh
./script/generate_update_feed.sh "/绝对路径/发行目录" \
  "https://github.com/zhaozachary1-cpu/MirrorLink/releases/download/v0.4.2/" --community
```

脚本必须确认社区渠道、ad-hoc 签名完整、对应源码包齐全、公钥与现有钥匙串匹配。它使用账户 `com.mirrorlink.desktop.updates` 内的原有密钥同时签署 XML 和更新 ZIP，并验证 XML。不要手工修改签名后的 XML；重新生成时要更新校验清单。

若 macOS 请求钥匙串访问，**发布者在本机安全窗口确认**，不把密码发到聊天，不导出私钥、不修改安全策略。不能通过重新生成一把密钥来绕过此步骤，否则旧用户将不信任更新。

`--allow-local-test` 仅用于隔离测试，不是公开发布开关。省略社区/测试参数的默认路径仍严格要求 Developer ID、公证票据与 Gatekeeper 验证；社区路径不会放宽正式路径。

### 3. 源码与 Release

先执行 `./script/sync_github.sh "版本说明"` 验证、提交及推送，并核对远端 SHA。为相同源码提交创建版本标签与 GitHub Release，建议先建草稿，上传并核对下面六项后再公开为 latest：

1. 完整安装 ZIP。
2. 完整安装 DMG。
3. 更新专用 ZIP。
4. 完整签名 `appcast.xml`。
5. 对应第三方源码 `.tar.gz`。
6. `SHA256SUMS.txt`。

每次新版本公开并完成下载验证后，同步更新 README 顶部按钮、备用 DMG/ZIP 直链及版本文案。按钮使用明确版本的 `releases/download/v<version>/MirrorLink-<version>-macOS-universal.dmg`，以免把版本化文件名拼到 `latest/download` 后在下一版发布时出现 404。按钮必须直达完整安装包，不得指向 Release 列表、源码包或更新专用 ZIP；浏览器下载后仍须用户自行安装。

Release 必须明确“免费社区版、无 Apple 公证”和首次打开说明。仅发布了完整可用的更新源之后，才为 0.3.0 用户配置此地址。GitHub token 只用于发布者工具认证，不嵌入客户端。

更新归档 URL 固定到版本标签；更新清单使用 `latest/download/appcast.xml`。未来每次发布应保持完整六项，并将已完成校验的 Release 标为 latest。不要让无 appcast 的 Release 意外接管 latest。需要分支版本/兼容性历史时，保留旧版 appcast 条目及仍被引用的归档；不要覆写历史版本的签名 ZIP。

### 4. 验收

- 匿名 HTTPS 请求能取得 canonical appcast 及其引用的 ZIP，公开资产哈希与本地一致。
- XML/ZIP 签名均通过；单字节修改的 XML/ZIP 被拒绝；不依赖 Apple 身份作为更新签名替代。
- ZIP 解包、DMG 只读挂载后严格签名和许可检查通过。
- 备份已安装旧版与设置，然后从旧版实际执行发现、下载、确认安装、覆盖、重启、版本核对、设置保留及再次检查无更新。
- 另行验证断网重试、投屏中的延后安装、陌生 Mac 首次打开、Intel 实际运行；未执行的项目要单独记录，不以脚本或本机进程代替。

可独立复验已下载的发行文件，不需要私钥或钥匙串授权。可信 `Info.plist` 必须来自发布者已有的本地构建，不要使用与待验证下载同时取得的公钥替换信任根。下面的工具使用该构建的公钥、版本与 Build 验证对应发布；实际应用仍由 Sparkle 自行验签。

```zsh
mkdir -p .build
swiftc -swift-version 5 script/verify_update_artifacts.swift \
  -o .build/verify_update_artifacts
.build/verify_update_artifacts \
  "/可信本地发行目录/MirrorLink.app/Contents/Info.plist" \
  "/公开下载目录/appcast.xml" \
  "/公开下载目录/MirrorLink-0.4.2-update.zip" --self-test
```

`--self-test` 在内存中对清单、ZIP、签名和尾部做负面测试，不修改原文件。验签成功不能代替旧版应用中的真实安装和重启测试；每次发布都要记录各自结果。

## 可选公证路线

发布者未来获得 Developer ID 后可执行 [DISTRIBUTION.md](DISTRIBUTION.md) 中的签名与公证命令，再不带 `--community` 生成更新清单。仍沿用现有更新密钥，不因 Apple 签名方式变化而自动轮换 Ed25519 密钥。

本项目未配置 CI 私钥或后台自动发布任务；源码同步不是 Release 发布。用户已授权上述现有仓库的公开发行范围，但安全确认、收费注册与协议仍只能本人处理。
