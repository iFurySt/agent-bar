# 功能发布记录

## 2026-07

| 日期 | 功能域 | 用户价值 | 变更摘要 |
| --- | --- | --- | --- |
| 2026-07-04 | Claude Code 配额 | 同时使用 Codex 和 Claude Code 的用户，展开顶部浮窗就能看到 Claude Code 的 5h/weekly 剩余配额，不用切到终端查看；未安装或未登录 Claude Code 时不会看到多余的空状态。 | 新增 Claude Code OAuth 配额读取（本机 `~/.claude/.credentials.json` 或 macOS Keychain，必要时自动刷新 token），展开面板新增单账号、只读的 Claude Code 5h/weekly 配额卡片；收起状态的顶部一行继续只服务 Codex。 |

## 2026-04

| 日期 | 功能域 | 用户价值 | 变更摘要 |
| --- | --- | --- | --- |
| 2026-04-29 | Usage | 快速切换 Day/Year 或连续翻日期时，Usage 不再反复重算旧数据，也不会被较慢返回的中间日期结果回滚。 | Usage 视图级结果写入 `~/.agentbar/cache.json`，过去日期/年份直接复用缓存；今天和当前年使用短时缓存；设置页只刷新当前可见视图，并用 debounce、任务取消和刷新序号保证最后一次选择才能写回图表。 |
| 2026-04-28 | 多屏体验 | 新用户安装并启动后能立刻看到 AgentBar 已经运行，减少“应用是不是没打开”的困惑。 | `AgentBar.pinnedOpen` 缺省值改为 pinned open；只有用户主动取消 pin 后，无 notch 普通屏才进入 auto-hide 行为，已有用户保存过的 pin 选择继续保留。 |
| 2026-04-28 | Usage | Day 视图除了看 token 峰值，也能看到当天真实和 Agent 协作的活跃时间分布。 | 新增独立的 Vibe Coding Time block，读取本地 session 中的用户消息、token_count、命令、patch、diff、collab 等活动事件时间戳，按相邻 10 分钟内归为 active block 的规则聚合到 24 小时，并显示当日总活跃时长；坐标轴对齐 token 图样式，hover 小时点时显示该小时活跃时长；Day 模式下 token 总量和 Vibe 总时长分别移动到各自图表标题行右侧。 |
| 2026-04-28 | Usage | Usage 的 Year/Day 统计按用户本地时区归属，不再把 UTC 日界线附近的 token 误放到前一天或错误小时。 | `CodexCostScanner` 默认使用 `Calendar.autoupdatingCurrent`，Usage 日期显示使用 `TimeZone.autoupdatingCurrent`，cost 缓存记录聚合时区并在时区变化或旧缓存缺少时区时重新解析。 |
| 2026-04-28 | 设置窗口 | Usage 页的 Day/Year 切换、年份/日期选择和 Total 汇总保持在同一操作行，更符合扫视习惯。 | Header 第一行只保留 `Daily Tokens`；第二行左侧放 Day/Year segmented control，中间居中放年份/日期切换，右侧放 `Total x Tokens`。 |
| 2026-04-28 | 自动更新 | 开启 `Automatic Updates` 后，AgentBar 下载并校验新版本后会真正推进安装和重启，不再停在“等用户手动退出才安装”。 | 自动更新模式接管 Sparkle `willInstallUpdateOnQuit` 的 immediate installation block，在下载解包完成后立即触发安装流程；安装等待旧进程退出时短延迟重试终止请求，降低常驻小组件挂起更新的概率。 |
| 2026-04-28 | About | About 页面现在显示当前版本、是否已是最新版本，并在可更新时提供直接触发更新的按钮。 | About 打开时通过 Sparkle probing check 刷新状态；按钮调用 Sparkle 用户触发更新检查，沿用现有下载、自动安装和手动确认流程。 |
| 2026-04-27 | 设置窗口 | Usage 页可以在 Year 年度热力图和 Day 分时柱状图之间切换，既看长期趋势，也能按天查看小时级 token 峰值和模型构成。 | Usage header 新增原生 Day/Year segmented control，默认保持 Year 年度热力图；Year 汇总下移到年份切换同一行并简化为 `Total x Tokens`；Day 在同一位置提供日期左右切换，跨月/跨年按自然日处理，并读取所选日期 00-23 点 token 增量，右侧总量同样简化为 `Total x Tokens`；按当天实际出现的模型生成堆叠柱颜色和图例；小时柱 tooltip 只向上展开，堆叠柱只在最上方保留上圆角，窗口变窄时柱间距自动缩小，最窄可贴合。 |
| 2026-04-27 | 设置窗口 | gear 打开的 General、Accounts、Usage 和 About 页面保持干净的无滚动条外观，滚动时也不会露出系统 scroller。 | 设置窗口主内容滚动视图和 Usage 热力图横向滚动视图保留滚动手势，但不创建可见 scroller。 |
| 2026-04-27 | 设置窗口 | 打开 gear 设置窗口时会自动适配系统 Light/Dark 模式，不再在 Dark 模式下出现浅色背景上的白色文字。 | 将 Settings palette 改成基于 `NSAppearance` 的动态颜色，并让 layer-backed 背景、卡片、分隔线和 Usage heatmap 辅助色在 appearance 变化时刷新。 |
| 2026-04-27 | 自动更新 | 开启 `Automatic Updates` 后升级流程不再每次打断确认；未开启时仍会提示，并能在提示框里改为以后自动更新；升级完成后会收到一次从旧版本到新版本的系统通知。 | 设置开关改为控制 Sparkle 自动下载/安装模式，更新检查保持开启；自动模式下载解包完成后直接重启安装，手动模式确认框新增 `Turn On Automatic Updates`；安装前记录版本，重启后发送一次完成通知。 |
| 2026-04-27 | 设置窗口 | Accounts 页的 5h/7d quota 更容易横向比较，账号邮箱和剩余额度不再挤在同一行里。 | Settings Accounts 账号行改为邮箱下方两条 5h/7d quota bar，并保留右侧 `Switch`/`Current` 控件；账号行高度随内容增加。 |
| 2026-04-27 | 多账号管理 | 无 notch 普通屏展开账号时能更充分利用横向空间，一屏看到更多账号 quota，减少进入 Settings 的次数。 | 普通屏账号展开区在只有 1 个账号时保持单列满宽，超过 1 个账号后进入两列网格并最多展示 8 个账号；刘海屏继续保留单列 4 个账号，超过当前屏幕展示上限仍通过更多账号入口进入 Accounts 页面。 |
| 2026-04-27 | 多账号管理 | 用户保存超过顶部浮窗展示上限的 Codex 账号后，后续账号不会静默消失，而是能明确进入完整账号列表查看和切换。 | island 展开区底部新增更多账号入口；设置窗口新增 Accounts 页面，集中展示所有已见账号、5h/7d quota、当前状态和切换按钮。 |
| 2026-04-25 | 设置窗口 | 用户可以在 AgentBar 设置里按年份查看类似 GitHub contribution calendar 的 Codex token 使用热力图，快速识别每天的本地消耗强度，并悬停查看当天具体费用和 token。 | 新增 Usage 页面，读取 `~/.codex/sessions` 的 `token_count` 事件并按事件 timestamp 聚合到自然日；结果复用 `~/.agentbar/cache.json` 的 session 文件 size/mtime 缓存，跨天继续同一个 session 时会把新增 token 分到对应日期，并补捞最近修改过的旧日期目录 session 文件；热力图补齐年份切换、月份、Mon/Wed/Fri 标尺和深色 hover 浮层。 |
| 2026-04-25 | 顶部浮层交互 | 无 notch 屏幕在常驻或唤出后也保持更干净、更紧凑的单行信息，只有用户把鼠标移到 island 上时才露出 pin 和 settings 控制。 | 将 notch 屏已有的 action icon hover 显隐机制复用到普通屏，普通屏的 pin/gear 只在 hover 或账号展开态预留宽度并延迟显示，离开后恢复隐藏；收紧 quota、Today 和 30 Days 段落间距，去掉 `Tokens` 右侧额外安全宽度，并让 hover 展开/收起时固定左侧、只从右侧伸缩，避免先压缩末尾文字。 |
| 2026-04-25 | 账号展开交互 | 用户查看账号 quota 后不用手动再次点击收起，鼠标离开短暂延迟后展开区会自动回到顶部 island 状态，并可按自己的使用节奏调整等待时间。 | 展开区复用 hover polling 记录鼠标离开面板的时间，默认连续离开 200ms 后收起；设置窗口新增 `Auto Collapse Delay`，以 ms 为单位在 100 到 5000ms 间调整，鼠标在倒计时内回到面板会取消并重新计算。 |
| 2026-04-25 | 多账号切换 | 用户可以通过展开账号卡片里的账号切换控件切换 Codex 主用账号，新开的 Codex CLI 会话会使用切换后的账号，同时切换过程不会把 quota 闪成空数据。 | 账号卡片的邮箱和订阅 chip 右侧显示同高图标按钮，当前账号用 active 图标标识，非当前账号的切换图标 hover 时显示手型 cursor 和高亮样式，只有点击该图标才写回 live `auth.json`；本地先保留已有 quota/plan 并用滑动动画把目标账号置顶，后台刷新完成后再懒加载更新顶部和卡片数字。 |
| 2026-04-25 | 多账号 quota | 用户切换 Codex 登录账号后，AgentBar 可以累积并展示多个账号的剩余 quota，当前主用账号保持置顶，方便比较 5h 和 7d 资源。 | island 支持点击向下展开，展开区以 macOS 风格圆角账号卡片展示邮箱、订阅 chip、5h/7d 剩余百分比、小进度条和 reset 倒计时；新增 `~/.agentbar/accounts.json` 缓存已见 OAuth token，并让顶部百分比优先绑定当前 `auth.json` 账号。 |
| 2026-04-25 | 顶部浮层交互 | notch 屏下方的 settings 悬停交互更稳定，不再在过渡中遮挡右侧百分比文案。 | 调整 notch 布局顺序，保证 usage 文本使用完整宽度，settings 按钮改为 hover 后再显隐，并在 hover 状态变化时触发窗口尺寸重算，避免展开动画中间帧出现 `32%` 只显示 `3` 的裁切现象。 |
| 2026-04-24 | 设置窗口 | 用户可以直接从顶部 bar 右侧齿轮管理开机自动启动和自动更新，也可以在 About 页面进入 GitHub 仓库。 | 在 PIN 右侧新增常驻 gear icon，点击打开紧凑 macOS preferences 风格设置窗口；接入 `SMAppService.mainApp` 开机启动开关、Sparkle 自动更新开关和 About GitHub 页面，并使用 `#226CFF` 选中态。 |
| 2026-04-24 | 自动更新 | 安装过 Sparkle 版本后，AgentBar 可以从 GitHub Releases 自动检测新版本，后台下载完成后再让用户确认是否安装；跳过某个版本后，同版本不会重复打扰。 | 接入 Sparkle 2.9.1，自定义更新确认流程，release workflow 生成并上传签名 `appcast.xml`，DMG 内嵌 `Sparkle.framework` 和公钥配置。 |
| 2026-04-24 | 多屏体验 | 在无 notch 的普通屏幕上，AgentBar 可以跟随顶部菜单栏的隐藏语境自动收起，减少全屏或自动隐藏菜单栏时的视觉冲突；需要常驻时可以点右侧常驻 pin 固定，并在重启后保留选择。 | 新增无 notch 屏幕 auto-hide eligibility、顶部 hover 唤出区、0.26s 滑入滑出动画、右侧常驻 SF Symbols pin 状态按钮，以及 `UserDefaults` 持久化的 pin 偏好。 |
| 2026-04-23 | macOS 图标 | DMG 里的 `AgentBar.app` 在 Finder、Quick Look 和 Applications 中显示标准 macOS 应用图标。 | 新增 `AgentBar.icns`，打包时写入 `CFBundleIconFile`，并用带透明外边距的圆角 app icon 避免直角和视觉过大问题。 |
| 2026-04-23 | macOS 发布 | 可以通过 git tag 自动产出并发布 `AgentBar` DMG，下载物支持 Developer ID 签名与 notarization。 | 新增 macOS DMG 打包脚本，release workflow 改为 tag push 触发，并上传 DMG 到 GitHub Release，同时为 DMG 生成 provenance attestation。 |
| 2026-04-08 | 模板仓库 | 提供了一套可直接用于新项目启动的 Agent-first 基础模板。 | 补齐了 AGENTS 入口、execution plan、history、release note、CI/CD 和供应链安全骨架。 |
