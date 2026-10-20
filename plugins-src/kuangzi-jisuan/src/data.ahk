#Requires AutoHotkey v2.0

PluginDataFile() {
    return A_ScriptDir "\data.json"
}

PluginDefaultData() {
    return { settings: { saveHistory: true, maxHistory: 50, notifyStyle: "center" }, history: [] }
}

PluginLoadData() {
    f := PluginDataFile()
    if !FileExist(f)
        return PluginDefaultData()
    try {
        text := FileRead(f, "UTF-8")
        while (SubStr(text, 1, 1) = Chr(0xFEFF))
            text := SubStr(text, 2)
        m := PluginJsonParse(text)
        if (Type(m) != "Map")
            return PluginDefaultData()
        d := PluginDefaultData()
        if (m.Has("settings") && Type(m["settings"]) = "Map") {
            if (m["settings"].Has("saveHistory"))
                d.settings.saveHistory := !!m["settings"]["saveHistory"]
            if (m["settings"].Has("maxHistory") && IsNumber(m["settings"]["maxHistory"]))
                d.settings.maxHistory := m["settings"]["maxHistory"] + 0
            if (m["settings"].Has("notifyStyle") && (m["settings"]["notifyStyle"] = "toast"))
                d.settings.notifyStyle := "toast"
        }
        if (m.Has("history") && Type(m["history"]) = "Array") {
            d.history := []
            for item in m["history"] {
                if (Type(item) = "Map" && item.Has("t") && item.Has("expr") && item.Has("result"))
                    d.history.Push({ t: item["t"], expr: item["expr"], result: item["result"] })
            }
        }
        return d
    } catch {
        return PluginDefaultData()
    }
}

PluginSaveData(d) {
    q := Chr(34)
    s := "{`n"
    s .= "  " q "settings" q ": {"
    s .= q "saveHistory" q ":" (d.settings.saveHistory ? "true" : "false") ","
    s .= q "maxHistory" q ":" d.settings.maxHistory ","
    s .= q "notifyStyle" q ":" q d.settings.notifyStyle q "},`n"
    s .= "  " q "history" q ": ["
    first := true
    for item in d.history {
        if (!first)
            s .= ","
        first := false
        s .= "{`"t`":`"" PluginJsonEscape(item.t) "`",`"expr`":`"" PluginJsonEscape(item.expr) "`",`"result`":`"" PluginJsonEscape(item.result) "`"}"
    }
    s .= "]`n}"
    f := FileOpen(PluginDataFile(), "w", "UTF-8-RAW")
    f.Write(s), f.Close()
}

PluginAppendHistory(d, expr, result) {
    if (!d.settings.saveHistory)
        return false
    d.history.Push({ t: FormatTime(, "yyyy-MM-dd HH:mm"), expr: expr, result: result })
    while (d.history.Length > d.settings.maxHistory)
        d.history.RemoveAt(1)
    return true
}

PluginJsonEscape(s) {
    q := Chr(34), bs := Chr(92)
    s := StrReplace(s, bs, bs bs)
    s := StrReplace(s, q, bs q)
    s := StrReplace(s, "`n", bs "n")
    s := StrReplace(s, "`r", bs "r")
    s := StrReplace(s, "`t", bs "t")
    return s
}

PluginJsonParse(text) {
    pos := 1
    return PluginJsonValue(text, &pos)
}
PluginJsonSkipWs(text, &pos) {
    while (pos <= StrLen(text)) {
        c := SubStr(text, pos, 1)
        if (c = " " || c = "`t" || c = "`r" || c = "`n")
            pos++
        else
            break
    }
}
PluginJsonValue(text, &pos) {
    PluginJsonSkipWs(text, &pos)
    c := SubStr(text, pos, 1)
    if (c = "{") {
        pos++
        m := Map()
        PluginJsonSkipWs(text, &pos)
        if (SubStr(text, pos, 1) = "}") {
            pos++
            return m
        }
        loop {
            PluginJsonSkipWs(text, &pos)
            key := PluginJsonString(text, &pos)
            PluginJsonSkipWs(text, &pos)
            pos++
            m[key] := PluginJsonValue(text, &pos)
            PluginJsonSkipWs(text, &pos)
            nc := SubStr(text, pos, 1)
            if (nc = ",") {
                pos++
                continue
            }
            if (nc = "}") {
                pos++
                return m
            }
            throw Error("bad json object")
        }
    }
    if (c = "[") {
        pos++
        arr := []
        PluginJsonSkipWs(text, &pos)
        if (SubStr(text, pos, 1) = "]") {
            pos++
            return arr
        }
        loop {
            arr.Push(PluginJsonValue(text, &pos))
            PluginJsonSkipWs(text, &pos)
            nc := SubStr(text, pos, 1)
            if (nc = ",") {
                pos++
                continue
            }
            if (nc = "]") {
                pos++
                return arr
            }
            throw Error("bad json array")
        }
    }
    if (c = Chr(34))
        return PluginJsonString(text, &pos)
    rest := SubStr(text, pos)
    if (SubStr(rest, 1, 4) = "true") {
        pos += 4
        return 1
    }
    if (SubStr(rest, 1, 5) = "false") {
        pos += 5
        return 0
    }
    if RegExMatch(rest, "^-?\d+(?:\.\d+)?", &m) {
        pos += m.Len()
        return m[0] + 0
    }
    throw Error("bad json value")
}
PluginJsonString(text, &pos) {
    if (SubStr(text, pos, 1) != Chr(34))
        throw Error("bad json string")
    pos++
    s := ""
    while (pos <= StrLen(text)) {
        c := SubStr(text, pos, 1)
        if (c = Chr(34)) {
            pos++
            return s
        }
        if (c = Chr(92)) {
            nc := SubStr(text, pos + 1, 1)
            if (nc = "n")
                s .= "`n", pos += 2
            else if (nc = "r")
                s .= "`r", pos += 2
            else if (nc = "t")
                s .= "`t", pos += 2
            else if (nc = Chr(92))
                s .= Chr(92), pos += 2
            else if (nc = Chr(34))
                s .= Chr(34), pos += 2
            else
                s .= c, pos++
        } else {
            s .= c
            pos++
        }
    }
    throw Error("unterminated json string")
}
