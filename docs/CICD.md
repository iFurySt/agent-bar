# CI/CD 说明

这个仓库的 CI/CD 已经从模板占位链路切到真实 macOS app 打包链路。

## 当前 release 入口

- `ci.yml`：仓库级检查，覆盖 docs、repo hygiene、GitHub Action pinning、shell 脚本校验和 `swift test`。
- `supply-chain-security.yml`：在 PR 上做依赖变更检查，并在 PR、定时任务和手动触发时运行 OSV 扫描。
- `scripts/build-agent-bar-dmg.sh`：构建 `AgentBar.app`，封装 `dist/release/agent-bar/AgentBar-<version>.dmg`，支持 `native` / `arm64` / `x86_64` / `universal`。
- `scripts/release-package.sh`：release 的统一本地入口，默认构建 universal DMG 并写出 `dist/release/agent-bar/release-manifest.json`。
- `.github/workflows/release.yml`：支持 push semver tag 自动发布，也支持手动输入 tag。tag push 会在 `macos-26` 上构建 DMG、生成 SBOM、生成 build provenance，并把 DMG、manifest、SBOM 上传到对应 GitHub Release。

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

## 设计原则

release 入口只维护一条真实构建链路：本地和 GitHub Actions 都通过 `scripts/release-package.sh` 产出同一类 DMG 制品。后续如果要加入 auto-update、Homebrew 或更多归档格式，应该在现有脚本上扩展，而不是另起平行流程。

所有 GitHub Actions 都已经 pin 到 commit SHA。后续升级 action 时，也要继续保持这个约束。

## 发布方式

1. 确认 `make ci` 和本地 DMG 打包通过。
2. 提交代码并推送 main。
3. 创建并推送 tag，例如 `git tag v0.1.0 && git push origin v0.1.0`。
4. 用 `gh run watch` 跟踪 release workflow，完成后检查 GitHub Release 里的 `AgentBar-<version>.dmg`。

## 默认 release 产物

当前 release 流水线会产出：

- `dist/release/agent-bar/AgentBar-<version>.dmg`
- `dist/release/agent-bar/release-manifest.json`
- `dist/release/agent-bar/sbom.spdx.json`
- GitHub Actions 中上传的 `agent-bar-release-artifacts`
- GitHub Releases 中和 tag 对齐的 `AgentBar-<version>.dmg`
- 对 DMG 生成的 GitHub artifact attestation

也就是说，当前主发布路径已经是由 git tag 驱动的 macOS app DMG 交付链路。
