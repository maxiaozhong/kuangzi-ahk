#Requires AutoHotkey v2.0

#Include "ConfigManager.ahk"
#Include "PathModel.ahk"
#Include "CliCore.ahk"
#Include "SearchCommands.ahk"
#Include "VaultScan.ahk"

ParseQueryDate(args) {
    for i, a in args {
        if (a = "--date" && i < args.Length) {
            d := args[i + 1]
            if RegExMatch(d, "^\d{4}-\d{2}-\d{2}$")
                return d
            if (JsonMode)
                Out(JsonOut(Map("ok", "false", "code", "E_USAGE", "msg", "日期格式须为 YYYY-MM-DD，如 --date 2026-09-17")))
            else
                Out("❌ 日期格式须为 YYYY-MM-DD，如 --date 2026-09-17")
            ExitApp(3)
        }
    }
    return FormatTime(, "yyyy-MM-dd")
}

ScanScope(scope) {
    return VaultScan.Scan(ScopeDirs(scope))
}

CliNoteQuery(args) {
    dateStr := ParseQueryDate(args)
    scope := ParseScope(args, "all")
    scanned := ScanScope(scope)
    items := []
    for e in scanned.notes {
        if (e.date != dateStr)
            continue
        items.Push(Map("time", e.time, "text", e.text, "device", e.device))
    }
    if (JsonMode) {
        Out(JsonOut(Map("ok", "true", "count", String(items.Length), "date", dateStr, "scope", scope, "items", items)))
        return 0
    }
    if (items.Length = 0) {
        Out("（" dateStr " 无速记，范围: " scope "）")
        return 0
    }
    for it in items
        Out("  [" it["time"] "][" it["device"] "] " StrReplace(it["text"], "`n", " / "))
    Out("共 " items.Length " 条（" dateStr "，范围: " scope "）")
    return 0
}

CliTodoQuery(args) {
    dateStr := ParseQueryDate(args)
    scope := ParseScope(args, "all")
    scanned := ScanScope(scope)
    items := []
    for e in scanned.todos {
        if (e.date != dateStr)
            continue
        items.Push(Map("time", e.time, "text", e.text, "done", e.done ? "true" : "false", "device", e.device))
    }
    if (JsonMode) {
        Out(JsonOut(Map("ok", "true", "count", String(items.Length), "date", dateStr, "scope", scope, "items", items)))
        return 0
    }
    if (items.Length = 0) {
        Out("（" dateStr " 无待办，范围: " scope "）")
        return 0
    }
    for it in items
        Out("  " (it["done"] = "true" ? "[x]" : "[ ]") " [" it["time"] "] " it["text"] "  (" it["device"] ")")
    Out("共 " items.Length " 条（" dateStr "，范围: " scope "）")
    return 0
}

CliDaily(args) {
    dateStr := ParseQueryDate(args)
    scope := ParseScope(args, "all")
    scanned := ScanScope(scope)
    notes := [], todos := []
    for e in scanned.notes {
        if (e.date = dateStr)
            notes.Push(Map("time", e.time, "text", e.text, "device", e.device))
    }
    for e in scanned.todos {
        if (e.date = dateStr)
            todos.Push(Map("time", e.time, "text", e.text, "done", e.done ? "true" : "false", "device", e.device))
    }
    if (JsonMode) {
        Out(JsonOut(Map("ok", "true", "date", dateStr, "scope", scope
            , "notes", notes, "todos", todos)))
        return 0
    }
    Out("【" dateStr " 每日聚合（范围: " scope "）】")
    Out("速记 " notes.Length " 条：")
    for it in notes
        Out("  [" it["time"] "][" it["device"] "] " StrReplace(it["text"], "`n", " / "))
    Out("待办 " todos.Length " 条：")
    for it in todos
        Out("  " (it["done"] = "true" ? "[x]" : "[ ]") " [" it["time"] "] " it["text"] "  (" it["device"] ")")
    return 0
}
