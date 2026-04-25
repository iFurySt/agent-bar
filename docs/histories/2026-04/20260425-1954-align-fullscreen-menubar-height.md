## [2026-04-25 19:54] | Task: Align fullscreen menubar height

### 🤖 Execution Context

- **Agent ID**: `codex`
- **Base Model**: `GPT-5`
- **Runtime**: `Codex CLI`

### 📥 User Query

> Full Screen 应用 hover 顶部菜单栏时，AgentBar 高度和平时固定高度不一致；notch 和无 notch 场景都要保持和系统顶 bar 一样高。

### 🛠 Changes Overview

**Scope:** `Sources/AgentBar`, `docs`

**Key Actions:**

- **[Action 1]**: 在 `agentBarTopBarHeight` 中优先读取 Window Server 当前屏幕的 `Menubar` 窗口高度。
- **[Action 2]**: 将 live `Menubar` 窗口高度归一化为视觉菜单栏高度，避免普通屏多 1pt 或刘海屏把窗口底部额外边缘计入黑色高度。
- **[Action 3]**: 保留原有 `visibleFrame`、safe area 与 notch fallback，避免 live window 探测不可用时影响布局。
- **[Action 4]**: 更新架构和 UI 文档，明确 fullscreen hover 下拉菜单栏也按实时菜单栏高度对齐。

### 🧠 Design Intent (Why)

全屏 app 下系统菜单栏是临时下拉窗口，`NSScreen.visibleFrame` 和 safe area 不一定能表达当前真实顶栏高度；尤其刘海屏上 safe area 可能小于 Window Server 的实际 `Menubar` 窗口高度，而该窗口又可能包含视觉顶栏之外的底部边缘。以 live `Menubar` 窗口作为优先信号并归一化为视觉高度，可以让 AgentBar 在普通桌面、全屏 hover、notch 和无 notch 屏幕上都跟系统顶栏保持同高，同时保留现有 fallback 保证兼容性。

### 📁 Files Modified

- `Sources/AgentBar/App.swift`
- `docs/ARCHITECTURE.md`
- `docs/FRONTEND.md`
- `docs/histories/2026-04/20260425-1954-align-fullscreen-menubar-height.md`
