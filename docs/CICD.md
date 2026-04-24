# CI/CD 说明

这个仓库的 CI/CD 已经从模板占位链路切到真实 macOS app 打包链路。

## 当前 release 入口

- `ci.yml`：仓库级检查，覆盖 docs、repo hygiene、GitHub Action pinning、shell 脚本校验和 `swift test`，支持 push、PR 和手动触发。CI 运行在 Ubuntu 上，只声明并测试跨平台的 `AgentBarCore`；macOS AppKit executable 只在 macOS 主机和 release 打包链路里声明。
- `supply-chain-security.yml`：在 PR 上做依赖变更检查，并在 PR、定时任务和手动触发时运行 OSV 扫描。
- `scripts/build-agent-bar-dmg.sh`：构建 `AgentBar.app`，嵌入 `Sparkle.framework`，封装 `dist/release/agent-bar/AgentBar-<version>.dmg`，支持 `native` / `arm64` / `x86_64` / `universal`。
- `scripts/release-package.sh`：release 的统一本地入口，默认构建 universal DMG。
- `scripts/generate-sparkle-appcast.sh`：对 release DMG 生成签名 `appcast.xml`，其中下载 URL 指向同一 GitHub Release 的 DMG asset。
- `.github/workflows/release.yml`：支持 push semver tag 自动发布，也支持手动输入 tag。tag push 会在 `macos-26` 上构建 DMG、生成 Sparkle appcast、生成 build provenance，并把 DMG 与 `appcast.xml` 上传到对应 GitHub Release。

## 签名与 notarization

release workflow 默认使用 ad-hoc signing，保证缺少 secrets 时仍能产出可下载 DMG。配置以下 repo secrets 后会切到 Developer ID 签名，并在上传前做 notarization 和 staple：

- `AGENT_BAR_CODESIGN_P12_BASE64`
- `AGENT_BAR_CODESIGN_P12_PASSWORD`
- `AGENT_BAR_CODESIGN_KEYCHAIN_PASSWORD`
- `AGENT_BAR_CODESIGN_IDENTITY`
- `APPLE_NOTARY_API_KEY_P8_BASE64`
- `APPLE_NOTARY_KEY_ID`
- `APPLE_NOTARY_ISSUER_ID`
- `APPLE_DEVELOPER_TEAM_ID`
- `AGENT_BAR_SPARKLE_PRIVATE_KEY`

`AGENT_BAR_SPARKLE_PRIVATE_KEY` 是 Sparkle EdDSA 私钥，只用于生成 `appcast.xml` 里的更新包签名；对应公钥写入打包脚本生成的 `Info.plist`。缺少这个 secret 时 release workflow 会失败，避免发布无法被客户端校验的 appcast。

## 设计原则

release 入口只维护一条真实构建链路：本地和 GitHub Actions 都通过 `scripts/release-package.sh` 产出同一类 DMG 制品，Sparkle appcast 只引用这份 DMG。后续如果要加入 Homebrew 或更多归档格式，应该在现有脚本上扩展，而不是另起平行流程。

所有 GitHub Actions 都已经 pin 到 commit SHA。后续升级 action 时，也要继续保持这个约束。

## 发布方式

1. 确认 `make ci` 和本地 DMG 打包通过。
2. 提交代码并推送 main。
3. 创建并推送 tag，例如 `git tag v0.1.0 && git push origin v0.1.0`。
4. 用 `gh run watch` 跟踪 release workflow，完成后检查 GitHub Release 里的 `AgentBar-<version>.dmg` 和 `appcast.xml`。

## 默认 release 产物

当前 release 流水线会产出：

- `dist/release/agent-bar/AgentBar-<version>.dmg`
- `dist/release/agent-bar/appcast.xml`
- GitHub Actions 中上传的 `agent-bar-release-artifacts`
- GitHub Releases 中和 tag 对齐的 `AgentBar-<version>.dmg`
- GitHub Releases 中供 Sparkle 读取的 `appcast.xml`
- 对 DMG 生成的 GitHub artifact attestation

也就是说，当前主发布路径已经是由 git tag 驱动的 macOS app DMG 交付链路。
