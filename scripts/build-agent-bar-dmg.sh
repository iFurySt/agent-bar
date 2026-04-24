#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
configuration="release"
arch_mode="native"
version=""
output_dir=""
codesign_mode="${AGENT_BAR_CODESIGN_MODE:-adhoc}"
codesign_identity="${AGENT_BAR_CODESIGN_IDENTITY:-}"
codesign_keychain="${AGENT_BAR_CODESIGN_KEYCHAIN:-}"
sparkle_feed_url="${AGENT_BAR_SPARKLE_FEED_URL:-https://github.com/iFurySt/agent-bar/releases/latest/download/appcast.xml}"
sparkle_public_ed_key="${AGENT_BAR_SPARKLE_PUBLIC_ED_KEY:-m30I6HdBwFU7K1JLQyDdrxEbt20YzIXbFAnGdyOz29s=}"

usage() {
  cat <<'EOF'
Usage: ./scripts/build-agent-bar-dmg.sh [--configuration debug|release] [--arch native|arm64|x86_64|universal] [--version X.Y.Z] [--output-dir PATH]

Environment:
  AGENT_BAR_CODESIGN_MODE=identity|adhoc|none
  AGENT_BAR_CODESIGN_IDENTITY="Developer ID Application: Example, Inc. (TEAMID)"
  AGENT_BAR_CODESIGN_KEYCHAIN=/path/to/signing.keychain-db
  AGENT_BAR_SPARKLE_FEED_URL=https://github.com/iFurySt/agent-bar/releases/latest/download/appcast.xml
  AGENT_BAR_SPARKLE_PUBLIC_ED_KEY=base64-public-ed25519-key
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --configuration)
      configuration="${2:-}"
      if [[ -z "${configuration}" ]]; then
        echo "--configuration requires a value" >&2
        exit 1
      fi
      shift 2
      ;;
    --arch)
      arch_mode="${2:-}"
      if [[ -z "${arch_mode}" ]]; then
        echo "--arch requires a value" >&2
        exit 1
      fi
      shift 2
      ;;
    --version)
      version="${2:-}"
      if [[ -z "${version}" ]]; then
        echo "--version requires a value" >&2
        exit 1
      fi
      shift 2
      ;;
    --output-dir)
      output_dir="${2:-}"
      if [[ -z "${output_dir}" ]]; then
        echo "--output-dir requires a value" >&2
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

if [[ "${configuration}" != "debug" && "${configuration}" != "release" ]]; then
  echo "Unsupported configuration: ${configuration}" >&2
  exit 1
fi

if [[ "${arch_mode}" != "native" && "${arch_mode}" != "arm64" && "${arch_mode}" != "x86_64" && "${arch_mode}" != "universal" ]]; then
  echo "Unsupported arch mode: ${arch_mode}" >&2
  exit 1
fi

if [[ "${codesign_mode}" != "identity" && "${codesign_mode}" != "adhoc" && "${codesign_mode}" != "none" ]]; then
  echo "Unsupported AGENT_BAR_CODESIGN_MODE: ${codesign_mode}" >&2
  exit 1
fi

if [[ -z "${version}" ]]; then
  if tag="$(git -C "${repo_root}" describe --tags --exact-match 2>/dev/null)"; then
    version="${tag#v}"
  else
    version="0.0.0-dev"
  fi
fi

if [[ -z "${output_dir}" ]]; then
  output_dir="${repo_root}/dist/release/agent-bar"
fi

build_product() {
  local triple="${1:-}"
  local scratch_path="${2:-}"
  local -a args=(-c "${configuration}")

  if [[ -n "${triple}" ]]; then
    args+=(--triple "${triple}")
  fi

  if [[ -n "${scratch_path}" ]]; then
    args+=(--scratch-path "${scratch_path}")
  fi

  local binary_dir
  binary_dir="$(swift build "${args[@]}" --show-bin-path)"
  swift build "${args[@]}" --product AgentBar >&2

  printf '%s\n' "${binary_dir}"
}

list_user_keychains() {
  security list-keychains -d user \
    | sed -n 's/^[[:space:]]*"\(.*\)"$/\1/p'
}

run_with_codesign_keychain() {
  local keychain_path="${1:-}"
  shift

  if [[ -z "${keychain_path}" ]]; then
    "$@"
    return
  fi

  local -a existing_keychains=()
  while IFS= read -r keychain; do
    if [[ -n "${keychain}" ]]; then
      existing_keychains+=("${keychain}")
    fi
  done < <(list_user_keychains)

  local -a desired_keychains=("${keychain_path}")
  local existing=""
  for existing in "${existing_keychains[@]}"; do
    if [[ "${existing}" != "${keychain_path}" ]]; then
      desired_keychains+=("${existing}")
    fi
  done

  security list-keychains -d user -s "${desired_keychains[@]}" >/dev/null

  local status=0
  "$@" || status=$?

  if [[ ${#existing_keychains[@]} -gt 0 ]]; then
    security list-keychains -d user -s "${existing_keychains[@]}" >/dev/null
  else
    security list-keychains -d user -s >/dev/null
  fi

  return "${status}"
}

resolve_codesign_identity() {
  case "${codesign_mode}" in
    none)
      return 1
      ;;
    adhoc)
      printf '%s\n' "-"
      return 0
      ;;
    identity)
      if [[ -z "${codesign_identity}" ]]; then
        echo "AGENT_BAR_CODESIGN_IDENTITY is required when AGENT_BAR_CODESIGN_MODE=identity" >&2
        exit 1
      fi
      printf '%s\n' "${codesign_identity}"
      return 0
      ;;
  esac
}

codesign_app_bundle() {
  local app_path="${1:-}"
  local identity=""

  if ! identity="$(resolve_codesign_identity)"; then
    echo "Skipping codesign for ${app_path} (AGENT_BAR_CODESIGN_MODE=none)" >&2
    return
  fi

  local -a args=(--force --deep --sign "${identity}")

  if [[ -n "${codesign_keychain}" && "${identity}" != "-" ]]; then
    args+=(--keychain "${codesign_keychain}")
  fi

  if [[ "${identity}" != "-" ]]; then
    args+=(--options runtime)
  fi

  run_with_codesign_keychain "${codesign_keychain}" \
    codesign "${args[@]}" "${app_path}" >/dev/null

  if [[ "${identity}" == "-" ]]; then
    echo "Signed ${app_path} with ad-hoc identity." >&2
  else
    echo "Signed ${app_path} with ${identity}" >&2
  fi
}

find_sparkle_framework() {
  if [[ -n "${AGENT_BAR_SPARKLE_FRAMEWORK_PATH:-}" ]]; then
    printf '%s\n' "${AGENT_BAR_SPARKLE_FRAMEWORK_PATH}"
    return
  fi

  local candidate=""
  candidate="$(find "${repo_root}/.build" \
    -path "*/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" \
    -type d \
    | sort \
    | tail -n 1)"
  if [[ -n "${candidate}" ]]; then
    printf '%s\n' "${candidate}"
    return
  fi

  find "${repo_root}/.build" \
    -path "*/Sparkle.framework" \
    -type d \
    | sort \
    | tail -n 1
}

copy_sparkle_framework() {
  local framework_source=""
  framework_source="$(find_sparkle_framework)"
  if [[ -z "${framework_source}" || ! -d "${framework_source}" ]]; then
    echo "Missing Sparkle.framework. Run swift build before packaging or set AGENT_BAR_SPARKLE_FRAMEWORK_PATH." >&2
    exit 1
  fi

  mkdir -p "${frameworks_dir}"
  ditto "${framework_source}" "${frameworks_dir}/Sparkle.framework"
}

ensure_framework_rpath() {
  local binary_path="${1:-}"
  if ! otool -l "${binary_path}" | grep -q "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "${binary_path}"
  fi
}

app_name="AgentBar.app"
executable_name="AgentBar"
bundle_identifier="com.ifuryst.agentbar"
bundle_version="${AGENT_BAR_BUNDLE_VERSION:-${GITHUB_RUN_NUMBER:-$(git -C "${repo_root}" rev-list --count HEAD 2>/dev/null || echo 1)}}"
app_icon_name="AgentBar.icns"
app_icon_source="${repo_root}/Sources/AgentBar/Resources/${app_icon_name}"
app_root="${output_dir}/${app_name}"
contents_dir="${app_root}/Contents"
macos_dir="${contents_dir}/MacOS"
resources_dir="${contents_dir}/Resources"
frameworks_dir="${contents_dir}/Frameworks"
dmg_root="${output_dir}/dmg-root"
dmg_path="${output_dir}/AgentBar-${version}.dmg"

rm -rf "${output_dir}"
mkdir -p "${macos_dir}" "${resources_dir}" "${dmg_root}"

cd "${repo_root}"

resource_bundle_name="agent-bar_AgentBar.bundle"
resource_source_dir=""

case "${arch_mode}" in
  native)
    binary_dir="$(build_product "" ".build/agent-bar-native-${configuration}")"
    cp "${binary_dir}/${executable_name}" "${macos_dir}/${executable_name}"
    resource_source_dir="${binary_dir}/${resource_bundle_name}"
    ;;
  arm64)
    binary_dir="$(build_product "arm64-apple-macosx14.0" ".build/agent-bar-arm64-${configuration}")"
    cp "${binary_dir}/${executable_name}" "${macos_dir}/${executable_name}"
    resource_source_dir="${binary_dir}/${resource_bundle_name}"
    ;;
  x86_64)
    binary_dir="$(build_product "x86_64-apple-macosx14.0" ".build/agent-bar-x86_64-${configuration}")"
    cp "${binary_dir}/${executable_name}" "${macos_dir}/${executable_name}"
    resource_source_dir="${binary_dir}/${resource_bundle_name}"
    ;;
  universal)
    arm_binary_dir="$(build_product "arm64-apple-macosx14.0" ".build/agent-bar-arm64-${configuration}")"
    x86_binary_dir="$(build_product "x86_64-apple-macosx14.0" ".build/agent-bar-x86_64-${configuration}")"
    lipo -create -output "${macos_dir}/${executable_name}" "${arm_binary_dir}/${executable_name}" "${x86_binary_dir}/${executable_name}"
    resource_source_dir="${arm_binary_dir}/${resource_bundle_name}"
    ;;
esac

chmod +x "${macos_dir}/${executable_name}"

if [[ ! -d "${resource_source_dir}" ]]; then
  echo "Missing SwiftPM resource bundle: ${resource_source_dir}" >&2
  exit 1
fi

if [[ ! -f "${app_icon_source}" ]]; then
  echo "Missing app icon: ${app_icon_source}" >&2
  exit 1
fi

cp -R "${resource_source_dir}" "${resources_dir}/${resource_bundle_name}"
cp "${app_icon_source}" "${resources_dir}/${app_icon_name}"
copy_sparkle_framework
ensure_framework_rpath "${macos_dir}/${executable_name}"

cat > "${contents_dir}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${executable_name}</string>
  <key>CFBundleIdentifier</key>
  <string>${bundle_identifier}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>AgentBar</string>
  <key>CFBundleDisplayName</key>
  <string>AgentBar</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>${app_icon_name}</string>
  <key>CFBundleShortVersionString</key>
  <string>${version}</string>
  <key>CFBundleVersion</key>
  <string>${bundle_version}</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>SUEnableSystemProfiling</key>
  <false/>
  <key>SUFeedURL</key>
  <string>${sparkle_feed_url}</string>
  <key>SUPublicEDKey</key>
  <string>${sparkle_public_ed_key}</string>
  <key>SUScheduledCheckInterval</key>
  <integer>86400</integer>
</dict>
</plist>
PLIST

plutil -lint "${contents_dir}/Info.plist" >/dev/null
codesign_app_bundle "${app_root}"

cp -R "${app_root}" "${dmg_root}/"
ln -s /Applications "${dmg_root}/Applications"

hdiutil create \
  -volname "AgentBar" \
  -srcfolder "${dmg_root}" \
  -ov \
  -format UDZO \
  "${dmg_path}" \
  >/dev/null

echo "${dmg_path}"
