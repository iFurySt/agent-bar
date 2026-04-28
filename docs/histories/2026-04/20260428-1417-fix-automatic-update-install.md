## [2026-04-28 14:17] | Task: Fix Automatic Update Install

### 🤖 Execution Context

- **Agent ID**: `Codex`
- **Base Model**: `GPT-5`
- **Runtime**: `local CLI`

### 📥 User Query

> 排查并修复 AgentBar 自动更新检测到新版本后没有自动弹出/安装的问题。

### 🛠 Changes Overview

**Scope:** `Sources/AgentBar`, `docs`

**Key Actions:**

- **[Auto Update]**: `AgentBarUpdater` 在 Sparkle 自动更新已开启时接管 `willInstallUpdateOnQuit` 的 immediate installation block，下载解包完成后直接推进安装和重启。
- **[Termination Retry]**: 自定义 `SPUUserDriver` 在自动安装等待旧进程退出时短延迟重试终止请求，降低常驻小组件卡在等待退出阶段的概率。
- **[Docs]**: 更新稳定性文档，明确自动更新依赖 Sparkle immediate installation block，而不是被动等待用户手动退出。

### 🧠 Design Intent (Why)

AgentBar 是常驻顶部小组件，正常使用中不会频繁退出。Sparkle 已经能发现、下载并校验更新，但如果不接管自动更新的即时安装回调，更新会停在“下次退出时安装”，用户会误以为没有检测到更新。自动模式应在不二次打扰用户的前提下完成退出、替换、重启，并在新版本启动后复用既有完成通知。

### 📁 Files Modified

- `Sources/AgentBar/AgentBarUpdater.swift`
- `docs/RELIABILITY.md`
