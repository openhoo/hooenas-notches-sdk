#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
if [[ "$(uname -s)" != Darwin ]]; then
  printf '%s\n' 'The full quality gate requires macOS with Swift, Xcode, Node.js and Rust.' >&2
  exit 1
fi
mkdir -p output
python3 -m venv output/quality-tools
output/quality-tools/bin/python -m pip install --quiet --disable-pip-version-check -r requirements-dev.txt
PYTHON_PATHS=(scripts Tests)
output/quality-tools/bin/ruff check "${PYTHON_PATHS[@]}"
output/quality-tools/bin/ruff format --check "${PYTHON_PATHS[@]}"
xcrun swift-format lint --strict --recursive Package.swift Sources Tests
if [[ -f scripts/generate-app-icon.swift ]]; then
  xcrun swift-format lint --strict scripts/generate-app-icon.swift
fi
swift test -Xswiftc -warnings-as-errors
swift build -c release -Xswiftc -warnings-as-errors
npm ci --ignore-scripts
npm run format:check
npm --prefix packages/client ci
npm --prefix packages/client test
# The release build above is mandatory so the integration test cannot skip for a missing helper.
test -x .build/release/hooenas-notches-host
npm --prefix packages/client run test:native
HOOENAS_NOTCHES_HOST="$PROJECT_DIR/.build/release/hooenas-notches-host" python3 scripts/test-host-stream.py
npm --prefix examples/tauri ci
npm --prefix examples/tauri run tauri:build
cargo fmt --manifest-path examples/tauri/src-tauri/Cargo.toml -- --check
cargo clippy --manifest-path examples/tauri/src-tauri/Cargo.toml --locked --all-targets -- -D warnings
python3 scripts/check-project.py
if [[ -f Tests/test_packaging.py ]]; then
  python3 -m unittest discover -s Tests -v
fi
for shell_script in scripts/*.sh; do
  bash -n "$shell_script"
done
git diff --check
