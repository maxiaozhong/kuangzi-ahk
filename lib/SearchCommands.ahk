#Requires AutoHotkey v2.0

#Include "ConfigManager.ahk"
#Include "PathModel.ahk"
#Include "CliCore.ahk"
#Include "VaultScan.ahk"

global ScopeErr := ""
ScopeDirs(scope) {
    global ScopeErr
    ScopeErr := ""
    ConfigManager.EnsureLoaded()
    vault := PathModel.Vault()
    own := PathModel.DeviceRoot()
    arch := PathModel.ArchiveDir()
    dirs := []
    switch scope {
        case "local":
            dirs.Push(own)
        case "vault":
            dirs.Push(vault)
        case "devices", "all", "archive":
            if (scope = "all") {
                for p in PathModel.Partitions()
                    dirs.Push(p)
            }
            if (scope = "devices") {
                for p in PathModel.Partitions() {
                    if (p != own && p != arch)
                        dirs.Push(p)
                }
            }
            if (scope = "archive")
                dirs.Push(arch)
        default:
            for p in PathModel.Partitions() {
                SplitPath(p, &pname)
                if (pname = scope) {
                    dirs.Push(p)
                    return dirs
                }
            }
            ScopeErr := "未知查找区: " scope "（可用: local / devices / archive / all / vault / 分区目录名）"
    }
    return dirs
}

ScopeAllDirs() {
    return ScopeDirs("all")
}

ScopeDirNames(dirs) {
    names := []
    for d in dirs
        names.Push(StrReplace(d, PathModel.Vault() "\", ""))
    return names
}

ScopeDirOf(dir) {
    return StrReplace(dir, PathModel.Vault() "\", "")
}

ScanLines(dirs, matchFn) {
    items := []
    for dir in dirs {
        if !DirExist(dir)
            continue
        loop files dir "\*.md", "R" {
            fileName := A_LoopFileName
            fr := VaultScan.FileRange(fileName)
            fileDate := (fr != "") ? fr[1] : Utils.DateFromFileName(fileName)
            try
                lines := StrSplit(FileRead(A_LoopFilePath, "UTF-8"), "`n", "`r")
            catch
                continue
            inCode := false
            for lineNo, line in lines {
                if RegExMatch(line, "^``````")
                    inCode := !inCode
                if (!inCode && matchFn(line))
                    items.Push({file: A_LoopFilePath, date: fileDate, text: Trim(line), lineNo: lineNo})
            }
        }
    }
    return items
}

IsCodeLikeTag(t) {
    if RegExMatch(t, "[;),`"`'``]")   ; 含代码标点（含 markdown 内联代码反引号）
        return true
    if RegExMatch(t, "^[0-9A-Fa-f]{3,8}$")
        return true
    return false
}
ExtractTags(line) {
    tags := []
    pos := 1
    while (pos := RegExMatch(line, "(\s|^)#([^\s#]+)", &m, pos)) {
        if (m[1] != "" && !IsCodeLikeTag(m[2]))
            tags.Push(m[2])
        pos += m.Len[0] > 0 ? m.Len[0] : 1
    }
    return tags
}

ParseScope(args, defScope) {
    scope := defScope
    for i, a in args {
        if (a = "--scope" && i < args.Length)
            scope := args[i + 1]
    }
    ScopeDirs(scope)
    if (ScopeErr != "") {
        if (JsonMode)
            Out(JsonOut(Map("ok", "false", "code", "E_USAGE", "msg", ScopeErr)))
        else
            Out("❌ " ScopeErr)
        ExitApp(3)
    }
    return scope
}

ParseDays(args) {
    for i, a in args {
        if (a = "--days" && i < args.Length) {
            try
                return Integer(args[i + 1])
            catch
                return 0
        }
    }
    return 0
}

ParsePositionals(args, from := 1) {
    out := []
    i := from
    while (i <= args.Length) {
        a := args[i]
        if (a = "--date" || a = "--scope" || a = "--days") {
            i += 2
            continue
        }
        if (SubStr(a, 1, 2) = "--") {
            i++
            continue
        }
        out.Push(a)
        i++
    }
    return out
}

OutOfDays(date, days) {
    if (days <= 0)
        return false
    winStart := FormatTime(DateAdd(A_Now, -(days - 1), "Days"), "yyyy-MM-dd")
    return (StrCompare(date, winStart) < 0)
}

CliTag(args) {
    days := ParseDays(args)
    pos := ParsePositionals(args, 2)
    if (pos.Length = 0)
        return 3
    tagWord := pos[1]
    tagName := (SubStr(tagWord, 1, 1) = "#") ? SubStr(tagWord, 2) : tagWord
    scope := ParseScope(args, "all")
    dirs := ScopeDirs(scope)
    hits := ScanLines(dirs, (line) => HasTag(line, tagName))
    if (days > 0) {
        kept := []
        for h in hits
            if (!OutOfDays(h.date, days))
                kept.Push(h)
        hits := kept
    }
    if (JsonMode) {
        arr := []
        for h in hits
            arr.Push(Map("date", h.date, "file", h.file, "text", h.text))
        Out(JsonOut(Map("ok", "true", "count", String(hits.Length), "tag", tagName, "scope", scope, "scopeDirs", ScopeDirNames(dirs), "days", String(days), "items", arr)))
        return 0
    }
    if (hits.Length = 0) {
        Out("（无 #" tagName " 标签的行，范围: " scope (days > 0 ? "，最近 " days " 天" : "") "）")
        return 0
    }
    curDate := ""
    for h in hits {
        if (h.date != curDate) {
            curDate := h.date
            Out("— " curDate)
        }
        Out("  " h.text)
    }
    Out("共 " hits.Length " 条（范围: " scope (days > 0 ? "，最近 " days " 天" : "") "）")
    return 0
}

HasTag(line, tagName) {
    pos := 1
    while (pos := RegExMatch(line, "(\s|^)#([^\s#]+)", &m, pos)) {
        if (m[1] != "" && m[2] = tagName && !IsCodeLikeTag(m[2]))
            return true
        pos += m.Len[0] > 0 ? m.Len[0] : 1
    }
    return false
}

CliTags(args) {
    scope := ParseScope(args, "all")
    days := ParseDays(args)
    dirs := ScopeDirs(scope)
    hits := ScanLines(dirs, (line) => ExtractTags(line).Length > 0)
    if (days > 0) {
        kept := []
        for h in hits
            if (!OutOfDays(h.date, days))
                kept.Push(h)
        hits := kept
    }
    counts := Map()
    order := []
    for h in hits {
        for t in ExtractTags(h.text) {
            if (!counts.Has(t)) {
                counts[t] := 0
                order.Push(t)
            }
            counts[t] += 1
        }
    }
    Utils.SortBy(order, (t) => counts[t], true)
    if (JsonMode) {
        arr := []
        for t in order
            arr.Push(Map("tag", t, "count", String(counts[t])))
        Out(JsonOut(Map("ok", "true", "count", String(order.Length), "scope", scope, "scopeDirs", ScopeDirNames(dirs), "days", String(days), "tags", arr)))
        return 0
    }
    if (order.Length = 0) {
        Out("（范围内无任何标签，范围: " scope (days > 0 ? "，最近 " days " 天" : "") "）")
        return 0
    }
    for t in order
        Out("  #" t "  ×" counts[t])
    Out("共 " order.Length " 个标签（范围: " scope (days > 0 ? "，最近 " days " 天" : "") "）")
    return 0
}

CliFind(args) {
    kw := ""
    days := ParseDays(args)
    pos := ParsePositionals(args, 2)
    if (pos.Length = 0)
        return 3
    kw := pos[1]
    scope := ParseScope(args, "all")
    dirs := ScopeDirs(scope)
    kwLower := StrLower(kw)
    hits := ScanLines(dirs, (line) => InStr(StrLower(line), kwLower))
    if (days > 0) {
        kept := []
        for h in hits
            if (!OutOfDays(h.date, days))
                kept.Push(h)
        hits := kept
    }
    if (JsonMode) {
        arr := []
        for h in hits
            arr.Push(Map("date", h.date, "file", h.file, "text", h.text))
        Out(JsonOut(Map("ok", "true", "count", String(hits.Length), "scope", scope, "scopeDirs", ScopeDirNames(dirs), "days", String(days), "items", arr)))
        return 0
    }
    if (hits.Length = 0) {
        Out("（无包含「" kw "」的行，范围: " scope (days > 0 ? "，最近 " days " 天" : "") "）")
        return 0
    }
    curDate := ""
    for h in hits {
        if (h.date != curDate) {
            curDate := h.date
            Out("— " curDate)
        }
        Out("  " h.text)
    }
    Out("共 " hits.Length " 条（范围: " scope (days > 0 ? "，最近 " days " 天" : "") "）")
    return 0
}
