## [2026-04-25 19:30] | Task: Hide zero progress fill

### 🤖 Execution Context

- **Agent ID**: `Codex`
- **Base Model**: `GPT-5`
- **Runtime**: `Codex CLI`

### 📥 User Query

> 0% 的进度条不要显示小红点，直接显示整条灰色。

### 🛠 Changes Overview

**Scope:** `Sources/AgentBar`

**Key Actions:**

- **[Progress drawing]**: 账号卡片 quota 小进度条在 clamped ratio 为 0 时跳过彩色填充，只保留灰色 track。
- **[History]**: 记录本次 UI 绘制修正。

### 🧠 Design Intent (Why)

0% 表示没有剩余额度，继续强制绘制最小 5pt 红色填充会制造一个误导性的小红点；0 时只显示灰色 track 更符合状态语义。

### 📁 Files Modified

- `Sources/AgentBar/App.swift`
- `docs/histories/2026-04/20260425-1930-hide-zero-progress-fill.md`
