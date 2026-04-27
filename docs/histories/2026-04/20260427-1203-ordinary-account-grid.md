## [2026-04-27 12:03] | Task: Ordinary screen account grid

### 🤖 Execution Context

- **Agent ID**: `Codex`
- **Base Model**: `GPT-5`
- **Runtime**: `Codex CLI`

### 📥 User Query

> 非 notch 屏幕展开账号列表时一行一个账号太长，希望一行显示 2 个账号，最多展示 8 个账号，更好利用已有空间。
> 后续补充：如果只有一个账号，no-notch bar 展开区应自动变成一行一个；账号数大于 1 时才进入一行 2 个的逻辑。

### 🛠 Changes Overview

**Scope:** AgentBar account expansion UI

**Key Actions:**

- **[Action 1]**: 为账号展开视图增加 ordinary/notch presentation，普通屏使用 2 列最多 8 个账号，notch 继续使用 1 列最多 4 个账号。
- **[Action 2]**: 将展开高度、账号卡片布局、more row 位置和隐藏账号数量统一改为基于当前 presentation 计算。
- **[Action 3]**: 同步架构、界面规范和发布记录中的账号展开区描述。
- **[Action 4]**: 将普通屏列数改为按可见账号数计算，只有 1 个账号时单列满宽，超过 1 个账号时才使用两列。

### 🧠 Design Intent (Why)

无 notch 普通屏的顶部 island 本身展示完整 usage 文案，横向空间比 notch 场景更充足。展开区在多账号时继续单列会让账号卡片过长且垂直空间浪费；超过 1 个账号后改为 2 列可以在同样轻量浮层里展示最多 8 个账号。只有 1 个账号时保持单列满宽，避免单张卡片被压成半宽且右侧留下空白，同时保持超过上限时进入 Settings Accounts 页的管理路径。

### 📁 Files Modified

- `Sources/AgentBar/App.swift`
- `docs/ARCHITECTURE.md`
- `docs/FRONTEND.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260427-1203-ordinary-account-grid.md`
