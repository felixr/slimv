" Open a new REPL buffer
function! slimv#repl#open()
    call slimv#buffer#open( g:slimv_repl_name )
    call b:SlimvInitRepl()
    if g:slimv_repl_syntax
        call slimv#repl#setSyntax()
    else
        set syntax=
    endif

    " Prompt and its line and column number in the REPL buffer
    if !exists( 'b:repl_prompt' )
        let b:repl_prompt = ''
        let b:repl_prompt_line = 1
        let b:repl_prompt_col = 1
    endif

    " Add keybindings valid only for the REPL buffer
    inoremap <buffer> <silent>        <C-CR> <End><C-O>:call slimv#sendCommand(1)<CR>
    inoremap <buffer> <silent>        <C-C>  <C-O>:call slimv#interrupt()<CR>

    if g:slimv_repl_simple_eval
        inoremap <buffer> <silent>        <CR>     <C-R>=pumvisible() ? "\<lt>C-Y>"  : "\<lt>End>\<lt>C-O>:call slimv#sendCommand(0)\<lt>CR>"<CR>
        inoremap <buffer> <silent>        <Up>     <C-R>=pumvisible() ? "\<lt>Up>"   : slimv#handleUp()<CR>
        inoremap <buffer> <silent>        <Down>   <C-R>=pumvisible() ? "\<lt>Down>" : slimv#handleDown()<CR>
    else
        inoremap <buffer> <silent>        <CR>     <C-R>=pumvisible() ? "\<lt>C-Y>"  : slimv#handleEnterRepl()<CR><C-R>=slimv#arglistOnEnter()<CR>
        inoremap <buffer> <silent>        <C-Up>   <C-R>=pumvisible() ? "\<lt>Up>"   : slimv#handleUp()<CR>
        inoremap <buffer> <silent>        <C-Down> <C-R>=pumvisible() ? "\<lt>Down>" : slimv#handleDown()<CR>
    endif

    if exists( 'g:paredit_loaded' )
        inoremap <buffer> <silent> <expr> <BS>   PareditBackspace(1)
    else
        inoremap <buffer> <silent> <expr> <BS>   slimv#handleBS()
    endif

    if g:slimv_keybindings == 1
        execute 'noremap <buffer> <silent> ' . g:slimv_leader.'.      :call slimv#sendCommand(0)<CR>'
        execute 'noremap <buffer> <silent> ' . g:slimv_leader.'/      :call slimv#sendCommand(1)<CR>'
        execute 'noremap <buffer> <silent> ' . g:slimv_leader.'<Up>   :call slimv#previousCommand()<CR>'
        execute 'noremap <buffer> <silent> ' . g:slimv_leader.'<Down> :call slimv#nextCommand()<CR>'
    elseif g:slimv_keybindings == 2
        execute 'noremap <buffer> <silent> ' . g:slimv_leader.'rs     :call slimv#sendCommand(0)<CR>'
        execute 'noremap <buffer> <silent> ' . g:slimv_leader.'ro     :call slimv#sendCommand(1)<CR>'
        execute 'noremap <buffer> <silent> ' . g:slimv_leader.'rp     :call slimv#previousCommand()<CR>'
        execute 'noremap <buffer> <silent> ' . g:slimv_leader.'rn     :call slimv#nextCommand()<CR>'
    endif

    if g:slimv_repl_wrap
        inoremap <buffer> <silent>        <Home> <C-O>g<Home>
        inoremap <buffer> <silent>        <End>  <C-O>:call <SID>EndOfScreenLine()<CR>
        noremap  <buffer> <silent>        <Up>   gk
        noremap  <buffer> <silent>        <Down> gj
        noremap  <buffer> <silent>        <Home> g<Home>
        noremap  <buffer> <silent>        <End>  :call <SID>EndOfScreenLine()<CR>
        noremap  <buffer> <silent>        k      gk
        noremap  <buffer> <silent>        j      gj
        noremap  <buffer> <silent>        0      g0
        noremap  <buffer> <silent>        $      :call <SID>EndOfScreenLine()<CR>
        setlocal wrap
    endif

    hi SlimvNormal term=none cterm=none gui=none
    hi SlimvCursor term=reverse cterm=reverse gui=reverse

    augroup slimv#replAutoCmd
        au!
        " Add autocommands specific to the REPL buffer
        execute "au FileChangedShell " . g:slimv_repl_name . " :call slimv#repl#refresh()"
        execute "au FocusGained "      . g:slimv_repl_name . " :call slimv#repl#refresh()"
        execute "au BufEnter "         . g:slimv_repl_name . " :call slimv#repl#enter()" 
        execute "au BufLeave "         . g:slimv_repl_name . " :call slimv#repl#leave()" 
    augroup END

    call slimv#repl#refresh()
endfunction



" Clear the contents of the REPL buffer, keeping the last prompt only
function! slimv#repl#clear()
    let this_buf = bufnr( "%" )
    let repl_buf = bufnr( '^' . g:slimv_repl_name . '$' )
    if repl_buf == -1
        call slimv#error( "There is no REPL buffer." )
        return
    endif
    if this_buf != repl_buf
        let oldpos = winsaveview()
        execute "buf " . repl_buf
    endif
    if b:repl_prompt_line > 1
        execute "normal! gg0d" . (b:repl_prompt_line-1) . "GG$"
        let b:repl_prompt_line = 1
    endif
    if this_buf != repl_buf
        execute "buf " . this_buf
        call winrestview( oldpos )
    endif
endfunction

" Position the cursor at the end of the REPL buffer
" Optionally mark this position in Vim mark 's'
function! slimv#repl#moveToEnd()
    if line( '.' ) >= b:repl_prompt_line - 1
        " Go to the end of file only if the user did not move up from here
        call s:EndOfBuffer()
    endif
endfunction

" Go to the end of buffer, make sure the cursor is positioned
" after the last character of the buffer when in insert mode
function s:EndOfBuffer()
    normal! G$
    if &virtualedit != 'all'
        call cursor( line('$'), 99999 )
    endif
endfunction

" Stop updating the REPL buffer and switch back to caller
function! slimv#repl#endUpdate()
    " Keep only the last g:slimv_repl_max_len lines
    let lastline = line('$')
    let prompt_offset = lastline - b:repl_prompt_line
    if g:slimv_repl_max_len > 0 && lastline > g:slimv_repl_max_len
        let start = ''
        let ending = s:CloseForm( getline( 1, lastline - g:slimv_repl_max_len ) )
        if match( ending, ')\|\]\|}\|"' ) >= 0
            " Reverse the ending and replace matched characters with their pairs
            let start = join( reverse( split( ending, '.\zs' ) ), '' )
            let start = substitute( start, ')', '(', 'g' )
            let start = substitute( start, ']', '[', 'g' )
            let start = substitute( start, '}', '{', 'g' )
        endif

        " Delete extra lines
        execute "python vim.current.buffer[0:" . (lastline - g:slimv_repl_max_len) . "] = []"

        " Re-balance the beginning of the buffer
        if start != ''
            call append( 0, start . " .... ; output shortened" )
        endif
        let b:repl_prompt_line = line( '$' ) - prompt_offset
    endif

    " Mark current prompt position
    call slimv#markBufferEnd()
    let repl_buf = bufnr( '^' . g:slimv_repl_name . '$' )
    let repl_win = bufwinnr( repl_buf )
    let current_buf = slimv#getCurrentBuffer()
    let sldb_level = slimv#getSldbLevel()
    if current_buf >= 0 && repl_buf != current_buf && repl_win != -1 && sldb_level < 0
        " Switch back to the caller buffer/window
        let repl_winid = getwinvar( repl_win, 'id' )
        if winnr('$') > 1 && current_win != '' && current_win != repl_winid
            call s:SwitchToWindow( s:current_win )
        endif
        execute "buf " . current_buf
    endif
endfunction


" Called when entering REPL buffer
function! slimv#repl#enter()
    call slimv#addReplMenu()
    augroup SlimvReplChanged
        au!
        execute "au FileChangedRO " . g:slimv_repl_name . " :call slimv#refreshModeOff()"
    augroup END
    call slimv#refreshModeOn()
endfunction

" Called when leaving REPL buffer
function! slimv#repl#leave()
    try
        " Check if REPL menu exists, then remove it
        aunmenu REPL
        execute ':unmap ' . g:slimv_leader . '\'
    catch /.*/
        " REPL menu not found, we cannot remove it
    endtry
    if g:slimv_repl_split
        call slimv#refreshModeOn()
    else
        call slimv#refreshModeOff()
    endif
endfunction

" Reload the contents of the REPL buffer from the output file if changed
function! slimv#repl#refresh()
    if slimv#isRefreshDisabled()
        " Refresh is unwanted at the moment, probably another refresh is going on
        return
    endif

    let repl_buf = bufnr( '^' . g:slimv_repl_name . '$' )
    if repl_buf == -1
        " REPL buffer not loaded
        return
    endif

    if s:swank_connected
        call slimv#swankResponse()
    endif

    if exists("s:input_prompt") && s:input_prompt != ''
        let answer = input( s:input_prompt )
        unlet s:input_prompt
        echo ""
        call slimv#command( 'python swank_return("' . answer . '")' )
    endif
endfunction


" Set special syntax rules for the REPL buffer
function! slimv#repl#setSyntax()
    if slimv#getFiletype() == 'scheme'
        syn cluster replListCluster contains=@schemeListCluster,lispList
    else
        syn cluster replListCluster contains=@lispListCluster
    endif

if exists("g:lisp_rainbow") && g:lisp_rainbow != 0

    if &bg == "dark"
        hi def hlLevel0 ctermfg=red         guifg=red1
        hi def hlLevel1 ctermfg=yellow      guifg=orange1
        hi def hlLevel2 ctermfg=green       guifg=yellow1
        hi def hlLevel3 ctermfg=cyan        guifg=greenyellow
        hi def hlLevel4 ctermfg=magenta     guifg=green1
        hi def hlLevel5 ctermfg=red         guifg=springgreen1
        hi def hlLevel6 ctermfg=yellow      guifg=cyan1
        hi def hlLevel7 ctermfg=green       guifg=slateblue1
        hi def hlLevel8 ctermfg=cyan        guifg=magenta1
        hi def hlLevel9 ctermfg=magenta     guifg=purple1
    else
        hi def hlLevel0 ctermfg=red         guifg=red3
        hi def hlLevel1 ctermfg=darkyellow  guifg=orangered3
        hi def hlLevel2 ctermfg=darkgreen   guifg=orange2
        hi def hlLevel3 ctermfg=blue        guifg=yellow3
        hi def hlLevel4 ctermfg=darkmagenta guifg=olivedrab4
        hi def hlLevel5 ctermfg=red         guifg=green4
        hi def hlLevel6 ctermfg=darkyellow  guifg=paleturquoise3
        hi def hlLevel7 ctermfg=darkgreen   guifg=deepskyblue4
        hi def hlLevel8 ctermfg=blue        guifg=darkslateblue
        hi def hlLevel9 ctermfg=darkmagenta guifg=darkviolet
    endif

 if slimv#getFiletype() =~ '.*\(clojure\|scheme\|racket\).*'

    syn region lispParen9 matchgroup=hlLevel9 start="`\=(" matchgroup=hlLevel9 end=")"  matchgroup=replPrompt end="^\S\+>" contains=TOP,@Spell
    syn region lispParen0 matchgroup=hlLevel8 start="`\=(" end=")" matchgroup=replPrompt end="^\S\+>"me=s-1,re=s-1 contains=TOP,lispParen0,lispParen1,lispParen2,lispParen3,lispParen4,lispParen5,lispParen6,lispParen7,lispParen8,NoInParens
    syn region lispParen1 matchgroup=hlLevel7 start="`\=(" end=")" matchgroup=replPrompt end="^\S\+>"me=s-1,re=s-1 contains=TOP,lispParen1,lispParen2,lispParen3,lispParen4,lispParen5,lispParen6,lispParen7,lispParen8,NoInParens
    syn region lispParen2 matchgroup=hlLevel6 start="`\=(" end=")" matchgroup=replPrompt end="^\S\+>"me=s-1,re=s-1 contains=TOP,lispParen2,lispParen3,lispParen4,lispParen5,lispParen6,lispParen7,lispParen8,NoInParens
    syn region lispParen3 matchgroup=hlLevel5 start="`\=(" end=")" matchgroup=replPrompt end="^\S\+>"me=s-1,re=s-1 contains=TOP,lispParen3,lispParen4,lispParen5,lispParen6,lispParen7,lispParen8,NoInParens
    syn region lispParen4 matchgroup=hlLevel4 start="`\=(" end=")" matchgroup=replPrompt end="^\S\+>"me=s-1,re=s-1 contains=TOP,lispParen4,lispParen5,lispParen6,lispParen7,lispParen8,NoInParens
    syn region lispParen5 matchgroup=hlLevel3 start="`\=(" end=")" matchgroup=replPrompt end="^\S\+>"me=s-1,re=s-1 contains=TOP,lispParen5,lispParen6,lispParen7,lispParen8,NoInParens
    syn region lispParen6 matchgroup=hlLevel2 start="`\=(" end=")" matchgroup=replPrompt end="^\S\+>"me=s-1,re=s-1 contains=TOP,lispParen6,lispParen7,lispParen8,NoInParens
    syn region lispParen7 matchgroup=hlLevel1 start="`\=(" end=")" matchgroup=replPrompt end="^\S\+>"me=s-1,re=s-1 contains=TOP,lispParen7,lispParen8,NoInParens
    syn region lispParen8 matchgroup=hlLevel0 start="`\=(" end=")" matchgroup=replPrompt end="^\S\+>"me=s-1,re=s-1 contains=TOP,lispParen8,NoInParens

    syn region lispParen9 matchgroup=hlLevel9 start="`\=\[" matchgroup=hlLevel9 end="\]"  matchgroup=replPrompt end="^\S\+>" contains=TOP,@Spell
    syn region lispParen0 matchgroup=hlLevel8 start="`\=\[" end="\]" matchgroup=replPrompt end="^\S\+>"me=s-1,re=s-1 contains=TOP,lispParen0,lispParen1,lispParen2,lispParen3,lispParen4,lispParen5,lispParen6,lispParen7,lispParen8,NoInParens
    syn region lispParen1 matchgroup=hlLevel7 start="`\=\[" end="\]" matchgroup=replPrompt end="^\S\+>"me=s-1,re=s-1 contains=TOP,lispParen1,lispParen2,lispParen3,lispParen4,lispParen5,lispParen6,lispParen7,lispParen8,NoInParens
    syn region lispParen2 matchgroup=hlLevel6 start="`\=\[" end="\]" matchgroup=replPrompt end="^\S\+>"me=s-1,re=s-1 contains=TOP,lispParen2,lispParen3,lispParen4,lispParen5,lispParen6,lispParen7,lispParen8,NoInParens
    syn region lispParen3 matchgroup=hlLevel5 start="`\=\[" end="\]" matchgroup=replPrompt end="^\S\+>"me=s-1,re=s-1 contains=TOP,lispParen3,lispParen4,lispParen5,lispParen6,lispParen7,lispParen8,NoInParens
    syn region lispParen4 matchgroup=hlLevel4 start="`\=\[" end="\]" matchgroup=replPrompt end="^\S\+>"me=s-1,re=s-1 contains=TOP,lispParen4,lispParen5,lispParen6,lispParen7,lispParen8,NoInParens
    syn region lispParen5 matchgroup=hlLevel3 start="`\=\[" end="\]" matchgroup=replPrompt end="^\S\+>"me=s-1,re=s-1 contains=TOP,lispParen5,lispParen6,lispParen7,lispParen8,NoInParens
    syn region lispParen6 matchgroup=hlLevel2 start="`\=\[" end="\]" matchgroup=replPrompt end="^\S\+>"me=s-1,re=s-1 contains=TOP,lispParen6,lispParen7,lispParen8,NoInParens
    syn region lispParen7 matchgroup=hlLevel1 start="`\=\[" end="\]" matchgroup=replPrompt end="^\S\+>"me=s-1,re=s-1 contains=TOP,lispParen7,lispParen8,NoInParens
    syn region lispParen8 matchgroup=hlLevel0 start="`\=\[" end="\]" matchgroup=replPrompt end="^\S\+>"me=s-1,re=s-1 contains=TOP,lispParen8,NoInParens

    syn region lispParen9 matchgroup=hlLevel9 start="`\={" matchgroup=hlLevel9 end="}"  matchgroup=replPrompt end="^\S\+>" contains=TOP,@Spell
    syn region lispParen0 matchgroup=hlLevel8 start="`\={" end="}" matchgroup=replPrompt end="^\S\+>"me=s-1,re=s-1 contains=TOP,lispParen0,lispParen1,lispParen2,lispParen3,lispParen4,lispParen5,lispParen6,lispParen7,lispParen8,NoInParens
    syn region lispParen1 matchgroup=hlLevel7 start="`\={" end="}" matchgroup=replPrompt end="^\S\+>"me=s-1,re=s-1 contains=TOP,lispParen1,lispParen2,lispParen3,lispParen4,lispParen5,lispParen6,lispParen7,lispParen8,NoInParens
    syn region lispParen2 matchgroup=hlLevel6 start="`\={" end="}" matchgroup=replPrompt end="^\S\+>"me=s-1,re=s-1 contains=TOP,lispParen2,lispParen3,lispParen4,lispParen5,lispParen6,lispParen7,lispParen8,NoInParens
    syn region lispParen3 matchgroup=hlLevel5 start="`\={" end="}" matchgroup=replPrompt end="^\S\+>"me=s-1,re=s-1 contains=TOP,lispParen3,lispParen4,lispParen5,lispParen6,lispParen7,lispParen8,NoInParens
    syn region lispParen4 matchgroup=hlLevel4 start="`\={" end="}" matchgroup=replPrompt end="^\S\+>"me=s-1,re=s-1 contains=TOP,lispParen4,lispParen5,lispParen6,lispParen7,lispParen8,NoInParens
    syn region lispParen5 matchgroup=hlLevel3 start="`\={" end="}" matchgroup=replPrompt end="^\S\+>"me=s-1,re=s-1 contains=TOP,lispParen5,lispParen6,lispParen7,lispParen8,NoInParens
    syn region lispParen6 matchgroup=hlLevel2 start="`\={" end="}" matchgroup=replPrompt end="^\S\+>"me=s-1,re=s-1 contains=TOP,lispParen6,lispParen7,lispParen8,NoInParens
    syn region lispParen7 matchgroup=hlLevel1 start="`\={" end="}" matchgroup=replPrompt end="^\S\+>"me=s-1,re=s-1 contains=TOP,lispParen7,lispParen8,NoInParens
    syn region lispParen8 matchgroup=hlLevel0 start="`\={" end="}" matchgroup=replPrompt end="^\S\+>"me=s-1,re=s-1 contains=TOP,lispParen8,NoInParens

 else

    syn region lispParen0           matchgroup=hlLevel0 start="`\=("  skip="|.\{-}|" end=")"  matchgroup=replPrompt end="^\S\+>"              contains=@replListCluster,lispParen1,replPrompt
    syn region lispParen1 contained matchgroup=hlLevel1 start="`\=("  skip="|.\{-}|" end=")"  matchgroup=replPrompt end="^\S\+>"me=s-1,re=s-1 contains=@replListCluster,lispParen2
    syn region lispParen2 contained matchgroup=hlLevel2 start="`\=("  skip="|.\{-}|" end=")"  matchgroup=replPrompt end="^\S\+>"me=s-1,re=s-1 contains=@replListCluster,lispParen3
    syn region lispParen3 contained matchgroup=hlLevel3 start="`\=("  skip="|.\{-}|" end=")"  matchgroup=replPrompt end="^\S\+>"me=s-1,re=s-1 contains=@replListCluster,lispParen4
    syn region lispParen4 contained matchgroup=hlLevel4 start="`\=("  skip="|.\{-}|" end=")"  matchgroup=replPrompt end="^\S\+>"me=s-1,re=s-1 contains=@replListCluster,lispParen5
    syn region lispParen5 contained matchgroup=hlLevel5 start="`\=("  skip="|.\{-}|" end=")"  matchgroup=replPrompt end="^\S\+>"me=s-1,re=s-1 contains=@replListCluster,lispParen6
    syn region lispParen6 contained matchgroup=hlLevel6 start="`\=("  skip="|.\{-}|" end=")"  matchgroup=replPrompt end="^\S\+>"me=s-1,re=s-1 contains=@replListCluster,lispParen7
    syn region lispParen7 contained matchgroup=hlLevel7 start="`\=("  skip="|.\{-}|" end=")"  matchgroup=replPrompt end="^\S\+>"me=s-1,re=s-1 contains=@replListCluster,lispParen8
    syn region lispParen8 contained matchgroup=hlLevel8 start="`\=("  skip="|.\{-}|" end=")"  matchgroup=replPrompt end="^\S\+>"me=s-1,re=s-1 contains=@replListCluster,lispParen9
    syn region lispParen9 contained matchgroup=hlLevel9 start="`\=("  skip="|.\{-}|" end=")"  matchgroup=replPrompt end="^\S\+>"me=s-1,re=s-1 contains=@replListCluster,lispParen0

 endif

else

  if slimv#getFiletype() !~ '.*clojure.*'
    syn region lispList             matchgroup=Delimiter start="("    skip="|.\{-}|" end=")"  matchgroup=replPrompt end="^\S\+>" contains=@replListCluster
    syn region lispBQList           matchgroup=PreProc   start="`("   skip="|.\{-}|" end=")"  matchgroup=replPrompt end="^\S\+>" contains=@replListCluster
  endif

endif

    syn match   replPrompt /^[^(]\S\+>/
    syn match   replPrompt /^(\S\+)>/
    hi def link replPrompt Type
endfunction
