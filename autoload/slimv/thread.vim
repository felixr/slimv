" Create help text for Threads buffer
function slimv#thread#help()
    let help = []
    call add( help, '<F1>        : toggle this help' )
    call add( help, '<Backspace> : kill thread' )
    call add( help, g:slimv_leader . 'k          : kill thread' )
    call add( help, g:slimv_leader . 'd          : debug thread' )
    call add( help, g:slimv_leader . 'r          : refresh' )
    call add( help, g:slimv_leader . 'q          : quit' )
    return help
endfunction

" Kill thread(s) selected from the Thread List
function! slimv#thread#kill() range
    if slimv#connectSwank()
        if a:firstline == a:lastline
            let line = getline('.')
            let item = matchstr( line, '\d\+' )
            if bufname('%') != g:slimv_threads_name
                " We are not in the Threads buffer, not sure which thread to kill
                let item = input( 'Thread to kill: ', item )
            endif
            if item != ''
                call slimv#command( 'python swank_kill_thread(' . item . ')' )
                call slimv#repl#refresh()
            endif
            echomsg 'Thread ' . item . ' is killed.'
        else
            for line in getline(a:firstline, a:lastline)
                let item = matchstr( line, '\d\+' )
                if item != ''
                    call slimv#command( 'python swank_kill_thread(' . item . ')' )
                endif
            endfor
            call slimv#repl#refresh()
        endif
        call slimv#thread#list()
    endif
endfunction

" List current Lisp threads
function! slimv#thread#list()
    if slimv#connectSwank()
        call slimv#command( 'python swank_list_threads()' )
        call slimv#repl#refresh()
    endif
endfunction

" Open a new Threads buffer
function slimv#thread#open()
    call slimv#buffer#open(g:slimv_threads_name )
    let b:help = slimv#thread#help()

    " Add keybindings valid only for the Threads buffer
    "noremap  <buffer> <silent>        <CR>   :call slimv#handleEnterThreads()<CR>
    noremap  <buffer> <silent>        <F1>                        :call slimv#toggleHelp()<CR>
    noremap  <buffer> <silent> <Backspace>                        :call slimv#thread#kill()<CR>
    execute 'noremap <buffer> <silent> ' . g:slimv_leader.'r      :call slimv#thread#list()<CR>'
    execute 'noremap <buffer> <silent> ' . g:slimv_leader.'d      :call slimv#debug#thread()<CR>'
    execute 'noremap <buffer> <silent> ' . g:slimv_leader.'k      :call slimv#thread#kill()<CR>'
    execute 'noremap <buffer> <silent> ' . g:slimv_leader.'q      :call slimv#thread#quit()<CR>'
endfunction


" Quit Threads
function slimv#thread#quit()
    " Clear the contents of the Threads buffer
    setlocal modifiable
    silent! %d
    call slimv#endUpdate()
    b #
endfunction
