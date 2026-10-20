#Requires AutoHotkey v2.0

#Include "ConfigManager.ahk"
#Include "CliCore.ahk"
#Include "SearchCommands.ahk"
#Include "VaultScan.ahk"

TodoScanAll(scope := "all") {
    ConfigManager.EnsureLoaded()
    scanned := VaultScan.Scan(ScopeDirs(scope))
    todos := []
    for e in scanned.todos
        todos.Push({file: e.filePath, date: e.date, text: e.text, time: e.time
            , done: e.done, lineNo: e.lineNo})
    TodoSort(todos)
    return todos
}

TodoSort(todos) {
    return Utils.SortWith(todos, (a, b) => (a.date != b.date)
        ? -Utils.Cmp(a.date, b.date)
        : (!a.done && b.done) ? 1 : (a.done && !b.done) ? -1 : 0)
}

CliDone(keyword) {
    ConfigManager.EnsureLoaded()
    if (keyword = "")
        return 3
    todos := TodoScanAll()
    hits := []
    for t in todos {
        if (!t.done && (InStr(t.text, keyword) || InStr(t.time, keyword)))
            hits.Push(t)
    }
    if (hits.Length = 0) {
        if (JsonMode)
            Out(JsonOut(Map("ok", "false", "code", "E_FAIL", "msg", "未找到未完成待办: " keyword)))
        else
            Out("❌ 未找到未完成待办: " keyword)
        return 1
    }
    if (hits.Length > 1) {
        if (JsonMode) {
            cands := []
            for h in hits
                cands.Push(h.date " " h.text)
            Out(JsonOut(Map("ok", "false", "code", "E_MULTI", "msg", "多候选：请换更精确关键词", "candidates", cands)))
        } else {
            Out("❌ 多候选：请换更精确关键词。命中:")
            for h in hits
                Out("  - " h.date " " h.text)
        }
        return 2
    }
    target := hits[1]
    lines := StrSplit(FileRead(target.file, "UTF-8"), "`n", "`r")
    line := lines[target.lineNo]
    lines[target.lineNo] := StrReplace(line, "- [ ]", "- [x]", , , 1)
    nl := (InStr(FileRead(target.file, "UTF-8"), "`r`n") > 0) ? "`r`n" : "`n"
    f := FileOpen(target.file, "w", "UTF-8-RAW")
    f.Write(Join(lines, nl) nl)
    f.Close()
    if (JsonMode)
        Out(JsonOut(Map("ok", "true", "action", "done", "text", target.text, "file", target.file)))
    else
        Out("✅ 已完成: " target.text " → " target.file)
    return 0
}

Join(arr, sep) {
    out := ""
    for i, s in arr
        out .= (i = 1 ? "" : sep) s
    return out
}

CliTodos(args) {
    ConfigManager.EnsureLoaded()
    wantOpen := false, wantDone := false
    for i, a in args {
        if (i = 1)
            continue
        if (a = "--open")
            wantOpen := true
        else if (a = "--done")
            wantDone := true
    }
    days := ParseDays(args)
    scope := ParseScope(args, "all")
    all := TodoScanAll(scope)
    result := []
    for t in all {
        if (days > 0) {
            winStart := FormatTime(DateAdd(A_Now, -(days - 1), "Days"), "yyyy-MM-dd")
            if (StrCompare(t.date, winStart) < 0)
                continue
        }
        if (wantOpen && t.done)
            continue
        if (wantDone && !t.done)
            continue
        result.Push(t)
    }
    if (JsonMode) {
        arr := []
        for t in result {
            arr.Push(Map("date", t.date, "time", t.time, "text", t.text, "done", t.done ? "true" : "false"))
        }
        Out(JsonOut(Map("ok", "true", "count", String(result.Length), "scope", scope, "scopeDirs", ScopeDirNames(ScopeDirs(scope)), "todos", arr)))
        return 0
    }
    if (result.Length = 0) {
        Out("（无匹配待办：" (days > 0 ? "最近 " days " 天" : "全部") (wantOpen ? "·未完成" : wantDone ? "·已完成" : "") "）")
        return 0
    }
    curDate := ""
    for i, t in result {
        if (t.date != curDate) {
            curDate := t.date
            Out("— " curDate)
        }
        Out("  " (t.done ? "[x]" : "[ ]") " " (t.text != "" ? t.text : t.time))
    }
    Out("共 " result.Length " 条（未完成 "
        (wantDone ? 0 : CountOpen(result)) " / 已完成 "
        (wantOpen ? 0 : CountDone(result)) "）")
    return 0
}

CountOpen(arr) {
    n := 0
    for t in arr
        n += !t.done
    return n
}
CountDone(arr) {
    n := 0
    for t in arr
        n += t.done
    return n
}
