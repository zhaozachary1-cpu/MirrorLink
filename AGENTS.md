# MirrorLink 项目协作约定

## 用户已确认的交付方式

- 本目录是镜连 macOS 应用的完整项目；GitHub 源码仓库为 `zhaozachary1-cpu/MirrorLink`，已按用户在 2026-10-01 的要求直接公开，不另建仓库。
- 用户要求后续版本直接同步 GitHub。完成用户授权的代码迭代、验证后，提交本项目所有允许的新增、修改、删除文件并推送 `origin/main`，再核对远端与本地 SHA。若用户明确只要方案/审查或禁止上传，则不提交。
- 可运行 `./script/sync_github.sh "修改说明"`；不要 force push、覆盖远端提交或把“配置了 origin”说成“已上传”。遇到未整合的远端修改先停下来检查。
- 不创建后台文件监听，不在用户工作未完成时频繁自动提交。推送源码不等于发布应用；公开源码的授权不替代公开发行包、更新下载托管的授权。后续发布复用现有仓库，不另建发行仓库。
- 用户已于 2026-10-01 明确授权将镜连安装包和签名更新清单公开发布到现有 `zhaozachary1-cpu/MirrorLink` 仓库的 Releases，并将其作为应用默认更新源。本次授权已覆盖该发布范围，无需再次询问是否允许公开；仍须完成正式签名、公证、第三方发行材料核对和更新验证，不将授权本身记作已发布。付费开发者注册、协议签署及账户安全确认仍需用户本人处理。
- 用户已于 2026-10-01 确认 MirrorLink 自有代码和文档采用 Apache-2.0，标准文本见根目录 `LICENSE`，项目声明见 `NOTICE`。第三方组件保留各自许可证，来源与待核对事项见 `THIRD_PARTY_NOTICES.md`；不得将项目许可证当成对全部内置二进制的重新许可或完整发行合规证明。
- 用户随后于 2026-10-01 明确同意免费社区版：允许在现有 Releases 公开发布未经 Apple 公证的 ad-hoc 应用，并使用原有 Sparkle Ed25519 密钥签署更新包和清单。此项取代社区版必须先取得 Developer ID/公证的要求；首次安装可能需接收者按 Apple 官方流程手动允许，受管理的 Mac 可能无法安装。仍须核对第三方发行材料、验证真实更新，不得宣传为 Apple 认可或关闭系统安全检查。正式公证版保留独立严格流程，社区版必须显式使用 `--community`。

## 验证与分发边界

- 原生 SwiftUI / SwiftPM、最低 macOS 13，保留现有手机到显示器图标及多设备独立投屏。
- 验证入口：`script/run_core_checks.sh`、`script/run_session_checks.sh`、`script/run_update_checks.sh`、`script/build_and_run.sh --verify --no-launch`。
- 会话脚本使用模拟子进程；不能声称已完成多台真机画面验收。启动进程也不能替代原生 UI 验收。
- 更新采用锁定版本的 Sparkle。公钥可以入库，私钥仅存钥匙串账户 `com.mirrorlink.desktop.updates`，绝不导出入库。没有公开 HTTPS 更新源时，诚实显示“尚未配置”。
- Developer ID、公证、完整性校验是三种不同证据。不能将 ad-hoc 当成正式签名，不能绕过 Gatekeeper 或全局移除 quarantine。
- 裸 `.app` 放 `~/Library/Application Support/MirrorLink/Builds` 或 `Releases`，避免 Documents 的同步服务追加 FinderInfo 破坏签名；分享目录只放 ZIP/DMG。
- 不上传 `.p12`、`.p8`、`.pem`、`.key`、Apple/GitHub 凭据、`.env`、构建缓存、设备日志或临时 QA 截图。
- 安装/替换本机应用前备份旧版；仅清理镜连拥有的子进程，不终止其他软件的 ADB/scrcpy。
