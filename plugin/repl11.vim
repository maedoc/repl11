
" TODO need to send current buffer name/file so that quickfixing
" errors can take advantage
function! R11Send(target, message)
python<<EOF
import vim, json, urllib
port = vim.vars['r11port'] if 'r11port' in vim.vars else '8080'
target  = vim.eval('a:target')
message = vim.eval('a:message')
row, col = vim.current.window.cursor
pars = {'message': message
       ,'filename': vim.eval("expand('%:p')")
       ,'lineno': row
       }
message = urllib.urlencode(pars)
print 'waiting...'
req = urllib.urlopen('http://127.0.0.1:{2}/{0}?{1}'.format(target, message, port))
try:
    txt = req.read()
    resp = json.loads(txt)
    if resp['status'] in ('ok', 'fail'):
        out = resp['out'].strip()
        res = resp['result']
        if res != 'None':
            if out:
                out += '\n'
            out += res
        if len(out) == 0:
            out = resp['status']
        vim.vars['r11out'] = out
        #vim.command('let g:r11out = %r' % (out,))
        if resp['status'] == 'fail':
            qfl = []
            for filename, lineno, context, text in resp['traceback']:
                if filename.endswith('repl11/code.py'):
                    continue
                    qfl.append({
                        'text'     : text or '',
                        'filename' : filename,
                        'lnum'     : lineno
                    })
            vim.vars['r11qfl'] = vim.List(qfl)
            vim.command('call setqflist(g:r11qfl)')
    else:
        print 'unknown response status', resp['status']
except Exception as exc:
    vim.vars['r11out'] = 'unknown response: %r' % (txt, )
EOF
endfunction

function! R11DescribeCword()
    call R11Send('describe', expand("<cword>"))
endfunction

function! R11Complete(findstart, base)
    if a:findstart
        " borrowed from ivanov/vim-ipython
        let line = getline('.')
        let start = col('.') - 1
        while start > 0 && line[start-1] =~ '\k\|\.' " keyword or dot
            let start -= 1
        endwhile
        return start
    else
python<<EOF
import vim
port = vim.vars['r11port'] if 'r11port' in vim.vars else '8080'
from urllib import urlopen, urlencode
message = urlencode(
    {'message': vim.eval('a:base')
    ,'filename': vim.eval("expand('%:p')") # to know which namespace
    })
req = urlopen('http://127.0.0.1:{1}/complete?{0}'.format(message, port))
vim.command('let b:hrepl_resp = %r' % (req.read().strip(), ))
EOF
return split(b:hrepl_resp, ',')
    endif
endfunction

set completefunc=R11Complete

function! R11CurrentObjectName()
    " borrowed from ivanov/vim-ipython
    let line = getline('.')
    let start = col('.') - 1
    let endl = col('.')
    while start > 0 && line[start-1] =~ '\k\|\.' " keyword or dot
        let start -= 1
    endwhile
    while endl < strlen(line) && line[endl] =~ '\k\|\.'
        let endl += 1
    endwhile
    return strpart(line, start, endl)
endfunction

function!R11Help()
    let obj = R11CurrentObjectName()
    call R11Send('ex', 'help(' . obj . ')')
endfunction

function!R11Source()
    let obj = R11CurrentObjectName()
    call R11Send('ex', 'import inspect; print inspect.getsource(' . obj . ')')
endfunction

function!R11EditSource()
    let obj = R11CurrentObjectName()
    call R11Send('ex', 'import inspect; print "%s:%s" % (inspect.getsourcefile(' . obj . '), inspect.findsource(' . obj . ')[1]+1)')
    let parts = split(g:r11out, ':')
    exe 'e ' . parts[0]
    exe ':' . parts[1]
endfunction

function! R11Log()
python<<EOF
import vim, json, urllib
port = vim.vars['r11port'] if 'r11port' in vim.vars else '8080'
try:
    r11log_since
except:
    r11log_since = 0.0
message = urllib.urlencode({'since': r11log_since})
req = urllib.urlopen('http://127.0.0.1:{1}/log?{0}'.format(message, port))
records = json.loads(req.read())
r11log_since = float(records[-1][0])
for t, line in records:
    print line
EOF
endfunction

function! R11Begin(...)
python<<EOF
try:
    r11proc
except:
    import atexit
    r11proc = None
    @atexit.register
    def r11prockill():
        if r11proc is not None:
            r11proc.terminate()

if r11proc is None:
    import vim
    narg = int(vim.eval('a:0'))
    if narg > 0:
        port = vim.eval('a:1')
    else:
        port = '8080'
    vim.vars['r11port'] = port
    import subprocess
    cmd = ['python', '-m', 'repl11', '-v', '-s', '-p', port, '-l', 'pg']
    r11proc = subprocess.Popen(cmd, 
    	stdout=subprocess.PIPE, 
    	stderr=subprocess.PIPE)
    print ('started', ' '.join(cmd))
else:
    print ('r11proc already running, \\rr to restart')
EOF
endfunction

function! R11End()
python<<EOF
if r11proc is not None:
    try:
        r11proc.terminate()
        r11proc.wait()
    except Exception as exc:
        print ('failed to end r11proc: ', exc)
    finally:
        r11proc = None
	print ('r11proc killed!')
else:
    print ('no r11proc to end')
EOF
endfunction

function! R11Status()
python<<EOF
if r11proc.poll():
    print r11proc.stdout.read()
    print r11proc.stderr.read()
EOF
endfunction

" 0__o
map \r1o :echo g:r11out<CR>

vmap <c-s> "ry:call R11Send('ex', @r)<cr>
nmap <c-s> mtvip<c-s>`t\r1o
imap <c-s> <esc><c-s>

map K :call R11Help()<cr>\r1o
map <c-k> :call R11Source()<cr>\r1o
map \r1w :call R11Send('describe', 'whos')<cr>\r1o
map <c-j> :call R11DescribeCword()<cr>\r1o

map \rl :call R11Log()<cr>
map \rb :call R11Begin()<cr>
map \re :call R11End()<cr>
map \rs :call R11Status()<cr>
map \rr \re\rb

map \rd :call R11EditSource()<cr>

"map <F5> :w<CR>:call R11Send('ex', 'execfile("' . expand('%') . '", globals())')
