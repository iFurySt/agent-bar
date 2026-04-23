#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
release_dir="${repo_root}/dist/release/agent-bar"
version="${AGENT_BAR_RELEASE_VERSION:-}"

if [[ -z "${version}" ]]; then
  if tag="$(git -C "${repo_root}" describe --tags --exact-match 2>/dev/null)"; then
    version="${tag#v}"
  else
    version="0.0.0-dev"
  fi
fi

"${repo_root}/scripts/build-agent-bar-dmg.sh" \
  --configuration release \
  --arch "${AGENT_BAR_RELEASE_ARCH:-universal}" \
  --version "${version}" \
  --output-dir "${release_dir}"

cat > "${release_dir}/release-manifest.json" <<EOF
{
  "repository": "${GITHUB_REPOSITORY:-local}",
  "git_sha": "${GITHUB_SHA:-$(git -C "${repo_root}" rev-parse HEAD 2>/dev/null || echo unknown)}",
  "generated_at_utc": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "version": "${version}",
  "artifact": "AgentBar-${version}.dmg"
}
EOF

echo "${release_dir}/AgentBar-${version}.dmg"
