import time
import vim

def unquote(s):
    if len(s) < 2:
        return s
    if s[0] == '"' and s[-1] == '"':
        slist = []
        esc = False
        for c in s[1:-1]:
            if not esc and c == '\\':
                esc = True
            elif esc and c == 'n':
                esc = False
                slist.append('\n')
            else:
                esc = False
                slist.append(c)
        return "".join(slist)
    else:
        return s

def requote(s):
    t = s.replace('\\', '\\\\')
    t = t.replace('"', '\\"')
    return '"' + t + '"'

def make_keys(lst):
    keys = {}
    for i in range(len(lst)):
        if i < len(lst)-1 and lst[i][0] == ':':
            keys[lst[i]] = unquote( lst[i+1] )
    return keys

###############################################################################
# Basic utility functions
###############################################################################

def logprint(logfile, text):
    f = open(logfile, "a")
    f.write(text + '\n')
    f.close()

def logtime(logfile, text):
    logprint(logfile, text + ' ' + str(time.time() % 1000))


def format_filename(fname):
    fname = vim.eval('fnamemodify(' + fname + ', ":~:.")')
    if fname.find(' '):
        fname = '"' + fname + '"'
    return fname

def parse_filepos(fname, loc):
    lnum = 1
    cnum = 1
    pos = loc
    try:
        f = open(fname, "r")
    except:
        return [0, 0]
    for line in f:
        if pos < len(line):
            cnum = pos
            break
        pos = pos - len(line)
        lnum = lnum + 1
    f.close()
    return [lnum, cnum]

def parse_location(lst):
    fname = ''
    line  = ''
    pos   = ''
    if lst[0] == ':location':
        if type(lst[1]) == str:
            return unquote(lst[1])
        for l in lst[1:]:
            if l[0] == ':file':
                fname = l[1]
            if l[0] == ':line':
                line = l[1]
            if l[0] == ':position':
                pos = l[1]
        if fname == '':
            fname = 'Unknown file'
        if line != '':
            return 'in ' + format_filename(fname) + ' line ' + line
        if pos != '':
            [lnum, cnum] = parse_filepos(unquote(fname), int(pos))
            if lnum > 0:
                return 'in ' + format_filename(fname) + ' line ' + str(lnum)
            else:
                return 'in ' + format_filename(fname) + ' byte ' + pos
    return 'no source line information'

def unicode_len(text, use_unicode):
    if use_unicode:
        return len(unicode(text, "utf-8"))
    else:
        return len(text)

def get_package():
    """
    Package set by slimv.vim or nil
    """
    pkg = vim.eval("s:ctx.swank_package")
    if pkg == '':
        return 'nil'
    else:
        return requote(pkg)

def get_swank_package(package):
    """
    Package set by slimv.vim or current swank package
    """
    pkg = vim.eval("s:ctx.swank_package")
    if pkg == '':
        return requote(package)
    else:
        return requote(pkg)

def get_indent_info(name):
    indent = ''
    if name in indent_info:
        indent = indent_info[name]
    vc = ":let s:ctx.indent='" + indent + "'"
    vim.command(vc)

