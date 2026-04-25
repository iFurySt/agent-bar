# Codex 账号切换

## 目标

允许用户在 AgentBar 展开区点击已缓存账号，并把该账号凭据切换为 Codex CLI 的当前 live auth，使后续新开的 Codex 会话使用选中的账号。

## 范围

- 包含：点击账号卡片、写回当前 `CODEX_HOME/auth.json` 或 `~/.codex/auth.json`、更新 AgentBar 当前账号排序和顶部 quota。
- 不包含：热切换已经运行中的 Codex 进程、不接管 Codex 登录流程、不支持 keyring-only auth store 写入。

## 背景

- 相关文档：`docs/SECURITY.md`、`docs/ARCHITECTURE.md`
- 相关代码路径：`Sources/AgentBarCore/CodexAccountStore.swift`、`Sources/AgentBarCore/CodexAuth.swift`、`Sources/AgentBar/App.swift`
- 已知约束：Codex CLI 新会话会从当前 auth storage 读取 auth；当前 AgentBar 已支持 file-backed `auth.json` 读写。

## 风险

- 风险：写坏 live `auth.json` 会影响 Codex CLI 登录态。
- 缓解方式：复用现有 `CodexAuthStore.save`，保留原 auth 文件其他字段，使用 atomic write 并设置 `0600` 权限。

## 里程碑

1. 确认 Codex CLI live auth 读写位置。
2. 实现账号卡片点击切换。
3. 切换后刷新 AgentBar 当前账号展示。

## 验证方式

- 命令：`swift run AgentBar`
- 手工检查：点击非当前账号卡片后，顶部百分比和置顶账号切到目标账号。
- 观测检查：新开的 Codex CLI 会话读取切换后的 `auth.json`。

## 进度记录

- [x] 确认 Codex CLI 和 CodexBar 都以替换 live auth material 作为切换语义。
- [x] 实现点击切换账号。
- [x] 更新文档和 history。

## 决策记录

- 2026-04-25：采用写回当前 `auth.json` 的方式实现切换。该方案和 CodexBar promote live account 的语义一致，且能保证新开的 Codex CLI 会话使用目标账号。
