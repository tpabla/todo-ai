.PHONY: build build-debug build-release test test-lua test-rust test-single \
       test-watch clean clean-nvim check install dev lint help

# --- Build ---

build: build-release ## Build release binary (default)

build-release: ## Build optimized Rust backend
	cd rust && cargo build --release

build-debug: ## Build debug Rust backend (faster compile)
	cd rust && cargo build

# --- Test ---

test: test-lua test-rust ## Run all tests

test-lua: ## Run Lua/Neovim tests
	@echo "Running Lua tests..."
	@timeout 120 nvim --headless -u tests/minimal_init.lua \
		-c 'lua require("plenary.test_harness").test_directory("tests/plenary/", {minimal_init="tests/minimal_init.lua", sequential=true})'
	@pkill -f 'nvim --headless' 2>/dev/null || true

test-rust: ## Run Rust tests
	cd rust && cargo test

test-single: ## Run single test file (FILE=tests/plenary/xxx_spec.lua)
	@test -z "$(FILE)" && echo "Usage: make test-single FILE=tests/plenary/xxx_spec.lua" && exit 1 || true
	@echo "Running: $(FILE)"
	@timeout 10 nvim --headless -u tests/minimal_init.lua \
		-c "PlenaryBustedFile $(FILE)" -c "qa!" || \
		(pkill -f 'nvim --headless'; exit 1)

test-watch: ## Watch for changes and re-run Lua tests
	@which fswatch > /dev/null || (echo "Install fswatch: brew install fswatch" && exit 1)
	@while true; do \
		clear; \
		make test-lua; \
		echo ""; \
		echo "Watching for changes (Ctrl+C to stop)..."; \
		fswatch -1 -r lua/ tests/ 2>/dev/null; \
	done

# --- Install ---

install: build-release ## Build and install to Neovim packages dir
	@mkdir -p ~/.local/share/nvim/site/pack/plugins/start/todo-ai
	@rsync -a --delete \
		--exclude rust/target \
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
	cd rust && cargo clean
	@rm -f /tmp/todo-ai-*.sock

clean-nvim: ## Kill hanging headless nvim processes
	@pkill -f 'nvim --headless' 2>/dev/null || echo "No hanging processes"

# --- Help ---

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
