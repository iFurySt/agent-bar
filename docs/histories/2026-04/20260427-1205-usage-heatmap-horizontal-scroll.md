## [2026-04-27 12:05] | Task: Optimize Usage heatmap width

### 🤖 Execution Context

- **Agent ID**: `Codex`
- **Base Model**: `GPT-5`
- **Runtime**: `Codex CLI`

### 📥 User Query

> 设置里的 Usage 年度热力图会把设置窗口撑得很宽，希望默认窗口更窄；当宽度小于热力图宽度时，热力图改为横向滚动。

### 🛠 Changes Overview

**Scope:** AgentBar settings window and Usage heatmap layout

**Key Actions:**

- **[Action 1]**: 将设置窗口默认宽度和最小宽度收紧，让 General、Accounts、About 页面视觉上更协调。
- **[Action 2]**: 将 Usage 年度热力图放入只横向滚动的 `NSScrollView`，热力图本体保持完整年度绘制宽度，不再参与撑宽窗口。
- **[Action 3]**: 更新架构和界面文档，记录 Usage 热力图在紧凑窗口内横向滚动的布局约束。

### 🧠 Design Intent (Why)

年度热力图天然比其他设置内容宽，直接把它作为页面 intrinsic width 会让整个设置窗口为单个页面变宽。把宽度压力限制在 Usage 卡片内部，可以保持窗口默认尺寸紧凑，同时保留完整年度热力图和 hover tooltip 行为。

### 📁 Files Modified

- `Sources/AgentBar/AgentBarSettings.swift`
- `docs/ARCHITECTURE.md`
- `docs/FRONTEND.md`
- `docs/histories/2026-04/20260427-1205-usage-heatmap-horizontal-scroll.md`
