#Requires AutoHotkey v2.0
#Include "Utils.ahk"
#Include "ConfigManager.ahk"
#Include "QuickNote.ahk"
#Include "NotifyCenter.ahk"
#Include "Actions.ahk"
#Include "PluginManager.ahk"
#Include "Lexicon.ahk"

class Router {
    static Source := "route"
    static Route(text, mode := "submit", imgs := [], files := []) {
        ConfigManager.EnsureLoaded()
        InputText := Trim(text)
        if (InputText = "" && imgs.Length + files.Length = 0)
            return Utils.ResOk("empty")
        if (mode != "submit") {
            res := Actions.Run(mode, { text: InputText, images: imgs, files: files })
            if (res != "")
                return res
            return Utils.ResErr("未知动作: " mode, "", false)
        }
        return Actions.Run("submit", { text: InputText, images: imgs, files: files })
    }

    static SmartSubmit(InputText, imgs := [], files := []) {
        if (imgs.Length + files.Length > 0) {
            res := QuickNote.Submit(InputText, false, this.Source, imgs, files)
            if (res.ok)
                res.action := "image"
            return res
        }

        c1 := SubStr(InputText, 1, 1)
        if (c1 = "-") {
            TodoText := Trim(SubStr(InputText, 2))
            if (TodoText = "")
                return Utils.ResErr("", "todo", true)
            return Actions.Run("todo", { text: TodoText, source: this.Source })
        }

        AppPrefix := ConfigManager.Get("AppPrefix")
        if (AppPrefix != "" && SubStr(InputText, 1, StrLen(AppPrefix)) = AppPrefix) {
            AppCmd := Trim(SubStr(InputText, StrLen(AppPrefix) + 1))
            return Actions.Run("launch", { text: AppCmd, param: "none" })
        }

        PluginPrefix := ConfigManager.Get("PluginPrefix", "$")
        HasPluginPrefix := (PluginPrefix != "" && SubStr(InputText, 1, StrLen(PluginPrefix)) = PluginPrefix)
        if (HasPluginPrefix || c1 = "￥") {
            Body := Trim(SubStr(InputText, HasPluginPrefix ? StrLen(PluginPrefix) + 1 : 2))
            if (Body = "")
                return Utils.ResErr("", "plugin", true)
            SpacePos := InStr(Body, " ")
            Kw := (SpacePos) ? Trim(SubStr(Body, 1, SpacePos - 1)) : Body
            rest := (SpacePos) ? Trim(SubStr(Body, SpacePos + 1)) : ""
            gid := PluginManager.LookupKeyword(Kw)
            if (gid = "")
                return Utils.ResErr("未找到插件词：" Kw, "plugin", false, "ERR_PLUGIN_KW")
            return PluginManager.InvokeByDecision(gid, rest, this.Source, Kw)
        }

        Prefix := ConfigManager.Get("SearchPrefix")
        if (Prefix != "" && SubStr(InputText, 1, StrLen(Prefix)) = Prefix) {
            SBody := Trim(SubStr(InputText, StrLen(Prefix) + 1))
            if (SBody = "")
                return Utils.ResErr("", "search", true)
            return Lexicon.ResolveSearchBody(SBody)
        }

        res := Lexicon.Resolve(InputText, this.Source)
        if (IsObject(res))
            return res

        fb := ConfigManager.Get("ConfirmFallback")
        a := Actions.Get(fb)
        if (a = "" || a.kind = "entry")
            fb := "note"
        res := Actions.Run(fb, { text: InputText, source: this.Source, images: imgs, files: files })
        return (res != "") ? res : QuickNote.Submit(InputText, false, this.Source, imgs, files)
    }
}

Actions.RegisterRoute("submit", "智能提交路由", "⏎", (c) => Router.SmartSubmit(c.text, c.images, c.files))
