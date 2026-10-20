#Requires AutoHotkey v2.0
#Include "Utils.ahk"
#Include "ConfigManager.ahk"
#Include "PathModel.ahk"

class VaultScan {
    static ParseFile(path) {
        hTodo := ConfigManager.Get("TargetTodoHeader")
        hNote := ConfigManager.Get("TargetHeader")
        out := {custom: "", todos: [], notes: []}
        try
            lines := StrSplit(FileRead(path, "UTF-8"), "`n", "`r")
        catch
            return out
        todoIdx := 0, noteIdx := 0
        for i, line in lines {
            t := Trim(line)
            if (t = hTodo && todoIdx = 0)
                todoIdx := i
            else if (t = hNote && noteIdx = 0)
                noteIdx := i
        }
        firstSec := (todoIdx > 0 && noteIdx > 0) ? Min(todoIdx, noteIdx)
            : (todoIdx > 0) ? todoIdx : (noteIdx > 0) ? noteIdx : 0
        if (firstSec > 2) {
            txt := ""
            Loop firstSec - 2 {
                txt .= lines[A_Index + 1] "`n"
            }
            out.custom := Trim(txt, "`n ")
        }
        if (todoIdx > 0) {
            tEnd := (noteIdx > todoIdx) ? noteIdx - 1 : lines.Length
            out.todos := Utils.ParseTodoEntries(lines, todoIdx + 1, tEnd)
        }
        if (noteIdx > 0)
            out.notes := Utils.ParseNoteEntries(lines, noteIdx + 1, lines.Length)
        return out
    }

    static SplitTS(ts) {
        if RegExMatch(ts, "^(\d{4}-\d{2}-\d{2})[ T]+(\d{1,2}:\d{2}(:\d{2})?)", &m)
            return {date: m[1], time: m[2]}
        if RegExMatch(ts, "^(\d{1,2}:\d{2}(:\d{2})?)", &m)
            return {date: "", time: m[1]}
        return ""
    }

    static FileRange(fileName) {
        if RegExMatch(fileName, "^(\d{4})-(\d{2})-(\d{2})_day", &m)
            return [m[1] "-" m[2] "-" m[3], m[1] "-" m[2] "-" m[3]]
        if RegExMatch(fileName, "^(\d{4})-(\d{2})-(\d{2})_week", &m) {
            start := m[1] m[2] m[3]
            try {
                s := FormatTime(start, "yyyy-MM-dd")
                wday := Integer(FormatTime(start, "WDay"))
                offset := (wday = 1) ? 6 : wday - 2
                monday := FormatTime(DateAdd(start, -offset, "Days"), "yyyy-MM-dd")
                sunday := FormatTime(DateAdd(monday, 6, "Days"), "yyyy-MM-dd")
                return [monday, sunday]
            } catch {
            }
            return ""
        }
        if RegExMatch(fileName, "^(\d{4})-(\d{2})_month", &m) {
            try {
                start := FormatTime(m[1] m[2] "01", "yyyy-MM-dd")
                y := Integer(m[1]), mo := Integer(m[2])
                lastDay := (mo = 12) ? FormatTime((y + 1) "0101", "yyyy-MM-dd")
                    : FormatTime(y Format("{:02d}", mo + 1) "01", "yyyy-MM-dd")
                return [start, FormatTime(DateAdd(lastDay, -1, "Days"), "yyyy-MM-dd")]
            } catch {
            }
            return ""
        }
        return ""
    }

    static Scan(dirs) {
        res := {todos: [], notes: [], files: []}
        for dir in dirs {
            if !DirExist(dir)
                continue
            device := StrReplace(dir, PathModel.Vault() "\", "")
            loop files dir "\*.md" {
                parsed := this.ParseFile(A_LoopFilePath)
                fr := this.FileRange(A_LoopFileName)
                if (fr != "")
                    res.files.Push({path: A_LoopFilePath, start: fr[1], end: fr[2]})
                for e in parsed.todos {
                    ts := this.SplitTS(e.time)
                    res.todos.Push({date: ts != "" ? ts.date : (fr != "" ? fr[1] : "")
                        , time: ts != "" ? ts.time : e.time
                        , text: e.text, done: e.done
                        , channel: this._MetaVal(e.meta, "channel")
                        , files: this._MetaVals(e.meta, "file")
                        , meta: e.meta
                        , device: device, filePath: A_LoopFilePath, lineNo: e.idx})
                }
                for e in parsed.notes {
                    ts := this.SplitTS(e.time)
                    res.notes.Push({date: ts != "" ? ts.date : (fr != "" ? fr[1] : "")
                        , time: ts != "" ? ts.time : e.time
                        , text: e.text
                        , channel: this._MetaVal(e.meta, "channel")
                        , files: this._MetaVals(e.meta, "file")
                        , meta: []
                        , device: device, filePath: A_LoopFilePath, lineNo: 0})
                }
            }
        }
        return res
    }

    static _MetaVal(metaLines, key) {
        for l in metaLines {
            if RegExMatch(Trim(l), "^" key ":\s*(.+)$", &m)
                return Trim(m[1])
        }
        return ""
    }
    static _MetaVals(metaLines, key) {
        out := []
        for l in metaLines {
            if RegExMatch(Trim(l), "^" key ":\s*(.+)$", &m)
                out.Push(Trim(m[1]))
        }
        return out
    }
}
