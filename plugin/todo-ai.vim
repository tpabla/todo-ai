" todo-ai.vim - Entry point for todo-ai plugin

if exists('g:loaded_todo_ai')
  finish
endif
let g:loaded_todo_ai = 1

" Initialize Lua module
lua require('todo-ai').setup()

" Commands
command! TodoAIScan lua require('todo-ai').scan_buffer()
command! TodoAIAccept lua require('todo-ai').accept_change()
command! TodoAIReject lua require('todo-ai').reject_change()
command! TodoAIChat lua require('todo-ai').open_chat()
command! TodoAIConfig lua require('todo-ai').open_config()

" Edit queue commands
command! TodoAIEditAccept lua require('todo-ai.chat').accept_current_edit()
command! TodoAIEditReject lua require('todo-ai.chat').reject_current_edit()
command! TodoAIEditNext lua require('todo-ai.chat').show_next_edit()

" Default keymaps (user can override)
nnoremap <silent> <leader>ts :TodoAIScan<CR>
nnoremap <silent> <leader>ta :TodoAIAccept<CR>
nnoremap <silent> <leader>tr :TodoAIReject<CR>
nnoremap <silent> <leader>tc :TodoAIChat<CR>

" Edit queue keymaps
nnoremap <silent> <leader>ea :TodoAIEditAccept<CR>
nnoremap <silent> <leader>er :TodoAIEditReject<CR>
nnoremap <silent> <leader>en :TodoAIEditNext<CR>

" Auto-scan on save if enabled
augroup TodoAI
  autocmd!
  autocmd BufWritePost * lua require('todo-ai').auto_scan()
augroup END