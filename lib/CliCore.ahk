#Requires AutoHotkey v2.0

#Include "JSON.ahk"
#Include "Utils.ahk"
#Include "AppInfo.ahk"
#Include "ConfigManager.ahk"
#Include "QuickNote.ahk"
#Include "PluginManager.ahk"

global JsonMode := false
Out(text) {
    static HasConsole := -1
    if (HasConsole = -1)
        HasConsole := DllCall("Kernel32\GetStdHandle", "Int", -11, "Ptr") != 0
            && DllCall("Kernel32\GetFileType", "Ptr", DllCall("Kernel32\GetStdHandle", "Int", -11, "Ptr"), "UInt") != 0
    if (HasConsole)
        FileAppend(text "`n", "*", "UTF-8")
}

JsonOut(obj) {
    return JSON.stringify(JsonBoolize(obj), 0, "")
}
JsonBoolize(v) {
    switch Type(v) {
        case "Array":
            out := []
            for e in v
                out.Push(JsonBoolize(e))
            return out
        case "Map":
            out := Map()
            for k, e in v
                out[k] := JsonBoolize(e)
            return out
        case "Object":
            out := {}
            for k, e in v.OwnProps()
                out.%k% := JsonBoolize(e)
            return out
    }
    return (v = "true") ? JSON.true : (v = "false") ? JSON.false : v
}
Fail(msg, code := "E_FAIL") {
    if (JsonMode)
        Out(JsonOut(Map("ok", "false", "code", code, "msg", msg)))
    else
        Out("❌ " msg)
    ExitApp(1)
}
Usage() {
    if (JsonMode) {
        Out(JsonOut(Map("ok", "false", "code", "E_USAGE", "msg", "未知命令或用法错误，--help 看全部命令")))
        ExitApp(3)
    }
    Out(AppInfo.name "CLI v" AppInfo.version " - 智能体用无界面执行器")
    Out("")
    Out("用法: kuangzi <命令> [参数] [--json]")
    Out("")
    Out("命令:")
    Out("  note <文本>        速记（写入今日日记，多行保留）")
    Out("  todo <文本>        待办（写入今日日记，多行保留）")
    Out("  note/todo          无文本=查询态：按日期查该节内容（--date / --scope local）")
    Out("  daily [--date D]   每日聚合：一次返回该日期速记+待办（默认今天/全部范围）")
    Out("  archive [--week|--month] [--go]  归档：跨设备合并上周期及以前的日记进归档区（默认按月，缺省 dry-run，--go 才执行）")
    Out("  note/todo -        从 stdin 读文本（多行/特殊字符首选，不碰剪贴板）")
    Out("  clip [note|todo]   剪贴板内容提交（默认note；兼容通道，stdin 更优）")
    Out("  go <内容>          智能路由（继承语义: @词启动 / -待办 / /引擎搜索）")
    Out("  search <词|查询>   搜索：'search 天气'=默认引擎；'search 百度 天气'=指定引擎（智能体首选，无前缀歧义）")
    Out("  open <词|路径|URL> 快捷启动关键词或直接路径/网址")
    Out("  attach <文件路径>  附件归档：复制到附件目录（图片/视频/音频/文档）+追加引用到今日日记")
    Out("  done <关键词>      完成待办：全库扫描匹配的未完成项，翻转为 [x]")
    Out("  todos [--days N] [--open|--done] [--scope S]  查询待办（默认不限时间/全部范围）")
    Out("  tag <标签>         查含指定标签的行（#前须空白；精确匹配）")
    Out("  tags               标签地图：范围内所有标签+次数")
    Out("  find <关键词>      全文行检索（子串匹配不区分大小写；自定义区/历史手写全靠它）")
    Out("  查询默认全量：全部分区+不限时间，收窄才带 --scope / --days")
    Out("  path [today|dir|config]  路径查询；path add/remove/rename/list 管理个人直达挂载")
    Out("  engine [list|add|remove|rename]  搜索引擎表管理（词 → URL 模板；add 的 URL 用 %s 占位搜索词）")
    Out("  word [list|add|remove|rename]    快捷启动词表管理（词 → 程序/路径/网址/动作 id）")
    Out("  send <按键串>      模拟按键（AHK Send 语法，如 #v 剪贴板历史、#l 锁屏）")
    Out("  today              打开今日日记")
    Out("  dir                打开笔记目录")
    Out("  new <文件名>       新建笔记（可省略.md后缀，创建并打开）")
    Out("")
    Out("全局: --json 机器可读输出（智能体调用建议始终带上）")
    Out("查找区: --scope local本机 / devices全部多设备 / archive归档 / all全部 / vault整库递归 / <多设备目录名>")
    Out("退出码: 0成功 / 1失败 / 2多候选 / 3用法错误（契约，永久不变）")
    ExitApp(3)
}

EmitResult(res) {
    path := ""
    if (res.ok && (res.action = "note" || res.action = "todo" || res.action = "image"))
        path := CliTodayPath()
    if (res.ok) {
        if (res.pending) {
            if (JsonMode) {
                Out(JsonOut(Map("ok", "false", "code", "E_MULTI", "msg", "多候选：该关键词命中多个快捷启动，请换精确词")))
                ExitApp(2)
            }
            Out("❌ 多候选：该关键词命中多个快捷启动，请换精确词")
            ExitApp(2)
        }
        if (JsonMode) {
            o := Map("ok", "true", "action", res.action)
            if (path != "")
                o["path"] := path
            if (res.text != "")
                o["text"] := res.text
            if (res.msg != "")
                o["msg"] := res.msg
            if (res.action = "plugin" && res.HasOwnProp("intent") && res.intent != "notify")
                o["intent"] := res.intent
            Out(JsonOut(o))
        } else {
            Out("✅ " CliActionLabel(res.action))
        }
        if (res.action = "plugin" && res.HasOwnProp("intent")) {
            try
                CliApplyIntent(res)
            catch as e {
                if (!JsonMode)
                    Out("⚠️ 插件副作用未完成：" e.Message)
            }
        }
        ExitApp(0)
    }
    eCode := res.code != "" ? res.code : (res.silent ? "E_SILENT" : "E_FAIL")
    if (JsonMode)
        Out(JsonOut(Map("ok", "false", "code", eCode, "msg", res.msg)))
    else
        Out("❌ " res.msg)
    ExitApp(1)
}
CliActionLabel(action) {
    switch action {
        case "note":  return "已写入速记 → " CliTodayPath()
        case "todo":  return "已写入待办 → " CliTodayPath()
        case "image": return "已写入速记(含图) → " CliTodayPath()
        case "launch": return "已启动目标"
        case "search": return "已在浏览器打开搜索"
        case "ai":     return "已打开AI页面"
        case "fy":     return "已打开翻译页面"
        case "open":   return "已打开"
        case "newnote": return "已新建笔记"
        case "empty":  return "空输入已忽略"
        default:       return "完成(" action ")"
    }
}
CliTodayPath() {
    p := QuickNote.EnsureNoteFile(FormatTime(, ConfigManager.Get("DateFormat")))
    return (p = "") ? "今日日记" : p
}

CheckInstalled() {
    cfg := AppPaths.ConfigFile()
    if (!FileExist(cfg)) {
        Out("❌ 框子未安装：找不到配置文件 " cfg)
        Out("   请先安装 GUI 版（首次运行会完成配置初始化），安装说明见仓库 skills/kuangzi-cli/SKILL.md")
        ExitApp(1)
    }
    try {
        ConfigManager.Init()
    } catch as e {
        Out("❌ 配置不可用：" e.Message)
        ExitApp(1)
    }
}

ReadStdinAll() {
    s := ""
    try {
        f := FileOpen("*", "r", "UTF-8")
        if (f) {
            s := f.Read()
            f.Close()
        }
    } catch {
        s := ""
    }
    while (SubStr(s, 1, 1) = Chr(0xFEFF))
        s := SubStr(s, 2)
    return s
}

CliWaitPluginDone() {
    deadline := A_TickCount + PluginManager.TASK_TIMEOUT_MS + 2000
    lastResult := ""
    while (A_TickCount < deadline) {
        anyPending := false
        for _, t in PluginManager.TasksByRequestId {
            if (t.state = PluginManager.TASK_PENDING) {
                anyPending := true
                break
            }
            lastResult := t.result
        }
        if (!anyPending) {
            if (lastResult = "" && PluginManager._cliLastResult != "")
                lastResult := PluginManager._cliLastResult
            return (lastResult != "") ? lastResult : Utils.ResErr("插件任务无结果", "plugin", false, "ERR_PLUGIN_FAIL")
        }
        Sleep 100
        PluginManager._PollTick()
    }
    PluginManager.CancelAll()
    return Utils.ResErr("插件执行超时", "plugin", false, "ERR_PLUGIN_TIMEOUT")
}
CliInstallPluginCallback() {
    PluginManager._cliLastResult := ""
    PluginManager.OnTaskDone := (t) => (PluginManager._cliLastResult := t.result)
    PluginManager.HostContext := (want) => CliHostContext(want)
}

CliApplyIntent(res) {
    intent := (res.HasOwnProp("intent") && res.intent != "notify") ? res.intent : "notify"
    if (intent != "notify" && res.text = "")
        intent := "notify"
    switch intent {
        case "fill":
            return
        case "copy":
            A_Clipboard := res.text
            CliIntentNote("已复制到剪贴板")
            return
        case "todo":
            r := QuickNote.Submit(res.text, true, "plugin")
            if (!r.ok)
                Out("❌ 记待办失败：" r.msg)
            else
                CliIntentNote("已记待办 → " CliTodayPath())
            return
    }
}
CliIntentNote(msg) {
    if (!JsonMode)
        Out("ℹ️ " msg)
}

CliHostContext(want) {
    hc := Map()
    try {
        MonitorGet(1, &mL, &mT, &mR, &mB)
        hc["screen"] := Map("w", mR - mL, "h", mB - mT, "scale", 1)
    } catch {
    }
    if (want.Has("read:focused-window")) {
        fw := WinExist("A")
        if (fw) {
            title := "", exe := ""
            try title := WinGetTitle("ahk_id " fw)
            try exe := WinGetProcessName("ahk_id " fw)
            hc["focused"] := Map("title", title, "exe", exe)
        }
    }
    if (want.Has("read:clipboard")) {
        clip := Map("text", "", "hasImage", false, "truncated", false)
        try {
            t := A_Clipboard
            if (StrLen(t) > 4096) {
                t := SubStr(t, 1, 4096)
                clip["truncated"] := true
            }
            clip["text"] := t
        } catch {
        }
        hc["clipboard"] := clip
    }
    return hc
}
