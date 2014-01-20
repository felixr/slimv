
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
# Swank server interface
###############################################################################

def swank_parse_inspect_content(pcont):
    """
    Parse the swank inspector content
    """
    global inspect_lines
    global inspect_newline

    if type(pcont[0]) != list:
        return
    vim.command('setlocal modifiable')
    buf = vim.current.buffer
    help_lines = int( vim.eval('exists("b:help_shown") ? len(b:help) : 1') )
    pos = help_lines + inspect_lines
    buf[pos:] = []
    istate = pcont[1]
    start  = pcont[2]
    end    = pcont[3]
    lst = []
    for el in pcont[0]:
        logprint(str(el))
        newline = False
        if type(el) == list:
            if el[0] == ':action':
                text = '{<' + unquote(el[2]) + '> ' + unquote(el[1]) + ' <>}'
            else:
                text = '{[' + unquote(el[2]) + '] ' + unquote(el[1]) + ' []}'
            lst.append(text)
        else:
            text = unquote(el)
            lst.append(text)
            if text == "\n":
                newline = True
    lines = "".join(lst).split("\n")
    if inspect_newline or pos > len(buf):
        buf.append(lines)
    else:
        buf[pos-1] = buf[pos-1] + lines[0]
        buf.append(lines[1:])
    inspect_lines = len(buf) - help_lines
    inspect_newline = newline
    if int(istate) > int(end):
        # Swank returns end+1000 if there are more entries to request
        buf.append(['', "[--more--]", "[--all---]"])
    inspect_path = vim.eval('s:inspect_path')
    if len(inspect_path) > 1:
        buf.append(['', '[<<] Return to ' + ' -> '.join(inspect_path[:-1])])
    else:
        buf.append(['', '[<<] Exit Inspector'])
    if int(istate) > int(end):
        # There are more entries to request
        # Save current range for the next request
        vim.command("let b:range_start=" + start)
        vim.command("let b:range_end=" + end)
        vim.command("let b:inspect_more=" + end)
    else:
        # No ore entries left
        vim.command("let b:inspect_more=0")
    vim.command('call SlimvEndUpdate()')

def swank_parse_inspect(struct):
    """
    Parse the swank inspector output
    """
    global inspect_lines
    global inspect_newline

    vim.command('call SlimvOpenInspectBuffer()')
    vim.command('setlocal modifiable')
    buf = vim.current.buffer
    title = parse_plist(struct, ':title')
    vim.command('let b:inspect_title="' + title + '"')
    buf[:] = ['Inspecting ' + title, '--------------------', '']
    vim.command('normal! 3G0')
    vim.command('call SlimvHelp(2)')
    pcont = parse_plist(struct, ':content')
    inspect_lines = 3
    inspect_newline = True
    swank_parse_inspect_content(pcont)
    vim.command('call SlimvSetInspectPos("' + title + '")')

def swank_parse_debug(struct):
    """
    Parse the SLDB output
    """
    vim.command('call SlimvOpenSldbBuffer()')
    vim.command('setlocal modifiable')
    buf = vim.current.buffer
    [thread, level, condition, restarts, frames, conts] = struct[1:7]
    buf[:] = [l for l in (unquote(condition[0]) + "\n" + unquote(condition[1])).splitlines()]
    buf.append(['', 'Restarts:'])
    for i in range( len(restarts) ):
        r0 = unquote( restarts[i][0] )
        r1 = unquote( restarts[i][1] )
        r1 = r1.replace("\n", " ")
        buf.append([str(i).rjust(3) + ': [' + r0 + '] ' + r1])
    buf.append(['', 'Backtrace:'])
    for f in frames:
        frame = str(f[0])
        ftext = unquote( f[1] )
        ftext = ftext.replace('\n', '')
        ftext = ftext.replace('\\\\n', '')
        buf.append([frame.rjust(3) + ': ' + ftext])
    vim.command('call SlimvEndUpdate()')
    vim.command("call search('^Restarts:', 'w')")
    vim.command('stopinsert')
    # This text will be printed into the REPL buffer
    return unquote(condition[0]) + "\n" + unquote(condition[1]) + "\n"

def swank_parse_xref(struct):
    """
    Parse the swank xref output
    """
    buf = ''
    for e in struct:
        buf = buf + unquote(e[0]) + ' - ' + parse_location(e[1]) + '\n'
    return buf

def swank_parse_compile(struct):
    """
    Parse compiler output
    """
    buf = ''
    warnings = struct[1]
    time = struct[3]
    filename = ''
    if len(struct) > 5:
        filename = struct[5]
    if filename == '' or filename[0] != '"':
        filename = '"' + filename + '"'
    vim.command('let s:compiled_file=' + filename + '')
    vim.command("let qflist = []")
    if type(warnings) == list:
        buf = '\n' + str(len(warnings)) + ' compiler notes:\n\n'
        for w in warnings:
            msg      = parse_plist(w, ':message')
            severity = parse_plist(w, ':severity')
            if severity[0] == ':':
                severity = severity[1:]
            location = parse_plist(w, ':location')
            if location[0] == ':error':
                # "no error location available"
                buf = buf + '  ' + unquote(location[1]) + '\n'
                buf = buf + '  ' + severity + ': ' + msg + '\n\n'
            else:
                fname   = unquote(location[1][1])
                pos     = location[2][1]
                if location[3] != 'nil':
                    snippet = unquote(location[3][1]).replace('\r', '')
                    buf = buf + snippet + '\n'
                buf = buf + fname + ':' + pos + '\n'
                buf = buf + '  ' + severity + ': ' + msg + '\n\n' 
                if location[2][0] == ':line':
                    lnum = pos
                    cnum = 1
                else:
                    [lnum, cnum] = parse_filepos(fname, int(pos))
                msg = msg.replace("'", "' . \"'\" . '")
                qfentry = "{'filename':'"+fname+"','lnum':'"+str(lnum)+"','col':'"+str(cnum)+"','text':'"+msg+"'}"
                logprint(qfentry)
                vim.command("call add(qflist, " + qfentry + ")")
    else:
        buf = '\nCompilation finished. (No warnings)  [' + time + ' secs]\n\n'
    vim.command("call setqflist(qflist)")
    return buf

def swank_parse_list_breakpoints(tl):
    vim.command('call SlimvOpenBuffer("BREAKPOINTS")')
    vim.command('setlocal modifiable')
    buf = vim.current.buffer
    # buf[:] = ['Threads in pid '+pid, '--------------------']
    # vim.command('call SlimvHelp(2)')
    # buf.append(['', 'Idx  ID      Status         Name                           Priority', \
    #                 '---- ------  ------------   ----------------------------   ---------'])
    vim.command('normal! G0')
    lst = tl[1]
    headers = lst.pop(0)
    logprint(str(lst))
    idx = 0
    for t in lst:
        # t is a tuple of: 
        # ((:id :file :line :enabled)
        state = unquote(t[2])
        name = unquote(t[1])
        buf.append(["%3d:  %s %s %s %s" % (idx, t[0], t[1], t[2], t[3])])
        idx = idx + 1
    vim.command('normal! j')
    vim.command('call SlimvEndUpdate()')


def swank_parse_list_threads(tl):
    vim.command('call SlimvOpenThreadsBuffer()')
    vim.command('setlocal modifiable')
    buf = vim.current.buffer
    buf[:] = ['Threads in pid '+pid, '--------------------']
    vim.command('call SlimvHelp(2)')
    buf.append(['', 'Idx  ID      Status         Name                           Priority', \
                    '---- ------  ------------   ----------------------------   ---------'])
    vim.command('normal! G0')
    lst = tl[1]
    headers = lst.pop(0)
    logprint(str(lst))
    idx = 0
    for t in lst:
        priority = ''
        if len(t) > 3:
            priority = unquote(t[3])

        # t is a tuple of: 
        # (:id :name :state :at-breakpoint? :suspended? :suspends) 
        try:
            id = "%5d" % int(t[0])
        except ValueError:
            id = " "*5 

        state = unquote(t[2])
        name = unquote(t[1])
        buf.append(["%3d:  %s  %-15s %-29s %s" % (idx, id, state, name, priority)])
        idx = idx + 1
    vim.command('normal! j')
    vim.command('call SlimvEndUpdate()')

def swank_parse_frame_call(struct, action):
    """
    Parse frame call output
    """
    vim.command('call SlimvGotoFrame(' + action.data + ')')
    vim.command('setlocal modifiable')
    buf = vim.current.buffer
    win = vim.current.window
    line = win.cursor[0]
    if type(struct) == list:
        buf[line:line] = [struct[1][1]]
    else:
        buf[line:line] = ['No frame call information']
    vim.command('call SlimvEndUpdate()')

def swank_parse_frame_source(struct, action):
    """
    Parse frame source output
    http://comments.gmane.org/gmane.lisp.slime.devel/9961 ;-(
    'Well, let's say a missing feature: source locations are currently not available for code loaded as source.'
    """
    vim.command('call SlimvGotoFrame(' + action.data + ')')
    vim.command('setlocal modifiable')
    buf = vim.current.buffer
    win = vim.current.window
    line = win.cursor[0]
    if type(struct) == list and len(struct) == 4:
        if struct[1] == 'nil':
            [lnum, cnum] = [int(struct[2][1]), 1]
            fname = 'Unknown file'
        else:
            [lnum, cnum] = parse_filepos(unquote(struct[1][1]), int(struct[2][1]))
            fname = format_filename(struct[1][1])
        if lnum > 0:
            s = '      in ' + fname + ' line ' + str(lnum)
        else:
            s = '      in ' + fname + ' byte ' + struct[2][1]
        slines = s.splitlines()
        if len(slines) > 2:
            # Make a fold (closed) if there are too many lines
            slines[ 0] = slines[ 0] + '{{{'
            slines[-1] = slines[-1] + '}}}'
            buf[line:line] = slines
            vim.command(str(line+1) + 'foldclose')
        else:
            buf[line:line] = slines
    else:
        buf[line:line] = ['      No source line information']
    vim.command('call SlimvEndUpdate()')

def swank_parse_locals(struct, action):
    """
    Parse frame locals output
    """
    frame_num = action.data
    vim.command('call SlimvGotoFrame(' + frame_num + ')')
    vim.command('setlocal modifiable')
    buf = vim.current.buffer
    win = vim.current.window
    line = win.cursor[0]
    if type(struct) == list:
        lines = '    Locals:'
        num = 0
        for f in struct:
            name  = parse_plist(f, ':name')
            id    = parse_plist(f, ':id')
            value = parse_plist(f, ':value')
            lines = lines + '\n      ' + name + ' = ' + value
            # Remember variable index in frame
            frame_locals[str(frame_num) + " " + name] = num
            num = num + 1
    else:
        lines = '    No locals'
    buf[line:line] = lines.split("\n")
    vim.command('call SlimvEndUpdate()')


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
    swank.rex(':eval-string-in-frame', cmd, get_swank_package(swank.package), current_thread, str(n))

def swank_pprint_eval(exp):
    cmd = '(swank:pprint-eval ' + requote(exp) + ')'
    swank.rex(':pprint-eval', cmd, get_swank_package(swank.package), ':repl-thread')

def swank_interrupt():
    swank.send('(:emacs-interrupt :repl-thread)')

def swank_invoke_restart(level, restart):
    cmd = '(swank:invoke-nth-restart-for-emacs ' + level + ' ' + restart + ')'
    swank.rex(':invoke-nth-restart-for-emacs', cmd, 'nil', current_thread, restart)

def swank_throw_toplevel():
    swank.rex(':throw-to-toplevel', '(swank:throw-to-toplevel)', 'nil', current_thread)

def swank_invoke_abort():
    swank.rex(':sldb-abort', '(swank:sldb-abort)', 'nil', current_thread)

def swank_invoke_continue():
    swank.rex(':sldb-continue', '(swank:sldb-continue)', 'nil', current_thread)

def swank_require(contrib):
    cmd = "(swank:swank-require '" + contrib + ')'
    swank.rex(':swank-require', cmd, 'nil', 't')

def swank_frame_call(frame):
    cmd = '(swank-backend:frame-call ' + frame + ')'
    swank.rex(':frame-call', cmd, 'nil', current_thread, frame)

def swank_frame_source_loc(frame):
    cmd = '(swank:frame-source-location ' + frame + ')'
    swank.rex(':frame-source-location', cmd, 'nil', current_thread, frame)

def swank_frame_locals(frame):
    cmd = '(swank:frame-locals-and-catch-tags ' + frame + ')'
    swank.rex(':frame-locals-and-catch-tags', cmd, 'nil', current_thread, frame)

def swank_restart_frame(frame):
    cmd = '(swank-backend:restart-frame ' + frame + ')'
    swank.rex(':restart-frame', cmd, 'nil', current_thread, frame)

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
    vim.command('let s:inspect_path = s:inspect_path[:-2]')
    swank.rex(':inspector-pop', '(swank:inspector-pop)', 'nil', 't')

def swank_inspect_in_frame(symbol, n):
    key = str(n) + " " + symbol
    if swank.frame_locals.has_key(key):
        cmd = '(swank:inspect-frame-var ' + str(n) + " " + str(swank.frame_locals[key]) + ')'
    else:
        cmd = '(swank:inspect-in-frame "' + symbol + '" ' + str(n) + ')'
    swank.rex(':inspect-in-frame', cmd, get_swank_package(swank.package), current_thread, str(n))

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
        swank.rex(':break-on-exception', '(swank:break-on-exception "true")', 'nil', current_thread)
    else:
        swank.rex(':break-on-exception', '(swank:break-on-exception "false")', 'nil', current_thread)

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

def swank_output(self):
    swank.output()

def swank_response(name):
    swank.response(name)

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

def swank_response(name):
    swank.response(name)

def swank_output(echo):
    swank.output(echo)
