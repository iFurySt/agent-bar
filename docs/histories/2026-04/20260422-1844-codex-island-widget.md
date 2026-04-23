## [2026-04-22 18:44] | Task: implement Codex island widget

### 🤖 Execution Context

- **Agent ID**: `Codex`
- **Base Model**: `GPT-5`
- **Runtime**: `local macOS SwiftPM`

### 📥 User Query

> 参考 CodexBar 的 Swift 实现，做一个超轻量 macOS 灵动岛小组件，只显示 Codex 5h/Weekly 剩余百分比、当天 token/cost 和约 30 天 token/cost。

### 🛠 Changes Overview

**Scope:** SwiftPM macOS app, Codex data scanning, repository docs

**Key Actions:**

- **Implemented app shell**: Added `AgentBar` AppKit executable with a top-centered rounded floating panel.
- **Implemented data path**: Added Codex usage API reader, OAuth token refresh, local JSONL token/cost scanner, fallback rate limit scanner, and display formatting.
- **Adjusted island placement**: Moved ordinary displays to a transparent top edge overlay, then added notch-aware island placement for built-in notched displays.
- **Added multi-screen overlays**: Created one panel per `NSScreen` and rebuilt overlays when screen parameters change.
- **Researched notch behavior**: Checked public macOS notch implementations and adopted the minimal pattern: detect the physical notch from `NSScreen` safe/auxiliary top areas, keep ordinary displays transparent, and draw a black island shell only where the physical notch would otherwise obscure centered text.
- **Avoided physical notch occlusion**: Changed notched displays to a compact, notch-height island that only shows the icon plus 5h/7d quota while external displays keep the full line.
- **Matched local island geometry**: Verified the local reference app uses a notch-sized closed panel on the built-in display, then adjusted AgentBar so the physical notch is a center gap and compact quota text stays in the left/right lanes.
- **Corrected notch silhouette**: Replaced the iPhone-style capsule background with a custom path modeled after the local X Island `NotchShape`: full-width top edge, 6pt upper shoulder radius, and larger lower rounded corners; verified alpha edge profile against the reference app.
- **Simplified built-in display content**: Copied CodexBar's Codex provider SVG icon and changed the notched display compact content to icon plus the two quota percentages only.
- **Fixed quota refresh**: Made local `token_count.rate_limits` the fast path for quota, preferred base `limit_id == "codex"` over model-specific limits, and kept the usage API only as a fill-in source for missing windows.
- **Tuned compact notch layout**: Pulled the built-in display percentages closer to the physical notch edge, added right-side label safety room, and vertically centered the icon/text on a shared center line.
- **Fixed three-digit percent clipping**: Added symmetric label safety width and a slightly larger notch inner gap so values like `100%` do not get clipped by the physical notch edge.
- **Unified external displays**: Replaced the transparent top bar on ordinary screens with the same top-attached black island language, horizontally centered and showing the full Codex usage line without a center gap.
- **Aligned per-screen menu bar height**: Derived island height separately for each `NSScreen` from the visible top inset, safe area, and notch height so mixed-resolution displays align with their own menu bars.
- **Prevented full-line clipping**: Added label width safety on attached external-screen islands so token counts such as `71M` do not render with a middle ellipsis.
- **Renamed product**: Renamed the local package, executable, targets, source folders, and docs to `agent-bar`/`AgentBar` while keeping Codex provider names for the data source.
- **Reduced quota startup latency**: Changed the fallback quota scanner to read JSONL session files from the tail and stop once a base `codex` quota is found in a file, avoiding long `--%` startup states when recent sessions are large.
- **Added persistent incremental caching**: Added `~/.agentbar/cache.json` for the last full snapshot plus per-session file summaries keyed by path/size/mtime, so startup can show cached values and refreshes only recompute changed files.
- **Improved live refresh affordance and color**: Added a small green pulsing status dot while recomputing and styled quota percentages with green/orange/red remaining-capacity thresholds, with subtler supporting text and token accents on full external-display rows.
- **Added tests**: Covered line formatting and basic Codex session token/cost parsing.
- **Synced docs**: Replaced template README/architecture/UI/reliability/security/quality text with the current project behavior.

### 🧠 Design Intent (Why)

The widget intentionally avoids CodexBar's multi-provider app surface. It keeps only the Codex quota and local token/cost logic needed for a single-line macOS floating display.

### 📁 Files Modified

- `Package.swift`
- `Sources/AgentBar/App.swift`
- `Sources/AgentBarCore/*.swift`
- `Tests/AgentBarCoreTests/*.swift`
- `README.md`
- `docs/ARCHITECTURE.md`
- `docs/FRONTEND.md`
- `docs/RELIABILITY.md`
- `docs/SECURITY.md`
- `docs/QUALITY_SCORE.md`
- `.gitignore`
