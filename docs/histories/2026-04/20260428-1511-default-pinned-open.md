## [2026-04-28 15:11] | Task: 默认固定显示新安装用户的 AgentBar

### 🤖 Execution Context

- **Agent ID**: `codex`
- **Base Model**: `GPT-5`
- **Runtime**: `local CLI`

### 📥 User Query

> 新用户默认应该是 PIN，避免用户安装后不知道 app 已经打开。

### 🛠 Changes Overview

**Scope:** AgentBar AppKit 偏好与交互文档

**Key Actions:**

- **[Action 1]**: 将 `AgentBar.pinnedOpen` 缺省读取改为 `true`，保留已有用户明确保存的 pin/unpin 选择。
- **[Action 2]**: 同步架构、界面协作说明和功能发布记录，明确新用户首次启动默认 pinned open，取消 pin 后才进入 auto-hide。

### 🧠 Design Intent (Why)

新用户安装后如果普通屏默认 auto-hide，容易误以为应用没有启动。默认固定显示能让首次反馈更明确，同时仍允许用户主动取消 pin 来恢复低打扰的自动隐藏模式。

### 📁 Files Modified

- `Sources/AgentBar/App.swift`
- `docs/ARCHITECTURE.md`
- `docs/FRONTEND.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260428-1511-default-pinned-open.md`
