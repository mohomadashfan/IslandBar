#!/usr/bin/env bash
# Runs the test suite with a toolchain that includes XCTest.
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/toolchain.sh

swift test "$@"
