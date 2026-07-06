## [2026-07-06 21:27] | Task: Stop constant Claude credential reads

**User request:** 用户观察到 AgentBar 一直在读 Claude Code 的 credential（文件/Keychain），要求把这部分代码删掉；进一步澄清后，用户指向 `CodexBar` 项目参考它是怎么做的，说明本质诉求是“理论上只需要读 5h/weekly 两个配额数字”，不需要每次轮询都真正touch 底层存储。

**Scope:** Claude Code credential 读取路径（`ClaudeAuthStore`）

**Actions:**

- **[Claude auth cache]**: 给 `ClaudeAuthStore` 加了 30 分钟内存缓存。文件来源的凭据靠 mtime/size 指纹判断文件是否变化，变化了才重新读盘；Keychain 来源的凭据在缓存有效期内完全不重新访问 Keychain。token 刷新后 `save()` 会同步更新内存缓存和指纹。
- **[Docs]**: 更新 `docs/ARCHITECTURE.md` 里 Claude Code 配额那一段，说明缓存和指纹机制。

**Decision notes:**

参考了 `CodexBar` 里 `ClaudeOAuthCredentialsStore` 的内存缓存（`memoryCacheValidityDuration`）思路，但没有照搬它完整的 Keychain prompt gating/fingerprint hashing 等复杂度——agent-bar 这里是单账号只读展示，60 秒轮询一次即可，只需要避免每次轮询都重新读文件或碰 Keychain。没有整体删除 Claude 配额功能。

**Touched files:**

- `Sources/AgentBarCore/ClaudeAuth.swift`
- `docs/ARCHITECTURE.md`
