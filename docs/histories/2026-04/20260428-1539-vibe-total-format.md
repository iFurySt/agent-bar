## [2026-04-28 15:39] | Task: 统一 Vibe 总时长格式

### 🤖 Execution Context

- **Agent ID**: `Codex`
- **Base Model**: `GPT-5`
- **Runtime**: `Codex CLI`

### 📥 User Query

> Vibe Coding Time 里的 `2h 39m Total` 改成 `Total 2h39m`，这样更统一。

### 🛠 Changes Overview

**Scope:** Usage Day 视图 Vibe Coding Time header

**Key Actions:**

- **[Usage UI]**: 将 Vibe Coding Time 标题行右侧汇总从后置 `Total` 改为前置 `Total`。
- **[Duration formatting]**: 为 duration formatter 增加紧凑模式，只在 Vibe 总时长汇总里去掉小时和分钟之间的空格。

### 🧠 Design Intent (Why)

Day 视图里的汇总文案统一采用 `Total <value>` 结构；Vibe 总时长使用 `2h39m` 这样的紧凑写法，减少标题行右侧占宽并和用户期望一致。

### 📁 Files Modified

- `Sources/AgentBar/AgentBarSettings.swift`
- `docs/histories/2026-04/20260428-1539-vibe-total-format.md`
