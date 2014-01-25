" Select a specific restart in debugger
function! slimv#debug#command( name, cmd )
    if slimv#connectSwank()
        if s:sldb_level >= 0
            if bufname('%') != g:slimv_sldb_name
                call slimv#openSldbBuffer()
            endif
            call slimv#command( 'python ' . a:cmd . '()' )
            call slimv#repl#refresh()
            if s:sldb_level < 0
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
    let frame = s:DebugFrame()
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

