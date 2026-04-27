## [2026-04-27 12:25] | Task: 调整自动更新安装确认流程

### 🤖 Execution Context

- **Agent ID**: `Codex`
- **Base Model**: `GPT-5`
- **Runtime**: `codex-cli`

### 📥 User Query

> 设置里勾选 `Automatic Updates` 后，检测到升级就自动下载、重启、升级；不勾选时才提醒用户，并在提醒里增加以后自动升级的选项。

### 🛠 Changes Overview

**Scope:** AgentBar Sparkle 更新流程与仓库文档

**Key Actions:**

- **[Auto Update]**: `Automatic Updates` 现在控制 Sparkle 的自动下载/安装模式；更新检查保持开启，勾选后准备安装时直接交给 Sparkle 重启安装，不再弹确认。
- **[Manual Prompt]**: 未开启自动更新时，下载完成确认框增加 `Turn On Automatic Updates`，选择后会开启后续自动更新并安装当前版本。
- **[Docs]**: 同步架构、可靠性和用户发布记录中的自动更新行为说明。

### 🧠 Design Intent (Why)

用户把 `Automatic Updates` 理解为自动完成升级，而不是每次下载完仍要求确认。更新检测本身保持开启，避免关闭自动安装后就完全收不到升级提示；确认框里的“以后自动更新”给用户一个低摩擦的升级偏好切换入口。

### 📁 Files Modified

- `Sources/AgentBar/AgentBarUpdater.swift`
- `docs/ARCHITECTURE.md`
- `docs/RELIABILITY.md`
- `docs/releases/feature-release-notes.md`
