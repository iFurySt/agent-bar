## [2026-04-25 12:30] | Task: Multi-account island expansion

### Execution Context

- **Agent ID**: `Codex`
- **Base Model**: `GPT-5`
- **Runtime**: `Codex CLI`

### User Query

> 展开内容里展示多个 Codex 账号；参考 Codex `/login` 和 CodexBar token 处理。每次登录拿到新 token 后缓存到 `~/.agentbar/`，用户换账号后也能累积账号。

### Changes Overview

**Scope:** `Sources/AgentBarCore`, `Sources/AgentBar`, `docs`

**Key Actions:**

- **Account cache**: 新增 `~/.agentbar/accounts.json`，保存已见 Codex OAuth credentials，并在 macOS 上设置 `0600` 权限。
- **Token sync**: 当前 `auth.json` 被读取或刷新时，同步 upsert 到 AgentBar 多账号缓存；refresh token 轮换后也同步更新。
- **Multi-account usage**: 后台刷新遍历缓存账号，逐个获取 usage quota，展开态每账号一行展示 5h/7d。
- **Local account fallback**: 启动时如果 usage 快照还没刷新完成，会先从本地账号缓存渲染账号行，避免展开态误显示没有账号。
- **Account cards**: 展开区从纯文本行升级为圆角账号卡片，当前账号只排序置顶，不再显示 `Current`；每张卡展示 5h/7d 剩余百分比、小进度条和 reset 倒计时。
- **Plan chip**: 从 Codex usage response 的 `plan_type` 读取 PLUS/PRO/TEAM 等订阅信息，并在账号卡片右上角以 chip 展示。
- **Current account priority**: 顶部 island 百分比优先使用当前 `auth.json` 账号的 usage API 结果，session JSONL fallback 只在 API 缺失或失败时补位，避免旧 session 里的其他账号 quota 覆盖主账号。
- **Docs**: 更新架构和安全文档，明确新增 token 缓存行为。

### Design Intent (Why)

先实现最小多账号闭环：AgentBar 不接管登录流程，只观察 Codex 当前登录态并累积账号。这样用户通过 Codex 自己的登录/切换流程获得新 token 后，AgentBar 就能保存并持续展示这些账号的 quota。

### Files Modified

- `Sources/AgentBarCore/CodexAccountStore.swift`
- `Sources/AgentBarCore/CodexAuth.swift`
- `Sources/AgentBarCore/CodexUsageClient.swift`
- `Sources/AgentBarCore/CodexSnapshotService.swift`
- `Sources/AgentBarCore/AgentBarCacheStore.swift`
- `Sources/AgentBar/App.swift`
- `docs/ARCHITECTURE.md`
- `docs/SECURITY.md`
- `docs/histories/2026-04/20260425-1230-multi-account-island.md`
