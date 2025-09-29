-- LSP context collection for AI assistance
local M = {}

-- Get LSP diagnostics for current buffer
function M.get_diagnostics(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local diagnostics = vim.diagnostic.get(bufnr)

  if #diagnostics == 0 then
    return nil
  end

  local result = {}
  for _, diag in ipairs(diagnostics) do
    table.insert(result, {
      line = diag.lnum + 1, -- Convert to 1-based
      col = diag.col + 1,
      severity = vim.diagnostic.severity[diag.severity],
      message = diag.message,
      source = diag.source or "unknown"
    })
  end

  return result
end

-- Get hover information at cursor position
function M.get_hover_info(bufnr, line, col)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  line = line or vim.api.nvim_win_get_cursor(0)[1]
  col = col or vim.api.nvim_win_get_cursor(0)[2]

  -- Get first client for position encoding
  local clients = vim.lsp.get_clients({bufnr = bufnr})
  local client = clients[1]
  local params = vim.lsp.util.make_position_params(0, client and client.offset_encoding)
  local timeout = 1000  -- Default timeout
  local ok, cfg = pcall(require, 'todo-ai.config')
  if ok then
    local lsp_cfg = cfg.get('lsp_context')
    if lsp_cfg and lsp_cfg.timeout then
      timeout = lsp_cfg.timeout
    end
  end
  local result = vim.lsp.buf_request_sync(bufnr, 'textDocument/hover', params, timeout)

  if not result then
    return nil
  end

  for _, server_result in pairs(result) do
    if server_result.result and server_result.result.contents then
      local contents = server_result.result.contents
      if type(contents) == 'string' then
        return contents
      elseif type(contents) == 'table' then
        if contents.value then
          return contents.value
        elseif #contents > 0 then
          local parts = {}
          for _, content in ipairs(contents) do
            if type(content) == 'string' then
              table.insert(parts, content)
            elseif content.value then
              table.insert(parts, content.value)
            end
          end
          return table.concat(parts, '\n')
        end
      end
    end
  end

  return nil
end

-- Get signature help at cursor position
function M.get_signature_help(bufnr, line, col)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  line = line or vim.api.nvim_win_get_cursor(0)[1]
  col = col or vim.api.nvim_win_get_cursor(0)[2]

  -- Get first client for position encoding
  local clients = vim.lsp.get_clients({bufnr = bufnr})
  local client = clients[1]
  local params = vim.lsp.util.make_position_params(0, client and client.offset_encoding)
  local result = vim.lsp.buf_request_sync(bufnr, 'textDocument/signatureHelp', params, 1000)

  if not result then
    return nil
  end

  for _, server_result in pairs(result) do
    if server_result.result and server_result.result.signatures then
      local signatures = {}
      for _, sig in ipairs(server_result.result.signatures) do
        table.insert(signatures, {
          label = sig.label,
          documentation = sig.documentation and (sig.documentation.value or sig.documentation) or nil,
          parameters = sig.parameters
        })
      end
      return signatures
    end
  end

  return nil
end

-- Get references for symbol at cursor
function M.get_references(bufnr, line, col, include_declaration)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  line = line or vim.api.nvim_win_get_cursor(0)[1]
  col = col or vim.api.nvim_win_get_cursor(0)[2]
  include_declaration = include_declaration == nil and true or include_declaration

  -- Get first client for position encoding
  local clients = vim.lsp.get_clients({bufnr = bufnr})
  local client = clients[1]
  local params = vim.lsp.util.make_position_params(0, client and client.offset_encoding)
  params.context = { includeDeclaration = include_declaration }

  local result = vim.lsp.buf_request_sync(bufnr, 'textDocument/references', params, 1000)

  if not result then
    return nil
  end

  local references = {}
  for _, server_result in pairs(result) do
    if server_result.result then
      for _, ref in ipairs(server_result.result) do
        table.insert(references, {
          uri = ref.uri,
          range = {
            start = {line = ref.range.start.line + 1, col = ref.range.start.character + 1},
            ["end"] = {line = ref.range["end"].line + 1, col = ref.range["end"].character + 1}
          }
        })
      end
    end
  end

  return #references > 0 and references or nil
end

-- Get definition location for symbol at cursor
function M.get_definition(bufnr, line, col)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  line = line or vim.api.nvim_win_get_cursor(0)[1]
  col = col or vim.api.nvim_win_get_cursor(0)[2]

  -- Get first client for position encoding
  local clients = vim.lsp.get_clients({bufnr = bufnr})
  local client = clients[1]
  local params = vim.lsp.util.make_position_params(0, client and client.offset_encoding)
  local result = vim.lsp.buf_request_sync(bufnr, 'textDocument/definition', params, 1000)

  if not result then
    return nil
  end

  for _, server_result in pairs(result) do
    if server_result.result then
      local def = server_result.result
      if type(def) == 'table' and def[1] then
        def = def[1]
      end
      if def and def.uri then
        return {
          uri = def.uri,
          range = {
            start = {line = def.range.start.line + 1, col = def.range.start.character + 1},
            ["end"] = {line = def.range["end"].line + 1, col = def.range["end"].character + 1}
          }
        }
      end
    end
  end

  return nil
end

-- Get document symbols (outline)
function M.get_document_symbols(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local params = { textDocument = vim.lsp.util.make_text_document_params() }
  local result = vim.lsp.buf_request_sync(bufnr, 'textDocument/documentSymbol', params, 1000)

  if not result then
    return nil
  end

  local symbols = {}

  local function extract_symbols(items, parent_name)
    for _, item in ipairs(items or {}) do
      -- Skip invalid symbols (no range = invalid)
      if not item.range then
        goto continue
      end

      local symbol = {
        name = item.name,
        kind = vim.lsp.protocol.SymbolKind[item.kind] or item.kind,
        range = {
          start = {line = item.range.start.line + 1, col = item.range.start.character + 1},
          ["end"] = {line = item.range["end"].line + 1, col = item.range["end"].character + 1}
        }
      }

      if parent_name then
        symbol.parent = parent_name
      end

      table.insert(symbols, symbol)

      -- Recursively extract children
      if item.children then
        extract_symbols(item.children, item.name)
      end

      ::continue::
    end
  end

  for _, server_result in pairs(result) do
    if server_result.result then
      extract_symbols(server_result.result)
    end
  end

  return #symbols > 0 and symbols or nil
end

-- Get active LSP clients for buffer
function M.get_active_clients(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local clients = vim.lsp.get_clients({bufnr = bufnr})

  if #clients == 0 then
    return nil
  end

  local result = {}
  for _, client in ipairs(clients) do
    table.insert(result, {
      name = client.name,
      id = client.id,
      capabilities = client.server_capabilities and vim.tbl_keys(client.server_capabilities) or {}
    })
  end

  return result
end

-- Get comprehensive LSP context for a buffer
function M.get_full_context(bufnr, line, col)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Check if LSP is available
  local clients = vim.lsp.get_clients({bufnr = bufnr})
  if #clients == 0 then
    return nil
  end

  local context = {
    clients = M.get_active_clients(bufnr),
    diagnostics = M.get_diagnostics(bufnr),
    symbols = M.get_document_symbols(bufnr)
  }

  -- If line/col specified, get position-specific info
  if line and col then
    context.hover = M.get_hover_info(bufnr, line, col)
    context.signature = M.get_signature_help(bufnr, line, col)
    context.definition = M.get_definition(bufnr, line, col)
    context.references = M.get_references(bufnr, line, col)
  end

  -- Filter out nil values
  for k, v in pairs(context) do
    if v == nil then
      context[k] = nil
    end
  end

  return context
end

-- Get focused LSP context (only most relevant info)
function M.get_focused_context(bufnr, line, col, config)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Use provided config or get defaults
  if not config then
    local ok, cfg_module = pcall(require, 'todo-ai.config')
    if ok then
      config = cfg_module.get('lsp_context') or {}
    else
      config = {}
    end
  end

  -- Check if LSP context is enabled
  if config.enabled == false then
    return nil
  end

  local clients = vim.lsp.get_clients({bufnr = bufnr})
  if #clients == 0 then
    return nil
  end

  local context = {}

  -- Include diagnostics if enabled
  if config.include_diagnostics ~= false then
    local diagnostics = M.get_diagnostics(bufnr)
    if diagnostics and #diagnostics > 0 then
      -- Limit to configured max (default 10)
      local max_diags = config.max_diagnostics or 10
      local sorted = {}
      for _, diag in ipairs(diagnostics) do
        table.insert(sorted, diag)
      end
      table.sort(sorted, function(a, b)
        -- Sort by severity (ERROR > WARN > INFO > HINT) and proximity to cursor
        if a.severity ~= b.severity then
          return a.severity == "ERROR" or (a.severity == "WARN" and b.severity ~= "ERROR")
        end
        if line then
          return math.abs(a.line - line) < math.abs(b.line - line)
        end
        return a.line < b.line
      end)

      context.diagnostics = {}
      for i = 1, math.min(max_diags, #sorted) do
        table.insert(context.diagnostics, sorted[i])
      end
    end
  end

  -- Include symbol outline if enabled
  if config.include_symbols ~= false then
    local symbols = M.get_document_symbols(bufnr)
    if symbols then
      -- Filter to only top-level symbols or those near cursor
      local filtered = {}
      for _, symbol in ipairs(symbols) do
        if not symbol.parent or (line and line >= symbol.range.start.line and line <= symbol.range["end"].line) then
          table.insert(filtered, {
            name = symbol.name,
            kind = symbol.kind,
            line = symbol.range.start.line
          })
        end
      end
      if #filtered > 0 then
        context.symbols = filtered
      end
    end
  end

  -- If at specific position, include hover info if enabled
  if line and col and config.include_hover ~= false then
    local hover = M.get_hover_info(bufnr, line, col)
    if hover then
      context.hover = hover
    end
  end

  return context
end

-- Get a compact summary of LSP diagnostics for a buffer
function M.get_buffer_diagnostics_summary(bufnr, config)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Get config if not provided
  if not config then
    local ok, cfg_module = pcall(require, 'todo-ai.config')
    if ok then
      config = cfg_module.get('lsp_context') or {}
    else
      config = {}
    end
  end

  -- Check if LSP is active for this buffer
  local clients = vim.lsp.get_clients({bufnr = bufnr})
  if #clients == 0 then
    return nil
  end

  local diagnostics = vim.diagnostic.get(bufnr)
  if #diagnostics == 0 then
    return {
      has_lsp = true,
      clean = true,
      clients = vim.tbl_map(function(c) return c.name end, clients)
    }
  end

  -- Count diagnostics by severity
  local counts = {
    errors = 0,
    warnings = 0,
    info = 0,
    hints = 0
  }

  local summary_items = {}
  local max_items = config.max_buffer_diagnostics or 5

  for _, diag in ipairs(diagnostics) do
    if diag.severity == vim.diagnostic.severity.ERROR then
      counts.errors = counts.errors + 1
      if #summary_items < max_items then  -- Include up to max_items errors
        table.insert(summary_items, {
          line = diag.lnum + 1,
          severity = "ERROR",
          message = diag.message:sub(1, 100)  -- Truncate long messages
        })
      end
    elseif diag.severity == vim.diagnostic.severity.WARN then
      counts.warnings = counts.warnings + 1
      if counts.errors == 0 and #summary_items < math.ceil(max_items / 2) then  -- Include warnings if no errors
        table.insert(summary_items, {
          line = diag.lnum + 1,
          severity = "WARN",
          message = diag.message:sub(1, 100)
        })
      end
    elseif diag.severity == vim.diagnostic.severity.INFO then
      counts.info = counts.info + 1
    else
      counts.hints = counts.hints + 1
    end
  end

  return {
    has_lsp = true,
    counts = counts,
    total = #diagnostics,
    summary = summary_items,
    clients = vim.tbl_map(function(c) return c.name end, clients)
  }
end

return M