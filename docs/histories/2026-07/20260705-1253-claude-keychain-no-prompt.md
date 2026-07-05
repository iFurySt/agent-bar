## [2026-07-05 12:53] | Task: Stop Claude Keychain prompt loops

**User request:** Claude Code 重新登录后，AgentBar 会反复弹出读取 Claude Code credential 的系统提示，希望不要每次都打断输入。

**Scope:** Claude Code credential lookup and documentation

**Actions:**

- **[Claude auth]**: 将 macOS Keychain 中 `Claude Code-credentials` 的读取改为 non-interactive；如果系统需要弹出授权窗口，AgentBar 直接视为没有可用 Claude 凭据。
- **[Claude refresh writeback]**: Keychain 写回同样使用 non-interactive 查询，避免后台 token refresh 触发授权 UI。
- **[Docs]**: 更新架构、安全和功能发布记录，明确 Claude 卡片是可选展示，读不到无提示凭据时隐藏。

**Decision notes:**

Claude Code 配额只是展开面板里的辅助信息，不是 AgentBar 主功能。为了一个只读卡片反复打断用户不值得；更合适的默认行为是“能无提示读到就显示，读不到就安静隐藏”。

**Touched files:**

- `Sources/AgentBarCore/ClaudeAuth.swift`
- `docs/ARCHITECTURE.md`
- `docs/SECURITY.md`
- `docs/releases/feature-release-notes.md`
