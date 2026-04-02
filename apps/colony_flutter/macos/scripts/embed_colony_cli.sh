#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "${PROJECT_DIR}/../../.." && pwd)"
APP_RESOURCES_DIR="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"

SWIFT_CONFIG="release"
if [[ "${CONFIGURATION}" == "Debug" ]]; then
  SWIFT_CONFIG="debug"
fi

swift build --package-path "${REPO_ROOT}" -c "${SWIFT_CONFIG}" --product colony

CLI_SOURCE="${REPO_ROOT}/.build/${SWIFT_CONFIG}/colony"
if [[ ! -x "${CLI_SOURCE}" ]]; then
  CLI_SOURCE="${REPO_ROOT}/.build/$(uname -m)-apple-macosx/${SWIFT_CONFIG}/colony"
fi

if [[ ! -x "${CLI_SOURCE}" ]]; then
  echo "error: unable to find built colony CLI at ${CLI_SOURCE}" >&2
  exit 1
fi

mkdir -p "${APP_RESOURCES_DIR}"
ditto "${CLI_SOURCE}" "${APP_RESOURCES_DIR}/colony"
chmod +x "${APP_RESOURCES_DIR}/colony"
