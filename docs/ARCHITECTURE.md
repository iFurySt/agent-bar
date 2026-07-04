# 架构总览

`agent-bar` 是一个单机 macOS 小组件，主体是把 Codex usage 摘成顶部一行浮窗；此外在展开面板里附带展示 Claude
Code 的 5h/weekly 配额（只读、单账号）。

## 运行结构

- `Sources/AgentBar/`：AppKit 入口，创建无 Dock 图标的顶部浮窗；刘海屏和无 notch 普通屏幕都使用各自的 island 布局，刘海屏支持设置入口（不显示 pin）、无 notch 支持 pin 与齿轮设置入口，并通过 Sparkle 检查 GitHub Release appcast 更新。展开面板除了 Codex 账号列表，还会在其上方展示一张 Claude Code 配额卡片（`ClaudeQuotaView`），本机未登录 Claude Code 时这张卡片不渲染。
- `Sources/AgentBarCore/`：数据读取、token/cost 扫描、价格计算、日级和小时级 token 历史聚合、Vibe Coding 活跃时间扫描、显示格式化，以及 Claude Code OAuth 配额读取（`ClaudeAuth.swift`/`ClaudeUsageClient.swift`）。
- `Tests/AgentBarCoreTests/`：核心格式化和本地 session 扫描的 smoke coverage。
- `scripts/build-agent-bar-dmg.sh`：把 SwiftPM executable 打成 `AgentBar.app`，嵌入 `Sparkle.framework`，支持 universal DMG、Developer ID 签名和 release notarization。
- `scripts/generate-sparkle-appcast.sh`：基于 release DMG 生成签名 `appcast.xml`，供 Sparkle 从 GitHub Releases 检测和下载更新。
- `docs/`：仓库内知识、协作规则和变更 history。

## 数据流

1. `CodexRateLimitFallbackScanner` 优先扫描最近 session 里的 `event_msg.token_count.rate_limits`，取基础 `limit_id == "codex"` 的 5h/7d used percent，再换算为 remaining percent。
2. 如果本地 session 没有完整 quota，`CodexUsageClient` 读取 `CODEX_HOME/auth.json` 或 `~/.codex/auth.json`，调用 Codex usage API 补齐缺失窗口。
3. `CodexCostScanner` 扫描最近约 30 天 `sessions/YYYY/MM/DD/*.jsonl`，使用用户本机 `TimeZone.autoupdatingCurrent` 对 `token_count` timestamp 做本地自然日/小时归属并估算 cost；设置页 Usage 复用同一个 scanner 按年份读取 Jan-Dec 日级 token 历史，并按 Day 视图选中的本地自然日读取 00-23 点小时级模型拆分。Usage 设置页按当前 Day/Year 模式只刷新当前可见视图，不再每次切换都同时计算两套数据；日期/年份快速连续切换时会短暂 debounce，并用刷新序号丢弃旧请求结果，保证 UI 只展示最后停留的目标日期或年份。
4. `AgentBarCacheStore` 把最后一次完整快照、每个 session 文件的计算结果和 Usage 视图级 snapshot 缓存在 `~/.agentbar/cache.json`。启动时先用缓存快照显示旧值；如果完整快照缺失但 cost 文件缓存还在，则先从 cost 文件缓存恢复 Today/~30 Days，避免启动时退回 `$0.00`。Settings 的 Accounts 页同样优先复用顶部浮窗当前账号快照和 latest snapshot 里的账号 quota，只有没有 snapshot 时才回落到只含账号身份的 `accounts.json`。后台刷新时按文件 size/mtime 和聚合时区复用未变化文件，只解析新增、更新过、价格表需要重算或时区不一致的 session。cost 文件缓存按 session 文件保存 day/model 和 day/hour/model 聚合；Usage 视图级缓存按时区保存 Year 日级 snapshot、Day 小时级 token snapshot 和 Day Vibe Coding Time snapshot，过去日期和过去年份直接复用，今天和当前年使用短时缓存吸收快速切换。分日和分小时都依据每条 `token_count` 的 timestamp 在用户本地时区归属，所以同一个长期 session 今天消耗 N、明天继续消耗 M 时会分别落到对应本地日期和小时。`CodexActivityScanner` 独立读取同一批本地 session JSONL 的用户消息、token_count、命令/patch/collab/diff 等活动事件时间戳，把相邻间隔不超过 10 分钟的事件归为 active block，再按用户本地时区分摊到所选日期的 24 小时。扫描还会补捞最近修改过的旧日期目录文件，避免长期 session 仍存放在创建日目录时漏算后续日期。
5. `CodexAccountStore` 在每次读取或刷新当前 Codex OAuth auth 时，把账号凭据同步到 `~/.agentbar/accounts.json`；后台刷新会遍历这些已见账号，必要时刷新 token，并为展开态生成每账号一行的 quota 快照。顶部展开区只展示当前账号和最近账号的轻量列表：无 notch 普通屏只有 1 个账号时保持单列满宽，超过 1 个账号后利用较宽空间按两列最多展示 8 个账号，刘海屏保持单列最多展示 4 个账号；超过当前屏幕展示上限时显示更多账号入口并打开 Settings 的 Accounts 页。用户在展开区或 Accounts 页点击切换控件时，`CodexAccountSwitcher` 会把目标账号凭据写回当前 Codex live `auth.json`，后续新开的 Codex CLI 会话使用该账号。
6. `AgentBarDisplayFormatting` 输出单行文案，`IslandWindowController` 为每块 `NSScreen` 建立 overlay，并每 60 秒静默刷新一次；刷新过程不显示状态点，先用 quick quota 更新顶部百分比，如果展开区账号 quota 仍为空则先单独拉取账号 usage，再等待完整 cost 扫描完成后写回缓存并更新文案。数字变化由 `RollingTextLabel` 做短时向上滚动，位数变化带来的 island 宽度变化用 0.44s ease-in-out 过渡，并遵守系统 Reduce Motion。所有屏幕都使用贴住顶部、水平居中的黑色 island shell，高度优先采用 Window Server 暴露的当前屏 `Menubar` 窗口并归一化为视觉菜单栏高度，再回退到该屏 `frame.maxY - visibleFrame.maxY`、`safeAreaInsets.top` 和物理 notch 高度推导；这样普通桌面、全屏 app 顶部 hover 下拉菜单栏、刘海屏和无 notch 屏都保持与系统顶栏同高。刘海屏通过 `safeAreaInsets` 与 `auxiliaryTopLeftArea`/`auxiliaryTopRightArea` 计算物理 notch，把 notch 本体作为中心禁区，默认仅显示 Codex icon 和两个 quota 百分比，hover 或展开后才显示右侧设置入口；普通屏幕保留相同视觉语言，但用连续 island 显示更紧凑的完整信息。账号展开区在鼠标离开面板后开始计时，默认连续离开 200ms 自动收回；设置窗口可调整 100 到 5000ms，鼠标回到面板内会重新计算。
7. 无 notch 的普通屏幕启用 auto-hide eligibility：新用户首次启动默认 pinned open，避免安装后看不到 AgentBar；用户取消 pin 后，island 收到屏幕顶部外，鼠标进入顶部唤出区或 island 区域时用 0.26s ease-in-out 动画滑出。鼠标悬停到 island 后，右侧 SF Symbols pin 和 gear 才随宽度动画显现，展开账号面板时保持可见。pin 状态写入 `UserDefaults` 的 `AgentBar.pinnedOpen`，重启后继续沿用；缺少该 key 时按 pinned open 处理。刘海屏 notch-aware island 固定在顶部，不参与 auto-hide，右侧 gear 同样只在悬停或展开时显现。
8. PIN 右侧的 gear icon 打开独立设置窗口。窗口采用紧凑 macOS preferences 布局，默认宽度 640pt，最小宽度 480pt：Light 模式下左侧 sidebar 使用 `#E6E5E3`，右侧正文使用 `#F3F1EF`，grouped settings 卡片使用 `#EFEDEB`，列表选中态使用 `#226CFF`；Dark 模式下这些背景、边框、分隔线和 Usage heatmap 辅助色跟随系统 appearance 切到深色 token，文字继续使用系统动态 label 色，避免浅底白字或深底黑字。General 页的 `Launch at Login` 调用 `SMAppService.mainApp` 注册/取消开机启动，`Automatic Updates` 控制 Sparkle 的自动下载/安装模式，更新检查始终保持开启，`Auto Collapse Delay` 写入 `UserDefaults` 的 `AgentBar.expansionAutoCollapseDelayMilliseconds`；Accounts 页展示所有已见 Codex 账号、当前账号状态、邮箱下方的 5h/7d quota 进度条，以及贴在 plan chip 右侧的小型切换控件，账号列表按内容完整撑开，滚动发生在右侧正文主体但不显示滚动条；Usage 页 header 第一行显示 `Daily Tokens`，第二行左侧提供 Day/Year segmented control，中间居中显示日期/年份切换，右侧显示 `Total x Tokens`；Year 保持类似 GitHub contribution calendar 的年度 token 热力图并支持在当前年份和最早有数据年份之间切换，年度热力图保持完整宽度但在设置窗口较窄时由卡片内部横向滚动承载，横向滚动同样不显示滚动条；Day 提供按自然日左右切换的日期控制，跨月和跨年由 Calendar 加减天处理，下面先展示所选日期 24 小时 token 消耗堆叠柱状图，再展示 Vibe Coding Time 折线/面积图和当日活跃总时长；Day 只为当天实际出现的模型生成颜色和 legend，不预置未出现的模型名称，图表不声明固定宽度，窗口变窄时按可用宽度重排，柱间距逐步缩小，最窄时允许柱子贴合，hover 单小时柱子时只向上展开 tooltip，显示该小时 token 总量和模型拆分；About 页展示当前版本、更新状态、手动检查/更新按钮和 GitHub 仓库入口。设置窗口使用普通 window level，避免打开后阻止用户切换到其他窗口；打开设置时 app 临时切到 `.regular` 以进入 Command+Tab，关闭设置后切回 `.accessory`，保持平时无 Dock 图标。启动和切入 `.regular` 时显式从 `AgentBar.icns` 设置 `NSApp.applicationIconImage` 并刷新 `NSDockTile`，保证临时 Dock 图标使用 AgentBar logo。
9. `AgentBarUpdater` 启动 Sparkle 后按 `SUFeedURL` 检查 `https://github.com/iFurySt/agent-bar/releases/latest/download/appcast.xml`。它维护一个轻量 `AgentBarUpdateStatus` 供 About 页显示当前版本、最新可用版本、检查中、已最新或失败状态；About 打开时用 `checkForUpdateInformation()` 做不打扰的探测，用户点击按钮时再调用 `checkForUpdates()` 触发 Sparkle 的下载/安装流程。发现可更新版本时，自定义 `SPUUserDriver` 先选择安装以触发后台下载；如果 `Automatic Updates` 已开启，下载和解包完成后直接交给 Sparkle 退出、替换并重启，不再二次确认。未开启时才在准备安装后弹出确认框，用户可选择立即安装、跳过此版本，或打开以后自动更新并安装当前版本；跳过会记录 `AgentBar.updater.skippedVersion`，同一个 `sparkle:version` 不再提醒。安装前会把当前版本和目标版本临时写入 `UserDefaults`，新版本启动后用 macOS 通知提示 `Updated from x to y`，成功投递或发现版本不匹配后清掉这条待通知记录，避免重复提醒。
10. `ClaudeUsageClient` 读取 `~/.claude/.credentials.json`，找不到文件时回退到 macOS Keychain 里的
    `Claude Code-credentials`（`ClaudeAuthStore`，用 `#if canImport(Security)` 包住以保持 `AgentBarCore`
    在 Linux CI 上可编译）；`accessToken` 临近过期或请求失败时用 `ClaudeTokenRefresher` 调用
    `platform.claude.com/v1/oauth/token` 刷新并写回原凭据来源。拿到 token 后调用 Anthropic
    `GET /api/oauth/usage`，把 `five_hour`/`seven_day` 两个窗口的 `utilization` 换算成 remaining percent、
    `resets_at` 换算成 reset 倒计时，再把凭据里的 `subscriptionType`（`pro`/`max`/`team`/... ）映射成大写
    plan 标签，一起存进 `AgentBarSnapshot.claudeRateLimits`，随 Codex 快照一起写入 `~/.agentbar/cache.json`。
    这是单账号只读展示：本机没有 Claude Code 凭据时 `claudeRateLimits` 为 nil，展开面板里的
    `ClaudeQuotaView` 整块不渲染，不进入错误态；不做账号切换、也不扫描 Claude Code 本地 session 的
    token/cost。`ClaudeQuotaView` 的 plan 徽章、reset 倒计时和百分比进度条渲染复用和 Codex 账号卡片
    （`AccountBlocksView`）同一套 `AgentBarQuotaMetrics` 绘制辅助函数，避免两处重复实现。

## 边界

- 顶部一行浮窗（收起状态）与 Settings 的 Usage/Accounts 页仍然只服务 Codex；Claude Code 目前只在展开面板
  提供一张单账号、只读的 5h/weekly 配额卡片，不是通用多 provider 架构。
- 不提供菜单栏状态项或登录流程；当前只有顶部 gear 设置窗口承载开机启动、自动更新、Usage Day/Year 视图、About 版本/更新状态与 GitHub 入口，以及 pin 和跳过更新版本这些本地偏好。
- 打包发布只覆盖 macOS DMG 和 Sparkle appcast；当前不提供 Homebrew 或 App Store 分发。
- 不上传本地 session 内容；所有 cost/token 汇总都在本机完成。
