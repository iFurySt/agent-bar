# 功能发布记录

## 2026-04

| 日期 | 功能域 | 用户价值 | 变更摘要 |
| --- | --- | --- | --- |
| 2026-04-24 | 自动更新 | 安装过 Sparkle 版本后，AgentBar 可以从 GitHub Releases 自动检测新版本，后台下载完成后再让用户确认是否安装；跳过某个版本后，同版本不会重复打扰。 | 接入 Sparkle 2.9.1，自定义更新确认流程，release workflow 生成并上传签名 `appcast.xml`，DMG 内嵌 `Sparkle.framework` 和公钥配置。 |
| 2026-04-24 | 多屏体验 | 在无 notch 的普通屏幕上，AgentBar 可以跟随顶部菜单栏的隐藏语境自动收起，减少全屏或自动隐藏菜单栏时的视觉冲突；需要常驻时可以点右侧常驻 pin 固定，并在重启后保留选择。 | 新增无 notch 屏幕 auto-hide eligibility、顶部 hover 唤出区、0.26s 滑入滑出动画、右侧常驻 SF Symbols pin 状态按钮，以及 `UserDefaults` 持久化的 pin 偏好。 |
| 2026-04-23 | macOS 图标 | DMG 里的 `AgentBar.app` 在 Finder、Quick Look 和 Applications 中显示标准 macOS 应用图标。 | 新增 `AgentBar.icns`，打包时写入 `CFBundleIconFile`，并用带透明外边距的圆角 app icon 避免直角和视觉过大问题。 |
| 2026-04-23 | macOS 发布 | 可以通过 git tag 自动产出并发布 `AgentBar` DMG，下载物支持 Developer ID 签名与 notarization。 | 新增 macOS DMG 打包脚本，release workflow 改为 tag push 触发，并上传 DMG 到 GitHub Release，同时为 DMG 生成 provenance attestation。 |
| 2026-04-08 | 模板仓库 | 提供了一套可直接用于新项目启动的 Agent-first 基础模板。 | 补齐了 AGENTS 入口、execution plan、history、release note、CI/CD 和供应链安全骨架。 |
