if exists('g:loaded_todo_ai')
  finish
endif
let g:loaded_todo_ai = 1

command! TodoAI lua require('todo-ai').open_agent_interactive()
command! TodoAIFocus lua require('todo-ai').focus_agent()
command! TodoAIScan lua require('todo-ai').scan()
command! TodoAIInstall lua require('todo-ai').install()
command! -range TodoAIVisual lua require('todo-ai.visual').process()

nnoremap <silent> <leader>tc :TodoAI<CR>
nnoremap <silent> <leader>tf :TodoAIFocus<CR>
nnoremap <silent> <leader>ts :TodoAIScan<CR>
vnoremap <silent> <leader>ti :'<,'>TodoAIVisual<CR>
