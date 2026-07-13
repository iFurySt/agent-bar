# Codex 动态额度窗口适配

## 目标

让 AgentBar 不再假设 Codex 的 primary/secondary 固定为 5h/7d，而是根据 usage API 或本地 session
返回的窗口时长展示 5h、Daily、7d、Monthly、Annual 或通用标签。

## 完成内容

- Codex quota 模型改为携带 remaining percent、reset time 和 duration 的 primary/secondary window。
- 自定义 Codable 兼容旧版 `~/.agentbar/cache.json` 中的 5h/weekly 字段。
- usage API 与 session fallback 都读取服务端窗口时长；fallback cache 同步保存 duration/reset。
- 顶部浮窗、展开账号卡片和 Settings Accounts 使用动态标签。
- 顶部浮窗只显示有有效百分比的窗口；单窗口不保留空槽，双窗口按周期从短到长排列。
- 成功返回单窗口时以服务端形状为准，不拼接旧 session 中可能过期的另一窗口。
- Claude Code 的固定 5h/weekly API 和展示保持不变。

## 验证

- `swift test`：31 tests passed。
- 覆盖 generalized usage response、monthly-only、未知窗口、旧 cache 解码和 session fallback duration/reset。
