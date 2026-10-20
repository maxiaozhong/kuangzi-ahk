#Requires AutoHotkey v2.0

CalcEvaluate(expr) {
    expr := Trim(expr)
    if (expr = "")
        return { ok: false, text: "", msg: "算式为空" }
    norm := CalcNormalize(expr)
    if (norm = "")
        return { ok: false, text: "", msg: "算式无法解析，请检查格式" }
    try {
        val := CalcParser.Compute(norm)
    } catch as e {
        return { ok: false, text: "", msg: e.Message }
    }
    if (!IsNumber(val))
        return { ok: false, text: "", msg: "算式无法解析，请检查格式" }
    return { ok: true, text: CalcFormat(val), msg: "" }
}

CalcNormalize(expr) {
    s := expr
    s := StrReplace(s, "（", "("), s := StrReplace(s, "）", ")")
    s := StrReplace(s, "＋", "+"), s := StrReplace(s, "－", "-")
    s := StrReplace(s, "×", "*"), s := StrReplace(s, "÷", "/")
    s := StrReplace(s, "％", "%"), s := StrReplace(s, "．", ".")
    s := StrReplace(s, "，", ","), s := StrReplace(s, "：", ":")
    loop 10
        s := StrReplace(s, Chr(0xFF10 + A_Index - 1), Chr(0x30 + A_Index - 1))
    if RegExMatch(s, "\d\s+\d")
        return ""
    s := StrReplace(s, " "), s := StrReplace(s, "`t"), s := StrReplace(s, ",")
    if RegExMatch(s, "i)[^0-9+\-*/%^().e]")
        return ""
    s := RegExReplace(s, "(\d+(?:\.\d+)?)%(?!\d)", "($1/100)")
    return s
}

class CalcParser {
    static _pos := 1, _src := ""
    static Compute(s) {
        this._src := s, this._pos := 1
        val := this._Expr()
        if (this._pos <= StrLen(this._src))
            throw Error("算式在位置 " this._pos " 附近有误")
        return val
    }
    static _Peek() {
        return (this._pos <= StrLen(this._src)) ? SubStr(this._src, this._pos, 1) : ""
    }
    static _Expr() {
        val := this._Term()
        loop {
            c := this._Peek()
            if (c = "+" || c = "-") {
                this._pos++
                rhs := this._Term()
                val := (c = "+") ? (val + rhs) : (val - rhs)
            } else
                break
        }
        return val
    }
    static _Term() {
        val := this._Factor()
        loop {
            c := this._Peek()
            if (c = "*" || c = "/" || c = "%") {
                this._pos++
                rhs := this._Factor()
                if ((c = "/" || c = "%") && rhs = 0)
                    throw Error("除数为零")
                val := (c = "*") ? (val * rhs) : (c = "/") ? (val / rhs) : Mod(val, rhs)
            } else
                break
        }
        return val
    }
    static _Factor() {
        val := this._Unary()
        if (this._Peek() = "^") {
            this._pos++
            val := val ** this._Factor()
        }
        return val
    }
    static _Unary() {
        c := this._Peek()
        if (c = "-" || c = "+") {
            this._pos++
            v := this._Unary()
            return (c = "-") ? -v : v
        }
        return this._Primary()
    }
    static _Primary() {
        c := this._Peek()
        if (c = "(") {
            this._pos++
            val := this._Expr()
            if (this._Peek() != ")")
                throw Error("括号不匹配")
            this._pos++
            return val
        }
        if RegExMatch(this._src, "\d+(?:\.\d+)?(?:[eE][+\-]?\d+)?", &m, this._pos) && m.Pos() = this._pos {
            this._pos += m.Len()
            return m[0] + 0
        }
        throw Error("位置 " this._pos " 附近缺少数字")
    }
}

CalcFormat(val) {
    if (val = Round(val) && Abs(val) < 1e15)
        return String(Round(val))
    s := String(Round(val, 10))
    if (InStr(s, ".")) {
        s := RTrim(s, "0")
        s := RTrim(s, ".")
    }
    return s
}
