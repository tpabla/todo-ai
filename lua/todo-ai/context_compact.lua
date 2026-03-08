-- Compact project context generator with compression
local M = {}

local logger = require('todo-ai.logger')

M.context_file = '.todoai/context.md'
M.cache = nil
M.cache_time = 0
M.cache_ttl = 300  -- 5 minutes

-- Generate concise project snapshot
function M.generate_compact()
  local ctx = {}
  local cwd = vim.fn.getcwd()

  -- Project basics (1 line each)
  local project = vim.fn.fnamemodify(cwd, ':t')
  local branch = vim.fn.system("git branch --show-current 2>/dev/null"):gsub('\n', '')

  table.insert(ctx, string.format("Project: %s | Branch: %s", project, branch ~= '' and branch or 'none'))

  -- Tech stack detection (compact)
  local stack = {}
  local stack_files = {
    ['package.json'] = 'Node',
    ['Cargo.toml'] = 'Rust',
    ['go.mod'] = 'Go',
    ['requirements.txt'] = 'Python',
    ['Gemfile'] = 'Ruby',
    ['pom.xml'] = 'Java/Maven',
    ['build.gradle'] = 'Java/Gradle',
    ['composer.json'] = 'PHP',
    ['mix.exs'] = 'Elixir',
  }

  for file, tech in pairs(stack_files) do
    if vim.fn.filereadable(file) == 1 then
      table.insert(stack, tech)
    end
  end

  -- Language detection by extensions
  local langs = {}
  local lang_cmds = {
    lua = "find . -name '*.lua' 2>/dev/null | wc -l",
    python = "find . -name '*.py' 2>/dev/null | wc -l",
    javascript = "find . -name '*.js' 2>/dev/null | wc -l",
    typescript = "find . -name '*.ts' 2>/dev/null | wc -l",
    go = "find . -name '*.go' 2>/dev/null | wc -l",
    rust = "find . -name '*.rs' 2>/dev/null | wc -l",
  }

  for lang, cmd in pairs(lang_cmds) do
    local ok, output = pcall(vim.fn.system, cmd)
    if ok and output then
      -- Clean the output: remove whitespace and keep only digits
      local count_str = output:match('%d+')
      if count_str then
        local count = tonumber(count_str)
        if count and count > 0 then
          table.insert(langs, lang .. ':' .. count)
        end
      end
    end
  end

  if #stack > 0 or #langs > 0 then
    table.insert(ctx, string.format("Stack: %s | Files: %s",
      table.concat(stack, ','),
      table.concat(langs, ',')))
  end

  -- Key directories (compact listing)
  local dirs = {}
  local check_dirs = {'src', 'lib', 'test', 'tests', 'spec', 'docs', 'api', 'pkg', 'cmd', 'internal'}
  for _, dir in ipairs(check_dirs) do
    if vim.fn.isdirectory(dir) == 1 then
      table.insert(dirs, dir)
    end
  end
  if #dirs > 0 then
    table.insert(ctx, "Dirs: " .. table.concat(dirs, ', '))
  end

  -- Key config files (just list names)
  local configs = {}
  local config_patterns = {
    '*.config.{js,json,ts}',
    '.env*',
    'Makefile',
    'Dockerfile',
    'docker-compose.yml',
    '.github/workflows/*',
  }

  for _, pattern in ipairs(config_patterns) do
    local files = vim.fn.glob(pattern, false, true)
    for _, file in ipairs(files) do
      local name = vim.fn.fnamemodify(file, ':t')
      if not vim.tbl_contains(configs, name) then
        table.insert(configs, name)
      end
    end
  end

  if #configs > 0 then
    table.insert(ctx, "Config: " .. table.concat(vim.list_slice(configs, 1, 5), ', ') ..
                    (#configs > 5 and '...' or ''))
  end

  -- Testing framework
  local test_info = {}
  if vim.fn.glob("**/*.test.{js,ts}", false, true)[1] then
    table.insert(test_info, "Jest/Mocha")
  end
  if vim.fn.glob("**/test_*.py", false, true)[1] then
    table.insert(test_info, "pytest")
  end
  if vim.fn.glob("**/*_test.go", false, true)[1] then
    table.insert(test_info, "go-test")
  end
  if vim.fn.glob("**/*_spec.rb", false, true)[1] then
    table.insert(test_info, "RSpec")
  end

  if #test_info > 0 then
    table.insert(ctx, "Tests: " .. table.concat(test_info, ','))
  end

  -- Package manager detection
  local pkg_mgr = {}
  if vim.fn.filereadable("package-lock.json") == 1 then
    table.insert(pkg_mgr, "npm")
  end
  if vim.fn.filereadable("yarn.lock") == 1 then
    table.insert(pkg_mgr, "yarn")
  end
  if vim.fn.filereadable("pnpm-lock.yaml") == 1 then
    table.insert(pkg_mgr, "pnpm")
  end
  if vim.fn.filereadable("Pipfile.lock") == 1 then
    table.insert(pkg_mgr, "pipenv")
  end
  if vim.fn.filereadable("poetry.lock") == 1 then
    table.insert(pkg_mgr, "poetry")
  end

  if #pkg_mgr > 0 then
    table.insert(ctx, "PkgMgr: " .. table.concat(pkg_mgr, ','))
  end

  -- Key patterns/conventions (detect from sample)
  local patterns = M.detect_patterns()
  if patterns then
    table.insert(ctx, "Style: " .. patterns)
  end

  -- Recent files modified (for context awareness)
  local recent = vim.fn.system("git diff --name-only HEAD~1 2>/dev/null | head -5"):gsub('\n', ' ')
  if recent ~= '' then
    table.insert(ctx, "Recent: " .. recent)
  end

  -- Dependencies summary (super compact)
  local dep_summary = M.get_dependency_summary()
  if dep_summary then
    table.insert(ctx, "Deps: " .. dep_summary)
  end

  return table.concat(ctx, '\n')
end

-- Detect code patterns quickly
function M.detect_patterns()
  local patterns = {}

  -- Check for common patterns in first few files
  local sample_files = vim.fn.glob('**/*.{js,ts,py,lua,go,rs}', false, true)
  if #sample_files > 0 then
    local file = sample_files[1]
    local lines = vim.fn.readfile(file, '', 20)

    -- Quick pattern detection
    local has_classes = false
    local has_functions = false
    local style = nil

    for _, line in ipairs(lines) do
      if line:match('class%s+%w+') then has_classes = true end
      if line:match('function%s+%w+') or line:match('def%s+%w+') then has_functions = true end
      if not style then
        if line:match('function%s+[a-z][a-zA-Z]') then style = 'camelCase'
        elseif line:match('function%s+[a-z]+_[a-z]') then style = 'snake_case'
        elseif line:match('function%s+[A-Z]') then style = 'PascalCase'
        end
      end
    end

    if has_classes then table.insert(patterns, 'OOP') end
    if has_functions then table.insert(patterns, 'FP') end
    if style then table.insert(patterns, style) end
  end

  return #patterns > 0 and table.concat(patterns, ',') or nil
end

-- Get compact dependency summary
function M.get_dependency_summary()
  local deps = {}

  -- Node dependencies
  if vim.fn.filereadable("package.json") == 1 then
    local content = vim.fn.readfile and vim.fn.readfile("package.json")
    if content and type(content) == 'table' then
      local ok, pkg = pcall(vim.fn.json_decode, table.concat(content, '\n'))
      if ok and pkg then
        local count = 0
        if pkg.dependencies then
          for _ in pairs(pkg.dependencies) do count = count + 1 end
        end
        if count > 0 then
          table.insert(deps, 'npm:' .. count)
        end
      end
    end
  end

  -- Python requirements
  if vim.fn.filereadable("requirements.txt") == 1 then
    local lines = vim.fn.readfile and vim.fn.readfile("requirements.txt") or {}
    local count = 0
    for _, line in ipairs(lines) do
      if line ~= '' and not line:match('^#') then
        count = count + 1
      end
    end
    if count > 0 then
      table.insert(deps, 'py:' .. count)
    end
  end

  return #deps > 0 and table.concat(deps, ',') or nil
end

-- Generate full context with human section
-- Scan project for tagged reusable functions and patterns
function M.scan_for_functions()
  local hints = {}
  local cwd = vim.fn.getcwd()

  -- Define reusable function tags with their meanings
  local reuse_tags = {
    ["# DRY:"] = "Reusable function",
    ["# UTIL:"] = "Utility function",
    ["# HELPER:"] = "Helper function",
    ["# PATTERN:"] = "Reusable pattern",
    ["# COMMON:"] = "Common functionality",
    ["# SHARED:"] = "Shared component"
  }

  -- Find source files and scan for tagged functions
  local source_patterns = {
    "*.py", "*.js", "*.ts", "*.lua", "*.go", "*.rs", "*.java", "*.cpp", "*.c", "*.rb", "*.php", "*.swift"
  }

  local tagged_functions = {}
  local regular_functions = {}

  for _, pattern in ipairs(source_patterns) do
    local cmd = string.format("find %s -name '%s' -type f 2>/dev/null | head -20", cwd, pattern)
    local files = vim.fn.systemlist(cmd)

    for _, file in ipairs(files) do
      if vim.fn.filereadable(file) == 1 then
        local content = vim.fn.readfile(file)
        local filename = vim.fn.fnamemodify(file, ':t')
        local rel_path = vim.fn.fnamemodify(file, ':.')

        for i, line in ipairs(content) do
          -- Check for reusability tags first
          local tag_found = false
          for tag, description in pairs(reuse_tags) do
            if line:match(vim.pesc(tag)) then
              local tag_content = line:match(vim.pesc(tag) .. "%s*(.*)")
              -- Look for function definition in next few lines
              for j = i + 1, math.min(i + 3, #content) do
                local func_name = M.extract_function_name(content[j])
                if func_name then
                  table.insert(tagged_functions, {
                    name = func_name,
                    file = rel_path,
                    line = j,
                    tag = tag,
                    description = tag_content or description,
                    priority = 1 -- Tagged functions get priority
                  })
                  tag_found = true
                  break
                end
              end
              break
            end
          end

          -- If no tag found, check if this line has a function
          if not tag_found then
            local func_name = M.extract_function_name(line)
            if func_name and not func_name:match("^_") and #regular_functions < 5 then
              table.insert(regular_functions, {
                name = func_name,
                file = filename,
                line = i,
                priority = 2 -- Lower priority for untagged
              })
            end
          end
        end
      end
    end
  end

  -- Generate hints - prioritize tagged functions
  if #tagged_functions > 0 then
    table.insert(hints, "### Tagged for Reuse")
    for _, func in ipairs(tagged_functions) do
      table.insert(hints, string.format("- `%s()` - %s (%s:%d)",
        func.name, func.description, func.file, func.line))
    end
    table.insert(hints, "")
  end

  if #regular_functions > 0 and #tagged_functions < 5 then
    table.insert(hints, "### Other Functions")
    for _, func in ipairs(regular_functions) do
      table.insert(hints, string.format("- `%s()` in %s:%d",
        func.name, func.file, func.line))
    end
    table.insert(hints, "")
  end

  return hints
end

-- Extract function name from a line (language-agnostic)
function M.extract_function_name(line)
  -- Python: def function_name(
  local func_name = line:match("def%s+([%w_]+)%s*%(")

  -- JavaScript/TypeScript: function name( or name = function( or name: function(
  if not func_name then
    func_name = line:match("function%s+([%w_]+)%s*%(") or
               line:match("([%w_]+)%s*=%s*function%s*%(") or
               line:match("([%w_]+)%s*:%s*function%s*%(") or
               line:match("([%w_]+)%s*=%s*%([^)]*%)%s*=>") -- Arrow functions
  end

  -- Go: func name(
  if not func_name then
    func_name = line:match("func%s+([%w_]+)%s*%(")
  end

  -- Lua: function name( or M.name = function(
  if not func_name then
    func_name = line:match("function%s+([%w_.]+)%s*%(") or
               line:match("([%w_.]+)%s*=%s*function%s*%(")
  end

  -- Rust: fn name(
  if not func_name then
    func_name = line:match("fn%s+([%w_]+)%s*%(")
  end

  -- C/C++/Java: type name( (basic pattern)
  if not func_name then
    func_name = line:match("%w+%s+([%w_]+)%s*%(")
  end

  -- PHP: function name(
  if not func_name then
    func_name = line:match("function%s+([%w_]+)%s*%(")
  end

  return func_name
end

-- Scan project for common coding patterns
function M.scan_for_patterns()
  local patterns = {}
  local files = vim.fn.glob("**/*.lua", false, true)

  local pattern_counts = {}

  for _, file in ipairs(files) do
    if vim.fn.filereadable(file) == 1 then
      local lines = vim.fn.readfile(file)
      for _, line in ipairs(lines) do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")

        -- Common patterns to look for
        local common_patterns = {
          "local ok, .* = pcall%(.*%)",  -- pcall pattern
          "if not .* then",              -- error checking
          "vim%.api%.nvim_.*",           -- nvim API calls
          "require%(.*%)",               -- module loading
          "local .* = require%(.*%)",    -- require assignment
          "function .*%(.*%)",           -- function definitions
        }

        for _, pattern_regex in ipairs(common_patterns) do
          if line:match(pattern_regex) then
            local clean_line = line:gsub("%s+", " ")
            pattern_counts[clean_line] = (pattern_counts[clean_line] or 0) + 1
          end
        end
      end
    end
  end

  -- Sort by frequency and take top patterns
  local sorted_patterns = {}
  for pattern, count in pairs(pattern_counts) do
    if count >= 2 then  -- Pattern appears at least twice
      table.insert(sorted_patterns, {pattern = pattern, count = count})
    end
  end

  table.sort(sorted_patterns, function(a, b) return a.count > b.count end)

  -- Take top 5 patterns
  for i = 1, math.min(5, #sorted_patterns) do
    table.insert(patterns, "-- " .. sorted_patterns[i].pattern)
  end

  return patterns
end

-- Get DRY (Don't Repeat Yourself) hints - reusable functions
function M.get_dry_hints()
  local hints = {}

  -- Scan current project for reusable functions
  table.insert(hints, "## REUSABLE FUNCTIONS (DRY)")
  table.insert(hints, "")

  local function_hints = M.scan_for_functions()
  if #function_hints > 0 then
    for _, hint in ipairs(function_hints) do
      table.insert(hints, hint)
    end
  else
    table.insert(hints, "*No significant reusable functions detected in current project*")
  end
  table.insert(hints, "")

  -- Add common patterns found in this project
  local patterns = M.scan_for_patterns()
  if #patterns > 0 then
    table.insert(hints, "### Common Patterns to Reuse")
    table.insert(hints, "```lua")
    for _, pattern in ipairs(patterns) do
      table.insert(hints, pattern)
    end
    table.insert(hints, "```")
  end

  return table.concat(hints, '\n')
end

function M.generate_full()
  local lines = {}

  -- Header
  table.insert(lines, "# Project Context")
  table.insert(lines, "")

  -- Human notes section FIRST (protected)
  table.insert(lines, "## Human Notes (Protected)")
  table.insert(lines, "<!-- BEGIN_HUMAN_SECTION -->")

  -- Check if existing file has human notes
  local existing_human = M.load_human_section()
  if existing_human then
    table.insert(lines, existing_human)
  else
    table.insert(lines, "<!-- Add your project-specific notes here -->")
    table.insert(lines, "<!-- This section will NOT be auto-edited -->")
    table.insert(lines, "")
    table.insert(lines, "### Architecture Notes")
    table.insert(lines, "")
    table.insert(lines, "### Business Logic")
    table.insert(lines, "")
    table.insert(lines, "### Important Conventions")
    table.insert(lines, "")
    table.insert(lines, "### Critical Dependencies")
    table.insert(lines, "")
  end

  table.insert(lines, "<!-- END_HUMAN_SECTION -->")
  table.insert(lines, "")

  -- Compact auto-generated section
  table.insert(lines, "## Auto-Generated (Compact)")
  table.insert(lines, "```")
  table.insert(lines, M.generate_compact())
  table.insert(lines, "```")
  table.insert(lines, "")

  -- DRY hints for code reuse
  table.insert(lines, M.get_dry_hints())
  table.insert(lines, "")
  table.insert(lines, "*Updated: " .. os.date("%Y-%m-%d %H:%M") .. "*")

  return table.concat(lines, '\n')
end

-- Load existing human section
function M.load_human_section()
  local path = vim.fn.getcwd() .. '/' .. M.context_file
  if vim.fn.filereadable(path) == 1 then
    local content = vim.fn.readfile(path)
    local in_human = false
    local human_lines = {}

    for _, line in ipairs(content) do
      if line:match('<!-- BEGIN_HUMAN_SECTION -->') then
        in_human = true
      elseif line:match('<!-- END_HUMAN_SECTION -->') then
        in_human = false
      elseif in_human then
        table.insert(human_lines, line)
      end
    end

    if #human_lines > 0 then
      return table.concat(human_lines, '\n')
    end
  end
  return nil
end

-- Encode context for LLM transport
function M.encode_for_llm(context)
  -- Remove comments and excessive whitespace
  context = context:gsub('<!%-%-.-%-%->', '')
  context = context:gsub('\n\n+', '\n')
  context = context:gsub('^%s+', '')
  context = context:gsub('%s+$', '')

  -- Further compress by removing markdown formatting for transport
  local compressed = context:gsub('#+ ', '')
                          :gsub('```\n?', '')
                          :gsub('%*', '')
                          :gsub('%-%-+', '')

  -- Limit size
  if #compressed > 2000 then
    compressed = compressed:sub(1, 2000) .. "..."
  end

  return compressed
end

-- Get context for prompt (cached and compressed)
function M.get_for_prompt()
  local now = os.time()

  -- Check cache
  if M.cache and (now - M.cache_time) < M.cache_ttl then
    return M.cache
  end

  -- Load or generate
  local path = vim.fn.getcwd() .. '/' .. M.context_file
  local context

  if vim.fn.filereadable(path) == 1 then
    -- Load existing
    local content = vim.fn.readfile(path)
    context = table.concat(content, '\n')
  else
    -- Generate minimal
    context = M.generate_compact()
  end

  -- Encode and cache
  M.cache = M.encode_for_llm(context)
  M.cache_time = now

  return M.cache
end

-- Save context
function M.save()
  local path = vim.fn.getcwd() .. '/' .. M.context_file
  local dir = vim.fn.fnamemodify(path, ':h')

  -- Create directory
  vim.fn.mkdir(dir, 'p')

  -- Generate and save
  local content = M.generate_full()
  local file = io.open(path, 'w')
  if file then
    file:write(content)
    file:close()
    logger.info("Context saved: " .. path)
    return true
  end

  logger.error("Failed to save context")
  return false
end

-- Generate and open
function M.generate_and_open()
  if M.save() then
    vim.notify("Context generated at .todoai/context.md", vim.log.levels.INFO)
    vim.cmd('split ' .. M.context_file)
    vim.bo.filetype = 'markdown'
  else
    vim.notify("Failed to generate context", vim.log.levels.ERROR)
  end
end

-- Auto-update specific info
---Parse human notes from context
---@param content string
---@return string|nil
function M.parse_human_notes(content)
  if not content then return nil end

  -- Find HUMAN NOTES section
  local start_pattern = "## HUMAN NOTES"
  local end_pattern = "## PROJECT CONTEXT"

  local start_pos = content:find(start_pattern)
  if not start_pos then return nil end

  local end_pos = content:find(end_pattern, start_pos)
  if not end_pos then
    -- If no end marker, take everything after start
    return content:sub(start_pos + #start_pattern):gsub("^%s*", "")
  end

  -- Extract content between markers
  local notes = content:sub(start_pos + #start_pattern, end_pos - 1)
  return notes:gsub("^%s*", ""):gsub("%s*$", "")
end

---Load existing context
---@return string|nil
function M.load()
  local path = vim.fn.getcwd() .. '/.todoai/context.md'
  if vim.fn.filereadable(path) ~= 1 then
    return nil
  end

  local file = io.open(path, 'r')
  if not file then return nil end

  local content = file:read('*all')
  file:close()

  return content
end

return M