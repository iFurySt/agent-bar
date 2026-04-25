## [2026-04-25 18:12] | Task: expanded panel auto collapse

### Execution Context

- **Agent ID**: `Codex`
- **Base Model**: `GPT-5`
- **Runtime**: `Codex CLI`

### User Query

> 鼠标离开展开区后自动向上收回；默认 200ms，并且可以在设置里用 ms 调整。

### Changes Overview

**Scope:** AgentBar account expansion interaction

**Key Actions:**

- **[Action 1]**: 账号展开区复用现有 hover polling，在 `ScreenOverlay` 上记录鼠标离开展开面板的时间点。
- **[Action 2]**: 鼠标连续离开面板达到用户配置的毫秒数后自动收起展开区；鼠标回到面板内会清空离开时间并重新计算。
- **[Action 3]**: 设置窗口新增 `Auto Collapse Delay` stepper，默认 200ms，可在 100 到 5000ms 之间按 100ms 调整。
- **[Action 4]**: 同步架构、界面规范和 release notes，记录展开区自动收回行为。

### Design Intent (Why)

展开区用于临时查看和切换账号 quota，鼠标离开后应自然回到顶部 island 的轻量状态。计时从离开面板后开始，而不是从展开时开始，避免用户正在查看或操作账号卡片时被自动收起；等待时间进入设置窗口，避免固定时长不适合不同使用节奏。

### Files Modified

- `Sources/AgentBar/App.swift`
- `Sources/AgentBar/AgentBarSettings.swift`
- `docs/ARCHITECTURE.md`
- `docs/FRONTEND.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260425-1812-expanded-panel-auto-collapse.md`
