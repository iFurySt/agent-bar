# 稳定性与可运维性

`agent-bar` 的稳定性目标是本机轻量、失败可降级、UI 不阻塞。

## 默认行为

- 顶部浮窗每 60 秒刷新一次。
- Codex usage API 读取失败时，使用最近 session 中的 rate limit 事件兜底。
- 本地 cost 扫描只读最近约 30 天 `~/.codex/sessions/YYYY/MM/DD/*.jsonl`。
- cost/token 扫描在后台任务中运行，避免阻塞 AppKit 主线程。

## 验证

```sh
swift test
swift run AgentBar
```

如果 5h/7d 显示 `--%`，优先检查 `codex` 是否已登录，以及最近 session 里是否存在 `token_count.rate_limits`。
