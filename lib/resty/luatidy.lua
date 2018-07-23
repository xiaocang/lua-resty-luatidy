#!/etc/nginx/bin/resty
--[[
author: wangjiahao@2018
translate from luatidy perl version
use for create pretty lua code
--]]

local _M = { _VERSION = 0.1 }

local INDENT = '    ' -- space x 4

-- remove useless \r\n
local function chomp(l)
    if not l then
        return ""
    end
    local nl, n, err = ngx.re.gsub(l, [=[[\r\n]+$]=], "", "jo")

    return nl or l
end

-- count capture numbers
local function y(l, regex, repl, regex_op)
    if not l then
        return 0
    end

    regex_op = regex_op or "jo"

    local nl, n, err = ngx.re.gsub(l, regex, repl, regex_op)
    if not nl then
        return nl, 0
    end

    return nl, n
end

local function pretty(code, print_flag)
    local tidycode, tidycode_len = {}, 0
    local warning, warning_len = {}, 0

    local currIndent, nextIndent, prevLength = 0, 0, 0

    if not code then
        return nil, "empty code"
    end

    local code_by_line, err = ngx.re.gmatch(code, [=[([^\r\n]+\r?\n)]=], "jo")
    if not code_by_line then
        return
    end

    local ix = 0
    local ltbl = code_by_line()
    while ltbl do
        ix = ix + 1
        local l = ltbl[1]
        l = chomp(l)

        -- remove all spaces on both ends
        do
            local nl = ngx.re.gsub(l, [=[^\s+|\s+$]=], "", "jo")
            l = nl or l
        end

        -- replace all whitespaces inside the string with one space
        do
            local nl = ngx.re.gsub(l, [[\s+]], " ", "jo")
            l = nl or l
        end

        -- save line
        local orig_l = l

        -- remove all quoted fragments for proper bracket processing
        do
            local nl = ngx.re.gsub(l, [=[['"])[^\1]*?\1]=], "", "jo")
            l = nl or l
        end
        -- remove all comments; this ignores long bracket style comments
        do
            local nl = ngx.re.gsub(l, [=[\s*--.+]=], "", "jo")
            l = nl or l
        end

        -- open a level; increase next indentation; don't change current one
        local open_level_flag
        do
            open_level_flag
                = ngx.re.match(l,
                        [=[^((local )?function|repeat|while)\b]=], "jio")
                    and not ngx.re.match(l, [=[\bend\s*[\),;]*$]=], "jio")

            -- only open on 'then' if there is no 'elseif'
            open_level_flag = open_level_flag
                or ngx.re.match(l, [=[\b(then|do)$]=], "jio")
                and ngx.re.match(l, [=[^elseif\b]=], "jio")

            -- only open on 'if' if there is no 'end' at the end
            open_level_flag = open_level_flag
                or ngx.re.match(l, [[^if\b]], "jio")
                and ngx.re.match(l, [[\bthen\b]], "jio")
                and not ngx.re.match(l, [[\bend$]], "jio")

            open_level_flag = open_level_flag
                or ngx.re.match(l, [=[\bfunction\s*\([^\)]*\)$]=], "jio")

            open_level_flag = open_level_flag
                or ngx.re.match(l, [[\bdo\b]], "jio")
                and not ngx.re.match(l, [[\bend$]], "jio")
        end

        -- close the level; change both current and next indentation
        local close_level_flag
        do
            close_level_flag = ngx.re.match(l, [[^until\b]], "jio")

            close_level_flag = close_level_flag
                or ngx.re.match(l, [=[^end\s*[\),;]*$]=], "jio")

            -- this is a special case of 'end).."some string"'
            close_level_flag = close_level_flag
                or ngx.re.match(l, [=[^end\s*\)\s*\.\.]=], "jio")

            close_level_flag = close_level_flag
                or ngx.re.match(l, [=[^else(if)?\b/ && /\bend$]=], "jio")
        end

        -- keep the level; decrease the current indentation; keep the next one
        local keep_level_flag
        do
            keep_level_flag = ngx.re.match(l, [[^else\b]], "jio")
                or ngx.re.match(l, [[^elseif\b]], "jio")
        end

        if open_level_flag then
            nextIndent = currIndent + 1
        elseif close_level_flag then
            currIndent = currIndent - 1
            nextIndent = currIndent
        elseif keep_level_flag then
            nextIndent = currIndent
            currIndent = currIndent - 1
        end

        -- capture unbalanced brackets
        local brackets
        do
            local lb, rb
            l, lb = y(l, [[\(]], "")
            l, rb = y(l, [[\)]], "")
            brackets = lb - rb
        end
        -- capture unbalanced curly brackets
        local curly
        do
            local lc, rc
            l, lc = y(l, [[\{]], "")
            l, rc = y(l, [[\}]], "")
            curly = lc - rc
        end

        -- close (curly) brackets if needed
        if curly < 0 and ngx.re.match(l, [[^\}]], "jo") then
            currIndent = currIndent + curly
        end
        if brackets < 0 and ngx.re.match(l, [[^\)]], "jo") then
            currIndent = currIndent + brackets
        end

        if currIndent < 0 then
            if print_flag then
                ngx.log(ngx.ERR, "WARNING: negative indentation at line ",
                    ix, ": ", orig_l, " `", currIndent, "`")
            else
                warning_len = warning_len + 1
                warning[warning_len] = table.concat{
                    "WARNING: negative indentation at line ",
                    ix, ": ", orig_l, " `", currIndent, "`"
                }
            end
        end

        -- this is to collapse empty lines
        if prevLength > 0 or #orig_l > 0 then
            local indent = ""

            if #orig_l > 0 then
                indent = string.rep(INDENT, currIndent)
            end

            if print_flag then
                ngx.print(table.concat{indent, orig_l, "\n"})
            else
                tidycode_len = tidycode_len + 1
                tidycode[tidycode_len] = table.concat{indent, orig_l, "\n"}
            end
        end

        nextIndent = nextIndent + brackets + curly
        currIndent = nextIndent
        prevLength = #orig_l

        ltbl = code_by_line()
    end

    if nextIndent > 0 then
        if print_flag then
            ngx.log(ngx.ERR, "WARNING: positive indentation at the end")
        else
            warning_len = warning_len + 1
            warning[warning_len] = "WARNING: positive indentation at the end"
        end
    end

    return table.concat(tidycode, "\n"), table.concat(warning, "\n")
end

_M.pretty = pretty

-- call from command line
do
    -- When called from the command line, debug.getinfo(3).name is nil
    if not debug.getinfo(3).name then
        local narg = #arg
        local filename = arg[1]
        local fh = io.open(filename, "r")
        io.input(fh)
        local code = io.read("*a")
        pretty(code, true)
    end
end

return _M
