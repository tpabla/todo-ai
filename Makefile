.PHONY: test test-lua test-rust test-watch test-single clean-nvim check-nvim build build-rust build-rust-release clean-rust clean

# Build Rust backend (debug)
build-rust:
	@echo "Building Rust backend (debug)..."
	@cd rust && cargo build
	@echo "Built: rust/target/debug/todo-ai-core"

# Build Rust backend (release - optimized)
build-rust-release:
	@echo "Building Rust backend (release)..."
	@cd rust && cargo build --release
	@echo "Built: rust/target/release/todo-ai-core"

# Build everything (release)
build: build-rust-release

# Run Rust tests
test-rust:
	@echo "Running Rust tests..."
	@cd rust && cargo test

# Run Lua tests
test-lua:
	@echo "Running Lua tests with cleanup..."
	@lua tests/run_tests.lua

# Run all tests (Rust + Lua)
test: test-rust test-lua

# Watch for changes and run tests
test-watch:
	@which fswatch > /dev/null || (echo "Install fswatch: brew install fswatch" && exit 1)
	@while true; do \
		clear; \
		make test; \
		echo ""; \
		echo "Watching for changes (Ctrl+C to stop)..."; \
		fswatch -1 -r lua/ tests/ rust/src/ 2>/dev/null; \
	done

# Run a single test file
test-single:
	@test -z "$(FILE)" && echo "Usage: make test-single FILE=tests/plenary/xxx_spec.lua" && exit 1 || true
	@echo "Running single test: $(FILE)"
	@timeout 10 nvim --headless -u tests/minimal_init.lua \
		-c "PlenaryBustedFile $(FILE)" -c "qa!" || \
		(pkill -f 'nvim --headless'; exit 1)

# Clean up any hanging nvim processes
clean-nvim:
	@echo "Cleaning up hanging nvim processes..."
	@pkill -f 'nvim --headless' 2>/dev/null || echo "No hanging processes found"
	@ps aux | grep -v grep | grep 'nvim --headless' || echo "All clean!"

# Check for hanging nvim processes
check-nvim:
	@echo "Checking for nvim headless processes..."
	@ps aux | grep -v grep | grep 'nvim --headless' || echo "No nvim headless processes running"

# Clean Rust build artifacts
clean-rust:
	@echo "Cleaning Rust build..."
	@cd rust && cargo clean

# Clean everything
clean: clean-rust clean-nvim
