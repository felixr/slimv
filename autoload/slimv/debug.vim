" Select a specific restart in debugger
function! slimv#debug#command( name, cmd )
    let ctx = slimv#context()
    if slimv#connectSwank()
        if ctx.sldb_level >= 0
            if bufname('%') != g:slimv_sldb_name
                call slimv#debug#openSldb()
            endif
            call slimv#command( 'python ' . a:cmd . '()' )
            call slimv#repl#refresh()
            if ctx.sldb_level < 0
                " Swank exited the debugger
                if bufname('%') != g:slimv_sldb_name
                    call slimv#debug#openSldb()
                endif
                call slimv#debug#quitSldb()
                call slimv#restoreFocus()
            else
                echomsg 'Debugger re-activated by the SWANK server.'
            endif
        else
            call slimv#error( "Debugger is not activated." )
        endif
    endif
endfunction

" Various debugger restarts
function! slimv#debug#abort()
    call slimv#debug#command( ":sldb-abort", "swank_invoke_abort" )
endfunction

function! slimv#debug#quit()
    call slimv#debug#command( ":throw-to-toplevel", "swank_throw_toplevel" )
endfunction

function! slimv#debug#continue()
    call slimv#debug#command( ":sldb-continue", "swank_invoke_continue" )
endfunction

" Restart execution of the frame with the same arguments
function! slimv#debug#restartFrame()
    let frame = slimv#debug#frame()
    if frame != ''
        call slimv#command( 'python swank_restart_frame("' . frame . '")' )
        call slimv#repl#refresh()
    endif
endfunction

" Debug thread selected from the Thread List
function! slimv#debug#thread()
    if slimv#connectSwank()
        let line = getline('.')
        let item = matchstr( line, '\d\+' )
        let item = input( 'Thread to debug: ', item )
        if item != ''
            call slimv#command( 'python swank_debug_thread(' . item . ')' )
            call slimv#repl#refresh()
        endif
    endif
endfunction

" Return frame number if we are in the Backtrace section of the debugger
function! slimv#debug#frame()
    let ctx = slimv#context()
    if ctx.swank_connected && ctx.sldb_level >= 0
        " Check if we are in SLDB
        let sldb_buf = bufnr( '^' . g:slimv_sldb_name . '$' )
        if sldb_buf != -1 && sldb_buf == bufnr( "%" )
            let bcktrpos = search( '^Backtrace:', 'bcnw' )
            let framepos = line( '.' )
            if matchstr( getline('.'), ctx.frame_def ) == ''
                let framepos = search( ctx.frame_def, 'bcnw' )
            endif
            if framepos > 0 && bcktrpos > 0 && framepos > bcktrpos
                let line = getline( framepos )
                let item = matchstr( line, ctx.frame_def )
                if item != ''
                    return substitute( item, '\s\|:', '', 'g' )
                endif
            endif
        endif
    endif
    return ''
endfunction


" Open a new SLDB buffer
function! slimv#debug#openSldb()
    call slimv#buffer#open( g:slimv_sldb_name )

    " Add keybindings valid only for the SLDB buffer
    noremap  <buffer> <silent>        <CR>   :call slimv#debug#handleEnterSldb()<CR>
    if g:slimv_keybindings == 1
        execute 'noremap <buffer> <silent> ' . g:slimv_leader.'a      :call slimv#debug#abort()<CR>'
        execute 'noremap <buffer> <silent> ' . g:slimv_leader.'q      :call slimv#debug#quit()<CR>'
        execute 'noremap <buffer> <silent> ' . g:slimv_leader.'n      :call slimv#debug#continue()<CR>'
        execute 'noremap <buffer> <silent> ' . g:slimv_leader.'N      :call slimv#debug#restartFrame()<CR>'
    elseif g:slimv_keybindings == 2
        execute 'noremap <buffer> <silent> ' . g:slimv_leader.'da     :call slimv#debug#abort()<CR>'
        execute 'noremap <buffer> <silent> ' . g:slimv_leader.'dq     :call slimv#debug#quit()<CR>'
        execute 'noremap <buffer> <silent> ' . g:slimv_leader.'dn     :call slimv#debug#continue()<CR>'
        execute 'noremap <buffer> <silent> ' . g:slimv_leader.'dr     :call slimv#debug#restartFrame()<CR>'
    endif

    " Set folding parameters
    setlocal foldmethod=marker
    setlocal foldmarker={{{,}}}
    setlocal foldtext=substitute(getline(v:foldstart),'{{{','','')
    call slimv#SetKeyword()
    if g:slimv_sldb_wrap
        setlocal wrap
    endif

    if version < 703
        " conceal mechanism is defined since Vim 7.3
        syn match Ignore /{{{/
        syn match Ignore /}}}/
    else
        setlocal conceallevel=3 concealcursor=nc
        syn match Comment /{{{/ conceal
        syn match Comment /}}}/ conceal
    endif
    syn match Type /^\s\{0,2}\d\{1,3}:/
    syn match Type /^\s\+in "\(.*\)" \(line\|byte\) \(\d\+\)$/
endfunction

" Quit Sldb
function! slimv#debug#quitSldb()
    " Clear the contents of the Sldb buffer
    setlocal modifiable
    silent! %d
    call slimv#endUpdate()
    b #
endfunction

" Handle normal mode 'Enter' keypress in the SLDB buffer
function! slimv#debug#handleEnterSldb()
    let line = getline('.')
    let ctx = slimv#context()
    if ctx.sldb_level >= 0
        " Check if Enter was pressed in a section printed by the SWANK debugger
        " The source specification is within a fold, so it has to be tested first
        let mlist = matchlist( line, '^\s\+in "\(.*\)" \(line\|byte\) \(\d\+\)$' )
        if len(mlist)
            if g:slimv_repl_split
                " Switch back to other window
                execute "wincmd p"
            endif
            " Jump to the file at the specified position
            if mlist[2] == 'line'
                exec ":edit +" . mlist[3] . " " . mlist[1]
            else
                exec ":edit +" . mlist[3] . "go " . mlist[1]
            endif
            return
        endif
        if foldlevel('.')
            " With a fold just toggle visibility
            normal za
            return
        endif
        let item = matchstr( line, ctx.frame_def )
        if item != ''
            let item = substitute( item, '\s\|:', '', 'g' )
            if search( '^Backtrace:', 'bnW' ) > 0
                " Display item-th frame
                call slimv#makeFold()
                silent execute 'python swank_frame_locals("' . item . '")'
                if slimv#getFiletype() != 'scheme' && g:slimv_impl != 'clisp'
                    " Not implemented for CLISP or scheme
                    silent execute 'python swank_frame_source_loc("' . item . '")'
                endif
                if slimv#getFiletype() == 'lisp' && g:slimv_impl != 'clisp' && g:slimv_impl != 'allegro' && g:slimv_impl != 'clojure'
                    " Not implemented for CLISP or other lisp dialects
                    " silent execute 'python swank_frame_call("' . item . '")'
                endif
                call slimv#repl#refresh()
                return
            endif
            if search( '^Restarts:', 'bnW' ) > 0
                " Apply item-th restart
                call slimv#debug#quitSldb()
                silent execute 'python swank_invoke_restart("' . ctx.sldb_level . '", "' . item . '")'
                call slimv#repl#refresh()
                return
            endif
        endif
    endif

    " No special treatment, perform the original function
    execute "normal! \<CR>"
endfunction

