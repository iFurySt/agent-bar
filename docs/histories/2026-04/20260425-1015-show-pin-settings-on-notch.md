## [2026-04-25 10:15] | Task: 在刘海屏上显示 pin 与设置

### 🤖 Execution Context

- **Agent ID**: `Codex Assistant`
- **Base Model**: `GPT-5.5`
- **Runtime**: `macOS / AppKit`

### 📥 User Query

> 当前 PIN 和设置只显示在没有 notch 的屏幕上，希望在有 notch 的屏幕上也显示。

### 🛠 Changes Overview

**Scope:** AppKit 显示层与架构/前端文档

**Key Actions:**

- **[Action 1]**: 修改 `Sources/AgentBar/App.swift` 中 `IslandView` 的 notch 布局配置，允许 notch 模式展示 pin 和 settings 按钮，并加入对应按钮布局逻辑。
- **[Action 2]**: 调整 notch 模式的宽度计算与按钮定位，避免与 `5h/7d` 百分比文字相互覆盖。
- **[Action 3]**: 更新 `docs/ARCHITECTURE.md` 与 `docs/FRONTEND.md`，同步行为说明，去除“notch 屏不显示 pin/settings”的描述。

### 🧠 Design Intent (Why)

该需求是保持无刘海屏与刘海屏的一致交互入口。Pin 与设置是核心操作入口，按统一入口策略在所有屏幕都可见可用，减少用户在不同屏幕上切换时的操作认知差异。

### 📁 Files Modified

- `Sources/AgentBar/App.swift`
- `docs/ARCHITECTURE.md`
- `docs/FRONTEND.md`
