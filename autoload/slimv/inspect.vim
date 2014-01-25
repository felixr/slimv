
" Open a new Inspect buffer
function slimv#inspect#open()
    call SlimvOpenBuffer( g:slimv_inspect_name )
    let b:range_start = 0
    let b:range_end   = 0
    let b:help = slimv#inspect#help()

    " Add keybindings valid only for the Inspect buffer
    noremap  <buffer> <silent>        <F1>   :call slimv#toggleHelp()<CR>
    noremap  <buffer> <silent>        <CR>   :call slimv#inspect#handleEnter()<CR>
    noremap  <buffer> <silent> <Backspace>   :call slimv#sendSilent(['[-1]'])<CR>
    execute 'noremap <buffer> <silent> ' . g:slimv_leader.'q      :call slimv#inspect#quit(1)<CR>'

    if version < 703
        " conceal mechanism is defined since Vim 7.3
        syn region inspectItem   matchgroup=Ignore start="{\[\d\+\]\s*" end="\s*\[]}"
        syn region inspectAction matchgroup=Ignore start="{<\d\+>\s*"   end="\s*<>}"
    else
        syn region inspectItem   matchgroup=Ignore start="{\[\d\+\]\s*" end="\s*\[]}" concealends
        syn region inspectAction matchgroup=Ignore start="{<\d\+>\s*"   end="\s*<>}" concealends
        setlocal conceallevel=3 concealcursor=nc
    endif

    hi def link inspectItem   Special
    hi def link inspectAction String

    syn match Special /^\[<<\].*$/
    syn match Special /^\[--....--\]$/
endfunction

" Quit Inspector
function slimv#inspect#quit( force )
    " Clear the contents of the Inspect buffer
    if exists( 'b:inspect_pos' )
        unlet b:inspect_pos
    endif
    setlocal modifiable
    silent! %d
    call slimv#endUpdate()
    if a:force
        call slimv#command( 'python swank_quit_inspector()' )
    endif
    b #
endfunction

" Create help text for Inspect buffer
function slimv#inspect#help()
    let help = []
    call add( help, '<F1>        : toggle this help' )
    call add( help, '<Enter>     : open object or select action under cursor' )
    call add( help, '<Backspace> : go back to previous object' )
    call add( help, g:slimv_leader . 'q          : quit' )
    return help
endfunction

