import socket
import vim
import select
from utils import logtime, logprint, unicode_len, unquote, make_keys

from sexpr import parse_sexpr


class SwankAction:
    def __init__ (self, id, name, data):
        self.id = id
        self.name = name
        self.data = data
        self.result = ''
        self.pending = True

class SwankSocket(object):

    def __init__(self):
        self.actions         = dict()        # Swank actions (like ':write-string'), by message id
        self.current_thread  = '0'
        self.debug_activated = False         # Swank debugger was activated
        self.debug_active    = False         # Swank debugger is active
        self.debug           = False
        self.empty_last_line = True          # Swank output ended with a new line
        self.frame_locals    = dict()        # Map frame variable names to their index
        self.id              = 0             # Message id
        self.indent_info     = dict()        # Data of :indentation-update
        self.input_port      = 4005
        self.inspect_lines   = 0             # Number of lines in the Inspector (excluding help text)
        self.inspect_newline = True          # Start a new line in the Inspector (for multi-part objects)
        self.inspect_package = ''            # Package used for the current Inspector
        self.lenbytes        = 6             # Message length is encoded in this number of bytes
        self.listen_retries  = 10            # number of retries if no response in swank_listen()
        self.log             = False         # Set this to True in order to enable logging
        self.logfile         = 'swank.log'   # Logfile name in case logging is on
        self.maxmessages     = 50            # Maximum number of messages to receive in one listening session
        self.output_port     = 4006
        self.package         = 'COMMON-LISP-USER' # Current package
        self.pid             = '0'           # Process id
        self.prompt          = 'SLIMV'       # Command prompt
        self.read_string     = None          # Thread and tag in Swank read string mode
        self.recv_timeout    = 0.001         # socket recv timeout in seconds
        self.sock            = None          # Swank socket object
        self.use_unicode     = True          # Use unicode message length counting

    def connect(self, host, port, resultvar):
        """
        Create socket to swank server and request connection info
        """
        if not self.sock:
            try:
                self.input_port = port
                swank_server = (host, self.input_port)
                self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                self.sock.connect(swank_server)
                self.connection_info()
                vim.command('let ' + resultvar + '=""')
                return self.sock
            except socket.error:
                vim.command('let ' + resultvar + '="SWANK server is not running."')
                self.sock = None
                return self.sock
        vim.command('let ' + resultvar + '=""')


    def send(self, text):
        if self.log:
            logtime(self.logfile,'[---Sent---]')
            logprint(self.logfile,text)
        l = "%06x" % unicode_len(text, self.use_unicode)
        t = l + text
        if self.debug:
            print 'Sending:', t
        try:
            self.sock.send(t)
        except socket.error:
            vim.command("let s:swank_result='Socket error when sending to SWANK server.\n'")
            self.disconnect()

    def disconnect(self):
        """
        Disconnect from swank server
        """
        try:
            # Try to close socket but don't care if doesn't succeed
            self.sock.close()
        finally:
            self.sock = None
            vim.command('let s:swank_connected = 0')
            vim.command("let s:swank_result='Connection to SWANK server is closed.\n'")

    def recv_len(self, timeout):
        rec = ''
        self.sock.setblocking(0)
        ready = select.select([self.sock], [], [], timeout)
        if ready[0]:
            l = self.lenbytes
            self.sock.setblocking(1)
            try:
                data = self.sock.recv(l)
            except socket.error:
                vim.command("let s:swank_result='Socket error when receiving from SWANK server.\n'")
                self.disconnect()
                return rec
            while data and len(rec) < self.lenbytes:
                rec = rec + data
                l = l - len(data)
                if l > 0:
                    try:
                        data = self.sock.recv(l)
                    except socket.error:
                        vim.command("let s:swank_result='Socket error when receiving from SWANK server.\n'")
                        self.disconnect()
                        return rec
        return rec

    def recv(self, msglen, timeout):
        if msglen > 0:
            self.sock.setblocking(0)
            ready = select.select([self.sock], [], [], timeout)
            if ready[0]:
                self.sock.setblocking(1)
                rec = ''
                while True:
                    # Each codepoint has at least 1 byte; so we start with the 
                    # number of bytes, and read more if needed.
                    try:
                        needed = msglen - unicode_len(rec, self.use_unicode)
                    except UnicodeDecodeError:
                        # Add single bytes until we've got valid UTF-8 again
                        needed = max(msglen - len(rec), 1)
                    if needed == 0:
                        return rec
                    try:
                        data = self.sock.recv(needed)
                    except socket.error:
                        vim.command("let s:swank_result='Socket error when receiving from SWANK server.\n'")
                        self.disconnect()
                        return rec
                    if len(data) == 0:
                        vim.command("let s:swank_result='Socket error when receiving from SWANK server.\n'")
                        self.disconnect()
                        return rec
                    rec = rec + data
        rec = ''

    def rex(self, action, cmd, package, thread, data=''):
        """
        Send an :emacs-rex command to SWANK
        """
        self.id = self.id + 1
        key = str(self.id)
        self.actions[key] = SwankAction(key, action, data)
        form = '(:emacs-rex ' + cmd + ' ' + package + ' ' + thread + ' ' + str(self.id) + ')\n'
        self.send(form)

    def listen(self):
        retval = ''
        msgcount = 0
        #logtime(self.logfile,'[- Listen--]')
        timeout = self.recv_timeout
        while msgcount < self.maxmessages:
            rec = self.recv_len(timeout)
            if rec == '':
                break
            timeout = 0.0
            msgcount = msgcount + 1
            if self.debug:
                print 'swank_recv_len received', rec
            msglen = int(rec, 16)
            if self.debug:
                print 'Received length:', msglen
            if msglen > 0:
                # length already received so it must be followed by data
                # use a higher timeout
                rec = self.recv(msglen, 1.0)
                logtime(self.logfile,'[-Received-]')
                logprint(self.logfile,rec)
                [s, r] = parse_sexpr( rec )
                if self.debug:
                    print 'Parsed:', r
                if len(r) > 0:
                    r_id = r[-1]
                    message = r[0].lower()
                    if self.debug:
                        print 'Message:', message
                retval = self.handle_return_message(retval, message, r, r_id)
        if retval != '':
            self.empty_last_line = (retval[-1] == '\n')
        return retval

    def new_line(self, new_text):
        if new_text != '':
            if new_text[-1] != '\n':
                return '\n'
        elif not self.empty_last_line:
            return '\n'
        return ''

    def get_prompt(self):
        if self.prompt.rstrip()[-1] == '>':
            return self.prompt + ' '
        else:
            return self.prompt + '> '

    def handle_return_message(self, retval, message, r, r_id):
        if message == ':open-dedicated-output-stream':
            self.output_port = int( r[1].lower(), 10 )
            if self.debug:
                print ':open-dedicated-output-stream result:', output_port
            return
            # break

        elif message == ':presentation-start':
            retval = retval + self.new_line(retval)

        elif message == ':write-string':
            logprint(self.logfile, "\t:write-string")
            # REPL has new output to display
            retval = retval + unquote(r[1])
            add_prompt = True
            for k,a in self.actions.items():
                if a.pending and a.name.find('eval'):
                    add_prompt = False
                    break
            if add_prompt:
                retval = retval + self.new_line(retval) + self.get_prompt()
            logprint(self.logfile, "\t:write-string %s" % retval)

        elif message == ':read-string':
            # REPL requests entering a string
            self.read_string = r[1:3]

        elif message == ':read-from-minibuffer':
            # REPL requests entering a string in the command line
            self.read_string = r[1:3]
            vim.command("let s:input_prompt='%s'" % unquote(r[3]).replace("'", "''"))

        elif message == ':indentation-update':
            for el in r[1]:
                self.indent_info[ unquote(el[0]) ] = el[1]

        elif message == ':new-package':
            self.package = unquote( r[1] )
            self.prompt  = unquote( r[2] )

        elif message == ':return':
            self.read_string = None
            if len(r) > 1:
                result = r[1][0].lower()
            else:
                result = ""
            if type(r_id) == str and r_id in self.actions:
                action = self.actions[r_id]
                action.pending = False
            else:
                action = None
            if self.log:
                logtime(self.logfile,'[Actionlist]')
                for k,a in sorted(actions.items()):
                    if a.pending:
                        pending = 'pending '
                    else:
                        pending = 'finished'
                    logprint(self.logfile,"%s: %s %s %s" % (k, str(pending), a.name, a.result))

            if result == ':ok':
                params = r[1][1]
                logprint(self.logfile,'params: ' + str(params))
                if params == []:
                    params = 'nil'
                if type(params) == str:
                    element = params.lower()
                    to_ignore = [':frame-call', ':quit-inspector', ':kill-thread', ':debug-thread']
                    to_nodisp = [':describe-symbol']
                    to_prompt = [':undefine-function', ':swank-macroexpand-1', ':swank-macroexpand-all', ':disassemble-form', \
                                 ':load-file', ':toggle-profile-fdefinition', ':profile-by-substring', ':swank-toggle-trace', 'sldb-break']
                    if action and action.name in to_ignore:
                        # Just ignore the output for this message
                        pass
                    elif element == 'nil' and action and action.name == ':inspector-pop':
                        # Quit inspector
                        vim.command('call SlimvQuitInspect(0)')
                    elif element != 'nil' and action and action.name in to_nodisp:
                        # Do not display output, just store it in actions
                        action.result = unquote(params)
                    else:
                        retval = retval + self.new_line(retval)
                        if element != 'nil':
                            retval = retval + unquote(params)
                            if action:
                                action.result = retval
                        if element == 'nil' or (action and action.name in to_prompt):
                            # No more output from REPL, write new prompt
                            retval = retval + self.new_line(retval) + self.get_prompt()

                elif type(params) == list and params:
                    element = ''
                    if type(params[0]) == str: 
                        element = params[0].lower()
                    if element == ':present':
                        # No more output from REPL, write new prompt
                        retval = retval + self.new_line(retval) + unquote(params[1][0][0]) + '\n' + self.get_prompt()
                    elif element == ':values':
                        retval = retval + self.new_line(retval)
                        if type(params[1]) == list: 
                            retval = retval + unquote(params[1][0]) + '\n'
                        else:
                            retval = retval + unquote(params[1]) + '\n' + self.get_prompt()
                    elif element == ':suppress-output':
                        pass
                    elif element == ':pid':
                        conn_info = make_keys(params)
                        pid = conn_info[':pid']
                        ver = conn_info.get(':version', 'nil')
                        if len(ver) == 8:
                            # Convert version to YYYY-MM-DD format
                            ver = ver[0:4] + '-' + ver[4:6] + '-' + ver[6:8]
                        imp = make_keys( conn_info[':lisp-implementation'] )
                        pkg = make_keys( conn_info[':package'] )
                        self.package = pkg[':name']
                        self.prompt = pkg[':prompt']
                        vim.command('let s:swank_version="' + ver + '"')
                        if ver >= '2011-11-08':
                            # Recent swank servers count bytes instead of unicode characters
                            self.use_unicode = False
                        vim.command('let s:lisp_version="' + imp[':version'] + '"')
                        retval = retval + self.new_line(retval)
                        retval = retval + imp[':type'] + ' ' + imp[':version'] + '  Port: ' + str(self.input_port) + '  Pid: ' + pid + '\n; SWANK ' + ver
                        retval = retval + '\n' + self.get_prompt()
                        logprint(self.logfile,' Package:' + self.package + ' Prompt:' + self.prompt)
                    elif element == ':name':
                        keys = make_keys(params)
                        retval = retval + self.new_line(retval)
                        retval = retval + '  ' + keys[':name'] + ' = ' + keys[':value'] + '\n'
                    elif element == ':title':
                        swank_parse_inspect(params)
                    elif element == ':compilation-result':
                        retval = retval + self.new_line(retval) + swank_parse_compile(params) + self.get_prompt()
                    else:
                        if action.name == ':simple-completions':
                            if type(params[0]) == list and type(params[0][0]) == str and params[0][0] != 'nil':
                                compl = "\n".join(params[0])
                                retval = retval + compl.replace('"', '')
                        elif action.name == ':fuzzy-completions':
                            if type(params[0]) == list and type(params[0][0]) == list:
                                compl = "\n".join(map(lambda x: x[0], params[0]))
                                retval = retval + compl.replace('"', '')
                        elif action.name == ':list-threads':
                            swank_parse_list_threads(r[1])
                        elif action.name == ':list-breakpoints':
                            swank_parse_list_breakpoints(r[1])
                        elif action.name == ':xref':
                            retval = retval + '\n' + swank_parse_xref(r[1][1])
                            retval = retval + self.new_line(retval) + self.get_prompt()
                        elif action.name == ':set-package':
                            self.package = unquote(params[0])
                            self.prompt = unquote(params[1])
                            retval = retval + '\n' + self.get_prompt()
                        elif action.name == ':untrace-all':
                            retval = retval + '\nUntracing:'
                            for f in params:
                                retval = retval + '\n' + '  ' + f
                            retval = retval + '\n' + self.get_prompt()
                        elif action.name == ':frame-call':
                            swank_parse_frame_call(params, action)
                        elif action.name == ':frame-source-location':
                            swank_parse_frame_source(params, action)
                        elif action.name == ':frame-locals-and-catch-tags':
                            swank_parse_locals(params[0], action)
                        elif action.name == ':profiled-functions':
                            retval = retval + '\n' + 'Profiled functions:\n'
                            for f in params:
                                retval = retval + '  ' + f + '\n'
                            retval = retval + self.get_prompt()
                        elif action.name == ':inspector-range':
                            swank_parse_inspect_content(params)
                        if action:
                            action.result = retval

            elif result == ':abort':
                self.debug_active = False
                vim.command('let s:sldb_level=-1')
                if len(r[1]) > 1:
                    retval = retval + '; Evaluation aborted on ' + unquote(r[1][1]).replace('\n', '\n;') + '\n' + self.get_prompt()
                else:
                    retval = retval + '; Evaluation aborted\n' + self.get_prompt()

        elif message == ':inspect':
            swank_parse_inspect(r[1])

        elif message == ':debug':
            retval = retval + swank_parse_debug(r)

        elif message == ':debug-activate':
            self.debug_active = True
            self.debug_activated = True
            self.current_thread = r[1]
            sldb_level = r[2]
            vim.command('let s:sldb_level=' + sldb_level)
            self.frame_locals.clear()

        elif message == ':debug-return':
            self.debug_active = False
            vim.command('let s:sldb_level=-1')
            retval = retval + '; Quit to level ' + r[2] + '\n' + self.get_prompt()

        elif message == ':ping':
            [thread, tag] = r[1:3]
            self.send('(:emacs-pong ' + thread + ' ' + tag + ')')
        return retval

    def output(self, echo):
        # global debug_active
        # global debug_activated

        if not self.sock:
            return "SWANK server is not connected."
        count = 0
        #logtime(self.logfile,'[- Output--]')
        self.debug_activated = False
        result = self.listen()
        pending = self.actions_pending()
        while self.sock and result == '' and pending > 0 and count < self.listen_retries:
            result = self.listen()
            pending = self.actions_pending()
            count = count + 1
        if echo and result != '':
            # Append SWANK output to REPL buffer
            vim.command('call SlimvOpenReplBuffer()')
            buf = vim.current.buffer
            lines = result.split("\n")
            if lines[0] != '':
                # Concatenate first line to the last line of the buffer
                nlines = len(buf)
                buf[nlines-1] = buf[nlines-1] + lines[0]
            if len(lines) > 1:
                # Append all subsequent lines
                buf.append(lines[1:])
            vim.command('call SlimvEndUpdateRepl()')
        if self.debug_activated and self.debug_active:
            # Debugger was activated in this run
            vim.command('call SlimvOpenSldbBuffer()')
            vim.command('call SlimvEndUpdate()')
            vim.command("call search('^Restarts:', 'w')")

    def actions_pending(self):
        count = 0
        for k,a in sorted(self.actions.items()):
            if a.pending:
                count = count + 1
        vc = ":let s:swank_actions_pending=" + str(count)
        vim.command(vc)
        return count

    def connection_info(self):
        self.actions.clear()
        self.indent_info.clear()
        self.frame_locals.clear()
        self.debug_activated = False
        if vim.eval('exists("g:swank_log") && g:swank_log') != '0':
            self.log = True
        self.rex(':connection-info', '(swank:connection-info)', 'nil', 't')

    def response(self,name):
        #logtime(self.logfile,'[-Response-]')
        for k,a in sorted(self.actions.items()):
            if not a.pending and (name == '' or name == a.name):
                vc = ":let s:swank_action='" + a.name + "'"
                vim.command(vc)
                vim.command("let s:swank_result='%s'" % a.result.replace("'", "''"))
                self.actions.pop(a.id)
                self.actions_pending()
                return
        vc = ":let s:swank_action=''"
        vc = ":let s:swank_result=''"
        vim.command(vc)
        self.actions_pending()
