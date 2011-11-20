" rsto.vim      : Some ReSTructured text routines
" Version       : 0.0.2
" Maintainer    : Yosifov Paul<bulg@ngs.ru>
" Last modified : 11/16/2011
" License       : This script is released under the Vim License.
" 
" 1. Open file when cursor is in '.. include::' block or create such file and
"    lines, if does not exists in targeted file. Also jump to corresponding
"    position in the file
" 2. Open image when cursor is in '.. image::' or '.. figure::' blocks. If
"    does not exist, then create file via external tool.
"
" Settings:
" * RSTO_imgopen - path to executable file to open image.
" * RSTO_imgnew - path to executable file to create image.
"   Default is 'gimp'. For Windows good value is
"   'rundll32 url.dll,FileProtocolHandler'
"
" See bindings at the end of this file. Defaults are:
"   ',gf' - open a file referenced by a directive (position has not mean)
"   ',gF' - forced open at specified position in the directive (line or
"           pattern is used).  If does not exist (file, text), they will be
"           created
"
" To add custom opener, create own function (handler, like RSTOImageHandler),
" then add entry in g:RSTO_handlers for customized directive

if exists("loaded_rsto")
    finish "stop loading the script
endif
let loaded_rsto=1

let s:global_cpo = &cpo  "store compatible-mode in local variable 
set cpo&vim              " go into nocompatible-mode

" ----------------------------------------------------------------------------
" Settings

if !exists("RSTO_imgopen")
    let s:RSTO_imgopen = "gimp"
else
    let s:RSTO_imgopen = RSTO_imgopen
    unlet RSTO_imgopen
endif
if !exists("RSTO_imgnew")
    let s:RSTO_imgnew = "gimp"
else
    let s:RSTO_imgnew = RSTO_imgnew
    unlet RSTO_imgnew
endif

" ----------------------------------------------------------------------------
" Dictionary for RST directive block:
" .hdvalue - value of directive (heading line)
" .hdtitle - name of directive
" [*] - options

function! s:RSTODirectiveBlock()
    let lln = line('$') " last line number
    let cln = line('.') " current line number
    let curline = getline(cln)
    let block_range = [0, lln+1]

    if empty(curline)
        " If current line is empty so block detection is impossible
        return {}
    endif

    " Find begin of block
    let nln = cln
    while nln > 0
        let curline = getline(nln)
        if empty(curline)
            let block_range[0] = nln
            break
        endif
        let nln = nln - 1
    endwhile

    let nln = cln
    " Find end of block
    while nln <= lln
        let curline = getline(nln)
        if empty(curline)
            let block_range[1] = nln
            break
        endif
        let nln = nln + 1
    endwhile
    " lines of the block
    let lines = getline(block_range[0]+1, block_range[1]-1)
    " Recognize directive name and value (after ::)
    let line0 = get(lines, 0, '')
    let m = matchlist(line0, '\s*\(\w\+\)::\s*\([^\r\n]\+\)')
    if len(m) < 3
        return {}
    endif
    let dict = {'hdtitle':m[1], 'hdvalue':m[2]}
    " Recognize all options names and its values
    for line in lines[1:]
        let m = matchlist(line, '\s*:\(\S\+\):\s*\([^\r\n]\+\)\?')
        if len(m) < 3
            continue
        else
            if empty(m[2])
                let dict[m[1]] = 1
            else
                let dict[m[1]] = m[2]
            endif
        endif
    endfor
    " Return as dictionary
    return dict
endfunction

" ----------------------------------------------------------------------------
"  Append to the file end text snippet (started with line, stopped with line)

function! s:RSTOCreateTextForInclude(start_after, end_before)
    norm 1G
    if 0 == search(a:start_after)
        " If no such pattern yet, then append
        norm G
        if line("$") != 1
            " If file not empty
            call append("$", "")
            let pos = line("$")
        else
            let pos = 0
        endif
        call append(pos, a:start_after)
        let pos += 1
        call append(pos, "    TODO...")
        let pos += 1
        call append(pos, a:end_before)
        exec "norm " . pos . "G"
        norm zo
        norm _
    endif
endfunction

" ----------------------------------------------------------------------------
"  Handle opening events for image/figure directive

function! s:RSTOImageHandler(event, block)
    let filename = a:block.hdvalue
    if empty(filename)
        return
    else
        let filename = fnameescape(filename)
        let exists = filereadable(filename)
        let shopen = s:RSTO_imgopen . ' ' . filename
        if a:event == 'goto'
            if exists
                call system(shopen)
            else
                echohl ErrorMsg
                echomsg "File does not exist"
                echohl None
            endif
        elseif a:event == 'goto-force'
            if exists
                echomsg "File already exists. Opening.."
                call system(shopen)
            else
                let shnew = s:RSTO_imgnew . ' ' . filename
                call system(shnew)
            endif
        endif
    endif
endfunction

" ----------------------------------------------------------------------------
"  Handle opening events for include directive

function! s:RSTOIncludeHandler(event, block)
    let filename = a:block.hdvalue
    if empty(filename)
        return
    else
        let filename = fnameescape(filename)
        let exists = filereadable(filename)
        if a:event == 'goto'
            if !exists
                echohl ErrorMsg
                echomsg "File does not exist"
                echohl None
                return
            else
                exec ":e " . filename
            endif
        elseif a:event == 'goto-force'
            if !exists
                echomsg "File does not exist. Creating.."
                :w
                :enew!
                exec ":w " . filename
            endif
            " Now exists, so try to open and may be add nonexistent text
            exec ":e " . filename
            if has_key(a:block, 'start-line')
                exec ":norm " . a:block['start-line'] . "G"
            elseif has_key(a:block, 'start-after') && has_key(a:block, 'end-before')
                let found = search(a:block['start-after'])
                if found == 0
                    echomsg "Text does not exist. Creating.."
                    call s:RSTOCreateTextForInclude(a:block['start-after'], a:block['end-before'])
                endif
            else
                echohl ErrorMsg
                echomsg "Incomplete directive options list. Can not open"
                echohl None
            endif
        endif
    endif
endfunction

" ----------------------------------------------------------------------------
"  Emit (dispatching) event to handlers of currect recognized directive

function! g:RSTOEmit(event)
    let block = s:RSTODirectiveBlock()
    if !empty(block)
        for directive in keys(g:RSTO_handlers)
            " Try to find handler (from known directives handlers) for this block
            if block.hdtitle == directive
                " This line contents current directive
                call g:RSTO_handlers[directive](a:event, block)
                break
            endif
        endfor
    endif
endfunction

" Return to the users own compatible-mode setting
:let &cpo = s:global_cpo

" ----------------------------------------------------------------------------
" Customizations

" handlers are dictionary {'RST-directive' : function('handler-func-name')}
let g:RSTO_handlers = {
            \ "image": function('s:RSTOImageHandler'),
            \ "figure": function('s:RSTOImageHandler'),
            \ "include": function('s:RSTOIncludeHandler') }

" map keys
nnoremap <unique> <silent> <leader>gf :call g:RSTOEmit('goto')<CR>
nnoremap <unique> <silent> <leader>gF :call g:RSTOEmit('goto-force')<CR>
