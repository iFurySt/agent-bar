# Claude Code 5h/Weekly 配额接入

## 目标

在现有只支持 Codex 的顶部浮窗基础上，新增 Claude Code 的 5h / 7d 配额展示，作为顶部浮窗展开面板里的一个只读区块。

## 范围

- 包含：
  - 读取本机 Claude Code OAuth 凭据（`~/.claude/.credentials.json` 或 macOS Keychain 里的
    `Claude Code-credentials`），必要时刷新 token。
  - 调用 Anthropic `GET /api/oauth/usage` 拿 `five_hour` / `seven_day` 两个窗口的 `utilization`，
    换算成 remaining percent，展示在顶部浮窗的展开面板里（收起状态不显示，保持顶部一行 Codex 专属）。
  - 单账号：不做 Claude Code 账号列表、账号切换、`~/.agentbar/accounts.json` 式的多账号持久化。
  - 未登录 Claude Code（本机找不到凭据）时该区块直接不渲染，不报错、不占位。
- 不包含：
  - Claude Code 本地 session token/cost 统计（`~/.claude/projects/**/*.jsonl` 扫描）——这次不做，
    留到未来需要时再评估（tokscale 的 `claudecode.rs` 可以参考）。
  - Opus 单独的周配额窗口（`seven_day_opus`）。
  - Settings 里的 Usage Day/Year 视图接入 Claude Code 数据。
  - 多 provider 顶部一行合并展示（`ARCHITECTURE.md` 的“不支持多 provider”边界只做小范围松绑，
    不代表通用多 provider 架构）。

## 背景

- 相关文档：`docs/ARCHITECTURE.md`、`docs/design-docs/core-beliefs.md`。
- 参考实现：`/Users/ifuryst/projects/github/tokscale` 的
  `crates/tokscale-core/src/sessions/claudecode.rs`（session 解析，本次不用）与
  `crates/tokscale-cli/src/commands/usage/claude.rs`（OAuth 配额查询，本次参考的主要对象）。
- 现有 Codex 对应实现：`Sources/AgentBarCore/CodexAuth.swift`、
  `Sources/AgentBarCore/CodexUsageClient.swift`、`CodexSnapshotService.swift`、
  `AgentBarCacheStore.swift`、`Sources/AgentBar/App.swift` 里的 `IslandView`/`IslandWindowController`。
- 已知约束：
  - `AgentBarCore` 需要同时在 macOS 和 Linux CI（`swift test` on ubuntu-latest）下编译，Keychain 访问
    必须用 `#if canImport(Security)` 包住，Linux 分支直接返回不可用。
  - 首次读取 Keychain 时系统会弹出授权对话框，属于预期行为。
  - `AgentBarCache` 是 additive/optional 字段即可安全升级，不需要因为这次改动就 bump `currentVersion`。

## 风险

- 风险：Anthropic 的 `api/oauth/usage` 接口和字段可能变化。
  缓解方式：字段全部 optional 解析，拿不到就显示 `--%`，不影响 Codex 主流程。
- 风险：本机没有 Claude Code 凭据时误报错误或让顶部浮窗抖动。
  缓解方式：找不到凭据时该区块整体不渲染，不进入错误态。
- 风险：Keychain 读取在非交互式环境下可能一直弹授权框。
  缓解方式：读取失败按“未登录”处理，不重试到用户主动展开面板之前。

## 里程碑

1. 调研与方案收敛（已完成，见本文件）。
2. 实现 `ClaudeAuth.swift` + `ClaudeUsageClient.swift`，接入 `CodexSnapshotService`/`AgentBarCacheStore`。
3. UI：展开面板新增 Claude Code 配额行；补测试；同步文档与 history；关闭本计划。

## 验证方式

- 命令：`swift test`
- 手工检查：本机已登录 Claude Code 的情况下，展开顶部浮窗能看到 Claude Code 5h/7d 配额；未登录时该
  区块不显示。
- 观测检查：无（本地纯客户端功能，无需额外观测接入）。

## 进度记录

- [x] 确认范围和约束（只做 5h/weekly 配额、单账号、展开可见）。
- [x] 完成 `ClaudeAuth.swift` / `ClaudeUsageClient.swift` 实现。
- [x] 完成 snapshot/cache 接入。
- [x] 完成展开面板 UI。
- [x] 完成测试与文档收尾，归档到 `docs/exec-plans/completed/`。

## 决策记录

- 2026-07-04：确认第一版范围只做顶部浮窗展开面板里的 5h/weekly 配额展示，不做本地 token/cost 统计、
  不做账号切换、收起状态不展示。原因：用户明确要求先验证配额读取路径，缩小改动面。
- 2026-07-04：实现完成，`swift test` 全绿，并用一个独立编译的 smoke 脚本直接调用
  `ClaudeUsageClient().fetchRateLimits()` 验证了本机真实 Keychain 凭据读取 + Anthropic usage API 调用
  链路可用。计划关闭，归档到 `docs/exec-plans/completed/`。
