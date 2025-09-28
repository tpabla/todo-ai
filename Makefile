.PHONY: test test-unit test-integration test-all lint install clean docs docs-update-readme

# Default target
all: install

# Install plugin
install:
	@echo "Installing todo-ai plugin..."
	@./install.sh

# Run all tests (Plenary)
test:
	@echo "Running Plenary tests..."
	@nvim --headless --noplugin -l tests/run_tests.lua 2>&1 | grep -v "^Test environment" | tail -100

# Alias for backwards compatibility
test-plenary: test

# Run specific test file
test-file:
	@echo "Running test file: $(FILE)"
	@nvim --headless --noplugin -u tests/minimal_init.lua \
		-c "lua require('plenary.busted').run('$(FILE)')" \
		-c "qall!"

# Lint code
lint:
	@echo "Linting Lua code..."
	@which luacheck > /dev/null 2>&1 || (echo "Installing luacheck..." && luarocks install luacheck)
	@luacheck lua/ --globals vim --ignore 212 213 --max-line-length 120

# Clean build artifacts
clean:
	@echo "Cleaning up..."
	@rm -rf .todoai/
	@rm -f /tmp/todo-ai.log
	@find . -name "*.swp" -delete
	@find . -name "*~" -delete

# Development setup
dev:
	@echo "Setting up development environment..."
	@./dev-setup.sh


# Generate API documentation (always runs)
docs:
	@echo "Generating API documentation..."
	@rm -rf docs/api
	@lua scripts/generate_docs.lua lua/todo-ai docs/api

# Update README with API docs links
docs-update-readme: docs
	@echo "Updating README with API documentation links..."
	@echo "\n## API Documentation\n" >> README.md
	@echo "Auto-generated API documentation from LuaLS annotations:\n" >> README.md
	@find docs/api -name "*.md" | sort | while read file; do \
		name=$$(basename $$file .md); \
		path=$$file; \
		echo "- [$$name]($$path)" >> README.md; \
	done

# Check dependencies
check-deps:
	@echo "Checking dependencies..."
	@which lua > /dev/null 2>&1 || echo "Warning: lua not found"
	@which nvim > /dev/null 2>&1 || echo "Warning: nvim not found"
	@which curl > /dev/null 2>&1 || echo "Warning: curl not found"
	@test -n "$$ANTHROPIC_API_KEY" || echo "Warning: ANTHROPIC_API_KEY not set"

# Run benchmarks
bench:
	@echo "Running benchmarks..."
	@cd test && lua benchmark.lua

# Watch for changes and run tests
watch:
	@echo "Watching for changes..."
	@which fswatch > /dev/null 2>&1 || (echo "Installing fswatch..." && brew install fswatch)
	@fswatch -o lua/ test/ | xargs -n1 -I{} make test-unit

# Help
help:
	@echo "Available targets:"
	@echo "  make install      - Install the plugin"
	@echo "  make test        - Run all tests"
	@echo "  make test-unit   - Run unit tests"
	@echo "  make test-integration - Run integration tests"
	@echo "  make lint        - Lint the code"
	@echo "  make clean       - Clean build artifacts"
	@echo "  make dev         - Setup development environment"
	@echo "  make docs        - Generate documentation"
	@echo "  make check-deps  - Check dependencies"
	@echo "  make help        - Show this help message"