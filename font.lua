local font = require("fonts.h")

local function getGlyph(char)
    local upperChar = char:upper()
    if font[char] then
        return font[char]
    elseif font[upperChar] then
        return font[upperChar]
    else
        return {
            " ",
            " ",
            " ",
            char,
        }
    end
end

local function header(text)
    if not text or text == "" then
        return {}
    end

    -- figure out actual glyph height dynamically
    local height = 0
    for i = 1, #text do
        local glyph = getGlyph(text:sub(i, i))
        if #glyph > height then height = #glyph end
    end

    local lines = {}
    for i = 1, height do lines[i] = "" end

    for i = 1, #text do
        local char = text:sub(i, i)
        local glyph = getGlyph(char)
        for line = 1, height do
            lines[line] = lines[line] .. (glyph[line] or string.rep(" ", #glyph[1]))
        end
        if i < #text then
            for line = 1, height do
                lines[line] = lines[line] .. (font.spacing[line] or " ")
            end
        end
    end

    return lines
end

return {
    header = header,
    font = font
}
