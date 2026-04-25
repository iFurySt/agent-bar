## [2026-04-25 17:39] | Task: account switch button

### 🤖 Execution Context

- **Agent ID**: `Codex`
- **Base Model**: `GPT-5`
- **Runtime**: `Codex CLI`

### 📥 User Query

> 账号 block 点击切换不够明显，在账号 block 增加一个明确按钮用于切换账号。

### 🛠 Changes Overview

**Scope:** AgentBar account expansion UI

**Key Actions:**

- **[Action 1]**: 在账号邮箱和订阅 chip 右侧绘制同高图标按钮，当前账号显示 active 图标，非当前账号显示切换图标。
- **[Action 2]**: 将账号切换命中区域从整张卡片收窄到非当前账号的切换图标，并只在按钮区域显示手型光标。
- **[Action 3]**: 同步架构、安全、release notes 和账号切换计划文档里的交互描述。

### 🧠 Design Intent (Why)

整张账号卡片可点击不够显性，也容易和查看 quota 的卡片语义混在一起。把切换动作放到邮箱和订阅 chip 右侧的紧凑图标按钮上，可以保持账号标题行的视觉节奏，同时让用户清楚知道哪个控件会修改 Codex live auth。

### 📁 Files Modified

- `Sources/AgentBar/App.swift`
- `docs/ARCHITECTURE.md`
- `docs/SECURITY.md`
- `docs/releases/feature-release-notes.md`
- `docs/exec-plans/completed/codex-account-switching.md`
- `docs/histories/2026-04/20260425-1739-account-switch-button.md`
