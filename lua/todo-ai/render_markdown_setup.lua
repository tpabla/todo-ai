-- Setup render-markdown for todo-ai chat windows
local M = {}

function M.setup()
  -- Check if render-markdown is available
  local ok, render_markdown = pcall(require, 'render-markdown')
  if not ok then
    return
  end

  -- Apply cyberpunk aesthetic highlight groups for icons only (no backgrounds)
  vim.api.nvim_set_hl(0, "RenderMarkdownH1", { fg = "#00ff9f", bold = true, bg = "NONE" })
  vim.api.nvim_set_hl(0, "RenderMarkdownH2", { fg = "#00d9ff", bold = true, bg = "NONE" })
  vim.api.nvim_set_hl(0, "RenderMarkdownH3", { fg = "#ff00ff", bold = true, bg = "NONE" })
  vim.api.nvim_set_hl(0, "RenderMarkdownH4", { fg = "#ffb86c", bold = true, bg = "NONE" })
  vim.api.nvim_set_hl(0, "RenderMarkdownH5", { fg = "#ff79c6", bold = true, bg = "NONE" })
  vim.api.nvim_set_hl(0, "RenderMarkdownH6", { fg = "#bd93f9", bold = true, bg = "NONE" })

  -- Also set the background highlights to NONE
  vim.api.nvim_set_hl(0, "RenderMarkdownH1Bg", { bg = "NONE" })
  vim.api.nvim_set_hl(0, "RenderMarkdownH2Bg", { bg = "NONE" })
  vim.api.nvim_set_hl(0, "RenderMarkdownH3Bg", { bg = "NONE" })
  vim.api.nvim_set_hl(0, "RenderMarkdownH4Bg", { bg = "NONE" })
  vim.api.nvim_set_hl(0, "RenderMarkdownH5Bg", { bg = "NONE" })
  vim.api.nvim_set_hl(0, "RenderMarkdownH6Bg", { bg = "NONE" })

  vim.api.nvim_set_hl(0, "RenderMarkdownCode", { bg = "#1a1a2e" })
  vim.api.nvim_set_hl(0, "RenderMarkdownCodeInline", { fg = "#50fa7b", bg = "#282a36" })
  vim.api.nvim_set_hl(0, "RenderMarkdownBullet", { fg = "#ff00ff" })
  vim.api.nvim_set_hl(0, "RenderMarkdownQuote", { fg = "#8be9fd", italic = true })
  vim.api.nvim_set_hl(0, "RenderMarkdownDash", { fg = "#ff00ff" })

  vim.api.nvim_set_hl(0, "RenderMarkdownTableHead", { fg = "#00ff9f", bg = "#1a1a2e", bold = true })
  vim.api.nvim_set_hl(0, "RenderMarkdownTableRow", { fg = "#00d9ff" })
  vim.api.nvim_set_hl(0, "RenderMarkdownTableFill", { fg = "#ff00ff" })

  vim.api.nvim_set_hl(0, "RenderMarkdownChecked", { fg = "#50fa7b" })
  vim.api.nvim_set_hl(0, "RenderMarkdownUnchecked", { fg = "#ff5555" })
  vim.api.nvim_set_hl(0, "RenderMarkdownTodo", { fg = "#ffb86c" })
  vim.api.nvim_set_hl(0, "RenderMarkdownImportant", { fg = "#ff79c6" })
  vim.api.nvim_set_hl(0, "RenderMarkdownCancelled", { fg = "#6272a4" })

  vim.api.nvim_set_hl(0, "RenderMarkdownLink", { fg = "#8be9fd", underline = true })
  vim.api.nvim_set_hl(0, "RenderMarkdownLinkText", { fg = "#ff79c6" })

  -- No need to register filetypes here - render-markdown will handle it
  -- when we set the buffer filetype to markdown or todoai-chat
end

return M