## [2026-04-23 23:17] | Task: 补充发版闭环文档

### Execution Context

- **Agent ID**: `Codex`
- **Base Model**: `GPT-5`
- **Runtime**: `Codex CLI`

### User Query

> 用户希望把“发版”默认流程沉淀到仓库文档：bump version、git tag 推送、持续观察 GitHub Actions；失败时修复、删除本地和远端 tag 后重新打同名 tag，直到发布成功。并在 `AGENTS.md` 里提示发版前阅读对应文档。

### Changes Overview

**Scope:** release documentation

**Key Actions:**

- **[Agent Navigation]**: 在 `AGENTS.md` 中明确用户说“发版”前必须先读 `docs/CICD.md`。
- **[Release SOP]**: 扩展 `docs/CICD.md` 的发版流程，覆盖 semver bump、release note/history、本地验证、推送 main/tag、`gh run watch` 观察、失败修复与删除/重打 tag 的闭环。

### Design Intent (Why)

发版不是单次 `git tag && git push`，而是需要确认远端 CI、release workflow 和 GitHub Release 资产都成功。把失败重试和 tag 重打规则写进仓库文档，可以避免 Agent 在 release workflow 还没完成或失败时过早结束任务。

### Files Modified

- `AGENTS.md`
- `docs/CICD.md`
- `docs/histories/2026-04/20260423-2317-document-release-loop.md`
