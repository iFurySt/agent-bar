# 界面协作说明

这个仓库的界面是 macOS AppKit 顶部浮窗，不是 Web 前端。

## UI 约束

- 首屏就是顶部浮窗，不做 landing page、设置页或复杂菜单。
- 浮窗只展示一行：`5h`、`7d`、Today cost/tokens、约 30 天 cost/tokens。
- 所有屏幕都使用贴住顶部、水平居中的黑色 island，高度对齐各自屏幕的菜单栏高度。普通屏幕显示完整信息且中间不留空区；刘海屏绘制和 notch 等高的小型黑色 island，把物理 notch 作为中心禁区，只显示 Codex icon、5h 百分比和 7d 百分比，不显示 `5h`/`7d` 文本标签。
- 刘海屏黑底遵循 X Island 同类 macOS notch 轮廓：顶边贴住屏幕直线，左右侧从顶边用小半径收进，底部两侧使用更大的圆角；不要用 iPhone Dynamic Island 那种双边胶囊形，也不要用透明圆形直接挖出大缺口。
- 窗口忽略鼠标事件，避免透明覆盖层挡住菜单栏交互。
- 文本过长时允许中间截断，但不换行、不改变浮窗高度。

## 本地验证

```sh
swift run AgentBar
```
