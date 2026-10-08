# 0.4.2 投屏稳定性修复记录

日期：2026-10-07。源码/本地安装版本：0.4.2（build 7）。本次没有发布 GitHub Release 或修改更新清单。

后续：2026-10-08 已按社区版流程公开发布 0.4.2 安装包与签名更新清单；完整发布和匿名下载验证见 [UPDATE-QA.md](UPDATE-QA.md)。下文保留 10 月 7 日故障修复时的证据与验收边界，不将后续发布等同于新增 UI 验收。

## 已复现的故障

用户截图显示“启动超时：尚未收到手机画面”。检查时 0.4.1 主应用进程仍在，完整代码签名有效，未找到对应的 MirrorLink/scrcpy 崩溃报告；不能将这次现象定性为主应用崩溃。

在已授权的 USB 手机上，用原生产 `MirrorSessionStore` 和随包 scrcpy 4.1 复现：

| 相对启动时间 | 事件 |
| --- | --- |
| 约 0.57 秒 | scrcpy 服务端识别手机 |
| 25.01 秒 | MirrorLink 未见就绪日志，判定启动超时并终止自己的 scrcpy 子进程 |
| 25.23 秒 | 退出时才读到缓冲的 `Renderer: metal` / `Texture: 1080x2400` |

根因是 stdout 缓冲：scrcpy 4.1 的 INFO 日志使用 C 标准输出，macOS 下接普通 Pipe 时不会逐行刷新。MirrorLink 原先必须读到 `Texture:` 才进入“正在投屏”，因此健康会话也可能在 25 秒时被关闭。上游对应实现为 `v4.1/app/src/util/log.c` 以及 `v4.1/app/src/main.c`；本次未修改或重新编译第三方二进制。

## 修复

- 新增 `SessionLogStream`：stdout 通过专用 PTY 逐行刷新，stderr 保留独立管道；stdin 仍为空设备。不是启动 shell，也不使用动态库注入。
- 描述符设置 close-on-exec；父进程在启动后关闭自己的写端。用非阻塞 POSIX 读取处理 EOF/EIO，避免 PTY 断开时抛出 `FileHandle.availableData` 的 Objective-C 异常。
- 子进程退出后最多继续排空日志 500ms；后代进程即使保留标准输出，也不能使本次会话永久占用“正在启动/停止”状态。保留最后的诊断信息与独立重试能力。
- 私有日志 PTY 不接受交互，不需要终端标题；为 scrcpy 添加 `--no-terminal-title`。
- 继续使用真实 `Texture:` 就绪信号、25 秒启动期限、每会话 token 和仅清理自有子进程的规则；没有用“进程启动成功”代替画面就绪，也没有取消故障超时保护。
- 主控制界面改为单实例 SwiftUI `Window`。AppDelegate 明确处理 reopen 并激活主窗口；增加“投屏 → 显示主窗口”（⌘0）。关闭主控制窗口不退出整个应用，⌘Q 仍清理自有投屏会话。

## 本轮已完成的验证

环境：Apple Silicon Mac / macOS 27.0.1；USB Pixel 6 / Android 17；随包 scrcpy 4.1。设备序列号及原始日志不进入仓库。

| 验证层级 | 结果 |
| --- | --- |
| 核心逻辑 | `script/run_core_checks.sh` 通过 |
| 会话模拟回归 | `script/run_session_checks.sh` 的 40 项通过；新增缓冲 C stdout、PTY EOF、继承描述符、退出日志、快速重试覆盖 |
| 无线模拟回归 | `script/run_wireless_checks.sh` 的 127 项通过；未改变配对、授权及 GUID 匹配边界 |
| 更新策略回归 | `script/run_update_checks.sh` 的 28 项通过 |
| 回归有效性 | 将模拟就绪日志改为无 `fflush` 的 `fputs` 后，旧 Pipe 实现会在等待就绪时失败；修复后通过 |
| 单台真机服务层 | 同一生产会话实现配合随包工具，三轮就绪约为 1.37 / 1.27 / 0.53 秒；第一轮持续 75 秒，随后两轮各约 6 秒；各轮主动停止后自有子进程数均为 0 |
| 本地构建 | `script/build_and_run.sh --verify --no-launch` 成功；应用、scrcpy、ADB、Sparkle 均通过双架构检查和完整嵌套 ad-hoc 签名检查 |
| 本地安装 | 已备份旧版，再替换 `/Applications/MirrorLink.app`；安装后版本为 0.4.2 / 7，主二进制 SHA-256 与本次构建一致，严格签名再次通过，通过 macOS `open` 启动且主进程存活 |
| 清理边界 | 5037/5038 两个原有 ADB 守护进程均保留；没有全局终止 ADB/scrcpy，没有改变 Gatekeeper 或清除下载隔离标记 |

原版备份位于项目内 `artifacts/Backups/stability-0.4.1-before-0.4.2-20261007/MirrorLink.app`，本次构建位于 `artifacts/Builds/MirrorLink-20261007-033306.app`。两者均不上传 Git。

## 尚未完成的验收与限制

- 原生界面工具持续返回 `Sky Computer Use native pipe closed before response`，因此未执行实际 Dock 点击、关闭主窗口后重开、最小化后恢复或手机画面目视/输入交互验收。进程存活和真实 scrcpy 就绪日志不是这些 UI 验收的替代品。
- 已添加 AppDelegate 重开回调 XCTest（主窗口关闭、其他窗口仍可见、场景尚未接入的回退）。本机只有 Command Line Tools，`swift test --scratch-path .build-mirrorlink-tests --filter MirrorLinkAppTests.testDockReopen` 在测试模块编译时因 `unable to resolve module dependency: 'XCTest'` 失败；这些 XCTest 未执行，不能计为通过。
- 两种架构均已构建，但没有 Intel Mac 真机运行验收。链接器报告本机工具链缺失可选搜索路径以及兼容库不含 x86_64 的警告；构建和签名校验仍完成，不能据此宣称 Intel 运行行为已验证。
- 本次只有单台 USB 真机短时验证；不代表多台真机画面、无线实景或数小时压力测试已通过，也不保证不存在其他崩溃原因。
- 这是本地 ad-hoc 构建，不是 Developer ID 签名或 Apple 公证。源码同步不等于发布自动更新包。

人工复验建议：启动投屏等待至少一分钟；停止后再投屏；关闭镜连主窗口后点击 Dock 图标，确认可恢复控制窗口且现有投屏不受影响；再检查 ⌘0 和最小化后的恢复。
