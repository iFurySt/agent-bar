## [2026-04-23 20:38] | Task: 接入 macOS app 打包 CI 并用 tag 发布 DMG

### 用户诉求

参考相邻 macOS app 仓库的发布方式，为本仓库接入 GitHub Actions macOS app 打包 CI；签名和 notarization 所需材料从本机既有资产写入 repo secrets；最终通过 git tag 触发发布，并把 DMG 上传到 GitHub Releases。

### 本次改动

- **[DMG Builder]**: 新增 `scripts/build-agent-bar-dmg.sh`，支持 SwiftPM `AgentBar` 的 native / arm64 / x86_64 / universal 构建，封装 `AgentBar.app` 和 `AgentBar-<version>.dmg`。
- **[Resource Packaging]**: App 内的 Codex icon 资源加载先查 `Contents/Resources` 下的 SwiftPM resource bundle，再回退到本地 `Bundle.module`，保证打包后的 `.app` 结构可签名。
- **[Signing Path]**: 打包脚本支持 `AGENT_BAR_CODESIGN_*` 环境变量；release workflow 会在 secrets 存在时导入 Developer ID `.p12`，用 hardened runtime 签名 app。
- **[Notarization Path]**: release workflow 在 Developer ID 签名和 `APPLE_NOTARY_*` secrets 都存在时提交 DMG notarization 并 staple。
- **[Tag Release]**: `.github/workflows/release.yml` 改为 push semver tag 触发，发布 DMG、manifest、SBOM，并为 DMG 生成 provenance。
- **[Docs Sync]**: 更新 CI/CD、架构边界、质量评分和面向用户 release notes。

### 设计动机

`AgentBar` 已经是明确的单机 macOS AppKit 小组件，继续保留模板式 repo metadata release 会让真实交付路径缺位。把本地脚本和 GitHub Actions 都收敛到同一个 `scripts/release-package.sh` 入口，可以让 tag、DMG 文件名、manifest 和 release 页面稳定对齐；Developer ID 签名和 notarization 则保持可选降级，避免 secrets 缺失时完全阻断打包。

### 受影响文件

- `.github/workflows/release.yml`
- `Sources/AgentBar/App.swift`
- `scripts/build-agent-bar-dmg.sh`
- `scripts/release-package.sh`
- `scripts/ci.sh`
- `docs/CICD.md`
- `docs/ARCHITECTURE.md`
- `docs/QUALITY_SCORE.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260423-2038-add-macos-dmg-release-ci.md`
