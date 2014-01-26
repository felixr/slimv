" Cross reference: who calls
function! slimv#xref#xrefBase( text, cmd )
    if slimv#connectSwank()
        let s = input( a:text, slimv#selectSymbol() )
        if s != ''
            call slimv#commandUsePackage( 'python swank_xref("' . s . '", "' . a:cmd . '")' )
        endif
    endif
endfunction

" Cross reference: who calls
function! slimv#xref#xrefCalls()
    call slimv#xref#xrefBase( 'Who calls: ', ':calls' )
endfunction

" Cross reference: who references
function! slimv#xref#xrefReferences()
    call slimv#xref#xrefBase( 'Who references: ', ':references' )
endfunction

" Cross reference: who sets
function! slimv#xref#xrefSets()
    call slimv#xref#xrefBase( 'Who sets: ', ':sets' )
endfunction

" Cross reference: who binds
function! slimv#xref#xrefBinds()
    call slimv#xref#xrefBase( 'Who binds: ', ':binds' )
endfunction

" Cross reference: who macroexpands
function! slimv#xref#xrefMacroexpands()
    call slimv#xref#xrefBase( 'Who macroexpands: ', ':macroexpands' )
endfunction

" Cross reference: who specializes
function! slimv#xref#xrefSpecializes()
    call slimv#xref#xrefBase( 'Who specializes: ', ':specializes' )
endfunction

" Cross reference: list callers
function! slimv#xref#xrefCallers()
    call slimv#xref#xrefBase( 'List callers: ', ':callers' )
endfunction

" Cross reference: list callees
function! slimv#xref#xrefCallees()
    call slimv#xref#xrefBase( 'List callees: ', ':callees' )
endfunction

