" slimv-clojure.vim:
"               Clojure filetype plugin for Slimv
" Version:      0.9.13
" Last Change:  04 May 2014
" Maintainer:   Tamas Kovacs <kovisoft at gmail dot com>
" License:      This file is placed in the public domain.
"               No warranty, express or implied.
"               *** ***   Use At-Your-Own-Risk!   *** ***
"
" =====================================================================
"
"  Load Once:
if exists("b:slimv_did_ftplugin") || exists("g:slimv_disable_clojure")
    finish
endif


" ---------- Begin part loaded once ----------
if !exists( 'g:slimv_clojure_loaded' )


let g:slimv_template_apropos = '(clojure.repl/apropos "%1")'
let g:slimv_clojure_loaded = 1

" Transform filename so that it will not contain spaces
function! s:TransformFilename( name )
    if match( a:name, ' ' ) >= 0
        return fnamemodify( a:name , ':8' )
    else
        return a:name
    endif
endfunction

" Build a Clojure startup command by adding
" all clojure*.jar files found to the classpath
function! s:BuildStartCmd( lisps )
    let cp = s:TransformFilename( a:lisps[0] )
    let i = 1
    while i < len( a:lisps )
        let cp = cp . ';' . s:TransformFilename( a:lisps[i] )
        let i = i + 1
    endwhile

    " Try to find swank-clojure and add it to classpath
    let swanks = split( globpath( &runtimepath, 'swank-clojure'), '\n' )
    if len( swanks ) > 0
        let cp = cp . ';' . s:TransformFilename( swanks[0] )
    endif
    return ['java -cp ' . cp . ' clojure.main', 'clojure']
endfunction

" Try to autodetect Clojure executable
" Returns list [Clojure executable, Clojure implementation]
function! SlimvAutodetect( preferred )
    " Firts try the most basic setup: everything in the path
    if executable( 'lein' )
        return ['"lein repl"', 'clojure']
    endif
    if executable( 'cake' )
        return ['"cake repl"', 'clojure']
    endif
    if executable( 'clojure' )
        return ['clojure', 'clojure']
    endif
    let lisps = []
    if executable( 'clojure.jar' )
        let lisps = ['clojure.jar']
    endif
    if executable( 'clojure-contrib.jar' )
        let lisps = lisps + 'clojure-contrib.jar'
    endif
    if len( lisps ) > 0
        return s:BuildStartCmd( lisps )
    endif

    " Check if Clojure is bundled with Slimv
    let lisps = split( globpath( &runtimepath, 'swank-clojure/clojure*.jar'), '\n' )
    if len( lisps ) > 0
        return s:BuildStartCmd( lisps )
    endif

    " Try to find Clojure in the PATH
    let path = substitute( $PATH, ';', ',', 'g' )
    let lisps = split( globpath( path, 'clojure*.jar' ), '\n' )
    if len( lisps ) > 0
        return s:BuildStartCmd( lisps )
    endif

    if g:slimv_windows
        " Try to find Clojure on the standard installation places
        let lisps = split( globpath( 'c:/*clojure*,c:/*clojure*/lib', 'clojure*.jar' ), '\n' )
        if len( lisps ) > 0
            return s:BuildStartCmd( lisps )
        endif
    else
        " Try to find Clojure in the home directory
        let lisps = split( globpath( '/usr/local/bin/*clojure*', 'clojure*.jar' ), '\n' )
        if len( lisps ) > 0
            return s:BuildStartCmd( lisps )
        endif
        let lisps = split( globpath( '~/*clojure*', 'clojure*.jar' ), '\n' )
        if len( lisps ) > 0
            return s:BuildStartCmd( lisps )
        endif
    endif

    return ['', '']
endfunction

" Try to find out the Clojure implementation
function! SlimvImplementation()
    if exists( 'g:slimv_impl' ) && g:slimv_impl != ''
        " Return Lisp implementation if defined
        return tolower( g:slimv_impl )
    endif

    return 'clojure'
endfunction

" Try to autodetect SWANK and build the command to load the SWANK server
function! SlimvSwankLoader()
    " First autodetect Leiningen and Cake
    if executable( 'lein' )
        if globpath( '~/.lein/plugins', 'lein-ritz*.jar' ) != ''
            return '"lein ritz ' . g:swank_port . '"'
        else
            return '"lein swank"'
        endif
    elseif executable( 'cake' )
        return '"cake swank"'
    else
        " Check if swank-clojure is bundled with Slimv
        let swanks = split( globpath( &runtimepath, 'swank-clojure/swank/swank.clj'), '\n' )
        if len( swanks ) == 0
            return ''
        endif
        let sclj = substitute( swanks[0], '\', '/', "g" )
        return g:slimv_lisp . ' -i "' . sclj . '" -e "(swank.swank/start-repl)" -r'
    endif
endfunction

" Filetype specific initialization for the REPL buffer
function! SlimvInitRepl()
    set filetype=clojure
endfunction

" Lookup symbol in the list of Clojure Hyperspec symbol databases
function! SlimvHyperspecLookup( word, exact, all )
    if !exists( 'g:slimv_cljapi_loaded' )
        runtime ftplugin/**/slimv-cljapi.vim
    endif

    if !exists( 'g:slimv_javadoc_loaded' )
        runtime ftplugin/**/slimv-javadoc.vim
    endif

    let symbol = []
    if exists( 'g:slimv_cljapi_db' )
        let symbol = slimv#findSymbol( a:word, a:exact, a:all, g:slimv_cljapi_db,  g:slimv_cljapi_root,  symbol )
    endif
    if exists( 'g:slimv_javadoc_db' )
        let symbol = slimv#findSymbol( a:word, a:exact, a:all, g:slimv_javadoc_db, g:slimv_javadoc_root, symbol )
    endif
    if exists( 'g:slimv_cljapi_user_db' )
        " Give a choice for the user to extend the symbol database
        if exists( 'g:slimv_cljapi_user_root' )
            let user_root = g:slimv_cljapi_user_root
        else
            let user_root = ''
        endif
        let symbol = slimv#findSymbol( a:word, a:exact, a:all, g:slimv_cljapi_user_db, user_root, symbol )
    endif
    return symbol
endfunction

" Implementation specific REPL initialization
function! SlimvReplInit( lisp_version )
    " Import functions commonly used in REPL but not present when not running in repl mode
    if a:lisp_version[0:2] >= '1.3'
        call slimv#sendSilent( ["(use '[clojure.repl :only (source apropos dir pst doc find-doc)])",
        \                      "(use '[clojure.java.javadoc :only (javadoc)])",
        \                      "(use '[clojure.pprint :only (pp pprint)])"] )
    elseif a:lisp_version[0:2] >= '1.2'
        call slimv#sendSilent( ["(use '[clojure.repl :only (source apropos)])",
        \                      "(use '[clojure.java.javadoc :only (javadoc)])",
        \                      "(use '[clojure.pprint :only (pp pprint)])"] )
    endif
endfunction

" Source Slimv general part
runtime ftplugin/**/slimv.vim

endif "!exists( 'g:slimv_clojure_loaded' )
" ---------- End of part loaded once ----------

runtime ftplugin/**/lisp.vim

" Must be called for each lisp buffer
call slimv#initBuffer()

" Don't initiate Slimv again for this buffer
let b:slimv_did_ftplugin = 1

" noremap <silent> <Tab> <Ins><C-X><C-O>

nnoremap [slimv] <Nop>
nmap \ [slimv]

noremap <silent> [slimv]) :<C-U>call slimv#closeForm()<CR>

" Evaluation commands
map <silent> [slimv]d :<C-U>call slimv#eval#defun()<CR>
map <silent> [slimv]e :<C-U>call slimv#eval#exp()<CR>
map <silent> [slimv]r :call slimv#eval#region()<CR>
map <silent> [slimv]b :<C-U>call slimv#eval#buffer()<CR>
map <silent> [slimv]v :call slimv#eval#interactive()<CR>
map <silent> [slimv]u :call slimv#undefineFunction()<CR>

" Debug commands
map <silent> [slimv]1 :<C-U>call slimv#macroexpand()<CR>
map <silent> [slimv]m :<C-U>call slimv#macroexpandAll()<CR>
map <silent> [slimv]t :call slimv#trace()<CR>
map <silent> [slimv]T :call slimv#untrace()<CR>
" map <silent> [slimv]B :call slimv#break()<CR>
map <silent> [slimv]B :call slimv#commandUsePackage("python swank_line_breakpoint()")<cr>
map <silent> [slimv]V :python swank_list_breakpoints()<cr>

map <silent> [slimv]E :call slimv#breakOnException()<CR>
map <silent> [slimv]l :call slimv#disassemble()<CR>
map <silent> [slimv]i :call slimv#inspect()<CR>
map <silent> [slimv]a :call slimv#debug#abort()<CR>
map <silent> [slimv]q :call slimv#debug#quit()<CR>
map <silent> [slimv]n :call slimv#debug#continue()<CR>
map <silent> [slimv]N :call slimv#debug#restartFrame()<CR>
map <silent> [slimv]H :call slimv#thread#list()<CR>
map <silent> [slimv]K :call slimv#thread#kill()<CR>
map <silent> [slimv]G :call slimv#debug#thread()<CR>

" Compile commands
map <silent> [slimv]D :<C-U>call slimv#compileDefun()<CR>
map <silent> [slimv]L :<C-U>call slimv#compileLoadFile()<CR>
map <silent> [slimv]F :<C-U>call slimv#compileFile()<CR>
map <silent> [slimv]R :call slimv#compileRegion()<CR>

" Xref commands
map <silent> [slimv]xc :call slimv#xref#xrefCalls()<CR>
map <silent> [slimv]xr :call slimv#xref#xrefReferences()<CR>
map <silent> [slimv]xs :call slimv#xref#xrefSets()<CR>
map <silent> [slimv]xb :call slimv#xref#xrefBinds()<CR>
map <silent> [slimv]xm :call slimv#xref#xrefMacroexpands()<CR>
map <silent> [slimv]xp :call slimv#xref#xrefSpecializes()<CR>
map <silent> [slimv]xl :call slimv#xref#xrefCallers()<CR>
map <silent> [slimv]xe :call slimv#xref#xrefCallees()<CR>

" Profile commands
map <silent> [slimv]p :<C-U>call slimv#profile()<CR>
map <silent> [slimv]P :<C-U>call slimv#profileSubstring()<CR>
map <silent> [slimv]U :<C-U>call slimv#unprofileAll()<CR>
map <silent> [slimv]? :<C-U>call slimv#showProfiled()<CR>
map <silent> [slimv]o :<C-U>call slimv#profileReport()<CR>
map <silent> [slimv]X :<C-U>call slimv#profileReset()<CR>

" Documentation commands
map <silent> [slimv]s :call slimv#describeSymbol()<CR>
map <silent> [slimv]A :call slimv#apropos()<CR>
map <silent> [slimv]h :call slimv#hyperspec()<CR>
map <silent> [slimv]] :call slimv#generateTags()<CR>

" REPL commands
map <silent> [slimv]c :call slimv#connectServer()<CR>
map <silent> [slimv]g :call slimv#setPackage()<CR>
map <silent> [slimv]y :call slimv#interrupt()<CR>
map <silent> [slimv]- :call slimv#repl#clear()<CR>
