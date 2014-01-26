slimv - SLIME for vim
======================

This is a fork of Tamas Kovacs' slimv plugin for vim.

**Changes in this fork:**

 - removed included paredit
     - this allows you to use alternative plugins, such as vim-sexp 
 - removed included SWANK server code
     - while it might be convenient to ship the code with slimv, I don't want it in my vim plugin directory
 - removed Clojure ftdetect and syntax (its now included in vim's runtime)
 - refactored slimv.vim into multiple autoload files
 - refactored swank.py into a module (multiple files)
     - I hope this will make slimv easier to extend and maintain

 
Description
-----------

Slimv is a SWANK client for Vim, similarly to SLIME for Emacs. SWANK is a TCP
server for Emacs, which runs a Common Lisp, Clojure or Scheme REPL and provides
a socket interface for evaluating, compiling, debugging, profiling lisp code. 

Slimv opens the lisp REPL (Read-Eval-Print Loop) inside a Vim buffer. Lisp
commands may be entered and executed in the REPL buffer, just as in a regular
REPL.

Slimv supports SLIME's debugger, inspector, profiler, cross reference, arglist,
indentation, symbol name completion functions. The script also has a Common
Lisp Hyperspec lookup feature and it is able to lookup symbols in the Clojure
API, as well as in JavaDoc.



Original version and documentation
-----------------------------------

The most recent development version of the original slimv version can be found at:
https://bitbucket.org/kovisoft/slimv

Please visit the Slimv Tutorial for a more complete introduction:
http://kovisoft.bitbucket.org/tutorial.html


The plugin in action
---------------------

<img src="http://i.imgur.com/0u82A1F.gif" alt="vim + slimv + clojure"/>
