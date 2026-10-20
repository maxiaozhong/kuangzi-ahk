#Requires AutoHotkey v2.0
#Include "ConfigManager.ahk"
#Include "QuickLaunch.ahk"
#Include "NotifyCenter.ahk"

class QuickAppDialog {
    host := 0
    QuickAppGui := ""
    BatchAppGui := ""
    QuickSearchGui := ""

    __New(host) {
        this.host := host
    }

    GetTopmostGuis() {
        out := []
        if (this.QuickAppGui)
            out.Push(this.QuickAppGui)
        if (this.BatchAppGui)
            out.Push(this.BatchAppGui)
        if (this.QuickSearchGui)
            out.Push(this.QuickSearchGui)
        return out
    }

    _SaveTable(cfgKey, pairs, rebuildFn, syncFn) {
        for p in pairs
            ConfigManager.Config[cfgKey][p[1]] := p[2]
        rebuildFn.Call()
        ConfigManager.Save()
        syncFn.Call()
    }

    ShowQuickAppDialog(*) {
        if (this.QuickAppGui) {
            this.QuickAppGui.Show()
            return
        }

        this.QuickAppGui := Gui("-MinimizeBox -MaximizeBox +AlwaysOnTop", "添加快捷启动")
        this.QuickAppGui.SetFont("s9", "Microsoft YaHei")
        this.QuickAppGui.OnEvent("Close", (*) => (this.QuickAppGui.Hide(), this.QuickAppGui := ""))

        this.QuickAppGui.Add("Text", "x15 y15 w60", "关键词:")
        kwEdit := this.QuickAppGui.Add("Edit", "x85 y12 w220 vKeyword")
        this.QuickAppGui.Add("Text", "x15 y50 w60", "地址:")
        pathEdit := this.QuickAppGui.Add("Edit", "x85 y47 w220 vPath")
        this.QuickAppGui.Add("Text", "x15 y80 w290 c9CA3AF", "支持变量：A_UserProfile、A_Desktop、A_MyDocuments、`nA_AppData、A_Temp（可加后缀，如 A_UserProfile\Downloads）")

        okBtn := this.QuickAppGui.Add("Button", "x85 y118 w100 h28 Default", "确认")
        cancelBtn := this.QuickAppGui.Add("Button", "x195 y118 w100 h28", "取消")

        okBtn.OnEvent("Click", ObjBindMethod(this, "SaveQuickApp", kwEdit, pathEdit))
        cancelBtn.OnEvent("Click", (*) => (this.QuickAppGui.Hide(), this.QuickAppGui := ""))

        this.QuickAppGui.Show("w320 h162")
        kwEdit.Focus()
    }

    SaveQuickApp(kwEdit, pathEdit, *) {
        keyword := Trim(kwEdit.Value)
        path := Trim(pathEdit.Value)

        if (keyword = "") {
            this.host.TopMsgBox("关键词不能为空", "提示", 48)
            kwEdit.Focus()
            return
        }
        if (path = "") {
            this.host.TopMsgBox("地址不能为空", "提示", 48)
            pathEdit.Focus()
            return
        }

        keyword := QuickLaunch.GetUniqueKeyword(keyword)

        this._SaveTable("WordTable", [[keyword, path]],
            () => ConfigManager.RebuildWordCache(), () => this.host.SyncAppShortcuts())

        this.QuickAppGui.Hide()
        this.QuickAppGui := ""
        NotifyCenter.Send("info", "快捷启动已添加", keyword)
    }

    ShowBatchAppDialog(*) {
        if (this.BatchAppGui) {
            this.BatchAppGui.Show()
            return
        }

        this.BatchAppGui := Gui("-MinimizeBox -MaximizeBox +AlwaysOnTop", "批量添加快捷启动")
        this.BatchAppGui.SetFont("s9", "Microsoft YaHei")
        this.BatchAppGui.OnEvent("Close", (*) => (this.BatchAppGui.Hide(), this.BatchAppGui := ""))

        this.BatchAppGui.Add("Text", "x15 y12 w450", "每行一条: 关键词=路径（词=目标 即语法糖），重复关键词自动加序号:")
        batchEdit := this.BatchAppGui.Add("Edit", "x15 y35 w450 h220 vBatchText Multi WantReturn")

        okBtn := this.BatchAppGui.Add("Button", "x135 y270 w100 h28 Default", "确认")
        cancelBtn := this.BatchAppGui.Add("Button", "x245 y270 w100 h28", "取消")

        okBtn.OnEvent("Click", ObjBindMethod(this, "SaveBatchApps", batchEdit))
        cancelBtn.OnEvent("Click", (*) => (this.BatchAppGui.Hide(), this.BatchAppGui := ""))

        this.BatchAppGui.Show("w480 h310")
        batchEdit.Focus()
    }

    SaveBatchApps(batchEdit, *) {
        text := batchEdit.Value
        if (Trim(text) = "") {
            this.host.TopMsgBox("内容不能为空", "提示", 48)
            batchEdit.Focus()
            return
        }

        pairs := []
        errLines := []

        for line in StrSplit(text, "`n", "`r") {
            line := Trim(line)
            if (line = "")
                continue

            pos := InStr(line, "=")
            if (!pos) {
                errLines.Push(line)
                continue
            }
            keyword := Trim(SubStr(line, 1, pos - 1))
            path := Trim(SubStr(line, pos + 1))
            if (keyword = "" || path = "") {
                errLines.Push(line)
                continue
            }

            pairs.Push([QuickLaunch.GetUniqueKeyword(keyword), path])
        }

        if (pairs.Length = 0) {
            this.host.TopMsgBox("没有可导入的有效条目`n每行格式: 关键词=路径", "提示", 48)
            return
        }

        this._SaveTable("WordTable", pairs,
            () => ConfigManager.RebuildWordCache(), () => this.host.SyncAppShortcuts())

        this.BatchAppGui.Hide()
        this.BatchAppGui := ""

        if (errLines.Length > 0) {
            detail := ""
            for l in errLines
                detail .= (detail ? "`n" : "") l
            this.host.TopMsgBox("以下 " errLines.Length " 行格式错误已跳过：`n`n" detail, "批量添加 - 部分跳过", 48)
        }
        NotifyCenter.Send("info", "批量添加完成", "成功 " pairs.Length " 条" (errLines.Length ? "，跳过 " errLines.Length " 条" : ""))
    }

    ShowQuickSearchDialog(*) {
        if (this.QuickSearchGui) {
            this.QuickSearchGui.Show()
            return
        }

        this.QuickSearchGui := Gui("-MinimizeBox -MaximizeBox +AlwaysOnTop", "添加搜索引擎")
        this.QuickSearchGui.SetFont("s9", "Microsoft YaHei")
        this.QuickSearchGui.OnEvent("Close", (*) => (this.QuickSearchGui.Hide(), this.QuickSearchGui := ""))

        this.QuickSearchGui.Add("Text", "x15 y15 w60", "快捷词:")
        kwEdit := this.QuickSearchGui.Add("Edit", "x85 y12 w220 vKeyword")
        this.QuickSearchGui.Add("Text", "x15 y50 w60", "URL:")
        urlEdit := this.QuickSearchGui.Add("Edit", "x85 y47 w220 vUrl")
        this.QuickSearchGui.Add("Text", "x15 y80 w290 c9CA3AF", "用 %s 代表搜索词，如 https://www.google.com/search?q=%s")

        okBtn := this.QuickSearchGui.Add("Button", "x85 y110 w100 h28 Default", "确认")
        cancelBtn := this.QuickSearchGui.Add("Button", "x195 y110 w100 h28", "取消")

        okBtn.OnEvent("Click", ObjBindMethod(this, "SaveQuickSearch", kwEdit, urlEdit))
        cancelBtn.OnEvent("Click", (*) => (this.QuickSearchGui.Hide(), this.QuickSearchGui := ""))

        this.QuickSearchGui.Show("w320 h150")
        kwEdit.Focus()
    }

    SaveQuickSearch(kwEdit, urlEdit, *) {
        keyword := Trim(kwEdit.Value)
        url := Trim(urlEdit.Value)

        if (keyword = "") {
            this.host.TopMsgBox("快捷词不能为空", "提示", 48)
            kwEdit.Focus()
            return
        }
        if (url = "") {
            this.host.TopMsgBox("URL 不能为空", "提示", 48)
            urlEdit.Focus()
            return
        }
        if (!InStr(url, "%s")) {
            this.host.TopMsgBox("URL 必须含 %s（搜索词占位）", "提示", 48)
            urlEdit.Focus()
            return
        }

        this._SaveTable("SearchEngines", [[keyword, { type: "search", target: url }]],
            () => ConfigManager.RebuildEngineCache(), () => this.host.SyncSearchEngines())

        this.QuickSearchGui.Hide()
        this.QuickSearchGui := ""
        NotifyCenter.Send("info", "搜索引擎已添加", keyword)
    }
}
