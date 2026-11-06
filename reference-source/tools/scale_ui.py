#!/usr/bin/env python3
"""One-shot helper used for the 640x360 re-base: scales the pixel literals of UI scripts by 2/3 (the 960x540 -> 640x360 ratio).
Handles Vector2/Vector2i/Rect2/Rect2i(...) arguments, theme constants, offsets / size / position assignments, UITheme.icon sizes and
outline widths. Literals < 3 are left alone (fractions, 1-2 px details are reviewed by hand). Not needed after the re-base; kept for reference.
Usage: python3 tools/scale_ui.py file.gd [...]"""
import re, sys
K = 2.0 / 3.0
NUM = re.compile(r"(?<![\w.])(\d+\.\d+|\d+)(?![\w])")

def sc(tok):
    v = float(tok)
    if v < 3.0:
        return tok
    r = max(2, int(v * K + 0.5))
    return ("%d.0" % r) if "." in tok else str(r)

def scale_args(txt):
    return NUM.sub(lambda m: sc(m.group(1)), txt)

def convert(src):
    out = []
    i = 0
    pat = re.compile(r"\b(Vector2i|Vector2|Rect2i|Rect2)\(")
    while i < len(src):
        m = pat.search(src, i)
        if not m:
            out.append(src[i:])
            break
        out.append(src[i:m.end()])
        j = m.end()
        depth = 1
        k = j
        while k < len(src) and depth:
            if src[k] == "(":
                depth += 1
            elif src[k] == ")":
                depth -= 1
            k += 1
        inner = src[j:k - 1]
        # nested constructors are handled by the recursion below: scale this level's plain text, recurse into the rest
        out.append(convert(inner))
        out.append(")")
        i = k
        # numbers directly inside (not in nested ctor) are scaled by the recursive call only if they were in a ctor; do it here for the level
    res = "".join(out)
    return res

def level_scale(src):
    """scale literals inside every ctor (nested ones once): process innermost-first by scanning ctor spans on the original text."""
    spans = []
    pat = re.compile(r"\b(Vector2i|Vector2|Rect2i|Rect2)\(")
    for m in pat.finditer(src):
        j = m.end(); depth = 1; k = j
        while k < len(src) and depth:
            if src[k] == "(":
                depth += 1
            elif src[k] == ")":
                depth -= 1
            k += 1
        spans.append((j, k - 1))
    mark = [False] * len(src)
    for a, b in spans:
        for x in range(a, b):
            mark[x] = True
    out = []
    pos = 0
    for m in NUM.finditer(src):
        s, e = m.span(1)
        if mark[s]:
            out.append(src[pos:s]); out.append(sc(m.group(1))); pos = e
    out.append(src[pos:])
    return "".join(out)

def other(src):
    src = re.sub(r'(add_theme_constant_override\("(?:separation|h_separation|v_separation|margin_\w+)",\s*)(-?\d+)(\))', lambda m: m.group(1) + (str(max(1, int(int(m.group(2)) * K + 0.5))) if int(m.group(2)) > 0 else m.group(2)) + m.group(3), src)
    src = re.sub(r'(\b(?:offset_left|offset_right|offset_top|offset_bottom|texture_margin_\w+|content_margin_\w+)\s*[+-]?=\s*)(-?\d+(?:\.\d+)?)', lambda m: m.group(1) + sc(m.group(2).lstrip("-")) if not m.group(2).startswith("-") else m.group(1) + "-" + sc(m.group(2)[1:]), src)
    src = re.sub(r'(\b(?:custom_minimum_size|size|position)\.[xy]\s*[+-]?=\s*)(\d+(?:\.\d+)?)', lambda m: m.group(1) + sc(m.group(2)), src)
    src = re.sub(r'(UITheme\.icon\([^,()]+,\s*)(\d+)(\))', lambda m: m.group(1) + sc(m.group(2)) + m.group(3), src)
    src = re.sub(r'(, false, )(\d+(?:\.\d+)?)(\))', lambda m: m.group(1) + ("%.1f" % max(1.0, round(float(m.group(2)) * 0.5))) + m.group(3), src)
    return src

if __name__ == "__main__":
    for f in sys.argv[1:]:
        s = open(f).read()
        s2 = other(level_scale(s))
        open(f, "w").write(s2)
        print(f, "changed" if s2 != s else "same")
