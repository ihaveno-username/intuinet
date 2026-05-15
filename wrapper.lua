-- wrapper.lua
local filename = "runner.lua"

local function log_error(err)
    local f = io.open("crash.txt", "a")
    if f then
        f:write(os.date("%Y-%m-%d %H:%M:%S") .. " - " .. debug.traceback(err) .. "\n")
        f:close()
    end
end

local function cleanup_and_exit()
    -- disable mouse reporting and restore terminal and cursor
    io.write("\27[?25h")
    io.write("\27[?1000l")
    io.write("\27[?1006l")
    io.write("\27[?1003l") -- disable mouse motion events
    io.flush()
    os.execute("stty sane")
end

-- try to load the file
local func, load_err = loadfile(filename)
if not func then
    log_error(load_err)
    print("Failed to load file:", load_err)
    os.exit(1)
end

-- run the file safely
xpcall(func, log_error)

cleanup_and_exit()
