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

## 发版流程

当用户说“发版”“发布新版本”“bump version”“打 tag 发布”时，默认执行完整发布闭环，不要只推 tag 后结束。

1. 确认当前最新 tag，例如 `git tag --sort=-v:refname | head`，按 semver bump 下一个版本。当前仓库没有单独版本文件，release 版本由 `vX.Y.Z` tag 决定；如果未来新增版本文件，也要在同一提交里同步。
2. 确认需要面向用户记录的变更已经写入 `docs/releases/feature-release-notes.md`，代码变更已经写入 `docs/histories/`。
3. 本地运行 `make ci`。
4. 本地跑一次 release 包验证，例如 `AGENT_BAR_RELEASE_VERSION=X.Y.Z AGENT_BAR_RELEASE_ARCH=native ./scripts/release-package.sh`。正式 release workflow 会默认构建 universal DMG；本地验证可以用 `native` 节省时间，除非本次改动影响多架构打包。
5. 提交代码并推送 `main`。
6. 创建并推送 tag，例如 `git tag vX.Y.Z && git push origin vX.Y.Z`。
7. 用 `gh run list --repo iFurySt/agent-bar --limit 5` 找到本次 `CI` 和 `release` run。
8. 用 `gh run watch <run-id> --repo iFurySt/agent-bar --exit-status` 持续观察远端 CI 和 release workflow，直到成功或失败。不要在 release workflow 仍在运行时结束任务。
9. release 成功后，用 `gh release view vX.Y.Z --repo iFurySt/agent-bar --json url,tagName,assets` 检查 GitHub Release 和资产，确认至少有 `AgentBar-X.Y.Z.dmg` 和 `appcast.xml`。

如果远端 CI 或 release workflow 失败，默认继续修复到成功：

1. 用 `gh run view <run-id> --repo iFurySt/agent-bar --log-failed` 查看失败日志。
2. 修改代码、脚本、文档或 workflow，重新运行相关本地验证。
3. 提交修复并推送 `main`。
4. 如果失败发生在已经推送的 release tag 上，删除本地和远端的失败 tag，再在修复后的 `HEAD` 重新创建同名 tag：

   ```bash
   git tag -d vX.Y.Z
   git push origin :refs/tags/vX.Y.Z
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

5. 再次用 `gh run watch` 观察新的 CI/release run。重复这个循环，直到 GitHub Release 发布成功。

只有在远端 CI、release workflow 和 GitHub Release 资产都确认成功后，才算发版完成。

## 默认 release 产物

当前 release 流水线会产出：

- `dist/release/agent-bar/AgentBar-<version>.dmg`
- `dist/release/agent-bar/appcast.xml`
- GitHub Actions 中上传的 `agent-bar-release-artifacts`
- GitHub Releases 中和 tag 对齐的 `AgentBar-<version>.dmg`
- GitHub Releases 中供 Sparkle 读取的 `appcast.xml`
- 对 DMG 生成的 GitHub artifact attestation

也就是说，当前主发布路径已经是由 git tag 驱动的 macOS app DMG 交付链路。
