## [2026-04-24 14:28] | Task: 接入 Sparkle 自动更新

### 🤖 Execution Context

- **Agent ID**: `Codex`
- **Base Model**: `GPT-5`
- **Runtime**: `Codex CLI`

### 📥 User Query

> 希望基于 GitHub Releases 里的产物检测更新；检测到新版本后自动下载，下载完成弹窗确认是否升级，升级则直接安装，不升级则等下一个新版本再提醒。

### 🛠 Changes Overview

**Scope:** macOS AppKit app、release workflow、发布/安全/架构文档

**Key Actions:**

- **[Sparkle Updater]**: 接入 Sparkle 2.9.1，并新增自定义 `SPUUserDriver`，发现更新后先后台下载，准备安装后再弹确认。
- **[Skip Semantics]**: 用户选择跳过时记录已跳过的 `sparkle:version`，同版本后续检查不再提醒。
- **[Release Appcast]**: release workflow 在发布 DMG 后生成签名 `appcast.xml`，并和 DMG 一起上传到 GitHub Release。
- **[Packaging]**: DMG 打包时嵌入 `Sparkle.framework`、写入 `SUFeedURL`、`SUPublicEDKey` 和 24 小时检查间隔。
- **[Docs Sync]**: 同步 README、架构、CI/CD、安全、可靠性、供应链和用户可感知 release notes。

### 🧠 Design Intent (Why)

原生 macOS app 不适合自研替换 `.app` 的安装流程。Sparkle 负责签名校验、下载、替换和重启，仓库继续保持 GitHub Release DMG 作为唯一真实交付物；appcast 只是 Sparkle 的索引和签名入口。自定义 user driver 用来匹配本项目想要的交互：不在发现版本时打扰，而是在下载准备好后再确认。

### 📁 Files Modified

- `Package.swift`
- `Package.resolved`
- `Sources/AgentBar/App.swift`
- `Sources/AgentBar/AgentBarUpdater.swift`
- `scripts/build-agent-bar-dmg.sh`
- `scripts/generate-sparkle-appcast.sh`
- `.github/workflows/release.yml`
- `README.md`
- `docs/ARCHITECTURE.md`
- `docs/CICD.md`
- `docs/SECURITY.md`
- `docs/RELIABILITY.md`
- `docs/SUPPLY_CHAIN_SECURITY.md`
- `docs/QUALITY_SCORE.md`
- `docs/releases/feature-release-notes.md`
