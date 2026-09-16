#!/usr/bin/env bash
# Build Cortex-M4 firmware with QuickLogic's qorc-sdk.
#
#   ./fw_build.sh <app>          e.g. ./fw_build.sh qf_hello
#   ./fw_build.sh <app> clean    remove build output
#
# Output: firmware/<app>/GCC_Project/output/bin/<app>.bin
#
# qorc-sdk apps expect to live three levels below the SDK root
# (their makefiles use GCC_Project/../../..), so the app folder is mounted at
# /opt/qorc-sdk/user_apps/<app> inside the container, next to the SDK sources.
set -euo pipefail

cd "$(dirname "$0")"
source ./scripts/common.sh

APP=${1:-}
if [[ -z "$APP" || ! -d "firmware/$APP/GCC_Project" ]]; then
    echo "usage: $(basename "$0") <app> [clean]"
    echo "apps: $(ls firmware 2>/dev/null | tr '\n' ' ')"
    exit 1
fi

TARGET=${2:-}
DOCKER_EXTRA_ARGS="-v $PWD/firmware/$APP:/opt/qorc-sdk/user_apps/$APP"

# The SDK makefiles don't support parallel builds (-j)
run_in_toolchain "cd /opt/qorc-sdk/user_apps/$APP/GCC_Project && make $TARGET"

if [[ "$TARGET" != "clean" ]]; then
    echo
    echo ">> Firmware: firmware/$APP/GCC_Project/output/bin/$APP.bin"
    ls -l "firmware/$APP/GCC_Project/output/bin/$APP.bin"
fi
