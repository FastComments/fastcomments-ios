#!/bin/bash
set -e

# FastComments iOS — Run All Tests
#
# Usage:
#   ./run_tests.sh           # Run everything
#   ./run_tests.sh sdk       # SDK integration tests only
#   ./run_tests.sh ui        # Single-simulator UI tests only
#   ./run_tests.sh dual      # Dual-simulator live event tests only

DEST='platform=iOS Simulator,name=iPhone 16,OS=latest'
PROJECT="ExampleApp/FastCommentsExample.xcodeproj"
SCHEME="FastCommentsExample"

run_sdk() {
    echo "=========================================="
    echo "  SDK Integration Tests (84 tests)"
    echo "=========================================="
    xcodebuild test \
        -scheme FastCommentsUI \
        -destination "$DEST" \
        2>&1 | grep -E 'Test Case|Executed.*tests|SUCCEEDED|FAILED'
    echo ""
}

run_ui() {
    echo "=========================================="
    echo "  Single-Simulator UI Tests"
    echo "=========================================="
    cd ExampleApp && /opt/homebrew/bin/xcodegen generate 2>&1 | tail -1 && cd ..
    xcodebuild test \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -destination "$DEST" \
        -skip-testing FastCommentsUITests/LiveEventUserA_UITests \
        -skip-testing FastCommentsUITests/LiveEventUserB_UITests \
        -skip-testing FastCommentsUITests/FeedUserA_UITests \
        -skip-testing FastCommentsUITests/FeedUserB_UITests \
        2>&1 | grep -E 'Test Case|Executed.*tests|SUCCEEDED|FAILED'
    echo ""
}

run_dual() {
    echo "=========================================="
    echo "  Dual-Simulator Live Event Tests"
    echo "=========================================="
    echo "  Requires two booted simulators."
    echo "  Check: xcrun simctl list devices booted"
    echo "=========================================="
    cd ExampleApp
    /opt/homebrew/bin/xcodegen generate 2>&1 | tail -1
    lsof -ti :9999 | xargs kill -9 2>/dev/null || true
    sleep 1
    python3 run_dual_sim_tests.py
    cd ..
    echo ""
}

case "${1:-all}" in
    sdk)  run_sdk ;;
    ui)   run_ui ;;
    dual) run_dual ;;
    all)
        run_sdk
        run_ui
        run_dual
        echo "=========================================="
        echo "  ALL TEST SUITES COMPLETE"
        echo "=========================================="
        ;;
    *)
        echo "Usage: $0 [sdk|ui|dual|all]"
        exit 1
        ;;
esac
