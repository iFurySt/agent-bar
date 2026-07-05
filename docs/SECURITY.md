# 安全默认约束

`agent-bar` 只读取本机 Codex 凭据和 session 日志，不采集、不上传、不持久化额外遥测。

## 本地数据

- 默认读取 `~/.codex/auth.json`，如果设置了 `CODEX_HOME` 则读取对应目录。
- 默认读取 `~/.codex/sessions` 下最近约 30 天 JSONL session 文件；设置页 Usage 会按当前可见的 Day/Year 视图读取所选年份 Jan-Dec，或按用户本地时区选中的自然日读取 00-23 点 token 和 Vibe Coding 活跃时间，同时补捞最近修改过的旧日期目录 session 文件。
- session 内容只在本机进程内解析 token 计数、模型名、rate limit 字段和活动事件时间戳，不展示 prompt、回复或工具输出。
- 默认写入 `~/.agentbar/cache.json`，只缓存 session 文件路径、size/mtime、聚合时区、rate limit 百分比、模型维度 token/cost 日级和小时级汇总、Usage Year/Day 视图级 token 与活跃时间 snapshot、已展示账号 usage 快照和最后一次展示快照，不缓存 prompt、回复或工具输出正文。
- 默认写入 `~/.agentbar/accounts.json` 记录已见 Codex OAuth 账号的 access token、refresh token、id token、account id 与展示标签，用于在用户切换 Codex 登录账号后继续展示多账号 quota；文件权限在 macOS 上设置为 `0600`。
- 用户在展开区点击已缓存账号卡片内的账号切换控件时，会把该账号 OAuth token 写回当前 Codex live `auth.json`，使后续新开的 Codex CLI 会话使用该账号；写入保留原 auth 文件其他字段并设置 `0600` 权限。
- Claude Code 配额只读取 `~/.claude/.credentials.json`，或以不弹授权窗口的方式尝试读取 macOS Keychain 里的 `Claude Code-credentials`；如果系统要求交互授权，则视为没有可用 Claude Code 凭据并隐藏卡片。

## 网络

- 仅为获取实时 5h/7d quota 调用 `https://chatgpt.com/backend-api/wham/usage`。
- 仅在本机已有可无提示读取的 Claude Code OAuth 凭据时，调用 Anthropic OAuth usage API 读取 Claude Code 5h/weekly quota。
- 仅为检查和下载应用更新读取 `https://github.com/iFurySt/agent-bar/releases/latest/download/appcast.xml` 以及其中指向的 GitHub Release DMG。
- access token 过期时，会按 CodexBar 参考实现刷新 OAuth token 并写回 `auth.json`；AgentBar 自己缓存的多账号 token 也会同步更新，避免 refresh token 轮换后丢失。
- usage API 失败时使用本地 session fallback，不要求持续联网。
- 更新包由 Sparkle 校验 EdDSA 签名，签名不匹配时不会安装。
