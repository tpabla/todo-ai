.PHONY: test test-lua test-single test-watch clean install dev lint help

# --- Test ---

test: test-lua ## Run all tests

test-lua: ## Run Lua/Neovim tests
	@echo "Running Lua tests..."
	@nvim --headless -u tests/minimal_init.lua \
		-c 'PlenaryBustedDirectory tests/plenary/ {minimal_init="tests/minimal_init.lua", sequential=true}'

test-single: ## Run single test file (FILE=tests/plenary/xxx_spec.lua)
	@test -z "$(FILE)" && echo "Usage: make test-single FILE=tests/plenary/xxx_spec.lua" && exit 1 || true
	@echo "Running: $(FILE)"
	@nvim --headless -u tests/minimal_init.lua \
		-c "PlenaryBustedFile $(FILE)"

test-watch: ## Watch for changes and re-run tests
	@which fswatch > /dev/null || (echo "Install fswatch: brew install fswatch" && exit 1)
	@while true; do \
		clear; \
		make test-lua; \
		echo ""; \
		echo "Watching for changes (Ctrl+C to stop)..."; \
		fswatch -1 -r lua/ tests/ 2>/dev/null; \
	done

# --- Install ---

install: ## Install to Neovim packages dir
	@mkdir -p ~/.local/share/nvim/site/pack/plugins/start/todo-ai
	@rsync -a --delete \
		--exclude .git \
		--exclude .todoai \
		. ~/.local/share/nvim/site/pack/plugins/start/todo-ai/
	@echo "Installed to ~/.local/share/nvim/site/pack/plugins/start/todo-ai"

dev: ## Symlink local dev copy into Neovim packages
	@ln -sfn $(CURDIR) ~/.local/share/nvim/site/pack/plugins/start/todo-ai
	@echo "Symlinked $(CURDIR) → ~/.local/share/nvim/site/pack/plugins/start/todo-ai"

# --- Lint ---

lint: ## Find dead code and other issues
	@echo "Checking for dead Lua functions..."
	@bash scripts/find_dead_code.sh

# --- Clean ---

clean: ## Remove build artifacts
	@rm -f /tmp/todo-ai-*.sock /tmp/todo-ai.log

# --- Help ---

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
