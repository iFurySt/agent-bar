## [2026-04-27 17:49] | Task: Add README screenshots and bilingual docs

### Execution Context

- **Agent ID**: `Codex`
- **Base Model**: `GPT-5`
- **Runtime**: `Codex CLI`

### User Query

> Move the screenshots from a local download folder into the repo, update README to show them, then add English/Chinese README switching based on the latest user-edited copy.

### Changes Overview

**Scope:** `docs/showcase`, `README.md`, `README.zh-CN.md`

**Key Actions:**

- **Archived screenshots**: Moved the six provided PNG screenshots into `docs/showcase/screenshots/`.
- **README showcase**: Added a screenshots section that previews compact island, full island, account panels, and Usage heatmap states.
- **Bilingual README**: Kept `README.md` as the English entry, added `README.zh-CN.md` as the Chinese entry, and added language/release badges at the top of both files.
- **Showcase badge**: Added a top-level Showcase badge linking to the published showcase page.

### Design Intent (Why)

The README should show the current product surface directly without relying on a local-only screenshots folder. Keeping the images under `docs/showcase/` makes them reusable for README, GitHub Pages, and future showcase updates. The public README surface follows the paired English/Chinese pattern used by the reference repo.

### Files Modified

- `README.md`
- `README.zh-CN.md`
- `docs/showcase/screenshots/1.png`
- `docs/showcase/screenshots/2.png`
- `docs/showcase/screenshots/3.png`
- `docs/showcase/screenshots/4.png`
- `docs/showcase/screenshots/5.png`
- `docs/showcase/screenshots/6.png`
