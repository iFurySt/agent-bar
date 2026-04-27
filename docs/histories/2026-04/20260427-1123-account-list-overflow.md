## [2026-04-27 11:23] | Task: account list overflow

### 🤖 Execution Context

- **Agent ID**: `Codex`
- **Base Model**: `GPT-5`
- **Runtime**: `local CLI`

### 📥 User Query

> 确认账号下拉为什么只显示 4 个，并选择一个更适合超过 4 个账号的方案后落地。

### 🛠 Changes Overview

**Scope:** AgentBar account expansion and settings window

**Key Actions:**

- **[Action 1]**: 保持顶部 island 展开区最多展示 4 个账号，但超过 4 个账号时新增 `View N more accounts` 入口，避免后续账号静默消失。
- **[Action 2]**: Settings 新增 Accounts 页面，展示所有已见 Codex 账号、当前账号状态、5h/7d quota 和切换按钮。
- **[Action 3]**: 从展开区的更多入口直接打开 Settings Accounts 页，并复用现有账号切换逻辑刷新顶部浮窗。
- **[Action 4]**: Accounts 页改为读取顶部浮窗当前持有的账号快照，并让 `cachedAccounts()` 优先复用 latest snapshot 里的账号 quota，避免每次切入 Accounts 都重新拉取并闪回 `--%`。
- **[Action 5]**: 将展开区底部更多入口从 CTA 文案改成 macOS disclosure row：左侧 `person.2` 和 `All Accounts`，右侧低对比数量与 chevron。
- **[Action 6]**: 将 Settings Accounts section header 移到 grouped block 外部，并把列表改成透明 grouped rows：一行一个账号，复用底层 card 背景，右侧保留 `Switch`/`Current` 文本 chip。
- **[Action 7]**: 让 Accounts section header 只保留轻微横向内缩，避免贴边但仍与下面的 grouped block 保持同一视觉宽度。
- **[Action 8]**: 让 Accounts grouped block 按账号行内容高度收缩，账号很多时才在 block 内滚动，避免边框无意义撑到窗口底部。
- **[Action 9]**: 将 Usage 的 `Daily Tokens` header 同样移到 grouped block 外部，保持和 Accounts 页一致的 section 结构。
- **[Action 10]**: 收紧 Usage heatmap 固定高度，去掉网格下方由 190pt 画布留下的多余空白。
- **[Action 11]**: Usage summary 和 heatmap hover 复用顶部 bar 的 token formatter，让超过 1000M 的值进位到 B，例如 `9161.8M` 显示为 `9.2B`。
- **[Action 12]**: 将 Usage heatmap tooltip 从热力图 view 内部提升到 Usage 页面级 overlay，避免 tooltip 被 heatmap/card bounds 限制而挤压。
- **[Action 13]**: 同步更新架构、界面规范和功能发布记录，明确超过 4 个账号时不在顶部浮窗里做滚动列表。

### 🧠 Design Intent (Why)

顶部 island 是短停留、会自动收回的轻量浮窗，滚动列表会让发现和操作都变得隐蔽。超过 4 个账号属于管理场景，因此展开区只保留最近账号和明确入口，完整查看与切换放到 Settings 的 Accounts 页。

Settings Accounts 不应该拥有独立刷新节奏。顶部浮窗已经负责每 60 秒刷新账号 usage，设置页只是同一份运行时快照的管理视图；如果启动时只有磁盘缓存，也应优先使用 latest snapshot 中带 quota 的账号数据，再回落到只含身份信息的 `accounts.json`。

### 📁 Files Modified

- `Sources/AgentBar/App.swift`
- `Sources/AgentBar/AgentBarSettings.swift`
- `Sources/AgentBarCore/CodexSnapshotService.swift`
- `docs/ARCHITECTURE.md`
- `docs/FRONTEND.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260427-1123-account-list-overflow.md`
