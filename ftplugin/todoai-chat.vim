" File type plugin for Todo-AI Chat buffers
" Inherit all markdown settings
runtime! ftplugin/markdown.vim

" Set local options for chat buffers
setlocal wrap
setlocal linebreak
setlocal breakindent
setlocal conceallevel=2
setlocal concealcursor=

" Disable spell checking by default in chat
setlocal nospell

" Set comment string for markdown
setlocal commentstring=<!--%s-->