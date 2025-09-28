-- Diff visual formatting module
-- Handles visual presentation of changes with headers, colors, and indicators
local M = {}

-- Default configuration - Cyberpunk neon aesthetic
M.config = {
  indicators = {
    pending = "🤔 PENDING",
    accepted = "✅ ACCEPTED",
    rejected = "🔥 REJECTED"
  },
  colors = {
    -- Neon cyberpunk colors - bright foreground on dark
    pending = "DiagnosticWarn",  -- Neon yellow/amber
    accepted = "DiagnosticOk",   -- Neon green glow
    rejected = "DiagnosticError", -- Neon red/pink
    separator = "Special",        -- Neon purple/magenta
    add = "DiffAdd",            -- Use native DiffAdd for proper highlighting
    delete = "DiffDelete",      -- Use native DiffDelete for proper red
    normal = "Normal",
    comment = "Keyword",         -- Neon blue/cyan
    description = "Title"        -- Bright, bold text that pops
  },
  signs = {
    add = "+",
    delete = "-",
    separator = "━",
    search_marker = "◆",
    replace_marker = "◈"
  },
  separator_width = 60,
  header_width = 50
}

-- Create status header for a change
function M.create_header(status, description, opts)
  opts = opts or {}
  local cfg = opts.config or M.config

  -- Determine indicator and color based on status
  local indicator = cfg.indicators[status] or cfg.indicators.pending
  local color = cfg.colors[status] or cfg.colors.pending

  -- Single line header with separator and status
  local header_line = {
    {string.rep("─", 10), cfg.colors.separator},
    {" ", cfg.colors.normal},
    {indicator, color},
    {" ", cfg.colors.normal},
    {"[", cfg.colors.comment},
    {"ta", cfg.colors.accepted},
    {"]", cfg.colors.comment},
    {" ACCEPT ", cfg.colors.accepted},
    {" ", cfg.colors.normal},
    {"[", cfg.colors.comment},
    {"tr", cfg.colors.rejected},
    {"]", cfg.colors.comment},
    {" REJECT ", cfg.colors.rejected},
  }

  -- Add description as bullet point if provided
  if description and description ~= "" then
    table.insert(header_line, {" • ", cfg.colors.separator})
    table.insert(header_line, {description, cfg.colors.description})
  end

  -- Fill rest with separator line
  table.insert(header_line, {" ", cfg.colors.normal})
  table.insert(header_line, {string.rep("─", 20), cfg.colors.separator})

  return {header_line}  -- Return as single-element array for consistency
end

-- Create footer separator
function M.create_footer(opts)
  opts = opts or {}
  local cfg = opts.config or M.config

  return {{
    string.rep("─", cfg.separator_width),
    cfg.colors.separator
  }}
end

-- Format removed lines for virtual text display
function M.format_removed_lines(lines, opts)
  opts = opts or {}
  local cfg = opts.config or M.config

  local removed_display = {}
  for _, line in ipairs(lines) do
    -- Use minus sign in gutter position, then the line content with red coloring
    table.insert(removed_display, {
      {"- ", cfg.colors.delete},  -- Minus sign in gutter (red)
      {line, cfg.colors.delete}   -- Line content (red)
    })
  end

  return removed_display
end


-- Apply visual formatting to a buffer
function M.apply_formatting(buf, hunks, state, ns_id, opts)
  opts = opts or {}
  local buf_line_count = vim.api.nvim_buf_line_count(buf)

  for idx, hunk in ipairs(hunks) do
    if hunk.start_line and hunk.end_line then
      local change_idx = hunk.change_index

      -- Skip rejected changes
      if state.rejected_diffs[change_idx] then
        goto continue
      end

      local status = state.accepted_diffs[change_idx] and "accepted" or "pending"
      local description = hunk.description or ""

      -- Build complete virtual text block (header + removed lines)
      local virt_lines_block = {}

      -- Add header (can be multiple lines)
      local header_lines = M.create_header(status, description, opts)
      for _, line in ipairs(header_lines) do
        table.insert(virt_lines_block, line)
      end

      -- Add removed content as virtual text
      if hunk.search_text then
        local search_lines = vim.split(hunk.search_text, '\n', { plain = true })
        local removed_display = M.format_removed_lines(search_lines, opts)
        for _, line in ipairs(removed_display) do
          table.insert(virt_lines_block, line)
        end
      end

      -- Apply all virtual lines at once
      local header_line = math.max(0, math.min(hunk.start_line - 1, buf_line_count - 1))
      if header_line >= 0 and header_line < buf_line_count and #virt_lines_block > 0 then
        vim.api.nvim_buf_set_extmark(buf, ns_id, header_line, 0, {
          virt_lines_above = true,
          virt_lines = virt_lines_block
        })
      end

      -- Highlight replacement lines with green background
      -- Use display_start/display_end if available (the correct positions in the display buffer)
      local start_line = hunk.display_start or hunk.start_line
      local end_line = hunk.display_end or hunk.end_line

      for line_num = start_line, math.min(end_line, buf_line_count) do
        local line_idx = line_num - 1
        if line_idx >= 0 and line_idx < buf_line_count then
          local line = vim.api.nvim_buf_get_lines(buf, line_idx, line_idx + 1, false)[1] or ""
          local cfg = opts.config or M.config  -- Get config here

          -- Add line highlight (DiffAdd handles the entire line styling)
          vim.api.nvim_buf_set_extmark(buf, ns_id, line_idx, 0, {
            line_hl_group = cfg.colors.add,  -- Use line_hl_group for full line highlighting
            priority = 10
          })

          -- Add the sign in the gutter
          vim.api.nvim_buf_set_extmark(buf, ns_id, line_idx, 0, {
            sign_text = cfg.signs.add,
            sign_hl_group = cfg.colors.add,
            priority = 10
          })
        end
      end

      -- Add footer
      local footer_lines = { M.create_footer(opts) }
      local footer_pos = math.min(hunk.end_line - 1, buf_line_count - 1)

      if footer_pos >= 0 and footer_pos < buf_line_count then
        vim.api.nvim_buf_set_extmark(buf, ns_id, footer_pos, 0, {
          virt_lines = footer_lines,
          virt_lines_above = false
        })
      end
    end
    ::continue::
  end
end

return M