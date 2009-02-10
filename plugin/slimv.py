#!/usr/bin/env python

###############################################################################
#
# Client/Server code for Slimv
# slimv.py:     Client/Server code for slimv.vim plugin
# Version:      0.1.1
# Last Change:  04 Feb 2009
# Maintainer:   Tamas Kovacs <kovisoft at gmail dot com>
# License:      This file is placed in the public domain.
#               No warranty, express or implied.
#               *** ***   Use At-Your-Own-Risk!   *** ***
# 
###############################################################################

import os
import sys
import getopt
import time
import shlex
import socket
from subprocess import Popen, PIPE, STDOUT
from threading import Thread, BoundedSemaphore

autoconnect = 1             # Start and connect server automatically

HOST        = ''            # Symbolic name meaning the local host
PORT        = 5151          # Arbitrary non-privileged port

debug_level = 0             # Debug level for diagnostic messages
terminate   = 0             # Main program termination flag

python_path = 'python'      # Path of the Python interpreter (overridden via command line args)
lisp_path   = 'clisp.exe'   # Path of the Lisp interpreter (overridden via command line args)
slimv_path  = 'slimv.py'    # Path of this script (determined later)
run_cmd     = ''            # Complex server-run command (if given via command line args)

# Are we running on Windows (otherwise assume Linux, sorry for other OS-es)
mswindows = (sys.platform == 'win32')


def log( s, level ):
    """Print diagnostic messages according to the actual debug level.
    """
    if debug_level >= level:
        print s


###############################################################################
#
# Client part
#
###############################################################################

def start_server( filename ):
    """Spawn server.
    """
    global python_path
    global run_cmd

    if run_cmd == '':
        # Complex run command not given, build it from the information available
        if mswindows:
            cmd = [python_path, slimv_path, '-p', str(PORT), '-l', lisp_path, '-s', filename]
        else:
            cmd = ['xterm', '-T', 'Slimv', '-e', python_path, slimv_path, '-p', str(PORT), '-l', lisp_path, '-s', filename]
    else:
        cmd = shlex.split(run_cmd)

    # Start server
    #TODO: put in try-block
    if mswindows:
        #from win32process import CREATE_NEW_CONSOLE
        CREATE_NEW_CONSOLE = 16
        server = Popen( cmd, creationflags=CREATE_NEW_CONSOLE )
    else:
        server = Popen( cmd )

    # Allow subprocess (server) to start
    time.sleep( 2.0 )


def connect_server( output_filename ):
    """Try to connect server, if server not found then spawn it.
       Return socket object on success, None on failure.
    """
    global autoconnect

    s = socket.socket( socket.AF_INET, socket.SOCK_STREAM )
    try:
        s.connect( ( 'localhost', PORT ) )
    except socket.error, msg:
        if autoconnect:
            # We need to try to start the server automatically
            s.close()
            start_server( output_filename )

            # Open socket to the server
            s = socket.socket( socket.AF_INET, socket.SOCK_STREAM )
            try:
                s.connect( ( 'localhost', PORT ) )
            except socket.error, msg:
                s.close()
                s =  None
        else:   # not autoconnect
            print "Server not found"
            s = None
    return s


def send_line( server, line ):
    """Send a line to the server:
       first send line length in 4 bytes, then send the line itself.
    """
    l = len(line)
    lstr = chr(l&255) + chr((l>>8)&255) + chr((l>>16)&255) + chr((l>>24)&255)
    server.send( lstr )     # send message length first
    server.send( line )     # then the message itself

#    print "send line"
#
    time.sleep(0.01)        # give a little chance to receive some output from the REPL before the next query
                            #TODO: synchronize it correctly
#
#    try:
#        print "receive length"
#        lstr = server.recv(4)
#        if len( lstr ) <= 0:
#            return
#    except:
#        return
#    l = ord(lstr[0]) + (ord(lstr[1])<<8) + (ord(lstr[2])<<16) + (ord(lstr[3])<<24)
#    if l > 0:
#        # Valid length received, now wait for the message
#        try:
#            # Read the message itself
#            print "receive message"
#            received = server.recv(l)
#            if len( received ) < l:
#                return
#        except:
#            return
#        print received


def client_file( input_filename, output_filename ):
    """Main client routine - input file version:
       starts server if needed then send text to server.
       Input is read from input file.
    """
    s = connect_server( output_filename )
    if s is None:
        return

    try:
        file = open( input_filename, 'rt' )
        try:
            # Send contents of the file to the server
            for line in file:
                send_line( s, line.rstrip( '\n' ) )
        finally:
            file.close()

        if ( output_filename != ''):
            time.sleep(0.02)
            send_line( s, 'SLIMV_READOUT::' + output_filename )
    except:
        return

    s.close()


#def readout( filename ):
#    """Client readout mode:
#       requests global display buffer contents from server.
#       Output file name is passed to the server, which writes the buffer into the file.
#    """
#    s = connect_server()
#    if s is None:
#        return
#
#    try:
#        # Send readout command to the server
#        send_line( s, 'SLIMV_READOUT::' + filename )
#    finally:
#        s.close()


###############################################################################
#
# Server part
#
###############################################################################

class repl_buffer:
    def __init__ ( self ):

        self.buffer = ''    # Text buffer (display queue) to collect socket input and REPL output
        self.buflen = 0     # Amount of text currently in the buffer
        self.sema   = BoundedSemaphore()
                            # Semaphore to synchronize access to the global display queue

    def read_and_display( self, output ):
        """Read and display lines received in global display queue buffer.
        """
        self.sema.acquire()
        l = len( self.buffer )
        while self.buflen < l:
            try:
                # Write all lines in the buffer to the display
                output.write( self.buffer[self.buflen] )
                self.buflen = self.buflen + 1
            except:
                break
        self.buffer = ''
        self.buflen = 0
        self.sema.release()


    def write( self, text ):
        """Write text into the global display queue buffer.
        """
        self.sema.acquire()
        self.buffer = self.buffer + text
        self.sema.release()


class input_listener( Thread ):
    """Server thread to receive input from console.
    """

    def __init__ ( self, inp, buffer ):
        Thread.__init__( self )
        self.inp = inp
        self.buffer = buffer

    def run( self ):
        global terminate

        log( "il.start", 1 )
        while not terminate:
            try:
                # Read input from the console and write it
                # to the stdin of REPL
                log( "il.raw_input", 1 )
                received = raw_input()
                self.inp.write( received + '\n' )
                self.buffer.write( received + '\n' )
            except EOFError:
                # EOF (Ctrl+Z on Windows, Ctrl+D on Linux) pressed?
                log( "il.EOFError", 1 )
                terminate = 1
            except KeyboardInterrupt:
                # Interrupted from keyboard (Ctrl+Break, Ctrl+C)?
                log( "il.KeyboardInterrupt", 1 )
                terminate = 1

            if terminate:
                # The socket is opened here only for waking up the server thread
                # in order to recognize the termination message
                #TODO: exit REPL if this script is about to exit
                cs = socket.socket( socket.AF_INET, socket.SOCK_STREAM )
                try:
                    cs.connect( ( 'localhost', PORT ) )
                    cs.send( " " )
                finally:
                    # We don't care if this above fails, we'll exit anyway
                    cs.close()


class output_listener( Thread ):
    """Server thread to receive REPL output.
    """

    def __init__ ( self, out, buffer ):
        Thread.__init__( self )
        self.out = out
        self.buffer = buffer

    def run( self ):
        global terminate

        log( "ol.start", 1 )
        while not terminate:
            log( "ol.read", 1 )
            try:
                # Read input from the stdout of REPL
                # and write it to the display (display queue buffer)
                c = self.out.read(1)
                self.buffer.write( c )
            except:
                #TODO: should we set terminate=1 here as well?
                break


def server( output_filename ):
    """Main server routine: starts REPL and helper threads for
       sending and receiving data to/from REPL.
    """
    global lisp_path
    global terminate

    # First check if server already runs
    s = socket.socket( socket.AF_INET, socket.SOCK_STREAM )
    try:
        s.connect( ( 'localhost', PORT ) )
    except socket.error, msg:
        # Server not found, our time has come, we'll start a new server in a moment
        pass
    else:
        # Server found, nothing to do here
        s.close()
        print "Server is already running"
        return

    # Build Lisp-starter command
    cmd = shlex.split( lisp_path.replace( '\\', '\\\\' ) )

    # Start Lisp
    if mswindows:
        #from win32con import CREATE_NO_WINDOW
        CREATE_NO_WINDOW = 134217728
        repl = Popen( cmd, stdin=PIPE, stdout=PIPE, stderr=STDOUT, creationflags=CREATE_NO_WINDOW )
    else:
        repl = Popen( cmd, stdin=PIPE, stdout=PIPE, stderr=STDOUT )

    buffer = repl_buffer()

    # Create and start helper threads
    ol = output_listener( repl.stdout, buffer )
    ol.start()
    il = input_listener( repl.stdin, buffer )
    il.start()

    # Allow Lisp to start, confuse it with some fancy Slimv messages
    log( "in.start", 1 )
    sys.stdout.write( ";;; Slimv server is started on port " + str(PORT) + "\n" )
    sys.stdout.write( ";;; Slimv is spawning REPL...\n" )
    time.sleep(0.5)                         # wait for Lisp to start
    sys.stdout.write( ";;; Slimv connection established\n" )
    if mswindows:
        sys.stdout.write( ";;; Type Ctrl-Z then Return to exit server\n" )
    else:
        sys.stdout.write( ";;; Type Ctrl-D then Return to exit server\n" )

    # Open server socket
    s = socket.socket( socket.AF_INET, socket.SOCK_STREAM )
    log( "sl.bind " + str(PORT), 1 )
    s.bind( (HOST, PORT) )

    while not terminate:
        # Listen server socket
        log( "sl.listen", 1 )
        try:
            s.listen( 1 )
            conn, addr = s.accept()
        except KeyboardInterrupt:
            # Interrupted from keyboard (Ctrl+Break, Ctrl+C)?
            log( "in.KeyboardInterrupt", 1 )
            terminate = 1

        while not terminate:
            l = 0
            lstr = ''
            # Read length first, it comes in 4 bytes
            log( "sl.recv len", 1 )
            try:
                lstr = conn.recv(4)
                if len( lstr ) <= 0:
                    break
            except:
                break
            if terminate:
                break
            l = ord(lstr[0]) + (ord(lstr[1])<<8) + (ord(lstr[2])<<16) + (ord(lstr[3])<<24)
            if l > 0:
                # Valid length received, now wait for the message
                log( "sl.recv data", 1 )
                try:
                    # Read the message itself
                    received = conn.recv(l)
                    if len( received ) < l:
                        break
                except:
                    break

                if received[0:15] == 'SLIMV_READOUT::':
                    filename = received[15:]
                    try:
                        #file = open( filename, 'wt' )
                        file = open( filename, 'at' )
                        try:
                            buffer.read_and_display( file )
                        finally:
                            file.close()
                    except:
                        break
                else:
                    # Fork here: write message to the stdin of REPL
                    # and also write it to the display (display queue buffer)
                    repl.stdin.write( received + '\n' )
                    buffer.write( received + '\n' )

        log( "sl.close", 1 )
        conn.close()

    # Send exit command to child process and
    # wake output listener up at the same time
    try:
        repl.stdin.close()
    except:
        # We don't care if this above fails, we'll exit anyway
        pass

    # Be nice
    print 'Thank you for using Slimv.'

    # Wait for the child process to exit
    time.sleep(1)


def escape_path( path ):
    """Surround path containing spaces with backslash + double quote,
       so that it can be passed as a command line argument.
    """
    if path.find( ' ' ) < 0:
        return path
    if path[0:2] == '\\\"':
        return path
    elif path[0] == '\"':
        return '\\' + path + '\\'
    else:
        return '\\\"' + path + '\\\"'


def usage():
    """Displays program usage information.
    """
    progname = os.path.basename( sys.argv[0] )
    print 'Usage: ', progname + ' [-d LEVEL] [-s] [-c ARGS]'
    print
    print 'Options:'
    print '  -?, -h, --help                show this help message and exit'
    print '  -l PATH, --lisp=PATH          path of Lisp interpreter'
    print '  -r PATH, --run=PATH           full command to run the server'
    print '  -p PORT, --port=PORT          port number to use by the server/client'
    print '  -d LEVEL, --debug=LEVEL       set debug LEVEL (0..3)'
    print '  -s FILENAME                   start server using FILENAME as the REPL output'
    print '  -f FILENAME, --file=FILENAME  start client and send contents of file'
    print '                                named FILENAME to server'
    print '  -c LINE1 LINE2 ... LINEn      start client and send LINE1...LINEn to server'
    print '                                (if present, this option must be the last one,'
    print '                                mutually exclusive with the -f option)'
    print '  -o FILENAME, --readout=FNAME  read out the latest contents of the REPL buffer'
    print '                                and put it in the given file'


###############################################################################
#
# Main program
#
###############################################################################

if __name__ == '__main__':

    #EXIT, SERVER, CLIENT, READOUT = range( 4 )
    EXIT, SERVER, CLIENT = range( 3 )
    mode = EXIT
    slimv_path = sys.argv[0]
    python_path = sys.executable
    input_filename = ''
    output_filename = ''

    # Always this trouble with the path/filenames containing spaces:
    # enclose them in double quotes
    if python_path.find( ' ' ) >= 0:
        python_path = '"' + python_path + '"'

    # Get command line options
    try:
        opts, args = getopt.getopt( sys.argv[1:], '?hcs:f:p:l:r:d:o:', \
                                    ['help', 'client', 'server=', 'file=', 'port=', 'lisp=', 'run=', 'debug=', 'readout='] )

        # Process options
        for o, a in opts:
            if o in ('-?', '-h', '--help'):
                usage()
                break
            if o in ('-p', '--port'):
                try:
                    PORT = int(a)
                except:
                    # If given port number is malformed, then keep default value
                    pass
            if o in ('-l', '--lisp'):
                lisp_path = a
            if o in ('-r', '--run'):
                run_cmd = a
            if o in ('-d', '--debug'):
                try:
                    debug_level = int(a)
                except:
                    # If given level is malformed, then keep default value
                    pass
            if o in ('-s', '--server'):
                mode = SERVER
                output_filename = a
            if o in ('-c', '--client'):
                mode = CLIENT
                input_filename = ''
            if o in ('-f', '--file'):
                mode = CLIENT
                input_filename = a
            if o in ('-o', '--readout'):
                #mode = READOUT
                output_filename = a

    except getopt.GetoptError:
        # print help information and exit:
        usage()

    if mode == SERVER:
        # We are started in server mode
        server( output_filename )

    if mode == CLIENT:
        # We are started in client mode
        if run_cmd != '':
            # It is possible to pass special argument placeholders to run_cmd
            run_cmd = run_cmd.replace( '@p', escape_path( python_path ) )
            run_cmd = run_cmd.replace( '@s', escape_path( slimv_path ) )
            run_cmd = run_cmd.replace( '@l', escape_path( lisp_path ) )
            run_cmd = run_cmd.replace( '@@', '@' )
            log( run_cmd, 1 )
        if input_filename != '':
            client_file( input_filename, output_filename )
        else:
            start_server( output_filename )

#    if mode == READOUT:
#        # We are started in readout mode
#        readout( output_filename )

# --- END OF FILE ---
