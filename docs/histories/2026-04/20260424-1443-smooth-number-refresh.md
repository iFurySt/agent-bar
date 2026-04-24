## [2026-04-24 14:43] | Task: smooth numeric refresh changes

### 🤖 Execution Context

- **Agent ID**: `Codex`
- **Base Model**: `GPT-5`
- **Runtime**: `local macOS SwiftPM`

### 📥 User Query

> 数字刷新时不要因为 99 到 100 这类位数变化突然跳宽；数字应该滚动上去，宽度变化也要动画过渡。

### 🛠 Changes Overview

**Scope:** AgentBar AppKit UI and docs

**Key Actions:**

- **Added rolling digits**: Replaced the direct `NSTextField` labels with `RollingTextLabel`, which draws changed digits as a short upward roll.
- **Animated width changes**: Data refresh updates now animate island frame changes with a 0.44s ease-in-out transition, so extra digits do not make the island jump.
- **Respected Reduce Motion**: Numeric and width animations fall back to immediate updates when the system Reduce Motion setting is enabled.
- **Synced docs**: Updated architecture, frontend, reliability, and quality notes for the smoother refresh behavior.

### 🧠 Design Intent (Why)

The widget sits in peripheral vision. Smooth digit and width transitions reduce attention-grabbing jumps while preserving the silent refresh model.

### 📁 Files Modified

- `Sources/AgentBar/App.swift`
- `docs/ARCHITECTURE.md`
- `docs/FRONTEND.md`
- `docs/RELIABILITY.md`
- `docs/QUALITY_SCORE.md`
