## [2026-04-25 18:34] | Task: Hover controls on ordinary screens

### 🤖 Execution Context

- **Agent ID**: `Codex`
- **Base Model**: `GPT-5`
- **Runtime**: `Codex CLI`

### 📥 User Query

> 之前 notch 屏在鼠标没移上去时隐藏设置 icon，hover 后才动画显示；现在无 notch 屏幕也要应用这套机制。

### 🛠 Changes Overview

**Scope:** macOS AppKit overlay controls

**Key Actions:**

- **[Action 1]**: 让普通 attached island 的 pin/settings 控制也走 hover/展开态可见性，而不是 bar 可见时常驻显示。
- **[Action 2]**: 普通屏宽度计算改为只在 hover 或账号展开态预留 action slot，保持默认单行信息更紧凑。
- **[Action 3]**: 复用 notch 的延迟显示逻辑，避免 icon 在黑色背景宽度动画完成前先露出。
- **[Action 4]**: 收紧普通屏显示字符串、logo 与文本间距、控制按钮间距，并移除 `Tokens` 右侧额外 label safety，让右侧 padding 与左侧 logo 前 padding 对称。
- **[Action 5]**: 调整普通屏 hover 过渡布局，窗口宽度动画期间优先保持完整文本，pin/gear 排在文字后方，避免黑色 island 覆盖或挤压 `Tokens`。
- **[Action 6]**: 普通屏宽度变化时固定左侧窗口边缘，并把 attached bar 内容改为左 padding 锚定，避免鼠标移开时文字先居中再左右同时收缩。
- **[Action 7]**: 修复 notch 屏展开后再次点击收起时 gear 短暂消失的问题；收起时如果鼠标仍在 island 上，继续保持 controls visible，并避免 notch `configure` 在重算布局时重置该状态。
- **[Action 8]**: 调整 notch 右侧百分比的安全宽度，只在 hover/展开需要 action slot 时参与布局；未显示 gear 时让 `7d` 百分比右侧 padding 对齐左侧 logo 前 padding。
- **[Action 9]**: 同步 README、架构、界面约束和功能发布记录。

### 🧠 Design Intent (Why)

普通屏虽然没有物理 notch，但 pin/settings 也是低频控制；默认常驻会让顶部信息更拥挤。把控制入口统一成 hover affordance 后，普通屏和 notch 屏交互模型一致：信息默认优先，鼠标进入 island 后再把控制按钮随宽度动画显现；账号展开时控制保持可见，避免用户展开后失去设置或 pin 入口。普通屏未 hover 时不再预留 action slot 或额外 label safety，避免 `Tokens` 右侧出现大片空白，并让整体宽度更接近真实内容宽度。hover 过渡期间不能用 action slot 反向压缩文本，否则窗口背景还在扩宽时会先遮住末尾文字；普通屏布局因此改为文本优先，控制按钮只从完整文本后方进入。窗口宽度变化也不再每帧重新居中，而是保留左边缘并只移动右边缘，内部内容保持左 padding 锚定，减少鼠标移开后的跳动感。notch 屏展开态依赖 `isExpanded` 保持 gear 可见，收起时如果 hover 延迟尚未写入 `controlsVisible`，gear 会瞬间消失；收起逻辑因此在鼠标仍悬停时主动保留 controls visible，同时 notch 布局重算不能再次把 `controlsVisible` 清零。notch 右侧百分比保留少量文字安全宽度，但只在 action controls 需要出现时计算进整体宽度，避免未显示 gear 时右侧黑边比左侧 logo 外边距更宽。

### 📁 Files Modified

- `Sources/AgentBar/App.swift`
- `Sources/AgentBarCore/DisplayFormatting.swift`
- `Tests/AgentBarCoreTests/DisplayFormattingTests.swift`
- `README.md`
- `docs/ARCHITECTURE.md`
- `docs/FRONTEND.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260425-1834-hover-controls-on-ordinary-screens.md`
