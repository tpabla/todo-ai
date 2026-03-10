.PHONY: test test-single lint dev install clean help

test: ## Run tests
	@nvim --headless -u tests/minimal_init.lua \
		-c 'PlenaryBustedDirectory tests/plenary/ {minimal_init="tests/minimal_init.lua", sequential=true}'

test-single: ## Run one test (FILE=tests/plenary/xxx_spec.lua)
	@nvim --headless -u tests/minimal_init.lua \
		-c "PlenaryBustedFile $(FILE)"

lint: ## Find dead Lua code
	@bash scripts/find_dead_code.sh

dev: ## Symlink into Neovim packages for development
	@ln -sfn $(CURDIR) ~/.local/share/nvim/site/pack/plugins/start/todo-ai
	@echo "Symlinked → ~/.local/share/nvim/site/pack/plugins/start/todo-ai"

install: ## Install to Neovim packages directory
	@mkdir -p ~/.local/share/nvim/site/pack/plugins/start/todo-ai
	@rsync -a --delete --exclude .git . ~/.local/share/nvim/site/pack/plugins/start/todo-ai/
	@echo "Installed"

clean: ## Remove temp files
	@rm -f /tmp/todo-ai-prompt.md /tmp/todo-ai.log

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
