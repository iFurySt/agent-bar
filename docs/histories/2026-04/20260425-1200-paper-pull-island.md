## [2026-04-25 12:00] | Task: Paper-pull island expansion

### Execution Context

- **Agent ID**: `Codex`
- **Base Model**: `GPT-5`
- **Runtime**: `Codex CLI`

### User Query

> 支持点击 island 后向下展开，左右上边和左右下边固定，中间竖线向下展开，类似卷纸拉出来的感觉，先做一版看看。

### Changes Overview

**Scope:** `Sources/AgentBar`

**Key Actions:**

- **Island click interaction**: 点击 island 空白区域切换展开/收起状态，pin 和 settings 按钮继续保留原行为。
- **Paper-pull geometry**: 展开时窗口顶部锚定、高度向下增加，顶部内容保持在原 island 行内。
- **Visual treatment**: 展开态沿用黑色 island 外形，并增加轻微侧边竖线和底部折痕，表达“卷纸拉出”的第一版手感。
- **Persistent controls**: 展开态保持 settings 等控制图标可见并继续参与布局，避免点击展开后图标因为 hover 状态重置或 frame 清零而消失。

### Design Intent (Why)

先把可交互空间和顶部锚定的动画手感跑通，不急着加入详情内容。这样能快速判断展开尺寸、路径和点击行为是否符合预期，再决定后续展开区承载什么信息。

### Files Modified

- `Sources/AgentBar/App.swift`
- `docs/histories/2026-04/20260425-1200-paper-pull-island.md`
