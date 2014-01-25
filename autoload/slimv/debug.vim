" Select a specific restart in debugger
function! slimv#debug#command( name, cmd )
    let ctx = slimv#context()
    if slimv#connectSwank()
        if ctx.sldb_level >= 0
            if bufname('%') != g:slimv_sldb_name
                call slimv#openSldbBuffer()
            endif
            call slimv#command( 'python ' . a:cmd . '()' )
            call slimv#repl#refresh()
            if ctx.sldb_level < 0
                " Swank exited the debugger
                if bufname('%') != g:slimv_sldb_name
                    call slimv#openSldbBuffer()
                endif
                call slimv#quitSldb()
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
