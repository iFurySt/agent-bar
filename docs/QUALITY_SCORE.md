# 质量评分

用这份文档按产品区域和架构层次记录当前质量水位，方便持续知道最薄弱的地方在哪。

## 建议的评分标准

- `A`：覆盖完整、行为稳定、文档清楚、运行风险低。
- `B`：整体可接受，但还有明确短板。
- `C`：能用，但需要针对性补强。
- `D`：脆弱、缺少规范，或很多行为尚未定义。

## 当前评分

| 区域 | 评分 | 原因 | 下一步 |
| --- | --- | --- | --- |
| 产品面 | B | 已有最小可用顶部浮窗，范围清楚，除了 Codex quota 与 token/cost 之外，还能点击 bar 展开本机已记录的多账号列表，并具备 tag 驱动 DMG 分发、Sparkle 更新、外接屏 auto-hide/pin、轻量设置窗口和数字刷新动效。 | 真实使用后再决定是否要把展开面板继续做成切号入口或加入手动刷新账号仓库。 |
| 架构文档 | B | 已替换为 SwiftPM/AppKit/Core 的真实结构，并补齐 macOS DMG、Sparkle appcast、顶部展开面板与本地账号仓库边界。 | 后续如果加入真正的切号写回流程、Homebrew 或 App Store 分发，同步更新边界。 |
| 测试 | B | 覆盖了显示格式、本地 token 扫描、缓存失效、fallback scanner，以及当前登录自动入库/去重的账号仓库路径；CI 已运行 `swift test`。 | 补更多 JWT 元数据提取 fixture，以及展开面板的 UI 回归验证。 |
| 可观测性 | B | UI 刷新保持静默以减少打扰，缓存可从 `~/.agentbar/cache.json` 直接检查，账号仓库也可从 `~/.agentbar/accounts.json` 直接核对。 | 如果出现账号列表不同步，再补最小本地 debug 输出。 |
| 安全 | B | 本地只读 session，网络面限定到 Codex usage API 和 GitHub Release 更新；更新包由 Sparkle EdDSA 签名校验，历史账号 token 只保存在本地 `accounts.json`。 | 评估多账号 token 是否要进一步迁移到 Keychain，并定期确认 Sparkle 私钥保管和轮换流程。 |
