.PHONY: test test-watch test-single clean-nvim check-nvim build-rust test-rust

# Run all tests with cleanup
test:
	@echo "Running tests..."
	@timeout 120 nvim --headless -u tests/minimal_init.lua \
		-c 'lua require("plenary.test_harness").test_directory("tests/plenary/", {minimal_init="tests/minimal_init.lua", sequential=true})'
	@pkill -f 'nvim --headless' 2>/dev/null || true

# Watch for changes and run tests
test-watch:
	@which fswatch > /dev/null || (echo "Install fswatch: brew install fswatch" && exit 1)
	@while true; do \
		clear; \
		make test; \
		echo ""; \
		echo "Watching for changes (Ctrl+C to stop)..."; \
		fswatch -1 -r lua/ tests/ 2>/dev/null; \
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

# Build Rust backend
build-rust:
	cd rust && cargo build --release

# Run Rust tests
test-rust:
	cd rust && cargo test
