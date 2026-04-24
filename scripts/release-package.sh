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

echo "${release_dir}/AgentBar-${version}.dmg"
