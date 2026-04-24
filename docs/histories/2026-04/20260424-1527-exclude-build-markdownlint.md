## [2026-04-24 15:27] | Task: 排除 CI 里的构建目录 Markdown

### 🤖 Execution Context

- **Agent ID**: `Codex`
- **Base Model**: `GPT-5`
- **Runtime**: `Codex CLI`

### 📥 User Query

> main 触发的 CI 因 markdownlint 扫到 Sparkle checkout 失败，允许排除并修复。

### 🛠 Changes Overview

**Scope:** GitHub Actions CI

**Key Actions:**

- **[Markdownlint Scope]**: 在 `.github/workflows/ci.yml` 的 markdownlint globs 中排除 `.build/**`，避免 SwiftPM 拉取的第三方依赖文档被仓库 lint 规则扫描。

### 🧠 Design Intent (Why)

`scripts/ci.sh` 会用 `.build/ci` 作为 SwiftPM scratch path。引入 Sparkle 后，SwiftPM 在 `.build/ci/checkouts/Sparkle` 下放入第三方 Markdown 文件；这些文件不属于本仓库文档质量边界，应该从 markdownlint action 的文件范围中排除，而不是修改依赖源码或放宽仓库文档规则。

### 📁 Files Modified

- `.github/workflows/ci.yml`
- `docs/histories/2026-04/20260424-1527-exclude-build-markdownlint.md`
