-- lutui.lua

local lutui = {}

lutui._afterprints = {}

function lutui.afterprint(txt)
    table.insert(lutui._afterprints, txt)
end

function lutui._flush_afterprints()
    for _, line in ipairs(lutui._afterprints) do
        print("AFTERPRINT - " .. line)
    end
end

function lutui.readbyte(n)
    n = n or 1
    return io.read(n)
end

function lutui.parse_mouse()
    local b2 = lutui.readbyte()
    if b2 ~= "[" then return nil end
    local b3 = lutui.readbyte()
    if b3 ~= "<" then
        -- might be arrow keys instead
        local type_map = {
            ["A"] = "arrowup",
            ["B"] = "arrowdown",
            ["C"] = "arrowright",
            ["D"] = "arrowleft",
        }

        local type = type_map[b3] or "arrowunknown"

        return { type = type, x = 0, y = 0 }
    end

    local seq = ""
    while true do
        local c = lutui.readbyte()
        seq = seq .. c
        if c == "M" or c == "m" then break end
    end

    local Cb, Cx, Cy = seq:match("^(%d+);(%d+);(%d+)[Mm]")
    Cb, Cx, Cy = tonumber(Cb), tonumber(Cx), tonumber(Cy)
    if not Cb or not Cx or not Cy then return nil end

    local type_map = {
        [0] = "left",
        [1] = "middle",
        [2] = "right",
        [32] = "leftmove",
        [33] = "middlemove",
        [34] = "rightmove",
        [35] = "move",
        [64] = "up",
        [65] = "down",
    }
    local button_type = type_map[Cb] or ("unknown: " .. Cb)
    local action = seq:sub(-1) == "M" and "press" or "release"

    return { type = button_type, x = Cx, y = Cy, action = action }
end

function lutui.decolor(str)
    return (str:gsub("\27%[[0-9;]*m", ""))
end

function lutui.getSize()
    -- 1) try environment (quick but may be stale)
    local cols = tonumber(os.getenv("COLUMNS"))
    local rows = tonumber(os.getenv("LINES"))
    if cols and rows then return cols, rows end

    -- 2) try `stty size` (POSIX)
    local fh = io.popen("stty size 2>/dev/null")
    if fh then
        local out = fh:read("*a")
        fh:close()
        if out and out:match("%d+%s+%d+") then
            local r, c = out:match("(%d+)%s+(%d+)")
            r = tonumber(r); c = tonumber(c)
            if r and c then return c, r end -- stty prints "rows cols"
        end
    end

    -- last fallback: reasonable defaults
    return 80, 24
end

function lutui.pad_text(txt, padding, dir, pad_char)
    pad_char = pad_char or " "
    dir = dir or "L"

    if not txt then return "" end
    if not padding then return txt end

    local txt_len = #lutui.decolor(txt)
    local pad_amount = math.max(0, padding - txt_len)

    if dir == "L" then
        return string.rep(pad_char, pad_amount) .. txt
    elseif dir == "R" then
        return txt .. string.rep(pad_char, pad_amount)
    else
        return txt -- fallback for invalid direction
    end
end

function lutui.text_wrap(text, x, term_width, config)
    config = config or {}
    config.pre = config.pre or ""
    config.suf = config.suf or ""

    local start_col = x or 1 -- 1-indexed column where printing will start
    local maxcols = term_width or 80

    -- available columns for the whole printed string (including pre/suf)
    local avail = maxcols - (start_col - 1)
    if avail <= 0 then avail = 1 end -- avoid zero/negative available width

    -- fast path: whole thing fits
    local full_stripped = lutui.decolor(config.pre .. text .. config.suf)
    if #full_stripped <= avail then
        return { config.pre .. text .. config.suf }
    end

    local lines = {}
    local cur = ""

    for word in text:gmatch("%S+") do
        local candidate = (cur == "" and word or (cur .. " " .. word))
        local cand_len = #lutui.decolor(config.pre .. candidate .. config.suf)

        if cand_len <= avail then
            cur = candidate
        else
            if cur == "" then
                -- single word longer than avail -> break it into chunks (byte-wise)
                local remaining = word
                -- compute header/footer stripped lengths once
                local pre_len = #lutui.decolor(config.pre)
                local suf_len = #lutui.decolor(config.suf)
                local chunk_capacity = avail - pre_len - suf_len
                if chunk_capacity < 1 then chunk_capacity = 1 end

                while #lutui.decolor(config.pre .. remaining .. config.suf) > avail do
                    local chunk = remaining:sub(1, chunk_capacity)
                    table.insert(lines, config.pre .. chunk .. config.suf)
                    remaining = remaining:sub(chunk_capacity + 1)
                end

                cur = remaining
            else
                table.insert(lines, config.pre .. cur .. config.suf)
                cur = word
            end
        end
    end

    if cur ~= "" then
        table.insert(lines, config.pre .. cur .. config.suf)
    end

    return lines
end

return lutui
