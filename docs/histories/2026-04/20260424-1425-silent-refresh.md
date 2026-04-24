## [2026-04-24 14:25] | Task: make periodic refresh silent

### 🤖 Execution Context

- **Agent ID**: `Codex`
- **Base Model**: `GPT-5`
- **Runtime**: `local macOS SwiftPM`

### 📥 User Query

> 定时更新不要显示小绿点，所有更新都应该静默完成。

### 🛠 Changes Overview

**Scope:** AgentBar AppKit UI and docs

**Key Actions:**

- **Removed refresh affordance**: Deleted the pulsing green status dot and all refresh-state layout width from `IslandView`.
- **Made refresh silent**: Stopped repainting overlays only to show refresh start/end state; periodic updates now only refresh displayed text when new data is available.
- **Synced docs**: Updated architecture, reliability, and quality notes to describe silent background refresh.

### 🧠 Design Intent (Why)

The widget should be glanceable and low-distraction. A short-lived refresh indicator can flash during fast incremental scans, so refresh progress is intentionally hidden.

### 📁 Files Modified

- `Sources/AgentBar/App.swift`
- `docs/ARCHITECTURE.md`
- `docs/RELIABILITY.md`
- `docs/QUALITY_SCORE.md`
