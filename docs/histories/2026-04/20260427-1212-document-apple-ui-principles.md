## [2026-04-27 12:12] | Task: Document Apple UI Principles

### Execution Context

- **Agent ID**: `Codex`
- **Base Model**: `GPT-5`
- **Runtime**: `Codex CLI`

### User Query

> 在 AGENTS.md 和对应 docs 里增加描述：所有涉及 UI/UX 的改动都要符合苹果的设计语言和设计哲学，less is more 的简约风格和美学。

### Changes Overview

**Scope:** repository documentation

**Key Actions:**

- **AGENTS routing**: Updated the `docs/FRONTEND.md` entry to call out Apple design language and less-is-more UI/UX expectations.
- **Frontend rules**: Added explicit UI/UX constraints for native macOS feel, restrained motion, familiar system patterns, and minimal visual complexity.
- **Core beliefs**: Added a concise product-design principle so UI work defaults to Apple-like clarity and restraint.

### Design Intent (Why)

UI/UX expectations should be versioned in the repository instead of relying on chat context. `AGENTS.md` stays short and points agents to `docs/FRONTEND.md`, while the detailed rule lives in the focused frontend document.

### Files Modified

- `AGENTS.md`
- `docs/FRONTEND.md`
- `docs/design-docs/core-beliefs.md`
- `docs/histories/2026-04/20260427-1212-document-apple-ui-principles.md`
