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
    todo_text = "Title",         -- Bold, bright text for TODO content
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

-- Helper function to wrap text at word boundaries
local function wrap_text(text, max_width)
  local lines = {}
  local current_line = ""

  for word in text:gmatch("%S+") do
    local test_line = current_line == "" and word or current_line .. " " .. word
    if #test_line <= max_width then
      current_line = test_line
    else
      if current_line ~= "" then
        table.insert(lines, current_line)
      end
      -- If word itself is longer than max_width, split it
      if #word > max_width then
        while #word > max_width do
          table.insert(lines, word:sub(1, max_width))
          word = word:sub(max_width + 1)
        end
      end
      current_line = word
    end
  end

  if current_line ~= "" then
    table.insert(lines, current_line)
  end

  return lines
end

-- Create status header for a change
function M.create_header(status, todo_text, opts)
  opts = opts or {}
  local cfg = opts.config or M.config

  -- Determine indicator and color based on status
  local indicator = cfg.indicators[status] or cfg.indicators.pending
  local color = cfg.colors[status] or cfg.colors.pending

  local header_lines = {}
  local line_width = 80  -- Total width for all lines

  -- Build status line with fixed total width
  -- The actual visible text (excluding color codes): indicator + " [ta] ACCEPT [tr] REJECT "
  local status_text = indicator .. " [ta] ACCEPT [tr] REJECT"
  local status_text_len = vim.fn.strdisplaywidth(status_text) + 2 -- +2 for spaces around

  -- Calculate padding to reach exactly 80 chars
  local total_padding = line_width - status_text_len
  local left_padding = math.floor(total_padding / 2)
  local right_padding = total_padding - left_padding

  -- Ensure at least 3 dashes on each side
  if left_padding < 3 or right_padding < 3 then
    -- If text is too long, use minimum padding
    left_padding = 3
    right_padding = 3
  end

  -- Build first line with exact padding
  local status_line = {
    {string.rep("─", left_padding), cfg.colors.separator},
    {" ", cfg.colors.normal},
    {indicator, color},
    {" [", cfg.colors.normal},
    {"ta", cfg.colors.accepted},
    {"] ACCEPT [", cfg.colors.normal},
    {"tr", cfg.colors.rejected},
    {"] REJECT ", cfg.colors.normal},
    {string.rep("─", right_padding), cfg.colors.separator},
  }
  table.insert(header_lines, status_line)

  -- Second line: raw TODO text (if provided) - left justified
  if todo_text and todo_text ~= "" then
    -- Wrap TODO text, leaving room for "━━━ " prefix (4 chars) and ensuring solid line suffix
    local max_text_width = line_width - 8
    local wrapped = wrap_text(todo_text, max_text_width)

    for i, line in ipairs(wrapped) do
      -- Build left-justified TODO line
      -- Format: "━━━ TODO text ━━━..."
      local prefix = "━━━ "
      local text_with_spacing = prefix .. line .. " "
      local text_len = vim.fn.strdisplaywidth(text_with_spacing)

      -- Calculate right padding to reach 80 chars total
      local right_padding = line_width - text_len

      -- Ensure at least 3 solid lines on the right
      if right_padding < 3 then
        -- Truncate text if needed to ensure minimum right padding
        local max_allowed = line_width - 7  -- "━━━ " (4) + minimum " ━━━" (4)
        line = line:sub(1, max_allowed)
        text_with_spacing = prefix .. line .. " "
        text_len = vim.fn.strdisplaywidth(text_with_spacing)
        right_padding = line_width - text_len
      end

      local todo_line = {
        {"━━━ ", cfg.colors.separator},  -- Use solid lines to match
        {line, cfg.colors.todo_text},  -- Use bold text for TODO content
        {" ", cfg.colors.normal},
        {string.rep("━", right_padding), cfg.colors.separator},  -- Solid line for padding
      }

      table.insert(header_lines, todo_line)
    end
  end

  -- Add a final solid separator line (full width)
  local separator_line = {{string.rep("━", line_width), cfg.colors.separator}}
  table.insert(header_lines, separator_line)

  return header_lines  -- Return array of lines
end

-- Create footer with description
function M.create_footer(description, opts)
  opts = opts or {}
  local cfg = opts.config or M.config
  local line_width = 80

  local footer_lines = {}

  -- Add solid separator line first
  table.insert(footer_lines, {{string.rep("━", line_width), cfg.colors.separator}})

  -- Add description if provided (same format as TODO in header)
  if description and description ~= "" then
    -- Wrap description text
    local max_text_width = line_width - 8
    local wrapped = wrap_text(description, max_text_width)

    for i, line in ipairs(wrapped) do
      -- Build left-justified description line
      -- Format: "━━━ description text ━━━..."
      local prefix = "━━━ "
      local text_with_spacing = prefix .. line .. " "
      local text_len = vim.fn.strdisplaywidth(text_with_spacing)

      -- Calculate right padding to reach 80 chars total
      local right_padding = line_width - text_len

      -- Ensure at least 3 solid lines on the right
      if right_padding < 3 then
        -- Truncate text if needed to ensure minimum right padding
        local max_allowed = line_width - 7  -- "━━━ " (4) + minimum " ━━━" (4)
        line = line:sub(1, max_allowed)
        text_with_spacing = prefix .. line .. " "
        text_len = vim.fn.strdisplaywidth(text_with_spacing)
        right_padding = line_width - text_len
      end

      local desc_line = {
        {"━━━ ", cfg.colors.separator},  -- Use solid lines to match
        {line, cfg.colors.description},
        {" ", cfg.colors.normal},
        {string.rep("━", right_padding), cfg.colors.separator},  -- Solid line for padding
      }

      table.insert(footer_lines, desc_line)
    end
  end

  return footer_lines
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
      local todo_text = hunk.todo_text or ""  -- Raw TODO text
      local description = hunk.description or ""  -- AI's description of the change

      -- Build complete virtual text block (header + removed lines)
      local virt_lines_block = {}

      -- Add header with TODO text (can be multiple lines)
      local header_lines = M.create_header(status, todo_text, opts)
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
      -- Use display_start if available (position in the display buffer after SEARCH/REPLACE)
      -- Otherwise fall back to start_line (position in original file)
      local position = hunk.display_start or hunk.start_line

      -- Calculate header line position
      -- With padding line added, we can use virt_lines_above normally
      local header_line = position - 1
      local use_virt_lines_above = true  -- Always use virt_lines_above now

      -- Debug logging
      local logger = require('todo-ai.logger')
      logger.info('diff_formatter', string.format('Hunk %d: position=%d, header_line=%d, display_start=%s, start_line=%s',
        idx, position, header_line, tostring(hunk.display_start), tostring(hunk.start_line)))

      -- Ensure header_line is within valid range [0, buf_line_count-1]
      if header_line >= 0 and header_line < buf_line_count and #virt_lines_block > 0 then
        logger.info('diff_formatter', string.format('Setting header at line %d, use_virt_lines_above=%s', header_line, tostring(use_virt_lines_above)))

        -- Store extmark ID for lifecycle tracking
        local mark_opts = {
          virt_lines = virt_lines_block
        }

        -- For line 0, use virt_lines without _above to work around rendering issue
        -- For other lines, use virt_lines_above for proper placement
        if use_virt_lines_above then
          mark_opts.virt_lines_above = true
        else
          -- Place at line 0 but show after (this makes it visible at top of file)
          mark_opts.virt_lines_above = false
        end

        local mark_id = vim.api.nvim_buf_set_extmark(buf, ns_id, header_line, 0, mark_opts)
        logger.info('diff_formatter', string.format('Header extmark created with ID %d', mark_id))

        -- Verify immediately
        local marks = vim.api.nvim_buf_get_extmarks(buf, ns_id, {header_line, 0}, {header_line, -1}, {details = true})
        logger.info('diff_formatter', string.format('Verification: %d marks at line %d', #marks, header_line))

        -- Schedule another check to see if extmarks persist
        vim.defer_fn(function()
          -- Validate buffer still exists before checking
          if not vim.api.nvim_buf_is_valid(buf) then
            logger.warn('diff_formatter', string.format('Buffer %d no longer valid after 100ms', buf))
            return
          end

          local delayed_marks = vim.api.nvim_buf_get_extmarks(buf, ns_id, {header_line, 0}, {header_line, -1}, {details = true})
          logger.info('diff_formatter', string.format('After 100ms: %d marks at line %d (mark_id=%d)', #delayed_marks, header_line, mark_id))

          -- Check if our specific mark still exists
          local our_mark = vim.api.nvim_buf_get_extmark_by_id(buf, ns_id, mark_id, {details = true})
          if #our_mark == 0 then
            logger.warn('diff_formatter', string.format('Extmark %d disappeared!', mark_id))
          else
            logger.info('diff_formatter', string.format('Extmark %d still exists at row=%d', mark_id, our_mark[1]))
          end
        end, 100)
      else
        logger.warn('diff_formatter', string.format('Skipping header: header_line=%d, buf_line_count=%d', header_line, buf_line_count))
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

      -- Add footer with description
      local footer_lines = M.create_footer(description, opts)
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