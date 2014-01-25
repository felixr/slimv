" Eval buffer lines in the given range
function! slimv#eval#region() range
    if v:register == '"'
        let lines = slimv#getRegion(a:firstline, a:lastline)
    else
        " Register was passed, so eval register contents instead
        let reg = getreg( v:register )
        let ending = slimv#CloseForm( [reg] )
        if ending == 'ERROR'
            call slimv#error( 'Too many or invalid closing parens in register "' . v:register )
            return
        endif
        let lines = [reg . ending]
    endif
    if lines != []
        if slimv#getFiletype() == 'scheme'
            " Swank-scheme requires us to pass a single s-expression
            " so embed buffer lines in a (begin ...) block
            let lines = ['(begin'] + lines + [')']
        endif
        call slimv#eval( lines )
    endif
endfunction

" Eval contents of the 's' register, optionally store it in another register
" Also optionally append a test form for quick testing (not stored in 'outreg')
" If the test form contains '%1' then it 'wraps' the selection around the '%1'
function! slimv#eval#selection( outreg, testform )
    let sel = slimv#getSelection()
    if a:outreg != '"'
        " Register was passed, so store current selection in register
        call setreg( a:outreg, sel )
    endif
    let lines = [sel]
    if a:testform != ''
        if match( a:testform, '%1' ) >= 0
            " We need to wrap the selection in the testform
            if match( sel, "\n" ) < 0
                " The selection is a single line, keep the wrapped form in one line
                let sel = substitute( a:testform, '%1', sel, 'g' )
                let lines = [sel]
            else
                " The selection is multiple lines, wrap it by adding new lines
                let lines = [strpart( a:testform, 0, match( a:testform, '%1' ) ),
                \            sel,
                \            strpart( a:testform, matchend( a:testform, '%1' ) )]
            endif
        else
            " Append optional test form at the tail
            let lines = lines + [a:testform]
        endif
    endif
    if bufname( "%" ) == g:slimv_repl_name
        " If this is the REPL buffer then go to EOF
        call s:EndOfBuffer()
    endif
    call slimv#eval( lines )
endfunction

" Eval Lisp form.
" Form given in the template is passed to Lisp without modification.
function! slimv#eval#form( template )
    let lines = [a:template]
    call slimv#eval( lines )
endfunction

" Eval Lisp form, with the given parameter substituted in the template.
" %1 string is substituted with par1
function! slimv#eval#form1( template, par1 )
    let p1 = escape( a:par1, '&' )
    let temp1 = substitute( a:template, '%1', p1, 'g' )
    let lines = [temp1]
    call slimv#eval( lines )
endfunction

" Eval Lisp form, with the given parameters substituted in the template.
" %1 string is substituted with par1
" %2 string is substituted with par2
function! slimv#eval#form2( template, par1, par2 )
    let p1 = escape( a:par1, '&' )
    let p2 = escape( a:par2, '&' )
    let temp1 = substitute( a:template, '%1', p1, 'g' )
    let temp2 = substitute( temp1,      '%2', p2, 'g' )
    let lines = [temp2]
    call slimv#eval( lines )
endfunction
" =====================================================================
"  Special functions
" =====================================================================

" Evaluate and test top level form at the cursor pos
function! slimv#eval#testDefun( testform )
    let outreg = v:register
    let oldpos = winsaveview()
    if !slimv#selectDefun()
        return
    endif
    call slimv#findPackage()
    call winrestview( oldpos ) 
    call slimv#eval#selection( outreg, a:testform )
endfunction

" Evaluate top level form at the cursor pos
function! slimv#eval#defun()
    call slimv#eval#testDefun( '' )
endfunction

" Evaluate the whole buffer
function! slimv#eval#buffer()
    if bufname( "%" ) == g:slimv_repl_name
        call slimv#error( "Cannot evaluate the REPL buffer." )
        return
    endif
    let lines = getline( 1, '$' )
    if slimv#getFiletype() == 'scheme'
        " Swank-scheme requires us to pass a single s-expression
        " so embed buffer lines in a (begin ...) block
        let lines = ['(begin'] + lines + [')']
    endif
    call slimv#eval( lines )
endfunction

" Return frame number if we are in the Backtrace section of the debugger
function! s:DebugFrame()
    if s:swank_connected && s:sldb_level >= 0
        " Check if we are in SLDB
        let sldb_buf = bufnr( '^' . g:slimv_sldb_name . '$' )
        if sldb_buf != -1 && sldb_buf == bufnr( "%" )
            let bcktrpos = search( '^Backtrace:', 'bcnw' )
            let framepos = line( '.' )
            if matchstr( getline('.'), s:frame_def ) == ''
                let framepos = search( s:frame_def, 'bcnw' )
            endif
            if framepos > 0 && bcktrpos > 0 && framepos > bcktrpos
                let line = getline( framepos )
                let item = matchstr( line, s:frame_def )
                if item != ''
                    return substitute( item, '\s\|:', '', 'g' )
                endif
            endif
        endif
    endif
    return ''
endfunction

" Evaluate and test current s-expression at the cursor pos
function! slimv#eval#testExp( testform )
    let outreg = v:register
    let oldpos = winsaveview()
    if !slimv#selectForm( 1 )
        return
    endif
    call slimv#findPackage()
    call winrestview( oldpos ) 
    call slimv#eval#selection( outreg, a:testform )
endfunction

" Evaluate current s-expression at the cursor pos
function! slimv#eval#exp()
    call slimv#eval#testExp( '' )
endfunction

" Evaluate expression entered interactively
function! slimv#interactiveEval()
    let frame = s:DebugFrame()
    if frame != ''
        " We are in the debugger, eval expression in the frame the cursor stands on
        let e = input( 'Eval in frame ' . frame . ': ' )
        if e != ''
            let result = slimv#commandGetResponse( ':eval-string-in-frame', 'python swank_eval_in_frame("' . e . '", ' . frame . ')', 0 )
            if result != ''
                redraw
                echo result
            endif
        endif
    else
        let e = input( 'Eval: ' )
        if e != ''
            call slimv#eval([e])
        endif
    endif
endfunction

