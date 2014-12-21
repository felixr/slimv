" View the given file in a top/bottom/left/right split window
function! s:SplitView( filename )
    " Check if we have at least two windows used by slimv (have a window id assigned)
    let winnr1 = 0
    let winnr2 = 0
    for winnr in range( 1, winnr('$') )
        if getwinvar( winnr, 'id' ) != ''
            let winnr2 = winnr1
            let winnr1 = winnr
        endif
    endfor
    let ctx = slimv#context()
    if winnr1 > 0 && winnr2 > 0
        " We have already at least two windows used by slimv
        let winid = getwinvar( winnr(), 'id' )
        if bufnr("%") == ctx.current_buf && winid == ctx.current_win
            " Keep the current window on screen, use the other window for the new buffer
            if winnr1 != winnr()
                execute winnr1 . "wincmd w"
            else
                execute winnr2 . "wincmd w"
            endif
        endif
        execute "silent view! " . a:filename
    else
        " Generate unique window id for the old window if not yet done
        call slimv#MakeWindowId()
        " No windows yet, need to split
        if g:slimv_repl_split == 1
            execute "silent topleft sview! " . a:filename
        elseif g:slimv_repl_split == 2
            execute "silent botright sview! " . a:filename
        elseif g:slimv_repl_split == 3
            execute "silent topleft vertical sview! " . a:filename
        elseif g:slimv_repl_split == 4
            execute "silent botright vertical sview! " . a:filename
        else
            execute "silent view! " . a:filename
        endif
        " Generate unique window id for the new window as well
        call slimv#MakeWindowId()
    endif
    stopinsert
endfunction

" Open a buffer with the given name if not yet open, and switch to it
function! slimv#buffer#open( name )
    let ctx = slimv#context()
    let buf = bufnr( '^' . a:name . '$' )
    if buf == -1
        " Create a new buffer
        call s:SplitView( a:name )
    else
        if g:slimv_repl_split
            " Buffer is already created. Check if it is open in a window
            let win = bufwinnr( buf )
            if win == -1
                " Create windows
                call s:SplitView( a:name )
            else
                " Switch to the buffer's window
                if winnr() != win
                    execute win . "wincmd w"
                endif
            endif
        else
            execute "buffer " . buf
            stopinsert
        endif
    endif
    if ctx.current_buf != bufnr( "%" )
        " Keep track of the previous buffer and window
        let b:previous_buf = ctx.current_buf
        let b:previous_win = ctx.current_win
    endif
    setlocal buftype=nofile
    setlocal noswapfile
    setlocal modifiable
endfunction

" Write help text to current buffer at given line
function slimv#buffer#help( line )
    setlocal modifiable
    if exists( 'b:help_shown' )
        let help = b:help
    else
        let help = ['Press <F1> for Help']
    endif
    let b:help_line = a:line
    call append( b:help_line, help )
endfunction

" Toggle help
function slimv#buffer#toggleHelp()
    if exists( 'b:help_shown' )
        let lines = len( b:help )
        unlet b:help_shown
    else
        let lines = 1
        let b:help_shown = 1
    endif
    setlocal modifiable
    execute ":" . (b:help_line+1) . "," . (b:help_line+lines) . "d"
    call slimv#buffer#help( b:help_line )
    call slimv#endUpdate()
endfunction

