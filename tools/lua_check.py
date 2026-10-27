#!/usr/bin/env python3
"""Offline syntax check of the G-SA1 Lua addon (no Lua needed): a Lua 5.1 recursive-descent parser.

    py -3.12 tools/lua_check.py [files...]        (default: every addon/lua/**/*.lua)

Reports syntax errors with line numbers, and assignments to global names that are not in ALLOWED_GLOBALS
(accidental globals). Plain Lua 5.1 only: GLua's C-style extensions (!=, &&, ||, //, /* */, continue) are
rejected on purpose, so the addon also parses as standard Lua.

Feature files (G0, sadc docs/research/gsa1_rounds_plan.md section 5): addon/lua/gsa1/feat/ holds only files the
autorun loads - sh_<feature>.lua, cl_<feature>.lua, sv_<feature>.lua (lower case, no subdirectories) - and they get
no globals of their own either: a feature's state goes into GSA1 (GSA1.ConVar, GSA1.AddMenuPage, GSA1.HasFeature).
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ALLOWED_GLOBALS = {"GSA1"}

KEYWORDS = {"and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in", "local", "nil",
            "not", "or", "repeat", "return", "then", "true", "until", "while"}
OPS = ["...", "..", "==", "~=", "<=", ">=", "+", "-", "*", "/", "%", "^", "#", "<", ">", "=", "(", ")", "{", "}",
       "[", "]", ";", ":", ",", "."]
BINPRI = {"or": (1, 1), "and": (2, 2), "<": (3, 3), ">": (3, 3), "<=": (3, 3), ">=": (3, 3), "~=": (3, 3),
          "==": (3, 3), "..": (5, 4), "+": (6, 6), "-": (6, 6), "*": (7, 7), "/": (7, 7), "%": (7, 7), "^": (10, 9)}
UNARY_PRI = 8


class LuaError(Exception):
    pass


def tokenize(src):
    toks = []
    i, line, n = 0, 1, len(src)
    while i < n:
        c = src[i]
        if c == "\n":
            line += 1
            i += 1
            continue
        if c in " \t\r\f\v":
            i += 1
            continue
        if src.startswith("--", i):
            m = re.match(r"--\[(=*)\[", src[i:])
            if m:
                close = "]" + m.group(1) + "]"
                j = src.find(close, i + len(m.group(0)))
                if j < 0:
                    raise LuaError("line %d: unfinished long comment" % line)
                line += src.count("\n", i, j)
                i = j + len(close)
            else:
                j = src.find("\n", i)
                i = n if j < 0 else j
            continue
        m = re.match(r"\[(=*)\[", src[i:])
        if m:
            close = "]" + m.group(1) + "]"
            j = src.find(close, i + len(m.group(0)))
            if j < 0:
                raise LuaError("line %d: unfinished long string" % line)
            toks.append(("str", src[i:j + len(close)], line))
            line += src.count("\n", i, j)
            i = j + len(close)
            continue
        if c in "\"'":
            j = i + 1
            while j < n and src[j] != c:
                if src[j] == "\\":
                    # escapes LuaJIT accepts: a b f n r t v, backslash, quotes, newline, decimal, x, z, u
                    e = src[j + 1] if j + 1 < n else ''
                    if not (e in 'abfnrtvxzu"' + chr(39) + chr(92) + chr(10) or e.isdigit()):
                        raise LuaError('line %d: invalid escape sequence ' % line + chr(92) + e)
                    j += 1
                elif src[j] == "\n":
                    raise LuaError("line %d: unfinished string" % line)
                j += 1
            if j >= n:
                raise LuaError("line %d: unfinished string" % line)
            toks.append(("str", src[i:j + 1], line))
            i = j + 1
            continue
        m = re.match(r"0[xX][0-9a-fA-F]+|(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?", src[i:])
        if m and m.group(0):
            toks.append(("num", m.group(0), line))
            i += len(m.group(0))
            continue
        m = re.match(r"[A-Za-z_][A-Za-z0-9_]*", src[i:])
        if m:
            w = m.group(0)
            toks.append(("kw" if w in KEYWORDS else "name", w, line))
            i += len(w)
            continue
        for op in OPS:
            if src.startswith(op, i):
                toks.append(("op", op, line))
                i += len(op)
                break
        else:
            raise LuaError("line %d: unexpected character %r" % (line, c))
    toks.append(("eof", "<eof>", line))
    return toks


class Parser:
    def __init__(self, toks):
        self.t = toks
        self.i = 0
        self.scopes = [set()]
        self.global_writes = []
        self.global_reads = set()

    # -- tokens
    def peek(self, k=0):
        return self.t[self.i + k]

    def check(self, v):
        tok = self.peek()
        return tok[1] == v and tok[0] in ("op", "kw")

    def accept(self, v):
        if self.check(v):
            self.i += 1
            return True
        return False

    def expect(self, v, what=None):
        if not self.accept(v):
            tok = self.peek()
            raise LuaError("line %d: '%s' expected%s near '%s'" % (tok[2], v, (" (" + what + ")") if what else "", tok[1]))

    def name(self):
        tok = self.peek()
        if tok[0] != "name":
            raise LuaError("line %d: name expected near '%s'" % (tok[2], tok[1]))
        self.i += 1
        return tok[1]

    # -- scopes
    def declare(self, n):
        self.scopes[-1].add(n)

    def is_local(self, n):
        return any(n in s for s in self.scopes)

    # -- grammar
    def chunk(self):
        self.block()
        if self.peek()[0] != "eof":
            tok = self.peek()
            raise LuaError("line %d: '<eof>' expected near '%s'" % (tok[2], tok[1]))

    def block_follow(self):
        tok = self.peek()
        return tok[0] == "eof" or (tok[0] == "kw" and tok[1] in ("else", "elseif", "end", "until"))

    def block(self):
        while not self.block_follow():
            if self.check("return"):
                self.i += 1
                if not self.block_follow() and not self.check(";"):
                    self.explist()
                self.accept(";")
                if not self.block_follow():
                    tok = self.peek()
                    raise LuaError("line %d: 'return' must be the last statement (near '%s')" % (tok[2], tok[1]))
                return
            if self.check("break"):
                self.i += 1
                self.accept(";")
                if not self.block_follow():
                    tok = self.peek()
                    raise LuaError("line %d: 'break' must be the last statement (near '%s')" % (tok[2], tok[1]))
                return
            self.statement()
            self.accept(";")

    def scoped_block(self, names=()):
        self.scopes.append(set(names))
        self.block()
        self.scopes.pop()

    def statement(self):
        tok = self.peek()
        if self.accept("if"):
            self.expr()
            self.expect("then")
            self.scoped_block()
            while self.accept("elseif"):
                self.expr()
                self.expect("then")
                self.scoped_block()
            if self.accept("else"):
                self.scoped_block()
            self.expect("end", "to close 'if' at line %d" % tok[2])
        elif self.accept("while"):
            self.expr()
            self.expect("do")
            self.scoped_block()
            self.expect("end", "to close 'while' at line %d" % tok[2])
        elif self.accept("do"):
            self.scoped_block()
            self.expect("end", "to close 'do' at line %d" % tok[2])
        elif self.accept("for"):
            n1 = self.name()
            if self.accept("="):
                self.expr()
                self.expect(",")
                self.expr()
                if self.accept(","):
                    self.expr()
                self.expect("do")
                self.scoped_block([n1])
            else:
                names = [n1]
                while self.accept(","):
                    names.append(self.name())
                self.expect("in")
                self.explist()
                self.expect("do")
                self.scoped_block(names)
            self.expect("end", "to close 'for' at line %d" % tok[2])
        elif self.accept("repeat"):
            self.scopes.append(set())
            self.block()
            self.expect("until", "to close 'repeat' at line %d" % tok[2])
            self.expr()
            self.scopes.pop()
        elif self.accept("function"):
            first = self.name()
            dotted = method = False
            while self.accept("."):
                self.name()
                dotted = True
            if self.accept(":"):
                self.name()
                dotted = method = True
            if not self.is_local(first):
                if dotted:
                    self.global_reads.add(first)                  # function a.b() reads a
                else:
                    self.global_writes.append((first, tok[2]))    # function a() writes the global a
            self.funcbody(method, tok[2])
        elif self.accept("local"):
            if self.accept("function"):
                n = self.name()
                self.declare(n)
                self.funcbody(False, tok[2])
            else:
                names = [self.name()]
                while self.accept(","):
                    names.append(self.name())
                if self.accept("="):
                    self.explist()
                for n in names:
                    self.declare(n)
        else:
            self.expr_statement()

    def expr_statement(self):
        start = self.peek()
        kind, target = self.suffixedexp()
        if self.check("=") or self.check(","):
            targets = [(kind, target)]
            while self.accept(","):
                targets.append(self.suffixedexp())
            self.expect("=")
            self.explist()
            for k, tname in targets:
                if k == "call":
                    raise LuaError("line %d: cannot assign to a function call" % start[2])
                if k == "global":
                    self.global_writes.append((tname, start[2]))
        elif kind != "call":
            raise LuaError("line %d: syntax error near '%s' (a statement must be a call or an assignment)"
                           % (self.peek()[2], self.peek()[1]))

    def funcbody(self, method, line):
        self.expect("(")
        names = ["self"] if method else []
        if not self.check(")"):
            while True:
                if self.accept("..."):
                    names.append("arg")
                    break
                names.append(self.name())
                if not self.accept(","):
                    break
        self.expect(")")
        self.scopes.append(set(names))
        self.block()
        self.scopes.pop()
        self.expect("end", "to close 'function' at line %d" % line)

    def primaryexp(self):
        tok = self.peek()
        if tok[0] == "name":
            self.i += 1
            if self.is_local(tok[1]):
                return "local", tok[1]
            return "global", tok[1]
        if self.accept("("):
            self.expr()
            self.expect(")")
            return "paren", None
        raise LuaError("line %d: unexpected symbol near '%s'" % (tok[2], tok[1]))

    def suffixedexp(self):
        kind, target = self.primaryexp()
        if kind == "global":
            self.global_reads.add(target)
        while True:
            if self.accept("."):
                self.name()
                kind = "field"
            elif self.accept("["):
                self.expr()
                self.expect("]")
                kind = "field"
            elif self.accept(":"):
                self.name()
                self.args()
                kind = "call"
            elif self.check("(") or self.check("{") or self.peek()[0] == "str":
                if self.check("(") and self.peek()[2] != self.t[self.i - 1][2]:
                    raise LuaError("line %d: ambiguous syntax (function call x new statement)" % self.peek()[2])
                self.args()
                kind = "call"
            else:
                return kind, target

    def args(self):
        if self.peek()[0] == "str":
            self.i += 1
        elif self.check("{"):
            self.table()
        else:
            self.expect("(")
            if not self.check(")"):
                self.explist()
            self.expect(")")

    def table(self):
        self.expect("{")
        while not self.check("}"):
            if self.check("["):
                self.i += 1
                self.expr()
                self.expect("]")
                self.expect("=")
                self.expr()
            elif self.peek()[0] == "name" and self.peek(1)[1] == "=" and self.peek(1)[0] == "op":
                self.i += 2
                self.expr()
            else:
                self.expr()
            if not self.accept(",") and not self.accept(";"):
                break
        self.expect("}")

    def simpleexp(self):
        tok = self.peek()
        if tok[0] in ("num", "str"):
            self.i += 1
        elif tok[0] == "kw" and tok[1] in ("nil", "true", "false"):
            self.i += 1
        elif self.accept("..."):
            pass
        elif self.check("{"):
            self.table()
        elif self.accept("function"):
            self.funcbody(False, tok[2])
        else:
            self.suffixedexp()

    def expr(self, limit=0):
        tok = self.peek()
        if (tok[0] == "kw" and tok[1] == "not") or (tok[0] == "op" and tok[1] in ("-", "#")):
            self.i += 1
            self.expr(UNARY_PRI)
        else:
            self.simpleexp()
        while True:
            tok = self.peek()
            op = tok[1] if tok[0] in ("op", "kw") else None
            if op not in BINPRI or BINPRI[op][0] <= limit:
                return
            self.i += 1
            self.expr(BINPRI[op][1])

    def explist(self):
        self.expr()
        while self.accept(","):
            self.expr()


FEAT_DIR = os.path.join(ROOT, "addon", "lua", "gsa1", "feat")
FEAT_NAME = re.compile(r"^(sh|cl|sv)_[a-z0-9_]+\.lua$")


def feature_name_errors():
    """Files in addon/lua/gsa1/feat/ that the autorun would not load (wrong name, a subdirectory, not .lua)."""
    errs = []
    if not os.path.isdir(FEAT_DIR):
        return errs
    for dirpath, dirs, files in os.walk(FEAT_DIR):
        for n in sorted(files):
            try:
                rel = os.path.relpath(os.path.join(dirpath, n), ROOT)
            except ValueError:
                rel = os.path.join(dirpath, n)
            if dirpath != FEAT_DIR:
                errs.append("%s: feature files go directly into addon/lua/gsa1/feat/ (the autorun loads no subdirectory)" % rel)
            elif not FEAT_NAME.match(n):
                errs.append("%s: not a feature file name: sh_<feature>.lua, cl_<feature>.lua or sv_<feature>.lua in "
                            "lower case (the autorun loads only those; Linux servers see case)" % rel)
    return errs


def check_file(path):
    src = open(path, encoding="utf-8").read()
    toks = tokenize(src)
    p = Parser(toks)
    p.chunk()
    bad = [(n, l) for n, l in p.global_writes if n not in ALLOWED_GLOBALS]
    return bad


SELFTEST = [
    ("local p = \"C:\\x\\gsa1\"\n", "invalid escape sequence"),
    ("local x = 1\nif x then print(x) end\n", None),
    ("if x then print(1)\n", "'end' expected"),
    ("local t = { a = 1, [2] = 3, 4; }\nreturn t\n", None),
    ("if a != b then end\n", "unexpected character"),
    ("x = 1\n", "global"),
    ("local function f(...) return ... end\nf(1)(2)\n", None),
    ("local a = 1 + * 2\n", "unexpected symbol"),
    ("foo.bar = function(self) return self end\n", None),
    ("function foo() end\n", "global"),
    ("local s = [[long\nstring]] .. 'x'\n", None),
    ("return 1\nprint(2)\n", "last statement"),
    ("for i = 1, 3 do print(i) end\nfor k, v in pairs({}) do end\n", None),
    ("f()\n(g)()\n", "ambiguous"),
]


def selftest():
    import tempfile
    ok = True
    for src, want in SELFTEST:
        fd, path = tempfile.mkstemp(suffix=".lua")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(src)
        try:
            bad = check_file(path)
            got = "global" if bad else None
        except LuaError as e:
            got = str(e)
        os.remove(path)
        good = (want is None and got is None) or (want is not None and got is not None and want in got)
        ok = ok and good
        print("selftest %-5s %-60r -> %s" % ("ok" if good else "FAIL", src[:58], got))
    return ok


def main():
    if sys.argv[1:] == ["--selftest"]:
        return 0 if selftest() else 1
    files = sys.argv[1:] or sorted(glob.glob(os.path.join(ROOT, "addon", "lua", "**", "*.lua"), recursive=True))
    rc = 0
    if not sys.argv[1:]:
        for e in feature_name_errors():
            print(e)
            rc = 1
    for f in files:
        try:
            rel = os.path.relpath(f, ROOT)
        except ValueError:
            rel = f
        try:
            bad = check_file(f)
        except LuaError as e:
            print("%s: SYNTAX ERROR %s" % (rel, e))
            rc = 1
            continue
        if bad:
            for n, l in bad:
                print("%s:%d: assignment to the global '%s'" % (rel, l, n))
            rc = 1
        else:
            print("%s: ok" % rel)
    return rc


if __name__ == "__main__":
    sys.exit(main())
