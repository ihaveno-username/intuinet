-- runner.lua

local lutui = require("lutui")

local function cleanup_and_exit()
    -- disable mouse reporting and restore terminal and cursor
    io.write("\27[?25h")
    io.write("\27[?1000l")
    io.write("\27[?1006l")
    io.write("\27[?1003l") -- disable mouse motion events
    io.flush()
    os.execute("stty sane")
end

local _arg_singleton = require("args")

local arg = _arg_singleton.get()

-- enable raw mode
os.execute("stty raw -echo")

-- enable mouse reporting
io.write("\27[?1000h")
io.write("\27[?1006h")
io.write("\27[?1003h") -- optional: mouse]()

-- turn off cursor
io.write("\27[?25l")
io.flush()


local user_file = _TARGET_FILE or "main.lua"
local m = dofile(user_file)

if m.args then
    local marg = {}
    for i = 2, #arg do
        table.insert(marg, arg[i])
    end
    m.args(marg)
end

-- rendering/update loop

local function clear(handle)
    handle = handle and ((io.type(handle) == 'file') and handle or io.stdout) or io.stdout
    return handle:write('\27[2J')
end

local function main_loop()
    m.init()
    local running = true
    while running do
        clear()
        m.draw()

        local out = m.update()
        if out == false then
            break
        elseif out == "resize" then
            local termw, termh = lutui.getSize()
            m.resize(termw, termh)
        end
    end
end

local success, err = xpcall(main_loop, debug.traceback)

if not success then
    cleanup_and_exit()
    local crash_file = io.open("crash.txt", "w")
    if crash_file then
        crash_file:write("Runner crashed with error:\n")
        crash_file:write(tostring(err) .. "\n")
        crash_file:close()
        print("Crash logged to crash.txt")
    else
        print("ERROR! | " .. tostring(err))
    end
    print("Exited with error")
    os.exit(1)
end

cleanup_and_exit()

lutui._flush_afterprints()


print("Exited cleanly")
