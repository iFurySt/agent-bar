## [2026-07-07 08:38] | Task: Remove Claude Code Keychain fallback entirely

**User request:** 用户在上一版本发布后反馈 AgentBar 启动时仍然弹出 macOS Keychain 授权窗口（"XX 想访问你存在钥匙串里的机密信息"），追问能不能彻底不请求。

**Scope:** Claude Code credential 读取路径（`ClaudeAuthStore`）

**Actions:**

- **[调研]**: 对照 `CodexBar` 的 `ClaudeOAuthCredentialsStore` 实现，发现即使用 `kSecUseAuthenticationUI`/`LocalAuthentication` 做 non-interactive 读取，也不能在所有 macOS 系统上保证不弹窗（CodexBar 代码里也有类似注释承认这一点）；CodexBar 真正的解法是默认 `.onlyOnUserAction`——后台自动轮询永远不会走可能弹窗的交互式路径，只有用户主动触发的操作才允许。
- **[Claude auth]**: AgentBar 的 Claude 配额卡片本身没有"用户主动刷新"这种操作入口，上述策略等价于"后台轮询永远不碰 Keychain"。据此彻底删除了 `ClaudeAuthStore` 里的 Keychain 读写代码（`readKeychain`/`writeKeychain`/`nonInteractiveKeychainOptions`/`resolveKeychainUIFailPolicy`），以及 `ClaudeCredentialSource` 枚举和 `ClaudeAuthCredentials.source` 字段（只剩文件来源，枚举不再必要）。现在只读取 `~/.claude/.credentials.json`；文件不存在时直接视为没有 Claude Code 凭据并隐藏卡片，不再有任何触发系统授权弹窗的可能。
- **[Docs]**: 更新 `docs/ARCHITECTURE.md` 和 `docs/SECURITY.md`，去掉 Keychain 相关描述，说明只读文件、没有文件就隐藏卡片。
- **[Tests]**: 同步更新 `Tests/AgentBarCoreTests/ClaudeAuthTests.swift`，去掉 `source:` 参数。

**Decision notes:**

这是对同一个"Claude credential 一直在读"投诉的第二轮修复：第一轮（30 分钟内存缓存）解决了"轮询频率"问题，但没解决"Keychain 存储用户在启动时仍可能弹窗"的问题。用户明确选择彻底去掉 Keychain 路径而不是加开关默认关闭，接受"如果 Claude Code 凭据只存在 Keychain 里，配额卡片会直接不可用"的代价。

**Touched files:**

- `Sources/AgentBarCore/ClaudeAuth.swift`
- `Tests/AgentBarCoreTests/ClaudeAuthTests.swift`
- `docs/ARCHITECTURE.md`
- `docs/SECURITY.md`
