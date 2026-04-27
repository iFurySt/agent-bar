## [2026-04-27 16:18] | Task: Settings dark mode

### 🤖 Execution Context

- **Agent ID**: `Codex`
- **Base Model**: `GPT-5`
- **Runtime**: `Codex CLI local workspace`

### 📥 User Query

> gear 打开设置窗口后，如果系统是 Dark 模式，字体变白但背景仍是浅色；需要自动检测系统 Light/Dark 模式并自动切换。

### 🛠 Changes Overview

**Scope:** `Sources/AgentBar`

**Key Actions:**

- **[Settings Theme]**: 将设置窗口 palette 改为基于 `NSAppearance` 的动态颜色，Light 模式保留原 macOS preferences 浅色 token，Dark 模式切换到深色 sidebar、正文、卡片、边框、分隔线和 Usage heatmap 辅助色。
- **[Layer Refresh]**: 为 layer-backed 背景、sidebar、card 和 separator 增加 appearance 变化后的 layer color 刷新，避免系统模式切换后继续使用旧 `CGColor`。
- **[Docs]**: 同步架构、前端规范和发布记录，明确 gear 设置窗口必须跟随系统 Light/Dark 自动适配。

### 🧠 Design Intent (Why)

设置窗口原本背景是固定浅色 `CGColor`，但文本使用系统动态 label 色；系统处于 Dark 模式时 label 会变白，造成浅色背景上的白字。背景和辅助色应与系统 appearance 一起动态切换，同时继续复用 AppKit 动态文本色，保持 macOS 原生可读性。

### 📁 Files Modified

- `Sources/AgentBar/AgentBarSettings.swift`
- `docs/ARCHITECTURE.md`
- `docs/FRONTEND.md`
- `docs/releases/feature-release-notes.md`
