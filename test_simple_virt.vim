" Simple virtual text test
" Run this with :source test_simple_virt.vim

" Create a test namespace
let ns = nvim_create_namespace('test_virt')

" Clear any existing marks
call nvim_buf_clear_namespace(0, ns, 0, -1)

" Add simple virtual text above line 1
call nvim_buf_set_extmark(0, ns, 0, 0, {
  \ 'virt_lines_above': v:true,
  \ 'virt_lines': [
  \   [['>>> THIS IS A TEST HEADER <<<', 'ErrorMsg']]
  \ ]
\ })

" Add another one at current cursor position
let [line, col] = getpos('.')[1:2]
if line > 1
  call nvim_buf_set_extmark(0, ns, line - 1, 0, {
    \ 'virt_lines_above': v:true,
    \ 'virt_lines': [
      \ [['--- HEADER AT CURSOR ---', 'WarningMsg']]
    \ ]
  \ })
endif

echo "Virtual text added. If you don't see headers above line 1 and cursor position, virtual text rendering is broken."