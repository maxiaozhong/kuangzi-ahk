#Requires AutoHotkey v2.0
#Include "Utils.ahk"
#Include "ConfigManager.ahk"
#Include "PathCatalog.ahk"
#Include "QuickNote.ahk"
#Include "NotifyCenter.ahk"
#Include "ActionBindings.ahk"

class Actions {
    static _pluginReg := Map()
    static _wordReg := Map()
    static _routeReg := Map()
    static RegisterRoute(id, label, icon, runFn, display := 0) {
        e := { id: id, label: label, icon: icon
            , kind: "entry", textAction: false, cat: "route", run: runFn }
        if (IsObject(display))
            e.display := display
        this._routeReg[id] := e
    }
    static ROUTES() {
        out := []
        for _, a in this._routeReg
            out.Push(a)
        return out
    }

    static PLUGINS() {
        out := []
        for _, a in this._pluginReg
            out.Push(a)
        return out
    }

    static WORDS() {
        out := []
        for _, a in this._wordReg
            out.Push(a)
        return out
    }

    static _DeriveEntry(prefix, word, e, fromProjection) {
        gid := prefix word
        t := (Type(e) = "String") ? "run" : (e.HasOwnProp("type") ? e.type : "run")
        ta := false
        if (t = "search")
            ta := true
        else if (t = "action") {
            tgt := (Type(e) = "Object" && e.HasOwnProp("target")) ? e.target : ""
            a2 := this.Get(tgt)
            ta := (a2 != "" && a2.HasOwnProp("textAction") && a2.textAction)
        }
        entry := { id: gid, label: word
            , icon: (Type(e) = "Object" && e.HasOwnProp("icon")) ? e.icon : ""
            , kind: "action", textAction: ta
            , cat: (Type(e) = "Object" && e.HasOwnProp("cat")) ? e.cat : ((prefix = "eng.") ? "search" : "launch")
            , run: ActionBindings_RunWord.Bind(gid) }
        if (Type(e) = "Object" && e.HasOwnProp("display"))
            entry.display := e.display
        if (fromProjection)
            entry.srcEntry := e
        if (t = "search" && Type(e) = "Object" && e.HasOwnProp("home"))
            entry.allowEmpty := true
        return entry
    }

    static CONTENT := [
        { id: "launch",   label: "启动目标", icon: "🚀", kind: "action", textAction: false, cat: "launch", display: { toolbar: true, quickKey: false, any: false }, run: (c) => ActionBindings._RunLaunch(c) },
        { id: "search",   label: "默认搜索", icon: "🔍", kind: "action", textAction: true,  cat: "search", engineCfg: "SearchEngine", display: { toolbar: true, fallback: true }, run: (c) => ActionBindings._RunSearch(c) },
        { id: "todo",     label: "待办", icon: "✅", kind: "action", textAction: true,  cat: "note",   display: { toolbar: true, fallback: true }, run: (c) => QuickNote.Submit(Trim(c.text), true, c.source, c.images, c.files) },
        { id: "note",     label: "速记", icon: "✏", kind: "action", textAction: true,  cat: "note",   display: { toolbar: true, fallback: true }, run: (c) => QuickNote.Submit(Trim(c.text), false, c.source, c.images, c.files) },
        { id: "openNote", label: "打开日记", icon: "📖", kind: "action", textAction: false, cat: "note", display: { toolbar: true, tray: true, contextMenu: true }, run: (c) => QuickNote.OpenTodayNote() },
        { id: "openDir",  label: "打开目录", icon: "📁", kind: "action", textAction: false, cat: "note",   display: { toolbar: true, tray: true, contextMenu: true }, run: (c) => QuickNote.OpenNoteFolder() },
        { id: "send",     label: "模拟按键", icon: "⌨",  kind: "action", textAction: false, cat: "window", display: { quickKey: false, any: false }, run: (c) => (Utils.SendKeys(c.param), Utils.ResOk("send")) },
        { id: "bookmark", label: "打开书签", icon: "🔖", kind: "action", textAction: true, cat: "launch",  display: { toolbar: true }, run: (c) => ActionBindings._RunDomain(c.text, "bookmark", "书签") },
        { id: "localapp", label: "打开应用", icon: "💽", kind: "action", textAction: true, cat: "launch",  display: { toolbar: true }, run: (c) => ActionBindings._RunDomain(c.text, "localapp", "应用") },
        { id: "path",     label: "打开路径", icon: "📂", kind: "action", textAction: true, allowEmpty: true, cat: "launch", display: { toolbar: true }, run: (c) => ActionBindings._RunPath(c) },
        { id: "none",     label: "不处理",   icon: "🚫", kind: "action", textAction: true,  cat: "window", display: { textTargets: false, slots: false, fallback: true }, run: (c) => (NotifyCenter.Send("info", "未命中", "未匹配任何词表/引擎，已按无兜底处理（内容未写入）"), Utils.ResOk("none")) }
    ]

    static COMMANDS := [
            { id: "add",        label: "添加快捷启动",   icon: "➕", kind: "command", cat: "window", display: { tray: true, quickKey: false }, run: (c) => (c.host.ShowQuickAppDialog(),  Utils.ResOk("")) },
            { id: "newNote",    label: "新建笔记",       icon: "📝", kind: "command", cat: "note",   display: { toolbar: true, tray: true }, run: (c) => (c.host.NewNote(),              Utils.ResOk("")) },
            { id: "settings",   label: "设置",           icon: "⚙", kind: "command", cat: "window", display: { toolbar: true, tray: true, contextMenu: true, quickKey: false }, run: (c) => (c.host.ShowSettings(),         Utils.ResOk("")) },
            { id: "hide",       label: "隐藏",           icon: "✕", kind: "command", cat: "window", display: { toolbar: true, contextMenu: true, quickKey: false }, run: (c) => (c.host.HideAndSavePos(),       Utils.ResOk("")) },
            { id: "mode",       label: "切换输入框模式", icon: "⚡", kind: "command", cat: "window", display: { tray: true, contextMenu: true, quickKey: false }, run: (c) => (c.host.CycleMode(),            Utils.ResOk("")) },
            { id: "voice",      label: "语音输入",       icon: Chr(0xE720), kind: "command", cat: "window", display: { slots: true }, run: (c) => (c.host.VoiceInput(),           Utils.ResOk("")) },
            { id: "toggleMain", label: "显示/隐藏输入框", icon: "👁", kind: "command", cat: "window", display: { tray: true }, run: (c) => (c.host.ToggleMainGui(),        Utils.ResOk("")) },
            { id: "quit",       label: "退出",           icon: "🚪", kind: "command", cat: "window", display: { tray: true, quickKey: false }, run: (c) => (c.host.Quit(),                 Utils.ResOk("")) },
            { id: "history",    label: "通知历史",       icon: "🔔", kind: "command", cat: "window", display: { tray: true, quickKey: false }, run: (c) => (NotifyCenter.ShowHistory(),    Utils.ResOk("")) },
            { id: "alwaysShow", label: "常驻",           icon: "📌", kind: "command", cat: "window", display: { toolbar: true, tray: true, quickKey: false }, run: (c) => (c.host.ToggleAlwaysShow(),     Utils.ResOk("")) }
        ]
    static All() {
        out := []
        for a in this.ROUTES()
            out.Push(a)
        for a in this.CONTENT
            out.Push(a)
        for a in this.COMMANDS
            out.Push(a)
        for a in this.PLUGINS()
            out.Push(a)
        for a in this.WORDS()
            out.Push(a)
        return out
    }

    static SplitId(id) {
        if (SubStr(id, 1, 7) = "plugin.") {
            rest := SubStr(id, 8)
            dot := InStr(rest, ".")
            if (dot = 0)
                return { ns: "plugin", owner: rest, name: "" }
            return { ns: "plugin", owner: SubStr(rest, 1, dot - 1), name: SubStr(rest, dot + 1) }
        }
        if (SubStr(id, 1, 5) = "word.")
            return { ns: "word", owner: "", name: SubStr(id, 6) }
        if (SubStr(id, 1, 4) = "eng.")
            return { ns: "eng", owner: "", name: SubStr(id, 5) }
        return { ns: "", owner: "", name: id }
    }

    static Get(id) {
        for a in this.All() {
            if (a.id = id)
                return a
        }
        s := this.SplitId(id)
        if (s.ns = "word" && ConfigManager.WordMap.Has(s.name))
            return this._DeriveEntry("word.", s.name, ConfigManager.WordMap[s.name], false)
        if (s.ns = "eng" && ConfigManager.EngineMap.Has(s.name))
            return this._DeriveEntry("eng.", s.name, ConfigManager.EngineMap[s.name], false)
        return ""
    }

    static Run(id, ctx) {
        a := this.Get(id)
        if (a = "")
            return ""
        if !ctx.HasOwnProp("text")
            ctx.text := ""
        if !ctx.HasOwnProp("param")
            ctx.param := ""
        if !ctx.HasOwnProp("host")
            ctx.host := 0
        if !ctx.HasOwnProp("source")
            ctx.source := "action"
        if !ctx.HasOwnProp("images")
            ctx.images := []
        if !ctx.HasOwnProp("files")
            ctx.files := []
        if (a.kind = "command" && ctx.host = 0)
            return Utils.ResErr("「" a.label "」需要宿主界面，无壳环境不支持（CLI 请用对应命令，如 kuangzi new）", a.id, false, "ERR_NO_HOST")
        if (a.HasOwnProp("textAction") && a.textAction && Trim(ctx.text) = "" && ctx.images.Length + ctx.files.Length = 0) {
            if (a.HasOwnProp("allowEmpty") && a.allowEmpty)
                return a.run.Call(ctx)
            if (a.HasOwnProp("engineCfg") && ActionBindings._EngineHasHome(a.engineCfg, ctx.param))
                return a.run.Call(ctx)
            return Utils.ResOk("empty")
        }
        return a.run.Call(ctx)
    }
}
