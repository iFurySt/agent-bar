#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="${AGENT_BAR_RELEASE_VERSION:-}"
release_tag="${AGENT_BAR_RELEASE_TAG:-}"
dmg_path=""
output_path=""
private_key_file=""
download_url_prefix=""

usage() {
  cat <<'EOF'
Usage: ./scripts/generate-sparkle-appcast.sh --dmg-path PATH [--version X.Y.Z] [--release-tag vX.Y.Z] [--output PATH] [--private-key-file PATH]

Environment:
  AGENT_BAR_SPARKLE_PRIVATE_KEY=base64-private-ed25519-key
  AGENT_BAR_SPARKLE_GENERATE_APPCAST=/path/to/generate_appcast
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      version="${2:-}"
      if [[ -z "${version}" ]]; then
        echo "--version requires a value" >&2
        exit 1
      fi
      shift 2
      ;;
    --release-tag)
      release_tag="${2:-}"
      if [[ -z "${release_tag}" ]]; then
        echo "--release-tag requires a value" >&2
        exit 1
      fi
      shift 2
      ;;
    --dmg-path)
      dmg_path="${2:-}"
      if [[ -z "${dmg_path}" ]]; then
        echo "--dmg-path requires a value" >&2
        exit 1
      fi
      shift 2
      ;;
    --output)
      output_path="${2:-}"
      if [[ -z "${output_path}" ]]; then
        echo "--output requires a value" >&2
        exit 1
      fi
      shift 2
      ;;
    --private-key-file)
      private_key_file="${2:-}"
      if [[ -z "${private_key_file}" ]]; then
        echo "--private-key-file requires a value" >&2
        exit 1
      fi
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "${dmg_path}" ]]; then
  echo "--dmg-path is required" >&2
  usage >&2
  exit 1
fi

if [[ ! -f "${dmg_path}" ]]; then
  echo "DMG does not exist: ${dmg_path}" >&2
  exit 1
fi

if [[ -z "${version}" ]]; then
  if tag="$(git -C "${repo_root}" describe --tags --exact-match 2>/dev/null)"; then
    version="${tag#v}"
  else
    version="0.0.0-dev"
  fi
fi

if [[ -z "${release_tag}" ]]; then
  release_tag="v${version}"
fi

if [[ -z "${output_path}" ]]; then
  output_path="${repo_root}/dist/release/agent-bar/appcast.xml"
fi

download_url_prefix="https://github.com/iFurySt/agent-bar/releases/download/${release_tag}/"

find_generate_appcast() {
  if [[ -n "${AGENT_BAR_SPARKLE_GENERATE_APPCAST:-}" ]]; then
    printf '%s\n' "${AGENT_BAR_SPARKLE_GENERATE_APPCAST}"
    return
  fi

  find "${repo_root}/.build" \
    -path "*/artifacts/sparkle/Sparkle/bin/generate_appcast" \
    -type f \
    | sort \
    | tail -n 1
}

generate_appcast="$(find_generate_appcast)"
if [[ -z "${generate_appcast}" || ! -x "${generate_appcast}" ]]; then
  echo "Missing Sparkle generate_appcast tool. Build AgentBar first so SwiftPM downloads Sparkle artifacts." >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

cp "${dmg_path}" "${tmp_dir}/"

if [[ -n "${private_key_file}" ]]; then
  "${generate_appcast}" \
    --ed-key-file "${private_key_file}" \
    --download-url-prefix "${download_url_prefix}" \
    --maximum-versions 1 \
    -o "${tmp_dir}/appcast.xml" \
    "${tmp_dir}" \
    >/dev/null
else
  if [[ -z "${AGENT_BAR_SPARKLE_PRIVATE_KEY:-}" ]]; then
    echo "AGENT_BAR_SPARKLE_PRIVATE_KEY or --private-key-file is required" >&2
    exit 1
  fi
  printf '%s' "${AGENT_BAR_SPARKLE_PRIVATE_KEY}" \
    | "${generate_appcast}" \
      --ed-key-file - \
      --download-url-prefix "${download_url_prefix}" \
      --maximum-versions 1 \
      -o "${tmp_dir}/appcast.xml" \
      "${tmp_dir}" \
      >/dev/null
fi

mkdir -p "$(dirname "${output_path}")"
cp "${tmp_dir}/appcast.xml" "${output_path}"
echo "${output_path}"
