# 应用内更新与 GitHub 发布

## 当前状态（2026-10-01）

- 应用版本：0.3.0 / Build 3。新增 Sparkle 2.10.0 更新器和三个入口。
- 源码仓库：`zhaozachary1-cpu/MirrorLink`，已公开；后续源码和经确认的发行复用此仓库，不另建仓库。
- 更新公钥嵌入应用并随应用代码签名封装；私钥保存在发布机钥匙串账户 `com.mirrorlink.desktop.updates`，不会入库。
- 默认没有 `SUFeedURL`，没有可声称已经上线的更新服务器。可以在设置中配置发布者提供的 HTTPS appcast 地址。
- 本机尚无可用 Developer ID Application 证书/私钥，因此本地包仍是 ad-hoc；不能声称 Apple 已接受公证。
- 0.3.0 已完成双架构构建、ZIP 解包和 DMG 只读挂载完整性校验，并安装到本机。更新源生成在系统钥匙串授权处暂停，未完成签名源/在线替换端到端验收，详见 [UPDATE-QA.md](UPDATE-QA.md)。
- 2026-10-01，用户已明确授权公开安装包、签名更新清单，并将现有仓库 Releases 作为默认更新源。授权已完成，实际发布尚未完成；这两种状态不能混淆。

### 首次上线前复核（2026-10-01）

- GitHub API 确认当前凭据具有现有仓库的管理与写入权限，仓库公开；Releases 列表仍为空。没有创建空发行版，也没有上传本地 ad-hoc 包。
- 本机运行 `/Applications/MirrorLink.app` 的版本为 0.3.0 / Build 3；没有 `SUFeedURL`，也没有保存自定义更新地址。截图中的提示发生在联网检查之前，不是已经下载后的安装失败。
- `security find-identity -v -p codesigning` 仍返回 `0 valid identities found`；`xcrun notarytool history --keychain-profile mirrorlink-notary --output-format json` 返回该钥匙串配置不存在。正式发布当前阻塞在 Apple 身份与公证配置，不能由 GitHub 发布授权替代。
- 用户需在 Apple 官方账户页面本人登录并确认开发者资格，配置 Developer ID Application 证书及对应私钥和公证凭据。不得在聊天中索取登录密码、验证码或私钥，不自动购买会员或签署协议。
- 待发行条件补齐后，按以下流程生成高于 Build 3 的版本、签名并公证、生成和校验更新清单，再发布到已获授权的仓库。只有匿名 HTTPS 下载及签名验证通过后，才配置当前应用的更新地址并进行低版本覆盖更新验收；不要提前填入尚未上线的 URL 使“未配置”变成网络错误。

## 用户流程

1. 旧版 0.2.0 没有更新器，需先安装一次包含更新器的版本。
2. 发布者上线更新源后，在“镜连 → 设置 → 应用更新 → 设置更新地址”保存其完整 HTTPS 地址。
3. 点击“检查更新…”，查看新版本说明并确认下载、安装。
4. 更新器验证签名并替换当前应用，随后重启；设置仍保留在同一应用标识的 UserDefaults 中。
5. 投屏进行中安装更新或退出时，先确认停止；选择“稍后安装”或“继续投屏”不会自动终止会话。

更新关闭静默下载/静默安装及系统信息上报。自动检查默认为关闭，可主动开启。网络、下载、签名等错误会显示失败提示；不得自动退回未签名安装方式。

## 发布者流程

### 1. 准备 Apple 身份

发布机钥匙串必须有 Developer ID Application 证书及匹配私钥。先验证：

```zsh
security find-identity -v -p codesigning
xcrun notarytool store-credentials mirrorlink-notary
```

在系统提示中输入凭据，不将密码、应用专用密码、API 私钥发到聊天或写入仓库。若证书由其他 Mac 创建，需要安全迁移证书和私钥；只有 `.cer` 可能不足以签名。

### 2. 递增版本并打包

修改 `Sources/MirrorLinkApp/Resources/Info.plist` 的显示版本与 **单调递增**的 `CFBundleVersion`，更新本文件和 README。运行全部回归检查，再执行：

```zsh
./script/package_release.sh \
  --sign "Developer ID Application: 公司或个人名 (TEAMID)" \
  --notary-profile mirrorlink-notary --notarize
```

脚本先验证身份/公证配置，再嵌套签名 Sparkle、工具和应用，提交并保存 Apple 结果、附加票据；DMG 也独立签名、公证、附加票据。只有 Accepted 和后续验证通过才生成 `notarized=yes` 的发行清单。

每个发行目录含分享 ZIP/DMG，以及 `updates/MirrorLink-<version>-update.zip`（仅包含 `.app`）。不要把含 Applications 快捷方式的分享 ZIP 当作更新 ZIP。

### 3. 生成安全更新源

在 `updates` 目录放与更新 ZIP 同名的 Markdown 发行说明（仅替换扩展名）。使用实际批准的下载地址，不照抄示例域名：

```zsh
./script/generate_update_feed.sh "/绝对路径/发行目录" \
  "https://你的公开下载域名/镜连版本路径/"
```

脚本检查公证状态和签名密钥是否匹配，生成同时签署了 XML 和更新 ZIP 的 appcast，再校验 XML 签名。私钥不会导出。测试用 `--allow-local-test` 只绕过正式公证前置检查，不关闭更新签名，也不联网发布；测试源不能当作正式上线。

第一次使用 `generate_appcast` 或 `sign_update` 时，macOS 可能要求批准访问钥匙串中的更新签名密钥。此安全窗口需要发布者在本机操作；不要通过导出私钥、修改系统安全策略或在聊天中提供密码绕过它。

公钥轮换需要按 Sparkle 官方迁移流程，不能每个版本重新生成密钥。丢失原钥匙串私钥会影响已安装用户的更新信任链；应由发布者进行安全离线备份。

### 4. 上线与验收

用户已确认直接公开现有 `zhaozachary1-cpu/MirrorLink` 仓库，不另建二进制发行仓库，并于 2026-10-01 授权公开安装包、签名更新清单及默认更新源接入；该范围无需重复征求发布授权。正式安装包和更新文件使用同一仓库的 Releases 发布；当前没有已发布的 Release 或 appcast，不应把源码地址填作更新源，也不要把 GitHub token 嵌入客户端。

上传更新 ZIP 和完整签名的 `appcast.xml`；先上传 ZIP，确认匿名 HTTPS 可下载，再更新固定 appcast 地址。签名后不要手动改 XML。需要保留历史版本时，在生成前放回上一版 appcast/必要的更新文件，并检查生成差异。

首次上线必须从较低版本实测：发现更新 → 断网失败重试 → 签名异常拒绝 → 下载安装 → 投屏中的延后安装 → 替换重启 → 版本号提升 → 设置保留。还要在未参与开发的 Mac 上验证 Gatekeeper；Intel 运行验收需 Intel Mac。

源码 push 不会自动公开安装包，也不代表线上更新链路完成。项目尚未配置 CI 签名秘密、自动 Release 或后台同步任务。
