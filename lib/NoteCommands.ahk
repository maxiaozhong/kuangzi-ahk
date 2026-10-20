#Requires AutoHotkey v2.0

#Include "ConfigManager.ahk"
#Include "PathModel.ahk"
#Include "QuickNote.ahk"
#Include "QuickLaunch.ahk"
#Include "AttachHelper.ahk"
#Include "PathCatalog.ahk"
#Include "CliCore.ahk"

CliPath(sub, arg := "") {
    ConfigManager.EnsureLoaded()
    sub := (sub = "") ? "today" : sub
    switch sub {
        case "config":
            if (JsonMode)
                Out(JsonOut(Map("ok", "true", "path", ConfigManager.ConfigFile)))
            else
                Out("✅ " ConfigManager.ConfigFile)
            return 0
        case "dir":
            NoteDir := PathModel.DeviceRoot()
            if (JsonMode)
                Out(JsonOut(Map("ok", "true", "path", NoteDir)))
            else
                Out("✅ " NoteDir)
            return 0
        case "today":
            NotePath := PathModel.NoteFile()
            if (JsonMode)
                Out(JsonOut(Map("ok", "true", "path", NotePath, "exists", FileExist(NotePath) ? "true" : "false")))
            else
                Out("✅ " NotePath (FileExist(NotePath) ? "（已存在）" : "（尚未创建，写入时自动生成）"))
            return 0
        case "add":
            if (arg = "") {
                Out("用法: kuangzi path add <目录或文件路径>（在 path/lnk 创建快捷方式挂载）")
                return 3
            }
            err := PathCatalog.AddTarget(arg)
            if (err != "") {
                if (JsonMode)
                    Out(JsonOut(Map("ok", "false", "code", "E_PATH_ADD", "msg", err)))
                else
                    Out("❌ " err)
                return 1
            }
            SplitPath(Trim(arg), &name)
            if (JsonMode)
                Out(JsonOut(Map("ok", "true", "word", name, "dir", PathCatalog.LnkDir())))
            else
                Out("✅ 已挂载「" name "」→ 输入框输 " name " 或 path " name " 直达")
            return 0
        case "remove":
            if (arg = "") {
                Out("用法: kuangzi path remove <词>（删除 lnk 子层挂载；手放文件请去资源管理器删）")
                return 3
            }
            err := PathCatalog.RemoveByWord(arg)
            if (err != "") {
                if (JsonMode)
                    Out(JsonOut(Map("ok", "false", "code", "E_PATH_REMOVE", "msg", err)))
                else
                    Out("❌ " err)
                return 1
            }
            if (JsonMode)
                Out(JsonOut(Map("ok", "true", "removed", arg)))
            else
                Out("✅ 已移除挂载「" arg "」")
            return 0
        case "rename":
            parts := StrSplit(arg, " ")
            if (parts.Length < 2) {
                Out("用法: kuangzi path rename <旧词> <新词>（改挂载词；文件挂载的词=目标文件名，不可改）")
                return 3
            }
            err := PathCatalog.RenameMount(parts[1], parts[2])
            if (err != "") {
                if (JsonMode)
                    Out(JsonOut(Map("ok", "false", "code", "E_PATH_RENAME", "msg", err)))
                else
                    Out("❌ " err)
                return 1
            }
            if (JsonMode)
                Out(JsonOut(Map("ok", "true", "from", parts[1], "to", parts[2])))
            else
                Out("✅ 「" parts[1] "」→「" parts[2] "」（词已更新，目标不变）")
            return 0
        case "list":
            tops := PathCatalog.TopEntries()
            if (JsonMode) {
                arr := []
                for e in tops
                    arr.Push(Map("word", e.key, "target", e.target, "mount", e.mount))
                Out(JsonOut(Map("ok", "true", "count", tops.Length, "entries", arr)))
            } else {
                if (tops.Length = 0) {
                    Out("（空）path 目录暂无挂载/文件；kuangzi path add <路径> 添加")
                    return 0
                }
                Out("共 " tops.Length " 项（词 → 目标）：")
                for e in tops
                    Out("  " e.key " → " e.target)
            }
            return 0
        default:
            Out("未知子命令: " sub "（可用: today / dir / config / add / remove / rename / list）")
            return 3
    }
}

CliAttach(filePath) {
    ConfigManager.EnsureLoaded()
    if !FileExist(filePath) {
        Fail("文件不存在: " filePath)
        return 1
    }
    ref := AttachHelper.Attach(filePath)
    if (ref = "__OVERSIZE__") {
        Fail("文件超出大小上限 " AttachHelper.MaxMB() "MB，未归档: " filePath)
        return 1
    }
    if (ref = "") {
        Fail("附件归档失败（支持的格式：图片/视频/音频/文档，见白名单）: " filePath)
        return 1
    }
    cat := AttachHelper.Classify(filePath)
    imgs := (cat = "image") ? [ref] : []
    fls := (cat = "image") ? [] : [ref]
    res := QuickNote.Submit("", false, "cli", imgs, fls)
    if (res.ok) {
        if (JsonMode) {
            Out(JsonOut(Map("ok", "true", "action", "attach", "ref", ref, "path", CliTodayPath())))
        } else {
            Out("✅ 附件已归档并追加引用 → " CliTodayPath())
            Out(ref)
        }
        return 0
    }
    if (JsonMode)
        Out(JsonOut(Map("ok", "false", "code", res.code != "" ? res.code : "E_FAIL", "msg", res.msg)))
    else
        Out("❌ " res.msg)
    return 1
}

CliOpen(arg) {
    ConfigManager.EnsureLoaded()
    looksPath := InStr(arg, ":\") || InStr(arg, ":/") || InStr(arg, "\\\\") || InStr(arg, "://") || SubStr(StrLower(arg), 1, 4) = "www."
    if (looksPath) {
        try {
            Run(arg)
            if (JsonMode)
                Out(JsonOut(Map("ok", "true", "action", "open", "target", arg)))
            else
                Out("✅ 已打开 " arg)
            return 0
        } catch as e {
            if (JsonMode)
                Out(JsonOut(Map("ok", "false", "code", "E_FAIL", "msg", "打开失败: " arg " " e.Message)))
            else
                Out("❌ 打开失败: " arg "`n" e.Message)
            return 1
        }
    }
    m := QuickLaunch.Ask(arg, "", true)
    if (m != "" && !m.HasOwnProp("cands"))
        EmitResult(EntryExecutor.Execute(m.entry, m.word, ""))
    if (m != "" && m.HasOwnProp("cands")) {
        candKeys := []
        for c in m.cands
            candKeys.Push(c.key)
        if (JsonMode)
            Out(JsonOut(Map("ok", "false", "code", "E_MULTI", "msg", "多候选：请换精确关键词", "candidates", candKeys)))
        else
            Out("❌ 多候选：请换精确关键词。命中: " JoinStr(candKeys, ", "))
        return 2
    }
    if (JsonMode)
        Out(JsonOut(Map("ok", "false", "code", "E_FAIL", "msg", "未找到快捷词: " arg "（如需直接打开文件/网址请给完整路径）")))
    else
        Out("❌ 未找到快捷词: " arg "（如需直接打开文件/网址请给完整路径）")
    return 1
}
JoinStr(arr, sep) {
    out := ""
    for s in arr
        out .= (out = "" ? "" : sep) s
    return out
}

CliNewNote(name) {
    ConfigManager.EnsureLoaded()
    NoteDir := PathModel.DeviceRoot()
    if !DirExist(NoteDir)
        DirCreate(NoteDir)
    FileName := Trim(name)
    if (SubStr(FileName, -2) != ".md")
        FileName .= ".md"
    NotePath := NoteDir "\" FileName
    if FileExist(NotePath) {
        if (JsonMode)
            Out(JsonOut(Map("ok", "false", "code", "E_FAIL", "msg", "已存在同名笔记: " NotePath)))
        else
            Out("❌ 已存在同名笔记: " NotePath)
        return 1
    }
    FileObj := FileOpen(NotePath, "w", "UTF-8-RAW")
    FileObj.Write("# " Trim(StrReplace(FileName, ".md", "")) "`n`n")
    FileObj.Close()
    try {
        Run(NotePath)
        if (JsonMode)
            Out(JsonOut(Map("ok", "true", "action", "newnote", "path", NotePath)))
        else
            Out("✅ 已新建并打开: " NotePath)
        return 0
    } catch as e {
        if (JsonMode)
            Out(JsonOut(Map("ok", "true", "action", "newnote", "path", NotePath, "msg", "打开失败: " e.Message)))
        else
            Out("✅ 已新建: " NotePath "（打开失败: " e.Message "）")
        return 0
    }
}
