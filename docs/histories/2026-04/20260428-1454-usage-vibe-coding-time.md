## [2026-04-28 14:54] | Task: Usage Day 增加 Vibe Coding Time

### 🤖 Execution Context

- **Agent ID**: `Codex`
- **Base Model**: `GPT-5`
- **Runtime**: `local CLI`

### 📥 User Query

> 在 Usage Day 的柱状图下面增加 Vibe Coding Time，参考设计图；随后修正为独立 block，跟在原柱状图 block 下面。

### 🛠 Changes Overview

**Scope:** `Sources/AgentBar`, `Sources/AgentBarCore`, `Tests/AgentBarCoreTests`, `docs`

**Key Actions:**

- **[Activity scanner]**: 新增 `CodexActivityScanner`，从本地 session JSONL 的用户消息、token_count、命令、patch、diff 和 collab 事件时间戳计算每日 24 小时 active minutes。
- **[Usage UI]**: 在 Day 视图 token 柱状图下面新增独立的 Vibe Coding Time grouped block，使用紫色折线/面积图展示小时级活跃时间，并显示当日总时长。
- **[Hover and axes]**: 为 Vibe Coding Time 增加小时点 hover tooltip，并将 Y 轴移动到左侧，轴标签颜色、字号和横轴 `Hours` 文案对齐 token 图。
- **[Header summaries]**: Day 模式不再在页面 header 右侧显示 total；token 总量和 Vibe 总时长分别移动到各自图表标题行右侧，并用小圆点标识。
- **[Tests]**: 增加 activity scanner 单测，覆盖 active block 跨小时分摊。
- **[Docs sync]**: 同步更新架构、UI、安全、稳定性和功能发布记录。

### 🧠 Design Intent (Why)

Token 峰值只能说明模型消耗强度，不能表达用户和 Agent 实际协作的时间分布。Vibe Coding Time 复用已有行为模型文档里的 active block 口径，只解析本地时间戳，不展示 prompt 或回复内容；UI 上独立成 block，避免和 token 柱状图争抢同一绘制区域。

### 📁 Files Modified

- `Sources/AgentBar/AgentBarSettings.swift`
- `Sources/AgentBarCore/CodexActivityScanner.swift`
- `Tests/AgentBarCoreTests/CodexActivityScannerTests.swift`
- `docs/ARCHITECTURE.md`
- `docs/FRONTEND.md`
- `docs/SECURITY.md`
- `docs/RELIABILITY.md`
- `docs/releases/feature-release-notes.md`
