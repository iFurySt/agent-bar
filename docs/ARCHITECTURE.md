# 架构总览

`agent-bar` 是一个单机 macOS 小组件，只负责把 Codex usage 摘成顶部一行浮窗。

## 运行结构

- `Sources/AgentBar/`：AppKit 入口，创建无 Dock 图标的顶部浮窗；刘海屏使用 notch-aware island 布局。
- `Sources/AgentBarCore/`：数据读取、token/cost 扫描、价格计算和显示格式化。
- `Tests/AgentBarCoreTests/`：核心格式化和本地 session 扫描的 smoke coverage。
- `scripts/build-agent-bar-dmg.sh`：把 SwiftPM executable 打成 `AgentBar.app`，支持 universal DMG、Developer ID 签名和 release notarization。
- `docs/`：仓库内知识、协作规则和变更 history。

## 数据流

1. `CodexRateLimitFallbackScanner` 优先扫描最近 session 里的 `event_msg.token_count.rate_limits`，取基础 `limit_id == "codex"` 的 5h/7d used percent，再换算为 remaining percent。
2. 如果本地 session 没有完整 quota，`CodexUsageClient` 读取 `CODEX_HOME/auth.json` 或 `~/.codex/auth.json`，调用 Codex usage API 补齐缺失窗口。
3. `CodexCostScanner` 扫描最近约 30 天 `sessions/YYYY/MM/DD/*.jsonl`，按 `token_count` 增量聚合 token 和估算 cost。
4. `AgentBarCacheStore` 把最后一次完整快照和每个 session 文件的计算结果缓存在 `~/.agentbar/cache.json`。启动时先用缓存快照显示旧值，后台刷新时按文件 size/mtime 复用未变化文件，只解析新增或更新过的 session。
5. `AgentBarDisplayFormatting` 输出单行文案，`IslandWindowController` 为每块 `NSScreen` 建立 overlay，并每 60 秒刷新一次。刷新期间 island 显示一个绿色呼吸点；刷新完成后写回缓存。所有屏幕都使用贴住顶部、水平居中的黑色 island shell，高度由该屏 `frame.maxY - visibleFrame.maxY`、`safeAreaInsets.top` 和物理 notch 高度推导；刘海屏通过 `safeAreaInsets` 与 `auxiliaryTopLeftArea`/`auxiliaryTopRightArea` 计算物理 notch，把 notch 本体作为中心禁区，只显示 Codex icon 和两个 quota 百分比；普通屏幕保留相同视觉语言，但用连续 island 显示完整信息。

## 边界

- 不支持多 provider。
- 不提供设置页、菜单栏状态项、登录流程或更新框架。
- 打包发布只覆盖 macOS DMG；当前不提供 Homebrew、Sparkle auto-update 或 App Store 分发。
- 不上传本地 session 内容；所有 cost/token 汇总都在本机完成。
