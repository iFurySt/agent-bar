# Codex 动态额度窗口适配

## 用户诉求

Codex 已开始为部分账号返回非固定 5h/weekly 的额度周期，希望 AgentBar 跟随服务端真实窗口展示。

## 改动

- 将 Codex quota 从固定 5h/weekly 字段升级为 primary/secondary window，并保留百分比、时长和 reset。
- usage API 和本地 session fallback 同时支持动态窗口；已知时长映射为 5h、Daily、7d、Monthly、Annual。
- 顶部浮窗、展开账号卡片和 Settings Accounts 改为动态标签。
- 顶部浮窗只渲染可用窗口；单窗口不显示 `--%` 占位，多个窗口按周期从短到长排列，刘海屏同步隐藏多余百分比槽位。
- 兼容旧 cache；避免 monthly-only 服务端响应被旧 session 的 weekly 数据污染。
- 新增 API response、旧 cache、fallback 和显示格式测试，并同步架构、UI、可靠性与发布文档。

## 主要文件

- `Sources/AgentBarCore/CodexUsageClient.swift`
- `Sources/AgentBarCore/CodexSnapshotService.swift`
- `Sources/AgentBarCore/DisplayFormatting.swift`
- `Sources/AgentBar/App.swift`
- `Sources/AgentBar/AgentBarSettings.swift`
- `Tests/AgentBarCoreTests/CodexUsageClientTests.swift`

## 验证

- `swift test`：31 tests passed。
