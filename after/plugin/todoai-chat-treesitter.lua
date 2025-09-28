-- Configure treesitter to use markdown parser for todoai-chat filetype
vim.treesitter.language.register('markdown', 'todoai-chat')

-- Ensure markdown parser is installed
local ok, parsers = pcall(require, 'nvim-treesitter.parsers')
if ok then
  local parser_config = parsers.get_parser_configs()
  -- Register todoai-chat to use markdown parser
  if parser_config then
    vim.treesitter.language.add('todoai-chat', {
      install_info = parser_config.markdown.install_info,
      filetype = 'todoai-chat',
    })
  end
end