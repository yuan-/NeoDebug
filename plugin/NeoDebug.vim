"""""""""""""""""""""""""""""""""""""""""""""""""""""""
" NeoDebug - Vim plugin for interface to gdb from Vim 
" Maintainer: scott (cpiger@qq.com)
" Version: 0.1 2018-05-03  ready to use.
"""""""""""""""""""""""""""""""""""""""""""""""""""""""
" In case this gets loaded twice.
if exists(':NeoDebug')
    finish
endif
" Name of the NeoDebug command, defaults to "gdb".
if !exists('g:neodbg_debugger')
    let g:neodbg_debugger = 'gdb'
endif

if !exists('g:neodbg_ballonshow_with_print')
    let g:neodbg_ballonshow_with_print = 0
endif

if !exists('g:neodbg_debuginfo')
    let g:neodbg_debuginfo = 0
endif

if !exists('g:neodbg_enable_help')
    let g:neodbg_enable_help = 1
endif

if !exists('g:neodbg_openbreaks_default')
    let g:neodbg_openbreaks_default    = 0
endif
if !exists('g:neodbg_openstacks_default')
    let g:neodbg_openstacks_default    = 0
endif
if !exists('g:neodbg_openthreads_default')
    let g:neodbg_openthreads_default   = 0
endif
if !exists('g:neodbg_openlocals_default')
    let g:neodbg_openlocals_default    = 1
endif
if !exists('g:neodbg_openregisters_default')
    let g:neodbg_openregisters_default = 0
endif

let g:neodbg_console_name = "__DebugConsole__"
let g:neodbg_console_height = 15
let g:neodbg_prompt = '(gdb) '

let g:neodbg_breakpoints_name = "__Breakpoints__"
let g:neodbg_breakpoints_width = 50
let g:neodbg_breakpoints_height = 25

let g:neodbg_locals_name = "__Locals__"
let g:neodbg_locals_width = 50
let g:neodbg_locals_height = 25

let g:neodbg_registers_name = "__Registers__"
let g:neodbg_registers_width = 50
let g:neodbg_registers_height = 25

let g:neodbg_stackframes_name = "__Stack Frames__"
let g:neodbg_stackframes_width = 50
let g:neodbg_stackframes_height = 25

let g:neodbg_threads_name = "__Threads__"
let g:neodbg_threads_width = 50
let g:neodbg_threads_height = 25

let g:neodbg_locals_win = 0
let g:neodbg_registers_win = 0
let g:neodbg_stackframes_win = 0
let g:neodbg_threads_win = 0
let g:neodbg_breakpoints_win = 0


let s:neodbg_chan = 0

let s:neodbg_is_debugging = 0
let s:neodbg_running = 0
let s:neodbg_exrc_dir = $HOME.'/.neodebug'
let s:neodbg_exrc = s:neodbg_exrc_dir . '/neodbg_exrc'
let s:neodbg_port = 30777 

let s:ismswin = has('win32')
let s:isunix = has('unix')

let s:completers = []
let s:neodbg_cmd_historys = [" "]

let s:pc_id = 12
let s:break_id = 13
let s:stopped = 1
let s:breakpoints = {}

let s:cur_wid = 0
let s:cur_winnr = 0

" mode: i|n|c|<empty>
" i - input command in console window and press enter
" n - press enter (or double click) in console window
" c - run debugger command
function! NeoDebug(cmd, ...)  " [mode]
    let usercmd = a:cmd
    let mode = a:0>0 ? a:1 : ''

    if s:neodbg_running == 0
        let s:neodbg_port= 30000 + reltime()[1] % 10000

        call neodebug#OpenLocals()
        let g:neodbg_locals_win = win_getid(winnr())

        call neodebug#OpenRegisters()
        let g:neodbg_registers_win = win_getid(winnr())

        call neodebug#OpenStackFrames()
        let g:neodbg_stackframes_win = win_getid(winnr())

        call neodebug#OpenThreads()
        let g:neodbg_threads_win = win_getid(winnr())

        call neodebug#OpenBreakpoints()
        let g:neodbg_breakpoints_win = win_getid(winnr())


        call neodebug#CloseBreakpointsWindow()
        call neodebug#CloseThreadsWindow()
        call neodebug#CloseStackFramesWindow()
        call neodebug#CloseRegistersWindow()
        call neodebug#CloseLocalsWindow()
        call s:NeoDebugStart(usercmd)

        " save current setting and restore when neodebug quits via 'so .exrc'
        if finddir(s:neodbg_exrc_dir) == ''
            call mkdir(s:neodbg_exrc_dir, "p")
        endif
        exec 'mk! ' . s:neodbg_exrc . s:neodbg_port
        let sed_cmd = 'sed -i "/^set /d" ' . s:neodbg_exrc . s:neodbg_port

        if has('nvim')
            call jobstart(sed_cmd)
        else
            call job_start(sed_cmd)
        endif

        set nocursorline
        set nocursorcolumn

        call neodebug#OpenConsole()
        let s:neodbg_console_win = win_getid(winnr())
        "fix minibufexpl plugin conflict
        " call neodebug#CloseConsoleWindow()
        " call neodebug#OpenConsoleWindow()

        let s:neodbg_quitted = 0
        let s:neodbg_running = 1

        return
    endif

    if s:neodbg_running == 0
        echomsg "NeoDebug is not running"
        return
    endif

    " if -1 == bufwinnr(g:neodbg_console_name)
        " call neodebug#ToggleConsoleWindow()
        " return
    " endif

    " echomsg "usercmd[".usercmd."]"
    if g:neodbg_debugger == 'gdb' && usercmd =~ '^\s*(gdb)' 
        let usercmd = substitute(usercmd, '^\s*(gdb)\s*', '', '')
    elseif g:neodbg_debugger == 'gdb' && usercmd =~ '^\s*>\s*' 
        let usercmd = substitute(usercmd, '^\s*>\s*', '', '')
        " echomsg "usercmd2[".usercmd."]"
    endif

    " goto frame
    " #0  factor (n=1, r=0x22fe48) at factor/factor.c:4
    " #1  0x00000000004015e2 in main (argc=1, argv=0x5b3480) at sample.c:12
    if s:MyMatch(usercmd, '\v^#(\d+)')  && s:neodbg_is_debugging
        let usercmd = "frame " . s:match[1]
        call NeoDebugSendCommand(usercmd)
        return
    endif

    " goto thread and show frames
    " Id   Target Id         Frame 
    " 2    Thread 83608.0x14dd0 0x00000000773c22da in ntdll!RtlInitString () from C:\\windows\\SYSTEM32\tdll.dll
    " 1    Thread 83608.0x1535c factor (n=1, r=0x22fe48) at factor/factor.c:5
    if s:MyMatch(usercmd, '\v^\s+(\d+)\s+Thread ') && s:neodbg_is_debugging
        let usercmd = "-thread-select " . s:match[1]
        call NeoDebugSendCommand(usercmd)
        call NeoDebugSendCommand("bt")
        return
    endif

    " Num     Type           Disp Enb Address            What
    " 1       breakpoint     keep y   0x00000000004015c4 in main at sample.c:8
    " 2       breakpoint     keep y   0x00000000004015d4 in main at sample.c:12
    " 3       breakpoint     keep y   0x00000000004015e2 in main at sample.c:13
    if s:MyMatch(usercmd, '\v<at %(0x\S+ )?(..[^:]*):(\d+)') || s:MyMatch(usercmd, '\vfile ([^,]+), line (\d+)') || s:MyMatch(usercmd, '\v\((..[^:]*):(\d+)\)')
        call s:NeoDebugGotoFile(s:match[1], s:match[2])
        return
    endif

    if mode == 'n'  " mode n: jump to source or current callstack, dont exec other gdb commands
        call NeoDebugExpandPointerExpr()
        return
    endif

    if usercmd == 'c'
        let usercmd = s:neodbg_is_debugging ? 'continue' : 'run'
    endif

    let s:cur_wid = win_getid(winnr())
    let s:cur_winnr = bufwinnr("%")
    call NeoDebugSendCommand(usercmd, mode)
endf

function! s:DeleteSedTempfile()
    let sed_tmp = fnamemodify(s:neodbg_exrc . s:neodbg_port, ":p:h")
    if s:ismswin
        silent exec '!start /b del /f '. sed_tmp . '/sed*'   
    endif
endfunction

function! NeoDebugStop(cmd)
	if !s:neodbg_running
		return
	endif
    if has('nvim')
        call jobstop(s:nvim_commjob)
    else
        call job_stop(s:commjob)
    endif
endfunction

let s:neodbg_init_flag = 0
func s:NeoDebugStart(cmd)
    let s:startwin = win_getid(winnr())
    let s:startsigncolumn = &signcolumn

    let s:save_columns = 0
    if exists('g:neodbg_wide')
        if &columns < g:neodbg_wide
            let s:save_columns = &columns
            let &columns = g:neodbg_wide
        endif
        let vertical = 1
    else
        let vertical = 0
    endif

    let cmd = [g:neodbg_debugger, '-quiet','-q', '-f', '--interpreter=mi2', a:cmd]
    " Create a hidden terminal window to communicate with gdb
    if has('nvim')
        let opts = {
                    \ 'on_stdout': function('s:NvimHandleOutput'),
                    \ 'on_exit': function('s:NvimNeoDebugEnd'),
                    \ }

        let s:nvim_commjob = jobstart(cmd, opts)

    else
        let s:commjob = job_start(cmd, {
                    \ 'out_cb' : function('s:HandleOutput'),
                    \ 'exit_cb': function('s:NeoDebugEnd'),
                    \ })

        let s:neodbg_chan = job_getchannel(s:commjob)  
        let commpty = job_info((s:commjob))['tty_out']
    endif


    " Interpret commands while the target is running.  This should usualy only be
    " exec-interrupt, since many commands don't work properly while the target is
    " running.
    let s:neodbg_init_flag = 1
    call NeoDebugSendCommand('set mi-async on')
    if s:ismswin
        call NeoDebugSendCommand('set new-console on')
    elseif s:isunix
        call NeoDebugSendCommand('show inferior-tty')
    endif
    call NeoDebugSendCommand('set print pretty on')
    call NeoDebugSendCommand('set breakpoint pending on')
    call NeoDebugSendCommand('set pagination off')
    let s:neodbg_init_flag = 0

    " Install debugger commands in the text window.
    call win_gotoid(s:startwin)

    " Enable showing a balloon with eval info
    if has("balloon_eval") || has("balloon_eval_term")
        set bexpr=NeoDebugBalloonExpr()
        if has("balloon_eval")
            set ballooneval
            set balloondelay=500
        endif
        if has("balloon_eval_term")
            set balloonevalterm
        endif
    endif

    augroup NeoDebugAutoCMD
        au BufRead * call s:BufferRead()
        au BufUnload * call s:BufferUnload()
        au VimLeavePre * call delete(s:neodbg_exrc . s:neodbg_port)
    augroup END

endfunc

func s:NvimNeoDebugEnd(job_id, data, event_type) abort
    call s:NeoDebugEnd(a:job_id, a:event_type)
endfunction

func s:NeoDebugEnd(job, status)

	if !s:neodbg_running
		return
	endif

	let s:neodbg_running = 0
    sign unplace *

    " If neodebug console window is open then close it.
    call neodebug#GotoBreakpointsWindow()
    quit
    call neodebug#GotoRegistersWindow()
    quit
    call neodebug#GotoStackFramesWindow()
    quit
    call neodebug#GotoThreadsWindow()
    quit
    call neodebug#GotoLocalsWindow()
    quit
    call neodebug#GotoConsoleWindow()
    quit

    exe 'bwipe! ' . bufnr(g:neodbg_locals_name)
    exe 'bwipe! ' . bufnr(g:neodbg_registers_name)
    exe 'bwipe! ' . bufnr(g:neodbg_stackframes_name)
    exe 'bwipe! ' . bufnr(g:neodbg_threads_name)
    exe 'bwipe! ' . bufnr(g:neodbg_breakpoints_name)
    exe 'bwipe! ' . bufnr(g:neodbg_console_name)

    let curwinid = win_getid(winnr())

    call win_gotoid(s:startwin)
    let &signcolumn = s:startsigncolumn
    call NeoDebugDeleteCommandsHotkeys()

    call win_gotoid(curwinid)
    if s:save_columns > 0
        let &columns = s:save_columns
    endif

    if has("balloon_eval") || has("balloon_eval_term")
        set bexpr=
        if has("balloon_eval")
            set noballooneval
        endif
        if has("balloon_eval_term")
            set noballoonevalterm
        endif
    endif

    au! NeoDebugAutoCMD
endfunc

function! s:NvimHandleOutput(id, data, event)
    for msg in a:data
        call s:HandleOutput(a:id, substitute(msg, '\r','', 'g'))
    endfor
endfunction


let s:updateinfo_skip_flag = 0
let s:completer_skip_flag = 0
let s:append_msg = ''
let s:appendline = ''
let s:append_err = ''
let s:comm_msg   = ''
let g:append_messages = ["(gdb) "]
" Handle a message received from debugger
func s:HandleOutput(chan, msg)
    if g:neodbg_debuginfo == 1
        echomsg "<GDB>:".a:msg."[s:mode:".s:mode."]"
    endif

    let neodbg_winnr = bufwinnr(g:neodbg_console_name)
    " echomsg "neodbg_winnr".neodbg_winnr

    let cur_mode = mode()
    " let cur_wid = win_getid(winnr())

    " skip complete command,do not output completers
    if  "complete" == strpart(a:msg, 2, strlen("complete"))
        let s:completer_skip_flag = 1
    endif

    if s:completer_skip_flag == 1
        let s:comm_msg .= a:msg
    endif

    if  "complete" == strpart(s:comm_msg, 2, strlen("complete"))  && ( s:comm_msg =~  g:neodbg_prompt)
        let s:completer_skip_flag = 0
        let s:comm_msg = ''
        return
    endif


    " Handle update window
    if  (s:mode == 'u') && ( "info breakpoints" == strpart(a:msg, 2, strlen("info breakpoints")) || "info locals" == strpart(a:msg, 2, strlen("info locals")) || "backtrace" == strpart(a:msg, 2, strlen("backtrace")) || "info threads" == strpart(a:msg, 2, strlen("info threads"))|| "info registers" == strpart(a:msg, 2, strlen("info registers")))
        let s:updateinfo_skip_flag = 1
    endif

    if s:updateinfo_skip_flag == 1
        let s:comm_msg .= a:msg
        let updateinfo_line = a:msg
        if  s:neodbg_quitted != 1
            if  "info locals" == strpart(s:comm_msg, 2, strlen("info locals"))
                call neodebug#GotoLocalsWindow()
            endif

            if  "info registers" == strpart(s:comm_msg, 2, strlen("info registers"))
                call neodebug#GotoRegistersWindow()
            endif

            if  "backtrace" == strpart(s:comm_msg, 2, strlen("backtrace"))
                call neodebug#GotoStackFramesWindow()
            endif

            if  "info threads" == strpart(s:comm_msg, 2, strlen("info threads"))
                call neodebug#GotoThreadsWindow()
            endif

            if "info breakpoints" == strpart(s:comm_msg, 2, strlen("info breakpoints"))
                call neodebug#GotoBreakpointsWindow()
            endif

            if updateinfo_line =~ '^\~"'  
                let updateinfo_line = substitute(updateinfo_line, '\~"\\t', "\~\"\t\t", 'g')
                let updateinfo_line = substitute(updateinfo_line, '\\"', '"', 'g')
                let updateinfo_line = substitute(updateinfo_line, '\\\\', '\\', 'g')
                let s:appendline .= strpart(updateinfo_line, 2, strlen(updateinfo_line)-3)
                if updateinfo_line =~ '\\n"\_$'
                    " echomsg "s:appendfile:".s:appendline
                    let s:appendline = substitute(s:appendline, '\\n\|\\032\\032', '', 'g')
                    call append(line("$")-1, s:appendline)
                    let s:appendline = ''
                    " redraw!
                endif
            endif
            " exec "wincmd ="
        endif
        " echomsg "updateinfo_line::".updateinfo_line
        if updateinfo_line == g:neodbg_prompt
            if neodbg_winnr != -1
                call neodebug#GotoConsoleWindow()

                " if !empty(g:append_messages)
                    " for append_message in (g:append_messages)
                        " call append(line("$"), append_message)
                    " endfor
                    " " let  g:append_messages = []
                    " let g:append_messages = ["(gdb) "]
                " endif
            else
                call win_gotoid(s:cur_wid)
            endif
        endif
    endif


    if  "info locals" == strpart(s:comm_msg, 2, strlen("info locals"))  && ( s:comm_msg =~  g:neodbg_prompt)
        let s:updateinfo_skip_flag = 0
        let s:comm_msg = ''
        return
    endif

    if  "info registers" == strpart(s:comm_msg, 2, strlen("info registers"))  && ( s:comm_msg =~  g:neodbg_prompt)
        let s:updateinfo_skip_flag = 0
        let s:comm_msg = ''
        return
    endif

    if  "backtrace" == strpart(s:comm_msg, 2, strlen("backtrace"))  && ( s:comm_msg =~  g:neodbg_prompt)
        let s:updateinfo_skip_flag = 0
        let s:comm_msg = ''
        return
    endif

    if  "info threads" == strpart(s:comm_msg, 2, strlen("info threads"))  && ( s:comm_msg =~  g:neodbg_prompt)
        let s:updateinfo_skip_flag = 0
        let s:comm_msg = ''
        return
    endif

    if  "info breakpoints" == strpart(s:comm_msg, 2, strlen("info breakpoints"))  && ( s:comm_msg =~  g:neodbg_prompt)
        let s:updateinfo_skip_flag = 0
        let s:comm_msg = ''
        return
    endif


    let debugger_line = a:msg

    if debugger_line != '' && s:completer_skip_flag == 0 && s:updateinfo_skip_flag == 0
        " Handle 
        if debugger_line =~ '^\(\*stopped\|\^done,new-thread-id=\|\*running\|=thread-selected\)'
            call s:HandleCursor(debugger_line)
        elseif debugger_line =~ '^\^done,bkpt=' || debugger_line =~ '=breakpoint-created,'
            call s:HandleNewBreakpoint(debugger_line)
        elseif debugger_line =~ '^=breakpoint-deleted,'
            call s:HandleBreakpointDelete(debugger_line)
        elseif debugger_line =~ '^\(=thread-created,id=\|=thread-selected,id=\|=thread-exited,id=\)'
            if !s:neodbg_quitted
                " call neodebug#UpdateThreadsWindow()
            endif
        elseif debugger_line =~ '^\^done,value='
            call s:HandleEvaluate(debugger_line)
        elseif debugger_line =~ '^\^error,msg='
            call s:HandleError(debugger_line)
        elseif debugger_line == g:neodbg_prompt
            let debugger_line = g:neodbg_prompt
        endif

        if neodbg_winnr != -1
            call neodebug#GotoConsoleWindow()
        endif

        if s:neodbg_sendcmd_flag == 1
            " call setline(line('$'), getline('$').s:neodbg_cmd_historys[-1])
            if neodbg_winnr != -1
                call setline(line('$'), getline('$').s:neodbg_cmd_historys[-1])
            else
                let g:append_messages[-1] =  g:append_messages[-1].s:neodbg_cmd_historys[-1]
            endif
            let s:neodbg_sendcmd_flag = 0
        endif

        if debugger_line =~ '^\~" >"' 
            call append(line("$"), strpart(debugger_line, 2, strlen(debugger_line)-3))
            " elseif debugger_line =~ '^\~"\S\+' 

        " elseif debugger_line =~ '^\*' 
            " call append(line("$"), debugger_line)

            "fix win32 gdb D:\\path\\path\\file
        elseif debugger_line =~ '^&"' && s:usercmd != substitute(strpart(debugger_line, 2 , strlen(debugger_line)-5), '\\\\', '\\', 'g')
            let debugger_line = substitute(debugger_line, '\~"\\t', "\~\"\t\t", 'g')
            let debugger_line = substitute(debugger_line, '\\"', '"', 'g')
            let debugger_line = substitute(debugger_line, '\\\\', '\\', 'g')
            let s:append_msg .= strpart(debugger_line, 2, strlen(debugger_line)-3)
            if debugger_line =~ '\\n"\_$'
                " echomsg "s:append_msg:".s:append_msg
                let s:append_msg = substitute(s:append_msg, '\\n\|\\032\\032', '', 'g')
                " call append(line("$"), s:append_msg)
                if neodbg_winnr != -1
                    call append(line("$"), s:append_msg)
                else
                    call add(g:append_messages, s:append_msg)
                endif
                let s:append_msg = ''
            endif

        elseif debugger_line =~ '^\~"' 
            if debugger_line =~ '^\~"\(Kill the program\|Program exited\|The program is not being run\|The program no longer exists\|Detaching from\|Inferior\)'
                let s:neodbg_is_debugging = 0
            elseif  debugger_line =~ '^\~"\(Starting program\|Attaching to\)'
                " ~"Starting program:  \n" 
                let index_colon = stridx(debugger_line, ":")
                let program_name = strpart(debugger_line, index_colon+2, stridx(debugger_line, ' \n', index_colon)-(index_colon+2) )
                if program_name != ''
                    let s:neodbg_is_debugging = 1
                endif
            endif
            " echomsg 's:neodbg_is_debugging'. s:neodbg_is_debugging
            let debugger_line = substitute(debugger_line, '\~"\\t', "\~\"\t\t", 'g')
            let debugger_line = substitute(debugger_line, '\\"', '"', 'g')
            let debugger_line = substitute(debugger_line, '\\\\', '\\', 'g')
            let s:appendline .= strpart(debugger_line, 2, strlen(debugger_line)-3)
            if debugger_line =~ '\\n"\_$'
                " echomsg "s:appendfile:".s:appendline
                let s:appendline = substitute(s:appendline, '\\n\|\\032\\032', '', 'g')
                " call append(line("$"), s:appendline)
                if neodbg_winnr != -1
                    call append(line("$"), s:appendline)
                    if s:isunix && -1 != stridx(s:appendline, "Terminal for future runs of program being debugged is")
                        call append(line('$'), "Please use gdb's tty command to redirect Your Program's Input and Output.")
                    endif
                else
                    call add(g:append_messages, s:appendline)
                endif
                let s:appendline = ''
            endif

        elseif debugger_line =~ '^\^error,msg='
            " if debugger_line =~ '^\^error,msg="The program'
                let s:append_err =  substitute(a:msg, '.*msg="\(.*\)"', '\1', '')
                let s:append_err =  substitute(s:append_err, '\\"', '"', 'g')
                if getline("$") != s:append_err
                    " call append(line("$"), s:append_err)
                    if neodbg_winnr != -1
                        call append(line("$"), s:append_err)
                    else
                        call add(g:append_messages, s:append_err)
                    endif
                endif
            " endif
        elseif debugger_line == g:neodbg_prompt
            if getline("$") != g:neodbg_prompt
                " call append(line("$"), debugger_line)
                    if neodbg_winnr != -1
                        call neodebug#GotoConsoleWindow()
                        call append(line("$"), debugger_line)
                    else
                        call add(g:append_messages, debugger_line)
                    endif
            endif
        endif

        "vim bug  on linux ?
        if s:isunix
            if debugger_line =~ '^\(\*stopped\)'
                " call append(line("$"), g:neodbg_prompt)
                if neodbg_winnr != -1
                    call append(line("$"), g:neodbg_prompt)
                else
                    call add(g:append_messages, g:neodbg_prompt)
                endif
            endif
        endif

        if neodbg_winnr != -1
            $
            starti!
            redraw
            if cur_mode != "i"
                stopi
            endif
        endif

        " call win_gotoid(s:cur_wid)
        " exec s:cur_winnr. "wincmd w"
    endif


endfunc

function! NeoDebugFoldTextExpr()
    return getline(v:foldstart) . ' ' . substitute(getline(v:foldstart+1), '\v^\s+', '', '') . ' ... (' . (v:foldend-v:foldstart-1) . ' lines)'
endfunction

" Show a balloon with information of the variable under the mouse pointer,
" if there is any.
let s:neodbg_balloonexpr_flag = 0
func! NeoDebugBalloonExpr()
    if v:beval_winid != s:startwin
        return
    endif
    let s:evalFromBalloonExpr = 1
    let s:evalFromBalloonExprResult = ''
    let s:ignoreEvalError = 1
    let s:neodbg_balloonexpr_flag = 1
    call s:SendEval(v:beval_text)
    let s:neodbg_balloonexpr_flag = 0

    let output = ch_readraw(s:neodbg_chan)
    let alloutput = ''
    while output != g:neodbg_prompt
        let alloutput .= output
        let output = ch_readraw(s:neodbg_chan)
    endw

    let value = substitute(alloutput, '.*value="\(.*\)"', '\1', '')
    let value = substitute(value, '\\"', '"', 'g')
    let value = substitute(value, '\\n\s*', '', 'g')

    if s:evalFromBalloonExprResult == ''
        let s:evalFromBalloonExprResult = s:evalexpr . ': ' . value
    else
        let s:evalFromBalloonExprResult .= ' = ' . value
    endif

    if s:evalexpr[0] != '*' && value =~ '^0x' && value != '0x0' && value !~ '"$'
        " Looks like a pointer, also display what it points to.
        let s:ignoreEvalError = 1
        let s:neodbg_balloonexpr_flag = 1
        call s:SendEval('*' . s:evalexpr)
        let s:neodbg_balloonexpr_flag = 0

        let output = ch_readraw(s:neodbg_chan)
        let alloutput = ''
        while output != g:neodbg_prompt
            let alloutput .= output
            let output = ch_readraw(s:neodbg_chan)
        endw

        let value = substitute(alloutput, '.*value="\(.*\)"', '\1', '')
        let value = substitute(value, '\\"', '"', 'g')
        let value = substitute(value, '\\n\s*', '', 'g')

        let s:evalFromBalloonExprResult .= ' ' . value

    endif

    " for neodebug#GotoConsoleWindow to display also
    if g:neodbg_ballonshow_with_print == 1
        call NeoDebugSendCommand('p '. v:beval_text)
        call NeoDebugSendCommand('p '. s:evalexpr)
    endif

    return s:evalFromBalloonExprResult

endfunc

let s:neodbg_complete_flag = 0
fun! NeoDebugComplete(findstart, base)

    if a:findstart

        let usercmd = getline('.')
        if g:neodbg_debugger == 'gdb' && usercmd =~ '^\s*(gdb)' 
            let usercmd = substitute(usercmd, '^\s*(gdb)\s*', '', '')
            let usercmd = substitute(usercmd, '*', '', '') "fixed *pointer
            let usercmd = 'complete ' .  usercmd
        endif

        call NeoDebugSendCommand(usercmd)

        let output = ch_readraw(s:neodbg_chan)
        let s:completers = []
        while output != g:neodbg_prompt
            if output =~ '\~"' 
                let completer = strpart(output, 2, strlen(output)-5) 
                call add(s:completers, completer)
            endif
            let output = ch_readraw(s:neodbg_chan)
        endw

        " locate the start of the word
        let line = getline('.')
        let start = col('.') - 1
        while start > 0 && line[start - 1] =~ '\S' && line[start-1] != '*' "fixed *pointer
            let start -= 1
        endwhile
        return start
    else
        " find s:completers matching the "a:base"
        let res = []
        for m in (s:completers)
            if a:base == '' 
                return res
            endif

            if m =~ '^' . a:base
                call add(res, m)
            endif

            if m =~ '^\a\+\s\+' . a:base
                call add(res, substitute(m, '^\a*\s*', '', ''))
            endif
        endfor
        return res
    endif
endfun

let s:match = []
function! s:MyMatch(expr, pat)
    let s:match = matchlist(a:expr, a:pat)
    return len(s:match) >0
endf
" if the value is a pointer ( var = 0x...), expand it by "NeoDebug p *var"
" e.g. $11 = (CDBMEnv *) 0x387f6d0
" e.g.  
" (CDBMEnv) $22 = {
"  m_pTempTables = 0x37c6830,
"  ...
" }
function! NeoDebugExpandPointerExpr()
    if ! s:MyMatch(getline('.'), '\v((\$|\w)+) \=.{-0,} 0x')
        return 0
    endif
    let cmd = s:match[1]
    let lastln = line('.')
    while 1
        normal [z
        if line('.') == lastln
            break
        endif
        let lastln = line('.')

        if ! s:MyMatch(getline('.'), '\v(([<>$]|\w)+) \=')
            return 0
        endif
        " '<...>' means the base class. Just ignore it. Example:
        " (OBserverDBMCInterface) $4 = {
        "   <__DBMC_ObserverA> = {
        "     members of __DBMC_ObserverA:
        "     m_pEnv = 0x378de60
        "   }, <No data fields>}

        if s:match[1][0:0] != '<' 
            let cmd = s:match[1] . '.' . cmd
        endif
    endwhile 
    call NeoDebugSendCommand("p *" . cmd)
    if foldlevel('.') > 0
        " goto beginning of the fold and close it
        normal [zzc
        " ensure all folds for this var are closed
        foldclose!
    endif
    return 1
endf

" Install commands in the current window to control the debugger.
func NeoDebugInstallCommandsHotkeys()

    command Break call s:SetBreakpoint()
    command Clear call s:ClearBreakpoint()
    command Step call NeoDebugSendCommand('-exec-step')
    command Over call NeoDebugSendCommand('-exec-next')
    command Finish call NeoDebugSendCommand('-exec-finish')
    command -nargs=* Run call s:Run(<q-args>)
    command -nargs=* Arguments call NeoDebugSendCommand('-exec-arguments ' . <q-args>)
    command Stop call NeoDebugSendCommand('-exec-interrupt')
    command Continue call NeoDebugSendCommand('-exec-continue')
    command -range -nargs=* Evaluate call s:Evaluate(<range>, <q-args>)
    command Winbar call NeoDebugInstallWinbar()

    " TODO: can the K mapping be restored?
    nnoremap K :Evaluate<CR>

    if has('menu') && &mouse != ''
        call NeoDebugInstallWinbar()

        if !exists('g:neodbg_popup') || g:neodbg_popup != 0
            let s:saved_mousemodel = &mousemodel
            let &mousemodel = 'popup_setpos'
            an 1.200 PopUp.-SEP3-	<Nop>
            an 1.210 PopUp.Set\ breakpoint	:Break<CR>
            an 1.220 PopUp.Clear\ breakpoint	:Clear<CR>
            an 1.230 PopUp.Evaluate		:Evaluate<CR>
        endif
    endif


    hi NeoDbgBreakPoint    guibg=darkblue  ctermbg=darkblue term=reverse 
    hi NeoDbgDisabledBreak guibg=lightblue guifg=black ctermbg=lightblue ctermfg=black
    hi NeoDbgPC            guibg=Orange    guifg=black gui=bold ctermbg=Yellow ctermfg=black

    " hi NeoDbgBreakPoint guibg=darkred guifg=white ctermbg=darkred ctermfg=white
    " hi NeoDbgDisabledBreak guibg=lightred guifg=black ctermbg=lightred ctermfg=black

    sign define NeoDebugBP  linehl=NeoDbgBreakPoint    text=B> texthl=NeoDbgBreakPoint
    sign define NeoDebugDBP linehl=NeoDbgDisabledBreak text=b> texthl=NeoDbgDisabledBreak
    sign define NeoDebugPC  linehl=NeoDbgPC            text=>> texthl=NeoDbgPC

    " highlight NeoDebugGoto guifg=Blue
    hi def link NeoDebugKey Statement
    hi def link NeoDebugHiLn Statement
    hi def link NeoDebugGoto Underlined
    hi def link NeoDebugPtr Underlined
    hi def link NeoDebugFrame LineNr
    hi def link NeoDebugCmd Macro
    " syntax
    syn keyword NeoDebugKey Function Breakpoint Catchpoint 
    syn match NeoDebugFrame /\v^#\d+ .*/ contains=NeoDebugGoto
    syn match NeoDebugGoto /\v<at [^()]+:\d+|file .+, line \d+/
    syn match NeoDebugCmd /^(gdb).*/
    syn match NeoDebugPtr /\v(^|\s+)\zs\$?\w+ \=.{-0,} 0x\w+/
    " highlight the whole line for 
    " returns for info threads | info break | finish | watchpoint
    syn match NeoDebugHiLn /\v^\s*(Id\s+Target Id|Num\s+Type|Value returned is|(Old|New) value =|Hardware watchpoint).*$/

    " syntax for perldb
    syn match NeoDebugCmd /^\s*DB<.*/
    "	syn match NeoDebugFrame /\v^#\d+ .*/ contains=NeoDebugGoto
    syn match NeoDebugGoto /\v from file ['`].+' line \d+/
    syn match NeoDebugGoto /\v at ([^ ]+) line (\d+)/
    syn match NeoDebugGoto /\v at \(eval \d+\)..[^:]+:\d+/


    " shortcut in NeoDebug window

    call neodebug#CustomConsoleKey()

    noremap <buffer><silent>? :call neodebug#ToggleHelp()<cr>

    inoremap <expr><buffer> <silent> <c-p>  "\<c-x><c-l>"
    inoremap <expr><buffer> <silent> <c-r>  "\<c-x><c-n>"

    inoremap <expr><buffer><silent> <TAB>    pumvisible() ? "\<C-n>" : "\<c-x><c-u>"
    inoremap <expr><buffer><silent> <S-TAB>  pumvisible() ? "\<C-p>" : "\<c-x><c-u>"
    noremap <buffer><silent> <Tab> ""
    noremap <buffer><silent> <S-Tab> ""

    noremap <buffer><silent> <ESC> :call neodebug#CloseConsoleWindow()<CR>

    inoremap <expr><buffer> <silent> <CR> pumvisible() ? "\<c-y><c-o>:call NeoDebug(getline('.'), 'i')<cr>" : "<c-o>:call NeoDebug(getline('.'), 'i')<cr>"
    " inoremap <buffer> <silent> <C-CR> :<c-o>:call NeoDebug("", 'i')<cr>

    nnoremap <buffer> <silent> <CR> :call NeoDebug(getline('.'), 'n')<cr>
    nmap <buffer> <silent> <2-LeftMouse> <cr>

    nmap <silent> <F9>	         :call <SID>ToggleBreakpoint()<CR>
    map! <silent> <F9>	         <c-o>:call <SID>ToggleBreakpoint()<CR>

    nmap <silent> <Leader>ju	 :call <SID>Jump()<CR>
    nmap <silent> <C-S-F10>		 :call <SID>Jump()<CR>
    nmap <silent> <C-F10>        :call <SID>RunToCursur()<CR>
    map! <silent> <C-S-F10>		 <c-o>:call <SID>Jump()<CR>
    map! <silent> <C-F10>        <c-o>:call <SID>RunToCursur()<CR>
    nmap <silent> <F6>           :call neodebug#ToggleConsoleWindow()<CR>
    imap <silent> <F6>           <c-o>:call neodebug#ToggleConsoleWindow()<CR>
    nmap <silent> <C-P>	         :NeoDebug p <C-R><C-W><CR>
    vmap <silent> <C-P>	         y:NeoDebug p <C-R>0<CR>
    nmap <silent> <Leader>pr	 :NeoDebug p <C-R><C-W><CR>
    vmap <silent> <Leader>pr	 y:NeoDebug p <C-R>0<CR>
    nmap <silent> <Leader>bt	 :NeoDebug bt<CR>

    nmap <silent> <F5>    :NeoDebug c<cr>
    nmap <silent> <S-F5>  :NeoDebug k<cr>
    nmap <silent> <F10>   :NeoDebug n<cr>
    nmap <silent> <F11>   :NeoDebug s<cr>
    nmap <silent> <S-F11> :NeoDebug finish<cr>
    nmap <silent> <c-c> :NeoDebugStop<cr>

    map! <silent> <F5>    <c-o>:NeoDebug c<cr>
    map! <silent> <S-F5>  <c-o>:NeoDebug k<cr>
    map! <silent> <F10>   <c-o>:NeoDebug n<cr>
    map! <silent> <F11>   <c-o>:NeoDebug s<cr>
    map! <silent> <S-F11> <c-o>:NeoDebug finish<cr>

    amenu NeoDebug.Run/Continue<tab>F5 					:NeoDebug c<CR>
    amenu NeoDebug.Step\ into<tab>F11					:NeoDebug s<CR>
    amenu NeoDebug.Next<tab>F10							:NeoDebug n<CR>
    amenu NeoDebug.Step\ out<tab>Shift-F11				:NeoDebug finish<CR>
    amenu NeoDebug.Run\ to\ cursor<tab>Ctrl-F10			:call <SID>RunToCursur()<CR>
    amenu NeoDebug.Stop\ debugging\ (Kill)<tab>Shift-F5	:NeoDebug k<CR>
    amenu NeoDebug.-sep1- :

    amenu NeoDebug.Show\ callstack<tab>\\bt				:call NeoDebug("where")<CR>
    amenu NeoDebug.Set\ next\ statement\ (Jump)<tab>Ctrl-Shift-F10\ or\ \\ju 	:call <SID>Jump()<CR>
    amenu NeoDebug.Top\ frame 						:call NeoDebug("frame 0")<CR>
    amenu NeoDebug.Callstack\ up 					:call NeoDebug("up")<CR>
    amenu NeoDebug.Callstack\ down 					:call NeoDebug("down")<CR>
    amenu NeoDebug.-sep2- :

    amenu NeoDebug.Preview\ variable<tab>Ctrl-P		:NeoDebug p <C-R><C-W><CR> 
    amenu NeoDebug.Print\ variable<tab>\\pr			:NeoDebug p <C-R><C-W><CR> 
    amenu NeoDebug.Show\ breakpoints 				:NeoDebug info breakpoints<CR>
    amenu NeoDebug.Show\ locals 					:NeoDebug info locals<CR>
    amenu NeoDebug.Show\ args 						:NeoDebug info args<CR>
    amenu NeoDebug.Quit			 					:NeoDebug q<CR>


endfunc

let s:winbar_winids = []

" Install the window toolbar in the current window.
func NeoDebugInstallWinbar()
    nnoremenu WinBar.Step   :NeoDebug s<CR>
    nnoremenu WinBar.Next   :NeoDebug n<CR>
    nnoremenu WinBar.Finish :NeoDebug finish<CR>
    nnoremenu WinBar.Cont   :NeoDebug c<CR>
    nnoremenu WinBar.Stop   :NeoDebug k<CR>
    nnoremenu WinBar.Eval   :Evaluate<CR>
    call add(s:winbar_winids, win_getid(winnr()))
endfunc

" Delete installed debugger commands in the current window.
func NeoDebugDeleteCommandsHotkeys()
    delcommand Break
    delcommand Clear
    delcommand Step
    delcommand Over
    delcommand Finish
    delcommand Run
    delcommand Arguments
    delcommand Stop
    delcommand Continue
    delcommand Evaluate
    delcommand Winbar

    nunmap K

    if has('menu')
        " Remove the WinBar entries from all windows where it was added.
        let curwinid = win_getid(winnr())
        for winid in s:winbar_winids
            if win_gotoid(winid)
                aunmenu WinBar.Step
                aunmenu WinBar.Next
                aunmenu WinBar.Finish
                aunmenu WinBar.Cont
                aunmenu WinBar.Stop
                aunmenu WinBar.Eval
            endif
        endfor
        call win_gotoid(curwinid)
        let s:winbar_winids = []

        if exists('s:saved_mousemodel')
            let &mousemodel = s:saved_mousemodel
            unlet s:saved_mousemodel
            aunmenu PopUp.-SEP3-
            aunmenu PopUp.Set\ breakpoint
            aunmenu PopUp.Clear\ breakpoint
            aunmenu PopUp.Evaluate
        endif
    endif

    exe 'sign unplace ' . s:pc_id
    for key in keys(s:breakpoints)
        exe 'sign unplace ' . (s:break_id + key)
    endfor
    sign undefine NeoDebugPC
    sign undefine NeoDebugBP
    "unlet s:breakpoints

    unmap <F9>
    unmap <Leader>ju
    unmap <C-S-F10>
    unmap <C-F10>
    unmap <C-P>
    unmap <Leader>pr
    unmap <Leader>bt

    unmap <F5>
    unmap <S-F5>
    unmap <F10>
    unmap <F11>
    unmap <S-F11>

    if s:ismswin
        " so _exrc
        exec 'so '. s:neodbg_exrc . s:neodbg_port
        call delete(s:neodbg_exrc . s:neodbg_port)
    else
        " so .exrc
        exec 'so '. s:neodbg_exrc . s:neodbg_port
        call delete(s:neodbg_exrc . s:neodbg_port)
    endif
    stopi
endfunc

" :Next, :Continue, etc - send a command to debugger
let s:neodbg_quitted = 0
let s:neodbg_sendcmd_flag = 0
let s:usercmd = ''
" func NeoDebugSendCommand(cmd)
function! NeoDebugSendCommand(cmd, ...)  " [mode]
    " echomsg "<GDB>cmd:[".a:cmd."]"
    let usercmd = a:cmd
    let mode = a:0>0 ? a:1 : ''
    let s:mode = mode

    if  mode == 'u'  ||  -1 != match(usercmd, '^complete')
        " echomsg "<GDB1>:[".usercmd."][mode:".mode."]"
        let s:neodbg_sendcmd_flag = 0
    else
        if usercmd != s:neodbg_cmd_historys[-1] && usercmd != ''
            " echomsg "<GDB2>:[".usercmd."][mode:".mode."]"
            call add(s:neodbg_cmd_historys, usercmd)
        endif

        if mode == '' && s:neodbg_init_flag == 0
            let s:neodbg_sendcmd_flag = 1
        endif

        if usercmd == '' && mode == 'i'
            let usercmd = s:neodbg_cmd_historys[-1]
            let s:neodbg_sendcmd_flag = 1
        elseif usercmd == s:neodbg_cmd_historys[-1] && mode == 'i'
            let s:neodbg_sendcmd_flag = 0
        endif

    endif


    if g:neodbg_debuginfo == 1
        silent echohl ModeMsg
        echomsg "<GDB>:[".usercmd."][mode:".mode."]"
        silent echohl None
    endif
    let s:usercmd = usercmd
    if has('nvim')
        call jobsend(s:nvim_commjob, usercmd . "\n")
    else
        call ch_sendraw(s:commjob, usercmd . "\n")
    endif
    if usercmd == 'q'
        let  s:neodbg_quitted = 1
    endif
endfunc

func s:SendKey(key)
    if has('nvim')
        call jobsend(s:nvim_commjob, a:key)
    else
        call ch_sendraw(s:commjob, a:key)
    endif
endfunc

func s:SendEval(expr)
    call NeoDebugSendCommand('-data-evaluate-expression "' . a:expr . '"')
    let s:evalexpr = a:expr
endfunc

func s:PlaceSign(nr, entry)
    exe 'sign place ' . (s:break_id + a:nr) . ' line=' . a:entry['lnum'] . ' name=NeoDebugBP file=' . a:entry['fname']
    let a:entry['placed'] = 1
endfunc

" Handle a BufRead autocommand event: place any signs.
func s:BufferRead()
    let fname = expand('<afile>:p')
    " let fname = fnamemodify(expand('<afile>:t'), ":p")
    " echomsg "BufferRead:".fname
    for [nr, entry] in items(s:breakpoints)
        if entry['fname'] == fname
            call s:PlaceSign(nr, entry)
        endif
    endfor
endfunc

" Handle a BufUnload autocommand event: unplace any signs.
func s:BufferUnload()
    let fname = expand('<afile>:p')
    " let fname = fnamemodify(expand('<afile>:t'), ":p")
    " echomsg "BufferUnload:".fname
    for [nr, entry] in items(s:breakpoints)
        if entry['fname'] == fname
            let entry['placed'] = 0
        endif
    endfor
endfunc


func s:SetBreakpoint()
    " Setting a breakpoint may not work while the program is running.
    " Interrupt to make it work.
    let do_continue = 0
    if !s:stopped
        let do_continue = 1
        call NeoDebugSendCommand('-exec-interrupt')
        sleep 10m
    endif
    " call NeoDebugSendCommand('-break-insert '
    " \ . fnameescape(expand('%:p')) . ':' . line('.'))
    call NeoDebugSendCommand('break '
                \ . fnameescape(expand('%:p')) . ':' . line('.'))
    if do_continue
        call NeoDebugSendCommand('-exec-continue')
    endif
endfunc

func s:ClearBreakpoint()
    call win_gotoid(s:startwin)
    let fname = fnameescape(expand('%:p'))
    let lnum = line('.')
    " echomsg "ClearBreakpoint:fname:lnum".fname.":".lnum
    for [key, val] in items(s:breakpoints)
        if val['fname'] == fname && val['lnum'] == lnum
            " echomsg "val[fname]:lnum".val['fname'].":".val['lnum'].":".key
            call NeoDebugSendCommand('delete ' . key)
            " call ch_sendraw(s:commjob, '-break-delete ' . key . "\n")
            " call ch_sendraw(s:commjob, '-break-disable ' . key . "\n")
            " Assume this always wors, the reply is simply "^done".
            exe 'sign unplace ' . (s:break_id + key)
            unlet s:breakpoints[key]
            break
        endif
    endfor
endfunc

func s:ToggleBreakpoint()
    call win_gotoid(s:startwin)
    let fname = fnameescape(expand('%:p'))
    let lnum = line('.')
    " echomsg "ToggleBreakpoint:fname:lnum".fname.":".lnum

    for [key, val] in items(s:breakpoints)
        if val['fname'] == fname && val['lnum'] == lnum
            " echomsg "val[fname]:lnum".val['fname'].":".val['lnum'].":".key
            " call ch_sendraw(s:commjob, 'delete ' . key . "\n")
            call NeoDebugSendCommand('delete ' . key)
            " Assume this always wors, the reply is simply "^done".
            exe 'sign unplace ' . (s:break_id + key)
            unlet s:breakpoints[key]
            return
        endif
    endfor
    call s:SetBreakpoint()
endfunc

func s:Run(args)
    if a:args != ''
        call NeoDebugSendCommand('-exec-arguments ' . a:args)
    endif
    call NeoDebugSendCommand('-exec-run')
endfunc

func s:Evaluate(range, arg)
    if a:arg != ''
        let expr = a:arg
    elseif a:range == 2
        let pos = getcurpos()
        let reg = getreg('v', 1, 1)
        let regt = getregtype('v')
        normal! gv"vy
        let expr = @v
        call setpos('.', pos)
        call setreg('v', reg, regt)
    else
        let expr = expand('<cexpr>')
    endif
    let s:ignoreEvalError = 0
    call s:SendEval(expr)
endfunc

let s:ignoreEvalError = 0
let s:evalFromBalloonExpr = 0

" Handle the result of data-evaluate-expression
func s:HandleEvaluate(msg)
    " echomsg "HandleEvaluate:".a:msg
    let value = substitute(a:msg, '.*value="\(.*\)"', '\1', '')
    let value = substitute(value, '\\"', '"', 'g')

    if s:evalexpr[0] != '*' && value =~ '^0x' && value != '0x0' && value !~ '"$'
        " Looks like a pointer, also display what it points to.
        let s:ignoreEvalError = 1
        call s:SendEval('*' . s:evalexpr)
    else
        let s:evalFromBalloonExpr = 0
    endif
endfunc


" Handle an error.
func s:HandleError(msg)
    " call s:SendEval(v:beval_text)
    if s:ignoreEvalError
        " Result of s:SendEval() failed, ignore.
        let s:ignoreEvalError = 0
        let s:evalFromBalloonExpr = 0
        return
    endif
    " echoerr substitute(a:msg, '.*msg="\(.*\)"', '\1', '')
endfunc

" Handle stopping and running message from debugger.
" Will update the sign that shows the current position.
func s:HandleCursor(msg)
    let wid = win_getid(winnr())

    if a:msg =~ '\*stopped'
        let s:stopped = 1
    elseif a:msg =~ '\*running'
        let s:stopped = 0
    endif
    if a:msg =~ '\(\*stopped,reason="breakpoint-hit"\)'
        call  neodebug#UpdateBreakpoints()
    endif

    if a:msg =~ '\(\*stopped\)'
        call neodebug#UpdateLocals()
        call neodebug#UpdateStackFrames()
    endif

    if win_gotoid(s:startwin)
        let fname = substitute(a:msg, '.*fullname="\([^"]*\)".*', '\1', '')
        " let fname = fnamemodify(fnamemodify(fname, ":t"), ":p")
        "fix mswin
        " echomsg "HandleCursor:fname:".fname
        if -1 == match(fname, '\\\\')
            let fname = fname
        else
            let fname = substitute(fname, '\\\\','\\', 'g')
        endif
        " echomsg "HandleCursor:fname:".fname

        if a:msg =~ '\(\*stopped\|=thread-selected\|new-thread-id=\)' && filereadable(fname)
            let lnum = substitute(a:msg, '.*line="\([^"]*\)".*', '\1', '')
            if lnum =~ '^[0-9]*$'
                if expand('%:p') != fnamemodify(fname, ':p')
                    if &modified
                        " TODO: find existing window
                        exe 'split ' . fnameescape(fname)
                        let s:startwin = win_getid(winnr())
                    else
                        exe 'edit ' . fnameescape(fname)
                    endif
                endif
                " echomsg "HandleCursor:fname:lnum=".fname.':'.lnum
                exe lnum
                exe 'sign unplace ' . s:pc_id
                exe 'sign place ' . s:pc_id . ' line=' . lnum . ' name=NeoDebugPC file=' . fname
                setlocal signcolumn=yes
            endif
        else
            exe 'sign unplace ' . s:pc_id
        endif

        call win_gotoid(wid)
    endif
endfunc

" Handle setting a breakpoint
" Will update the sign that shows the breakpoint
func s:HandleNewBreakpoint(msg)
    if -1 == stridx(a:msg, 'fullname')
        return
    endif
    let nr = substitute(a:msg, '.*number="\([0-9]\)*\".*', '\1', '') + 0
    if nr == 0
        return
    endif

    if has_key(s:breakpoints, nr)
        let entry = s:breakpoints[nr]
    else
        let entry = {}
        let s:breakpoints[nr] = entry
    endif

    let fname = substitute(a:msg, '.*fullname="\([^"]*\)".*', '\1', '')
    let lnum = substitute(a:msg, '.*line="\([^"]*\)".*', '\1', '')


    " let fname = fnamemodify(fnamemodify(fname, ":t"), ":p")
    " echomsg "fname:".fname
    " echomsg "lnum:".lnum

    " fix mswin
    " echomsg "HandleCursor:fname:".fname
    if -1 == match(fname, '\\\\')
        let fname = fname
    else
        let fname = substitute(fname, '\\\\','\\', 'g')
    endif
    " echomsg "fname:lnum=".fname.':'.lnum

    let entry['fname'] = fname
    let entry['lnum'] = lnum

    call win_gotoid(s:startwin)
    " exe 'e +'.lnum ' '.fname
    try
        exe 'e '.fname
        exe lnum
    catch /^Vim\%((\a\+)\)\=:E37/
        " TODO ask 
        silent echohl ModeMsg
        echomsg "No write since last change (add ! to override)"
        silent echohl None
    catch /^Vim\%((\a\+)\)\=:E325/
        " TODO ask 
        silent echohl ModeMsg
        echomsg "Found a swap file"
        silent echohl None
    endtry

    if bufloaded(fname)
        call s:PlaceSign(nr, entry)
    endif
    redraw

        call neodebug#UpdateBreakpoints()
endfunc

" Handle deleting a breakpoint
" Will remove the sign that shows the breakpoint
func s:HandleBreakpointDelete(msg)
    let nr = substitute(a:msg, '.*id="\([0-9]*\)\".*', '\1', '') + 0
    if nr == 0
        return
    endif
    if has_key(s:breakpoints, nr)
        let entry = s:breakpoints[nr]
        if has_key(entry, 'placed')
            exe 'sign unplace ' . (s:break_id + nr)
            unlet entry['placed']
        endif
        unlet s:breakpoints[nr]
    endif
    call neodebug#UpdateBreakpoints()
endfunc

" TODO 
function! s:NeoDebug_bpkey(file, line)
    return a:file . ":" . a:line
endf

function! s:NeoDebugGotoFile(fname, lnum)
    let fname = a:fname
    let lnum  = a:lnum
    let wid = win_getid(winnr())

    if win_gotoid(s:startwin)
        let fname = fnamemodify(fnamemodify(fname, ":t"), ":p")

        if filereadable(fname)
            if lnum =~ '^[0-9]*$'
                if expand('%:p') != fnamemodify(fname, ':p')
                    if &modified
                        " TODO: find existing window
                        exe 'split ' . fnameescape(fname)
                        let s:startwin = win_getid(winnr())
                    else
                        exe 'edit ' . fnameescape(fname)
                    endif
                endif
                exe lnum
                exe 'sign unplace ' . s:pc_id
                exe 'sign place ' . s:pc_id . ' line=' . lnum . ' name=NeoDebugPC file=' . fname
                setlocal signcolumn=yes
            else
                exe 'sign unplace ' . s:pc_id
            endif
        endif

        call win_gotoid(wid)
    endif
endfunction

function! s:CursorPos()
    let file = expand("%:t")
    let line = line(".")
    return s:NeoDebug_bpkey(file, line)
endf

function! s:Jump()
    call win_gotoid(s:startwin)
    let key = s:CursorPos()
    "	call NeoDebug("@tb ".key." ; ju ".key)
    "	call NeoDebug("set $rbp1=$rbp; set $rsp1=$rsp; @tb ".key." ; ju ".key . "; set $rsp=$rsp1; set $rbp=$rbp1")
    call NeoDebug("ju ".key)
endf

function! s:RunToCursur()
    call win_gotoid(s:startwin)
    let key = s:CursorPos()
    call NeoDebug("tb ".key)
    call NeoDebug("c")
endf

function! NeoDebugGotoStartWin()
    call win_gotoid(s:startwin)
endfunction

command! -nargs=* -complete=file NeoDebug :call NeoDebug(<q-args>)
command! -nargs=* -complete=file NeoDebugStop :call NeoDebugStop(<q-args>)
command!  ToggleConsole :call neodebug#ToggleConsoleWindow()
command!  OpenConsole :call neodebug#UpdateConsoleWindow()
command!  OpenLocals :call neodebug#UpdateLocalsWindow()
command!  OpenRegisters :call neodebug#UpdateRegistersWindow()
command!  OpenStacks :call neodebug#UpdateStackFramesWindow()
command!  OpenThreads :call neodebug#UpdateThreadsWindow()
command!  OpenBreaks :call neodebug#UpdateBreakpointsWindow()

command!  CloseConsole :call neodebug#CloseConsole()
command!  CloseLocals :call neodebug#CloseLocals()
command!  CloseRegisters :call neodebug#CloseRegisters()
command!  CloseStacks :call neodebug#CloseStackFrames()
command!  CloseThreads :call neodebug#CloseThreads()
command!  CloseBreaks :call neodebug#CloseBreakpoints()

" vim: set foldmethod=marker 
