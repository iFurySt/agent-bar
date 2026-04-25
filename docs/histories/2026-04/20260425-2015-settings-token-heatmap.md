## [2026-04-25 20:15] | Task: Add settings token heatmap

### 🤖 Execution Context

- **Agent ID**: `Codex`
- **Base Model**: `GPT-5`
- **Runtime**: `Codex CLI`

### 📥 User Query

> 在设置里新增一个类似 GitHub 个人页日历热力图的页面，基于 CodexBar 和 Codex 源码统计每天的 Tokens 消耗量并存到 `~/.agentbar/`，要能区分同一个 session 跨天继续消耗的 token，并避免大量重复计算。

### 🛠 Changes Overview

**Scope:** `AgentBar`, `AgentBarCore`, docs

**Key Actions:**

- **[Usage heatmap]**: 新增设置窗口 Usage 页面，展示按年份切换的 Codex token 热力图和总量摘要。
- **[Daily scanner]**: `CodexCostScanner` 新增日级 token usage 接口，复用 `~/.agentbar/cache.json` 的 per-session-file day/model 聚合。
- **[Cross-day handling]**: 分日依据每条 `token_count` 的 timestamp，同一个长期 session 在不同日期追加时会拆到对应自然日。
- **[Old session lookup]**: 扫描范围除日期目录外补捞最近修改过的旧日期目录 JSONL，避免长期 session 仍存放在创建日目录时漏算。
- **[Heatmap styling]**: 热力图补齐月份和 Mon/Wed/Fri 标尺，使用接近 CodexBar 风格的浅灰/青绿色格子，并在 hover 时显示深色浮层，包含日期、美元消耗和 Tokens。
- **[Year navigation]**: Usage header 中增加年份左右切换，范围限制在当前年份和最早有数据年份之间；热力图按所选年份的 Jan-Dec 绘制，不再显示滚动的 371 days。
- **[Tests/docs]**: 增加跨天 session 和旧目录补捞测试，同步架构、可靠性、安全、前端和 release note 文档。

### 🧠 Design Intent (Why)

热力图只需要本机聚合后的 token 日历，不应该保存 prompt、回复或工具输出。沿用现有 cost scanner 的文件 size/mtime 缓存可以避免历史 session 越来越多后每次设置页打开都全量重算；按 event timestamp 拆分增量则能处理同一个 session 跨天继续工作的场景。

### 📁 Files Modified

- `Sources/AgentBar/AgentBarSettings.swift`
- `Sources/AgentBarCore/CodexCostScanner.swift`
- `Tests/AgentBarCoreTests/CodexCostScannerTests.swift`
- `docs/ARCHITECTURE.md`
- `docs/FRONTEND.md`
- `docs/QUALITY_SCORE.md`
- `docs/RELIABILITY.md`
- `docs/SECURITY.md`
- `docs/releases/feature-release-notes.md`
