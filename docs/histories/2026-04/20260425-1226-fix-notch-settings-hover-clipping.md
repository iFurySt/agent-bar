## [2026-04-25 12:26] | Task: Fix notch settings hover clipping

### 🤖 Execution Context

- **Agent ID**: `Codex`
- **Base Model**: `GPT-5`
- **Runtime**: `Codex CLI`

### 📥 User Query

> 用户反馈 notch 顶部条 hover 展开 settings icon 的动画中间帧会挡住右侧百分比文本，例如 `32%` 短暂只显示为 `3`。

### 🛠 Changes Overview

**Scope:** macOS AppKit overlay layout

**Key Actions:**

- **[Action 1]**: 调整 `IslandView.layoutNotch()` 的右侧布局，让 usage 百分比始终使用完整 intrinsic 宽度。
- **[Action 2]**: 将 pin/settings 按钮放到右侧百分比文本之后，避免展开动画的中间宽度压缩或遮挡文本。
- **[Action 3]**: 修正 notch action controls 的可见性和宽度预留，只在鼠标 hover 时显示 settings 入口。
- **[Action 4]**: 恢复 notch 屏 hover 判定，并在 hover 状态切换时重新计算窗口宽度，确保 settings 入口能随 hover 展开。
- **[Action 5]**: 为 notch hover 展开增加 action icon 延迟显示，避免黑色背景宽度动画未完成时 icon 先露出到背景外。

### 🧠 Design Intent (Why)

notch 样式的窗口宽度会在 hover 展开 settings icon 时做动画。旧布局在中间帧按当前 `bounds` 先预留 action slot，再把 usage 文本宽度压缩到剩余空间，导致数字被裁剪。新布局优先保证百分比文本完整，按钮从文本右侧进入，最终宽度仍由 `fittingSize` 负责提供；settings 入口是 hover affordance，不应在启动后的非 hover 状态常驻显示。notch 屏不参与 auto-hide，但仍需要基于当前 panel frame 做 hover 判定，并在 hover 改变时触发尺寸动画。由于背景宽度动画和按钮显示不是同一绘制层，展开时按钮需要略晚于背景出现，避免 icon 视觉上爆出黑色 island。

### 📁 Files Modified

- `Sources/AgentBar/App.swift`
- `docs/histories/2026-04/20260425-1226-fix-notch-settings-hover-clipping.md`
