-- Project context generator and manager
local M = {}

local utils = require('todo-ai.utils')
local logger = require('todo-ai.logger')

-- Context file path
M.context_file = '.todoai/context.md'
M.context_cache = nil
M.last_update = 0

-- Context template sections
M.sections = {
  {
    name = "Project Overview",
    key = "overview",
    generator = "generate_overview"
  },
  {
    name = "Technology Stack",
    key = "stack",
    generator = "generate_stack"
  },
  {
    name = "Project Structure",
    key = "structure",
    generator = "generate_structure"
  },
  {
    name = "Code Patterns & Conventions",
    key = "patterns",
    generator = "generate_patterns"
  },
  {
    name = "Architecture",
    key = "architecture",
    generator = "generate_architecture"
  },
  {
    name = "Testing Strategy",
    key = "testing",
    generator = "generate_testing"
  },
  {
    name = "Build & Tooling",
    key = "tooling",
    generator = "generate_tooling"
  },
  {
    name = "Dependencies",
    key = "dependencies",
    generator = "generate_dependencies"
  },
  {
    name = "API & Interfaces",
    key = "api",
    generator = "generate_api"
  },
  {
    name = "Configuration",
    key = "configuration",
    generator = "generate_configuration"
  },
  {
    name = "Development Workflow",
    key = "workflow",
    generator = "generate_workflow"
  },
  {
    name = "Performance Considerations",
    key = "performance",
    generator = "generate_performance"
  },
  {
    name = "Security Practices",
    key = "security",
    generator = "generate_security"
  },
  {
    name = "Documentation",
    key = "documentation",
    generator = "generate_documentation"
  },
  {
    name = "Known Issues & TODOs",
    key = "issues",
    generator = "generate_issues"
  }
}

-- Analyze project to generate overview
function M.generate_overview()
  local overview = {}

  -- Get project name from directory or git
  local project_name = vim.fn.fnamemodify(vim.fn.getcwd(), ':t')
  local git_remote = vim.fn.system('git remote get-url origin 2>/dev/null'):gsub('\n', '')

  table.insert(overview, string.format("**Project Name**: %s", project_name))

  if git_remote ~= '' then
    table.insert(overview, string.format("**Repository**: %s", git_remote))
  end

  -- Get project description from README or package.json
  local readme_files = {'README.md', 'README.rst', 'README.txt', 'readme.md'}
  for _, file in ipairs(readme_files) do
    if vim.fn.filereadable(file) == 1 then
      local lines = vim.fn.readfile(file, '', 5)
      for _, line in ipairs(lines) do
        if not line:match('^#') and line ~= '' then
          table.insert(overview, string.format("**Description**: %s", line))
          break
        end
      end
      break
    end
  end

  -- Count files and lines of code
  local file_count = vim.fn.system("find . -type f -name '*.lua' -o -name '*.py' -o -name '*.js' -o -name '*.ts' -o -name '*.go' -o -name '*.rs' 2>/dev/null | wc -l"):gsub('\n', '')
  local line_count = vim.fn.system("find . -type f \\( -name '*.lua' -o -name '*.py' -o -name '*.js' -o -name '*.ts' -o -name '*.go' -o -name '*.rs' \\) -exec wc -l {} + 2>/dev/null | tail -n 1 | awk '{print $1}'"):gsub('\n', '')

  table.insert(overview, string.format("**Files**: %s source files", file_count))
  table.insert(overview, string.format("**Lines of Code**: %s", line_count))

  return table.concat(overview, '\n')
end

-- Detect technology stack
function M.generate_stack()
  local stack = {}
  local detected = {}

  -- Language detection based on file extensions
  local languages = {}
  local lang_patterns = {
    {pattern = "%.lua$", lang = "Lua"},
    {pattern = "%.py$", lang = "Python"},
    {pattern = "%.js$", lang = "JavaScript"},
    {pattern = "%.ts$", lang = "TypeScript"},
    {pattern = "%.go$", lang = "Go"},
    {pattern = "%.rs$", lang = "Rust"},
    {pattern = "%.java$", lang = "Java"},
    {pattern = "%.cpp$", lang = "C++"},
    {pattern = "%.c$", lang = "C"},
    {pattern = "%.rb$", lang = "Ruby"},
    {pattern = "%.swift$", lang = "Swift"},
    {pattern = "%.kt$", lang = "Kotlin"},
  }

  for _, pattern_info in ipairs(lang_patterns) do
    local files = vim.fn.glob('**/*' .. pattern_info.pattern:sub(2), false, true)
    if #files > 0 then
      languages[pattern_info.lang] = #files
    end
  end

  table.insert(stack, "### Languages")
  for lang, count in pairs(languages) do
    table.insert(stack, string.format("- **%s**: %d files", lang, count))
  end

  -- Framework detection
  table.insert(stack, "\n### Frameworks & Libraries")

  -- Check for common framework files
  local framework_checks = {
    {file = "package.json", framework = "Node.js/npm", parser = M.parse_package_json},
    {file = "Cargo.toml", framework = "Rust/Cargo", parser = M.parse_cargo_toml},
    {file = "go.mod", framework = "Go Modules", parser = M.parse_go_mod},
    {file = "requirements.txt", framework = "Python/pip"},
    {file = "Gemfile", framework = "Ruby/Bundler"},
    {file = "composer.json", framework = "PHP/Composer"},
    {file = ".nvimrc", framework = "Neovim Plugin"},
    {file = "Makefile", framework = "Make"},
    {file = "docker-compose.yml", framework = "Docker Compose"},
    {file = "Dockerfile", framework = "Docker"},
  }

  for _, check in ipairs(framework_checks) do
    if vim.fn.filereadable(check.file) == 1 then
      table.insert(stack, string.format("- **%s**", check.framework))
      if check.parser then
        local details = check.parser(check.file)
        if details then
          table.insert(stack, details)
        end
      end
    end
  end

  return table.concat(stack, '\n')
end

-- Parse package.json for dependencies
function M.parse_package_json(file)
  local content = vim.fn.readfile(file)
  local json_str = table.concat(content, '\n')
  local ok, package = pcall(vim.fn.json_decode, json_str)

  if not ok then return nil end

  local details = {}
  if package.dependencies then
    table.insert(details, "  Dependencies: " .. vim.tbl_keys(package.dependencies)[1] .. ", ...")
  end
  if package.devDependencies then
    table.insert(details, "  Dev Dependencies: " .. vim.tbl_keys(package.devDependencies)[1] .. ", ...")
  end

  return table.concat(details, '\n')
end

-- Generate project structure
function M.generate_structure()
  local structure = {}

  -- Get directory tree (limited depth)
  local tree = vim.fn.system('tree -d -L 3 --gitignore 2>/dev/null || find . -type d -maxdepth 3 2>/dev/null | head -20')

  table.insert(structure, "```")
  table.insert(structure, tree)
  table.insert(structure, "```")

  -- Key directories
  table.insert(structure, "\n### Key Directories")

  local key_dirs = {
    {path = "src/", desc = "Source code"},
    {path = "lib/", desc = "Library code"},
    {path = "test/", desc = "Test files"},
    {path = "tests/", desc = "Test files"},
    {path = "spec/", desc = "Test specifications"},
    {path = "docs/", desc = "Documentation"},
    {path = "config/", desc = "Configuration files"},
    {path = "scripts/", desc = "Build/utility scripts"},
    {path = "examples/", desc = "Example code"},
    {path = ".github/", desc = "GitHub configuration"},
  }

  for _, dir in ipairs(key_dirs) do
    if vim.fn.isdirectory(dir.path) == 1 then
      table.insert(structure, string.format("- `%s` - %s", dir.path, dir.desc))
    end
  end

  return table.concat(structure, '\n')
end

-- Detect code patterns and conventions
function M.generate_patterns()
  local patterns = {}

  -- Analyze code style
  table.insert(patterns, "### Coding Style")

  -- Check for style config files
  local style_files = {
    {file = ".editorconfig", style = "EditorConfig"},
    {file = ".prettierrc", style = "Prettier"},
    {file = ".eslintrc", style = "ESLint"},
    {file = ".rubocop.yml", style = "RuboCop"},
    {file = ".rustfmt.toml", style = "rustfmt"},
    {file = "pyproject.toml", style = "Black/Python"},
    {file = ".clang-format", style = "clang-format"},
  }

  for _, config in ipairs(style_files) do
    if vim.fn.filereadable(config.file) == 1 then
      table.insert(patterns, string.format("- %s configuration found", config.style))
    end
  end

  -- Analyze naming conventions
  table.insert(patterns, "\n### Naming Conventions")

  -- Sample some files to detect patterns
  local sample_files = vim.fn.glob('**/*.{lua,py,js,ts,go,rs}', false, true)
  local naming_patterns = {
    camelCase = 0,
    PascalCase = 0,
    snake_case = 0,
    kebab_case = 0,
  }

  -- Simple heuristic analysis
  for i = 1, math.min(10, #sample_files) do
    local content = vim.fn.readfile(sample_files[i], '', 100)
    for _, line in ipairs(content) do
      if line:match('function%s+[a-z][a-zA-Z]') then
        naming_patterns.camelCase = naming_patterns.camelCase + 1
      end
      if line:match('function%s+[A-Z][a-zA-Z]') then
        naming_patterns.PascalCase = naming_patterns.PascalCase + 1
      end
      if line:match('function%s+[a-z]+_[a-z]') then
        naming_patterns.snake_case = naming_patterns.snake_case + 1
      end
    end
  end

  -- Report dominant pattern
  local dominant = "mixed"
  local max_count = 0
  for pattern, count in pairs(naming_patterns) do
    if count > max_count then
      dominant = pattern
      max_count = count
    end
  end

  table.insert(patterns, string.format("- Dominant naming style: %s", dominant))

  -- Design patterns
  table.insert(patterns, "\n### Common Patterns")
  table.insert(patterns, "- Modular structure with clear separation of concerns")
  table.insert(patterns, "- Error handling with proper validation")
  table.insert(patterns, "- Async/await or callback patterns for async operations")

  return table.concat(patterns, '\n')
end

-- Generate architecture information
function M.generate_architecture()
  local arch = {}

  table.insert(arch, "### Architecture Style")

  -- Detect architecture patterns
  if vim.fn.isdirectory("controllers/") == 1 or vim.fn.isdirectory("models/") == 1 then
    table.insert(arch, "- MVC (Model-View-Controller) pattern detected")
  end

  if vim.fn.isdirectory("src/components/") == 1 then
    table.insert(arch, "- Component-based architecture")
  end

  if vim.fn.isdirectory("services/") == 1 or vim.fn.isdirectory("domain/") == 1 then
    table.insert(arch, "- Service-oriented or Domain-driven design")
  end

  if vim.fn.filereadable("docker-compose.yml") == 1 then
    table.insert(arch, "- Microservices/containerized architecture")
  end

  -- API architecture
  table.insert(arch, "\n### API Design")

  if vim.fn.glob("**/*route*", false, true)[1] then
    table.insert(arch, "- RESTful API routes detected")
  end

  if vim.fn.glob("**/*graphql*", false, true)[1] then
    table.insert(arch, "- GraphQL API detected")
  end

  if vim.fn.glob("**/*grpc*", false, true)[1] then
    table.insert(arch, "- gRPC services detected")
  end

  return table.concat(arch, '\n')
end

-- Generate testing information
function M.generate_testing()
  local testing = {}

  table.insert(testing, "### Test Framework")

  -- Detect test frameworks
  local test_patterns = {
    {pattern = "**/test_*.py", framework = "Python unittest/pytest"},
    {pattern = "**/*_test.go", framework = "Go testing"},
    {pattern = "**/*.test.js", framework = "JavaScript testing (Jest/Mocha)"},
    {pattern = "**/*.spec.ts", framework = "TypeScript testing"},
    {pattern = "**/test/*.lua", framework = "Lua testing"},
    {pattern = "**/*_spec.rb", framework = "Ruby RSpec"},
  }

  for _, pattern in ipairs(test_patterns) do
    local files = vim.fn.glob(pattern.pattern, false, true)
    if #files > 0 then
      table.insert(testing, string.format("- %s (%d test files)", pattern.framework, #files))
    end
  end

  -- Test configuration files
  local test_configs = {
    {file = "jest.config.js", framework = "Jest"},
    {file = "karma.conf.js", framework = "Karma"},
    {file = "pytest.ini", framework = "pytest"},
    {file = ".rspec", framework = "RSpec"},
    {file = "phpunit.xml", framework = "PHPUnit"},
  }

  for _, config in ipairs(test_configs) do
    if vim.fn.filereadable(config.file) == 1 then
      table.insert(testing, string.format("- %s configuration found", config.framework))
    end
  end

  -- Coverage
  table.insert(testing, "\n### Test Coverage")

  if vim.fn.filereadable(".coverage") == 1 or vim.fn.isdirectory("coverage/") == 1 then
    table.insert(testing, "- Code coverage tracking enabled")
  end

  -- CI/CD
  table.insert(testing, "\n### Continuous Integration")

  local ci_files = {
    {file = ".github/workflows/", name = "GitHub Actions"},
    {file = ".gitlab-ci.yml", name = "GitLab CI"},
    {file = ".travis.yml", name = "Travis CI"},
    {file = "Jenkinsfile", name = "Jenkins"},
    {file = ".circleci/", name = "CircleCI"},
  }

  for _, ci in ipairs(ci_files) do
    if vim.fn.filereadable(ci.file) == 1 or vim.fn.isdirectory(ci.file) == 1 then
      table.insert(testing, string.format("- %s configured", ci.name))
    end
  end

  return table.concat(testing, '\n')
end

-- Generate tooling information
function M.generate_tooling()
  local tooling = {}

  table.insert(tooling, "### Build Tools")

  -- Build tools
  local build_tools = {
    {file = "Makefile", tool = "Make", docs = "https://www.gnu.org/software/make/manual/"},
    {file = "package.json", tool = "npm/yarn", docs = "https://docs.npmjs.com/"},
    {file = "Cargo.toml", tool = "Cargo", docs = "https://doc.rust-lang.org/cargo/"},
    {file = "go.mod", tool = "Go Modules", docs = "https://go.dev/ref/mod"},
    {file = "pom.xml", tool = "Maven", docs = "https://maven.apache.org/guides/"},
    {file = "build.gradle", tool = "Gradle", docs = "https://docs.gradle.org/"},
    {file = "CMakeLists.txt", tool = "CMake", docs = "https://cmake.org/documentation/"},
    {file = "setup.py", tool = "setuptools", docs = "https://setuptools.pypa.io/"},
  }

  for _, build in ipairs(build_tools) do
    if vim.fn.filereadable(build.file) == 1 then
      table.insert(tooling, string.format("- **%s** - [Documentation](%s)", build.tool, build.docs))
    end
  end

  -- Development tools
  table.insert(tooling, "\n### Development Tools")

  local dev_tools = {
    {file = ".eslintrc", tool = "ESLint", docs = "https://eslint.org/docs/"},
    {file = ".prettierrc", tool = "Prettier", docs = "https://prettier.io/docs/"},
    {file = "tslint.json", tool = "TSLint", docs = "https://palantir.github.io/tslint/"},
    {file = ".rubocop.yml", tool = "RuboCop", docs = "https://docs.rubocop.org/"},
    {file = ".flake8", tool = "Flake8", docs = "https://flake8.pycqa.org/"},
    {file = "rustfmt.toml", tool = "rustfmt", docs = "https://rust-lang.github.io/rustfmt/"},
  }

  for _, tool in ipairs(dev_tools) do
    if vim.fn.filereadable(tool.file) == 1 then
      table.insert(tooling, string.format("- **%s** - [Documentation](%s)", tool.tool, tool.docs))
    end
  end

  -- Package managers
  table.insert(tooling, "\n### Package Managers")

  if vim.fn.filereadable("package-lock.json") == 1 then
    table.insert(tooling, "- **npm** - Node Package Manager")
  end

  if vim.fn.filereadable("yarn.lock") == 1 then
    table.insert(tooling, "- **Yarn** - Fast, reliable JavaScript package manager")
  end

  if vim.fn.filereadable("Pipfile.lock") == 1 then
    table.insert(tooling, "- **Pipenv** - Python dependency management")
  end

  if vim.fn.filereadable("poetry.lock") == 1 then
    table.insert(tooling, "- **Poetry** - Python packaging and dependency management")
  end

  return table.concat(tooling, '\n')
end

-- Generate dependencies list
function M.generate_dependencies()
  local deps = {}

  -- Package.json dependencies
  if vim.fn.filereadable("package.json") == 1 then
    table.insert(deps, "### npm/Node.js Dependencies")
    local content = vim.fn.readfile("package.json")
    local ok, package = pcall(vim.fn.json_decode, table.concat(content, '\n'))

    if ok and package.dependencies then
      table.insert(deps, "\n**Production:**")
      for dep, version in pairs(package.dependencies) do
        table.insert(deps, string.format("- `%s`: %s", dep, version))
      end
    end

    if ok and package.devDependencies then
      table.insert(deps, "\n**Development:**")
      local count = 0
      for dep, version in pairs(package.devDependencies) do
        if count < 10 then
          table.insert(deps, string.format("- `%s`: %s", dep, version))
          count = count + 1
        end
      end
      if count >= 10 then
        table.insert(deps, "- ... and more")
      end
    end
  end

  -- Python requirements
  if vim.fn.filereadable("requirements.txt") == 1 then
    table.insert(deps, "\n### Python Dependencies")
    local reqs = vim.fn.readfile("requirements.txt", '', 10)
    for _, req in ipairs(reqs) do
      if req ~= '' and not req:match('^#') then
        table.insert(deps, string.format("- `%s`", req))
      end
    end
  end

  -- Go modules
  if vim.fn.filereadable("go.mod") == 1 then
    table.insert(deps, "\n### Go Modules")
    local content = vim.fn.readfile("go.mod", '', 20)
    for _, line in ipairs(content) do
      if line:match("^require") then
        table.insert(deps, "Dependencies listed in go.mod")
        break
      end
    end
  end

  return table.concat(deps, '\n')
end

-- Generate API documentation
function M.generate_api()
  local api = {}

  table.insert(api, "### API Endpoints")

  -- Look for route definitions
  local route_files = vim.fn.glob("**/routes/**/*.{js,ts,py,go,rb}", false, true)
  if #route_files > 0 then
    table.insert(api, string.format("- %d route files found", #route_files))
  end

  -- OpenAPI/Swagger
  if vim.fn.filereadable("swagger.json") == 1 or vim.fn.filereadable("openapi.yaml") == 1 then
    table.insert(api, "- OpenAPI/Swagger documentation available")
  end

  -- GraphQL schema
  if vim.fn.glob("**/*.graphql", false, true)[1] then
    table.insert(api, "- GraphQL schema defined")
  end

  table.insert(api, "\n### Public Interfaces")
  table.insert(api, "- Main entry points and public APIs should be documented here")

  return table.concat(api, '\n')
end

-- Generate configuration information
function M.generate_configuration()
  local config = {}

  table.insert(config, "### Configuration Files")

  -- Common config files
  local config_files = {
    {pattern = "*.config.{js,ts,json}", desc = "Application configuration"},
    {pattern = ".env*", desc = "Environment variables"},
    {pattern = "config/*.{yml,yaml,json}", desc = "Configuration directory"},
    {pattern = "settings.{py,ini,json}", desc = "Settings files"},
  }

  for _, cfg in ipairs(config_files) do
    local files = vim.fn.glob(cfg.pattern, false, true)
    if #files > 0 then
      table.insert(config, string.format("- %s: %d files", cfg.desc, #files))
    end
  end

  -- Environment variables
  if vim.fn.filereadable(".env.example") == 1 then
    table.insert(config, "\n### Environment Variables")
    table.insert(config, "- `.env.example` file provides template for environment configuration")
  end

  return table.concat(config, '\n')
end

-- Generate workflow information
function M.generate_workflow()
  local workflow = {}

  table.insert(workflow, "### Development Workflow")

  -- Git workflow
  if vim.fn.isdirectory(".git") == 1 then
    local branch = vim.fn.system("git branch --show-current 2>/dev/null"):gsub('\n', '')
    table.insert(workflow, string.format("- Current branch: `%s`", branch))

    -- Check for git flow
    if vim.fn.system("git branch -a 2>/dev/null | grep -q develop; echo $?"):gsub('\n', '') == '0' then
      table.insert(workflow, "- Git Flow workflow detected (main/develop branches)")
    end
  end

  -- Scripts
  table.insert(workflow, "\n### Available Scripts")

  if vim.fn.filereadable("package.json") == 1 then
    local content = vim.fn.readfile("package.json")
    local ok, package = pcall(vim.fn.json_decode, table.concat(content, '\n'))

    if ok and package.scripts then
      for script, cmd in pairs(package.scripts) do
        table.insert(workflow, string.format("- `npm run %s`: %s", script, cmd:sub(1, 50)))
      end
    end
  end

  if vim.fn.filereadable("Makefile") == 1 then
    local targets = vim.fn.system("make -qp 2>/dev/null | awk -F':' '/^[a-zA-Z0-9][^$#\\/\\t=]*:([^=]|$)/ {split($1,A,/ /);for(i in A)print A[i]}' | sort -u | head -10")
    if targets ~= '' then
      table.insert(workflow, "\n**Make targets:**")
      for target in targets:gmatch("[^\r\n]+") do
        table.insert(workflow, string.format("- `make %s`", target))
      end
    end
  end

  return table.concat(workflow, '\n')
end

-- Generate performance considerations
function M.generate_performance()
  local perf = {}

  table.insert(perf, "### Performance Optimizations")

  -- Check for caching
  if vim.fn.isdirectory(".cache/") == 1 or vim.fn.isdirectory("cache/") == 1 then
    table.insert(perf, "- Caching layer implemented")
  end

  -- Database indexes
  if vim.fn.glob("**/migrations/*.{sql,js,py}", false, true)[1] then
    table.insert(perf, "- Database migrations present (check for index definitions)")
  end

  -- Build optimizations
  if vim.fn.filereadable("webpack.config.js") == 1 then
    table.insert(perf, "- Webpack bundling configured")
  end

  if vim.fn.filereadable("tsconfig.json") == 1 then
    table.insert(perf, "- TypeScript compilation configured")
  end

  table.insert(perf, "\n### Monitoring")

  -- APM tools
  local apm_indicators = {
    {pattern = "*newrelic*", tool = "New Relic"},
    {pattern = "*datadog*", tool = "Datadog"},
    {pattern = "*sentry*", tool = "Sentry"},
    {pattern = "*prometheus*", tool = "Prometheus"},
  }

  for _, apm in ipairs(apm_indicators) do
    if vim.fn.glob(apm.pattern, false, true)[1] then
      table.insert(perf, string.format("- %s monitoring integrated", apm.tool))
    end
  end

  return table.concat(perf, '\n')
end

-- Generate security information
function M.generate_security()
  local security = {}

  table.insert(security, "### Security Measures")

  -- Security config files
  if vim.fn.filereadable(".snyk") == 1 then
    table.insert(security, "- Snyk security scanning configured")
  end

  if vim.fn.filereadable("security.txt") == 1 then
    table.insert(security, "- Security policy documented")
  end

  -- Authentication
  if vim.fn.glob("**/auth/**", false, true)[1] then
    table.insert(security, "- Authentication layer implemented")
  end

  -- HTTPS/TLS
  if vim.fn.glob("**/*.{crt,pem,key}", false, true)[1] then
    table.insert(security, "- TLS/SSL certificates present (ensure proper handling)")
  end

  table.insert(security, "\n### Security Best Practices")
  table.insert(security, "- Never commit sensitive data (API keys, passwords)")
  table.insert(security, "- Use environment variables for configuration")
  table.insert(security, "- Keep dependencies up to date")
  table.insert(security, "- Implement proper input validation")
  table.insert(security, "- Use prepared statements for database queries")

  return table.concat(security, '\n')
end

-- Generate documentation information
function M.generate_documentation()
  local docs = {}

  table.insert(docs, "### Documentation")

  -- Documentation files
  local doc_files = {
    {file = "README.md", desc = "Main documentation"},
    {file = "CONTRIBUTING.md", desc = "Contribution guidelines"},
    {file = "CHANGELOG.md", desc = "Change log"},
    {file = "LICENSE", desc = "License information"},
    {file = "CODE_OF_CONDUCT.md", desc = "Code of conduct"},
  }

  for _, doc in ipairs(doc_files) do
    if vim.fn.filereadable(doc.file) == 1 then
      table.insert(docs, string.format("- `%s`: %s", doc.file, doc.desc))
    end
  end

  -- Documentation directories
  if vim.fn.isdirectory("docs/") == 1 then
    local doc_count = vim.fn.system("find docs -name '*.md' 2>/dev/null | wc -l"):gsub('\n', '')
    table.insert(docs, string.format("- `docs/`: %s documentation files", doc_count))
  end

  -- API documentation
  if vim.fn.isdirectory("apidoc/") == 1 or vim.fn.isdirectory("api-docs/") == 1 then
    table.insert(docs, "- API documentation available")
  end

  -- Inline documentation
  table.insert(docs, "\n### Code Documentation")

  -- Check for documentation tools
  if vim.fn.filereadable("jsdoc.json") == 1 then
    table.insert(docs, "- JSDoc configured for JavaScript documentation")
  end

  if vim.fn.filereadable("Doxyfile") == 1 then
    table.insert(docs, "- Doxygen configured for documentation generation")
  end

  if vim.fn.glob("**/*.{md,rst}", false, true)[1] then
    table.insert(docs, "- Markdown/reStructuredText documentation present")
  end

  return table.concat(docs, '\n')
end

-- Generate known issues and TODOs
function M.generate_issues()
  local issues = {}

  table.insert(issues, "### Known Issues")

  -- Check for TODO comments
  local todo_count = vim.fn.system("grep -r 'TODO\\|FIXME\\|HACK\\|XXX' --include='*.lua' --include='*.py' --include='*.js' --include='*.ts' --include='*.go' --include='*.rs' 2>/dev/null | wc -l"):gsub('\n', '')

  if tonumber(todo_count) > 0 then
    table.insert(issues, string.format("- %s TODO/FIXME comments in codebase", todo_count))
  end

  -- GitHub issues
  if vim.fn.isdirectory(".github/") == 1 then
    table.insert(issues, "- Check GitHub Issues for tracked problems")
  end

  -- Issue tracking files
  if vim.fn.filereadable("TODO.md") == 1 then
    table.insert(issues, "- `TODO.md` file contains task list")
  end

  if vim.fn.filereadable("ISSUES.md") == 1 then
    table.insert(issues, "- `ISSUES.md` file contains known issues")
  end

  table.insert(issues, "\n### Areas for Improvement")
  table.insert(issues, "- Review and update this context regularly")
  table.insert(issues, "- Add specific technical debt items here")
  table.insert(issues, "- Document any performance bottlenecks")

  return table.concat(issues, '\n')
end

-- Generate complete context
function M.generate()
  logger.info("Generating project context...")

  local context = {}

  -- Header
  table.insert(context, "# Project Context")
  table.insert(context, "")
  table.insert(context, "*Generated: " .. os.date("%Y-%m-%d %H:%M:%S") .. "*")
  table.insert(context, "")
  table.insert(context, "---")
  table.insert(context, "")

  -- Generate each section
  for _, section in ipairs(M.sections) do
    vim.notify("Generating " .. section.name .. "...", vim.log.levels.INFO)

    table.insert(context, "## " .. section.name)
    table.insert(context, "")

    local generator = M[section.generator]
    if generator then
      local ok, content = pcall(generator)
      if ok then
        table.insert(context, content)
      else
        table.insert(context, "*Error generating this section: " .. tostring(content) .. "*")
      end
    else
      table.insert(context, "*Generator not implemented*")
    end

    table.insert(context, "")
    table.insert(context, "---")
    table.insert(context, "")
  end

  -- Custom notes section
  table.insert(context, "## Custom Notes")
  table.insert(context, "")
  table.insert(context, "<!-- Add your custom project notes here -->")
  table.insert(context, "")

  return table.concat(context, '\n')
end

-- Save context to file
function M.save_context(content)
  local project_root = vim.fn.getcwd()
  local context_path = project_root .. '/' .. M.context_file

  -- Create directory if needed
  local dir = vim.fn.fnamemodify(context_path, ':h')
  vim.fn.mkdir(dir, 'p')

  -- Write file
  local file = io.open(context_path, 'w')
  if file then
    file:write(content)
    file:close()
    logger.info("Context saved to: " .. context_path)
    return true
  else
    logger.error("Failed to save context to: " .. context_path)
    return false
  end
end

-- Load context from file
function M.load_context()
  -- Check cache first
  local now = os.time()
  if M.context_cache and (now - M.last_update) < 300 then -- 5 minute cache
    return M.context_cache
  end

  local project_root = vim.fn.getcwd()
  local context_path = project_root .. '/' .. M.context_file

  if vim.fn.filereadable(context_path) == 1 then
    local file = io.open(context_path, 'r')
    if file then
      local content = file:read('*all')
      file:close()

      M.context_cache = content
      M.last_update = now

      return content
    end
  end

  return nil
end

-- Update specific section
function M.update_section(section_key, new_content)
  local context = M.load_context() or M.generate()

  -- Find and replace section
  local section_name = nil
  for _, section in ipairs(M.sections) do
    if section.key == section_key then
      section_name = section.name
      break
    end
  end

  if not section_name then
    return false
  end

  -- Pattern to match section
  local pattern = "## " .. section_name .. "\n\n.-\n\n---"
  local replacement = string.format("## %s\n\n%s\n\n---", section_name, new_content)

  context = context:gsub(pattern, replacement)

  return M.save_context(context)
end

-- Generate and save context
function M.generate_and_save()
  local content = M.generate()

  if M.save_context(content) then
    vim.notify("Project context generated successfully", vim.log.levels.INFO)

    -- Open the file for review
    vim.cmd('split ' .. M.context_file)
    vim.cmd('setlocal ft=markdown')
  else
    vim.notify("Failed to save project context", vim.log.levels.ERROR)
  end
end

-- Auto-update context based on changes
function M.auto_update(change_type, details)
  -- Determine which sections need updating
  local sections_to_update = {}

  if change_type == 'dependencies' then
    table.insert(sections_to_update, 'dependencies')
    table.insert(sections_to_update, 'stack')
  elseif change_type == 'structure' then
    table.insert(sections_to_update, 'structure')
  elseif change_type == 'testing' then
    table.insert(sections_to_update, 'testing')
  elseif change_type == 'configuration' then
    table.insert(sections_to_update, 'configuration')
  end

  -- Update each section
  for _, section_key in ipairs(sections_to_update) do
    local generator = M['generate_' .. section_key]
    if generator then
      local ok, content = pcall(generator)
      if ok then
        M.update_section(section_key, content)
      end
    end
  end
end

-- Get context for AI prompts
function M.get_context_for_prompt()
  local context = M.load_context()

  if not context then
    -- Generate minimal context if none exists
    local minimal = {
      "Project: " .. vim.fn.fnamemodify(vim.fn.getcwd(), ':t'),
      "Language: " .. vim.bo.filetype,
      "Working directory: " .. vim.fn.getcwd(),
    }
    return table.concat(minimal, '\n')
  end

  -- Return condensed version for prompts
  -- Remove empty sections and excessive whitespace
  context = context:gsub('\n\n+', '\n\n')
  context = context:gsub('## [^\n]+\n\n*%*Generator not implemented%*', '')

  -- Limit size for API calls
  if #context > 10000 then
    context = context:sub(1, 10000) .. "\n... (truncated)"
  end

  return context
end

return M