# agent-bar

一个超轻量 macOS 顶部浮窗，用一行信息显示 Codex 剩余额度和本地 token/cost 消耗。

```text
[CODEX] 5h 47%   7d 79%      Today: $119.63 · 307M / ~30 Days: $1,448.86 · 3.4B Tokens
```

## 功能

- 显示 Codex 5h 和 7d 窗口的剩余百分比。
- 扫描本机 `~/.codex/sessions`，显示当天 token/cost 与约 30 天 token/cost。
- 所有屏幕都使用贴住顶部、水平居中的黑色 attached island，并按各自屏幕的菜单栏高度绘制。无 notch 的普通屏幕支持未 pin 时自动收起，顶边悬停时按菜单栏自动隐藏节奏滑出，并在 PIN 右侧提供轻量设置窗口。刘海屏按物理 notch 几何绘制等高 compact island，把 notch 中心作为禁区，只显示 Codex icon 和两个剩余百分比。黑底参考 X Island 的 macOS notch path，顶边贴屏成直线，上侧小半径收肩，底部使用更大圆角，不使用 iPhone 式胶囊圆角。
- 只使用 SwiftPM、Foundation、AppKit、ServiceManagement 和 Sparkle，不引入 CodexBar 的多 provider 或额外打包框架。
- 优先从最近 Codex session 的 `token_count.rate_limits` 读取 quota，基础 `codex` 窗口缺失时再用 Codex usage API 补齐。
- 支持通过 GitHub Releases 的 Sparkle appcast 自动检查更新；检测到新版本后先后台下载，准备好安装时再让用户确认，跳过后同版本不再提醒。
- 设置窗口提供开机自动启动、自动更新开关；About 页面展示 GitHub 仓库入口。

## 运行

```sh
swift run AgentBar
```

应用默认读取 `CODEX_HOME`，没有设置时读取 `~/.codex`。

## 验证

```sh
swift test
```

## 许可证

[MIT](LICENSE)
