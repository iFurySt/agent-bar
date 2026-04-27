# 界面协作说明

这个仓库的界面是 macOS AppKit 顶部浮窗，不是 Web 前端。

## UI 约束

- 首屏就是顶部浮窗，不做 landing page、设置页或复杂菜单。
- 浮窗只展示一行：`5h`、`7d`、Today cost/tokens、约 30 天 cost/tokens。
- 所有屏幕都使用贴住顶部、水平居中的黑色 island，高度对齐各自屏幕当前系统菜单栏的视觉高度；全屏应用左上角绿色 Full Screen 后，系统顶栏 hover 下拉时也按实时 `Menubar` 高度归一化重算，不使用固定 24pt 近似值，也不把菜单栏窗口底部额外边缘算进黑色高度。普通屏幕显示完整信息且中间不留空区，文本分隔保持紧凑，`Tokens` 右侧 padding 和左侧 logo 前 padding 对称；无 notch 的普通屏幕未 pin 时自动收起，顶边悬停时按 0.26s ease-in-out 滑出，鼠标悬停到 island 后右侧 pin icon 和 gear icon 才随宽度动画显现；gear 打开轻量设置窗口，窗口使用紧凑 macOS preferences 风格：sidebar 背景 `#E6E5E3`，正文背景 `#F3F1EF`，grouped settings 卡片背景 `#EFEDEB`，`#226CFF` 选中态和原生开关，Accounts 作为独立页面展示所有已见 Codex 账号和切换按钮，Usage 作为独立页面展示类似 GitHub contribution calendar 的年度 token 热力图，header 中间提供年份左右切换，热力图顶部显示月份、左侧显示 Mon/Wed/Fri，hover 单元格时用自适应宽高的深色浮层展示缩写日期、美元消耗和 Tokens，年度热力图宽于默认设置窗口时只在卡片内部横向滚动，不应撑宽整个设置窗口，About 作为独立页面展示 GitHub 仓库入口；刘海屏绘制和 notch 等高的小型黑色 island，把物理 notch 作为中心禁区，不显示 `5h`/`7d` 文本标签，并在右侧保留 hover 显现的 gear icon（无 pin）。
- 刘海屏黑底遵循 X Island 同类 macOS notch 轮廓：顶边贴住屏幕直线，左右侧从顶边用小半径收进，底部两侧使用更大的圆角；不要用 iPhone Dynamic Island 那种双边胶囊形，也不要用透明圆形直接挖出大缺口。
- 无 notch 的自动隐藏 island 默认忽略鼠标事件；悬停唤出或点击 pin/settings 时临时接管鼠标，避免平时挡住菜单栏交互；刘海屏 island 保持常驻交互，悬停后才展示设置入口。
- 账号展开区只在鼠标离开整个 island 面板后开始自动收回倒计时，默认 200ms，设置窗口以 ms 为单位可调 100 到 5000ms；鼠标回到面板内要取消并重新计算，停留在面板内时不得自动收回。
- 账号展开区最多展示当前账号和最近 3 个账号；超过 4 个账号时不要把顶部浮窗变成滚动列表，而是在底部显示 `View N more accounts` 入口，打开 Settings 的 Accounts 页查看和切换全部账号。
- 文本过长时允许中间截断，但不换行、不改变浮窗高度。
- quota、cost、token 等数字变化时使用短时向上滚动；位数变化导致的 island 宽度变化要用缓和动画过渡，不允许瞬间跳宽。系统开启 Reduce Motion 时禁用这些刷新动画。

## 本地验证

```sh
swift run AgentBar
```
