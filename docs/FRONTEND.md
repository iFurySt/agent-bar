# 界面协作说明

这个仓库的界面是 macOS AppKit 顶部浮窗，不是 Web 前端。

## UI 约束

- 所有 UI/UX 改动都要符合 Apple 的设计语言和设计哲学：尊重 macOS 原生控件、系统层级、空间节奏、动效克制和可访问性默认行为；优先使用熟悉、低打扰、直接服务任务的界面表达。
- 视觉风格坚持 less is more。新增入口、状态、文案、装饰和动效前要先证明它确实减少认知负担；能用留白、对齐、层级、系统色和 SF Symbols 解决的，不引入额外装饰、复杂配色或营销化视觉。
- 首屏就是顶部浮窗，不做 landing page、设置页或复杂菜单。
- 浮窗只展示一行：可用的 Codex quota、Today cost/tokens、约 30 天 cost/tokens。quota 标签按服务端窗口时长显示为 `5h`、`Daily`、`7d`、`Monthly`、`Annual`，未知时长不猜测周期；只渲染带有效百分比的窗口，不为缺失窗口保留 `--%`，多个窗口按周期从短到长排列。刘海屏遵循同一规则，只隐藏周期标签并显示百分比。
- 所有屏幕都使用贴住顶部、水平居中的黑色 island，高度对齐各自屏幕当前系统菜单栏的视觉高度；全屏应用左上角绿色 Full Screen 后，系统顶栏 hover 下拉时也按实时 `Menubar` 高度归一化重算，不使用固定 24pt 近似值，也不把菜单栏窗口底部额外边缘算进黑色高度。普通屏幕显示完整信息且中间不留空区，文本分隔保持紧凑，`Tokens` 右侧 padding 和左侧 logo 前 padding 对称；无 notch 的普通屏幕新用户首次启动默认 pinned open，取消 pin 后才自动收起，顶边悬停时按 0.26s ease-in-out 滑出，鼠标悬停到 island 后右侧 pin icon 和 gear icon 才随宽度动画显现；gear 打开轻量设置窗口，窗口使用紧凑 macOS preferences 风格：sidebar、正文、grouped settings 卡片、边框、分隔线和 Usage heatmap 辅助色必须跟随系统 Light/Dark appearance 自动切换，Light 模式保留 sidebar `#E6E5E3`、正文 `#F3F1EF`、卡片 `#EFEDEB`，`#226CFF` 选中态和原生开关保持一致，不能出现浅色背景配白字或深色背景配黑字。Accounts 作为独立页面展示所有已见 Codex 账号，每行在邮箱下方用两条低对比 5h/7d quota bar 表达剩余量，切换控件使用贴在 plan chip 右侧的小型符号按钮；账号列表不在 grouped block 内部滚动，block 随账号数量完整撑开，由右侧正文主体承担纵向滚动，但不显示滚动条。Usage 作为独立页面在 header 第一行显示 `Daily Tokens`，第二行左侧使用原生 segmented control 切换 Day/Year，中间居中显示日期/年份切换，右侧总量只写 `Total x Tokens`；Year 展示类似 GitHub contribution calendar 的年度 token 热力图并提供年份左右切换，热力图顶部显示月份、左侧显示 Mon/Wed/Fri，hover 单元格时用自适应宽高的深色浮层展示缩写日期、美元消耗和 Tokens，所有日期都按用户本地时区归属和显示，年度热力图宽于默认设置窗口时只在卡片内部横向滚动且不显示滚动条，不应撑宽整个设置窗口；Day 在同一控制行提供日期左右切换，跨月和跨年都用用户本地 Calendar 自然日加减，并展示所选本地日期 00-24 的小时级 token 堆叠柱状图和跟在下方的独立 Vibe Coding Time block，token 图标题为 `Tokens`，横轴按 4 小时间隔标注，末尾使用 `Hours` 表示小时轴，纵轴使用紧凑 token 单位，只为当天实际出现的模型生成柱段颜色和底部 legend，legend 与柱状图/横轴标签之间必须保留清楚间距，legend 每行居中且过多时自动换行继续居中；Vibe Coding Time 使用紫色低对比面积图展示每小时 active block 分布，并在标题旁显示当日总活跃时长；堆叠柱内部和底部保持直角，只允许最上方柱段的上两角圆角；hover 单小时柱子时 tooltip 只向上展开，避免挡住鼠标，并显示总 tokens 和模型拆分；Day 图表不能撑宽设置窗口，窗口变窄时柱间距逐步缩小，极窄时允许柱子贴合；About 作为独立页面展示当前版本、更新状态、紧凑的 Check/Update 按钮和 GitHub 仓库入口；刘海屏绘制和 notch 等高的小型黑色 island，把物理 notch 作为中心禁区，不显示 `5h`/`7d` 文本标签，并在右侧保留 hover 显现的 gear icon（无 pin）。
- Vibe Coding Time 的坐标轴要和 Day token 图保持一致：Y 轴放左侧，轴标签使用 `heatmapLabel` 和 10.8pt monospaced 字体，横轴末尾写 `Hours`；hover 小时点时复用 Usage 页面级 tooltip 显示该小时活跃时长。
- Day 模式的 total 不放在 Usage 页面 header 右侧；token 总量放在 `Tokens` 标题行右侧并带模型色小圆点，Vibe 总时长放在 `Vibe Coding Time` 标题行右侧并带紫色小圆点，圆点与文字保持垂直居中。
- 刘海屏黑底遵循 X Island 同类 macOS notch 轮廓：顶边贴住屏幕直线，左右侧从顶边用小半径收进，底部两侧使用更大的圆角；不要用 iPhone Dynamic Island 那种双边胶囊形，也不要用透明圆形直接挖出大缺口。
- 无 notch 的自动隐藏 island 默认忽略鼠标事件；悬停唤出或点击 pin/settings 时临时接管鼠标，避免平时挡住菜单栏交互；刘海屏 island 保持常驻交互，悬停后才展示设置入口。
- 账号展开区只在鼠标离开整个 island 面板后开始自动收回倒计时，默认 200ms，设置窗口以 ms 为单位可调 100 到 5000ms；鼠标回到面板内要取消并重新计算，停留在面板内时不得自动收回。
- 账号展开区在无 notch 普通屏只有 1 个账号时保持单列满宽，超过 1 个账号后按两列最多展示 8 个账号；刘海屏仍保持单列，最多展示当前账号和最近 3 个账号。超过当前屏幕展示上限时不要把顶部浮窗变成滚动列表，而是在底部显示更多账号入口，打开 Settings 的 Accounts 页查看和切换全部账号。
- 文本过长时允许中间截断，但不换行、不改变浮窗高度。
- quota、cost、token 等数字变化时使用短时向上滚动；位数变化导致的 island 宽度变化要用缓和动画过渡，不允许瞬间跳宽。系统开启 Reduce Motion 时禁用这些刷新动画。

## 本地验证

```sh
swift run AgentBar
```
