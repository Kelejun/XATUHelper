#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export PATH="$HOME/.swiftly/bin:$ANDROID_HOME/platform-tools:/opt/homebrew/bin:$PATH"
cd "$project_dir/Android"
# Gradle runs Skip's Swift and Kotlin generation in the correct order.
exec gradle :app:assembleDebug "$@"
