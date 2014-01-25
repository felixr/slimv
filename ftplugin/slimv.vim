" slimv.vim:    The Superior Lisp Interaction Mode for VIM
" Version:      0.9.12
" Last Change:  15 Dec 2013
" Maintainer:   Tamas Kovacs <kovisoft at gmail dot com>
" License:      This file is placed in the public domain.
"               No warranty, express or implied.
"               *** ***   Use At-Your-Own-Risk!   *** ***
"
" =====================================================================
"
"  Load Once:
if &cp || exists( 'g:slimv_loaded' )
    finish
endif

let g:slimv_loaded = 1

let g:slimv_windows = 0
let g:slimv_cygwin  = 0
let g:slimv_osx     = 0

if has( 'win32' ) || has( 'win95' ) || has( 'win64' ) || has( 'win16' )
    let g:slimv_windows = 1
elseif has( 'win32unix' )
    let g:slimv_cygwin = 1
elseif has( 'macunix' )
    let g:slimv_osx = 1
endif


" =====================================================================
"  Functions used by global variable definitions
" =====================================================================

" Convert Cygwin path to Windows path, if needed
function! s:Cygpath( path )
    let path = a:path
    if g:slimv_cygwin
        let path = system( 'cygpath -w ' . path )
        let path = substitute( path, "\n", "", "g" )
        let path = substitute( path, "\\", "/", "g" )
    endif
    return path
endfunction

" Find swank.py in the Vim ftplugin directory (if not given in vimrc)
if !exists( 'g:swank_path' )
    let plugins = split( globpath( &runtimepath, 'ftplugin/**/swank.py'), '\n' )
    if len( plugins ) > 0
        let g:swank_path = s:Cygpath( plugins[0] )
    else
        let g:swank_path = 'swank.py'
    endif
endif


" =====================================================================
"  Global variable definitions
" =====================================================================

" Host name or IP address of the SWANK server
if !exists( 'g:swank_host' )
    let g:swank_host = 'localhost'
endif

" TCP port number to use for the SWANK server
if !exists( 'g:swank_port' )
    let g:swank_port = 4005
endif

" Find Lisp (if not given in vimrc)
if !exists( 'g:slimv_lisp' )
    let lisp = ['', '']
    if exists( 'g:slimv_preferred' )
        let lisp = b:SlimvAutodetect( tolower(g:slimv_preferred) )
    endif
    if lisp[0] == ''
        let lisp = b:SlimvAutodetect( '' )
    endif
    let g:slimv_lisp = lisp[0]
    if !exists( 'g:slimv_impl' )
        let g:slimv_impl = lisp[1]
    endif
endif

" Try to find out the Lisp implementation
" if not autodetected and not given in vimrc
if !exists( 'g:slimv_impl' )
    let g:slimv_impl = b:SlimvImplementation()
endif

" REPL buffer name
if !exists( 'g:slimv_repl_name' )
    let g:slimv_repl_name = 'REPL'
endif

" SLDB buffer name
if !exists( 'g:slimv_sldb_name' )
    let g:slimv_sldb_name = 'SLDB'
endif

" INSPECT buffer name
if !exists( 'g:slimv_inspect_name' )
    let g:slimv_inspect_name = 'INSPECT'
endif

" THREADS buffer name
if !exists( 'g:slimv_threads_name' )
    let g:slimv_threads_name = 'THREADS'
endif

" Shall we open REPL buffer in split window?
if !exists( 'g:slimv_repl_split' )
    let g:slimv_repl_split = 1
endif

" Wrap long lines in REPL buffer
if !exists( 'g:slimv_repl_wrap' )
    let g:slimv_repl_wrap = 1
endif

" Wrap long lines in SLDB buffer
if !exists( 'g:slimv_sldb_wrap' )
    let g:slimv_sldb_wrap = 0
endif

" Maximum number of lines echoed from the evaluated form
if !exists( 'g:slimv_echolines' )
    let g:slimv_echolines = 4
endif

" Syntax highlighting for the REPL buffer
if !exists( 'g:slimv_repl_syntax' )
    let g:slimv_repl_syntax = 1
endif

" Specifies the behaviour of insert mode <CR>, <Up>, <Down> in the REPL buffer:
" 1: <CR>   evaluates,      <Up>/<Down>     brings up command history
" 0: <C-CR> evaluates,      <C-Up>/<C-Down> brings up command history,
"    <CR>   opens new line, <Up>/<Down>     moves cursor up/down
if !exists( 'g:slimv_repl_simple_eval' )
    let g:slimv_repl_simple_eval = 1
endif

" Alternative value (in msec) for 'updatetime' while the REPL buffer is changing
if !exists( 'g:slimv_updatetime' )
    let g:slimv_updatetime = 500
endif

" Slimv keybinding set (0 = no keybindings)
if !exists( 'g:slimv_keybindings' )
    let g:slimv_keybindings = 1
endif

" Append Slimv menu to the global menu (0 = no menu)
if !exists( 'g:slimv_menu' )
    let g:slimv_menu = 1
endif

" Build the ctags command capable of generating lisp tags file
" The command can be run with execute 'silent !' . g:slimv_ctags
if !exists( 'g:slimv_ctags' )
    let ctags = split( globpath( '$vim,$vimruntime', 'ctags.exe' ), '\n' )
    if len( ctags ) > 0
        " Remove -a option to regenerate every time
        let g:slimv_ctags = '"' . ctags[0] . '" -a --language-force=lisp *.lisp *.clj'
    endif
endif

" Package/namespace handling
if !exists( 'g:slimv_package' )
    let g:slimv_package = 1
endif

" General timeout for various startup and connection events (seconds)
if !exists( 'g:slimv_timeout' )
    let g:slimv_timeout = 20
endif

" Use balloonexpr to display symbol description
if !exists( 'g:slimv_balloon' )
    let g:slimv_balloon = 1
endif

" Shall we use simple or fuzzy completion?
if !exists( 'g:slimv_simple_compl' )
    let g:slimv_simple_compl = 0
endif

" Custom <Leader> for the Slimv plugin
if !exists( 'g:slimv_leader' )
    if exists( 'mapleader' ) && mapleader != ' '
        let g:slimv_leader = mapleader
    else
        let g:slimv_leader = ','
    endif
endif

" Maximum number of lines searched backwards for indenting special forms
if !exists( 'g:slimv_indent_maxlines' )
    let g:slimv_indent_maxlines = 50
endif

" Special indentation for keyword lists
if !exists( 'g:slimv_indent_keylists' )
    let g:slimv_indent_keylists = 1
endif

" Maximum length of the REPL buffer
if !exists( 'g:slimv_repl_max_len' )
    let g:slimv_repl_max_len = 0
endif

" =====================================================================
"  Template definitions
" =====================================================================

if !exists( 'g:slimv_template_apropos' )
    if slimv#getFiletype() =~ '.*clojure.*'
        let g:slimv_template_apropos = '(find-doc "%1")'
    else
        let g:slimv_template_apropos = '(apropos "%1")'
    endif
endif

" =====================================================================
"  Slimv commands
" =====================================================================

command! -complete=customlist,slimv#commandComplete -nargs=* Lisp call slimv#eval([<q-args>])
command! -complete=customlist,slimv#commandComplete -nargs=* Eval call slimv#eval([<q-args>])

" Switch on syntax highlighting
if !exists("g:syntax_on")
    syntax on
endif
