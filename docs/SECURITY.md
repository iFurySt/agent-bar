# 安全默认约束

`agent-bar` 只读取本机 Codex 凭据和 session 日志，不采集、不上传、不持久化额外遥测。

## 本地数据

- 默认读取 `~/.codex/auth.json`，如果设置了 `CODEX_HOME` 则读取对应目录。
- 默认读取 `~/.codex/sessions` 下最近约 30 天 JSONL session 文件。
- session 内容只在本机进程内解析 token 计数、模型名和 rate limit 字段，不展示 prompt、回复或工具输出。
- 默认写入 `~/.agentbar/cache.json`，只缓存 session 文件路径、size/mtime、rate limit 百分比、模型维度 token/cost 汇总和最后一次展示快照，不缓存 prompt、回复或工具输出正文。
- 为了支持顶部展开面板的多账号展示，默认还会写入 `~/.agentbar/accounts.json`，保存当前 OAuth 登录账号的 access token、refresh token、id token 以及最小展示元数据（如 email、account id、plan、最近出现时间）。该文件只在本机使用，写入后会尝试收紧为 `0600` 权限。

## 网络

- 仅为获取实时 5h/7d quota 调用 `https://chatgpt.com/backend-api/wham/usage`。
- 仅为检查和下载应用更新读取 `https://github.com/iFurySt/agent-bar/releases/latest/download/appcast.xml` 以及其中指向的 GitHub Release DMG。
- access token 过期时，会按 CodexBar 参考实现刷新 OAuth token 并写回 `auth.json`，避免 refresh token 轮换后丢失。
- 当前不会把 `accounts.json` 里的历史账号 token 主动发往网络；只有当前 `auth.json` 对应账号会继续参与 usage API 请求和必要的 OAuth refresh。
- usage API 失败时使用本地 session fallback，不要求持续联网。
- 更新包由 Sparkle 校验 EdDSA 签名，签名不匹配时不会安装。
