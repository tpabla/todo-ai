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
command! TodoAIGenerateContext lua require('todo-ai.context_compact').generate_and_open()
command! TodoAISuggestDryTags lua require('todo-ai.dry_tagger').suggest_dry_tags()
command! -range TodoAIVisual lua require('todo-ai.visual').process_visual_selection()
command! -range TodoAIInteractive lua require('todo-ai.visual').process_visual_selection()
command! TodoAIScanProject lua require('todo-ai').process_project_todos()
command! TodoAIAcceptAll lua require('todo-ai').accept_all_project_changes()
command! TodoAILogs lua vim.cmd('split /tmp/todo-ai.log | setlocal autoread | normal! G')

" Edit queue commands
command! TodoAIEditAccept lua require('todo-ai.chat').accept_current_edit()
command! TodoAIEditReject lua require('todo-ai.chat').reject_current_edit()
command! TodoAIEditNext lua require('todo-ai.chat').show_next_edit()

" Default keymaps (user can override)
nnoremap <silent> <leader>ts :TodoAIScan<CR>
nnoremap <silent> <leader>ta :TodoAIAccept<CR>
nnoremap <silent> <leader>tr :TodoAIReject<CR>
nnoremap <silent> <leader>tc :TodoAIChat<CR>
nnoremap <silent> <leader>tg :TodoAIGenerateContext<CR>
nnoremap <silent> <leader>td :TodoAISuggestDryTags<CR>
nnoremap <silent> <leader>tS :TodoAIScanProject<CR>
nnoremap <silent> <leader>tG :TodoAIAcceptAll<CR>

" Visual mode keybinding for interactive TODO
vnoremap <silent> <leader>ti :'<,'>TodoAIVisual<CR>

" Edit queue keymaps
nnoremap <silent> <leader>ea :TodoAIEditAccept<CR>
nnoremap <silent> <leader>er :TodoAIEditReject<CR>
nnoremap <silent> <leader>en :TodoAIEditNext<CR>

" Auto-scan on save if enabled
augroup TodoAI
  autocmd!
  autocmd BufWritePost * lua require('todo-ai').auto_scan()
augroup END