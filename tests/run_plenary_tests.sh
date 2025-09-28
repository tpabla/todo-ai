#!/usr/bin/env bash

# TodoAI Plenary Test Runner
# Runs tests using Plenary.nvim inside Neovim

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}🧪 TodoAI Plenary Test Suite${NC}"
echo "================================"

# Check if Neovim is installed
if ! command -v nvim &> /dev/null; then
    echo -e "${RED}❌ Neovim not found. Please install Neovim first.${NC}"
    exit 1
fi

# Default to running all tests
TEST_DIR="${1:-tests/plenary}"
MINIMAL_INIT="tests/minimal_init.lua"

# Check if test directory exists
if [ ! -d "$TEST_DIR" ]; then
    echo -e "${YELLOW}⚠️  Test directory not found: $TEST_DIR${NC}"
    echo "Creating Plenary test directory..."
    mkdir -p "$TEST_DIR"
fi

# Run tests based on arguments
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    echo "Usage: $0 [test_directory] [options]"
    echo ""
    echo "Examples:"
    echo "  $0                    # Run all tests"
    echo "  $0 tests/plenary      # Run tests in specific directory"
    echo "  $0 --watch            # Watch mode (requires entr)"
    echo "  $0 --coverage         # Run with coverage report"
    exit 0
fi

# Watch mode
if [ "$1" == "--watch" ] || [ "$2" == "--watch" ]; then
    if ! command -v entr &> /dev/null; then
        echo -e "${YELLOW}⚠️  'entr' not found. Install it for watch mode.${NC}"
        echo "  macOS: brew install entr"
        echo "  Linux: apt/yum install entr"
        exit 1
    fi

    echo -e "${BLUE}👁️  Watch mode enabled${NC}"
    find lua tests -name "*.lua" | entr -c bash $0
    exit 0
fi

# Coverage mode
if [ "$1" == "--coverage" ] || [ "$2" == "--coverage" ]; then
    echo -e "${BLUE}📊 Running with coverage...${NC}"
    nvim --headless --noplugin -u "$MINIMAL_INIT" \
         -c "lua require('plenary.test_harness').test_directory('$TEST_DIR', { minimal_init = '$MINIMAL_INIT', sequential = true })" \
         -c "lua require('tests.coverage').report()" \
         -c "qall!"
    exit $?
fi

# Normal test run
echo -e "${BLUE}Running tests in: $TEST_DIR${NC}"
echo ""

# Run Plenary tests
nvim --headless --noplugin -u "$MINIMAL_INIT" \
     -c "lua require('plenary.test_harness').test_directory('$TEST_DIR', { minimal_init = '$MINIMAL_INIT', sequential = false })" \
     -c "qall!" \
     2>&1 | tee /tmp/test-results.txt

# Check results
if grep -q "Tests Failed" /tmp/test-results.txt; then
    echo ""
    echo -e "${RED}❌ Some tests failed. Check output above.${NC}"
    exit 1
else
    echo ""
    echo -e "${GREEN}✅ All Plenary tests passed!${NC}"
    exit 0
fi