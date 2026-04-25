# 架构总览

`agent-bar` 是一个单机 macOS 小组件，只负责把 Codex usage 摘成顶部一行浮窗。

## 运行结构

- `Sources/AgentBar/`：AppKit 入口，创建无 Dock 图标的顶部浮窗；刘海屏和无 notch 普通屏幕都使用各自的 island 布局，刘海屏支持设置入口（不显示 pin）、无 notch 支持 pin 与齿轮设置入口，并通过 Sparkle 检查 GitHub Release appcast 更新。
- `Sources/AgentBarCore/`：数据读取、token/cost 扫描、价格计算和显示格式化。
- `Tests/AgentBarCoreTests/`：核心格式化和本地 session 扫描的 smoke coverage。
- `scripts/build-agent-bar-dmg.sh`：把 SwiftPM executable 打成 `AgentBar.app`，嵌入 `Sparkle.framework`，支持 universal DMG、Developer ID 签名和 release notarization。
- `scripts/generate-sparkle-appcast.sh`：基于 release DMG 生成签名 `appcast.xml`，供 Sparkle 从 GitHub Releases 检测和下载更新。
- `docs/`：仓库内知识、协作规则和变更 history。

## 数据流

1. `CodexRateLimitFallbackScanner` 优先扫描最近 session 里的 `event_msg.token_count.rate_limits`，取基础 `limit_id == "codex"` 的 5h/7d used percent，再换算为 remaining percent。
2. 如果本地 session 没有完整 quota，`CodexUsageClient` 读取 `CODEX_HOME/auth.json` 或 `~/.codex/auth.json`，调用 Codex usage API 补齐缺失窗口。
3. `CodexCostScanner` 扫描最近约 30 天 `sessions/YYYY/MM/DD/*.jsonl`，按 `token_count` 增量聚合 token 和估算 cost。
4. `AgentBarCacheStore` 把最后一次完整快照和每个 session 文件的计算结果缓存在 `~/.agentbar/cache.json`。启动时先用缓存快照显示旧值，后台刷新时按文件 size/mtime 复用未变化文件，只解析新增或更新过的 session。
5. `CodexAccountStore` 在每次读取或刷新当前 Codex OAuth auth 时，把账号凭据同步到 `~/.agentbar/accounts.json`；后台刷新会遍历这些已见账号，必要时刷新 token，并为展开态生成每账号一行的 quota 快照。用户点击展开区账号卡片内的账号切换控件时，`CodexAccountSwitcher` 会把目标账号凭据写回当前 Codex live `auth.json`，后续新开的 Codex CLI 会话使用该账号。
6. `AgentBarDisplayFormatting` 输出单行文案，`IslandWindowController` 为每块 `NSScreen` 建立 overlay，并每 60 秒静默刷新一次；刷新过程不显示状态点，完成后写回缓存并更新文案。数字变化由 `RollingTextLabel` 做短时向上滚动，位数变化带来的 island 宽度变化用 0.44s ease-in-out 过渡，并遵守系统 Reduce Motion。所有屏幕都使用贴住顶部、水平居中的黑色 island shell，高度由该屏 `frame.maxY - visibleFrame.maxY`、`safeAreaInsets.top` 和物理 notch 高度推导；刘海屏通过 `safeAreaInsets` 与 `auxiliaryTopLeftArea`/`auxiliaryTopRightArea` 计算物理 notch，把 notch 本体作为中心禁区，仅显示 Codex icon、两个 quota 百分比及右侧设置入口；普通屏幕保留相同视觉语言，但用连续 island 显示完整信息。
7. 无 notch 的普通屏幕启用 auto-hide eligibility：未 pin 时 island 收到屏幕顶部外，鼠标进入顶部唤出区或 island 区域时用 0.26s ease-in-out 动画滑出，右侧显示 SF Symbols pin；pin 状态写入 `UserDefaults` 的 `AgentBar.pinnedOpen`，重启后继续沿用。刘海屏 notch-aware island 固定显示设置入口，不参与 auto-hide。
8. PIN 右侧的 gear icon 打开独立设置窗口。窗口采用紧凑 macOS preferences 布局：左侧 sidebar 使用 `#E6E5E3`，右侧正文使用 `#F3F1EF`，grouped settings 卡片使用 `#EFEDEB`，列表选中态使用 `#226CFF`。General 页的 `Launch at Login` 调用 `SMAppService.mainApp` 注册/取消开机启动，`Automatic Updates` 直接读写 Sparkle 的 `automaticallyChecksForUpdates`；About 页展示 GitHub 仓库入口并点击打开仓库。设置窗口使用普通 window level，避免打开后阻止用户切换到其他窗口；打开设置时 app 临时切到 `.regular` 以进入 Command+Tab，关闭设置后切回 `.accessory`，保持平时无 Dock 图标。启动和切入 `.regular` 时显式从 `AgentBar.icns` 设置 `NSApp.applicationIconImage` 并刷新 `NSDockTile`，保证临时 Dock 图标使用 AgentBar logo。
9. `AgentBarUpdater` 启动 Sparkle 后按 `SUFeedURL` 检查 `https://github.com/iFurySt/agent-bar/releases/latest/download/appcast.xml`。发现可更新版本时，自定义 `SPUUserDriver` 先选择安装以触发后台下载；下载和解包完成后弹出确认框。用户选择安装会交给 Sparkle 退出、替换并重启；用户选择跳过会记录 `AgentBar.updater.skippedVersion`，同一个 `sparkle:version` 不再提醒。

## 边界

- 不支持多 provider。
- 不提供菜单栏状态项或登录流程；当前只有顶部 gear 设置窗口承载开机启动、自动更新、About GitHub 入口，以及 pin 和跳过更新版本这些本地偏好。
- 打包发布只覆盖 macOS DMG 和 Sparkle appcast；当前不提供 Homebrew 或 App Store 分发。
- 不上传本地 session 内容；所有 cost/token 汇总都在本机完成。
