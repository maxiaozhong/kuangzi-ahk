#Requires AutoHotkey v2.0
#Include "ConfigManager.ahk"
#Include "NotifyCenter.ahk"
#Include "Actions.ahk"
#Include "ActionBindings.ahk"
#Include "PluginManager.ahk"

class Presentation {
    static Toolbar := "toolbar"
    static ToolbarPool := "toolbar"
    static TextTargets := "textTargets"
    static Fallback := "fallback"
    static Slots := "slots"
    static Tray := "tray"
    static ContextMenu := "contextMenu"
    static QuickKey := "quickKey"
    static Voice := "voice"
    static Global := "any"

    static POLARITY := Map(
        "toolbar", "white", "slots", "pred", "textTargets", "pred"
        , "fallback", "white", "tray", "white", "contextMenu", "white"
        , "voice", "black", "quickKey", "pred", "any", "pred")

    static _Polarity(domain) {
        return Presentation.POLARITY.Has(domain) ? Presentation.POLARITY[domain] : "white"
    }

    static _Declared(a, domain) {
        if (!a.HasOwnProp("display") || !a.display.HasOwnProp(domain))
            return ""
        return a.display.%domain%
    }

    static _Auto(a, domain) {
        p := Presentation._Polarity(domain)
        if (p = "pred") {
            if (domain = Presentation.Global)
                return Presentation._CanAnyHotkey(a)
            if (domain = Presentation.QuickKey)
                return Presentation._CanQuickKey(a)
            return Presentation._CanTextTarget(a, domain)
        }
        d := Presentation._Declared(a, domain)
        if (p = "black") {
            if (a.HasOwnProp("kind") && a.kind = "entry")
                return false
            return (Type(d) = "String") ? true : d
        }
        return (Type(d) = "String") ? false : d
    }

    static CanConsume(id, domain) {
        a := Actions.Get(id)
        if (a = "")
            return false
        return Presentation._Auto(a, domain)
    }

    static _CanQuickKey(a) {
        if (a.HasOwnProp("display") && a.display.HasOwnProp("quickKey")) {
            if (!a.display.quickKey)
                return false
            return true
        }
        if (a.HasOwnProp("plugin") && a.plugin)
            return false
        if (!a.HasOwnProp("textAction") || !a.textAction)
            return true
        if (a.HasOwnProp("allowEmpty") && a.allowEmpty)
            return true
        if (a.HasOwnProp("engineCfg") && ActionBindings._EngineHasHome(a.engineCfg, ""))
            return true
        return false
    }

    static _CanAnyHotkey(a) {
        if (a.HasOwnProp("display") && a.display.HasOwnProp("any"))
            return a.display.any ? true : false
        if (a.HasOwnProp("plugin") && a.plugin)
            return false
        if (a.HasOwnProp("kind") && a.kind = "entry")
            return false
        if (a.HasOwnProp("kind") && a.kind = "command")
            return true
        if (a.HasOwnProp("textAction") && a.textAction) {
            if (a.HasOwnProp("allowEmpty") && a.allowEmpty)
                return true
            return false
        }
        return true
    }

    static _CanTextTarget(a, domain) {
        if (a.HasOwnProp("display") && a.display.HasOwnProp(domain))
            return a.display.%domain% ? true : false
        if (a.HasOwnProp("plugin") && a.plugin)
            return false
        if (a.HasOwnProp("kind") && a.kind = "entry")
            return false
        return (a.HasOwnProp("textAction") && a.textAction) ? true : false
    }

    static For(domain) {
        out := []
        for a in Actions.All() {
            if (Presentation._Auto(a, domain))
                out.Push(a)
        }
        return out
    }

    static ToolbarShown() {
        pool := Map()
        for a in Presentation.For(Presentation.ToolbarPool)
            pool[a.id] := true
        out := []
        tools := ConfigManager.Get("InputBarTools", ConfigManager.GetDefaultInputBarTools())
        for name in tools {
            if (!pool.Has(name))
                continue
            a := Actions.Get(name)
            if (a != "")
                out.Push(a)
        }
        return out
    }

    static ActionLabel(id) {
        a := Actions.Get(id)
        if (a = "")
            return "🚫 " id
        s := Actions.SplitId(id)
        if (s.ns = "eng")
            return "搜索·" s.name
        if (s.ns = "word")
            return "目标·" s.name
        if (s.ns = "plugin" && s.name != "" && PluginManager.ActionsById.Has(id) && PluginManager.PluginsById.Has(s.owner))
            return PluginManager.PluginsById[s.owner].name "·" PluginManager.ActionsById[id].label
        return a.label
    }

    static _ActionOptions(domain, currentValue := "", skipEntry := false) {
        out := []
        found := false
        for a in Presentation.For(domain) {
            if (skipEntry && a.HasOwnProp("kind") && a.kind = "entry")
                continue
            out.Push({ label: Presentation.ActionLabel(a.id), value: a.id })
            if (a.id = currentValue)
                found := true
        }
        if (currentValue != "" && !found && Presentation.IsDanglingRef(currentValue))
            out.Push({ label: Presentation.ActionLabel(currentValue), value: currentValue })
        return out
    }

    static TextActionOptions(currentValue := "") => Presentation._ActionOptions(Presentation.TextTargets, currentValue)

    static SubmitFallbackOptions(currentValue := "") => Presentation._ActionOptions(Presentation.Fallback, currentValue, true)

    static HOTKEY_SOURCES := Map(
        "clip", "textTargets", "select", "textTargets"
        , "input", "slots", "any", "any")

    static RESERVED := [
        { id: "submit",  label: "提交" },
        { id: "newline", label: "换行" }
    ]

    static HotkeyDomainOptions(domKey, currentValue := "") {
        out := []
        if (domKey = "input") {
            for r in Presentation.RESERVED
                out.Push({ label: r.label, id: r.id })
        }
        src := Presentation.HOTKEY_SOURCES.Has(domKey) ? Presentation.HOTKEY_SOURCES[domKey] : domKey
        for o in Presentation._ActionOptions(src, currentValue)
            out.Push({ label: o.label, id: o.value })
        return out
    }

    static IsDanglingRef(id) {
        return Actions.SplitId(id).ns != ""
    }
}
