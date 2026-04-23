# 修复 Ubuntu CI Swift 构建

## 用户诉求

查看最新 GitHub Actions 失败原因并修复。

## 变更

- 确认最新失败 run 是 `CI`，失败点在 Ubuntu 上执行 `scripts/ci.sh` 时 Swift 编译找不到 `URLRequest` 和 `URLSession.shared`。
- 为 `CodexAuth.swift` 和 `CodexUsageClient.swift` 在可用时引入 `FoundationNetworking`，兼容 Swift on Linux 的 networking 类型位置。
- 调整 `Package.swift`，非 macOS 主机只声明 `AgentBarCore` 和测试 target，避免 Ubuntu CI 编译 AppKit executable。
- 为 `CI` workflow 增加手动触发入口，方便 push 事件未及时生成 run 时仍可验证 main。
- 同步 `docs/CICD.md`，说明 Ubuntu CI 只覆盖跨平台 core，macOS app 构建由 macOS/release 链路负责，并记录 CI 触发方式。

## 受影响文件

- `Package.swift`
- `.github/workflows/ci.yml`
- `Sources/AgentBarCore/CodexAuth.swift`
- `Sources/AgentBarCore/CodexUsageClient.swift`
- `docs/CICD.md`
