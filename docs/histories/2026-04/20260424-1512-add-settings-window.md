## [2026-04-24 15:12] | Task: 添加顶部齿轮设置窗口

### Execution Context

- **Agent ID**: `Codex`
- **Base Model**: `GPT-5`
- **Runtime**: `Codex CLI`

### User Query

> 用户希望在 PIN 右侧新增齿轮 icon，点击后打开类似 macOS 设置的弹窗；弹窗先包含 System Settings，里面有开机自动启动和自动更新选择；About 做成独立页面并放 GitHub 信息。后续明确希望窗口接近系统设置类布局，颜色配色对齐 AgentBar 自己的色系，且设置窗口不要置顶。

### Changes Overview

**Scope:** macOS AppKit overlay and settings

**Key Actions:**

- **[Gear Control]**: 在无 notch 普通屏幕的 PIN 右侧新增常驻 `gearshape` icon，并打开独立 macOS 设置风格窗口。
- **[System Settings]**: 新增设置窗口，左侧为紧凑 sidebar，右侧为 grouped settings 卡片，包含 `Launch at Login` 和 `Automatic Updates` 两个原生开关；sidebar、正文、卡片背景和卡片外框分别对齐 `#E6E5E3`、`#F3F1EF`、`#EFEDEB`、`#E2E0DF`，标题、设置行、sidebar 和 About 字号按 OrbStack preferences 的紧凑密度调整，并保持设置卡片左右外边距一致。设置窗口打开时临时进入 `.regular` activation policy 支持 Command+Tab，关闭后恢复 `.accessory`；临时 Dock 图标显式使用 `AgentBar.icns` 并刷新 Dock tile；窗口直接支持 `Command+W` 关闭。
- **[Launch at Login]**: 使用 macOS `SMAppService.mainApp` 注册和取消开机自动启动；失败时恢复复选框状态并显示系统错误。
- **[Auto Update]**: 通过 `AgentBarUpdater` 暴露 Sparkle `automaticallyChecksForUpdates`，设置窗口可直接开关自动更新。
- **[About]**: About 切换到独立页面，页面内展示 GitHub Repository 行并打开 `https://github.com/iFurySt/agent-bar`。
- **[Docs Sync]**: 同步 README、架构、界面、稳定性、质量评分和 release notes。

### Design Intent (Why)

顶部 bar 已经有 PIN 作为最小交互点，齿轮放在其右侧能保持工具入口集中，不需要新增菜单栏状态项。开机启动属于系统级设置，交给 `SMAppService` 处理；自动更新已经由 Sparkle 接管，因此设置窗口只负责读写 Sparkle 自带的自动检查开关，避免维护第二套更新状态。窗口采用更接近 OrbStack/macOS preferences 的紧凑结构，用 `#E6E5E3` sidebar、`#F3F1EF` 正文、`#EFEDEB` grouped card 和 `#226CFF` 选中态承载设置项。设置窗口保持普通 window level，避免置顶后影响用户切换到别的窗口。

### Files Modified

- `Sources/AgentBar/App.swift`
- `Sources/AgentBar/AgentBarSettings.swift`
- `Sources/AgentBar/AgentBarUpdater.swift`
- `README.md`
- `docs/ARCHITECTURE.md`
- `docs/FRONTEND.md`
- `docs/QUALITY_SCORE.md`
- `docs/RELIABILITY.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260424-1512-add-settings-window.md`
