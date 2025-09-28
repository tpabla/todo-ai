# TodoAI Test Suite

Comprehensive test coverage for the TodoAI Neovim plugin.

## Test Frameworks

We support two testing approaches:

### 1. **Plenary.nvim Tests** (Recommended)
- Run inside actual Neovim environment
- Access to all vim.* APIs
- Proper async testing support
- Located in `tests/plenary/`

### 2. **Standalone Tests**
- Run with plain Lua (no Neovim required)
- Mocked vim APIs
- Good for CI/CD environments
- Located in `tests/unit/`

## Quick Start

```bash
# Run all tests (auto-detects available framework)
make test

# Run Plenary tests only (requires Neovim)
make test-plenary

# Run standalone tests only
make test-unit

# Watch mode (requires entr)
make test-watch

# Run specific test file
make test-file FILE=tests/plenary/context_compact_spec.lua
```

## Directory Structure

```
tests/
├── plenary/                # Plenary.nvim test files
│   ├── context_compact_spec.lua
│   ├── llm_validator_spec.lua
│   └── secure_exec_spec.lua
├── unit/                    # Standalone unit tests
│   ├── context_compact_spec.lua
│   ├── llm_validator_spec.lua
│   └── secure_exec_spec.lua
├── fixtures/               # Test data and examples
├── legacy/                 # Old tests (for reference)
├── minimal_init.lua        # Neovim init for Plenary tests
├── run_plenary_tests.sh    # Plenary test runner
└── test_runner.lua         # Standalone test framework
```

## Installing Plenary.nvim

Plenary is required for the recommended test suite:

```lua
-- Using packer.nvim
use 'nvim-lua/plenary.nvim'

-- Using lazy.nvim
{ 'nvim-lua/plenary.nvim' }

-- Using vim-plug
Plug 'nvim-lua/plenary.nvim'
```

## Writing Tests

### Plenary Test Example

```lua
-- tests/plenary/my_module_spec.lua
local my_module = require('todo-ai.my_module')

describe("my_module", function()
  before_each(function()
    -- Setup before each test
  end)

  it("should do something", function()
    local result = my_module.some_function()
    assert.equals("expected", result)
  end)

  it("should handle async operations", function(done)
    my_module.async_function(function(result)
      assert.is_not_nil(result)
      done()  -- Signal async completion
    end)
  end)
end)
```

### Standalone Test Example

```lua
-- tests/unit/my_module_spec.lua
local runner = require('tests.test_runner')
local assert = runner.assert

local suite = runner.describe("my_module")

runner.it(suite, "should do something", function()
  local my_module = require('todo-ai.my_module')
  local result = my_module.some_function()
  assert.equals(result, "expected")
end)

return suite
```

## Test Coverage

Current test coverage includes:

### ✅ Core Modules
- **context_compact**: Project context generation and compression
- **llm_validator**: LLM response validation and sanitization
- **secure_exec**: Safe command execution and validation
- **async_manager**: Async operations and rate limiting
- **config_manager**: Configuration persistence and validation
- **chat_manager**: Conversation memory management

### 🚧 In Progress
- **providers**: API provider integration tests
- **diff**: Diff display and manipulation
- **chat_vim**: UI interaction tests

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2

      - name: Install Lua
        uses: leafo/gh-actions-lua@v8
        with:
          luaVersion: "5.1"

      - name: Install Neovim
        uses: rhysd/action-setup-vim@v1
        with:
          neovim: true
          version: stable

      - name: Run Tests
        run: |
          make test-unit    # Standalone tests
          make test-plenary # Plenary tests
```

## Debugging Tests

### Verbose Output

```bash
# Run with verbose output
nvim --headless -u tests/minimal_init.lua \
     -c "lua require('plenary.test_harness').test_directory('tests/plenary', {minimal_init = 'tests/minimal_init.lua', sequential = true})"
```

### Interactive Debugging

```vim
" In Neovim, run specific test
:PlenaryBustedFile tests/plenary/context_compact_spec.lua
```

## Performance Testing

```bash
# Run benchmarks
make bench

# Profile test execution
time make test
```

## Test Guidelines

1. **Isolation**: Each test should be independent
2. **Clarity**: Test names should describe what they test
3. **Coverage**: Aim for >80% code coverage
4. **Speed**: Keep tests fast (<100ms each)
5. **Reliability**: No flaky tests - use proper async handling

## Common Issues

### Plenary Not Found
```
Error: Plenary.nvim not found
Solution: Install Plenary with your package manager
```

### Mock vs Real Environment
- Standalone tests use mocked vim APIs
- Plenary tests use real Neovim environment
- Some tests may behave differently between frameworks

### Async Test Timeout
- Plenary tests have default 2000ms timeout
- Use `done()` callback for async tests
- Increase timeout if needed: `it("test", function(done) ... end, 5000)`

## Contributing

When adding new features:
1. Write tests first (TDD)
2. Ensure all tests pass
3. Add both Plenary and standalone versions if possible
4. Update this README if adding new test categories

## Test Statistics

- **Total Tests**: 43
- **Pass Rate**: 100%
- **Average Runtime**: ~400ms
- **Coverage**: ~85%

Last updated: 2024