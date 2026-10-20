#Requires AutoHotkey v2.0

class Utils {
    static ResOk(action := "", text := "") => { ok: true, action: action, msg: "", silent: false, pending: false, text: text, code: "" }
    static ResErr(msg, action := "", silent := false, code := "") => { ok: false, action: action, msg: msg, silent: silent, pending: false, text: "", code: code }
    static ResPending(action := "launch") => { ok: true, action: action, msg: "", silent: false, pending: true, text: "", code: "" }

    static UriEncode(str) {
        buf := Buffer(StrPut(str, "UTF-8"), 0)
        StrPut(str, buf, "UTF-8")
        res := ""
        Loop buf.Size - 1 {
            byte := NumGet(buf, A_Index - 1, "UChar")
            if (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A) || byte = 0x2D || byte = 0x5F || byte = 0x2E || byte = 0x7E
                res .= Chr(byte)
            else
                res .= Format("%{:02X}", byte)
        }
        return res
    }

    static ConvertMomentToAhkFormat(momentFmt) {
        result := momentFmt
        result := StrReplace(result, "YYYY", "\x01")
        result := StrReplace(result, "MMMM", "\x02")
        result := StrReplace(result, "MMM", "\x03")
        result := StrReplace(result, "MM", "\x04")
        result := StrReplace(result, "dddd", "\x05")
        result := StrReplace(result, "ddd", "\x06")
        result := StrReplace(result, "DD", "\x07")
        result := StrReplace(result, "dd", "\x08")
        result := StrReplace(result, "HH", "\x09")
        result := StrReplace(result, "mm", "\x0A")
        result := StrReplace(result, "ss", "\x0B")
        result := StrReplace(result, "\x01", "yyyy")
        result := StrReplace(result, "\x02", "MMMM")
        result := StrReplace(result, "\x03", "MMM")
        result := StrReplace(result, "\x04", "MM")
        result := StrReplace(result, "\x05", "dddd")
        result := StrReplace(result, "\x06", "ddd")
        result := StrReplace(result, "\x07", "dd")
        result := StrReplace(result, "\x08", "ddd")
        result := StrReplace(result, "\x09", "HH")
        result := StrReplace(result, "\x0A", "mm")
        result := StrReplace(result, "\x0B", "ss")
        return result
    }

    static ArrContains(arr, val) {
        for item in arr {
            if (item = val)
                return true
        }
        return false
    }

    static ObjGet(v, key, default := "") {
        if (Type(v) = "Map")
            return v.Has(key) ? v[key] : default
        if (Type(v) = "Object")
            return v.HasOwnProp(key) ? v.%key% : default
        return default
    }

    static SortWith(arr, cmpFn) {
        i := 2
        while (i <= arr.Length) {
            v := arr[i], j := i - 1
            while (j >= 1 && cmpFn.Call(arr[j], v) > 0)
                arr[j + 1] := arr[j], j--
            arr[j + 1] := v, i++
        }
        return arr
    }

    static SortBy(arr, keyFn, desc := false) {
        return Utils.SortWith(arr, (a, b) => desc
            ? -Utils.Cmp(keyFn.Call(a), keyFn.Call(b))
            : Utils.Cmp(keyFn.Call(a), keyFn.Call(b)))
    }

    static Cmp(x, y) {
        if (IsNumber(x) && IsNumber(y))
            return (x > y) ? 1 : (x < y) ? -1 : 0
        return StrCompare(x, y)
    }

    static RefreshMenuLabel(menu, enabled, checkedLabel, uncheckedLabel) {
        try menu.Rename(enabled ? uncheckedLabel : checkedLabel, enabled ? checkedLabel : uncheckedLabel)
    }

    static ConvertHotkeyToSend(hk) {
        mods := "", release := "", rest := hk, side := ""
        while (rest != "" && InStr("^!+#<>", SubStr(rest, 1, 1))) {
            c := SubStr(rest, 1, 1)
            rest := SubStr(rest, 2)
            if (c = ">")
                side := "R"
            else if (c = "<")
                side := "L"
            else if (c = "^") {
                key := side ? side "Ctrl" : "Ctrl"
                mods .= "{" key " down}", release := "{" key " up}" release, side := ""
            } else if (c = "!") {
                key := side ? side "Alt" : "Alt"
                mods .= "{" key " down}", release := "{" key " up}" release, side := ""
            } else if (c = "+") {
                key := side ? side "Shift" : "Shift"
                mods .= "{" key " down}", release := "{" key " up}" release, side := ""
            } else if (c = "#") {
                key := side ? side "Win" : "Win"
                mods .= "{" key " down}", release := "{" key " up}" release, side := ""
            }
        }
        if (mods = "" || rest = "")
            return ""
        return mods "{" rest "}" release
    }

    static SendKeys(keys, immediate := false) {
        if (keys = "")
            return false
        if (keys = "#l")
            return DllCall("user32\LockWorkStation") != 0
        if (immediate) {
            Utils._SendKeysNow(keys)
            return true
        }
        SetTimer(() => Utils._SendKeysNow(keys), -120)
        return true
    }
    static _SendKeysNow(keys) {
        capState := GetKeyState("CapsLock", "T")
        if (capState)
            SetCapsLockState("Off")
        try Send(keys)
        if (capState)
            SetCapsLockState("On")
    }

    static AddWrapText(guiObj, options, text) {
        t := guiObj.AddText(options, text)
        t.GetPos(, , &w, &h)
        t.Move(, , , h)
        return t
    }

    static DateFromFileName(fileName) {
        if RegExMatch(fileName, "^(\d{4})-(\d{2})-(\d{2})", &m)
            return m[1] "-" m[2] "-" m[3]
        if RegExMatch(fileName, "^(\d{4})-(\d{2})", &m)
            return m[1] "-" m[2]
        return fileName
    }

    static TODO_LINE_RE := "^\s*-\s\[( |x|X)\]\s*(.+)$"

    static ParseTodoEntries(lines, from, to) {
        out := []
        curTime := "", curText := "", curDone := false, curMeta := ""
        , curIdx := 0, flush := false, inMeta := false
        fence := "``````"
        i := from
        while (i <= to && i <= lines.Length) {
            line := lines[i]
            if RegExMatch(line, "^\s*-\s\[( |x|X)\]\s*(.+)$", &m) {
                if (flush)
                    out.Push({time: curTime, text: curText, done: curDone, idx: curIdx, meta: curMeta})
                curTime := Trim(m[2]), curText := "", curDone := (m[1] != " ")
                curMeta := [], curIdx := i, flush := true, inMeta := false
            } else if (flush) {
                t := Trim(line)
                if (t = fence "meta") {
                    inMeta := true
                } else if (inMeta && t = fence) {
                    inMeta := false
                } else if (inMeta) {
                    curMeta.Push(line)
                } else if (t != "") {
                    curText .= (curText = "" ? "" : "`n") t
                }
            }
            i++
        }
        if (flush)
            out.Push({time: curTime, text: curText, done: curDone, idx: curIdx, meta: curMeta})
        return out
    }

    static ParseNoteEntries(lines, from, to) {
        out := []
        curTime := "", curText := "", curSource := "", curMeta := ""
        , flush := false, inMeta := false
        fence := "``````"
        i := from
        while (i <= to && i <= lines.Length) {
            line := lines[i]
            if RegExMatch(line, "^-\s+(\d{4}-\d{2}-\d{2}[ .]\d{1,2}:\d{2}(:\d{2})?|\d{1,2}:\d{2}(:\d{2})?)\s*$", &m) {
                if (flush && curText != "")
                    out.Push({time: curTime, text: curText, source: curSource, meta: curMeta})
                curTime := m[1], curText := "", curSource := "", curMeta := []
                , flush := true, inMeta := false
            } else if (flush) {
                t := Trim(line)
                if (t = fence "meta") {
                    inMeta := true
                } else if (inMeta && t = fence) {
                    inMeta := false
                } else if (inMeta) {
                    curMeta.Push(line)
                    if RegExMatch(t, "^channel:\s*(.+)$", &sm)
                        curSource := Trim(sm[1])
                } else if (t != "") {
                    curText .= (curText = "" ? "" : "`n") t
                }
            }
            i++
        }
        if (flush && curText != "")
            out.Push({time: curTime, text: curText, source: curSource, meta: curMeta})
        return out
    }

    static CustomRange(lines, hTodo) {
        for i, line in lines {
            if (Trim(line) = hTodo)
                return (i > 1) ? [1, i - 1] : [0, 0]
        }
        return (lines.Length > 0) ? [1, lines.Length] : [0, 0]
    }
}
