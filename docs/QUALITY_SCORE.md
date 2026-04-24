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
| 产品面 | B | 已有最小可用顶部浮窗，范围清楚，只展示 Codex quota 与 token/cost，并具备 tag 驱动 DMG 分发、Sparkle 更新、外接屏 auto-hide/pin 和数字刷新动效。 | 真实使用后再决定是否需要完整设置页、菜单栏状态项或手动检查更新入口。 |
| 架构文档 | B | 已替换为 SwiftPM/AppKit/Core 的真实结构，并补齐 macOS DMG、Sparkle appcast 与 GitHub Release 更新边界。 | 后续如果加入登录流程、Homebrew 或 App Store 分发，同步更新边界。 |
| 测试 | B | 覆盖了显示格式、本地 token 扫描、缓存失效和 fallback scanner smoke path；CI 已运行 `swift test`。 | 补 API response fixture 与更完整的缓存复用测试。 |
| 可观测性 | B | UI 刷新保持静默以减少打扰，缓存可从 `~/.agentbar/cache.json` 直接检查。 | 如果出现 quota 读取问题，再补本地 debug 输出。 |
| 安全 | B | 本地只读 session，网络面限定到 Codex usage API 和 GitHub Release 更新；更新包由 Sparkle EdDSA 签名校验。 | 打包前评估 token 刷新写回策略是否需要用户开关，并定期确认 Sparkle 私钥保管和轮换流程。 |
