## [2026-04-27 18:11] | Task: Hide settings scrollbars

### 🤖 Execution Context

- **Agent ID**: `Codex`
- **Base Model**: `GPT-5`
- **Runtime**: `Codex CLI`

### 📥 User Query

> gear 打开的所有页面都要隐藏滚动条，滚动的时候也不要看到滚动条。

### 🛠 Changes Overview

**Scope:** AgentBar settings window UI

**Key Actions:**

- **[Action 1]**: 将 Settings 主内容滚动视图改为保留滚动手势但不创建可见 scroller。
- **[Action 2]**: 将 Usage 热力图内部横向滚动视图改为保留横向滚动但不显示 scroller。
- **[Action 3]**: 更新架构、前端规范和面向用户发布记录，明确 gear 设置窗口滚动条隐藏约束。

### 🧠 Design Intent (Why)

Settings 的 Accounts 页面和 Usage 热力图都可能超出窗口尺寸，但这个窗口走轻量 preferences 视觉，显式滚动条会占用空间并破坏简洁感。保留滚动手势、隐藏 scroller，可以让长账号列表和 Usage 横向热力图继续可操作，同时维持干净外观。

### 📁 Files Modified

- `Sources/AgentBar/AgentBarSettings.swift`
- `docs/ARCHITECTURE.md`
- `docs/FRONTEND.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260427-1811-hide-settings-scrollbars.md`
