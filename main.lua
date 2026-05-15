local tml = require("tml")
local lutui = require("lutui")
local page = tml.parseFile("main.tml")
local scroll_y = -1
local term = require("term")

local M = {}
local command_mode = false
local command = {}

function M.init()
    termw, termh = lutui.getSize()
end

function M.draw()
    for i = 0, termh - 1 do
        term.cursor.jump(i, 0)
        local line = page[scroll_y + i]
        if line then
            io.write(line)
        end
    end
    if command_mode then
        term.cursor.jump(termh - 1, 0)
        local line = ":" .. table.concat(command, "")
        io.write(term.colors.black .. term.colors.onwhite(line .. string.rep(" ", (termw - #line))) .. term.colors.reset)
    end
end

function M.runCommand(input)
    local parts = {}
    for word in input:gmatch("%S+") do
        table.insert(parts, word)
    end
    local cmd = parts[1]
    if cmd == "open" then
        local target = parts[3]
        if parts[2] == "local" and target then
            local ok, result = pcall(tml.parseFile, target)
            if ok then
                page = result
                scroll_y = -1
            else
                -- error already printed by crash handler
            end
        end
    end
end

-- i dont know how to optimize code.
function M.update()
    local k = io.read(1)
    if command_mode then
        if (k:byte() == 27) then
            local next = io.read(1)
            if next == nil or next == "" then
                command = {}
                command_mode = false
            elseif next == "[" then
                local arrow = io.read(1)
                if arrow == "A" then     -- up
                    scroll_y = scroll_y - 1
                elseif arrow == "B" then -- down
                    scroll_y = scroll_y + 1
                else
                    -- unknown escape sequence (mouse, etc)
                    -- consume bytes until we hit a letter which ends the sequence
                    local b = arrow
                    while b and not b:match("%a") do
                        b = io.read(1)
                    end
                end
            end
        elseif k:byte() == 127 or k:byte() == 8 then
            command[#command] = nil
        elseif k == "\r" then
            command_mode = false
            M.runCommand(table.concat(command, ""))
        elseif k == "`" then
            command = {}
            command_mode = false
        else
            command[#command + 1] = k
        end
    else
        if k == "w" then
            scroll_y = scroll_y - 1 -- math.max(1, scroll_y - 1)
        elseif k == "s" then
            scroll_y = scroll_y + 1 -- math.min(#page, scroll_y + 1)
        elseif k == ":" then
            command_mode = true
        elseif k == "q" then
            return false -- exit
        end
    end
end

return M
