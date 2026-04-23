# 功能发布记录

## 2026-04

| 日期 | 功能域 | 用户价值 | 变更摘要 |
| --- | --- | --- | --- |
| 2026-04-23 | macOS 发布 | 可以通过 git tag 自动产出并发布 `AgentBar` DMG，下载物支持 Developer ID 签名与 notarization。 | 新增 macOS DMG 打包脚本，release workflow 改为 tag push 触发，并上传 DMG、manifest、SBOM 到 GitHub Release。 |
| 2026-04-08 | 模板仓库 | 提供了一套可直接用于新项目启动的 Agent-first 基础模板。 | 补齐了 AGENTS 入口、execution plan、history、release note、CI/CD 和供应链安全骨架。 |
