#Requires AutoHotkey v2.0

#Include "ConfigManager.ahk"
#Include "PathModel.ahk"
#Include "CliCore.ahk"
#Include "SearchCommands.ahk"
#Include "VaultScan.ahk"

ParseNoteFile(path) {
    return VaultScan.ParseFile(path)
}

EntryDate(ts) {
    s := VaultScan.SplitTS(ts)
    return (s != "") ? s.date : ""
}

EntryPeriodName(dateStr, mode) {
    return PathModel.PeriodName(mode, "", "", "", StrReplace(dateStr, "-", "") "120000")
}

SortByTime(arr) {
    return Utils.SortBy(arr, (e) => e.time)
}

MergePeriod(sources, pn) {
    hTodo := ConfigManager.Get("TargetTodoHeader")
    hNote := ConfigManager.Get("TargetHeader")
    todoItems := [], noteEntries := []
    for src in sources {
        for e in src.parsed.todos
            todoItems.Push(e)
        for e in src.parsed.notes
            noteEntries.Push(e)
    }
    SortByTime(todoItems)
    SortByTime(noteEntries)
    out := "# " pn " 归档`n`n"
    for src in sources {
        if (src.parsed.custom != "")
            out .= src.parsed.custom "`n`n"
    }
    out .= hTodo "`n`n"
    for e in todoItems {
        out .= "- [" (e.done ? "x" : " ") "] " e.time "`n"
        if (e.text != "")
            out .= "  " StrReplace(e.text, "`n", "`n  ") "`n"
        if (e.meta.Length > 0) {
            out .= "  ``````meta`n"
            for ml in e.meta
                out .= ml "`n"
            out .= "  ```````n"
        }
    }
    out .= "`n" hNote "`n`n"
    for e in noteEntries {
        out .= "- " e.time "`n"
        out .= "  " StrReplace(e.text, "`n", "`n  ") "`n"
    }
    return RTrim(out, "`n") "`n"
}

CollectAttRefs(lines) {
    static imgFolderReg := ""
    if (imgFolderReg = "") {
        f := ConfigManager.Get("ImageFolder", "attachments")
        imgFolderReg := (f = "attachments") ? "attachments" : f "|attachments"
    }
    refs := []
    seen := Map()
    for line in lines {
        pos := 1
        while (pos := RegExMatch(line, "i)(?:" imgFolderReg ")[/\\][^\s\)\]]+", &m, pos)) {
            r := StrReplace(m[0], "\", "/")
            if !seen.Has(r) {
                seen[r] := true
                refs.Push(r)
            }
            pos += StrLen(m[0])
        }
    }
    return refs
}

CandAttRefs(c) {
    refs := []
    seen := Map()
    lines := []
    if (c.parsed.custom != "")
        lines.Push(c.parsed.custom)
    for e in c.parsed.todos
        lines.Push(e.text)
    for e in c.parsed.notes
        lines.Push(e.text)
    for r in CollectAttRefs(lines) {
        if !seen.Has(r) {
            seen[r] := true
            refs.Push(r)
        }
    }
    return refs
}

CliArchive(args) {
    mode := "month", dry := true
    for i, a in args {
        if (i = 1 && a = "archive")
            continue
        if (a = "--month")
            mode := "month"
        else if (a = "--week")
            mode := "week"
        else if (a = "--dry-run")
            dry := true
        else if (a = "--go")
            dry := false
        else if (a = "--json")
            continue
        else {
            if (JsonMode)
                Out(JsonOut(Map("ok", "false", "code", "E_USAGE", "msg", "未知参数: " a "（archive 参数: --week|--month|--dry-run|--go）")))
            else
                Out("❌ 未知参数: " a "（archive 参数: --week|--month|--dry-run|--go）")
            ExitApp(3)
        }
    }
    now := A_Now
    if (mode = "week") {
        wday := Integer(FormatTime(now, "WDay"))
        offset := (wday = 1) ? 6 : wday - 2
        cutoff := FormatTime(DateAdd(now, -offset, "Days"), "yyyy-MM-dd")
    } else
        cutoff := FormatTime(now, "yyyy-MM") "-01"

    dirs := []
    for d in ScopeDirs("local")
        dirs.Push(d)
    for d in ScopeDirs("devices")
        dirs.Push(d)
    cands := []
    for dir in dirs {
        if !DirExist(dir)
            continue
        loop files dir "\*.md" {
            parsed := ParseNoteFile(A_LoopFilePath)
            n := parsed.todos.Length + parsed.notes.Length
            if (n = 0)
                continue
            allOld := true
            for e in parsed.todos {
                d := EntryDate(e.time)
                if (d = "" || StrCompare(d, cutoff) >= 0) {
                    allOld := false
                    break
                }
            }
            if (allOld) {
                for e in parsed.notes {
                    d := EntryDate(e.time)
                    if (d = "" || StrCompare(d, cutoff) >= 0) {
                        allOld := false
                        break
                    }
                }
            }
            if (!allOld)
                continue
            mtime := FileGetTime(A_LoopFilePath, "M")
            cands.Push({path: A_LoopFilePath, dir: ScopeDirOf(dir), baseDir: A_LoopFileDir, mtime: mtime, parsed: parsed})
        }
    }
    if (cands.Length = 0) {
        if (JsonMode)
            Out(JsonOut(Map("ok", "true", "action", "archive", "mode", mode, "cutoff", cutoff, "periods", [])))
        else
            Out("（无可归档文件：写入区没有早于 " cutoff " 的周期日记）")
        return 0
    }

    groups := Map()
    for c in cands {
        pns := Map()
        for e in c.parsed.todos {
            d := EntryDate(e.time)
            if (d != "")
                pns[EntryPeriodName(d, mode)] := true
        }
        for e in c.parsed.notes {
            d := EntryDate(e.time)
            if (d != "")
                pns[EntryPeriodName(d, mode)] := true
        }
        for pn, _ in pns {
            if !groups.Has(pn)
                groups[pn] := {sources: [], paths: []}
            g := groups[pn]
            found := false
            for p in g.paths {
                if (p = c.path)
                    found := true
            }
            if (!found) {
                g.paths.Push(c.path)
                g.sources.Push({parsed: c.parsed, mtime: c.mtime})
            }
        }
    }

    archiveDir := PathModel.ArchiveDir()

    if (dry) {
        attCount := 0
        seenAtt := Map()
        for c in cands {
            for r in CandAttRefs(c) {
                if !seenAtt.Has(r) {
                    seenAtt[r] := true
                    attCount++
                }
            }
        }
        plans := []
        for pn, g in groups {
            srcNames := []
            for s in g.paths
                srcNames.Push(s)
            plans.Push(Map("file", pn ".md", "sources", srcNames))
        }
        if (JsonMode) {
            Out(JsonOut(Map("ok", "true", "action", "archive", "mode", mode, "cutoff", cutoff, "dryrun", "true"
                , "attachments", String(attCount), "periods", plans)))
            return 0
        }
        Out("【归档计划（dry-run，未执行）】模式: " (mode = "week" ? "按周" : "按月") "，边界: " cutoff " 之后不动")
        for p in plans {
            Out("→ " p["file"])
            for s in p["sources"]
                Out("   源: " s)
        }
        Out("附件随迁: " attCount " 个（引用有效的附件将移入归档区 attachments，只保留一份）")
        Out("确认无误后加 --go 执行")
        return 0
    }

    backupDir := A_Temp "\kuangzi-archive-backup-" FormatTime(, "yyyyMMdd-HHmmss")
    DirCreate(backupDir)
    for c in cands {
        name := c.dir "__" SubStr(c.path, InStr(c.path, "\", false, -1) + 1)
        FileCopy(c.path, backupDir "\" name, true)
    }

    results := []
    for pn, g in groups {
        archivePath := archiveDir "\" pn ".md"
        if FileExist(archivePath) {
            mtime := FileGetTime(archivePath, "M")
            old := ParseNoteFile(archivePath)
            g.sources.Push({parsed: old, mtime: mtime})
        }
        Utils.SortBy(g.sources, (s) => s.mtime)
        content := MergePeriod(g.sources, pn)
        prodLines := Map()
        for line in StrSplit(content, "`n", "`r") {
            t := Trim(line)
            if (t = "")
                continue
            prodLines[t] := prodLines.Has(t) ? prodLines[t] + 1 : 1
        }
        hTodo := ConfigManager.Get("TargetTodoHeader")
        hNote := ConfigManager.Get("TargetHeader")
        for c in cands {
            if !FileExist(c.path)
                continue
            srcLines := StrSplit(FileRead(c.path, "UTF-8"), "`n", "`r")
            for line in srcLines {
                t := Trim(line)
                if (t = "" || t = hTodo || t = hNote || RegExMatch(t, "^#\s"))
                    continue
                if !prodLines.Has(t) || prodLines[t] < 1 {
                    Fail("对账失败：行丢失于 " pn ".md → [" t "]，已中止未删源，备份在 " backupDir)
                    return 1
                }
                prodLines[t] -= 1
            }
        }
        if !DirExist(archiveDir)
            DirCreate(archiveDir)
        f := FileOpen(archivePath, "w", "UTF-8-RAW")
        f.Write(content)
        f.Close()
        srcNames := []
        for p in g.paths
            srcNames.Push(p)
        results.Push(Map("file", pn ".md", "sources", srcNames))
    }

    attMoved := []
    for c in cands {
        for r in CandAttRefs(c) {
            src := c.baseDir "\" StrReplace(r, "/", "\")
            if !FileExist(src)
                continue
            if !DirExist(PathModel.ArchiveAttachDir())
                DirCreate(PathModel.ArchiveAttachDir())
            name := SubStr(r, InStr(r, "/", false, -1) + 1)
            dst := PathModel.ArchiveAttachDir() "\" name
            if FileExist(dst)
                FileDelete(src)
            else
                FileMove(src, dst)
            attMoved.Push(c.dir "/" name)
        }
    }
    for c in cands
        FileDelete(c.path)

    if (JsonMode) {
        Out(JsonOut(Map("ok", "true", "action", "archive", "mode", mode, "cutoff", cutoff
            , "periods", results, "attachments", attMoved, "backup", backupDir)))
        return 0
    }
    Out("✅ 归档完成（" (mode = "week" ? "按周" : "按月") "，边界 " cutoff "）")
    for r in results {
        Out("→ " r["file"])
        for s in r["sources"]
            Out("   已并入并移除源: " s)
    }
    if (attMoved.Length > 0) {
        Out("附件随迁 " attMoved.Length " 个:")
        for a in attMoved
            Out("   " a)
    }
    Out("备份: " backupDir "（确认稳定后可删）")
    return 0
}
