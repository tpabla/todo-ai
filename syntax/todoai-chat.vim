" Syntax highlighting for Todo-AI Chat buffers
" Inherit markdown syntax
runtime! syntax/markdown.vim

" Only add minimal custom highlighting that won't conflict
" Let render-markdown handle the headers
syntax match TodoAIThinking /^`⚡.*`$/

" Link to appropriate highlight groups
highlight link TodoAIThinking Comment