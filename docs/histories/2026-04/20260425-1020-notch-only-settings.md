## [2026-04-25 10:20] | Task: 调整刘海屏控制项

### 🤖 Execution Context

- **Agent ID**: `Codex Assistant`
- **Base Model**: `GPT-5.5`
- **Runtime**: `macOS / AppKit`

### 📥 User Query

> 有 notch 的屏幕不需要 PIN，只需要有设置即可。

### 🛠 Changes Overview

**Scope:** 显示层布局与项目文档

**Key Actions:**

- **[Action 1]**: 在 `Sources/AgentBar/App.swift` 让 notch 样式不显示 `Pin`，只在右侧显示 `Settings` 按钮。
- **[Action 2]**: 调整 notch 右侧可用宽度和按钮布局逻辑，避免在没有 pin 的情况下与百分比文本发生重叠。
- **[Action 3]**: 同步更新 `README.md`、`docs/ARCHITECTURE.md`、`docs/FRONTEND.md` 的行为描述。

### 🧠 Design Intent (Why)

用户端统一偏好要求刘海屏以更简洁交互展示设置入口，避免 pin 对紧凑 notch 空间造成干扰；相比 pin，刘海屏场景下固定显示行为本身对用户可访问性已够用。

### 📁 Files Modified

- `Sources/AgentBar/App.swift`
- `README.md`
- `docs/ARCHITECTURE.md`
- `docs/FRONTEND.md`
