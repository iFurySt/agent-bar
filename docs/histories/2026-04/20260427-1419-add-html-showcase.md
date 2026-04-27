## [2026-04-27 14:19] | Task: add HTML showcase

### 🤖 Execution Context

- **Agent ID**: `codex`
- **Base Model**: `GPT-5`
- **Runtime**: `local zsh`

### 📥 User Query

> Build a GitHub Pages-friendly HTML showcase for Agent Bar, inspired by dynamic-island product sites, so it can later be used for README screenshots or GIF recordings.

### 🛠 Changes Overview

**Scope:** README and static docs showcase

**Key Actions:**

- **[Showcase]**: Added a standalone `docs/showcase/index.html` page with a macOS desktop mock, Agent Bar island states, account expansion, settings usage heatmap, and automatic scene rotation.
- **[Polish]**: Refined the mock into a full-width front-facing macOS desktop, changed Agent Bar into layered island states with a timed cursor/scene animation, fixed non-expanded island panel height, and added URL scene parameters for stable screenshot/GIF capture.
- **[Polish]**: Tightened the top island to match the mock macOS menu bar height, reduced label density, and separated notch versus no-notch showcase states.
- **[Polish]**: Replaced the hand-drawn logo with the repo Codex provider icon, removed the unused compact scene, split usage bar into notch and no-notch states, and aligned the Usage heatmap with the app's month and weekday layout.
- **[Polish]**: Matched the Swift island layout more closely: notch mode uses left logo plus 5h percent, a physical notch gap, and right 7d percent; no-notch mode uses the app's single-line display string, monospaced 11px semibold text, and the same icon/gap/padding rhythm.
- **[Polish]**: Removed the no-notch showcase gear control and reused the notch usage bar for Usage and Usage Tooltip scenes.
- **[Polish]**: Tightened the no-notch showcase width so the right rounded edge follows the final `Tokens` label instead of leaving an empty tail.
- **[Polish]**: Switched the no-notch showcase width from a guessed fixed value to a measured content width, matching Swift's intrinsic-label sizing behavior more closely.
- **[Polish]**: Set all visible 7d values to 55% so the orange warning state is represented, and removed terminal windows from the notch, no-notch, and accounts desktop scenes.
- **[Polish]**: Replaced the header mark with the AgentBar app icon and changed the right-side header copy into a GitHub repository link.
- **[Polish]**: Reused the no-notch usage bar content in the Accounts expansion header.
- **[Polish]**: Removed the obsolete Accounts top padding that was reserved for the old absolute-style header.
- **[Polish]**: Tightened the Accounts expansion width and centered the reused usage bar to avoid a right-side empty tail.
- **[Polish]**: Reworked the Accounts header as an attached no-notch bar with the account cards expanding below it.
- **[Polish]**: Kept compact account quota labels on one line, removed the passive Usage heatmap selection, added the selection only in Usage Tooltip, moved the cursor to the selected heatmap cell, and aligned the Usage sidebar density with the Swift settings sidebar.
- **[Polish]**: Replaced the Usage sidebar text glyphs with fixed-size SVG icons and corrected the tooltip cursor position inside the Mac mock coordinate space.
- **[Polish]**: Moved the Usage tooltip above the hovered heatmap cell so the cursor reads as hovering the selected point.
- **[Polish]**: Removed the separate visual titlebar from the Usage settings mock, let the sidebar run to the window top, reduced the empty space above General, and corrected the General sidebar icon to a gear.
- **[Polish]**: Further reduced the Usage sidebar top padding and replaced the sun-like General glyph with an explicit gear path.
- **[Polish]**: Moved the Usage Tooltip hovered cell and cursor away from the tooltip body so the selected heatmap square remains visible.
- **[Polish]**: Reduced the Accounts expansion height to remove the unused black space below the account cards.
- **[Polish]**: Tuned the Usage Tooltip cursor, selected heatmap cell, and tooltip right offset to match the inspected layout.
- **[README]**: Added a short Showcase section pointing to the static HTML page.

### 🧠 Design Intent (Why)

The README demo should be reproducible instead of depending on one-off screenshots. A pure static page can be served by GitHub Pages and recorded into screenshots, GIFs, or videos without a build step.

### 📁 Files Modified

- `README.md`
- `docs/showcase/index.html`
- `docs/showcase/assets/agentbar.png`
- `docs/showcase/assets/codex.svg`
- `docs/histories/2026-04/20260427-1419-add-html-showcase.md`
