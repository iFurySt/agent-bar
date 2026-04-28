## [2026-04-28 14:36] | Task: 修正 Usage 本地时区归属

### Execution Context

- **Agent ID**: `Codex`
- **Base Model**: `GPT-5`
- **Runtime**: `Codex CLI`

### User Query

> 现在的 Usage 里的时间，不应该默认 UTC，读取用户本地的时区来使用。

### Changes Overview

**Scope:** AgentBarCore cost scanner, Settings Usage UI, docs

**Key Actions:**

- **[Action 1]**: 将 `CodexCostScanner` 默认日历改为 `Calendar.autoupdatingCurrent`，让 Year/Day 聚合按用户本地时区归属。
- **[Action 2]**: Usage 日期显示、热力图 tooltip 和月份标尺使用自动更新的本地时区。
- **[Action 3]**: cost 文件缓存记录聚合时区；旧缓存缺少时区或用户时区变化时重新解析，避免复用旧的 UTC day/hour key。
- **[Action 4]**: Usage activity scanner 同样改用自动更新的本地日历，避免同一页面里 token 和 activity 使用不同日界线。
- **[Action 5]**: 增加 UTC 与 Asia/Shanghai 日界线测试，覆盖本地 00 点附近的日期和小时重分桶。

### Design Intent (Why)

Usage 面向用户查看自己的本地工作节奏，日视图和年度热力图都应该按用户本机时区解释 session timestamp。只改显示不够，因为缓存里的 day/hour key 可能已经按旧时区算好；缓存也必须带上时区维度。

### Files Modified

- `Sources/AgentBarCore/CodexCostScanner.swift`
- `Sources/AgentBarCore/CodexActivityScanner.swift`
- `Sources/AgentBarCore/AgentBarCacheStore.swift`
- `Sources/AgentBar/AgentBarSettings.swift`
- `Tests/AgentBarCoreTests/CodexCostScannerTests.swift`
- `docs/ARCHITECTURE.md`
- `docs/FRONTEND.md`
- `docs/RELIABILITY.md`
- `docs/SECURITY.md`
- `docs/releases/feature-release-notes.md`
