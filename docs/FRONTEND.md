# 界面协作说明

这个仓库的界面是 macOS AppKit 顶部浮窗，不是 Web 前端。

## UI 约束

- 首屏就是顶部浮窗，不做 landing page、设置页或复杂菜单。
- 浮窗只展示一行：`5h`、`7d`、Today cost/tokens、约 30 天 cost/tokens。
- 所有屏幕都使用贴住顶部、水平居中的黑色 island，高度对齐各自屏幕的菜单栏高度。普通屏幕显示完整信息且中间不留空区；无 notch 的普通屏幕未 pin 时自动收起，顶边悬停时按 0.26s ease-in-out 滑出，bar 可见时右侧常驻显示 pin icon 和 gear icon；gear 打开轻量设置窗口，窗口使用紧凑 macOS preferences 风格：sidebar 背景 `#E6E5E3`，正文背景 `#F3F1EF`，grouped settings 卡片背景 `#EFEDEB`，`#226CFF` 选中态和原生开关，About 作为独立页面展示 GitHub 仓库入口；刘海屏绘制和 notch 等高的小型黑色 island，把物理 notch 作为中心禁区，不显示 `5h`/`7d` 文本标签，并在右侧保留 gear icon（无 pin）。
- 刘海屏黑底遵循 X Island 同类 macOS notch 轮廓：顶边贴住屏幕直线，左右侧从顶边用小半径收进，底部两侧使用更大的圆角；不要用 iPhone Dynamic Island 那种双边胶囊形，也不要用透明圆形直接挖出大缺口。
- 无 notch 的自动隐藏 island 默认忽略鼠标事件；悬停或点击 pin 时临时接管鼠标，避免平时挡住菜单栏交互；刘海屏 island 保持常驻交互，始终接收点击以访问设置入口。
- 账号展开区只在鼠标离开整个 island 面板后开始自动收回倒计时，默认 200ms，设置窗口以 ms 为单位可调 100 到 5000ms；鼠标回到面板内要取消并重新计算，停留在面板内时不得自动收回。
- 文本过长时允许中间截断，但不换行、不改变浮窗高度。
- quota、cost、token 等数字变化时使用短时向上滚动；位数变化导致的 island 宽度变化要用缓和动画过渡，不允许瞬间跳宽。系统开启 Reduce Motion 时禁用这些刷新动画。

## 本地验证

```sh
swift run AgentBar
```
