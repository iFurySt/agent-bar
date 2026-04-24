## [2026-04-24 10:10] | Task: 移除 GitHub Release 里无消费方的 metadata 附件

### 用户诉求

检查 `v0.1.1` release assets 里的 `release-manifest.json` 和 `sbom.spdx.json` 是否有实际用途；如果没有，就去掉。

### 本次改动

- **[Release Assets]**: `.github/workflows/release.yml` 不再生成或上传 `release-manifest.json` 与 `sbom.spdx.json`，GitHub Release 只保留 `AgentBar-<version>.dmg`。
- **[Local Packaging]**: `scripts/release-package.sh` 去掉本地 manifest 生成逻辑，统一把 release 输出收敛到真正会分发的 DMG。
- **[Docs Sync]**: 更新 CI/CD、供应链安全和面向用户的 release 记录，移除对 manifest/SBOM release 附件的描述。

### 设计动机

这两个 JSON 文件当前只有“被生成并上传”这一个动作，没有下载入口、校验链路或消费方。对单机 macOS DMG 分发来说，它们只会让 release 页面变噪。保留 DMG 本体和 GitHub 的 build provenance attestation，已经足够表达这条发布链路的真实交付物与来源证明。

### 受影响文件

- `.github/workflows/release.yml`
- `scripts/release-package.sh`
- `docs/CICD.md`
- `docs/SUPPLY_CHAIN_SECURITY.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260423-2038-add-macos-dmg-release-ci.md`
- `docs/histories/2026-04/20260424-1010-remove-release-metadata-assets.md`
