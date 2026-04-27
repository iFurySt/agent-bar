## [2026-04-27 12:12] | Task: Account switch hover affordance

### 🤖 Execution Context

- **Agent ID**: `Codex`
- **Base Model**: `GPT-5`
- **Runtime**: `Codex CLI`

### 📥 User Query

> 账号卡片里的切换 icon 需要更明确：鼠标移上去变成手型 cursor，icon 也要有 hover 样式。

### 🛠 Changes Overview

**Scope:** AgentBar account expansion UI

**Key Actions:**

- **[Action 1]**: 为账号展开视图增加 mouse tracking，鼠标移动到非当前账号切换按钮时显式切换为 pointing hand cursor。
- **[Action 2]**: 记录当前 hover 的切换按钮账号，并在绘制时提高按钮背景、描边和 icon 颜色反馈。

### 🧠 Design Intent (Why)

账号卡片整体主要用于阅读 quota，真正会修改 Codex live auth 的操作只在切换 icon 上。让 cursor 和 hover 样式都绑定到这个小按钮，可以明确可点击区域，同时避免把整张卡片误导成可点击操作。

### 📁 Files Modified

- `Sources/AgentBar/App.swift`
- `docs/histories/2026-04/20260427-1212-account-switch-hover.md`
