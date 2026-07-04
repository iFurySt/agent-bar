## [2026-07-04 17:00] | Task: 接入 Claude Code 5h/weekly 配额

### 🤖 Execution Context

- **Agent ID**: `claude-code-cli`
- **Base Model**: `claude-sonnet-5`
- **Runtime**: `Claude Code CLI`

### 📥 User Query

> 参考 tokscale 项目里 Claude Code 的统计方式，agent-bar 目前只支持 Codex，需要能读取当前在用的 Claude
> Code。确认范围：第一版只做顶部浮窗展开面板里的 5h/weekly 配额展示；Claude Code 单账号，不需要账号切换；
> 收起状态的顶部一行仍然只显示 Codex，配额卡片只在点开展开面板后可见。

### 🛠 Changes Overview

**Scope:** `Sources/AgentBarCore`, `Sources/AgentBar`, `Tests/AgentBarCoreTests`, `docs/`

**Key Actions:**

- **凭据读取**：新增 `ClaudeAuth.swift`，读 `~/.claude/.credentials.json`，找不到时回退到 macOS Keychain
  的 `Claude Code-credentials`；`Security` 框架访问用 `#if canImport(Security)` 包住，保证
  `AgentBarCore` 仍能在 Linux CI 上 `swift test`。临近过期或请求失败时用 `ClaudeTokenRefresher` 调
  `platform.claude.com/v1/oauth/token` 刷新，并写回原凭据来源（文件或 Keychain）。
- **配额查询**：新增 `ClaudeUsageClient.swift`，调用 Anthropic `GET /api/oauth/usage`，解析
  `five_hour`/`seven_day` 两个窗口的 `utilization` 换算成 remaining percent。
- **快照接入**：`AgentBarSnapshot` 新增可选的 `claudeRateLimits` 字段，`CodexSnapshotService.snapshot()`
  并发拉取 Codex + Claude 数据；`AgentBarCacheStore` 的 `CachedAgentBarSnapshot` 新增同名可选字段（additive
  optional 字段，无需 bump cache version）。
- **UI**：新增 `ClaudeQuotaView`（`Sources/AgentBar/App.swift`），只在顶部浮窗展开时渲染，本机未登录
  Claude Code（凭据读取失败）时整块不渲染，不进入错误态；新增 `ProviderIcon-claude.svg` 图标资源；抽出
  `AgentBarResources.url(for:withExtension:)` 消除和 Codex 图标加载重复的资源查找代码。
- **测试**：新增 `ClaudeAuthTests.swift` 覆盖凭据 JSON 解析和 `needsRefresh` 边界，`ClaudeUsageClientTests`
  覆盖 remaining percent 的 clamp/取整逻辑。
- **验证**：本机手动编译一个独立 smoke 脚本直接调用 `ClaudeUsageClient().fetchRateLimits()`，确认真实读取
  本机 Keychain 凭据、调用 Anthropic usage API 并拿到真实 5h/weekly 百分比。

### 🧠 Design Intent (Why)

- 按用户明确的范围收窄：不做 Claude Code 本地 session 的 token/cost 扫描（tokscale 的
  `claudecode.rs` 那一套），不做账号切换/多账号持久化，收起状态的一行文案继续只服务 Codex——缩小这次改动
  的架构影响面，同时验证配额读取链路是否可靠。
- `AgentBarCore` 要在 macOS 和 Linux CI 上都能编译，Keychain 访问必须做平台条件编译，否则会破坏现有
  `swift test` on ubuntu-latest 的 CI job。
- 找不到凭据时整块隐藏而不是报错，是因为很多用户根本没有装 Claude Code，不应该在顶部浮窗里制造噪音。

### 📁 Files Modified

- `Sources/AgentBarCore/ClaudeAuth.swift`（新增）
- `Sources/AgentBarCore/ClaudeUsageClient.swift`（新增）
- `Sources/AgentBarCore/CodexSnapshotService.swift`
- `Sources/AgentBarCore/AgentBarCacheStore.swift`
- `Sources/AgentBar/App.swift`
- `Sources/AgentBar/Resources/ProviderIcon-claude.svg`（新增）
- `Tests/AgentBarCoreTests/ClaudeAuthTests.swift`（新增）
- `docs/ARCHITECTURE.md`
- `docs/exec-plans/active/claude-code-quota.md`（新增，待归档到 `completed/`）

## [2026-07-04 22:10] | Task: 补充 reset 倒计时和 plan 徽章（v0.1.20 发布后的用户反馈）

### 📥 User Query

> v0.1.20 发布后看实际效果，发现 Claude Code 配额卡片缺少 reset 时间，而且账号旁边应该像 Codex 一样带上
> PRO 之类的账号等级标签。

### 🛠 Changes Overview

- `ClaudeAuthCredentials` 新增 `subscriptionType` 字段（解析自 Keychain/文件里的
  `claudeAiOauth.subscriptionType`），刷新 token 时透传保留。
- `ClaudeUsageResponse.Window` 新增 `resets_at` 字段解析（ISO8601，带微秒和 `+00:00` 时区偏移，用
  `withFractionalSeconds` 兜底再退化到无小数秒解析）；`ClaudeRateLimitSnapshot` 新增
  `fiveHourResetAt`/`weeklyResetAt`/`plan`，`plan` 由 `subscriptionType` 映射成大写标签（`pro` → `PRO`，
  `max` → `MAX`，等等，未知值退化成大写下划线转空格）。
- 把 `AccountBlocksView`（Codex）和 `ClaudeQuotaView`（Claude Code）里三份几乎一样的 chip / metric row /
  countdown / percentColor 绘制代码收敛成共享的 `AgentBarQuotaMetrics` enum，两边都改成调用它，不再各自
  维护一份。
- `ClaudeQuotaView` 标题行加回 plan 徽章（复用 Codex 同款蓝色 chip 样式），5h/7d 行加回 `resets Xh Ym`
  文本。
- 新增/更新测试：`ClaudeAuthTests.testParsesCredentialsFileFormat` 断言 `subscriptionType`；
  `ClaudeUsageClientTests` 新增 `testPlanLabelMapsKnownSubscriptionTiers`，`testDecodesUsageResponseSnakeCaseWindows`
  补充 `resets_at` 断言。
- 验证：用独立编译的 AppKit 脚本把 `ClaudeQuotaView.draw` 渲染成 PNG 检查视觉效果（PRO 徽章 + reset 倒计时
  和 Codex 账号卡片布局一致），未直接操作用户正在运行的 AgentBar.app。

### 🧠 Design Intent (Why)

- 用户是拿 Codex 账号卡片截图对比着提的需求，目标就是让 Claude Code 卡片在信息密度上向 Codex 账号卡片
  看齐，而不是发明新样式。
- 三份重复的绘制代码已经出现在两个不同的 view 里，继续复制会变成第三份，这次顺手抽成共享 helper。

### 📁 Files Modified

- `Sources/AgentBarCore/ClaudeAuth.swift`
- `Sources/AgentBarCore/ClaudeUsageClient.swift`
- `Sources/AgentBar/App.swift`
- `Tests/AgentBarCoreTests/ClaudeAuthTests.swift`
- `docs/ARCHITECTURE.md`
- `docs/releases/feature-release-notes.md`
