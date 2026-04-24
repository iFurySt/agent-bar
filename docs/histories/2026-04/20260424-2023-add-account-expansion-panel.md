## [2026-04-24 20:23] | Task: 顶部 bar 点击展开账号列表

### Execution Context

- **Agent ID**: `Codex`
- **Base Model**: `GPT-5`
- **Runtime**: `Codex CLI`

### User Query

> 用户希望顶部 bar 可以点击，点击后有动画并向下展开，先展示多个账号的情况（一行一个）；同时每次用户登录后把对应 token 记录住，后续可以持续使用。实现上可参考 `cockpit-tools` 的多账号逻辑和 `codex` 的 token 管理方式。

### Changes Overview

**Scope:** AgentBarCore local account persistence and macOS overlay interaction

**Key Actions:**

- **[Account Store]**: 新增 `CodexAccountStore`，在每次刷新时读取当前 `auth.json`，从 `id_token` / `access_token` 解析 email、account id、plan 等最小元数据，并把 access/refresh/id token 与最近出现时间持久化到 `~/.agentbar/accounts.json`。
- **[Deduping]**: 多账号仓库按稳定 ChatGPT account id 去重，同一账号后续再次登录时只更新 token 和最后出现时间，不重复创建记录；当前版本只处理 OAuth 登录账号，不把 API key 模式混入多账号列表。
- **[Expandable Bar]**: 无 notch 的普通屏幕 bar 本体改为可点击，点击后通过现有 AppKit frame 动画向下展开黑色 dropdown 面板；面板里按最近出现时间列出已记录账号，每行一条，并把当前账号置顶标为 `Current`。
- **[Connected Geometry]**: 展开态改成主 bar 与下方面板一体连接的 neck geometry，而不是上下一分为二的独立卡片；同时加了仅供本地调形的预览导出环境变量，便于直接把渲染结果导出成 PNG 做视觉比对。
- **[Reference Reverse Engineering]**: 额外静态分析了本地 `Vibe Island.app`，确认其内部存在 `NotchPanel`、`NotchWindowController`、`NotchContentView`、`NotchShape`、`cardWidth`、`cardCorner` 等独立对象；据此把我们自己的展开态继续收敛为单一 shape，并改成从 bar 底边中段直接下拉的连续轮廓，而不是再拼一个独立挂载体块。
- **[Auto-hide Integration]**: 展开态会沿用现有 hover / pin 逻辑；未 pin 时，鼠标离开后 bar 和展开面板一起收起，避免在自动隐藏菜单栏场景下出现悬空的二级面板。
- **[Tests & Docs]**: 新增账号仓库测试，覆盖自动记账、最近账号排序和同账号 upsert；同步更新架构、稳定性、安全、质量评分和发布记录。

### Design Intent (Why)

这个需求的关键不是立即做完整切号，而是先把“账号列表可见”和“每次登录自动记住”做扎实。当前仓库已经稳定依赖 `auth.json` 和本地 session，所以最小闭环是：每次刷新顺手把当前 OAuth 登录态抽成一份本地账号快照，再让顶部 bar 通过点击展开把这些快照展示出来。这样既复用了现有本地数据源，也不需要在这一轮引入新的登录 UI 或切号写回链路，能先把交互形态和数据沉淀打通。

### Files Modified

- `Sources/AgentBar/App.swift`
- `Sources/AgentBarCore/CodexAccountStore.swift`
- `docs/ARCHITECTURE.md`
- `docs/RELIABILITY.md`
- `docs/SECURITY.md`
- `docs/QUALITY_SCORE.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260424-2023-add-account-expansion-panel.md`
- `Tests/AgentBarCoreTests/CodexAccountStoreTests.swift`
