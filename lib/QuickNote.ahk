#Requires AutoHotkey v2.0
#Include "Utils.ahk"
#Include "ConfigManager.ahk"
#Include "PathModel.ahk"

class QuickNote {
    static LastError := ""

    static _OpenRW(path) {
        Loop 3 {
            try {
                f := FileOpen(path, "rw", "UTF-8-RAW")
                if (f)
                    return f
            }
            Sleep 150
        }
        return ""
    }

    static Submit(InputText, isTodo, channel := "", images := [], files := []) {
        ConfigManager.EnsureLoaded()
        if (Trim(InputText) = "" && images.Length + files.Length = 0)
            return Utils.ResOk("empty")
        TodayDateStr := FormatTime(, ConfigManager.Get("DateFormat"))
        NotePath := this.EnsureNoteFile(TodayDateStr)
        if (NotePath = "")
            return Utils.ResErr(this.LastError, isTodo ? "todo" : "note", false, "ERR_NOTE_CREATE")

        FileObj := this._OpenRW(NotePath)
        if !FileObj
            return Utils.ResErr(NotePath, isTodo ? "todo" : "note", false, "ERR_FILE_LOCKED")

        try {
            Content := FileObj.Read()
            Content := StrReplace(Content, "`r`n", "`n")
            InputText := StrReplace(InputText, "`r`n", "`n")

            if (isTodo) {
                Target := ConfigManager.Get("TargetTodoHeader")
                Prefix := "- [ ] "
            } else {
                Target := ConfigManager.Get("TargetHeader")
                Prefix := "- "
            }
            if (images.Length > 0) {
                for img in images
                    InputText .= (InputText = "" ? "" : "`n") "![](" img ")"
            }
            FormattedInput := "  " . StrReplace(InputText, "`n", "`n  ")
            AppendStr := Prefix FormatTime(, ConfigManager.Get("DateTimeFormat")) "`n" FormattedInput
            metaOn := ConfigManager.Get("NoteMetaEnabled", 0)
            ch := metaOn ? channel : ""
            if (files.Length > 0 || ch != "") {
                fence := "``````"
                metaLines := []
                for f in files
                    metaLines.Push("file: " f)
                if (ch != "")
                    metaLines.Push("channel: " ch)
                AppendStr .= "`n  " fence "meta"
                for ml in metaLines
                    AppendStr .= "`n  " ml
                AppendStr .= "`n  " fence
            }

            SafeTarget := "\Q" Target "\E"

            if (Target = "")
                return Utils.ResErr(NotePath, isTodo ? "todo" : "note", false, "ERR_NOTE_CREATE")

            LastPos := 0, LastLen := 0
            ScanPos := 1
            while (ScanPos := RegExMatch(Content, "m)^" SafeTarget "\s*$", &Match, ScanPos)) {
                LastPos := Match.Pos, LastLen := Match.Len
                ScanPos += Match.Len > 0 ? Match.Len : 1
            }

            if (LastPos = 0) {
                Content := RegExReplace(Content, "\s+$", "")
                Content .= "`n`n" Target "`n" AppendStr "`n`n"
            } else {
                HeaderEnd := LastPos + LastLen
                After := SubStr(Content, HeaderEnd + 1)
                NextHeadingPos := RegExMatch(After, "m)^#{1,6}\s")
                BlockEnd := NextHeadingPos ? HeaderEnd + NextHeadingPos : StrLen(Content) + 1

                Prefix := RegExReplace(SubStr(Content, 1, BlockEnd - 1), "\s+$", "")
                Suffix := NextHeadingPos ? RegExReplace(SubStr(Content, BlockEnd), "^\s+", "") : ""

                Content := Prefix "`n`n" AppendStr "`n`n" (Suffix = "" ? "" : "`n" Suffix)
            }

            this._WriteBack(FileObj, Content)
            return Utils.ResOk(isTodo ? "todo" : "note", InputText)
        } catch as e {
            try FileObj.Close()
            return Utils.ResErr(NotePath "`n`n" e.Message, isTodo ? "todo" : "note", false, "ERR_FILE_WRITE")
        }
    }

    static _WriteBack(FileObj, Content) {
        FileObj.Seek(0)
        FileObj.Write(Content)
        FileObj.Length := FileObj.Pos
        FileObj.Close()
    }

    static EnsureNoteFile(TodayDateStr) {
        ConfigManager.EnsureLoaded()
        try {
            NoteDir := PathModel.DeviceRoot()
            NotePath := PathModel.NoteFile()

            if !DirExist(NoteDir)
                DirCreate(NoteDir)

            if !FileExist(NotePath) {
                NewFile := FileOpen(NotePath, "w", "UTF-8-RAW")
                NewFile.Write(this.BuildDayTemplate(TodayDateStr))
                NewFile.Close()
            }
            return NotePath
        } catch as e {
            this.LastError := PathModel.Vault() "`n`n" e.Message
            return ""
        }
    }

    static BuildDayTemplate(TodayDateStr) {
        ConfigManager.EnsureLoaded()
        content := ""
        if (ConfigManager.Get("TemplatePath") != "") {
            TemplateFilePath := PathModel.Vault() "\" ConfigManager.Get("TemplatePath")
            if !FileExist(TemplateFilePath) && FileExist(TemplateFilePath ".md")
                TemplateFilePath .= ".md"
            if FileExist(TemplateFilePath) {
                TemplateFile := FileOpen(TemplateFilePath, "r", "UTF-8-RAW")
                content := TemplateFile.Read()
                TemplateFile.Close()
            }
        }
        if (Trim(content) = "")
            content := this.DefaultTemplate()
        return StrReplace(this.ProcessTemplate(content, TodayDateStr), "`r`n", "`n")
    }

    static DefaultTemplate() {
        return "# {{period}} 框子笔记数据`n`n`n`n`n{{TargetTodoHeader}}`n`n{{TargetHeader}}`n"
    }

    static ProcessTemplate(Content, TodayStr) {
        Content := StrReplace(Content, "{{period}}", PathModel.PeriodName())
        Content := StrReplace(Content, "{{TargetTodoHeader}}", ConfigManager.Get("TargetTodoHeader"))
        Content := StrReplace(Content, "{{TargetHeader}}", ConfigManager.Get("TargetHeader"))
        Content := RegExReplace(Content, "i)\{\{date\}\}", TodayStr)
        Content := RegExReplace(Content, "i)\{\{title\}\}", TodayStr)
        Pos := 1
        while Pos := RegExMatch(Content, "\{\{DATE:(.*?)\}\}", &Match, Pos) {
            fmt := Match[1]
            dateVal := FormatTime(, Utils.ConvertMomentToAhkFormat(fmt))
            Content := StrReplace(Content, Match[0], dateVal)
        }
        return Content
    }

    static OpenTodayNote() {
        ConfigManager.EnsureLoaded()
        NotePath := this.EnsureNoteFile(FormatTime(, ConfigManager.Get("DateFormat")))
        if (NotePath = "")
            return Utils.ResErr(this.LastError, "", false, "ERR_NOTE_CREATE")
        try {
            Run(NotePath)
            return Utils.ResOk("open")
        } catch as e {
            return Utils.ResErr(NotePath "`n`n" e.Message, "", false, "ERR_NOTE_OPEN")
        }
    }

    static OpenNoteFolder() {
        ConfigManager.EnsureLoaded()
        NoteDir := PathModel.DeviceRoot()
        try {
            if !DirExist(NoteDir)
                DirCreate(NoteDir)
            Run(NoteDir)
            return Utils.ResOk("open")
        } catch as e {
            return Utils.ResErr(NoteDir "`n`n" e.Message, "", false, "ERR_DIR_OPEN")
        }
    }

    static NewNote() {
        ConfigManager.EnsureLoaded()
        NoteDir := PathModel.DeviceRoot()
        if !DirExist(NoteDir)
            DirCreate(NoteDir)
        Result := InputBox("请输入笔记文件名（无需加 .md）：", "新建笔记", "w320 h140")
        if (Result.Result = "OK" && Result.Value != "") {
            FileName := Trim(Result.Value)
            if (SubStr(FileName, -2) != ".md")
                FileName .= ".md"
            NotePath := NoteDir "\" FileName
            if !FileExist(NotePath) {
                FileObj := FileOpen(NotePath, "w", "UTF-8-RAW")
                FileObj.Write("# " Trim(Result.Value) "`n`n")
                FileObj.Close()
            }
            Run(NotePath)
        }
        return Utils.ResOk("newnote")
    }
}
