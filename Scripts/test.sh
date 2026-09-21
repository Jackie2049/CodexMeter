#!/bin/bash
# Runs the self-contained test harness (CLT has no XCTest/swift-testing).
set -euo pipefail
cd "$(dirname "$0")/.."
swift run CodexMeterTestRunner
