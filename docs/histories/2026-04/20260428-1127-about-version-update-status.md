## [2026-04-28 11:27] | Task: About 显示版本与更新状态

### Request

> About 里增加显示当前的版本，以及显示当前是否最新版本；如果不是，可以在那边直接点击触发更新。

### Changes

- **[Updater Status]**: `AgentBarUpdater` 新增 `AgentBarUpdateStatus`，暴露当前版本、最新可用版本、检查状态、失败状态和是否可触发检查。
- **[Manual Update Entry]**: About 打开时使用 Sparkle `checkForUpdateInformation()` 做不打扰的状态探测，用户点击按钮时调用 `checkForUpdates()` 进入现有 Sparkle 下载/安装流程。
- **[About UI]**: About 卡片新增 Version 行，显示当前版本、最新状态和紧凑 Check/Update 按钮，并保留 GitHub Repository 入口。
- **[Docs]**: 同步 architecture、frontend、reliability、quality 和 release notes，记录 About 版本/更新状态入口。

### Rationale

About 是用户自然查版本的位置。用 Sparkle 自带 probing check 只更新状态，不额外弹窗；真正安装仍走用户触发的 `checkForUpdates()`，继续复用现有自动安装、手动确认、跳过版本和签名校验流程，避免维护第二套更新逻辑。

### Files

- `Sources/AgentBar/AgentBarUpdater.swift`
- `Sources/AgentBar/AgentBarSettings.swift`
- `docs/ARCHITECTURE.md`
- `docs/FRONTEND.md`
- `docs/RELIABILITY.md`
- `docs/QUALITY_SCORE.md`
- `docs/releases/feature-release-notes.md`
