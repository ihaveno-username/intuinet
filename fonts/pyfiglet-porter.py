import string
import sys

import pyfiglet

font_name = sys.argv[1] if len(sys.argv) > 1 else "ansi_shadow"
output_file = sys.argv[2] if len(sys.argv) > 2 else "font.lua"

fig = pyfiglet.Figlet(font=font_name)
font_obj = pyfiglet.FigletFont(font=font_name)  # instantiate, not loadFont
supported_chars = font_obj.chars  # dict of char_code (int) -> list of strings


def get_glyph(c):
    lines = fig.renderText(c).split("\n")
    while lines and not lines[-1].strip():
        lines.pop()
    if not lines:
        return None
    maxw = max(len(l) for l in lines)
    return [l.ljust(maxw) for l in lines]


def entry(c, lines):
    esc = c.replace("\\", "\\\\").replace('"', '\\"')
    rows = ",\n        ".join(f'"{l}"' for l in lines)
    return f'    ["{esc}"] = {{\n        {rows}\n    }},'


out = ["return {"]
for code in sorted(supported_chars.keys()):
    char = chr(code)
    glyph = get_glyph(char)
    if glyph:
        out.append(f"    -- U+{code:04X} ({char})")
        out.append(entry(char, glyph))
        out.append("")
out.append("}")

with open(output_file, "w") as f:
    f.write("\n".join(out))

print(f"written to {output_file}")
