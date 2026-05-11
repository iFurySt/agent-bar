## [2026-05-11 14:30] | Task: 支持刘海屏 pin/unpin

### 🤖 Execution Context

- **Agent ID**: `Codex`
- **Base Model**: `GPT-5`
- **Runtime**: `Codex CLI`

### 📥 User Query

> 现在 mac 14 寸刘海屏是不是不支持 pin/unpin，改成也支持

### 🛠 Changes Overview

**Scope:** `Sources/AgentBar` 顶部 island 行为与相关文档

**Key Actions:**

- **[Action 1]**: 让 notch 屏幕也通过 `agentBarSupportsAutoHide` 参与 auto-hide eligibility。
- **[Action 2]**: notch 布局改为显示 pin 与 settings 两个 hover 控制，取消 pin 后可收进屏幕顶边。
- **[Action 3]**: 同步架构、前端、稳定性、质量评分和用户发布记录，移除“刘海屏无 pin/固定常驻”的旧描述。

### 🧠 Design Intent (Why)

14 寸内建刘海屏和外接普通屏都需要同一套“默认固定、用户取消 pin 后低打扰自动隐藏”的控制语义。刘海屏的差异应该只体现在 notch-aware 紧凑视觉布局和中心物理 notch 禁区，而不是功能能力缺失。

### 📁 Files Modified

- `Sources/AgentBar/App.swift`
- `docs/ARCHITECTURE.md`
- `docs/FRONTEND.md`
- `docs/RELIABILITY.md`
- `docs/QUALITY_SCORE.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-05/20260511-1430-notch-pin-unpin-auto-hide.md`
