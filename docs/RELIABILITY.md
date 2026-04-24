# 稳定性与可运维性

`agent-bar` 的稳定性目标是本机轻量、失败可降级、UI 不阻塞。

## 默认行为

- 顶部浮窗每 60 秒刷新一次。
- 启动时先读取 `~/.agentbar/cache.json` 里的最后一次完整快照，避免空白或长时间 `--%`。
- Codex usage API 读取失败时，使用最近 session 中的 rate limit 事件兜底。
- 本地 cost 扫描只读最近约 30 天 `~/.codex/sessions/YYYY/MM/DD/*.jsonl`。
- 每轮刷新按 session 文件 size/mtime 复用缓存，只重算新增或更新过的文件。
- cost/token 扫描在后台任务中运行，避免阻塞 AppKit 主线程。
- 后台刷新保持静默，不显示状态点，避免快速刷新时造成视觉闪烁。
- 无 notch 普通屏幕用 30Hz 主线程 timer 轮询鼠标位置来做顶部唤出，不依赖额外 Accessibility 权限；窗口平时仍默认透传鼠标事件。

## 验证

```sh
swift test
swift run AgentBar
```

如果 5h/7d 显示 `--%`，优先检查 `codex` 是否已登录、最近 session 里是否存在 `token_count.rate_limits`，以及 `~/.agentbar/cache.json` 是否可写。
