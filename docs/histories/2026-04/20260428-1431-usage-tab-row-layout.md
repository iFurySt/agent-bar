## [2026-04-28 14:31] | Task: 调整 Usage 切换控件布局

### 🤖 Execution Context

- **Agent ID**: `Codex`
- **Base Model**: `GPT-5`
- **Runtime**: `local CLI`

### 📥 User Query

> Usage 里的 Day/Year 切换 tab 移动到 2026 那行的左侧边。

### 🛠 Changes Overview

**Scope:** `Sources/AgentBar`, `docs`

**Key Actions:**

- **Usage header**: 第一行只保留 `Daily Tokens`；第二行左侧放 Day/Year segmented control，中间居中放 2026/日期选择，右侧放 Total 汇总。
- **Docs sync**: 同步更新 UI 约束、架构说明和功能发布记录，记录新的 header 布局。

### 🧠 Design Intent (Why)

Day/Year、年份/日期选择和 Total 都属于 Usage 视图状态，放在同一控制行可以减少上下跳读；年份/日期保持居中，维持图表上方的主视角锚点。

### 📁 Files Modified

- `Sources/AgentBar/AgentBarSettings.swift`
- `docs/ARCHITECTURE.md`
- `docs/FRONTEND.md`
- `docs/releases/feature-release-notes.md`
