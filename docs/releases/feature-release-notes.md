# 功能发布记录

## 2026-04

| 日期 | 功能域 | 用户价值 | 变更摘要 |
| --- | --- | --- | --- |
| 2026-04-27 | 设置窗口 | Accounts 页的 5h/7d quota 更容易横向比较，账号邮箱和剩余额度不再挤在同一行里。 | Settings Accounts 账号行改为邮箱下方两条 5h/7d quota bar，并保留右侧 `Switch`/`Current` 控件；账号行高度随内容增加。 |
| 2026-04-27 | 多账号管理 | 无 notch 普通屏展开账号时能更充分利用横向空间，一屏看到更多账号 quota，减少进入 Settings 的次数。 | 普通屏账号展开区改为两列网格，最多展示 8 个账号；刘海屏继续保留单列 4 个账号，超过当前屏幕展示上限仍通过更多账号入口进入 Accounts 页面。 |
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
