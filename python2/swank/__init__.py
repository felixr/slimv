# vim: sw=4 et :
###############################################################################
#
# SWANK client for Slimv
# swank.py:     SWANK client code for slimv.vim plugin
# Version:      0.9.12
# Last Change:  14 Dec 2013
# Maintainer:   Tamas Kovacs <kovisoft at gmail dot com>
# License:      This file is placed in the public domain.
#               No warranty, express or implied.
#               *** ***   Use At-Your-Own-Risk!   *** ***
# 
############################################################################### 


import string
import vim

from utils import requote, unquote, get_swank_package, get_package
from client import SwankSocket

swank = SwankSocket()

###############################################################################
# Various SWANK messages
###############################################################################

def swank_create_repl():
    swank.rex(':create-repl', '(swank:create-repl nil)', get_swank_package(swank.package), 't')

def swank_eval(exp):
    cmd = '(swank:listener-eval ' + requote(exp) + ')'
    swank.rex(':listener-eval', cmd, get_swank_package(swank.package), ':repl-thread')

def swank_eval_in_frame(exp, n):
    cmd = '(swank:eval-string-in-frame ' + requote(exp) + ' ' + str(n) + ')'
    swank.rex(':eval-string-in-frame', cmd, get_swank_package(swank.package), swank.current_thread, str(n))

def swank_pprint_eval(exp):
    cmd = '(swank:pprint-eval ' + requote(exp) + ')'
    swank.rex(':pprint-eval', cmd, get_swank_package(swank.package), ':repl-thread')

def swank_interrupt():
    swank.send('(:emacs-interrupt :repl-thread)')

def swank_invoke_restart(level, restart):
    cmd = '(swank:invoke-nth-restart-for-emacs ' + level + ' ' + restart + ')'
    swank.rex(':invoke-nth-restart-for-emacs', cmd, 'nil', swank.current_thread, restart)

def swank_throw_toplevel():
    swank.rex(':throw-to-toplevel', '(swank:throw-to-toplevel)', 'nil', swank.current_thread)

def swank_invoke_abort():
    swank.rex(':sldb-abort', '(swank:sldb-abort)', 'nil', swank.current_thread)

def swank_invoke_continue():
    swank.rex(':sldb-continue', '(swank:sldb-continue)', 'nil', swank.current_thread)

def swank_require(contrib):
    cmd = "(swank:swank-require '" + contrib + ')'
    swank.rex(':swank-require', cmd, 'nil', 't')

def swank_frame_call(frame):
    cmd = '(swank-backend:frame-call ' + frame + ')'
    swank.rex(':frame-call', cmd, 'nil', swank.current_thread, frame)

def swank_frame_source_loc(frame):
    cmd = '(swank:frame-source-location ' + frame + ')'
    swank.rex(':frame-source-location', cmd, 'nil', swank.current_thread, frame)

def swank_frame_locals(frame):
    cmd = '(swank:frame-locals-and-catch-tags ' + frame + ')'
    swank.rex(':frame-locals-and-catch-tags', cmd, 'nil', swank.current_thread, frame)

def swank_restart_frame(frame):
    cmd = '(swank-backend:restart-frame ' + frame + ')'
    swank.rex(':restart-frame', cmd, 'nil', swank.current_thread, frame)

def swank_set_package(pkg):
    cmd = '(swank:set-package "' + pkg + '")'
    swank.rex(':set-package', cmd, get_package(), ':repl-thread')

def swank_describe_symbol(fn):
    cmd = '(swank:describe-symbol "' + fn + '")'
    swank.rex(':describe-symbol', cmd, get_package(), 't')

def swank_describe_function(fn):
    cmd = '(swank:describe-function "' + fn + '")'
    swank.rex(':describe-function', cmd, get_package(), 't')

def swank_op_arglist(op):
    pkg = get_swank_package(swank.package)
    cmd = '(swank:operator-arglist "' + op + '" ' + pkg + ')'
    swank.rex(':operator-arglist', cmd, pkg, 't')

def swank_completions(symbol):
    cmd = '(swank:simple-completions "' + symbol + '" ' + get_swank_package(swank.package) + ')'
    swank.rex(':simple-completions', cmd, 'nil', 't')

def swank_fuzzy_completions(symbol):
    cmd = '(swank:fuzzy-completions "' + symbol + '" ' + get_swank_package(swank.package) + ' :limit 2000 :time-limit-in-msec 2000)' 
    swank.rex(':fuzzy-completions', cmd, 'nil', 't')

def swank_undefine_function(fn):
    cmd = '(swank:undefine-function "' + fn + '")'
    swank.rex(':undefine-function', cmd, get_package(), 't')

def swank_return_string(s):
    swank.send('(:emacs-return-string ' + swank.read_string[0] + ' ' + swank.read_string[1] + ' ' + requote(s) + ')')
    swank.read_string = None

def swank_return(s):
    if s != '':
        swank.send('(:emacs-return ' + swank.read_string[0] + ' ' + swank.read_string[1] + ' "' + s + '")')
    swank.read_string = None

def swank_inspect(symbol):
    cmd = '(swank:init-inspector "' + symbol + '")'
    swank.inspect_package = get_swank_package(swank.package) 
    swank.rex(':init-inspector', cmd, swank.inspect_package, 't')

def swank_inspect_nth_part(n):
    cmd = '(swank:inspect-nth-part ' + str(n) + ')'
    swank.rex(':inspect-nth-part', cmd, get_swank_package(swank.package), 't', str(n))

def swank_inspector_nth_action(n):
    cmd = '(swank:inspector-call-nth-action ' + str(n) + ')'
    swank.rex(':inspector-call-nth-action', cmd, 'nil', 't', str(n))

def swank_inspector_pop():
    # Remove the last entry from the inspect path
    vim.command('let s:ctx.inspect_path = s:ctx.inspect_path[:-2]')
    swank.rex(':inspector-pop', '(swank:inspector-pop)', 'nil', 't')

def swank_inspect_in_frame(symbol, n):
    key = str(n) + " " + symbol
    if swank.frame_locals.has_key(key):
        cmd = '(swank:inspect-frame-var ' + str(n) + " " + str(swank.frame_locals[key]) + ')'
    else:
        cmd = '(swank:inspect-in-frame "' + symbol + '" ' + str(n) + ')'
    swank.rex(':inspect-in-frame', cmd, get_swank_package(swank.package), swank.current_thread, str(n))

def swank_inspector_range():
    start = int(vim.eval("b:range_start"))
    end   = int(vim.eval("b:range_end"))
    cmd = '(swank:inspector-range ' + str(end) + " " + str(end+(end-start)) + ')'
    swank.rex(':inspector-range', cmd, inspect_package, 't')

def swank_quit_inspector():
    swank.rex(':quit-inspector', '(swank:quit-inspector)', 'nil', 't')
    swank.inspect_package = ''

def swank_break_on_exception(flag):
    if flag:
        swank.rex(':break-on-exception', '(swank:break-on-exception "true")', 'nil', swank.current_thread)
    else:
        swank.rex(':break-on-exception', '(swank:break-on-exception "false")', 'nil', swank.current_thread)

def swank_set_break(symbol):
    cmd = '(swank:sldb-break "' + symbol + '")'
    swank.rex(':sldb-break', cmd, get_package(), 't')


def swank_toggle_logging():
    cmd = '(swank:toggle-swank-logging)'
    swank.rex(':toggle-swank-logging', cmd, 'nil', 't')

def swank_list_breakpoints():
    cmd = '(swank:list-breakpoints)'
    swank.rex(':list-breakpoints', cmd, 'nil', 't')

def swank_line_breakpoint():
    filename = vim.eval("substitute( expand('%:p'), '\\', '/', 'g' )")
    line = vim.eval("line('.')")
    cmd = '(swank:line-breakpoint ' + get_package() +" "+ requote(filename) + " " + str(line) +")"
    # cmd = '(swank:line-breakpoint ' + get_package() +" nil " + str(line) +")"
    swank.rex(':line-breakpoint', cmd, get_package(), 't')

def swank_toggle_trace(symbol):
    cmd = '(swank:swank-toggle-trace "' + symbol + '")'
    swank.rex(':swank-toggle-trace', cmd, get_package(), 't')

def swank_untrace_all():
    swank.rex(':untrace-all', '(swank:untrace-all)', 'nil', 't')

def swank_macroexpand(formvar):
    form = vim.eval(formvar)
    cmd = '(swank:swank-macroexpand-1 ' + requote(form) + ')'
    swank.rex(':swank-macroexpand-1', cmd, get_package(), 't')

def swank_macroexpand_all(formvar):
    form = vim.eval(formvar)
    cmd = '(swank:swank-macroexpand-all ' + requote(form) + ')'
    swank.rex(':swank-macroexpand-all', cmd, get_package(), 't')

def swank_disassemble(symbol):
    cmd = '(swank:disassemble-form "' + "'" + symbol + '")'
    swank.rex(':disassemble-form', cmd, get_package(), 't')

def swank_xref(fn, type):
    cmd = "(swank:xref '" + type + " '" + '"' + fn + '")'
    swank.rex(':xref', cmd, get_package(), 't')

def swank_compile_string(formvar):
    form = vim.eval(formvar)
    filename = vim.eval("substitute( expand('%:p'), '\\', '/', 'g' )")
    line = vim.eval("line('.')")
    pos = vim.eval("line2byte(line('.'))")
    if vim.eval("&fileformat") == 'dos':
        # Remove 0x0D, keep 0x0A characters
        pos = str(int(pos) - int(line) + 1)
    cmd = '(swank:compile-string-for-emacs ' + requote(form) + ' nil ' + "'((:position " + str(pos) + ") (:line " + str(line) + " 1)) " + requote(filename) + ' nil)'
    swank.rex(':compile-string-for-emacs', cmd, get_package(), 't')

def swank_compile_file(name):
    cmd = '(swank:compile-file-for-emacs ' + requote(name) + ' t)'
    swank.rex(':compile-file-for-emacs', cmd, get_package(), 't')

def swank_load_file(name):
    cmd = '(swank:load-file ' + requote(name) + ')'
    swank.rex(':load-file', cmd, get_package(), 't')

def swank_toggle_profile(symbol):
    cmd = '(swank:toggle-profile-fdefinition "' + symbol + '")'
    swank.rex(':toggle-profile-fdefinition', cmd, get_package(), 't')

def swank_profile_substring(s, package):
    if package == '':
        p = 'nil'
    else:
        p = requote(package)
    cmd = '(swank:profile-by-substring ' + requote(s) + ' ' + p + ')'
    swank.rex(':profile-by-substring', cmd, get_package(), 't')

def swank_unprofile_all():
    swank.rex(':unprofile-all', '(swank:unprofile-all)', 'nil', 't')

def swank_profiled_functions():
    swank.rex(':profiled-functions', '(swank:profiled-functions)', 'nil', 't')

def swank_profile_report():
    swank.rex(':profile-report', '(swank:profile-report)', 'nil', 't')

def swank_profile_reset():
    swank.rex(':profile-reset', '(swank:profile-reset)', 'nil', 't')

def swank_list_threads():
    cmd = '(swank:list-threads)'
    swank.rex(':list-threads', cmd, get_swank_package(swank.package), 't')

def swank_kill_thread(index):
    cmd = '(swank:kill-nth-thread ' + str(index) + ')'
    swank.rex(':kill-thread', cmd, get_swank_package(swank.package), 't', str(index))

def swank_debug_thread(index):
    cmd = '(swank:debug-nth-thread ' + str(index) + ')'
    swank.rex(':debug-thread', cmd, get_swank_package(swank.package), 't', str(index))

###############################################################################
# Generic SWANK connection handling
###############################################################################

def swank_connection_info():
    swank.connection_info()

def swank_connect(host, port, resultvar):
    return swank.connect(host, port, resultvar)

def swank_disconnect():
    return swank.disconnect()

def swank_input(formvar):
    swank.empty_last_line = True
    form = vim.eval(formvar)
    if swank.read_string:
        # We are in :read-string mode, pass string entered to REPL
        swank_return_string(form)
    elif form[0] == '[':
        if form[1] == '-':
            swank_inspector_pop()
        else:
            swank_inspect_nth_part(form[1:-2])
    elif form[0] == '<':
        swank_inspector_nth_action(form[1:-2])
    else:
        # Normal s-expression evaluation
        swank_eval(form)
