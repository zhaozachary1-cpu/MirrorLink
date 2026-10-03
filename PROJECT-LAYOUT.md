# MirrorLink 项目目录与迁移记录

## 统一管理规则

所有维护文件随项目根目录一起移动。路径在脚本运行时解析，不将维护者电脑的绝对路径写入源码或发行应用。项目应位于非同步的本地目录，避免同步服务给签名应用附加 FinderInfo。

| 相对项目根目录 | 内容 | Git 管理 |
| --- | --- | --- |
| `Sources/`、`Tests/`、`script/` | 应用代码、测试、构建及发行脚本 | 是 |
| `vendor/`、根目录 Markdown、`Package.*` | 固定版本运行时、许可、文档及依赖声明 | 是 |
| `.git/`、`.codex/` | 原仓库历史、远端配置、Codex Run 配置 | 保留原配置 |
| `artifacts/Builds/` | 新构建的通用 `.app` | 否 |
| `artifacts/Releases/` | 历次安装 ZIP / DMG、更新包、发行清单 | 否 |
| `artifacts/Backups/` | 旧版应用及安装前备份 | 否 |
| `outputs/` | 早期便携版、历史构建/打包、图标和 QA 文件，保留原结构 | 否 |
| `work/` | 上游材料缓存、早期脚本、本机工作记录 | 否 |
| `work/tmp/` | 本次构建/打包的临时目录，退出时仅清理该次目录 | 否 |
| `.build/`、`.build-*/` | Swift 构建与检查缓存 | 否 |

`./script/build_and_run.sh --verify` 是 Codex Run 入口，默认输出到 `artifacts/Builds/`。`./script/package_release.sh` 默认输出到 `artifacts/Releases/`；不加 `--community` 仍仅是本地预览包。两者从其他工作目录调用也会找到同一个项目。`--output-dir` 优先于环境变量，覆盖位置的相对路径按调用时的工作目录解释。

系统管理的 `/Applications/MirrorLink.app`、偏好设置、ADB 授权数据、钥匙串和共享开发工具保留原位。发行应用只读取自身封装的运行时，不需要用户拥有开发目录。此次目录调整不更改应用版本、公开 Releases 或更新源。

## 2026-10-03 本机迁移

完整仓库（含 `.git`、被忽略的文件和历史产物）迁入用户指定目录；原 Application Support 下的 `Builds`、`Releases`、`Backups` 整体迁入 `artifacts/`。旧源码位置和旧 Application Support 位置保留符号链接，仅指向新位置，不保留第二份活动数据。

历史 `*-QA.md` 和发行清单中的路径仍是验收当时的真实位置，保持原文。需要查找旧 `Application Support/MirrorLink/…` 产物时，在项目内打开 `artifacts/…` 即可；旧地址也可通过兼容链接访问。

移动前后逐项校验结果：

- 原项目 28,006 个条目，其中 20,104 个普通文件；文件共 3,860,972,165 字节。
- 原 Application Support 1,871 个条目，其中 1,119 个普通文件；文件共 838,826,186 字节。
- 两组 SHA-256、权限、inode 与符号链接目标全部一致；Git 历史与原始文件均保留。
- 不包含本次新生成的审计记录自身。本机完整清单位于被 Git 忽略的 `work/migration-20261003/`，不公开本机绝对路径或设备数据。

对话中仍存在的两张问题截图另迁入 `outputs/reference/user-attachments/`，哈希一致。最早的一张临时截图在检查时已不存在，未计入迁移数量。未确认属于本项目的其他下载应用未被移动；具体本机映射和保留项记录在 `work/migration-20261003/LOCAL-PATHS.md`。

### 迁移后回归

- 在项目外的工作目录通过绝对路径运行四组检查：核心逻辑通过、35 项会话检查通过、127 项无线检查通过、28 项更新检查通过。
- 在项目外执行 `script/build_and_run.sh --verify --no-launch`：arm64 / x86_64 构建及内置工具、许可、严格嵌套签名校验通过，输出位于 `artifacts/Builds/MirrorLink-20261003-141309.app`。
- 通过旧源码兼容路径从项目外执行 `script/package_release.sh`：成功保存至 `artifacts/Releases/MirrorLink-0.4.1-20261003-141524/`。ZIP 完整性、DMG 校验和、解压后的更新应用严格签名均通过；发行清单中的路径已是新目录。
- `prepare_third_party.sh` 的上游哈希、运行时逐字节比对通过；三个脚本均使用 `work/tmp/` 暂存，退出后目录为空。
- 移动前后的 0.4.1 构建包、0.3.1 已发布包及原 `/Applications/MirrorLink.app` 严格签名均通过；已安装应用仍为 0.4.1 / build 6，未重装。
- 所有 Shell 入口的 `zsh -n` 和 `git diff --check` 通过，`artifacts/` 和本机审计资料被 Git 忽略。

本次打包仅为 `local-preview` / `local-adhoc` / `notarized=no`，没有签署新更新清单或公开发行。上述检查证明迁移、构建和封装的完整性，不代表真实手机画面、Developer ID 或 Apple 公证。
