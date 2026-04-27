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
- **[Action 4]**: 将 `Switch`/`Current` 从右侧大 pill 改为 plan chip 右侧的小型符号控件，并同步点击热区。
- **[Action 5]**: 修正 Settings Accounts 小符号按钮在 flipped 坐标系里的倒置绘制，并给可切换账号的 switch icon 增加 hover 高亮。
- **[Action 6]**: 移除 Accounts block 内部滚动，让账号列表按内容撑开，改由右侧正文主体承担纵向滚动。

### 🧠 Design Intent (Why)

Accounts 页是完整账号管理场景，5h/7d quota 用两条 bar 放在邮箱下方，比一行压缩文本更接近顶部展开区的阅读节奏，也能减少横向拥挤。切换控件贴近 plan chip 后，账号身份、订阅状态和切换动作归在同一行，右侧留给 quota bar 使用。完整账号列表是页面正文的一部分，不应在 grouped block 里再套一个纵向滚动层。

### 📁 Files Modified

- `Sources/AgentBar/AgentBarSettings.swift`
- `docs/ARCHITECTURE.md`
- `docs/FRONTEND.md`
- `docs/histories/2026-04/20260427-1216-settings-account-quota-bars.md`
