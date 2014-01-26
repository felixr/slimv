import vim

from utils import logtime, logprint, unicode_len, unquote, parse_filepos, format_filename 
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
        # logprint(str(el))
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
    inspect_path = vim.eval('s:ctx.inspect_path')
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
    vim.command('call slimv#endUpdate()')

def swank_parse_inspect(struct):
    """
    Parse the swank inspector output
    """
    global inspect_lines
    global inspect_newline

    vim.command('call slimv#inspect#open()')
    vim.command('setlocal modifiable')
    buf = vim.current.buffer
    title = parse_plist(struct, ':title')
    vim.command('let b:inspect_title="' + title + '"')
    buf[:] = ['Inspecting ' + title, '--------------------', '']
    vim.command('normal! 3G0')
    vim.command('call slimv#buffer#help(2)')
    pcont = parse_plist(struct, ':content')
    inspect_lines = 3
    inspect_newline = True
    swank_parse_inspect_content(pcont)
    vim.command('call slimv#inspect#setPos("' + title + '")')

def swank_parse_debug(struct):
    """
    Parse the SLDB output
    """
    vim.command('call slimv#debug#openSldb()')
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
    vim.command('call slimv#endUpdate()')
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


def swank_parse_list_breakpoints(tl):
    vim.command('call slimv#buffer#open("BREAKPOINTS")')
    vim.command('setlocal modifiable')
    buf = vim.current.buffer
    buf[:] = ['Breakpoints', '--------------------']
    # vim.command('call slimv#buffer#help(2)')
    buf.append(['', 'Idx  ID  File                         Line  Enbled?', \
                    '---- --- ---------------------------- ----- -------'])
    vim.command('normal! G0')
    lst = tl[1]
    headers = lst.pop(0)
    # logprint(str(lst))
    idx = 0
    for t in lst:
        # t is a tuple of: 
        # ((:id :file :line :enabled)
        state = unquote(t[2])
        name = unquote(t[1])
        buf.append(["%3d: %3s %20s %6s %s" % (idx, t[0], t[1], t[2], t[3])])
        idx = idx + 1
    vim.command('normal! j')
    vim.command('call slimv#endUpdate()')


def swank_parse_list_threads(swank, tl):
    vim.command('call slimv#thread#open()')
    vim.command('setlocal modifiable')
    buf = vim.current.buffer
    buf[:] = ['Threads in pid '+swank.pid, '--------------------']
    vim.command('call slimv#buffer#help(2)')
    buf.append(['', 'Idx  ID      Status         Name                           Priority', \
                    '---- ------  ------------   ----------------------------   ---------'])
    vim.command('normal! G0')
    lst = tl[1]
    headers = lst.pop(0)
    # logprint(str(lst))
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
    vim.command('call slimv#endUpdate()')

def swank_parse_frame_call(struct, action):
    """
    Parse frame call output
    """
    vim.command('call slimv#gotoFrame(' + action.data + ')')
    vim.command('setlocal modifiable')
    buf = vim.current.buffer
    win = vim.current.window
    line = win.cursor[0]
    if type(struct) == list:
        buf[line:line] = [struct[1][1]]
    else:
        buf[line:line] = ['No frame call information']
    vim.command('call slimv#endUpdate()')

def swank_parse_frame_source(struct, action):
    """
    Parse frame source output
    http://comments.gmane.org/gmane.lisp.slime.devel/9961 ;-(
    'Well, let's say a missing feature: source locations are currently not available for code loaded as source.'
    """
    vim.command('call slimv#gotoFrame(' + action.data + ')')
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
    vim.command('call slimv#endUpdate()')

def swank_parse_locals(swank, struct, action):
    """
    Parse frame locals output
    """
    frame_num = action.data
    vim.command('call slimv#gotoFrame(' + frame_num + ')')
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
            swank.frame_locals[str(frame_num) + " " + name] = num
            num = num + 1
    else:
        lines = '    No locals'
    buf[line:line] = lines.split("\n")
    vim.command('call slimv#endUpdate()')

def parse_plist(lst, keyword):
    for i in range(0, len(lst), 2):
        if keyword == lst[i]:
            return unquote(lst[i+1])
    return ''

