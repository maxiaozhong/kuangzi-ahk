#Requires AutoHotkey v2.0
#Include "Utils.ahk"
#Include "ConfigManager.ahk"
#Include "PathCatalog.ahk"
#Include "QuickNote.ahk"
#Include "QuickLaunch.ahk"
#Include "QuickSearch.ahk"
#Include "NotifyCenter.ahk"
#Include "CatalogHub.ahk"
#Include "PluginManager.ahk"
#Include "Actions.ahk"

class ActionBindings {
    static _coreRegistered := false

    static RegisterCore() {
        if (ActionBindings._coreRegistered)
            return
        ActionBindings._coreRegistered := true
        ConfigManager.OnCachesRebuilt := ActionBindings.RebuildWordActions.Bind(ActionBindings)
    }

    static RebuildPluginActions() {
        Actions._pluginReg := Map()
        for a in PluginManager.PluginActions() {
            e := { id: a.id
                , label: PluginManager.ActionLabel(a), icon: a.icon
                , kind: "action", textAction: a.textAction, cat: "plugin"
                , plugin: true, allowEmpty: a.allowEmpty, supportsGui: a.supportsGui
                , run: ActionBindings_RunPlugin.Bind(a.id) }
            if (ActionBindings._HasAnyDisplay(a))
                e.display := a.display
            Actions._pluginReg[a.id] := e
        }
    }

    static RebuildWordActions(*) {
        Actions._wordReg := Map()
        ActionBindings._ProjectWords("word.", ConfigManager.WordMap, "launch")
        ActionBindings._ProjectWords("eng.", ConfigManager.EngineMap, "search")
    }

    static _ProjectWords(prefix, m, defCat := "") {
        for word, e in m {
            gid := prefix word
            if (Actions._wordReg.Has(gid))
                continue
            dup := false
            for _, pe in Actions._wordReg {
                if (pe.HasOwnProp("srcEntry") && pe.srcEntry = e) {
                    dup := true
                    break
                }
            }
            if (dup)
                continue
            entry := Actions._DeriveEntry(prefix, word, e, true)
            Actions._wordReg[gid] := entry
        }
    }

    static _HasAnyDisplay(e) {
        for _, v in e.display.OwnProps() {
            if (v)
                return true
        }
        return false
    }

    static _RunSearch(c) {
        r := ActionBindings._ResolveEngine("SearchEngine", c.param)
        if (r.fallback)
            ActionBindings._NotifyEngineFallback()
        return QuickSearch.ExecuteEntry(r.entry, Trim(c.text), "search")
    }

    static _ResolveEngine(cfgKey, param := "") {
        word := (param != "") ? param : ConfigManager.Get(cfgKey)
        if (word != "" && ConfigManager.EngineMap.Has(word))
            return { word: word, entry: ConfigManager.EngineMap[word], fallback: false }
        return { word: "百度", entry: ActionBindings.FALLBACK_ENGINE, fallback: true }
    }

    static FALLBACK_ENGINE := { type: "search"
        , target: "https://www.baidu.com/s?wd=%s"
        , home: "https://www.baidu.com"
        , desc: "内置默认搜索（配置引擎失效时兜底）" }

    static _EngineHasHome(cfgKey, param) {
        r := ActionBindings._ResolveEngine(cfgKey, param)
        return (r.entry.HasOwnProp("home") && r.entry.home != "")
    }

    static _fallbackNoticed := false
    static _NotifyEngineFallback() {
        if (ActionBindings._fallbackNoticed)
            return
        ActionBindings._fallbackNoticed := true
        NotifyCenter.Send("info", "默认搜索", "配置的搜索引擎已失效，本次使用默认搜索打开，请重新设置您喜欢的搜索引擎")
    }

    static _RunLaunch(c) {
        res := QuickLaunch.Execute(Trim(c.text))
        if (res.ok || res.pending)
            return res
        target := CatalogHub.Lookup(Trim(c.text))
        if (IsObject(target)) {
            QuickLaunch.ShowAppPicker(target)
            return Utils.ResPending("launch")
        }
        if (target != "")
            return QuickLaunch.RunTarget(target)
        if (c.param = "")
            return res
        fb := Actions.Get(c.param)
        if (fb = "" || fb.kind = "entry")
            return res
        return fb.run.Call({ text: c.text, param: "", host: c.host })
    }

    static _RunPath(c) {
        if (Trim(c.text) = "") {
            dir := PathCatalog.PathDir()
            if !DirExist(dir)
                DirCreate(dir)
            return QuickLaunch.RunTarget(dir)
        }
        return CatalogHub.RunDomain(c.text, PathCatalog, "path")
    }

    static _RunDomain(text, domain, label) {
        switch domain {
            case "bookmark":
                return CatalogHub.RunDomain(text, BookmarkCatalog, label)
            case "localapp":
                return CatalogHub.RunDomain(text, LocalAppCatalog, label)
        }
        return Utils.ResErr("未知域：" domain, "launch", false, "ERR_NO_APP")
    }
}

ActionBindings_RunPlugin(gid, c) {
    return PluginManager.InvokeByDecision(gid, c.text, c.source)
}

ActionBindings_RunWord(gid, c) {
    s := Actions.SplitId(gid)
    m := (s.ns = "eng") ? ConfigManager.EngineMap : ConfigManager.WordMap
    if (!m.Has(s.name))
        return Utils.ResErr(s.name, "launch", false, "ERR_NO_APP")
    return EntryExecutor.Execute(m[s.name], s.name, c.text)
}
