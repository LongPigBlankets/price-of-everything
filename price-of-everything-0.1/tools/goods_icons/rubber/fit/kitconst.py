"""Read a dict/list constant out of rubber_kit.py without importing it (the kit needs Blender)."""
import ast, re
def const(name, path='source/rubber_kit.py'):
    s = open(path).read(); i = s.index(name + ' = ') + len(name + ' = '); open_ = s[i]; close = {'{': '}', '[': ']', '(': ')'}[open_]
    depth = 0; j = i
    while True:
        c = s[j]
        if c == open_: depth += 1
        elif c == close:
            depth -= 1
            if depth == 0: break
        j += 1
    txt = '\n'.join(l.split('#')[0] for l in s[i:j + 1].split('\n'))
    return ast.literal_eval(txt)
