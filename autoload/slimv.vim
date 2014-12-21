"     \ 'indent' : '',                                         " Most recent indentation info
"     \ 'last_update' : 0,                                     " The last update time for the REPL buffer
"     \ 'save_updatetime' : &updatetime,                       " The original value for 'updatetime'
"     \ 'save_showmode' : &showmode,                           " The original value for 'showmode'
"     \ 'python_initialized' : 0,                              " Is the embedded Python initialized?
"     \ 'swank_connected' : 0,                                 " Is the SWANK server connected?
"     \ 'swank_package' : '',                                  " Package to use at the next SWANK eval
"     \ 'swank_form' : '',                                     " Form to send to SWANK
"     \ 'refresh_disabled' : 0,                                " Set this variable temporarily to avoid recursive REPL rehresh calls
"     \ 'sldb_level' : -1,                                     " Are we in the SWANK debugger? -1 == no, else SLDB level
"     \ 'break_on_exception' : 0,                              " Enable debugger break on exceptions (for ritz-swank)
"     \ 'compiled_file = '',                                  " Name of the compiled file
"     \ 'current_buf' : -1,                                    " Swank action was requested from this buffer
"     \ 'current_win' : 0,                                     " Swank action was requested from this window
"     \ 'arglist_line' : 0,                                    " Arglist was requested in this line ...
"     \ 'arglist_col' : 0,                                     " ... and column
"     \ 'inspect_path' : [],                                   " Inspection path of the current object
"     \ 'skip_sc' : 'synIDattr(synID(line("."), col("."), 0), "name") =~ "[Ss]tring\\|[Cc]omment"', " Skip matches inside string or comment
"     \ 'skip_q' : 'getline(".")[col(".")-2] == "\\"',         " Skip escaped double quote characters in matches
"     \ 'frame_def' : '^\s\{0,2}\d\{1,}:',                     " Regular expression to match SLDB restart or frame identifier
"     \ 'spec_indent' : 'flet\|labels\|macrolet\|symbol-macrolet',  " List of symbols need special indenting
"     \ 'spec_param' : 'defmacro',                             " List of symbols with special parameter list
"     \ 'binding_form' : 'let\|let\*',                         " List of symbols with binding list
"     \ 'win_id' : 0 }                                          " Counter for generating unique window id

let s:ctx = {
    \'swank_actions_pending': 0,
    \'indent': '',
    \'last_update': 0,
    \'save_updatetime': &updatetime,
    \'save_showmode': &showmode,
    \'python_initialized': 0,
    \'swank_connected': 0,
    \'swank_package': '',
    \'swank_form': '',
    \'refresh_disabled': 0,
    \'sldb_level': -1,
    \'break_on_exception': 0,
    \'compiled_file': '',
    \'current_buf': -1,
    \'current_win': 0,
    \'arglist_line': 0,
    \'arglist_col': 0,
    \'inspect_path': [],
    \'skip_sc': 'synIDattr(synID(line("."), col("."), 0), "name") =~ "[Ss]tring\\|[Cc]omment"',
    \'skip_q': 'getline(".")[col(".")-2] == "\\"',
    \'frame_def': '^\s\{0,2}\d\{1,}:',
    \'spec_indent': 'flet\|labels\|macrolet\|symbol-macrolet',
    \'spec_param': 'defmacro',
    \'binding_form': 'let\|let\*',
    \'repl_buf': -1,
    \'win_id': 0 }

function! slimv#context()
    return s:ctx
endfunction

" Get the filetype (Lisp dialect) used by Slimv
function! slimv#getFiletype()
    if &ft != ''
        " Return Vim filetype if defined
        return &ft
    endif

    if match( tolower( g:slimv_lisp ), 'clojure' ) >= 0 || match( tolower( g:slimv_lisp ), 'clj' ) >= 0
        " Must be Clojure
        return 'clojure'
    endif

    " We have no clue, guess its lisp
    return 'lisp'
endfunction

" Try to autodetect SWANK and build the command to start the SWANK server
function! slimv#swankCommand()
    if exists( 'g:slimv_swank_clojure' ) && slimv#getFiletype() =~ '.*clojure.*'
        return g:slimv_swank_clojure
    endif
    if exists( 'g:slimv_swank_scheme' ) && slimv#getFiletype() == 'scheme'
        return g:slimv_swank_scheme
    endif
    if exists( 'g:slimv_swank_cmd' )
        return g:slimv_swank_cmd
    endif

    if g:slimv_lisp == ''
        let g:slimv_lisp = input( 'Enter Lisp path (or fill g:slimv_lisp in your vimrc): ', '', 'file' )
    endif

    let cmd = SlimvSwankLoader()
    if cmd != ''
        if g:slimv_windows || g:slimv_cygwin
            return '!start /MIN ' . cmd
        elseif g:slimv_osx
            let result = system('osascript -e "exists application \"iterm\""')
                if result[:-2] == 'true'
                    let path2as = globpath( &runtimepath, 'ftplugin/**/iterm.applescript')
                    return '!' . path2as . ' ' . cmd
                else
                    " doubles quotes within 'cmd' need to become '\\\"'
                    return '!osascript -e "tell application \"Terminal\" to do script \"' . escape(escape(cmd, '"'), '\"') . '\""'
                endif
        elseif $STY != ''
            " GNU screen under Linux
            return '! screen -X eval "title swank" "screen ' . cmd . '" "select swank"'
        elseif $TMUX != ''
            " tmux under Linux
            return "! tmux new-window -d -n swank '" . cmd . "'"
        elseif $DISPLAY == ''
            " No X, no terminal multiplexer. Cannot run swank server.
            call slimv#errorWait( 'No X server. Run Vim from screen/tmux or start SWANK server manually.' )
            return ''
        else
            " Must be Linux
            return '! SWANK_PORT=' . g:swank_port . ' xterm -iconic -e ' . cmd . ' &'
        endif
    endif
    return ''
endfunction

" =====================================================================
"  General utility functions
" =====================================================================

" Display an error message
function! slimv#error(msg)
    echohl ErrorMsg
    echo a:msg
    echohl None
endfunction

" Display an error message and a question, return user response
function! slimv#errorAsk(msg, question)
    echohl ErrorMsg
    let answer = input( a:msg . a:question )
    echo ""
    echohl None
    return answer
endfunction

" Display an error message and wait for ENTER
function! slimv#errorWait(msg)
    call slimv#errorAsk( a:msg, " Press ENTER to continue." )
endfunction

" Shorten long messages to fit status line
function! slimv#shortEcho(msg)
    let saved=&shortmess
    set shortmess+=T
    exe "normal :echomsg a:msg\n"
    let &shortmess=saved
endfunction

" Remember the end of the REPL buffer: user may enter commands here
" Also remember the prompt, because the user may overwrite it
function! slimv#markBufferEnd(force)
    if exists( 'b:slimv_repl_buffer' )
	setlocal nomodified
	call slimv#repl#moveToEnd(a:force)
	let b:repl_prompt_line = line( '$' )
	let b:repl_prompt_col = len( getline('$') ) + 1
	let b:repl_prompt = getline( b:repl_prompt_line )
    endif
endfunction


" Save caller buffer identification
function! slimv#beginUpdate()
    call slimv#MakeWindowId()
    let s:ctx.current_buf = bufnr( "%" )
    let s:ctx.current_win = getwinvar( winnr(), 'id' )
endfunction

" Switch to the buffer/window that was active before a swank action
function! slimv#restoreFocus(hide_current_buf)
    if exists("b:previous_buf")
        let new_buf = b:previous_buf
        let new_win = b:previous_win
    else
        let new_buf = s:ctx.current_buf
        let new_win = s:ctx.current_win
    endif
    let buf = bufnr( "%" )
    let win = getwinvar( winnr(), 'id' )
    if a:hide_current_buf
        set nobuflisted
        b #
    endif
    if winnr('$') > 1 && new_win != '' && new_win != win
        " Switch to the caller window
        call slimv#SwitchToWindow( new_win )
    endif
    if s:ctx.new_buf >= 0 && buf != s:ctx.new_buf
        " Switch to the caller buffer
        execute "buf " . new_buf
    endif
endfunction

function! slimv#isRefreshDisabled()
    return s:ctx.refresh_disabled
endfunction


" Handle response coming from the SWANK listener
function! slimv#swankResponse()
    let s:ctx.swank_ok_result = ''
    let s:ctx.refresh_disabled = 1
    silent execute 'python swank.output(1)'
    let s:ctx.refresh_disabled = 0
    let s:ctx.swank_action = ''
    let s:ctx.swank_result = ''
    silent execute 'python swank.response("")'

    if s:ctx.swank_action == ':describe-symbol' && s:ctx.swank_result != ''
        echo substitute(s:ctx.swank_result,'^\n*','','')
    elseif s:ctx.swank_ok_result != ''
        " Display the :ok result also in status bar in case the REPL buffer is not shown
        let s:ctx.swank_ok_result = substitute(s:ctx.swank_ok_result,"\<LF>",'','g')
        if s:ctx.swank_ok_result == ''
            call SlimvShortEcho( '=> OK' )
        else
            call SlimvShortEcho( '=> ' . s:swank_ok_result )
        endif
    endif
    if s:ctx.swank_actions_pending
        let s:ctx.last_update = -1
    elseif s:ctx.last_update < 0
        " Remember the time when all actions are processed
        let s:ctx.last_update = localtime()
    endif
    if s:ctx.swank_actions_pending == 0 && s:ctx.last_update >= 0 && s:ctx.last_update < localtime() - 2
        " All SWANK output handled long ago, restore original update frequency
        let &updatetime = s:ctx.save_updatetime
    else
        " SWANK output still pending, keep higher update frequency
        let &updatetime = g:slimv_updatetime
    endif
endfunction

" Execute the given command and write its output at the end of the REPL buffer
function! slimv#command( cmd )
    silent execute a:cmd
    if g:slimv_updatetime < &updatetime
        " Update more frequently until all swank responses processed
        let &updatetime = g:slimv_updatetime
        let s:ctx.last_update = -1
    endif
endfunction

" Execute the given SWANK command, wait for and return the response
function! slimv#commandGetResponse( name, cmd, timeout )
    let s:ctx.refresh_disabled = 1
    call slimv#command( a:cmd )
    let s:ctx.swank_action = ''
    let s:ctx.swank_result = ''
    let starttime = localtime()
    let cmd_timeout = a:timeout
    if cmd_timeout == 0
        let cmd_timeout = 3
    endif
    while s:ctx.swank_action == '' && localtime()-starttime < cmd_timeout
        python swank.output( 0 )
        silent execute 'python swank.response("' . a:name . '")'
    endwhile
    let s:ctx.refresh_disabled = 0
    return s:ctx.swank_result
endfunction

" This function re-triggers the CursorHold event
" after refreshing the REPL buffer
function! slimv#timer()
    if v:count > 0
        " Skip refreshing if the user started a command prefixed with a count
        return
    endif
    " We don't want autocommands trigger during the quick switch to/from the REPL buffer
    noautocmd call slimv#repl#refresh()
    if mode() == 'i' || mode() == 'I' || mode() == 'r' || mode() == 'R'
        if bufname('%') != g:slimv_sldb_name && bufname('%') != g:slimv_inspect_name && bufname('%') != g:slimv_threads_name
            " Put '<Insert>' twice into the typeahead buffer, which should not do anything
            " just switch to replace/insert mode then back to insert/replace mode
            " But don't do this for readonly buffers
            call feedkeys("\<insert>\<insert>")
        endif
    else
        " Put an incomplete 'f' command and an Esc into the typeahead buffer
        call feedkeys("f\e", 'n')
    endif
endfunction

" Switch refresh mode on:
" refresh REPL buffer on frequent Vim events
function! slimv#refreshModeOn()
    augroup SlimvCursorHold
        au!
        execute "au CursorHold   * :call slimv#timer()"
        execute "au CursorHoldI  * :call slimv#timer()"
    augroup END
endfunction

" Switch refresh mode off
function! slimv#refreshModeOff()
    augroup SlimvCursorHold
        au!
    augroup END
endfunction

" End updating an otherwise readonly buffer
function slimv#endUpdate()
    setlocal nomodifiable
    setlocal nomodified
endfunction
"
" Open SLDB buffer and place cursor on the given frame
function slimv#gotoFrame(frame)
    call slimv#debug#openSldb()
    let bcktrpos = search( '^Backtrace:', 'bcnw' )
    let line = getline( '.' )
    let item = matchstr( line, '^\s*' . a:frame .  ':' )
    if item != '' && line('.') > bcktrpos
        " Already standing on the frame
        return
    endif

    " Must locate the frame starting from the 'Backtrace:' string
    call search( '^Backtrace:', 'bcw' )
    call search( '^\s*' . a:frame .  ':', 'w' )
endfunction

" Set 'iskeyword' option depending on file type
function! slimv#SetKeyword()
    if slimv#getFiletype() =~ '.*\(clojure\|scheme\|racket\).*'
        setlocal iskeyword+=+,-,*,/,%,<,=,>,:,$,?,!,@-@,94,~,#,\|,&
    else
        setlocal iskeyword+=+,-,*,/,%,<,=,>,:,$,?,!,@-@,94,~,#,\|,&,.,{,},[,]
    endif
endfunction

" Select symbol under cursor and return it
function! slimv#selectSymbol()
    call slimv#SetKeyword()
    let oldpos = winsaveview()
    if col('.') > 1 && getline('.')[col('.')-1] =~ '\s'
        normal! h
    endif
    let symbol = expand('<cword>')
    call winrestview(oldpos)
    return symbol
endfunction

" Select symbol with possible prefixes under cursor and return it
function! slimv#selectSymbolExt()
    let save_iskeyword = &iskeyword
    call slimv#SetKeyword()
    setlocal iskeyword+='
    let symbol = expand('<cword>')
    let &iskeyword = save_iskeyword
    return symbol
endfunction

" Select bottom level form the cursor is inside and copy it to register 's'
function! slimv#selectForm( extended )
    if slimv#getFiletype() == 'r'
        silent! normal va(
        silent! normal "sY
        return 1
    endif
    " Search the opening '(' if we are standing on a special form prefix character
    let c = col( '.' ) - 1
    let firstchar = getline( '.' )[c]
    while c < len( getline( '.' ) ) && match( "'`#", getline( '.' )[c] ) >= 0
        normal! l
        let c = c + 1
    endwhile
    normal! va(
    let p1 = getpos('.')
    normal! o
    let p2 = getpos('.')
    if firstchar != '(' && p1[1] == p2[1] && (p1[2] == p2[2] || p1[2] == p2[2]+1)
        " Empty selection and no paren found, select current word instead
        normal! aw
    elseif a:extended || firstchar != '('
        " Handle '() or #'() etc. type special syntax forms (but stop at prompt)
        let c = col( '.' ) - 2
        while c >= 0 && match( ' \t()>', getline( '.' )[c] ) < 0
            normal! h
            let c = c - 1
        endwhile
    endif
    silent normal! "sy
    let sel = slimv#getSelection()
    if sel == ''
        call slimv#error( "Form is empty." )
        return 0
    elseif sel == '(' || sel == '[' || sel == '{'
        call slimv#error( "Form is unbalanced." )
        return 0
    else
        return 1
    endif
endfunction

" Find starting '(' of a top level form
function! slimv#findDefunStart()
    let l = line( '.' )
    let matchb = max( [l-200, 1] )
    if slimv#getFiletype() == 'r'
        while searchpair( '(', '', ')', 'bW', s:ctx.skip_sc, matchb ) || searchpair( '{', '', '}', 'bW', s:ctx.skip_sc, matchb ) || searchpair( '\[', '', '\]', 'bW', s:ctx.skip_sc, matchb )
        endwhile
    else
        while searchpair( '(', '', ')', 'bW', s:ctx.skip_sc, matchb )
        endwhile
    endif
endfunction

" Select top level form the cursor is inside and copy it to register 's'
function! slimv#selectDefun()
    call slimv#findDefunStart()
    if slimv#getFiletype() == 'r'
        " The cursor must be on the enclosing paren character
        silent! normal v%"sY
        return 1
    else
        return slimv#selectForm( 1 )
    endif
endfunction

" Return the contents of register 's'
function! slimv#getSelection()
    return getreg( 's' )
endfunction

" Find language specific package/namespace definition backwards
" Set it as the current package for the next swank action
function! slimv#findPackage()
    if !g:slimv_package || slimv#getFiletype() == 'scheme'
        return
    endif
    let oldpos = winsaveview()
    let save_ic = &ignorecase
    set ignorecase
    if slimv#getFiletype() =~ '.*clojure.*'
        let string = '\(in-ns\|ns\)'
    else
        let string = '\(cl:\|common-lisp:\|\)in-package'
    endif
    let found = 0
    let searching = search( '(\s*' . string . '\s', 'bcW' )
    while searching
        " Search for the previos occurrence
        if synIDattr( synID( line('.'), col('.'), 0), 'name' ) !~ '[Ss]tring\|[Cc]omment'
            " It is not inside a comment or string
            let found = 1
            break
        endif
        let searching = search( '(\s*' . string . '\s', 'bW' )
    endwhile
    if found
        " Find the package name with all folds open
        normal! zn
        silent normal! ww
        let l:packagename_tokens = split(expand('<cWORD>'),')\|\s')
        normal! zN
        if l:packagename_tokens != []
            " Remove quote character from package name
            let s:ctx.swank_package = substitute( l:packagename_tokens[0], "'", '', '' )
        else
            let s:ctx.swank_package = ''
        endif
    endif
    let &ignorecase = save_ic
    call winrestview( oldpos )
endfunction

" Execute the given SWANK command with current package defined
function! slimv#commandUsePackage( cmd )
    call slimv#findPackage()
    let s:ctx.refresh_disabled = 1
    call slimv#command( a:cmd )
    let s:ctx.swank_package = ''
    let s:ctx.refresh_disabled = 0
    call slimv#repl#refresh()
endfunction

" Initialize embedded Python and connect to SWANK server
function! slimv#connectSwank()
    if !s:ctx.python_initialized
        if ! has('python')
            call slimv#errorWait( 'Vim is compiled without the Python feature or Python is not installed. Unable to run SWANK client.' )
            return 0
        endif
        python import vim
        " execute 'pyfile ' . g:swank_path
        execute 'python from swank import *'
        let s:ctx.python_initialized = 1
    endif

    if !s:ctx.swank_connected
        let s:ctx.swank_version = ''
        let s:ctx.lisp_version = ''
        if g:swank_host == ''
            let g:swank_host = input( 'Swank server host name: ', 'localhost' )
        endif
        execute 'python swank_connect("' . g:swank_host . '", ' . g:swank_port . ', "result" )'
        if result != '' && ( g:swank_host == 'localhost' || g:swank_host == '127.0.0.1' )
            " SWANK server is not running, start server if possible
            let swank = slimv#swankCommand()
            if swank != ''
                redraw
                echon "\rStarting SWANK server..."
                silent execute swank
                let starttime = localtime()
                while result != '' && localtime()-starttime < g:slimv_timeout
                    sleep 500m
                    execute 'python swank_connect("' . g:swank_host . '", ' . g:swank_port . ', "result" )'
                endwhile
                redraw!
            endif
        endif
        if result != ''
            " Display connection error message
            call slimv#errorWait( result )
            return 0
        endif

        " Connected to SWANK server
        redraw
        echon "\rGetting SWANK connection info..."
        let starttime = localtime()
        while s:ctx.swank_version == '' && localtime()-starttime < g:slimv_timeout
            call slimv#swankResponse()
        endwhile
        if s:ctx.swank_version >= '2011-12-04'
            python swank_require('swank-repl')
            call slimv#swankResponse()
        endif
        if s:ctx.swank_version >= '2008-12-23'
            call slimv#commandGetResponse( ':create-repl', 'python swank_create_repl()', g:slimv_timeout )
        endif
        let s:ctx.swank_connected = 1
        if g:slimv_simple_compl == 0
            python swank_require('swank-fuzzy')
            call slimv#swankResponse()
        endif
        redraw
        echon "\rConnected to SWANK server on port " . g:swank_port . "."
        if exists( "g:swank_block_size" ) && slimv#getFiletype() == 'lisp'
            " Override SWANK connection output buffer size
            let cmd = "(progn (setf (slot-value (swank::connection.user-output swank::*emacs-connection*) 'swank-backend::buffer)"
            let cmd = cmd . " (make-string " . g:swank_block_size . ")) nil)"
            call slimv#send( [cmd], 0, 1 )
        endif
        if exists( "*b:slimv#replInit" )
            " Perform implementation specific REPL initialization if supplied
            call b:slimv#replInit( s:ctx.lisp_version )
        endif
    endif
    return s:ctx.swank_connected
endfunction

" Send argument to Lisp server for evaluation
function! slimv#send( args, echoing, output )
    call slimv#beginUpdate()

    if ! slimv#connectSwank()
        return
    endif

    " Send the lines to the client for evaluation
    let text = join( a:args, "\n" ) . "\n"

    let s:ctx.refresh_disabled = 1
    let s:ctx.swank_form = text
    if a:output
        call slimv#repl#open()
    endif
    if a:echoing && g:slimv_echolines != 0
        if g:slimv_echolines > 0
            let nlpos = match( s:ctx.swank_form, "\n", 0, g:slimv_echolines )
            if nlpos > 0
                " Echo only the first g:slimv_echolines number of lines
                let trimmed = strpart( s:ctx.swank_form, nlpos )
                let s:ctx.swank_form = strpart( s:ctx.swank_form, 0, nlpos )
                let ending = slimv#CloseForm( [s:ctx.swank_form] )
                if ending != 'ERROR'
                    if substitute( trimmed, '\s\|\n', '', 'g' ) == ''
                        " Only whitespaces are trimmed
                        let s:ctx.swank_form = s:ctx.swank_form . ending . "\n"
                    else
                        " Valuable characters trimmed, indicate it by printing "..."
                        let s:ctx.swank_form = s:ctx.swank_form . " ..." . ending . "\n"
                    endif
                endif
            endif
        endif
        let lines = split( s:ctx.swank_form, '\n', 1 )
        call append( '$', lines )
        let s:ctx.swank_form = text
    elseif a:output
        " Open a new line for the output
        call append( '$', '' )
    endif
    if a:output
        call slimv#markBufferEnd(0)
    endif
    call slimv#command( 'python swank_input("s:ctx.swank_form")' )
    let s:ctx.swank_package = ''
    let s:ctx.refresh_disabled = 0
    call slimv#refreshModeOn()
    call slimv#repl#refresh()
endfunction

" Eval arguments in Lisp REPL
function! slimv#eval( args )
    call slimv#send( a:args, 1, 1 )
endfunction

" Send argument silently to SWANK
function! slimv#sendSilent( args )
    call slimv#send( a:args, 0, 0 )
endfunction

" Return missing parens, double quotes, etc to properly close form
function! slimv#CloseForm( lines )
    let form = join( a:lines, "\n" )
    let end = ''
    let i = 0
    while i < len( form )
        if form[i] == '"'
            " Inside a string
            let end = '"' . end
            let i += 1
            while i < len( form )
                if form[i] == '\'
                    " Ignore next character
                    let i += 2
                elseif form[i] == '"'
                    let end = end[1:]
                    break
                else
                    let i += 1
                endif
            endwhile
        elseif form[i] == ';'
            " Inside a comment
            let end = "\n" . end
            let cend = match(form, "\n", i)
            if cend == -1
                break
            endif
            let i = cend
            let end = end[1:]
        else
            " We are outside of strings and comments, now we shall count parens
            if form[i] == '('
                let end = ')' . end
            elseif form[i] == '[' && slimv#getFiletype() =~ '.*\(clojure\|scheme\|racket\).*'
                let end = ']' . end
            elseif form[i] == '{' && slimv#getFiletype() =~ '.*\(clojure\|scheme\|racket\).*'
                let end = '}' . end
            elseif form[i] == ')' || ((form[i] == ']' || form[i] == '}') && slimv#getFiletype() =~ '.*\(clojure\|scheme\|racket\).*')
                if len( end ) == 0 || end[0] != form[i]
                    " Oops, too many closing parens or invalid closing paren
                    return 'ERROR'
                endif
                let end = end[1:]
            endif
        endif
        let i += 1
    endwhile
    return end
endfunction

" Some multi-byte characters screw up the built-in lispindent()
" This function is a wrapper that tries to fix it
" TODO: implement custom indent procedure and omit lispindent()
function slimv#lispindent( lnum )
    set lisp
    let li = lispindent( a:lnum )
    set nolisp
    let backline = max([a:lnum-g:slimv_indent_maxlines, 1])
    let oldpos = winsaveview()
    normal! 0
    " Find containing form
    let [lhead, chead] = searchpairpos( '(', '', ')', 'bW', s:ctx.skip_sc, backline )
    if lhead == 0
        " No containing form, lispindent() is OK
        call winrestview( oldpos )
        return li
    endif
    " Find outer form
    let [lparent, cparent] = searchpairpos( '(', '', ')', 'bW', s:ctx.skip_sc, backline )
    call winrestview( oldpos )
    if lparent == 0 || lhead != lparent
        " No outer form or starting above inner form, lispindent() is OK
        return li
    endif
    " Count extra bytes before the function header
    let header = strpart( getline( lparent ), 0 )
    let total_extra = 0
    let extra = 0
    let c = 0
    while a:lnum > 0 && c < chead-1
        let bytes = byteidx( header, c+1 ) - byteidx( header, c )
        if bytes > 1
            let total_extra = total_extra + bytes - 1
            if c >= cparent && extra < 10
                " Extra bytes in the outer function header
                let extra = extra + bytes - 1
            endif
        endif
        let c = c + 1
    endwhile
    if total_extra == 0
        " No multi-byte character, lispindent() is OK
        return li
    endif
    " In some cases ending spaces add up to lispindent() if there are multi-byte characters
    let ending_sp = len( matchstr( getline( lparent ), ' *$' ) )
    " Determine how wrong lispindent() is based on the number of extra bytes
    " These values were determined empirically
    if lparent == a:lnum - 1
        " Function header is in the previous line
        if extra == 0 && total_extra > 1
            let ending_sp = ending_sp + 1
        endif
        return li + [0, 1, 0, -3, -3, -3, -5, -5, -7, -7, -8][extra] - ending_sp
    else
        " Function header is in an upper line
        if extra == 0 || total_extra == extra
            let ending_sp = 0
        endif
        return li + [0, 1, 0, -2, -2, -3, -3, -3, -3, -3, -3][extra] - ending_sp
    endif
endfunction

" Return Lisp source code indentation at the given line
function! slimv#indent( lnum )
    if &autoindent == 0 || a:lnum <= 1
        " Start of the file
        return 0
    endif
    let pnum = prevnonblank(a:lnum - 1)
    if pnum == 0
        " Hit the start of the file, use zero indent.
        return 0
    endif
    let oldpos = winsaveview()
    let linenum = a:lnum

    " Handle multi-line string
    let plen = len( getline( pnum ) )
    if synIDattr( synID( pnum, plen, 0), 'name' ) =~ '[Ss]tring' && getline(pnum)[plen-1] != '"'
        " Previous non-blank line ends with an unclosed string, so this is a multi-line string
        let [l, c] = searchpairpos( '"', '', '"', 'bnW', s:ctx.skip_q )
        if l == pnum && c > 0
            " Indent to the opening double quote (if found)
            return c
        else
            return slimv#lispindent( linenum )
        endif
    endif
    if synIDattr( synID( pnum, 1, 0), 'name' ) =~ '[Ss]tring' && getline(pnum)[0] != '"'
        " Previous non-blank line is the last line of a multi-line string
        call cursor( pnum, 1 )
        " First find the end of the multi-line string (omit \" characters)
        let [lend, cend] = searchpos( '[^\\]"', 'nW' )
        if lend > 0 && strpart(getline(lend), cend+1) =~ '(\|)\|\[\|\]\|{\|}'
            " Structural change after the string, no special handling
        else
            " Find the start of the multi-line string (omit \" characters)
            let [l, c] = searchpairpos( '"', '', '"', 'bnW', s:ctx.skip_q )
            if l > 0 && strpart(getline(l), 0, c-1) =~ '^\s*$'
                " Nothing else before the string: indent to the opening "
                call winrestview( oldpos )
                return c - 1
            endif
            if l > 0
                " Pretend that we are really after the first line of the multi-line string
                let pnum = l
                let linenum = l + 1
            endif
        endif
        call winrestview( oldpos )
    endif

    " Handle special indentation style for flet, labels, etc.
    " When searching for containing forms, don't go back
    " more than g:slimv_indent_maxlines lines.
    let backline = max([pnum-g:slimv_indent_maxlines, 1])
    let indent_keylists = g:slimv_indent_keylists

    " Check if the previous line actually ends with a multi-line subform
    let parent = pnum
    let [l, c] = searchpos( ')', 'bW' )
    if l == pnum
        let [l, c] = searchpairpos( '(', '', ')', 'bW', s:ctx.skip_sc, backline )
        if l > 0
            " Make sure it is not a top level form and the containing form starts in the same line
            let [l2, c2] = searchpairpos( '(', '', ')', 'bW', s:ctx.skip_sc, backline )
            if l2 == l
                " Remember the first line of the multi-line form
                let parent = l
            endif
        endif
    endif
    call winrestview( oldpos )

    " Find beginning of the innermost containing form
    normal! 0
    let [l, c] = searchpairpos( '(', '', ')', 'bW', s:ctx.skip_sc, backline )
    if l > 0
        if slimv#getFiletype() =~ '.*\(clojure\|scheme\|racket\).*'
            " Is this a clojure form with [] binding list?
            call winrestview( oldpos )
            let [lb, cb] = searchpairpos( '\[', '', '\]', 'bW', s:ctx.skip_sc, backline )
            if lb >= l && (lb > l || cb > c)
                call winrestview( oldpos )
                return cb
            endif
        endif
        " Is this a form with special indentation?
        let line = strpart( getline(l), c-1 )
        if match( line, '\c^(\s*\('.s:ctx.spec_indent.'\)\>' ) >= 0
            " Search for the binding list and jump to its end
            if search( '(' ) > 0
                exe 'normal! %'
                if line('.') == pnum
                    " We are indenting the first line after the end of the binding list
                    call winrestview( oldpos )
                    return c + 1
                endif
            endif
        elseif l == pnum
            " If the containing form starts above this line then find the
            " second outer containing form (possible start of the binding list)
            let [l2, c2] = searchpairpos( '(', '', ')', 'bW', s:ctx.skip_sc, backline )
            if l2 > 0
                let line2 = strpart( getline(l2), c2-1 )
                if match( line2, '\c^(\s*\('.s:ctx.spec_param.'\)\>' ) >= 0
                    if search( '(' ) > 0
                        if line('.') == l && col('.') == c
                            " This is the parameter list of a special form
                            call winrestview( oldpos )
                            return c
                        endif
                    endif
                endif
                if slimv#getFiletype() !~ '.*clojure.*'
                    if l2 == l && match( line2, '\c^(\s*\('.s:ctx.binding_form.'\)\>' ) >= 0
                        " Is this a lisp form with binding list?
                        call winrestview( oldpos )
                        return c
                    endif
                    if match( line2, '\c^(\s*cond\>' ) >= 0 && match( line, '\c^(\s*t\>' ) >= 0
                        " Is this the 't' case for a 'cond' form?
                        call winrestview( oldpos )
                        return c
                    endif
                    if match( line2, '\c^(\s*defpackage\>' ) >= 0
                        let indent_keylists = 0
                    endif
                endif
                " Go one level higher and check if we reached a special form
                let [l3, c3] = searchpairpos( '(', '', ')', 'bW', s:ctx.skip_sc, backline )
                if l3 > 0
                    " Is this a form with special indentation?
                    let line3 = strpart( getline(l3), c3-1 )
                    if match( line3, '\c^(\s*\('.s:ctx.spec_indent.'\)\>' ) >= 0
                        " This is the first body-line of a binding
                        call winrestview( oldpos )
                        return c + 1
                    endif
                    if match( line3, '\c^(\s*defsystem\>' ) >= 0
                        let indent_keylists = 0
                    endif
                    " Finally go to the topmost level to check for some forms with special keyword indenting
                    let [l4, c4] = searchpairpos( '(', '', ')', 'brW', s:ctx.skip_sc, backline )
                    if l4 > 0
                        let line4 = strpart( getline(l4), c4-1 )
                        if match( line4, '\c^(\s*defsystem\>' ) >= 0
                            let indent_keylists = 0
                        endif
                    endif
                endif
            endif
        endif
    endif

    " Restore all cursor movements
    call winrestview( oldpos )

    " Check if the current form started in the previous nonblank line
    if l == parent
        " Found opening paren in the previous line
        let line = getline(l)
        let form = strpart( line, c )
        " Determine the length of the function part up to the 1st argument
        let funclen = matchend( form, '\s*\S*\s*' ) + 1
        " Contract strings, remove comments
        let form = substitute( form, '".\{-}[^\\]"', '""', 'g' )
        let form = substitute( form, ';.*$', '', 'g' )
        " Contract subforms by replacing them with a single character
        let f = ''
        while form != f
            let f = form
            let form = substitute( form, '([^()]*)',     '0', 'g' )
            let form = substitute( form, '([^()]*$',     '0', 'g' )
            let form = substitute( form, '\[[^\[\]]*\]', '0', 'g' )
            let form = substitute( form, '\[[^\[\]]*$',  '0', 'g' )
            let form = substitute( form, '{[^{}]*}',     '0', 'g' )
            let form = substitute( form, '{[^{}]*$',     '0', 'g' )
        endwhile
        " Find out the function name
        let func = matchstr( form, '\<\k*\>' )
        " If it's a keyword, keep the indentation straight
        if indent_keylists && strpart(func, 0, 1) == ':'
            if form =~ '^:\S*\s\+\S'
                " This keyword has an associated value in the same line
                return c
            else
                " The keyword stands alone in its line with no associated value
                return c + 1
            endif
        endif
        if slimv#getFiletype() =~ '.*clojure.*'
            " Fix clojure specific indentation issues not handled by the default lisp.vim
            if match( func, 'defn$' ) >= 0
                return c + 1
            endif
        else
            if match( func, 'defgeneric$' ) >= 0 || match( func, 'defsystem$' ) >= 0 || match( func, 'aif$' ) >= 0
                return c + 1
            endif
        endif
        " Remove package specification
        let func = substitute(func, '^.*:', '', '')
        if func != '' && s:ctx.swank_connected
            " Look how many arguments are on the same line
            " If an argument is actually a multi-line subform, then replace it with a single character
            let form = substitute( form, "([^()]*$", '0', 'g' )
            let form = substitute( form, "[()\\[\\]{}#'`,]", '', 'g' )
            let args_here = len( split( form ) ) - 1
            " Get swank indent info
            let s:ctx.indent = ''
            silent execute 'python get_indent_info("' . func . '")'
            if s:ctx.indent != '' && s:ctx.indent == args_here
                " The next one is an &body argument, so indent by 2 spaces from the opening '('
                return c + 1
            endif
            let llen = len( line )
            if synIDattr( synID( l, llen, 0), 'name' ) =~ '[Ss]tring' && line[llen-1] != '"'
                " Parent line ends with a multi-line string
                " lispindent() fails to handle it correctly
                if s:ctx.indent == '' && args_here > 0
                    " No &body argument, ignore lispindent() and indent to the 1st argument
                    return c + funclen - 1
                endif
            endif
        endif
    endif

    " Use default Lisp indenting
    let li = slimv#lispindent(linenum)
    let line = strpart( getline(linenum-1), li-1 )
    let gap = matchend( line, '^(\s\+\S' )
    if gap >= 0
        " Align to the gap between the opening paren and the first atom
        return li + gap - 2
    endif
    return li
endfunction

" Convert indent value to spaces or a mix of tabs and spaces
" depending on the value of 'expandtab'
function! slimv#MakeIndent( indent )
    if &expandtab
        return repeat( ' ', a:indent )
    else
        return repeat( "\<Tab>", a:indent / &tabstop ) . repeat( ' ', a:indent % &tabstop )
    endif
endfunction

" Close current top level form by adding the missing parens
function! slimv#closeForm()
    let l2 = line( '.' )
    call slimv#findDefunStart()
    let l1 = line( '.' )
    let form = []
    let l = l1
    while l <= l2
        call add( form, getline( l ) )
        let l = l + 1
    endwhile
    let end = slimv#CloseForm( form )
    if end == 'ERROR'
        " Too many closing parens
        call slimv#errorWait( "Too many or invalid closing parens found." )
    elseif end != ''
        " Add missing parens
        if end[0] == "\n"
            call append( l2, end[1:] )
        else
            call setline( l2, getline( l2 ) . end )
        endif
    endif
    normal! %
endfunction

" Handle insert mode 'Enter' keypress
function! slimv#handleEnter()
    let s:ctx.arglist_line = line('.')
    let s:ctx.arglist_col = col('.')
    if pumvisible()
        " Pressing <CR> in a pop up selects entry.
        return "\<C-Y>"
    else
        if exists( 'g:paredit_mode' ) && g:paredit_mode && g:paredit_electric_return
            " Apply electric return
            return PareditEnter()
        else
            " No electric return handling, just enter a newline
            return "\<CR>"
        endif
    endif
endfunction

" Display arglist after pressing Enter
function! slimv#arglistOnEnter()
    let retval = ""
    if s:ctx.arglist_line > 0
        if col('.') > len(getline('.'))
            " Stay at the end of line
            let retval = "\<End>"
        endif
        let l = line('.')
        if getline(l) == ''
            " Add spaces to make the correct indentation
            call setline( l, slimv#MakeIndent( slimv#indent(l) ) )
            normal! $
        endif
        call slimv#arglist( s:ctx.arglist_line, s:ctx.arglist_col )
    endif
    let s:ctx.arglist_line = 0
    let s:ctx.arglist_col = 0

    " This function is called from <C-R>= mappings, return additional keypress
    return retval
endfunction

" Handle insert mode 'Tab' keypress by doing completion or indentation
function! slimv#handleTab()
    if pumvisible()
        " Completions menu is active, go to next match
        return "\<C-N>"
    endif
    let c = col('.')
    if c > 1 && getline('.')[c-2] =~ '\k'
        " At the end of a keyword, bring up completions
        return "\<C-X>\<C-O>"
    endif
    let indent = slimv#indent(line('.'))
    if c-1 < indent && getline('.') !~ '\S\+'
        " We are left from the autoindent position, do an autoindent
        call setline( line('.'), slimv#MakeIndent( indent ) )
        return "\<End>"
    endif
    " No keyword to complete, no need for autoindent, just enter a <Tab>
    return "\<Tab>"
endfunction

" Make a fold at the cursor point in the current buffer
function slimv#makeFold()
    setlocal modifiable
    normal! o    }}}kA {{{0
    setlocal nomodifiable
endfunction


" Go to the end of buffer, make sure the cursor is positioned
" after the last character of the buffer when in insert mode
function s:EndOfBuffer()
    normal! G$
    if &virtualedit != 'all'
        call cursor( line('$'), 99999 )
    endif
endfunction


" Generate unique window id for the current window
function slimv#MakeWindowId()
    if g:slimv_repl_split && !exists('w:id')
        let s:ctx.win_id = s:ctx.win_id + 1
        let w:id = s:ctx.win_id
    endif
endfunction

" Find and switch to window with the specified window id
function slimv#SwitchToWindow( id )
    for winnr in range( 1, winnr('$') )
        if getwinvar( winnr, 'id' ) is a:id
            execute winnr . "wincmd w"
        endif
    endfor
endfunction

" Handle interrupt (Ctrl-C) keypress in the REPL buffer
function! slimv#interrupt()
    call slimv#command( 'python swank_interrupt()' )
    call slimv#repl#refresh()
endfunction

function! slimv#rFunction()
    " search backwards for the alphanums before a '('
    let l = line('.')
    let c = col('.') - 1
    let line = (getline('.'))[0:c]
    let list = matchlist(line, '\([a-zA-Z0-9_.]\+\)\s*(')
    if !len(list)
        return ""
    endif
    let valid = filter(reverse(list), 'v:val != ""')
    return valid[0]
endfunction

" Display function argument list
" Optional argument is the number of characters typed after the keyword
function! slimv#arglist( ... )
    let retval = ''
    let save_ve = &virtualedit
    set virtualedit=all
    if a:0
        " Symbol position supplied
        let l = a:1
        let c = a:2 - 1
        let line = getline(l)
    else
        " Check symbol at cursor position
        let l = line('.')
        let line = getline(l)
        let c = col('.') - 1
        if c >= len(line)
            " Stay at the end of line
            let c = len(line) - 1
            let retval = "\<End>"
        endif
        if line[c-1] == ' '
            " Is this the space we have just inserted in a mapping?
            let c = c - 1
        endif
    endif
    call slimv#SetKeyword()
    if s:ctx.swank_connected && c > 0 && line[c-1] =~ '\k\|)\|\]\|}\|"'
        " Display only if entering the first space after a keyword
        let arg = ''
        if slimv#getFiletype() == 'r'
            let arg = slimv#rFunction()
        else
            let matchb = max( [l-200, 1] )
            let [l0, c0] = searchpairpos( '(', '', ')', 'nbW', s:ctx.skip_sc, matchb )
            if l0 > 0
                " Found opening paren, let's find out the function name
                while arg == '' && l0 <= l
                    let funcline = substitute( getline(l0), ';.*$', '', 'g' )
                    let arg = matchstr( funcline, '\<\k*\>', c0 )
                    let l0 = l0 + 1
                    let c0 = 0
                endwhile
            endif
        endif

        if arg != ''
            " Ask function argument list from SWANK
            call slimv#findPackage()
            let msg = slimv#commandGetResponse( ':operator-arglist', 'python swank_op_arglist("' . arg . '")', 0 )
            if msg != ''
                " Print argument list in status line with newlines removed.
                " Disable showmode until the next ESC to prevent
                " immeditate overwriting by the "-- INSERT --" text.
                let s:ctx.save_showmode = &showmode
                set noshowmode
                let msg = substitute( msg, "\n", "", "g" )
                redraw
                if slimv#getFiletype() == 'r'
                    call slimv#shortEcho( arg . '(' . msg . ')' )
                elseif match( msg, "\\V" . arg ) != 1 " Use \V ('very nomagic') for exact string match instead of regex
                    " Function name is not received from REPL
                    call slimv#shortEcho( "(" . arg . ' ' . msg[1:] )
                else
                    call slimv#shortEcho( msg )
                endif
            endif
        endif
    endif

    " This function is also called from <C-R>= mappings, return additional keypress
    let &virtualedit=save_ve
    return retval
endfunction

" Start and connect swank server
function! slimv#connectServer()
    if s:ctx.swank_connected
        python swank_disconnect()
        let s:ctx.swank_connected = 0
        " Give swank server some time for disconnecting
        sleep 500m
    endif
    call slimv#beginUpdate()
    if slimv#connectSwank()
        let repl_buf = bufnr( '^' . g:slimv_repl_name . '$' )
        let repl_win = bufwinnr( repl_buf )
        if repl_buf == -1 || ( g:slimv_repl_split && repl_win == -1 )
            call slimv#repl#open()
        endif
    endif
endfunction

" Get the last region (visual block)
function! slimv#getRegion(first, last)
    let oldpos = winsaveview()
    if a:first < a:last || ( a:first == line( "'<" ) && a:last == line( "'>" ) )
        let lines = getline( a:first, a:last )
    else
        " No range was selected, select current paragraph
        normal! vap
        execute "normal! \<Esc>"
        call winrestview( oldpos )
        let lines = getline( "'<", "'>" )
        if lines == [] || lines == ['']
            call slimv#error( "No range selected." )
            return []
        endif
    endif
    let firstcol = col( "'<" ) - 1
    let lastcol  = col( "'>" ) - 2
    if lastcol >= 0
        let lines[len(lines)-1] = lines[len(lines)-1][ : lastcol]
    else
        let lines[len(lines)-1] = ''
    endif
    let lines[0] = lines[0][firstcol : ]

    " Find and set package/namespace definition preceding the region
    call slimv#findPackage()
    call winrestview( oldpos )
    return lines
endfunction


" Undefine function
function! slimv#undefineFunction()
    if s:ctx.swank_connected
        call slimv#command( 'python swank_undefine_function("' . slimv#selectSymbol() . '")' )
        call slimv#repl#refresh()
    endif
endfunction

" ---------------------------------------------------------------------

" Macroexpand-1 the current top level form
function! slimv#macroexpand()
    call slimv#beginUpdate()
    if slimv#connectSwank()
        if !slimv#selectForm( 0 )
            return
        endif
        let s:ctx.swank_form = slimv#getSelection()
        if bufname( "%" ) == g:slimv_repl_name
            " If this is the REPL buffer then go to EOF
            call s:EndOfBuffer()
        endif
        call slimv#commandUsePackage( 'python swank_macroexpand("s:ctx.swank_form")' )
    endif
endfunction

" Macroexpand the current top level form
function! slimv#macroexpandAll()
    call slimv#beginUpdate()
    if slimv#connectSwank()
        if !slimv#selectForm( 0 )
            return
        endif
        let s:ctx.swank_form = slimv#getSelection()
        if bufname( "%" ) == g:slimv_repl_name
            " If this is the REPL buffer then go to EOF
            call s:EndOfBuffer()
        endif
        call slimv#commandUsePackage( 'python swank_macroexpand_all("s:ctx.swank_form")' )
    endif
endfunction

" Toggle debugger break on exceptions
" Only for ritz-swank 0.4.0 and above
function! slimv#breakOnException()
    if slimv#getFiletype() =~ '.*clojure.*' && s:ctx.swank_version >= '2010-11-13'
        " swank-clojure is abandoned at protocol version 20100404, so it must be ritz-swank
        if slimv#connectSwank()
            let s:ctx.break_on_exception = ! s:ctx.break_on_exception
            call slimv#command( 'python swank_break_on_exception(' . s:ctx.break_on_exception . ')' )
            call slimv#repl#refresh()
            echomsg 'Break On Exception ' . (s:ctx.break_on_exception ? 'enabled.' : 'disabled.')
        endif
    else
        call slimv#error( "This function is implemented only for ritz-swank." )
    endif
endfunction

" Set a breakpoint on the beginning of a function
function! slimv#break()
    if slimv#connectSwank()
        let s = input( 'Set breakpoint: ', slimv#selectSymbol() )
        if s != ''
            call slimv#commandUsePackage( 'python swank_set_break("' . s . '")' )
            redraw!
        endif
    endif
endfunction

" Switch trace on for the selected function (toggle for swank)
function! slimv#trace()
    if slimv#getFiletype() == 'scheme'
        call slimv#error( "Tracing is not supported by swank-scheme." )
        return
    endif
    if slimv#connectSwank()
        let s = input( '(Un)trace: ', slimv#selectSymbol() )
        if s != ''
            call slimv#commandUsePackage( 'python swank_toggle_trace("' . s . '")' )
            redraw!
        endif
    endif
endfunction

" Switch trace off for the selected function (or all functions for swank)
function! slimv#untrace()
    if slimv#getFiletype() == 'scheme'
        call slimv#error( "Tracing is not supported by swank-scheme." )
        return
    endif
    if slimv#connectSwank()
        let s:ctx.refresh_disabled = 1
        call slimv#command( 'python swank_untrace_all()' )
        let s:ctx.refresh_disabled = 0
        call slimv#repl#refresh()
    endif
endfunction

" Disassemble the selected function
function! slimv#disassemble()
    let symbol = slimv#selectSymbol()
    if slimv#connectSwank()
        let s = input( 'Disassemble: ', symbol )
        if s != ''
            call slimv#commandUsePackage( 'python swank_disassemble("' . s . '")' )
        endif
    endif
endfunction

" Inspect symbol under cursor
function! slimv#inspect()
    if !slimv#connectSwank()
        return
    endif
    let s:ctx.inspect_path = []
    let frame = slimv#debug#frame()
    if frame != ''
        " Inspect selected for a frame in the debugger's Backtrace section
        let line = getline( '.' )
        if matchstr( line, s:ctx.frame_def ) != ''
            " This is the base frame line in form '  1: xxxxx'
            let sym = ''
        elseif matchstr( line, '^\s\+in "\(.*\)" \(line\|byte\)' ) != ''
            " This is the source location line
            let sym = ''
        elseif matchstr( line, '^\s\+No source line information' ) != ''
            " This is the no source location line
            let sym = ''
        elseif matchstr( line, '^\s\+Locals:' ) != ''
            " This is the 'Locals' line
            let sym = ''
        else
            let sym = slimv#selectSymbolExt()
        endif
        let s = input( 'Inspect in frame ' . frame . ' (evaluated): ', sym )
        if s != ''
            let s:ctx.inspect_path = [s]
            call slimv#beginUpdate()
            call slimv#command( 'python swank_inspect_in_frame("' . s . '", ' . frame . ')' )
            call slimv#repl#refresh()
        endif
    else
        let s = input( 'Inspect: ', slimv#selectSymbolExt() )
        if s != ''
            let s:ctx.inspect_path = [s]
            call slimv#beginUpdate()
            call slimv#commandUsePackage( 'python swank_inspect("' . s . '")' )
        endif
    endif
endfunction

" ---------------------------------------------------------------------

" Switch or toggle profiling on for the selected function
function! slimv#profile()
    if slimv#connectSwank()
        let s = input( '(Un)profile: ', slimv#selectSymbol() )
        if s != ''
            call slimv#commandUsePackage( 'python swank_toggle_profile("' . s . '")' )
            redraw!
        endif
    endif
endfunction

" Switch profiling on based on substring
function! slimv#profileSubstring()
    if slimv#connectSwank()
        let s = input( 'Profile by matching substring: ', slimv#selectSymbol() )
        if s != ''
            let p = input( 'Package (RET for all packages): ' )
            call slimv#commandUsePackage( 'python swank_profile_substring("' . s . '","' . p . '")' )
            redraw!
        endif
    endif
endfunction

" Switch profiling completely off
function! slimv#unprofileAll()
    if slimv#connectSwank()
        call slimv#commandUsePackage( 'python swank_unprofile_all()' )
    endif
endfunction

" Display list of profiled functions
function! slimv#showProfiled()
    if slimv#connectSwank()
        call slimv#commandUsePackage( 'python swank_profiled_functions()' )
    endif
endfunction

" Report profiling results
function! slimv#profileReport()
    if slimv#connectSwank()
        call slimv#commandUsePackage( 'python swank_profile_report()' )
    endif
endfunction

" Reset profiling counters
function! slimv#profileReset()
    if slimv#connectSwank()
        call slimv#commandUsePackage( 'python swank_profile_reset()' )
    endif
endfunction

" ---------------------------------------------------------------------

" Compile the current top-level form
function! slimv#compileDefun()
    let oldpos = winsaveview()
    if !slimv#selectDefun()
        call winrestview( oldpos )
        return
    endif
    call slimv#beginUpdate()
    if slimv#connectSwank()
        let s:ctx.swank_form = slimv#getSelection()
        call slimv#commandUsePackage( 'python swank_compile_string("s:ctx.swank_form")' )
    endif
endfunction

" Compile and load whole file
function! slimv#compileLoadFile()
    if bufname( "%" ) == g:slimv_repl_name
        call slimv#error( "Cannot compile the REPL buffer." )
        return
    endif
    let filename = fnamemodify( bufname(''), ':p' )
    let filename = substitute( filename, '\\', '/', 'g' )
    if &modified
        let answer = slimv#errorAsk( '', "Save file before compiling [Y/n]?" )
        if answer[0] != 'n' && answer[0] != 'N'
            write
        endif
    endif
    call slimv#beginUpdate()
    if slimv#connectSwank()
        let s:ctx.compiled_file = ''
        call slimv#commandUsePackage( 'python swank_compile_file("' . filename . '")' )
        let starttime = localtime()
        while s:ctx.compiled_file == '' && localtime()-starttime < g:slimv_timeout
            call slimv#swankResponse()
        endwhile
        if s:ctx.compiled_file != ''
            call slimv#commandUsePackage( 'python swank_load_file("' . s:ctx.compiled_file . '")' )
            let s:ctx.compiled_file = ''
        endif
    endif
endfunction

" Compile whole file
function! slimv#compileFile()
    if bufname( "%" ) == g:slimv_repl_name
        call slimv#error( "Cannot compile the REPL buffer." )
        return
    endif
    let filename = fnamemodify( bufname(''), ':p' )
    let filename = substitute( filename, '\\', '/', 'g' )
    if &modified
        let answer = slimv#errorAsk( '', "Save file before compiling [Y/n]?" )
        if answer[0] != 'n' && answer[0] != 'N'
            write
        endif
    endif
    call slimv#beginUpdate()
    if slimv#connectSwank()
        call slimv#commandUsePackage( 'python swank_compile_file("' . filename . '")' )
    endif
endfunction

" Compile buffer lines in the given range
function! slimv#compileRegion() range
    if v:register == '"'
        let lines = slimv#getRegion(a:firstline, a:lastline)
    else
        " Register was passed, so compile register contents instead
        let reg = getreg( v:register )
        let ending = slimv#CloseForm( [reg] )
        if ending == 'ERROR'
            call slimv#error( 'Too many or invalid closing parens in register "' . v:register )
            return
        endif
        let lines = [reg . ending]
    endif
    if lines == []
        return
    endif
    let region = join( lines, "\n" )
    call slimv#beginUpdate()
    if slimv#connectSwank()
        let s:ctx.swank_form = region
        call slimv#commandUsePackage( 'python swank_compile_string("s:ctx.swank_form")' )
    endif
endfunction

" ---------------------------------------------------------------------

" Describe the selected symbol
function! slimv#describeSymbol()
    call slimv#beginUpdate()
    if slimv#connectSwank()
        let symbol = slimv#selectSymbol()
        if symbol == ''
            call slimv#error( "No symbol under cursor." )
            return
        endif
        call slimv#commandUsePackage( 'python swank_describe_symbol("' . symbol . '")' )
    endif
endfunction

" Display symbol description in balloonexpr
function! slimv#describe(arg)
    let arg=a:arg
    if a:arg == ''
        let arg = expand('<cword>')
    endif
    " We don't want to try connecting here ... the error message would just
    " confuse the balloon logic
    if !s:ctx.swank_connected
        return ''
    endif
    call slimv#findPackage()
    let arglist = slimv#commandGetResponse( ':operator-arglist', 'python swank_op_arglist("' . arg . '")', 0 )
    if arglist == ''
        " Not able to fetch arglist, assuming function is not defined
        " Skip calling describe, otherwise SWANK goes into the debugger
        return ''
    endif
    let msg = slimv#commandGetResponse( ':describe-function', 'python swank_describe_function("' . arg . '")', 0 )
    if msg == ''
        " No describe info, display arglist
        if match( arglist, arg ) != 1
            " Function name is not received from REPL
            return "(" . arg . ' ' . arglist[1:]
        else
            return arglist
        endif
    else
        return substitute(msg,'^\n*','','')
    endif
endfunction

" Apropos of the selected symbol
function! slimv#apropos()
    call slimv#eval#form1( g:slimv_template_apropos, slimv#selectSymbol() )
endfunction

" Generate tags file using ctags
function! slimv#generateTags()
    if exists( 'g:slimv_ctags' ) && g:slimv_ctags != ''
        execute 'silent !' . g:slimv_ctags
    else
        call slimv#error( "Copy ctags to the Vim path or define g:slimv_ctags." )
    endif
endfunction

" ---------------------------------------------------------------------

" Find word in the CLHS symbol database, with exact or partial match.
" Return either the first symbol found with the associated URL,
" or the list of all symbols found without the associated URL.
function! slimv#findSymbol( word, exact, all, db, root, init )
    if a:word == ''
        return []
    endif
    if !a:all && a:init != []
        " Found something already at a previous db lookup, no need to search this db
        return a:init
    endif
    let lst = a:init
    let i = 0
    let w = tolower( a:word )
    if a:exact
        while i < len( a:db )
            " Try to find an exact match
            if a:db[i][0] == w
                " No reason to check a:all here
                return [a:db[i][0], a:root . a:db[i][1]]
            endif
            let i = i + 1
        endwhile
    else
        while i < len( a:db )
            " Try to find the symbol starting with the given word
            let w2 = escape( w, '~' )
            if match( a:db[i][0], w2 ) == 0
                if a:all
                    call add( lst, a:db[i][0] )
                else
                    return [a:db[i][0], a:root . a:db[i][1]]
                endif
            endif
            let i = i + 1
        endwhile
    endif

    " Return whatever found so far
    return lst
endfunction

" Lookup word in Common Lisp Hyperspec
function! slimv#lookup( word )
    " First try an exact match
    let w = a:word
    let symbol = []
    while symbol == []
        let symbol = b:SlimvHyperspecLookup( w, 1, 0 )
        if symbol == []
            " Symbol not found, try a match on beginning of symbol name
            let symbol = b:SlimvHyperspecLookup( w, 0, 0 )
            if symbol == []
                " We are out of luck, can't find anything
                let msg = 'Symbol ' . w . ' not found. Hyperspec lookup word: '
                let val = ''
            else
                let msg = 'Hyperspec lookup word: '
                let val = symbol[0]
            endif
            " Ask user if this is that he/she meant
            let w = input( msg, val )
            if w == ''
                " OK, user does not want to continue
                return
            endif
            let symbol = []
        endif
    endwhile
    if symbol != [] && len(symbol) > 1
        " Symbol found, open HS page in browser
        if match( symbol[1], ':' ) < 0 && exists( g:slimv_hs_root )
            let page = g:slimv_hs_root . symbol[1]
        else
            " URL is already a fully qualified address
            let page = symbol[1]
        endif
        if exists( "g:slimv_browser_cmd" )
            " We have an given command to start the browser
            if !exists( "g:slimv_browser_cmd_suffix" )
                " Fork the browser by default
                let g:slimv_browser_cmd_suffix = '&'
            endif
            silent execute '! ' . g:slimv_browser_cmd . ' ' . page . ' ' . g:slimv_browser_cmd_suffix
        else
            if g:slimv_windows
                " Run the program associated with the .html extension
                silent execute '! start ' . page
            else
                " On Linux it's not easy to determine the default browser
                if executable( 'xdg-open' )
                    silent execute '! xdg-open ' . page . ' &'
                else
                    " xdg-open not installed, ask help from Python webbrowser package
                    let pycmd = "import webbrowser; webbrowser.open('" . page . "')"
                    silent execute '! python -c "' . pycmd . '"'
                endif
            endif
        endif
        " This is needed especially when using text browsers
        redraw!
    endif
endfunction

" Lookup current symbol in the Common Lisp Hyperspec
function! slimv#hyperspec()
    call slimv#lookup(slimv#selectSymbol())
endfunction

" Complete symbol name starting with 'base'
function! slimv#complete( base )
    " Find all symbols starting with "a:base"
    if a:base == ''
        return []
    endif
    if s:ctx.swank_connected
        " Save current buffer and window in case a swank command causes a buffer change
        let buf = bufnr( "%" )
        if winnr('$') < 2
            let win = 0
        else
            let win = winnr()
        endif

        call slimv#findPackage()
        if g:slimv_simple_compl
            let msg = slimv#commandGetResponse( ':simple-completions', 'python swank_completions("' . a:base . '")', 0 )
        else
            let msg = slimv#commandGetResponse( ':fuzzy-completions', 'python swank_fuzzy_completions("' . a:base . '")', 0 )
        endif

        " Restore window and buffer, because it is not allowed to change buffer here
        if win > 0 && winnr() != win
            execute win . "wincmd w"
            let msg = ''
        endif
        if bufnr( "%" ) != buf
            execute "buf " . buf
            let msg = ''
        endif

        if msg != ''
            " We have a completion list from SWANK
            let res = split( msg, '\n' )
            return res
        endif
    endif

    " No completion yet, try to fetch it from the Hyperspec database
    let res = []
    let symbol = b:SlimvHyperspecLookup( a:base, 0, 1 )
    if symbol == []
        return []
    endif
    call sort( symbol )
    for m in symbol
        if m =~ '^' . a:base
            call add( res, m )
        endif
    endfor
    return res
endfunction

" Complete function that uses the Hyperspec database
function! slimv#omniComplete( findstart, base )
    if a:findstart
        " Locate the start of the symbol name
        call slimv#SetKeyword()
        let upto = strpart( getline( '.' ), 0, col( '.' ) - 1)
        return match(upto, '\k\+$')
    else
        return slimv#complete( a:base )
    endif
endfunction

" Define complete function only if none is defined yet
if &omnifunc == ''
    set omnifunc=slimv#omniComplete
endif

" Complete function for user-defined commands
function! slimv#commandComplete( arglead, cmdline, cursorpos )
    " Locate the start of the symbol name
    call slimv#SetKeyword()
    let upto = strpart( a:cmdline, 0, a:cursorpos )
    let base = matchstr(upto, '\k\+$')
    let ext  = matchstr(upto, '\S*\k\+$')
    let compl = slimv#complete( base )
    if len(compl) > 0 && base != ext
        " Command completion replaces whole word between spaces, so we
        " need to add any prefix present in front of the keyword, like '('
        let prefix = strpart( ext, 0, len(ext) - len(base) )
        let i = 0
        while i < len(compl)
            let compl[i] = prefix . compl[i]
            let i = i + 1
        endwhile
    endif
    return compl
endfunction

" Set current package
function! slimv#setPackage()
    if slimv#connectSwank()
        call slimv#findPackage()
        let pkg = input( 'Package: ', s:ctx.swank_package )
        if pkg != ''
            let s:ctx.refresh_disabled = 1
            call slimv#command( 'python swank_set_package("' . pkg . '")' )
            let s:ctx.refresh_disabled = 0
            call slimv#repl#refresh()
        endif
    endif
endfunction

" =====================================================================
"  Slimv keybindings
" =====================================================================

" <Leader> timeouts in 1000 msec by default, if this is too short,
" then increase 'timeoutlen'

" Map keyboard keyset dependant shortcut to command and also add it to menu
function! s:MenuMap( name, shortcut1, shortcut2, command )
    if g:slimv_keybindings == 1
        " Short (one-key) keybinding set
        let shortcut = a:shortcut1
    elseif g:slimv_keybindings == 2
        " Easy to remember (two-key) keybinding set
        let shortcut = a:shortcut2
    endif

    if shortcut != ''
        execute "noremap <silent> " . shortcut . " " . a:command
        if a:name != '' && g:slimv_menu == 1
            silent execute "amenu " . a:name . "<Tab>" . shortcut . " " . a:command
        endif
    elseif a:name != '' && g:slimv_menu == 1
        silent execute "amenu " . a:name . " " . a:command
    endif
endfunction

" Initialize buffer by adding buffer specific mappings
function! slimv#initBuffer()
    " Map space to display function argument list in status line
    if slimv#getFiletype() == 'r'
        inoremap <silent> <buffer> (          (<C-R>=slimv#arglist()<CR>
    else
        inoremap <silent> <buffer> <Space>    <Space><C-R>=slimv#arglist()<CR>
        inoremap <silent> <buffer> <CR>       <C-R>=pumvisible() ?  "\<lt>C-Y>" : slimv#handleEnter()<CR><C-R>=slimv#arglistOnEnter()<CR>
    endif
    "noremap  <silent> <buffer> <C-C>      :call slimv#interrupt()<CR>
    augroup SlimvInsertLeave
        au!
        au InsertLeave * :let &showmode=s:ctx.save_showmode
    augroup END
    inoremap <silent> <buffer> <C-X>0     <C-O>:call slimv#closeForm()<CR>
    inoremap <silent> <buffer> <Tab>      <C-R>=slimv#handleTab()<CR>
    inoremap <silent> <buffer> <S-Tab>    <C-R>=pumvisible() ? "\<lt>C-P>" : "\<lt>S-Tab>"<CR>

    " Setup balloonexp to display symbol description
    if g:slimv_balloon && has( 'balloon_eval' )
        "setlocal balloondelay=100
        setlocal ballooneval
        setlocal balloonexpr=slimv#describe(v:beval_text)
    endif
    " This is needed for safe switching of modified buffers
    set hidden
    call slimv#MakeWindowId()
endfunction

" " Edit commands
" call s:MenuMap( 'Slim&v.Edi&t.Close-&Form',                     g:slimv_leader.')',  g:slimv_leader.'tc',  ':<C-U>call slimv#closeForm()<CR>' )
" call s:MenuMap( 'Slim&v.Edi&t.&Complete-Symbol<Tab>Tab',        '',                  '',                   '<Ins><C-X><C-O>' )

" if exists( 'g:paredit_loaded' )
" call s:MenuMap( 'Slim&v.Edi&t.&Paredit-Toggle',                 g:slimv_leader.'(',  g:slimv_leader.'(t',  ':<C-U>call PareditToggle()<CR>' )
" call s:MenuMap( 'Slim&v.Edi&t.-PareditSep-',                    '',                  '',                   ':' )

" if g:paredit_shortmaps
" call s:MenuMap( 'Slim&v.Edi&t.Paredit-&Wrap<Tab>'                             .'W',  '',  '',              ':<C-U>call PareditWrap("(",")")<CR>' )
" call s:MenuMap( 'Slim&v.Edi&t.Paredit-Spli&ce<Tab>'                           .'S',  '',  '',              ':<C-U>call PareditSplice()<CR>' )
" call s:MenuMap( 'Slim&v.Edi&t.Paredit-&Split<Tab>'                            .'O',  '',  '',              ':<C-U>call PareditSplit()<CR>' )
" call s:MenuMap( 'Slim&v.Edi&t.Paredit-&Join<Tab>'                             .'J',  '',  '',              ':<C-U>call PareditJoin()<CR>' )
" call s:MenuMap( 'Slim&v.Edi&t.Paredit-Ra&ise<Tab>'             .g:slimv_leader.'I',  '',  '',              ':<C-U>call PareditRaise()<CR>' )
" call s:MenuMap( 'Slim&v.Edi&t.Paredit-Move&Left<Tab>'                         .'<',  '',  '',              ':<C-U>call PareditMoveLeft()<CR>' )
" call s:MenuMap( 'Slim&v.Edi&t.Paredit-Move&Right<Tab>'                        .'>',  '',  '',              ':<C-U>call PareditMoveRight()<CR>' )
" else
" call s:MenuMap( 'Slim&v.Edi&t.Paredit-&Wrap<Tab>'              .g:slimv_leader.'W',  '',  '',              ':<C-U>call PareditWrap("(",")")<CR>' )
" call s:MenuMap( 'Slim&v.Edi&t.Paredit-Spli&ce<Tab>'            .g:slimv_leader.'S',  '',  '',              ':<C-U>call PareditSplice()<CR>' )
" call s:MenuMap( 'Slim&v.Edi&t.Paredit-&Split<Tab>'             .g:slimv_leader.'O',  '',  '',              ':<C-U>call PareditSplit()<CR>' )
" call s:MenuMap( 'Slim&v.Edi&t.Paredit-&Join<Tab>'              .g:slimv_leader.'J',  '',  '',              ':<C-U>call PareditJoin()<CR>' )
" call s:MenuMap( 'Slim&v.Edi&t.Paredit-Ra&ise<Tab>'             .g:slimv_leader.'I',  '',  '',              ':<C-U>call PareditRaise()<CR>' )
" call s:MenuMap( 'Slim&v.Edi&t.Paredit-Move&Left<Tab>'          .g:slimv_leader.'<',  '',  '',              ':<C-U>call PareditMoveLeft()<CR>' )
" call s:MenuMap( 'Slim&v.Edi&t.Paredit-Move&Right<Tab>'         .g:slimv_leader.'>',  '',  '',              ':<C-U>call PareditMoveRight()<CR>' )
" endif "g:paredit_shortmaps
" endif "g:paredit_loaded

" " Evaluation commands
" call s:MenuMap( 'Slim&v.&Evaluation.Eval-&Defun',               g:slimv_leader.'d',  g:slimv_leader.'ed',  ':<C-U>call slimv#eval#defun()<CR>' )
" call s:MenuMap( 'Slim&v.&Evaluation.Eval-Current-&Exp',         g:slimv_leader.'e',  g:slimv_leader.'ee',  ':<C-U>call slimv#eval#exp()<CR>' )
" call s:MenuMap( 'Slim&v.&Evaluation.Eval-&Region',              g:slimv_leader.'r',  g:slimv_leader.'er',  ':call slimv#eval#region()<CR>' )
" call s:MenuMap( 'Slim&v.&Evaluation.Eval-&Buffer',              g:slimv_leader.'b',  g:slimv_leader.'eb',  ':<C-U>call slimv#eval#buffer()<CR>' )
" call s:MenuMap( 'Slim&v.&Evaluation.Interacti&ve-Eval\.\.\.',   g:slimv_leader.'v',  g:slimv_leader.'ei',  ':call slimv#interactiveEval()<CR>' )
" call s:MenuMap( 'Slim&v.&Evaluation.&Undefine-Function',        g:slimv_leader.'u',  g:slimv_leader.'eu',  ':call slimv#undefineFunction()<CR>' )

" " Debug commands
" call s:MenuMap( 'Slim&v.De&bugging.Macroexpand-&1',             g:slimv_leader.'1',  g:slimv_leader.'m1',  ':<C-U>call slimv#macroexpand()<CR>' )
" call s:MenuMap( 'Slim&v.De&bugging.&Macroexpand-All',           g:slimv_leader.'m',  g:slimv_leader.'ma',  ':<C-U>call slimv#macroexpandAll()<CR>' )
" call s:MenuMap( 'Slim&v.De&bugging.Toggle-&Trace\.\.\.',        g:slimv_leader.'t',  g:slimv_leader.'dt',  ':call slimv#trace()<CR>' )
" call s:MenuMap( 'Slim&v.De&bugging.U&ntrace-All',               g:slimv_leader.'T',  g:slimv_leader.'du',  ':call slimv#untrace()<CR>' )
" call s:MenuMap( 'Slim&v.De&bugging.Set-&Breakpoint',            g:slimv_leader.'B',  g:slimv_leader.'db',  ':call slimv#break()<CR>' )
" call s:MenuMap( 'Slim&v.De&bugging.Break-on-&Exception',        g:slimv_leader.'E',  g:slimv_leader.'de',  ':call slimv#breakOnException()<CR>' )
" call s:MenuMap( 'Slim&v.De&bugging.Disassemb&le\.\.\.',         g:slimv_leader.'l',  g:slimv_leader.'dd',  ':call slimv#disassemble()<CR>' )
" call s:MenuMap( 'Slim&v.De&bugging.&Inspect\.\.\.',             g:slimv_leader.'i',  g:slimv_leader.'di',  ':call slimv#inspect()<CR>' )
" call s:MenuMap( 'Slim&v.De&bugging.-SldbSep-',                  '',                  '',                   ':' )
" call s:MenuMap( 'Slim&v.De&bugging.&Abort',                     g:slimv_leader.'a',  g:slimv_leader.'da',  ':call slimv#debug#abort()<CR>' )
" call s:MenuMap( 'Slim&v.De&bugging.&Quit-to-Toplevel',          g:slimv_leader.'q',  g:slimv_leader.'dq',  ':call slimv#debug#quit()<CR>' )
" call s:MenuMap( 'Slim&v.De&bugging.&Continue',                  g:slimv_leader.'n',  g:slimv_leader.'dc',  ':call slimv#debug#continue()<CR>' )
" call s:MenuMap( 'Slim&v.De&bugging.&Restart-Frame',             g:slimv_leader.'N',  g:slimv_leader.'dr',  ':call slimv#debug#restartFrame()<CR>' )
" call s:MenuMap( 'Slim&v.De&bugging.-ThreadSep-',                '',                  '',                   ':' )
" call s:MenuMap( 'Slim&v.De&bugging.List-T&hreads',              g:slimv_leader.'H',  g:slimv_leader.'dl',  ':call slimv#thread#list()<CR>' )
" call s:MenuMap( 'Slim&v.De&bugging.&Kill-Thread\.\.\.',         g:slimv_leader.'K',  g:slimv_leader.'dk',  ':call slimv#thread#kill()<CR>' )
" call s:MenuMap( 'Slim&v.De&bugging.&Debug-Thread\.\.\.',        g:slimv_leader.'G',  g:slimv_leader.'dT',  ':call slimv#debug#thread()<CR>' )

" " Compile commands
" call s:MenuMap( 'Slim&v.&Compilation.Compile-&Defun',           g:slimv_leader.'D',  g:slimv_leader.'cd',  ':<C-U>call slimv#compileDefun()<CR>' )
" call s:MenuMap( 'Slim&v.&Compilation.Compile-&Load-File',       g:slimv_leader.'L',  g:slimv_leader.'cl',  ':<C-U>call slimv#compileLoadFile()<CR>' )
" call s:MenuMap( 'Slim&v.&Compilation.Compile-&File',            g:slimv_leader.'F',  g:slimv_leader.'cf',  ':<C-U>call slimv#compileFile()<CR>' )
" call s:MenuMap( 'Slim&v.&Compilation.Compile-&Region',          g:slimv_leader.'R',  g:slimv_leader.'cr',  ':call slimv#compileRegion()<CR>' )

" " Xref commands
" call s:MenuMap( 'Slim&v.&Xref.Who-&Calls',                      g:slimv_leader.'xc', g:slimv_leader.'xc',  ':call slimv#xref#xrefCalls()<CR>' )
" call s:MenuMap( 'Slim&v.&Xref.Who-&References',                 g:slimv_leader.'xr', g:slimv_leader.'xr',  ':call slimv#xref#xrefReferences()<CR>' )
" call s:MenuMap( 'Slim&v.&Xref.Who-&Sets',                       g:slimv_leader.'xs', g:slimv_leader.'xs',  ':call slimv#xref#xrefSets()<CR>' )
" call s:MenuMap( 'Slim&v.&Xref.Who-&Binds',                      g:slimv_leader.'xb', g:slimv_leader.'xb',  ':call slimv#xref#xrefBinds()<CR>' )
" call s:MenuMap( 'Slim&v.&Xref.Who-&Macroexpands',               g:slimv_leader.'xm', g:slimv_leader.'xm',  ':call slimv#xref#xrefMacroexpands()<CR>' )
" call s:MenuMap( 'Slim&v.&Xref.Who-S&pecializes',                g:slimv_leader.'xp', g:slimv_leader.'xp',  ':call slimv#xref#xrefSpecializes()<CR>' )
" call s:MenuMap( 'Slim&v.&Xref.&List-Callers',                   g:slimv_leader.'xl', g:slimv_leader.'xl',  ':call slimv#xref#xrefCallers()<CR>' )
" call s:MenuMap( 'Slim&v.&Xref.List-Call&ees',                   g:slimv_leader.'xe', g:slimv_leader.'xe',  ':call slimv#xref#xrefCallees()<CR>' )

" " Profile commands
" call s:MenuMap( 'Slim&v.&Profiling.Toggle-&Profile\.\.\.',      g:slimv_leader.'p',  g:slimv_leader.'pp',  ':<C-U>call slimv#profile()<CR>' )
" call s:MenuMap( 'Slim&v.&Profiling.Profile-&By-Substring\.\.\.',g:slimv_leader.'P',  g:slimv_leader.'pb',  ':<C-U>call slimv#profileSubstring()<CR>' )
" call s:MenuMap( 'Slim&v.&Profiling.Unprofile-&All',             g:slimv_leader.'U',  g:slimv_leader.'pa',  ':<C-U>call slimv#unprofileAll()<CR>' )
" call s:MenuMap( 'Slim&v.&Profiling.&Show-Profiled',             g:slimv_leader.'?',  g:slimv_leader.'ps',  ':<C-U>call slimv#showProfiled()<CR>' )
" call s:MenuMap( 'Slim&v.&Profiling.-ProfilingSep-',             '',                  '',                   ':' )
" call s:MenuMap( 'Slim&v.&Profiling.Profile-Rep&ort',            g:slimv_leader.'o',  g:slimv_leader.'pr',  ':<C-U>call slimv#profileReport()<CR>' )
" call s:MenuMap( 'Slim&v.&Profiling.Profile-&Reset',             g:slimv_leader.'X',  g:slimv_leader.'px',  ':<C-U>call slimv#profileReset()<CR>' )

" " Documentation commands
" call s:MenuMap( 'Slim&v.&Documentation.Describe-&Symbol',       g:slimv_leader.'s',  g:slimv_leader.'ds',  ':call slimv#describeSymbol()<CR>' )
" call s:MenuMap( 'Slim&v.&Documentation.&Apropos',               g:slimv_leader.'A',  g:slimv_leader.'dp',  ':call slimv#apropos()<CR>' )
" call s:MenuMap( 'Slim&v.&Documentation.&Hyperspec',             g:slimv_leader.'h',  g:slimv_leader.'dh',  ':call slimv#hyperspec()<CR>' )
" call s:MenuMap( 'Slim&v.&Documentation.Generate-&Tags',         g:slimv_leader.']',  g:slimv_leader.'dg',  ':call slimv#generateTags()<CR>' )

" " REPL commands
" call s:MenuMap( 'Slim&v.&Repl.&Connect-Server',                 g:slimv_leader.'c',  g:slimv_leader.'rc',  ':call slimv#connectServer()<CR>' )
" call s:MenuMap( '',                                             g:slimv_leader.'g',  g:slimv_leader.'rp',  ':call slimv#setPackage()<CR>' )
" call s:MenuMap( 'Slim&v.&Repl.Interrup&t-Lisp-Process',         g:slimv_leader.'y',  g:slimv_leader.'ri',  ':call slimv#interrupt()<CR>' )
" call s:MenuMap( 'Slim&v.&Repl.Clear-&REPL',                     g:slimv_leader.'-',  g:slimv_leader.'-',   ':call SlimvClearReplBuffer()<CR>' )


" =====================================================================
"  Slimv menu
" =====================================================================

if g:slimv_menu == 1
    " Works only if 'wildcharm' is <Tab>
    if &wildcharm == 0
        set wildcharm=<Tab>
    endif
    if &wildcharm != 0
        execute ':map ' . g:slimv_leader.', :emenu Slimv.' . nr2char( &wildcharm )
    endif
endif

" Add REPL menu. This menu exist only for the REPL buffer.
function! slimv#addReplMenu()
    if &wildcharm != 0
        execute ':map ' . g:slimv_leader.'\ :emenu REPL.' . nr2char( &wildcharm )
    endif

    amenu &REPL.Send-&Input                            :call slimv#sendCommand(0)<CR>
    amenu &REPL.Cl&ose-Send-Input                      :call slimv#sendCommand(1)<CR>
    amenu &REPL.Set-Packa&ge                           :call slimv#setPackage()<CR>
    amenu &REPL.Interrup&t-Lisp-Process                <Esc>:<C-U>call slimv#interrupt()<CR>
    amenu &REPL.-REPLSep-                              :
    amenu &REPL.&Previous-Input                        :call slimv#previousCommand()<CR>
    amenu &REPL.&Next-Input                            :call slimv#nextCommand()<CR>
    amenu &REPL.Clear-&REPL                            :call SlimvClearReplBuffer()<CR>
endfunction

