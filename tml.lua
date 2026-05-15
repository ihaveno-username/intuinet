local tml = {}
local font = require("font")

-- first time im actually USING comments in a lua file
-- i genually for hte life of me cannot read my own code anymore
-- even if its "clean"

-- TML Pipeline:
-- 1. Read file > lines
-- 2. Tokenize lines into text / <tags>
-- 3. Scaffold into a node tree (stack-based)
-- 4. Flatten tree into ANSI output
-- 5. Special cases: <h>, <fg>, <bg>
-- why the fuck is html and tml parsing so damn complicated


local getfile = function(filepath)
    local file = io.open(filepath, "r")
    if not file then
        error("Could not open file: " .. tostring(filepath))
    end

    local content = {}

    for line in file:lines() do
        table.insert(content, line)
    end

    file:close()

    return content
end

-- ==================
--  Line Tokenizer
-- ==================

local replacements = {
    ["&#SLASH;"] = "/",
    ["&#BSLASH;"] = "\\",
    ["&#GT;"] = ">",
    ["&#LT;"] = "<",
    ["&#AMP;"] = "&",
}

local tokenizeLine = function(line)
    local tokens = {}
    local pos = 1
    local inRaw = false -- track if we're inside <raw>…</raw>

    while pos <= #line do
        if not inRaw then
            -- normal tag search
            local startTag, endTag = line:find("<[^>]+>", pos)
            if startTag then
                local tagText = line:sub(startTag, endTag)

                -- check if this is a <raw> tag
                if tagText == "<raw>" then
                    -- push preceding text first
                    if startTag > pos then
                        local text = line:sub(pos, startTag - 1)
                        if text ~= "" then
                            table.insert(tokens, text)
                        end
                    end
                    table.insert(tokens, "<raw>") -- include the tag itself
                    pos = endTag + 1
                    inRaw = true
                else
                    -- add text before tag if any
                    if startTag > pos then
                        local text = line:sub(pos, startTag - 1)
                        if text ~= "" then
                            table.insert(tokens, text)
                        end
                    end
                    -- add the tag
                    table.insert(tokens, tagText)
                    pos = endTag + 1
                end
            else
                -- no more tags, add remaining text
                local text = line:sub(pos)
                if text ~= "" then
                    table.insert(tokens, text)
                end
                break
            end
        else
            -- inside <raw>, look for closing </raw>
            local rawEnd = line:find("</raw>", pos)
            if rawEnd then
                -- everything up to </raw> is literal
                local text = line:sub(pos, rawEnd - 1)
                if text ~= "" then
                    table.insert(tokens, text)
                end
                table.insert(tokens, "</raw>")
                pos = rawEnd + 6 -- length of </raw>
                inRaw = false
            else
                -- rest of line is literal
                local text = line:sub(pos)
                if text ~= "" then
                    table.insert(tokens, text)
                end
                break
            end
        end
    end

    for i, _ in ipairs(tokens) do
        for orig, repl in pairs(replacements) do
            tokens[i] = tokens[i]:gsub(orig, repl)
        end
    end

    return tokens
end


-- ==================
--  Tag Entries
-- ==================

tml.opentags = {
    "<h>",
    "<p>",
}

tml.closetags = {}

for _, tag in ipairs(tml.opentags) do
    table.insert(tml.closetags, "</" .. tag:sub(2, #tag))
end

for _, tag in ipairs({
    "<bold>",
    "<ital>",
    "<under>",
    "<strike>",
}) do
    table.insert(tml.opentags, tag)
end

local function seq_truecolor(vars, bg)
    local col = vars.col:gsub("#", "") -- remove # if present

    -- error message shit
    if not vars then error("ERROR | vars for '" .. (bg and "bg" or "fg") .. "' does not exist.") end
    if not vars.col then error("ERROR | color variable for '" .. (bg and "bg" or "fg") .. "' does not exist.") end
    if #vars.col ~= 6 then
        error("ERROR | color var for '" ..
            (bg and "bg" or "fg") .. "' is shorter than 6/not a hex value.")
    end
    -- turn to decimal
    local r = math.max(0, math.min(255, tonumber(col:sub(1, 2), 16)))
    local g = math.max(0, math.min(255, tonumber(col:sub(3, 4), 16)))
    local b = math.max(0, math.min(255, tonumber(col:sub(5, 6), 16)))

    return string.format("\27[%d;2;%d;%d;%dm", bg and 48 or 38, r, g, b)
end

tml.specialtags = {
    ["fg"] = { id = "fg", vars = { "col" }, code = function(vars) return seq_truecolor(vars, false) end },
    ["bg"] = { id = "bg", vars = { "col" }, code = function(vars) return seq_truecolor(vars, true) end },
}

-- ==================
--  Helpers
-- ==================

local function parse_tag_token(tok)
    if not tok:match("^<[^>]+>$") then return nil end
    local is_close = tok:match("^</")
    local inner = tok:sub(2, -2)              -- strip < >
    if is_close then inner = inner:sub(2) end -- strip leading /

    -- split name and attr-string at first semicolon
    local name, attrstr = inner:match("^([^;]+);?(.*)$")
    local attrs = {}
    local valid = true
    local missing = nil
    for pair in attrstr:gmatch("([^;]+)") do
        local k, v = pair:match("^(%w+)=([%w#]+)$")
        if not k or not v then
            valid = false
            missing = (not k) and "key" or ((not v) and "value" or "both key and value")
            break
        end
        attrs[k] = v
    end
    if not valid then
        error(missing .. " is missing from tok: " .. name)
    end

    return is_close, name, attrs
end

-- ====================================
--  TML Tree-ify-er thing/Scaffolder
-- ====================================

tml.scaffoldFile = function(filepath)
    local content = getfile(filepath)
    local stack = {}
    local processed = {}

    local function push_node(name, vars)
        local node = { id = name, content = {} }
        if vars and next(vars) then node.vars = vars end
        table.insert(stack, node)
    end

    local function pop_node(expected_name)
        local node = table.remove(stack)
        if not node then return end

        -- optional safety: if expected_name provided, try to find matching ancestor
        if expected_name and node.id ~= expected_name then
            -- find matching ancestor
            local found = false
            local tmp = { node }
            while #stack > 0 do
                local top = table.remove(stack)
                table.insert(tmp, 1, top)
                if top.id == expected_name then
                    found = true
                    break
                end
            end
            -- re-attach everything popped in tmp in order
            for _, n in ipairs(tmp) do
                if #stack > 0 then
                    table.insert(stack[#stack].content, n)
                else
                    table.insert(processed, n)
                end
            end
            return
        end

        if #stack > 0 then
            table.insert(stack[#stack].content, node)
        else
            table.insert(processed, node)
        end
    end

    local function add_text(text)
        if #stack > 0 then
            table.insert(stack[#stack].content, text)
        else
            table.insert(processed, text)
        end
    end

    for _, line in ipairs(content) do
        for _, tok in ipairs(tokenizeLine(line)) do
            local is_tag = tok:match("^<[^>]+>$")
            if not is_tag then
                add_text(tok)
            else
                local is_close, name, attrs = parse_tag_token(tok)
                if not is_close then
                    -- opening tag: push and attach attrs to node
                    push_node(name, attrs)
                else
                    -- closing tag: pop; try to match the name if possible
                    pop_node(name)
                end
            end
        end
    end

    -- flush unclosed nodes
    while #stack > 0 do
        pop_node()
    end

    return processed
end

-- ====================================
--  ANSI Codes & Truecolor
-- ====================================

local ANSI = {
    bold   = "\27[1m",
    ital   = "\27[3m",
    under  = "\27[4m",
    strike = "\27[9m",
    reset  = "\27[0m",
}

local function ansi(id, vars)
    if tml.specialtags[id] then
        local entry = tml.specialtags[id]
        return entry.code(vars)
    else
        return ANSI[id]
    end
end

-- ==================
--  File Parser
-- ==================

tml.parseFile = function(filepath)
    local scaffold = tml.scaffoldFile(filepath)
    if not scaffold then return {} end

    -- collect raw text (no ANSI) from a node subtree (used for <h>)
    local function raw_text(node)
        if type(node) == "string" then
            return node
        end
        local s = ""
        local has_col = (node.id == "fg" and "fg" or (node.id == "bg" and "bg" or false))
        has_col = has_col and { id = has_col, vars = node.vars } or nil
        local nested_has_col = nil
        for _, child in ipairs(node.content or {}) do
            local raw_text_child, temp = raw_text(child)
            if temp then
                nested_has_col = temp
            end
            s = s .. raw_text_child
        end
        return s, (has_col or nested_has_col)
    end

    -- flatten a node subtree into a string (or for <h> returns table of lines)
    -- active: array of active ANSI codes (outer-to-inner)
    local function flatten(node, active)
        active = active or {}

        if type(node) == "string" then
            return node
        end

        -- special-case header: build raw text and pass to font.header
        if node.id == "h" then
            local text, has_col = raw_text(node)
            local header = font.header(text or "")
            if not has_col then
                return header
            else
                local code = ansi(has_col.id, has_col.vars)
                for i, line in ipairs(header) do
                    header[i] = code .. line .. ANSI.reset
                end
                return header
            end
        end

        local code = ansi(node.id, node.vars) -- nil for non-modifier tags like <p>, <div>
        -- build new active list (outer ... inner)
        local new_active = {}
        for i = 1, #active do new_active[i] = active[i] end
        if code then table.insert(new_active, code) end

        -- inside flatten
        local buf = {} -- buffer for pieces
        local insert = table.insert
        for _, child in ipairs(node.content or {}) do
            local child_flat, child_active = flatten(child, new_active)
            if type(child_flat) == "table" then
                -- if child is header/table, append its lines without inserting extra newlines unless you want them
                for _, line in ipairs(child_flat) do insert(buf, line) end
            else
                insert(buf, child_flat or "")
            end
            new_active = child_active or new_active
        end
        local inner = table.concat(buf, "")

        if code then
            -- close: reset everything, then reapply parent's active codes
            local reapply = (#active > 0) and table.concat(active) or ""
            return code .. inner .. ANSI.reset .. reapply
        else
            return inner
        end
    end

    -- top-level: flatten scaffolded nodes into an array of lines (strings)
    local out = {}
    for _, entry in ipairs(scaffold) do
        local flat = flatten(entry, {})
        if type(flat) == "table" then
            -- header -> multiple lines
            for _, ln in ipairs(flat) do table.insert(out, ln) end
        else
            table.insert(out, flat or "")
        end
    end

    return out
end

return tml
