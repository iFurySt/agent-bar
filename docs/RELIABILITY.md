# 稳定性与可运维性

`agent-bar` 的稳定性目标是本机轻量、失败可降级、UI 不阻塞。

## 默认行为

- 顶部浮窗每 60 秒刷新一次。
- 启动时先读取 `~/.agentbar/cache.json` 里的最后一次完整快照，避免空白或长时间 `--%`。
- Codex usage API 读取失败时，使用最近 session 中的 rate limit 事件兜底。
- 本地 cost 扫描默认读取最近约 30 天 `~/.codex/sessions/YYYY/MM/DD/*.jsonl`；设置页 Usage 按所选年份读取 Jan-Dec，Day 视图按用户本地时区选中的自然日读取 00-23 点 token，并用独立 activity scanner 从本地活动事件时间戳计算 Vibe Coding Time，二者都会补捞最近修改过的旧日期目录文件。
- token/cost 缓存按 session 文件的 size/mtime 和聚合时区复用，未变化且时区一致的文件不会重复解析；日级和小时级 Usage 直接复用同一份 `~/.agentbar/cache.json` 聚合。
- 每轮刷新按 session 文件 size/mtime 复用缓存，只重算新增或更新过的文件。
- cost/token 和 Vibe Coding Time 扫描在后台任务中运行，避免阻塞 AppKit 主线程。
- 后台刷新保持静默，不显示状态点，避免快速刷新时造成视觉闪烁。
- 刷新后的数字变化只触发短时本地绘制动画，宽度变化使用 AppKit frame 动画；系统开启 Reduce Motion 时直接更新，不额外制造动画负担。
- 无 notch 普通屏幕用 30Hz 主线程 timer 轮询鼠标位置来做顶部唤出，不依赖额外 Accessibility 权限；窗口平时仍默认透传鼠标事件。
- Sparkle 按 24 小时间隔检查 GitHub Release appcast。About 页打开时用 Sparkle 的 probing check 刷新当前版本是否最新，点击 Check/Update 时才启动用户触发的更新检查与后续下载/安装流程。发现更新后先后台下载；如果设置里的 `Automatic Updates` 已开启，下载和解包完成后通过 Sparkle 的 immediate installation block 直接退出、替换并重启安装，避免常驻小组件一直等到用户手动退出。未开启时才弹出安装确认，用户可选择立即安装、跳过此版本，或打开以后自动更新并安装当前版本；用户跳过后，同一个 `sparkle:version` 不再提醒。升级安装前会记录旧版本和目标版本，新版本启动后尝试发送一次系统通知告知 `Updated from x to y`，通知记录随后清理。
- 设置窗口里的开机启动开关使用 macOS `SMAppService.mainApp`；如果当前运行形态不是可注册 app bundle，失败会回退开关状态并显示系统错误。
- 设置窗口打开时只激活应用并使用普通 window level 展示，避免窗口置顶后阻止用户切换到其他应用或窗口。由于 `.accessory` app 默认不会进入 Command+Tab，打开设置时临时切到 `.regular`，关闭设置后切回 `.accessory`；启动和切入 `.regular` 时显式设置 `NSApp.applicationIconImage` 并刷新 `NSDockTile`，避免临时 Dock 图标退回默认图标。设置窗口自身处理 `Command+W`，不依赖标准 app 菜单也能关闭。

## 验证

```sh
swift test
swift run AgentBar
AGENT_BAR_RELEASE_ARCH=native AGENT_BAR_RELEASE_VERSION=0.0.0-test ./scripts/release-package.sh
```

如果 5h/7d 显示 `--%`，优先检查 `codex` 是否已登录、最近 session 里是否存在 `token_count.rate_limits`，以及 `~/.agentbar/cache.json` 是否可写。
