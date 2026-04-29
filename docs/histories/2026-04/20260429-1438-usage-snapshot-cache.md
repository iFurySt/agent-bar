## [2026-04-29 14:38] | Task: 缓存 Usage Day/Year 计算结果

### Execution Context

- **Agent ID**: `Codex`
- **Base Model**: `GPT-5`
- **Runtime**: `Codex CLI`

### User Query

> Usage 里的 Day 和 Year 不应该每次重复计算，尤其过去的 Day 数据已经固定，应该计算后存到 `~/.agentbar/` 特定位置，避免快速切换时引发大量计算。
>
> 后续补充：快速从 April 28 连续切到 April 22 时，旧请求不能按 27、26、25、24、23、22 逐个回写；最后只显示停留那一天的数据。

### Changes Overview

**Scope:** AgentBarCore usage scanners, Settings Usage refresh, docs

**Key Actions:**

- **[Action 1]**: 在 `~/.agentbar/cache.json` 增加 Usage 视图级 snapshot 缓存，按时区保存 Year 日级 token、Day 小时级 token 和 Day Vibe Coding Time。
- **[Action 2]**: 过去日期和过去年份直接复用持久化 snapshot；今天和当前年保留短时缓存，用来吸收快速来回切换。
- **[Action 3]**: Settings Usage 刷新改为只计算当前可见的 Day 或 Year 视图，不再每次同时跑两套聚合。
- **[Action 4]**: Usage 日期/年份刷新增加短 debounce、任务取消和刷新序号校验，快速连续切换时只有最后一次请求能写回 UI。
- **[Action 5]**: 增加 token 与 activity 的过去日期/年份缓存复用测试，并同步架构、安全、稳定性和质量文档。

### Design Intent (Why)

Usage 的 per-session 文件缓存只能避免重复解析未变化文件，但 Year/Day 每次仍会重新枚举和聚合目标范围。把视图级结果持久化后，过去数据可以直接读取 snapshot；当前日期和年份仍允许刷新，只用短时缓存降低快速切换造成的重复计算。UI 刷新还需要 latest-wins 语义，因为异步扫描可能乱序返回；旧请求即使完成，也不能覆盖用户最后停留的日期或年份。

### Files Modified

- `Sources/AgentBarCore/CodexCostScanner.swift`
- `Sources/AgentBarCore/CodexActivityScanner.swift`
- `Sources/AgentBarCore/AgentBarCacheStore.swift`
- `Sources/AgentBar/AgentBarSettings.swift`
- `Tests/AgentBarCoreTests/CodexCostScannerTests.swift`
- `Tests/AgentBarCoreTests/CodexActivityScannerTests.swift`
- `docs/ARCHITECTURE.md`
- `docs/SECURITY.md`
- `docs/RELIABILITY.md`
- `docs/QUALITY_SCORE.md`
- `docs/histories/2026-04/20260429-1438-usage-snapshot-cache.md`
