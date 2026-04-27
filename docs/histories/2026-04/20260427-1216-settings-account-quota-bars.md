## [2026-04-27 12:16] | Task: Settings account quota bars

### 🤖 Execution Context

- **Agent ID**: `Codex`
- **Base Model**: `GPT-5`
- **Runtime**: `Codex CLI`

### 📥 User Query

> 设置里的 Accounts，我们改一下，5h 7d的变成两条bar放到邮箱下面，类似顶bar展开的那种样式

### 🛠 Changes Overview

**Scope:** AgentBar settings Accounts UI

**Key Actions:**

- **[Action 1]**: 将 Settings Accounts 每个账号行从横向 quota 文本改为邮箱下方的 5h/7d 两条进度 bar。
- **[Action 2]**: 保留右侧 `Switch`/`Current` 控件，并让行高随两条 quota bar 增加。
- **[Action 3]**: 同步更新架构和前端协作文档里的 Accounts 页面说明。

### 🧠 Design Intent (Why)

Accounts 页是完整账号管理场景，5h/7d quota 用两条 bar 放在邮箱下方，比一行压缩文本更接近顶部展开区的阅读节奏，也能减少横向拥挤。

### 📁 Files Modified

- `Sources/AgentBar/AgentBarSettings.swift`
- `docs/ARCHITECTURE.md`
- `docs/FRONTEND.md`
- `docs/histories/2026-04/20260427-1216-settings-account-quota-bars.md`
